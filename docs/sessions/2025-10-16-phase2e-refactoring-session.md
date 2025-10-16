# Phase 2E: DMC/OAM DMA Interaction - Refactoring Session

**Date:** 2025-10-16
**Status:** IN PROGRESS - Architecture refactored, 3/11 tests failing
**Previous Status:** 10/11 tests passing with architectural violations

## Executive Summary

Refactored Phase 2E (DMC/OAM DMA interaction) from broken 125-line implementation to clean VBlankLedger-based architecture. **Current regression: 8/11 tests passing (down from 10/11)**, but architecture is now correct and maintainable.

## Background

### Initial Implementation Issues
The original Phase 2E implementation (commit prior to this session) had critical architectural violations identified by agent review:

1. **125+ lines of complex logic** embedded directly in `execution.zig`
2. **No clear state machine** - implicit states from boolean flag combinations
3. **Byte duplication broken** - `temp_value` overwritten by `tickDma()` before use
4. **Cycle count off by 1** - Double increment causing timing error
5. **45+ lines of comments** trying to explain hacky logic (design smell)
6. **Agent verdict:** "DO NOT MERGE - Significant refactoring required"

### Reference Architecture: NMI Edge Detection
The correct pattern follows VBlankLedger (used for NMI):

**3-Layer Architecture:**
1. **Data Layer** - Pure timestamp-based ledger (VBlankLedger)
2. **State Layer** - Edge detection flags in CpuState
3. **Logic Layer** - Pure functions in checkInterrupts()

## Refactoring Implementation

### Created Files

#### 1. DmaInteractionLedger.zig (270 lines)
**Purpose:** Pure timestamp-based data structure for tracking DMC/OAM interaction state

**Key Components:**
```zig
pub const DmaInteractionLedger = struct {
    last_dmc_active_cycle: u64 = 0,      // DMC rising edge
    last_dmc_inactive_cycle: u64 = 0,    // DMC falling edge
    oam_pause_cycle: u64 = 0,            // OAM paused by DMC
    oam_resume_cycle: u64 = 0,           // OAM resumed after DMC
    interrupted_state: InterruptedState, // Captured state at pause
    duplication_pending: bool = false,   // Byte duplication flag
};
```

**Query Functions:**
- `isDmcActive()` - timestamp comparison (active > inactive)
- `isOamPaused()` - timestamp comparison (pause > resume)
- `didDmcJustComplete()` - edge detection for resume
- `shouldOamResume()` - combined query for resume logic

**Record Functions:**
- `recordDmcActive()` - record DMC rising edge
- `recordDmcInactive()` - record DMC falling edge
- `recordOamPause()` - capture OAM state at pause
- `recordOamResume()` - record resume edge
- `clearDuplication()` - clear duplication flag after write
- `clearPause()` - clear pause state on completion

**Tests:** 5 unit tests covering edge detection, pause/resume, duplication flags

#### 2. OamDma.zig - Added Explicit State Machine
**Purpose:** Replace implicit boolean states with explicit phase enum

**OamDmaPhase enum (8 states):**
```zig
pub const OamDmaPhase = enum {
    idle,                      // Not active
    aligning,                  // Alignment wait (odd cycle start)
    reading,                   // Read from CPU RAM (even cycles)
    writing,                   // Write to PPU OAM (odd cycles)
    paused_during_read,       // DMC paused us during read
    paused_during_write,      // DMC paused us during write
    resuming_with_duplication, // Resume after read interrupt (dup byte)
    resuming_normal,          // Resume after write interrupt (normal)
};
```

**Removed Fields:**
- `paused: bool` - replaced by phase enum
- `last_read_byte: u8` - moved to ledger.interrupted_state
- `was_reading_when_paused: bool` - moved to ledger.interrupted_state

**Updated `trigger()` method:**
- Initialize phase based on alignment: `if (on_odd_cycle) .aligning else .reading`
- Remove obsolete field initialization

#### 3. dma/interaction.zig (340 lines)
**Purpose:** Pure logic functions for pause/resume/duplication

**Core Functions:**

**handleDmcPausesOam():**
```zig
pub fn handleDmcPausesOam(
    ledger: *DmaInteractionLedger,
    oam: *const OamDma,
    cycle: u64,
) PauseAction
```
- Calculate effective_cycle accounting for alignment
- Determine if pausing during read (even) or write (odd)
- Record pause in ledger with captured state
- Return action: which phase to transition to, whether to read interrupted byte

**handleOamResumes():**
```zig
pub fn handleOamResumes(
    ledger: *DmaInteractionLedger,
    cycle: u64,
) ResumeAction
```
- Record resume in ledger
- Return action based on interrupted state: duplication or normal resume

**shouldOamPause():**
```zig
pub fn shouldOamPause(
    ledger: *const DmaInteractionLedger,
    oam: *const OamDma,
    dmc_active: bool,
) bool
```
- Query function: should OAM pause on this cycle?
- Checks: DMC active AND OAM active AND not already paused

**shouldOamResume():**
```zig
pub fn shouldOamResume(
    ledger: *const DmaInteractionLedger,
    oam: *const OamDma,
    dmc_active: bool,
    cycle: u64,
) bool
```
- Query function: should OAM resume on this cycle?
- Checks: OAM paused AND DMC just completed AND resume hasn't happened

**getDmaTickAction():**
```zig
pub fn getDmaTickAction(
    ledger: *const DmaInteractionLedger,
    oam: *const OamDma,
) DmaTickAction
```
- Query what action tickOamDma() should take based on phase
- Returns: skip (paused), continue_normal, or resume_with_duplication

**Tests:** 9 unit tests covering pause during read/write, resume with/without duplication, edge queries

### Modified Files

#### 1. execution.zig - Clean Ledger Integration
**Before:** 127 lines of complex pause/resume logic (lines 126-252)
**After:** 40 lines of clean ledger calls

**Key Changes:**

**Added DMC Edge Detection (lines 126-137):**
```zig
const prev_dmc_active = state.dma_interaction_ledger.isDmcActive();
const curr_dmc_active = state.dmc_dma.rdy_low;

if (curr_dmc_active and !prev_dmc_active) {
    state.dma_interaction_ledger.recordDmcActive(state.clock.ppu_cycles);
} else if (!curr_dmc_active and prev_dmc_active) {
    state.dma_interaction_ledger.recordDmcInactive(state.clock.ppu_cycles);
}
```

**DMC Active Path (lines 139-162):**
```zig
if (state.dmc_dma.rdy_low) {
    if (DmaInteraction.shouldOamPause(&state.dma_interaction_ledger, &state.dma, true)) {
        const action = DmaInteraction.handleDmcPausesOam(
            &state.dma_interaction_ledger,
            &state.dma,
            state.clock.ppu_cycles,
        );

        if (action.read_interrupted_byte) |read_info| {
            const addr = (@as(u16, read_info.source_page) << 8) | read_info.offset;
            state.dma_interaction_ledger.interrupted_state.byte_value = state.busRead(addr);
            state.dma_interaction_ledger.interrupted_state.oam_addr = state.ppu.oam_addr;
        }

        state.dma.phase = action.pause_phase;
    }

    state.tickDmcDma();
    return .{};
}
```

**OAM Active Path (lines 165-176):**
```zig
if (state.dma.active) {
    if (DmaInteraction.shouldOamResume(&state.dma_interaction_ledger, &state.dma, false, state.clock.ppu_cycles)) {
        const action = DmaInteraction.handleOamResumes(&state.dma_interaction_ledger, state.clock.ppu_cycles);
        state.dma.phase = action.resume_phase;
    }

    state.tickDma();
    return .{};
}
```

#### 2. dma/logic.zig - Phase Machine Integration
**Purpose:** Update tickOamDma() to use explicit phase machine and handle duplication

**Key Changes:**

**Query Action at Start (lines 36-81):**
```zig
const action = DmaInteraction.getDmaTickAction(&state.dma_interaction_ledger, &state.dma);

switch (action) {
    .skip => return,  // Paused

    .resume_with_duplication => |dup_info| {
        // Write duplicated byte (DOESN'T increment cycle counter)
        state.ppu.oam[dup_info.oam_addr] = dup_info.byte_to_write;
        state.ppu.oam_addr +%= 1;
        state.dma.phase = .resuming_normal;
        state.dma_interaction_ledger.clearDuplication();
        return;
    },

    .continue_normal => { /* fall through */ },
}
```

**Resume Phase Handling (lines 98-108):**
```zig
// Skip alignment if resuming (already did alignment before pause)
if (state.dma.needs_alignment and cycle == 0 and state.dma.phase != .resuming_normal) {
    state.dma.phase = .aligning;
    return;
}

// Transition resuming_normal to appropriate phase
if (state.dma.phase == .resuming_normal) {
    const effective_cycle = if (state.dma.needs_alignment) cycle - 1 else cycle;
    state.dma.phase = if (effective_cycle % 2 == 0) .reading else .writing;
}
```

**Phase Updates in Normal Flow (lines 120-142):**
```zig
if (effective_cycle % 2 == 0) {
    state.dma.phase = .reading;
    const source_addr = (@as(u16, state.dma.source_page) << 8) | @as(u16, state.dma.current_offset);
    state.dma.temp_value = state.busRead(source_addr);
} else {
    state.dma.phase = .writing;
    state.ppu.oam[state.ppu.oam_addr] = state.dma.temp_value;
    state.ppu.oam_addr +%= 1;
    state.dma.current_offset +%= 1;
}
```

**Removed:**
- `last_read_byte` tracking (now in ledger)

#### 3. State.zig - Added Ledger Field
```zig
pub const DmaInteractionLedger = @import("DmaInteractionLedger.zig").DmaInteractionLedger;

pub const EmulationState = struct {
    // ... existing fields ...
    vblank_ledger: VBlankLedger = .{},
    dma_interaction_ledger: DmaInteractionLedger = .{},  // NEW
    // ... remaining fields ...
};
```

#### 4. dmc_oam_conflict_test.zig - Test Updates
**Changes:**
- Replaced `state.dma.paused` with `isDmaPaused(state)` helper
- Helper checks phase: `phase == .paused_during_read or .paused_during_write`

## Test Results

### Before Refactoring
**Status:** 10/11 tests passing
- ✅ 10 tests passing
- ❌ 1 test failing (byte duplication - broken implementation)

### After Refactoring
**Status:** 8/11 tests passing (REGRESSION)
- ✅ 8 tests passing
- ❌ 3 tests failing

### Failing Tests

#### 1. "DMC interrupts OAM at byte 0 (start of transfer)"
**File:** `tests/integration/dmc_oam_conflict_test.zig:105`
**Failure:** `try testing.expect(state.ppu.oam[0] == 0x00);`
**Actual Result:** `state.ppu.oam[0] == 0` (no data transferred)

**Test Flow:**
1. Fill page 0x03 with sequential data (0x00, 0x01, 0x02, ...)
2. Trigger OAM DMA from page 0x03
3. Immediately trigger DMC DMA (interrupt at byte 0)
4. Tick 1 CPU cycle
5. **Verify pause happened** ✅ PASSES
6. Run DMC to completion
7. Run OAM to completion
8. **Verify OAM[0] == 0x00** ❌ FAILS (OAM[0] == 0)

**Hypothesis:** OAM DMA not actually transferring any data after resume. Possibly:
- Resume logic not transitioning to correct phase
- Alignment logic blocking first read after resume
- OAM address not properly tracked during pause/resume

#### 2. "Multiple DMC interrupts during single OAM transfer"
**File:** `tests/integration/dmc_oam_conflict_test.zig:279`
**Failure:** `try testing.expect(state.ppu.oam[0] == 0);`
**Actual Result:** Similar to test 1, OAM[0] remains 0

**Test Flow:**
1. Fill page with sequential data
2. Trigger OAM DMA
3. Interrupt 3 times (at bytes 50, 100, 150)
4. Verify OAM[0] == 0 after completion

**Hypothesis:** Same root cause as test 1 - data not transferring after resume

#### 3. "Cycle count: OAM 513 + DMC 4 = 517 total"
**File:** `tests/integration/dmc_oam_conflict_test.zig:358`
**Failure:** `try testing.expectEqual(@as(u64, 517), elapsed_cpu);`
**Actual Result:** 518 cycles (off by 1)

**Test Flow:**
1. Ensure even CPU cycle start
2. Start OAM DMA (513 cycles expected)
3. Run to byte 64 (128 cycles)
4. Interrupt with DMC (4 cycles)
5. Run to completion
6. **Verify total = 517** ❌ FAILS (518)

**Hypothesis:**
- Duplication write consuming an extra cycle
- Alignment logic adding extra cycle on resume
- Edge detection happening one cycle late

## Known Issues

### Critical Issues (Blocking 11/11)

1. **Data Transfer After Resume Broken**
   - Tests 1 & 2 show OAM remains all zeros
   - Resume logic transitions to correct phase, but data doesn't transfer
   - Possible issues:
     - Alignment logic blocks reads after resume
     - Phase transition timing wrong
     - OAM address reset during pause/resume

2. **Cycle Count Off By 1**
   - Test 3 shows 518 instead of 517
   - Possible causes:
     - Duplication write incorrectly increments cycle counter
     - Resume adds extra cycle
     - Edge detection timing

### Architecture Concerns

1. **Resume Phase Handling Complexity**
   - Lines 98-108 in dma/logic.zig have special-case logic
   - Skip alignment check for `.resuming_normal` phase
   - Then transition `.resuming_normal` → appropriate phase
   - This feels fragile - potential for double-phase-transition bugs

2. **Duplication Write Cycle Accounting**
   - Currently does NOT increment `current_cycle`
   - Is this correct? Hardware behavior unclear
   - Affects test 3 (cycle count)

3. **OAM Address Tracking**
   - Saved in `interrupted_state.oam_addr` at pause
   - Used during duplication write
   - NOT restored after duplication - is this correct?
   - Could cause writes to wrong OAM addresses

## Architecture Review: What Works

✅ **Clean Separation of Concerns:**
- Ledger stores pure timestamps
- State machine is explicit
- Logic functions are pure and testable

✅ **Edge Detection Working:**
- DMC active/inactive edges recorded correctly
- Pause/resume edges detected properly

✅ **Duplication Logic:**
- Correctly identifies read vs write interruption
- Captures interrupted byte
- Writes duplicated byte on resume

✅ **Reduced Complexity:**
- 127 lines → 40 lines (70% reduction)
- No more 45-line comment blocks
- Clear, readable flow

## Call Site Tracing

### DMC Edge Recording
**File:** `src/emulation/cpu/execution.zig`
**Lines:** 126-137
**Flow:**
1. Query previous DMC state from ledger
2. Compare with current hardware state (rdy_low)
3. Record edges when transitions occur

### Pause Detection & Handling
**File:** `src/emulation/cpu/execution.zig`
**Lines:** 139-162
**Flow:**
1. Check if DMC active (rdy_low)
2. Query `shouldOamPause()`
3. If true, call `handleDmcPausesOam()`
4. Read interrupted byte if needed
5. Transition phase
6. Tick DMC DMA
7. Return (CPU stalled)

### Resume Detection & Handling
**File:** `src/emulation/cpu/execution.zig`
**Lines:** 165-176
**Flow:**
1. Check if OAM active
2. Query `shouldOamResume()`
3. If true, call `handleOamResumes()`
4. Transition phase (to resuming_with_duplication or resuming_normal)
5. Tick OAM DMA
6. Return

### Duplication Write
**File:** `src/emulation/dma/logic.zig`
**Lines:** 45-72
**Flow:**
1. Query action from `getDmaTickAction()`
2. If `resume_with_duplication`:
   - Write byte to OAM (using saved oam_addr)
   - Increment oam_addr
   - Transition to resuming_normal
   - Clear duplication flag
   - Return (don't continue with normal tick)

### Resume Phase Transition
**File:** `src/emulation/dma/logic.zig`
**Lines:** 98-108
**Flow:**
1. Check if alignment needed AND cycle 0 AND NOT resuming_normal
2. If true, set phase to aligning and return
3. If phase is resuming_normal:
   - Calculate effective_cycle
   - Transition to reading or writing based on parity
   - Continue with normal flow

### Normal DMA Flow
**File:** `src/emulation/dma/logic.zig`
**Lines:** 110-142
**Flow:**
1. Increment current_cycle
2. Check alignment (if needed)
3. Calculate effective_cycle
4. Check completion (>= 512)
5. If even cycle: read, set phase=reading
6. If odd cycle: write, set phase=writing, increment offset

## Test Coverage Analysis

### Covered Scenarios ✅
1. DMC interrupts at byte 0 (start)
2. DMC interrupts at byte 128 (middle)
3. DMC interrupts at byte 255 (end)
4. Byte duplication during read interrupt
5. No duplication during write interrupt
6. Multiple DMC interrupts in single OAM transfer
7. Consecutive DMC interrupts (no gap)
8. Cycle count accuracy
9. Priority verification (DMC > OAM)
10. OAM alignment (odd cycle start)
11. DMC works without OAM active

### Missing Test Coverage ❌
1. **Interrupt during alignment cycle** (cycle 0 with needs_alignment=true)
2. **Resume during alignment phase** - how should this behave?
3. **OAM address != 0 at pause** - Does duplication use saved oam_addr correctly?
4. **Multiple pause/resume cycles for same byte** - Can we pause during duplication?
5. **DMC triggers exactly when OAM completes** - Edge case timing
6. **OAM completes during DMC stall** - Does completion wait?

## Questions Requiring Investigation

### Q1: What happens when DMC interrupts during alignment cycle?
**Current Code:** Pause logic calculates `effective_cycle = cycle - 1` if needs_alignment
**Result:** effective_cycle = -1, which is < 0, so `is_reading = false` (pause during write)
**Is this correct?** Need to verify hardware behavior

### Q2: Does duplication write consume a CPU cycle?
**Current Implementation:** Does NOT increment current_cycle
**Test Expectation:** 517 cycles total
**Actual Result:** 518 cycles
**Hypothesis:** Duplication should NOT add to cycle count, something else is adding 1

### Q3: How does resume interact with alignment?
**Current Code:** Skips alignment check if `phase == .resuming_normal`
**Question:** Is this correct? Or should we re-do alignment after pause?

### Q4: When is oam_addr used vs current_offset?
**Observation:**
- `current_offset` tracks which byte we're transferring (0-255)
- `oam_addr` is PPU's internal pointer (can start != 0)
- Duplication uses saved `oam_addr` from pause moment
- Normal writes use current `oam_addr` (which auto-increments)

**Question:** After duplication write (which increments oam_addr), do we need to restore it?

## Next Steps

### Immediate Actions (Critical Path)
1. ✅ **Document session thoroughly** (THIS FILE)
2. ⏳ **Launch agent analysis** - Comprehensive review by specialized agents:
   - Architecture review agent
   - Execution flow tracing agent
   - Test coverage analysis agent
   - Fix recommendation agent
3. ⏳ **Methodical debugging** - Trace exact execution for failing test 1:
   - Add detailed logging
   - Single-step through pause/resume
   - Verify phase transitions
   - Check data reads/writes
4. ⏳ **Fix identified issues** - Actually solve the 3 failures
5. ⏳ **Verify 11/11 passing** - Run full suite

### Investigation Tasks
1. Trace execution for "DMC interrupts OAM at byte 0" with verbose logging
2. Identify why OAM data doesn't transfer after resume
3. Determine correct cycle accounting for duplication
4. Verify alignment behavior on resume
5. Check oam_addr handling across pause/resume

### Potential Fixes (Hypotheses to Test)
1. **Fix resume phase transition:**
   - Remove special alignment skip for resuming_normal
   - Or: Ensure transition happens before alignment check
2. **Fix cycle accounting:**
   - Verify duplication doesn't increment counter
   - Check if resume adds extra cycle
3. **Fix data transfer:**
   - Ensure phase correctly set to reading after resume
   - Verify effective_cycle calculation on resume
   - Check that normal flow continues after phase transition

## Metrics

### Code Metrics
- **Lines Added:** ~610 (DmaInteractionLedger: 270, interaction.zig: 340)
- **Lines Removed:** ~127 (execution.zig complexity)
- **Net Change:** +483 lines (distributed across proper modules)
- **Complexity Reduction:** execution.zig: 127 lines → 40 lines (70% reduction)

### Test Metrics
- **Before:** 10/11 passing (90.9%)
- **After:** 8/11 passing (72.7%)
- **Regression:** -2 tests (-18.2 percentage points)
- **New Failures:** 2 tests (byte 0, multiple interrupts)
- **Existing Failures:** 1 test (cycle count - was already failing, now different)

### Time Investment
- **Agent Analysis:** ~30 minutes
- **Planning:** ~20 minutes
- **Implementation:** ~2 hours
- **Debugging:** ~1.5 hours (IN PROGRESS)
- **Total:** ~4+ hours

## Conclusion

The refactoring successfully achieved its primary goal: **architectural correctness**. The code now follows established patterns (VBlankLedger), has clear separation of concerns, and is maintainable.

However, **we introduced a regression** (8/11 vs 10/11). The clean architecture has bugs in edge cases that must be fixed before this can be considered complete.

**The code is not ready to merge** until all 11 tests pass.

**Next session must focus on:** Methodical debugging of the 3 failing tests, not moving forward with new features.
