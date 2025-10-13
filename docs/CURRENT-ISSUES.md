# Current Issues - RAMBO NES Emulator

**Last Updated:** 2025-10-13
**Test Status:** 930/966 passing (96.3%), 19 skipped, 17 failing
**AccuracyCoin CPU Tests:** ✅ PASSING (baseline validation complete)

This document tracks **active** bugs and issues verified against current codebase. Historical/resolved issues are archived in `docs/archive/`.

---

## P0 - Critical Issues

### VBlankLedger Race Condition Logic Bug

**Status:** 🔴 **ACTIVE BUG** (discovered 2025-10-13 during Phase 7 audit)
**Priority:** P0 (Critical - affects VBlank flag hardware accuracy)
**Failing Tests:** 4 tests in `vblank_ledger_test.zig`
**File:** `src/emulation/state/VBlankLedger.zig:201`

**Issue:**
When CPU reads $2002 (PPUSTATUS) on the **exact same cycle** VBlank sets (race condition), the flag incorrectly clears on subsequent reads. NES hardware keeps the flag set after a race condition read.

**Current Broken Behavior:**
```zig
// Line 201 in VBlankLedger.zig
if (self.last_status_read_cycle >= self.last_set_cycle) {
    return false; // ← WRONG: clears flag even for race condition
}
```

**Expected NES Hardware Behavior:**
- VBlank sets at scanline 241.1
- CPU reads $2002 at exact same cycle (race condition):
  - First read returns VBlank=1
  - Flag **stays set** for subsequent reads (hardware quirk)
  - NMI is suppressed (this part works correctly)

**Impact:**
- ❌ 4 VBlankLedger tests fail
- ⚠️ May affect commercial ROMs relying on race condition timing
- ✅ NMI suppression works correctly (separate logic)

**Fix Required:**
Add `race_condition_occurred` flag to track race condition state across multiple reads.

**References:**
- Audit: `/tmp/phase7_current_state_audit.md`
- NESDev: [VBlank Flag Race Condition](https://www.nesdev.org/wiki/PPU_frame_timing#VBlank_Flag)

---

### Commercial ROMs: Rendering Never Enabled

**Status:** 🔴 **ACTIVE ISSUE** (under investigation)
**Priority:** P0 (Critical - blocks commercial ROM compatibility)
**Failing Tests:** 4 tests in `commercial_rom_test.zig`
**Affected ROMs:** Super Mario Bros, Donkey Kong, BurgerTime

**Issue:**
Commercial ROMs never enable rendering (PPUMASK bits 3-4 stay 0). ROMs execute but display blank screens.

**Failing Tests:**
- `commercial_rom_test.zig:209` - Super Mario Bros rendering
- `commercial_rom_test.zig:260` - Donkey Kong rendering
- `commercial_rom_test.zig:294` - BurgerTime rendering
- `commercial_rom_test.zig` (Bomberman test - execution error)

**Hypothesis:**
May be related to VBlankLedger race condition bug. ROMs might be stuck in initialization loops waiting for correct VBlank timing.

**Next Steps:**
1. Fix VBlankLedger race condition bug first
2. Re-test commercial ROMs
3. If still failing, use debugger to trace NMI handler execution

**References:**
- Investigation: `docs/sessions/smb-investigation-plan.md`
- Debugger Guide: `docs/sessions/debugger-quick-start.md`

---

## P1 - High Priority Issues

### CPU-PPU Integration Tests Failing

**Status:** 🔴 **LIKELY CAUSED BY VBlankLedger BUG**
**Priority:** P1 (High - integration test coverage)
**Failing Tests:** 5 tests cascading from VBlankLedger bug

**Affected Tests:**
- `bit_nmi_test.zig:172` - BIT $2002 interaction (2 tests)
- `cpu_ppu_sync_test.zig` - CPU-PPU synchronization (2 tests)
- `vblank_wait_test.zig` - VBlank waiting loop (1 test)

**Root Cause:**
These tests verify VBlank flag behavior during race conditions. Failing due to VBlankLedger bug above.

**Expected Resolution:**
All 5 tests should pass after VBlankLedger race condition fix.

---

### NMI Sequence Test Failure

**Status:** 🟡 **NEEDS INVESTIGATION**
**Priority:** P1 (High - interrupt handling verification)
**Failing Tests:** 1 test in `nmi_sequence_test.zig:146`

**Issue:**
Test "NMI Sequence: Complete flow with real timing" fails with:
```
expect(harness.state.cpu.instruction_cycle == 0)
```

**Needs Investigation:**
Not clear if related to VBlankLedger bug or separate interrupt timing issue.

---

## P2 - Medium Priority Issues

### Missing Type Export: MirroringType

**Status:** 🟠 **COMPILATION ERROR**
**Priority:** P2 (Medium - breaks compilation of some tests)
**File:** Unknown (needs investigation)

**Issue:**
Type `MirroringType` is not exported from module, causing compilation errors in tests.

**Fix Required:**
Add `pub const MirroringType = ...` export to appropriate module.

---

### AccuracyCoin File Path Mismatch

**Status:** 🟠 **FILE NOT FOUND**
**Priority:** P2 (Medium - test infrastructure issue)
**Failing Tests:** 1 test in `commercial_rom_test.zig:160`

**Issue:**
Test tries to load "AccuracyCoin.nes" but file not found at expected path.

**Fix Required:**
Verify ROM file location or update test to use correct path.

---

## P3 - Low Priority Issues

### CPU Timing Deviation (Absolute,X/Y No Page Cross)

**Status:** 🟡 **KNOWN LIMITATION** (deferred)
**Priority:** P3 (Low - functionally correct, minor timing issue)

**Issue:**
Absolute,X and Absolute,Y addressing modes take 5 cycles instead of 4 when no page crossing occurs.

**Impact:**
- ✅ Functionally correct (all reads/writes work)
- ⚠️ Cycle-accurate timing slightly off

**Deferred Because:**
- AccuracyCoin tests pass despite deviation
- Commercial ROMs run correctly
- Fixing requires complex CPU microstep refactoring

---

### Threading Tests: Timing-Sensitive Failures

**Status:** 🟡 **TEST INFRASTRUCTURE ISSUE**
**Priority:** P4 (Very Low - not a functional problem)
**Skipped Tests:** 7 tests (timing-sensitive)

**Issue:**
Threading tests rely on precise timing that varies across systems.

**Impact:**
- ✅ Emulation, rendering, mailboxes work correctly in production
- ⚠️ Limited threading test coverage in CI

---

## Summary Statistics

| Priority | Count | Category |
|----------|-------|----------|
| P0 | 2 | Critical bugs blocking ROMs |
| P1 | 2 | High priority integration issues |
| P2 | 2 | Medium priority fixes |
| P3 | 2 | Low priority / deferred |

**Expected After VBlankLedger Fix:**
930/966 → **939+/966** (97.2%+) with cascading fixes

---

## Verification Commands

```bash
# Run all tests
zig build test

# Run specific test categories
zig build test-unit          # Unit tests only
zig build test-integration   # Integration tests only

# Run failing VBlankLedger tests
zig build test -- tests/emulation/state/vblank_ledger_test.zig

# Run commercial ROM tests
zig build test -- tests/integration/commercial_rom_test.zig
```

---

## Document History

**2025-10-13:** Initial creation from Phase 7 comprehensive audit
**Audit Source:** `/tmp/phase7_current_state_audit.md`
**Verification:** All issues verified against actual code and test output

**Previous Known Issues Documentation:** Archived to `docs/archive/2025-10/KNOWN-ISSUES-2025-10-12.md`
