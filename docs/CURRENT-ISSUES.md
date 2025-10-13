# Current Issues - RAMBO NES Emulator

**Last Updated:** 2025-10-13
**Test Status:** 930/966 passing (96.3%), 19 skipped, 17 failing
**AccuracyCoin CPU Tests:** ✅ PASSING (baseline validation complete)

This document tracks **active** bugs and issues verified against current codebase. Historical/resolved issues are archived in `docs/archive/`.

---

## P0 - Critical Issues

### VBlankLedger Race Condition Logic Bug

**Status:** ✅ **RESOLVED** (2025-10-14)
**Priority:** —
**Root Cause:** Test suite expected incorrect hardware behavior

**Summary:**
NESDev documentation states that reading $2002 on the same PPU clock **or the immediately following clock** returns the flag as set, clears it, and suppresses NMI for that frame. RAMBO already implemented this behavior (flag clears, NMI suppressed), but several unit tests and docs still assumed the flag should remain set through the frame. The failing tests were updated to match the hardware spec, and `shouldNmiEdge` now suppresses NMIs for reads occurring on either of the first two cycles after VBlank sets.

**References:**
- NESDev: [PPU frame timing – VBlank flag](https://www.nesdev.org/wiki/PPU_frame_timing#VBlank_Flag)
- Session log: `docs/sessions/2025-10-14-smb-integration-session.md`

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

**Status Update:**
VBlankLedger expectations have been realigned with hardware (2025-10-14). Commercial ROM tests still need to be re-run to confirm whether rendering now enables correctly.

**Next Steps:**
1. Re-run commercial ROM integration tests on the updated baseline
2. If still failing, use debugger to trace SMB’s NMI handler during initialization

**References:**
- Investigation: `docs/sessions/smb-investigation-plan.md`
- Debugger Guide: `docs/sessions/debugger-quick-start.md`

---

## P1 - High Priority Issues

### CPU-PPU Integration Tests Failing

**Status:** 🟡 **RETEST REQUIRED**
**Priority:** P1 (High - integration test coverage)
**Failing Tests:** Previously 5 tests cascading from the outdated VBlankLedger expectation

**Affected Tests:**
- `bit_nmi_test.zig:172` - BIT $2002 interaction (2 tests)
- `cpu_ppu_sync_test.zig` - CPU-PPU synchronization (2 tests)
- `vblank_wait_test.zig` - VBlank waiting loop (1 test)

**Root Cause:**
Tests verified the old "flag-stays-set" interpretation. They should pass once re-run with the corrected expectations.

**Action:**
Re-run the affected integration tests and update this entry with fresh results.

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
| P0 | 1 | Critical bug blocking commercial ROMs |
| P1 | 2 | High priority integration issues |
| P2 | 2 | Medium priority fixes |
| P3 | 2 | Low priority / deferred |

**Progress:**
VBlankLedger race-condition expectations reconciled with hardware documentation; focus now shifts to commercial ROM rendering enablement.

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
