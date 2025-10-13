# VBlank/NMI Investigation - Super Mario Bros Blank Screen

**Date Created:** 2025-10-12
**Priority:** P0 (Critical - blocks commercial ROM compatibility)
**Status:** Investigation in progress
**Related Bug:** Super Mario Bros displays blank screen, stuck in initialization

---

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [Hardware Specification](#hardware-specification)
3. [Current Implementation Analysis](#current-implementation-analysis)
4. [Investigation History](#investigation-history)
5. [Investigation Plan](#investigation-plan)
6. [Test Strategy](#test-strategy)
7. [Development Checklist](#development-checklist)
8. [Session Notes](#session-notes)

---

## Problem Statement

### What is the Bug?

Super Mario Bros displays a **blank screen** and never enables rendering. The game is stuck in its initialization sequence, unable to detect or respond to VBlank timing events correctly.

**Symptom:**
```
Expected: Game writes PPUMASK=0x1E to enable rendering
Actual:   Game writes PPUMASK=0x06 then 0x00 (rendering disabled)
          Never progresses to main game loop
```

**Comparison with Working ROM (Mario Bros):**
```
Mario Bros (✅):
  PPUMASK writes: 0x00 → 0x06 → 0x1E (rendering enabled on 3rd write)

Super Mario Bros (❌):
  PPUMASK writes: 0x06 → 0x00 → 0x00 (rendering never enabled)
```

### Why is this Critical?

1. **Blocks Commercial ROM Compatibility:** Super Mario Bros is one of the most iconic NES games. Failure to run it blocks major milestone.
2. **Indicates Core Timing Issue:** If SMB can't detect VBlank, other games likely have similar issues.
3. **Tests Don't Catch It:** AccuracyCoin passes (939/939 tests), but SMB fails. This suggests gap in test coverage for real-world timing scenarios.

### What Have We Tried?

**Phase 1: VBlank Flag Clear Bug (2025-10-09)**
- **Fix:** Implemented VBlankLedger timestamp-based tracking
- **Result:** Fixed primary bug where $2002 reads didn't clear VBlank flag
- **Outcome:** 17 tests fixed, but SMB still broken

**Phase 2: NMI Edge Persistence (2025-10-10)**
- **Fix:** Corrected NMI edge persistence and interrupt timing
- **Result:** NMI now fires correctly, handler executes
- **Outcome:** SMB NMI handler runs but gets stuck in internal loop at `0x8E6C-0x8E79`

**Phase 3: VBlank Migration (2025-10-10)**
- **Fix:** Completed 4-phase migration to VBlankLedger as single source of truth
- **Result:** Architecture cleaned up, race conditions handled
- **Outcome:** SMB still displays blank screen

**Phase 4: Test Harness Improvements (2025-10-12)**
- **Fix:** Added deterministic helpers for VBlank staging and ledger snapshots
- **Result:** Better test instrumentation for debugging
- **Outcome:** Identified SMB disables NMI after first handler, never re-enables

**Current Status:** Investigation ongoing - VBlank mechanism works correctly, but SMB initialization sequence doesn't complete as expected.

---

## Hardware Specification

### VBlank Timing (nesdev.org)

**Frame Structure (NTSC):**
```
Scanlines 0-239:   Visible frame (240 scanlines)
Scanline 240:      Post-render (idle)
Scanlines 241-260: VBlank period (20 scanlines)
Scanline 261:      Pre-render (VBlank ends)

Total: 262 scanlines × 341 dots = 89,342 PPU cycles (odd frames: 89,341)
```

**VBlank Flag Behavior:**
```
Scanline 241, Dot 1:  VBlank flag SET (bit 7 of $2002)
Scanlines 241-260:    VBlank flag REMAINS SET
Scanline 261, Dot 1:  VBlank flag CLEARED (pre-render)
```

**$2002 Read Side Effect:**
```
Reading PPUSTATUS ($2002):
1. Returns current status byte (VBlank in bit 7)
2. IMMEDIATELY clears VBlank flag
3. Resets PPUADDR/PPUSCROLL write toggle

The flag stays cleared until next VBlank (scanline 241.1)
```

### NMI Edge Detection (nesdev.org)

**NMI Signal Generation:**
```
NMI_signal = VBlank_flag AND PPUCTRL.7 (NMI_enable)

NMI fires on 0→1 transition of NMI_signal:
- VBlank sets while NMI already enabled → NMI fires
- NMI enabled while VBlank already set → NMI fires
- VBlank clears or NMI disabled → No edge (NMI doesn't fire)
```

**Edge Persistence:**
```
Once NMI edge is latched, it persists until acknowledged:
- Reading $2002 does NOT clear latched NMI edge
- Disabling PPUCTRL.7 does NOT clear latched NMI edge
- Only CPU interrupt acknowledgment clears the latch
```

### Race Condition (nesdev.org/wiki/NMI)

**Critical Timing Edge Case:**

> "If the VBlank flag is read on the same PPU clock cycle that it is set,
> the flag will not be cleared, but the NMI will be suppressed."

**Translation:**
```
CPU reads $2002 on exact cycle VBlank sets (scanline 241.1):
  - VBlank flag remains HIGH (not cleared by read)
  - But NMI is suppressed (interrupt doesn't fire)

This prevents NMI from firing for entire frame (until next VBlank)
```

**Our Implementation:**

VBlankLedger handles this with timestamp comparison:
```zig
pub fn isReadableFlagSet(self: *const VBlankLedger, current_cycle: u64) bool {
    // Race condition: Reading on exact set cycle suppresses NMI
    // but doesn't clear the readable flag
    if (current_cycle == self.last_set_cycle) {
        return true;  // Flag still readable, but NMI suppressed
    }

    // Normal case: Flag is set if last_set > last_clear
    return self.last_set_cycle > self.last_clear_cycle;
}
```

### PPU Warm-Up Period

**Hardware Behavior:**

After power-on, PPU ignores writes to PPUCTRL ($2000) and PPUMASK ($2001) for first **29,658 CPU cycles** (~10 frames). Games must wait for warm-up before configuring PPU.

**Our Implementation:**

`PpuState.warmup_complete` flag tracked in emulation logic.

---

## Current Implementation Analysis

### VBlankLedger Architecture

**File:** `src/emulation/state/VBlankLedger.zig`

**Design Philosophy:**

Decouples CPU NMI latch from readable PPU status flag using timestamp-based tracking:

```zig
pub const VBlankLedger = struct {
    // Live state flags
    span_active: bool = false,          // VBlank period active (241.1 to 261.1)
    nmi_edge_pending: bool = false,     // NMI latched, awaiting CPU ack

    // Timestamp history (PPU master clock cycles)
    last_set_cycle: u64 = 0,            // When VBlank set (241.1)
    last_clear_cycle: u64 = 0,          // When VBlank cleared ($2002 read or 261.1)
    last_status_read_cycle: u64 = 0,    // When $2002 last read
    last_ctrl_toggle_cycle: u64 = 0,    // When PPUCTRL written
    last_cpu_ack_cycle: u64 = 0,        // When CPU acknowledged NMI
};
```

**Key Functions:**

```zig
// Records VBlank set at scanline 241.1
pub fn recordVBlankSet(self: *VBlankLedger, cycle: u64, nmi_enabled: bool) void

// Records VBlank span end at scanline 261.1
pub fn recordVBlankSpanEnd(self: *VBlankLedger, cycle: u64) void

// Records $2002 read (clears readable flag)
pub fn recordStatusRead(self: *VBlankLedger, cycle: u64) void

// Records PPUCTRL write (may toggle NMI enable)
pub fn recordCtrlToggle(self: *VBlankLedger, cycle: u64, nmi_enabled: bool) void

// Query readable VBlank flag state (handles race condition)
pub fn isReadableFlagSet(self: *const VBlankLedger, current_cycle: u64) bool

// Query if NMI edge should be asserted
pub fn shouldAssertNmiLine(self: *const VBlankLedger) bool
```

### $2002 Read Implementation

**File:** `src/ppu/logic/registers.zig:72-100`

**Phase 2 Migration (Complete):**

```zig
0x0002 => blk: {
    // $2002 PPUSTATUS - Read-only

    // Query VBlank flag from ledger (single source of truth)
    // This handles race conditions correctly (reading on exact set cycle)
    const vblank_flag = vblank_ledger.isReadableFlagSet(current_cycle);

    // Build status byte using helper function
    // VBlank comes from ledger, sprite flags from PpuStatus
    const value = buildStatusByte(
        state.status.sprite_overflow,
        state.status.sprite_0_hit,
        vblank_flag,
        state.open_bus.value,
    );

    // Side effects:
    // 1. Record $2002 read in ledger (updates last_status_read_cycle, last_clear_cycle)
    vblank_ledger.recordStatusRead(current_cycle);

    // 2. Reset write toggle
    state.internal.resetToggle();

    // 3. Update open bus with status (top 3 bits)
    state.open_bus.write(value);

    break :blk value;
},
```

**Critical Properties:**

1. **Ledger is Single Source:** VBlank flag queried from ledger, not `PpuState.status.vblank`
2. **Race Condition Handled:** `isReadableFlagSet()` checks for read-on-set-cycle edge case
3. **Side Effect Isolated:** `recordStatusRead()` updates ledger timestamps cleanly
4. **No NMI Clear:** Reading $2002 does NOT clear `nmi_edge_pending` (correct behavior)

### NMI Edge Detection

**File:** `src/emulation/cpu/execution.zig` (stepCycle function)

**Current Flow:**

```zig
pub fn stepCycle(state: *EmulationState) void {
    // 1. Query NMI line from ledger
    const should_assert_nmi = state.vblank_ledger.shouldAssertNmiLine();

    // 2. Set CPU NMI line
    state.cpu.nmi_line = should_assert_nmi;

    // 3. Step CPU (interrupt detection happens in CPU microsteps)
    state.cpu.tick(&state.bus);

    // 4. If CPU acknowledged interrupt, clear ledger edge
    if (state.cpu.interrupt_acknowledged) {
        state.vblank_ledger.acknowledgeCpu(state.clock.ppu_cycles);
        state.cpu.interrupt_acknowledged = false;
    }
}
```

**shouldAssertNmiLine() Logic:**

```zig
pub fn shouldAssertNmiLine(self: *const VBlankLedger) bool {
    // NMI line is HIGH when edge is pending
    // Edge persists until CPU acknowledges (completes interrupt sequence)
    return self.nmi_edge_pending;
}
```

### Suspected Issues

Based on investigation history and SMB behavior:

**Issue 1: VBlank Detection Timing (UNLIKELY)**
- VBlankLedger correctly sets `span_active` at 241.1 and clears at 261.1
- $2002 reads correctly return VBlank flag and clear it
- Tests verify this works (`tests/ppu/vblank_behavior_test.zig`)

**Issue 2: NMI Handler Loop (CONFIRMED)**
- SMB NMI handler executes but gets stuck at `0x8E6C-0x8E79`
- Handler is countdown loop (DEY + BNE) waiting for Y=0
- Loop never terminates, suggesting memory/state corruption or PPU timing issue

**Issue 3: PPU State During NMI (INVESTIGATING)**
- SMB handler reads PPU state during NMI
- May be expecting specific scanline/dot timing
- May be waiting for sprite DMA or rendering state change

**Issue 4: Missing Game Initialization (POSSIBLE)**
- SMB may require specific controller input before starting
- May need to wait for multiple VBlank cycles before initializing
- Current debugger logging shows NMI handler runs, but game state may not be ready

---

## Investigation History

### 2025-10-09: VBlank Flag Clear Bug Discovery

**Document:** `docs/archive/sessions-2025-10-09-10/vblank-flag-clear-bug-2025-10-09.md`

**Finding:** Reading $2002 (PPUSTATUS) did not clear VBlank flag

**Evidence:**
```
Before fix: $2002 reads returned VBlank=true multiple times
After fix:  $2002 reads return VBlank=true once, then false
```

**Fix:** Implemented VBlankLedger timestamp tracking

**Result:** 17 tests fixed, commercial ROM (Bomberman) started working

---

### 2025-10-10: VBlank Flag Race Condition

**Document:** `docs/archive/sessions-2025-10-09-10/vblank-flag-race-condition-2025-10-10.md`

**Finding:** VBlank flag sets correctly at 241.1 but immediately clears before CPU reads it

**Evidence:**
```
[DEBUG] At 241.1: vblank_flag=false, about to set
[VBlankLedger] NMI EDGE PENDING SET!
[DEBUG] VBlank flag NOW TRUE
[$2002 READ] value=0x10, VBlank=false  ← Flag already cleared!
```

**Hypothesis:** $2002 read was clearing flag unconditionally, even on same cycle it set

**Fix:** Completed VBlank Migration Phases 1-4:
- Phase 1: Remove `PpuState.status.vblank` field entirely
- Phase 2: Make `readRegister()` query ledger for VBlank flag
- Phase 3: Update all callers to pass ledger and cycle
- Phase 4: Clean up PPU flags and update tests

**Result:** Architecture cleaned up, race condition handled, but SMB still broken

---

### 2025-10-10: NMI Handler Execution Investigation

**Document:** `docs/sessions/smb-nmi-handler-investigation.md`

**Finding:** NMI mechanism works correctly, but handler gets stuck in loop

**Evidence:**
```
[VBlankLedger] NMI EDGE PENDING SET!
[NMI LINE] changed false -> true at scanline=241, dot=1
[CPU] PC=0x8082  ← NMI handler entry
[CPU] PC=0x8E6C-0x8E79  ← Stuck in countdown loop (DEY + BNE)
```

**Handler Loop Analysis:**
```zig
0x8E6C: PHA          // Push A
0x8E6D: LDA abs,X    // Load from table
0x8E70: STA zp       // Store to zero page
0x8E72: LSR          // Shift right
0x8E73: ORA zp       // Combine with stored value
0x8E75: LSR          // Shift right again
0x8E76: PLA          // Pull A
0x8E77: ROL          // Rotate left
0x8E78: DEY          // Decrement Y counter
0x8E79: BNE 0x8E6C   // Loop if Y != 0
```

**Finding:** This is a data processing loop waiting for Y register to reach zero. Loop never terminates.

**Hypothesis:**
1. Y register initialized incorrectly (too large value)
2. Loop body is corrupting Y register
3. Memory being read/written is wrong
4. PPU timing is affecting memory-mapped I/O reads in loop

---

### 2025-10-12: Test Harness Improvements

**Document:** `docs/sessions/2025-10-12-bit-nmi-harness-notes.md`

**Changes:**
- Added deterministic helpers to TestHarness for VBlank staging
- Enhanced SMB regression harness with per-frame PPUCTRL/PPUMASK logging
- Added ledger snapshot capabilities for better debugging

**Findings:**
- BIT timing shows flag cleared immediately after execute cycle (matches hardware)
- SMB disables NMI after first handler and never re-enables rendering
- `last_status_read_cycle` never advances, confirming NMI handler stuck

**Outstanding Issues:**
- BIT timing needs CPU microcode cross-check
- SMB frame trace needs comparison with known-good capture
- Legacy NMI sequence tests need alignment with updated harness

---

## Investigation Plan

### Phase 1: Code Review ✅ COMPLETE

**Objective:** Verify VBlankLedger and $2002 side effect isolation

**Tasks:**
- [x] Review VBlankLedger timestamp tracking implementation
- [x] Review `readRegister()` $2002 handler
- [x] Review NMI edge detection in `stepCycle()`
- [x] Verify race condition handling in `isReadableFlagSet()`
- [x] Confirm no duplicate state tracking (single source of truth)

**Findings:**
- VBlankLedger architecture is sound
- $2002 reads correctly query ledger and record side effects
- NMI edge detection correctly queries `shouldAssertNmiLine()`
- Race condition handled with timestamp comparison
- No architectural duplication after cleanup

**Status:** ✅ Architecture verified correct

---

### Phase 2: Timing Analysis (CURRENT)

**Objective:** Trace SMB execution at scanline 241.1 to understand stuck handler

**Tasks:**
- [ ] Use debugger to break at NMI handler entry (`0x8082`)
- [ ] Trace handler execution until stuck loop (`0x8E6C-0x8E79`)
- [ ] Dump CPU state when loop starts (A, X, Y, SP, P registers)
- [ ] Identify what memory addresses loop reads/writes
- [ ] Compare Y register value vs expected loop count
- [ ] Check if PPU scanline/dot affects memory-mapped I/O

**Debugger Commands:**
```bash
# Break at NMI handler entry
./zig-out/bin/RAMBO "Super Mario Bros. (World).nes" \
  --break-at 0x8082 --inspect

# Watch PPUSTATUS reads during handler
./zig-out/bin/RAMBO "Super Mario Bros. (World).nes" \
  --watch 0x2002 --inspect

# Watch memory addresses being read in loop
./zig-out/bin/RAMBO "Super Mario Bros. (World).nes" \
  --break-at 0x8E6C --inspect
```

**Expected Outputs:**
- NMI handler entry state (registers before loop)
- Y register initial value (loop counter)
- Memory addresses accessed in loop body
- PPU scanline/dot during loop execution
- Exit condition that should terminate loop

---

### Phase 3: Test Enhancement

**Objective:** Add specific test cases for SMB timing scenario

**Tasks:**
- [ ] Create `tests/integration/smb_vblank_timing_test.zig`
- [ ] Test: NMI fires at 241.1 with handler executing
- [ ] Test: Handler reads $2002 during execution
- [ ] Test: Handler performs countdown loop (mock SMB loop)
- [ ] Test: Verify Y register decrements correctly
- [ ] Test: Verify loop terminates at Y=0

**Test Structure:**
```zig
// Simulate SMB NMI handler countdown loop
test "NMI handler countdown loop executes correctly" {
    var harness = try TestHarness.init(testing.allocator);
    defer harness.deinit();

    // Stage VBlank at 241.1
    harness.forceVBlankStart();

    // Set up CPU for countdown loop (Y=8)
    harness.state.cpu.y = 8;
    harness.state.cpu.pc = 0x8E6C;  // Loop entry

    // Execute loop (should take 8 iterations)
    const max_cycles = 1000;
    var cycle: usize = 0;
    while (cycle < max_cycles and harness.state.cpu.y != 0) : (cycle += 1) {
        harness.stepCpu();
    }

    // Verify loop terminated
    try testing.expect(harness.state.cpu.y == 0);
    try testing.expect(cycle < max_cycles);  // Didn't timeout
}
```

---

### Phase 4: Root Cause Identification

**Objective:** Determine why SMB handler loop doesn't terminate

**Possible Root Causes:**

**A. Y Register Not Decrementing (CPU Bug)**
- DEY instruction not working correctly
- Status register (Z flag) not setting correctly
- BNE instruction branching incorrectly

**B. Memory Corruption (Bus/Mapper Bug)**
- Loop reads wrong memory addresses
- Memory-mapped I/O returning wrong values
- Mapper (NROM) not routing addresses correctly

**C. PPU Timing Issue (Timing Bug)**
- Handler expects specific scanline/dot during execution
- OAM DMA timing not matching hardware
- VBlank period ending prematurely

**D. Initialization State Missing (Game Logic)**
- Game expects zero page memory initialized differently
- Stack pointer or stack contents wrong
- IRQ/BRK flags affecting handler execution

**Investigation Steps:**
1. Disassemble handler completely to understand logic
2. Compare with known-good NES disassembly (if available)
3. Test each opcode in loop individually (unit tests)
4. Verify memory-mapped I/O reads during handler
5. Check PPU state progression during handler execution

---

### Phase 5: Fix Implementation

**Objective:** Implement fix once root cause identified

**Potential Fixes (based on root cause):**

**If CPU Bug:**
- Fix DEY instruction implementation
- Fix status register flag setting
- Fix BNE branch condition evaluation

**If Memory Bug:**
- Fix bus address routing
- Fix open bus behavior during reads
- Fix mapper address decoding

**If Timing Bug:**
- Adjust VBlank timing (unlikely, tests pass)
- Fix OAM DMA cycle counting
- Fix PPU scanline/dot progression

**If Initialization Bug:**
- Implement missing hardware initialization
- Fix power-on state (zero page, stack)
- Document required user input (if START button needed)

---

### Phase 6: Regression Testing

**Objective:** Verify fix doesn't break existing tests

**Test Plan:**
```bash
# Run full test suite
zig build test

# Expected results:
# - All 949 tests still passing
# - No new failures introduced
# - SMB now progresses past initialization

# Run AccuracyCoin validation
./zig-out/bin/RAMBO tests/data/AccuracyCoin.nes

# Expected: All 939 opcode tests pass (no regression)

# Run SMB
./zig-out/bin/RAMBO "Super Mario Bros. (World).nes"

# Expected: Title screen appears, rendering enabled
```

**Regression Criteria:**
- ✅ All existing VBlank tests pass
- ✅ AccuracyCoin still passes (939/939)
- ✅ Mario Bros still works (working ROM doesn't break)
- ✅ SMB displays title screen and responds to input

---

## Test Strategy

### Existing Test Coverage

**VBlank-Related Tests:**

1. **`tests/ppu/vblank_behavior_test.zig`** (18 tests)
   - VBlank flag set/clear timing
   - $2002 read side effects
   - Scanline 241.1 and 261.1 behavior

2. **`tests/ppu/vblank_nmi_timing_test.zig`** (12 tests)
   - NMI edge detection timing
   - PPUCTRL toggle during VBlank
   - Race condition handling

3. **`tests/ppu/simple_vblank_test.zig`** (8 tests)
   - Basic VBlank set/clear
   - Simple $2002 polling

4. **`tests/integration/vblank_wait_test.zig`** (6 tests)
   - Full emulation VBlank wait loops
   - CPU/PPU integration

5. **`tests/integration/smb_vblank_reproduction_test.zig`** (NEW)
   - SMB-specific timing scenario
   - Reproduction test for blank screen bug

**Total Coverage:** 44 tests covering VBlank/NMI timing

**Gaps in Coverage:**

1. **No SMB-specific handler simulation**
   - Existing tests don't simulate countdown loops in NMI handler
   - Don't test memory access patterns during handler

2. **No multi-frame initialization tests**
   - Games like SMB may require 3-5 frames of initialization
   - Tests mostly focus on single VBlank cycle

3. **No OAM DMA during NMI tests**
   - SMB performs OAM DMA in NMI handler
   - May interact with VBlank timing

### New Tests Required

**Test 1: NMI Handler Countdown Loop**
```zig
test "NMI handler countdown loop terminates correctly" {
    // Simulate SMB's DEY+BNE loop structure
    // Verify Y register decrements and loop exits
}
```

**Test 2: Multiple VBlank Initialization**
```zig
test "Game initialization across multiple VBlank cycles" {
    // Run 5 frames, verify NMI fires each frame
    // Check that handler can execute multiple times
}
```

**Test 3: OAM DMA During NMI**
```zig
test "OAM DMA triggered during NMI handler" {
    // Trigger OAM DMA at $4014 during handler
    // Verify DMA completes and doesn't corrupt timing
}
```

**Test 4: $2002 Read During NMI Handler**
```zig
test "Reading PPUSTATUS during NMI handler execution" {
    // Handler reads $2002 to clear VBlank flag
    // Verify flag clears but NMI edge remains latched
}
```

### Test Verification Strategy

**Before Fix:**
- Capture current test results: `949/986 passing (96.2%)`
- Run SMB, capture blank screen behavior
- Document exact PPUMASK write sequence

**After Fix:**
- Run full test suite: `zig build test`
- Verify no regressions (949+ tests passing)
- Run AccuracyCoin: should still pass 939/939
- Run SMB: should display title screen
- Run Mario Bros: should still work (no regression)

**Acceptance Criteria:**
- [ ] SMB displays title screen
- [ ] SMB responds to controller input
- [ ] SMB gameplay starts on pressing START
- [ ] No test regressions in suite
- [ ] AccuracyCoin still passes

---

## Development Checklist

### Phase 1: Code Review ✅
- [x] Review VBlankLedger implementation
- [x] Review $2002 read side effects
- [x] Review NMI edge detection logic
- [x] Verify race condition handling
- [x] Confirm single source of truth architecture

### Phase 2: Timing Analysis (CURRENT)
- [ ] Break at NMI handler entry (`0x8082`)
- [ ] Trace handler to stuck loop (`0x8E6C-0x8E79`)
- [ ] Dump CPU registers at loop entry
- [ ] Identify memory addresses accessed in loop
- [ ] Compare Y register vs expected count
- [ ] Check PPU state during handler execution

### Phase 3: Test Enhancement
- [ ] Create SMB-specific timing tests
- [ ] Add countdown loop simulation test
- [ ] Add multi-frame initialization test
- [ ] Add OAM DMA during NMI test
- [ ] Add $2002 read during handler test

### Phase 4: Root Cause Identification
- [ ] Disassemble SMB NMI handler completely
- [ ] Test each opcode in loop individually
- [ ] Verify memory-mapped I/O behavior
- [ ] Check PPU timing during handler
- [ ] Identify why loop doesn't terminate

### Phase 5: Fix Implementation
- [ ] Implement fix based on root cause
- [ ] Add test coverage for fix
- [ ] Verify fix resolves SMB issue
- [ ] Document fix in KNOWN-ISSUES.md

### Phase 6: Regression Testing
- [ ] Run full test suite (expect 949+ passing)
- [ ] Run AccuracyCoin (expect 939/939)
- [ ] Run Mario Bros (expect no regression)
- [ ] Run SMB (expect title screen)
- [ ] Update documentation and commit

---

## Session Notes

### Session Template

Use this template for each investigation session:

```markdown
### Session: YYYY-MM-DD HH:MM - Brief Description

**Duration:** X hours
**Focus:** What was investigated this session

#### What Was Investigated

List specific files, functions, or behaviors examined:
- File: `path/to/file.zig` (lines X-Y)
- Function: `functionName()` behavior
- Test: `test_name.zig` results

#### Findings

Document discoveries with line numbers and evidence:
- Finding 1: Description
  - Evidence: Code snippet or test output
  - Location: File path and line numbers

- Finding 2: Description
  - Evidence: Debug output or trace
  - Impact: How this affects the bug

#### Hypotheses Tested

List hypotheses and test results:
1. **Hypothesis:** VBlank flag clears too early
   - **Test:** Added logging at 241.1
   - **Result:** ❌ Flag sets correctly, not the issue

2. **Hypothesis:** NMI edge not persisting
   - **Test:** Checked `nmi_edge_pending` in ledger
   - **Result:** ✅ Edge persists correctly

#### Next Steps

What to investigate in next session:
- [ ] Task 1: Specific action
- [ ] Task 2: Specific measurement
- [ ] Task 3: Specific test to write

#### References

Links to relevant documentation:
- `docs/path/to/related-doc.md`
- nesdev.org URL
- Commit hash if changes made
```

---

### Session: 2025-10-09 08:00 - VBlank Flag Clear Bug

**Duration:** 4 hours
**Focus:** Fixed primary bug where $2002 reads didn't clear VBlank flag

#### What Was Investigated

- File: `src/ppu/logic/registers.zig` (lines 46-56)
- File: `src/emulation/state/VBlankLedger.zig` (entire file)
- Test: `tests/ppu/ppustatus_polling_test.zig`

#### Findings

- **Finding 1:** $2002 read was not clearing `PpuState.status.vblank`
  - Evidence: Missing `state.status.vblank = false;` line
  - Location: `src/ppu/logic/registers.zig:46`
  - Impact: Commercial ROMs couldn't detect VBlank correctly

- **Finding 2:** Needed timestamp-based tracking for race conditions
  - Evidence: nesdev.org race condition specification
  - Solution: Created VBlankLedger with cycle tracking
  - Impact: Enables correct race condition handling

#### Hypotheses Tested

1. **Hypothesis:** VBlank flag not clearing on $2002 read
   - **Test:** Added `state.status.vblank = false;`
   - **Result:** ✅ Fixed 17 tests

2. **Hypothesis:** Need separate NMI latch vs readable flag
   - **Test:** Implemented VBlankLedger architecture
   - **Result:** ✅ Allows edge persistence separate from readable flag

#### Next Steps

- [x] Complete VBlank migration phases 1-4
- [x] Test with Bomberman (commercial ROM)
- [x] Verify SMB still broken (different issue)

#### References

- `docs/archive/sessions-2025-10-09-10/vblank-flag-clear-bug-2025-10-09.md`
- Commit: `6db2b2b`

---

### Session: 2025-10-10 14:00 - VBlank Migration Phase 2

**Duration:** 3 hours
**Focus:** Make readRegister() query ledger for VBlank flag

#### What Was Investigated

- File: `src/ppu/logic/registers.zig:72-100` (readRegister $2002 handler)
- File: `src/emulation/state/VBlankLedger.zig:162-180` (isReadableFlagSet)
- Updated 8 call sites to pass ledger and cycle parameters

#### Findings

- **Finding 1:** $2002 handler must query ledger, not PpuState
  - Evidence: Race condition requires timestamp comparison
  - Location: `src/ppu/logic/registers.zig:77`
  - Change: `vblank_ledger.isReadableFlagSet(current_cycle)`

- **Finding 2:** Side effect recording must happen in ledger
  - Evidence: Ledger tracks `last_status_read_cycle`
  - Location: `src/ppu/logic/registers.zig:89`
  - Change: `vblank_ledger.recordStatusRead(current_cycle)`

#### Hypotheses Tested

1. **Hypothesis:** Reading on set cycle should suppress NMI
   - **Test:** `isReadableFlagSet()` checks `current_cycle == last_set_cycle`
   - **Result:** ✅ Race condition handled correctly

2. **Hypothesis:** SMB will work after migration
   - **Test:** Ran SMB after Phase 2 complete
   - **Result:** ❌ Still blank screen (different issue)

#### Next Steps

- [x] Complete Phases 3-4 (remove PpuState.vblank field)
- [ ] Investigate SMB NMI handler execution
- [ ] Add test for multi-frame initialization

#### References

- `docs/archive/sessions-2025-10-09-10/vblank-migration-phase2-milestone-2025-10-10.md`
- Commit: `c713862`

---

### Session: 2025-10-10 18:00 - NMI Handler Investigation

**Duration:** 2 hours
**Focus:** Trace SMB NMI handler execution, identify stuck loop

#### What Was Investigated

- SMB ROM analysis with `xxd` at NMI vector
- CPU trace logging during NMI handler
- Handler loop at `0x8E6C-0x8E79` (countdown loop)

#### Findings

- **Finding 1:** NMI fires correctly, handler executes
  - Evidence: Trace shows PC jump to `0x8082` (handler entry)
  - Location: VBlankLedger sets `nmi_edge_pending` at 241.1
  - Impact: NMI mechanism works, not a timing bug

- **Finding 2:** Handler stuck in countdown loop
  - Evidence: PC loops `0x8E6C → 0x8E79 → 0x8E6C` indefinitely
  - Location: DEY + BNE loop structure
  - Impact: Loop never terminates, handler never returns

- **Finding 3:** Loop disassembly shows data processing
  - Evidence: LDA abs,X / STA zp / LSR / ORA / ROL pattern
  - Location: Processing table data indexed by Y register
  - Impact: Either Y too large or loop body corrupting state

#### Hypotheses Tested

1. **Hypothesis:** NMI not firing (timing bug)
   - **Test:** Added trace logging for NMI edge
   - **Result:** ❌ NMI fires correctly, handler executes

2. **Hypothesis:** Handler never completes
   - **Test:** Traced PC during handler
   - **Result:** ✅ Handler stuck at countdown loop

#### Next Steps

- [ ] Break at loop entry, dump Y register value
- [ ] Identify memory addresses accessed in loop
- [ ] Compare with known-good SMB execution
- [ ] Test DEY instruction in isolation

#### References

- `docs/sessions/smb-nmi-handler-investigation.md`
- Commit: `3540396` (NMI edge persistence fix)

---

### Session: 2025-10-12 10:00 - Test Harness Improvements

**Duration:** 2 hours
**Focus:** Add deterministic helpers for VBlank staging and ledger snapshots

#### What Was Investigated

- File: `tests/test/TestHarness.zig` (added helper functions)
- Test: BIT $2002 timing with VBlank staging
- Test: SMB regression harness with frame-by-frame logging

#### Findings

- **Finding 1:** BIT timing shows immediate flag clear after execute
  - Evidence: Flag cleared on cycle after $2002 read
  - Location: Matches hardware behavior
  - Impact: Need CPU microcode cross-check to verify ordering

- **Finding 2:** SMB disables NMI after first handler
  - Evidence: `last_status_read_cycle` never advances
  - Location: Handler writes PPUCTRL=0x10 (NMI disable)
  - Impact: Confirms handler stuck, never re-enables NMI

#### Hypotheses Tested

1. **Hypothesis:** Test harness timing unreliable
   - **Test:** Added `forceVBlankStart()` and `runPpuTicks()` helpers
   - **Result:** ✅ Tests now deterministic

2. **Hypothesis:** SMB waiting for multiple VBlanks
   - **Test:** Frame-by-frame trace of PPUCTRL/PPUMASK writes
   - **Result:** ❌ Only one NMI handler execution, then stuck

#### Next Steps

- [ ] Cross-check BIT CPU microcode with snapshots
- [ ] Compare SMB trace with known-good capture
- [ ] Update legacy NMI tests to use new harness helpers

#### References

- `docs/sessions/2025-10-12-bit-nmi-harness-notes.md`
- `tests/integration/smb_vblank_reproduction_test.zig`

---

### Session: 2025-10-12 14:00 - (NEXT SESSION)

**Duration:** TBD
**Focus:** Break at NMI handler loop, dump registers

#### What Was Investigated

(To be filled after session)

#### Findings

(To be filled after session)

#### Hypotheses Tested

(To be filled after session)

#### Next Steps

(To be filled after session)

#### References

(To be filled after session)

---

## References

### Documentation

- **KNOWN-ISSUES.md:** Comprehensive known issues list
- **CLAUDE.md:** Project overview and architecture
- **docs/sessions/smb-investigation-plan.md:** Original SMB investigation plan
- **docs/sessions/smb-nmi-handler-investigation.md:** NMI handler findings

### Archive Documents

- **docs/archive/sessions-2025-10-09-10/vblank-flag-clear-bug-2025-10-09.md**
- **docs/archive/sessions-2025-10-09-10/vblank-flag-race-condition-2025-10-10.md**
- **docs/archive/sessions-2025-10-09-10/vblank-migration-phase1-milestone-2025-10-10.md**
- **docs/archive/sessions-2025-10-09-10/vblank-migration-phase2-milestone-2025-10-10.md**

### NES Hardware References

- **nesdev.org/wiki/PPU_registers** - $2002 PPUSTATUS specification
- **nesdev.org/wiki/NMI** - NMI timing and race conditions
- **nesdev.org/wiki/PPU_frame_timing** - VBlank scanline timing
- **nesdev.org/wiki/PPU_power_up_state** - PPU warm-up period

### Implementation Files

- **src/emulation/state/VBlankLedger.zig** - Timestamp-based VBlank tracking
- **src/ppu/logic/registers.zig** - PPU register read/write handlers
- **src/emulation/cpu/execution.zig** - NMI edge detection and CPU stepping
- **tests/ppu/vblank_behavior_test.zig** - VBlank timing tests
- **tests/integration/smb_vblank_reproduction_test.zig** - SMB-specific reproduction

---

**Document Status:** Living document, update after each investigation session
**Last Updated:** 2025-10-12
**Next Review:** After Phase 2 complete (timing analysis)
