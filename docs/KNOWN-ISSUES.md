# Known Issues

This document tracks known bugs and limitations that are **intentionally deferred** or **out of scope** for current development efforts.

---

## PPU: $2002 VBlank Flag Clear Bug

**Status:** 🔴 Known Issue (Out of Scope for Refactoring)
**Priority:** P1 (High - blocks commercial ROM compatibility)
**Discovered:** 2025-10-09 during test audit
**Affects:** Commercial ROMs (Bomberman confirmed)

### Description

Reading PPUSTATUS register ($2002) **does not clear the VBlank flag** as required by NES hardware specification.

**Expected Behavior (Hardware):**
```
1. VBlank flag sets at scanline 241, dot 1
2. CPU reads $2002 → returns VBlank flag (bit 7 = 1)
3. VBlank flag IMMEDIATELY clears after read
4. Subsequent $2002 reads return 0 for bit 7 (until next VBlank)
```

**Actual Behavior (Current Implementation):**
```
1. VBlank flag sets at scanline 241, dot 1 ✅ CORRECT
2. CPU reads $2002 → returns VBlank flag (bit 7 = 1) ✅ CORRECT
3. VBlank flag PERSISTS after read ❌ BUG
4. Subsequent $2002 reads continue returning VBlank=1 ❌ BUG
```

### Impact

**Commercial ROM Compatibility:**
- **Bomberman (US)**: Hangs during gameplay - game polls $2002 waiting for VBlank to clear, loops forever
- **Other ROMs**: Any game using VBlank polling pattern may hang or exhibit timing issues

**Test Failures:**
- `tests/ppu/ppustatus_polling_test.zig:153` - "Multiple polls within VBlank period"
- `tests/ppu/ppustatus_polling_test.zig:308` - "BIT instruction timing - when does read occur?"

### Root Cause

**File:** `src/ppu/Logic.zig`
**Function:** `readRegister()`
**Location:** Case 0x0002 (PPUSTATUS register read)

```zig
// Current implementation (INCORRECT):
pub fn readRegister(state: *PpuState, address: u16) u8 {
    return switch (address & 0x0007) {
        0x0002 => blk: { // PPUSTATUS ($2002)
            const status = state.status.toByte();
            // BUG: Missing state.status.vblank = false;
            break :blk status;
        },
        // ...
    };
}
```

**Required Fix:**
```zig
pub fn readRegister(state: *PpuState, address: u16) u8 {
    return switch (address & 0x0007) {
        0x0002 => blk: { // PPUSTATUS ($2002)
            const status = state.status.toByte();
            state.status.vblank = false;  // ← ADD THIS LINE
            break :blk status;
        },
        // ...
    };
}
```

### Why Deferred

This bug is **OUT OF SCOPE** for the current EmulationState decomposition refactoring (2025-10-09 through 2025-10-29) because:

1. **Focus:** Refactoring is non-functionality changing - only restructuring code
2. **Risk:** Fixing this bug requires changing PPU behavior, which could introduce regressions
3. **Testing:** Need comprehensive validation of commercial ROMs after fix
4. **Timing:** Better to fix after refactoring is complete and code is stabilized

### Failing Tests (PRESERVED)

The following tests **intentionally fail** and **must be preserved** to prevent regression when this bug is eventually fixed:

#### Test 1: Multiple Polls Within VBlank Period
**File:** `tests/ppu/ppustatus_polling_test.zig:153`
**Purpose:** Validates that reading $2002 clears VBlank flag
**Expected:** Flag clears on first read, subsequent reads return 0
**Actual:** Flag persists across multiple reads

**DO NOT DELETE THIS TEST** - It correctly validates hardware behavior

#### Test 2: BIT Instruction Timing
**File:** `tests/ppu/ppustatus_polling_test.zig:308`
**Purpose:** Validates cycle-accurate timing of $2002 read within BIT instruction execution
**Expected:** VBlank flag clears during BIT instruction's read cycle
**Actual:** VBlank flag persists after BIT instruction completes

**DO NOT DELETE THIS TEST** - It validates instruction-level timing accuracy

### Coverage

These are the **ONLY** tests that validate $2002 VBlank clear behavior. Deleting them would:
- ❌ Remove critical hardware behavior validation
- ❌ Allow regression when bug is eventually fixed
- ❌ Reduce commercial ROM compatibility coverage

### Validation Plan (When Fixed)

When this bug is fixed (post-refactoring), validation must include:

1. **Unit Tests:** Both preserved tests must pass
2. **Integration Tests:**
   - Run Bomberman (US) for 10 seconds without hanging
   - Run full AccuracyCoin test suite
3. **Regression Testing:** Full test suite must pass (≥99%)
4. **Commercial ROM Testing:** Test at least 5 commercial ROMs with VBlank polling

### References

- **NESDev Wiki:** [PPUSTATUS ($2002)](https://www.nesdev.org/wiki/PPU_registers#PPUSTATUS)
- **Hardware Behavior:** "Reading the status register will clear D6 and return the old status of the NMI_occurred flag in D7"
- **Test Files:** `tests/ppu/ppustatus_polling_test.zig`
- **Investigation:** `docs/refactoring/failing-tests-analysis-2025-10-09.md` (Tests #7, #8)

---

## Emulation: Odd Frame Skip Not Implemented

**Status:** 🟡 Known Issue (Deferred - Timing Architecture)
**Priority:** P2 (Medium - affects timing accuracy, not functionality)
**Discovered:** 2025-10-09 during Phase 0-B test analysis
**Affects:** Cycle-accurate timing tests

### Description

The NES hardware skips dot 0 of scanline 0 on odd frames when rendering is enabled. The emulator detects this condition but does not correctly skip the clock position, only PPU processing.

**Expected Behavior (Hardware):**
```
Odd frame with rendering enabled:
- Scanline 261, dot 340 → tick() → Scanline 0, dot 1 (dot 0 skipped)
- Clock advances by 2 PPU cycles instead of 1
```

**Actual Behavior (Current Implementation):**
```
Odd frame with rendering enabled:
- Scanline 261, dot 340 → tick() → Scanline 0, dot 0
- Clock advances by 1, then PPU processing is skipped
- Net result: clock is at 0.0, not 0.1
```

### Impact

**Functional Impact:** ✅ Minimal - ROMs work correctly, only timing off by 1 cycle per frame
**Timing Impact:** ⚠️ Odd frames are 1 cycle too long (89,342 instead of 89,341)
**Test Failures:**
- `src/emulation/State.zig:2138` - "odd frame skip when rendering enabled"

### Root Cause

**File:** `src/emulation/State.zig`
**Function:** `tick()` (lines 668-698)
**Location:** Lines 678-688

```zig
// Current implementation (INCORRECT):
self.clock.advance(1); // Always advances by 1

const skip_odd_frame = self.odd_frame and self.rendering_enabled and
    self.clock.scanline() == 0 and self.clock.dot() == 0;

if (!skip_odd_frame) {
    // Process PPU at current clock position
    // ...
}
// Problem: Clock is at 0.0, but should be at 0.1
```

### Why Deferred

This requires **architectural changes** to the MasterClock timing model:

1. **Timing Invariant**: Current design has `tick()` always advance by exactly 1 cycle (line 673 comment)
2. **Fix Requires**: Conditional advance (1 or 2 cycles) based on pre-advance state
3. **Architectural Risk**: Part of larger PPU/clock decoupling work (see ADR-001)
4. **User Guidance**: "This is part of decoupling the ppu acting as the primary reference and advancing the clock, this should only ever be done once in a tick"

**Better to fix during Phase 2** when doing MasterClock/PPU architectural refactoring.

### Proposed Fix (For Phase 2)

```zig
pub fn tick(self: *EmulationState) void {
    if (self.debuggerShouldHalt()) return;

    // Determine advance amount BEFORE advancing
    const at_frame_boundary = self.clock.scanline() == 261 and
                             self.clock.dot() == 340;
    const will_skip_odd_frame = at_frame_boundary and
                               self.odd_frame and
                               self.rendering_enabled;

    // Advance by 2 if skipping, 1 otherwise (still only ONE advance call)
    self.clock.advance(if (will_skip_odd_frame) 2 else 1);

    // Rest of tick() unchanged...
}
```

### Failing Test (PRESERVED)

**File:** `src/emulation/State.zig:2138`
**Purpose:** Validates odd frame skip behavior
**Expected:** After tick from 261.340 → should be at 0.1
**Actual:** After tick from 261.340 → at 0.0

**DO NOT DELETE THIS TEST** - It correctly validates hardware behavior

### References

- **NESDev Wiki:** [PPU Frame Timing](https://www.nesdev.org/wiki/PPU_frame_timing)
- **Hardware Behavior:** "On odd frames with rendering enabled, the PPU skips the first idle cycle of the first visible scanline"
- **Investigation:** `docs/refactoring/failing-tests-analysis-2025-10-09.md` (Test #1)
- **Architectural Context:** Phase 0-B analysis (2025-10-09)

---

## PPU: AccuracyCoin Rendering Detection

**Status:** 🟡 Known Issue (Deferred - Requires Investigation)
**Priority:** P2 (Medium - test quality issue, ROM runs)
**Discovered:** 2025-10-09 during Phase 0-B test analysis
**Affects:** AccuracyCoin test ROM validation

### Description

The AccuracyCoin test ROM never sets `rendering_enabled` flag to `true` within the first 300 frames, causing a diagnostic test to fail.

**Expected Behavior:**
```
AccuracyCoin ROM should enable rendering within first 300 frames
- Test checks frames: 1, 5, 10, 30, 60, 120, 180, 240, 300
- rendering_enabled should become true at some point
```

**Actual Behavior:**
```
rendering_enabled remains false through all 300 frames
- Test fails at line 166: expect(rendering_enabled_frame != null)
```

### Impact

**Functional Impact:** ✅ None - AccuracyCoin tests pass (939/939 CPU opcode tests)
**ROM Execution:** ✅ ROM runs correctly, actual validation works
**Test Quality:** ⚠️ Diagnostic test cannot verify rendering initialization timing

**Test Failures:**
- `tests/integration/accuracycoin_execution_test.zig:166` - "Compare PPU initialization sequences"

### Root Cause

**Unknown** - Requires investigation. Possible causes:

1. **PPU Warmup Period**: PPU ignores writes for first 29,658 cycles - might affect rendering enable detection
2. **Rendering Enable Detection**: Flag might not be set correctly from PPUMASK ($2001) writes
3. **VBlank Timing**: Related to VBlank $2002 bug (rendering might not be detected during VBlank issues)
4. **Test Expectations**: ROM might genuinely not enable rendering until after frame 300

### Why Deferred

**Requires debugging investigation:**
1. Need to trace AccuracyCoin ROM execution to see when/if it writes to $2001
2. Need to verify `rendering_enabled` flag is set correctly from PPUMASK
3. Potentially related to VBlank $2002 bug (already documented as out of scope)
4. Core AccuracyCoin validation (939 opcode tests) all pass - this is diagnostic only

**Better to investigate** after VBlank $2002 bug is fixed and PPU/clock decoupling is complete.

### Investigation Required

```bash
# When investigating (Phase 2+):
# 1. Add logging to track PPUMASK ($2001) writes
# 2. Check if rendering_enabled flag is set from PPUMASK correctly
# 3. Extend frame limit to 500 or 1000 to see if it ever enables
# 4. Trace AccuracyCoin ROM to understand its initialization sequence
```

### Failing Test (PRESERVED)

**File:** `tests/integration/accuracycoin_execution_test.zig:166`
**Purpose:** Diagnostic test to compare PPU initialization timing
**Expected:** rendering_enabled becomes true within 300 frames
**Actual:** rendering_enabled stays false through 300 frames

**DO NOT DELETE THIS TEST** - It provides diagnostic information about ROM behavior

### References

- **ROM:** AccuracyCoin.nes (gold standard CPU test ROM)
- **Test File:** `tests/integration/accuracycoin_execution_test.zig`
- **Investigation:** `docs/refactoring/failing-tests-analysis-2025-10-09.md` (Test #13)
- **Architectural Context:** Phase 0-B analysis (2025-10-09)

---

## CPU: Absolute,X/Y Timing Deviation (Low Priority)

**Status:** 🟡 Known Limitation (Deferred)
**Priority:** P3 (Low - functionally correct, minor timing issue)

### Description

Absolute,X and Absolute,Y addressing modes have a +1 cycle deviation when **no page crossing occurs**.

**Hardware Timing:** 4 cycles (dummy read IS the actual read)
**Implementation Timing:** 5 cycles (separate addressing + execute states)

### Impact

**Functional Impact:** ✅ None - reads are correct, just slower by 1 cycle
**Timing Impact:** ⚠️ Minor - cycle-accurate timing slightly off for these instructions

### Why Deferred

- Functionally correct (all reads/writes work correctly)
- Fixing requires CPU microstep refactoring (complex change)
- AccuracyCoin test suite passes despite this deviation
- Commercial ROMs run correctly

### References

- **CLAUDE.md:** Known Issues section
- **Priority:** Defer to post-playability phase

---

## Threading: Timing-Sensitive Test Failures (Low Priority)

**Status:** 🟡 Test Infrastructure Issue
**Priority:** P4 (Very Low - not a functional problem)

### Description

1 of 14 threading tests fails intermittently in some environments due to timing sensitivity. 7 threading tests are skipped.

**Test Results:** 13/14 passing, 7 skipped

### Impact

**Functional Impact:** ✅ None - emulation, rendering, and mailboxes work correctly
**Test Coverage:** ⚠️ Threading edge cases not fully validated in CI

### Root Cause

Tests rely on precise timing of thread startup/shutdown which varies across systems, CPUs, and schedulers.

### Why Deferred

- Not a functional bug in emulation code
- Test infrastructure issue, not emulator issue
- Mailboxes work correctly in production (validated by visual testing)
- Fixing requires robust test synchronization primitives

---

## Document Metadata

**Created:** 2025-10-09
**Last Updated:** 2025-10-09
**Related Documents:**
- `docs/refactoring/failing-tests-analysis-2025-10-09.md`
- `docs/refactoring/emulation-state-decomposition-2025-10-09.md`
- `docs/CURRENT-STATUS.md`

**Maintenance:**
- Update this document when new known issues are discovered
- Remove entries when issues are fixed
- Keep issue count in `docs/CURRENT-STATUS.md` synchronized
