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
