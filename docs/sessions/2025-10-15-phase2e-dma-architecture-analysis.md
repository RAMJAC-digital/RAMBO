# Phase 2E: DMA Architecture Analysis

**Date:** 2025-10-15
**Analyst:** Code Review Agent (zaza-enhanced-code-review)
**Status:** ANALYSIS COMPLETE - Ready for implementation decision

---

## Executive Summary

RAMBO's DMA implementation uses a **sequential priority model** where DMC DMA blocks OAM DMA completely. Hardware uses a **preemptive priority model** where DMC interrupts and resumes OAM with byte duplication. The fix requires adding pause/resume state to OAM DMA and refactoring the priority logic in `execution.zig`.

**Complexity Assessment:** HIGH (6-8 hours)
**Risk Level:** MEDIUM-HIGH (complex state machine, subtle timing interactions)
**Recommendation:** Incremental implementation with comprehensive testing at each step

---

## Current Call Order Analysis

### Location: `/home/colin/Development/RAMBO/src/emulation/cpu/execution.zig` (Lines 125-135)

```zig
// DMC DMA active - CPU stalled (RDY line low)
if (state.dmc_dma.rdy_low) {
    state.tickDmcDma();
    return .{};
}

// OAM DMA active - CPU frozen for 512 cycles
if (state.dma.active) {
    state.tickDma();
    return .{};
}
```

**Current Behavior:**
1. DMC DMA checked FIRST (higher priority) ✅
2. If DMC active, OAM completely blocked ❌ **WRONG**
3. If OAM active, normal CPU execution blocked ✅
4. No mechanism for DMC to interrupt running OAM ❌ **MISSING**

**Hardware Behavior (Correct):**
1. DMC DMA has ABSOLUTE priority
2. DMC can interrupt OAM mid-transfer
3. OAM pauses, DMC runs for 4 cycles
4. OAM resumes with BYTE DUPLICATION bug
5. Both can be active simultaneously (OAM paused, DMC running)

---

## State Structure Analysis

### OAM DMA State (`src/emulation/state/peripherals/OamDma.zig`)

```zig
pub const OamDma = struct {
    active: bool = false,           // DMA in progress
    source_page: u8 = 0,            // Page number ($4014 write value)
    current_offset: u8 = 0,         // Byte offset (0-255)
    current_cycle: u16 = 0,         // Transfer cycle counter
    needs_alignment: bool = false,  // Odd CPU cycle start
    temp_value: u8 = 0,             // Read/write staging byte
};
```

**What's Missing:**
- ❌ `paused: bool` - Track if DMC interrupted us
- ❌ `last_read_byte: u8` - For duplication bug on resume
- ❌ Cycle state tracking (read vs write phase)

**Current Cycle Tracking:**
- `current_cycle` counts 0..513 (even start) or 0..514 (odd start)
- Alignment handled via `needs_alignment` flag
- Read/write alternation via `current_cycle % 2`

### DMC DMA State (`src/emulation/state/peripherals/DmcDma.zig`)

```zig
pub const DmcDma = struct {
    rdy_low: bool = false,              // CPU stalled
    stall_cycles_remaining: u8 = 0,     // 0-4 cycles (3 idle + 1 fetch)
    sample_address: u16 = 0,            // Fetch address
    sample_byte: u8 = 0,                // Fetched sample
    last_read_address: u16 = 0,         // For corruption tracking
};
```

**Current State:** COMPLETE - No changes needed ✅
- Tracks RDY line assertion (CPU stall)
- 4-cycle stall duration (3 idle + 1 fetch)
- Corruption tracking via `last_read_address`

---

## Cycle Consumption Analysis

### OAM DMA Cycle Handling

**Entry Point:** `src/emulation/dma/logic.zig::tickOamDma()`

```zig
pub fn tickOamDma(state: anytype) void {
    const cycle = state.dma.current_cycle;
    state.dma.current_cycle += 1;

    // Alignment wait (if needed)
    if (state.dma.needs_alignment and cycle == 0) {
        return; // Consume 1 cycle, do nothing
    }

    // Calculate effective cycle
    const effective_cycle = if (state.dma.needs_alignment) cycle - 1 else cycle;

    // Check completion (512 cycles = 256 read/write pairs)
    if (effective_cycle >= 512) {
        state.dma.reset();
        return;
    }

    // Alternate read/write
    if (effective_cycle % 2 == 0) {
        // Even: Read from CPU RAM
        const addr = (@as(u16, state.dma.source_page) << 8) |
                     @as(u16, state.dma.current_offset);
        state.dma.temp_value = state.busRead(addr);
    } else {
        // Odd: Write to PPU OAM via $2004
        state.ppu.oam[state.ppu.oam_addr] = state.dma.temp_value;
        state.ppu.oam_addr +%= 1;
        state.dma.current_offset +%= 1;
    }
}
```

**Key Observations:**
- ✅ Consumes exactly 1 CPU cycle per call
- ✅ Read/write alternation via modulo
- ✅ Uses `temp_value` for staging (enables pause/resume)
- ⚠️ **No pause support** - assumes continuous execution
- ⚠️ **Cycle counter advances unconditionally** - won't work if paused

### DMC DMA Cycle Handling

**Entry Point:** `src/emulation/dma/logic.zig::tickDmcDma()`

```zig
pub fn tickDmcDma(state: anytype) void {
    const cycle = state.dmc_dma.stall_cycles_remaining;

    if (cycle == 0) {
        state.dmc_dma.rdy_low = false;
        return;
    }

    state.dmc_dma.stall_cycles_remaining -= 1;

    if (cycle == 1) {
        // Final cycle: Fetch sample
        const address = state.dmc_dma.sample_address;
        state.dmc_dma.sample_byte = state.busRead(address);
        ApuLogic.loadSampleByte(&state.apu, state.dmc_dma.sample_byte);
        state.dmc_dma.rdy_low = false;
    } else {
        // Idle cycles (1-3): CPU repeats last read (NTSC bug)
        if (state.config.cpu.variant == .rp2a03e/g/h) {
            // Controller/PPU corruption
            if (last_addr == 0x4016/0x4017/0x2002/0x2007) {
                _ = state.busRead(last_addr);
            }
        }
    }
}
```

**Key Observations:**
- ✅ Consumes exactly 1 CPU cycle per call
- ✅ Self-contained, no dependencies
- ✅ Clean completion via `rdy_low = false`
- ✅ **Ready for OAM interruption** - stateless operation

---

## Existing Pause/Resume Mechanisms

### None Found ❌

**Search Results:**
- No `paused` field in any DMA state structure
- No suspend/resume functions in `dma/logic.zig`
- No interrupt handling between DMA types

**Implications:**
- Must build pause/resume from scratch
- No existing patterns to follow
- High implementation risk

---

## Timing System Integration

### Master Clock Architecture

**Key Files:**
- `src/emulation/MasterClock.zig` - Single source of truth
- `src/emulation/state/Timing.zig` - TimingStep descriptor
- `src/emulation/State.zig::tick()` - Main loop coordinator

**Timing Flow:**
```zig
pub fn tick(self: *EmulationState) void {
    // 1. Compute next timing step (advances clock)
    const step = self.nextTimingStep();

    // 2. PPU always ticks (every PPU cycle)
    const ppu_result = self.stepPpuCycle(step.scanline, step.dot);

    // 3. APU ticks (synchronized with CPU, every 3 PPU cycles)
    if (step.apu_tick) {
        const apu_result = self.stepApuCycle();
    }

    // 4. CPU ticks (every 3 PPU cycles)
    if (step.cpu_tick) {
        const cpu_result = self.stepCpuCycle(); // ← Calls execution.zig::stepCycle()
    }
}
```

**DMA Execution Context:**
- DMC/OAM DMA run DURING `stepCpuCycle()` via `execution.zig::stepCycle()`
- Both consume CPU cycles (not PPU cycles)
- Both run at 1.789 MHz (1 CPU cycle = 3 PPU cycles)
- Clock already advanced when DMA executes ✅

**Timing Implications:**
- ✅ No clock coordination issues
- ✅ DMC/OAM run in same timing domain
- ✅ Pause/resume won't affect clock accuracy
- ⚠️ Must ensure cycle accounting stays correct

---

## Potential Challenges for DMC/OAM Interaction

### CRITICAL ISSUE 1: Cycle Accounting

**Problem:** OAM DMA advances `current_cycle` unconditionally.

**Current Code:**
```zig
pub fn tickOamDma(state: anytype) void {
    const cycle = state.dma.current_cycle;
    state.dma.current_cycle += 1; // ← Always increments
    // ...
}
```

**Issue:** If OAM is paused, should `current_cycle` advance?

**Hardware Answer:** NO - OAM cycle counter FREEZES during DMC interruption

**Fix Required:**
```zig
pub fn tickOamDma(state: anytype) void {
    // Only increment if not paused
    if (!state.dma.paused) {
        state.dma.current_cycle += 1;
    }
}
```

### CRITICAL ISSUE 2: Byte Duplication Timing

**Hardware Behavior (per nesdev.org):**
> When DMC interrupts OAM DMA during a READ cycle, the OAM read is performed
> twice when OAM resumes (the read that was interrupted + the next read).

**Implementation Challenges:**
1. **When to detect interruption?** During read cycle ONLY
2. **What to duplicate?** The address being read, not the value
3. **When to perform duplication?** First cycle after resume

**Proposed State:**
```zig
pub const OamDma = struct {
    active: bool = false,
    paused: bool = false,              // NEW
    was_paused_during_read: bool = false, // NEW - Track interruption phase
    source_page: u8 = 0,
    current_offset: u8 = 0,
    current_cycle: u16 = 0,
    needs_alignment: bool = false,
    temp_value: u8 = 0,
};
```

**Resume Logic:**
```zig
// On resume (DMC completes)
if (state.dma.paused and !state.dmc_dma.rdy_low) {
    state.dma.paused = false;

    // If interrupted during read, re-read same byte
    if (state.dma.was_paused_during_read) {
        const addr = (@as(u16, state.dma.source_page) << 8) |
                     @as(u16, state.dma.current_offset);
        state.dma.temp_value = state.busRead(addr); // Duplicate read
        state.dma.was_paused_during_read = false;
    }
}
```

### CRITICAL ISSUE 3: Multiple DMC Interruptions

**Scenario:** DMC triggers again while OAM still paused from previous DMC.

**Hardware Behavior:** DMC wins, OAM stays paused (cumulative delay).

**Current Design:** ✅ Naturally handles this - `rdy_low` flag is boolean.

**Edge Case:** Back-to-back DMC fetches (extremely rare but possible).

**Test Coverage Needed:**
1. Single DMC interruption
2. DMC during read phase
3. DMC during write phase
4. Multiple DMC interruptions (back-to-back)
5. OAM completion while paused (should finish transfer first)

### CRITICAL ISSUE 4: Priority Logic Refactor

**Current Code (WRONG):**
```zig
// DMC blocks OAM completely
if (state.dmc_dma.rdy_low) {
    state.tickDmcDma();
    return .{};
}

if (state.dma.active) {
    state.tickDma();
    return .{};
}
```

**Correct Logic:**
```zig
// DMC interrupts OAM (pause if needed)
if (state.dmc_dma.rdy_low) {
    // Pause OAM if active and not already paused
    if (state.dma.active and !state.dma.paused) {
        state.dma.paused = true;

        // Track interruption phase (read vs write)
        const effective_cycle = if (state.dma.needs_alignment)
            state.dma.current_cycle - 1
        else
            state.dma.current_cycle;

        state.dma.was_paused_during_read = (effective_cycle % 2 == 0);
    }

    state.tickDmcDma();
    return .{};
}

// OAM active (runs if not paused)
if (state.dma.active) {
    // Resume if DMC just finished
    if (state.dma.paused and !state.dmc_dma.rdy_low) {
        state.dma.paused = false;

        // Byte duplication (if interrupted during read)
        if (state.dma.was_paused_during_read) {
            const addr = (@as(u16, state.dma.source_page) << 8) |
                         @as(u16, state.dma.current_offset);
            state.dma.temp_value = state.busRead(addr);
            state.dma.was_paused_during_read = false;
        }
    }

    // Tick OAM if not paused
    if (!state.dma.paused) {
        state.tickDma();
    }

    return .{};
}
```

**Key Changes:**
1. DMC can pause OAM (not block completely)
2. OAM checks for resume condition
3. Byte duplication on resume (if read interrupted)
4. OAM only ticks if not paused

---

## What Needs to Change

### 1. OamDma State Structure (MINOR CHANGE)

**File:** `src/emulation/state/peripherals/OamDma.zig`

**Add Fields:**
```zig
pub const OamDma = struct {
    active: bool = false,
    paused: bool = false,                      // NEW
    was_paused_during_read: bool = false,      // NEW
    source_page: u8 = 0,
    current_offset: u8 = 0,
    current_cycle: u16 = 0,
    needs_alignment: bool = false,
    temp_value: u8 = 0,
};
```

**Update Reset:**
```zig
pub fn reset(self: *OamDma) void {
    self.* = .{}; // Already handles all fields
}
```

### 2. OAM DMA Logic (MINOR CHANGE)

**File:** `src/emulation/dma/logic.zig`

**Modify `tickOamDma()` to respect pause:**
```zig
pub fn tickOamDma(state: anytype) void {
    // Skip cycle increment if paused
    if (state.dma.paused) {
        return; // Consume 1 CPU cycle, but don't advance OAM state
    }

    // Rest of function unchanged
    const cycle = state.dma.current_cycle;
    state.dma.current_cycle += 1;
    // ... existing logic ...
}
```

### 3. CPU Execution Priority Logic (MAJOR CHANGE)

**File:** `src/emulation/cpu/execution.zig`

**Replace Lines 125-135:**
```zig
// DMC DMA active - CPU stalled (RDY line low)
// DMC has ABSOLUTE priority - can interrupt OAM
if (state.dmc_dma.rdy_low) {
    // Pause OAM if active and not already paused
    if (state.dma.active and !state.dma.paused) {
        state.dma.paused = true;

        // Track interruption phase for byte duplication bug
        const effective_cycle = if (state.dma.needs_alignment)
            state.dma.current_cycle - 1
        else
            state.dma.current_cycle;

        // Hardware bug: If interrupted during READ cycle, byte is duplicated on resume
        state.dma.was_paused_during_read = (effective_cycle % 2 == 0);
    }

    state.tickDmcDma();
    return .{};
}

// OAM DMA active - CPU frozen for 512 cycles
if (state.dma.active) {
    // Resume if DMC just finished
    if (state.dma.paused and !state.dmc_dma.rdy_low) {
        state.dma.paused = false;

        // Byte duplication on resume (hardware bug)
        if (state.dma.was_paused_during_read) {
            const addr = (@as(u16, state.dma.source_page) << 8) |
                         @as(u16, state.dma.current_offset);
            state.dma.temp_value = state.busRead(addr);
            state.dma.was_paused_during_read = false;
        }
    }

    // Tick OAM (respects pause flag internally)
    state.tickDma();
    return .{};
}
```

### 4. Test Coverage (NEW)

**File:** `tests/integration/dma_interaction_test.zig` (NEW)

**Required Tests:**
1. DMC interrupts OAM during read phase
2. DMC interrupts OAM during write phase
3. Byte duplication occurs on resume
4. Multiple DMC interruptions
5. OAM completes correctly after interruption
6. Cycle count accuracy (513 + DMC stalls)

---

## What Can Stay the Same

### ✅ DMC DMA State Structure
- No changes needed
- Already self-contained
- Cycle accounting correct

### ✅ DMC DMA Logic
- `tickDmcDma()` unchanged
- 4-cycle stall works correctly
- Corruption tracking intact

### ✅ Timing System
- Master clock unchanged
- `TimingStep` unchanged
- `tick()` loop unchanged

### ✅ OAM DMA Core Logic
- Read/write alternation correct
- Alignment handling correct
- Completion detection correct

### ✅ Bus Architecture
- `busRead()`/`busWrite()` unchanged
- Side effects work correctly
- No DMA-specific bus changes needed

---

## Risk Assessment & Gotchas

### HIGH RISK: Byte Duplication Edge Cases

**Gotcha:** Hardware duplicates the READ, not the write.

**Test Required:** Verify duplication happens ONLY on read-phase interruption.

**Failure Mode:** If duplication logic triggers on write, sprites will corrupt.

### MEDIUM RISK: Cycle Accounting Drift

**Gotcha:** Paused OAM must not advance `current_cycle`.

**Test Required:** Verify total OAM cycles = 513 + (DMC_stalls × 4).

**Failure Mode:** OAM completes early/late, causing sync issues.

### MEDIUM RISK: State Machine Complexity

**Gotcha:** Three boolean flags (`active`, `paused`, `was_paused_during_read`).

**Test Required:** State transition matrix (all valid combinations).

**Failure Mode:** Invalid states (e.g., paused=true but active=false).

### LOW RISK: DMC State Pollution

**Gotcha:** DMC and OAM share EmulationState - no isolation.

**Test Required:** Verify DMC doesn't corrupt OAM state.

**Failure Mode:** Unlikely - states are separate structs.

### LOW RISK: Priority Logic Regression

**Gotcha:** New priority code is more complex.

**Test Required:** Verify existing OAM/DMC tests still pass.

**Failure Mode:** Existing games break.

---

## Recommended Approach

### Option A: Minimal Changes (RECOMMENDED) ⭐

**Strategy:** Add pause flag, refactor priority, keep everything else.

**Pros:**
- Smallest possible change surface
- Reuses existing cycle accounting
- Low regression risk
- Matches hardware model closely

**Cons:**
- Still requires careful testing
- Byte duplication logic is subtle

**Estimated Time:** 6-8 hours
**Confidence:** 80%

### Option B: Major Refactor (NOT RECOMMENDED)

**Strategy:** Redesign DMA as unified state machine.

**Pros:**
- Cleaner architecture
- Easier to add future DMA types (hypothetical)

**Cons:**
- HIGH regression risk
- Requires rewriting all DMA logic
- Breaks existing tests
- Overkill for current needs

**Estimated Time:** 16-20 hours
**Confidence:** 50%

---

## Implementation Plan (Option A - Minimal Changes)

### Step 1: Add Pause State (1 hour)

**Files:** `src/emulation/state/peripherals/OamDma.zig`

**Actions:**
1. Add `paused: bool = false`
2. Add `was_paused_during_read: bool = false`
3. Update initialization (already handled by `.{}`)

**Test:** Compile, verify no regressions (990/995 still pass)

### Step 2: Update OAM Logic (1 hour)

**Files:** `src/emulation/dma/logic.zig::tickOamDma()`

**Actions:**
1. Add early return if `paused`
2. Ensure cycle counter doesn't advance when paused

**Test:** Manually pause OAM, verify it freezes

### Step 3: Refactor Priority Logic (2-3 hours)

**Files:** `src/emulation/cpu/execution.zig`

**Actions:**
1. Modify DMC block to pause OAM (not skip)
2. Track interruption phase (read vs write)
3. Add resume logic in OAM block
4. Implement byte duplication on resume

**Test:** Run existing DMA tests, verify no breakage

### Step 4: Add Unit Tests (2-3 hours)

**Files:** `tests/integration/dma_interaction_test.zig` (NEW)

**Tests:**
1. `test "DMC interrupts OAM during read - byte duplication"`
2. `test "DMC interrupts OAM during write - no duplication"`
3. `test "Multiple DMC interruptions during OAM"`
4. `test "OAM cycle count with DMC interruptions"`
5. `test "OAM completes correctly after resume"`

**Success Criteria:** All 5 tests pass, 990/995 baseline maintained

### Step 5: Integration Testing (1 hour)

**Actions:**
1. Run full test suite (must pass 990/995)
2. Test commercial ROMs (Battletoads, Castlevania III, TMNT)
3. Listen for audio improvements (DMC glitches reduced)

**Success Criteria:**
- No regressions
- Audio quality improves (subjective)
- No new visual glitches

### Step 6: Documentation & Commit (1 hour)

**Actions:**
1. Update `CLAUDE.md` with DMA interaction notes
2. Update `docs/CURRENT-ISSUES.md` with fix status
3. Create detailed commit message
4. Update session notes

**Commit Message Template:**
```
feat(dma): Implement DMC/OAM DMA preemptive priority with byte duplication

Hardware Behavior:
- DMC DMA has absolute priority over OAM DMA
- When DMC interrupts OAM, OAM pauses mid-transfer
- If interrupted during READ cycle, byte is read twice on resume
- OAM cycle counter freezes during pause

Implementation:
- Added `paused` and `was_paused_during_read` flags to OamDma
- Refactored execution.zig priority logic to support pause/resume
- DMC can now interrupt OAM without blocking it completely
- Byte duplication occurs when resuming from read-phase interrupt

Testing:
- 5 new unit tests for DMC/OAM interaction
- All baseline tests still pass (990/995)
- Audio quality improved in Battletoads, Castlevania III

References:
- nesdev.org/wiki/APU_DMC
- nesdev.org/wiki/PPU_OAM#DMA

Expected Impact:
- Improved audio quality in DMC-heavy games
- Hardware-accurate DMA timing
- Foundation for future APU accuracy work
```

---

## Success Criteria

### Must Achieve:

1. **✅ Zero Regressions**
   - 990/995 tests must continue passing
   - All currently working ROMs must not break

2. **✅ DMC Can Interrupt OAM**
   - DMC triggers while OAM active
   - OAM pauses, DMC runs 4 cycles
   - OAM resumes correctly

3. **✅ Byte Duplication Works**
   - Interruption during read → duplicate read on resume
   - Interruption during write → no duplication

4. **✅ Cycle Accounting Correct**
   - Total OAM cycles = 513 + (DMC_interruptions × 4)

5. **✅ State Machine Valid**
   - No invalid state combinations
   - Pause/resume transitions clean

### Nice to Have:

1. Audio quality improvement in commercial ROMs (subjective)
2. Foundation for future APU DMC fixes
3. Comprehensive test coverage (5+ tests)

---

## Conclusion

**ANALYSIS COMPLETE** ✅

**Recommended Path:** Option A (Minimal Changes)
- Add 2 boolean flags to OamDma
- Refactor 10-15 lines in execution.zig
- Add 5 comprehensive unit tests
- 6-8 hour implementation time

**Risk Level:** MEDIUM-HIGH
- Complex state machine interactions
- Subtle byte duplication timing
- Comprehensive testing required

**Confidence:** 80%
- Clear hardware specification
- Well-understood current architecture
- Minimal change surface
- Strong test coverage plan

**Next Step:** Review this analysis with user, get approval to proceed with implementation.

---

**RETURN TO:** zaza-enhanced-coordinator or direct user
**STATUS:** Ready for implementation decision
**RECOMMENDATION:** Proceed with Option A (Minimal Changes) using incremental approach
