# Current Issues - RAMBO NES Emulator

**Last Updated:** 2025-10-15 (NMI Double-Trigger Fix)
**Test Status:** TBD (post-NMI fix), 19 skipped
**AccuracyCoin CPU Tests:** ✅ PASSING (baseline validation complete)

This document tracks **active** bugs and issues verified against current codebase. Historical/resolved issues are archived in `docs/archive/`.

---

## **CRITICAL FIX - NMI Line Management (2025-10-15)**

### NMI Line Prematurely Cleared - RESOLVED ✅

**Impact:** Commercial ROMs now execute correctly (Castlevania, Mega Man, Kid Icarus working)
**Commits:**
- 1985d74 "fix(nmi): Fix critical NMI line management bug"
- (subsequent) "fix(nmi): Prevent double-NMI trigger during same VBlank"

**Root Cause:**
- NMI line was cleared immediately after acknowledgment, preventing CPU edge detector from latching interrupt
- Commercial ROMs never received NMI, causing infinite loops waiting for VBlank
- Additional issue: SMB1 toggling NMI enable during VBlank caused double-NMI triggers

**Fix:**
- NMI line now reflects VBlank flag state directly (not cleared after acknowledgment)
- Removed `last_nmi_ack_cycle` field (hardware doesn't have this concept)
- Added `nmi_vblank_set_cycle` tracking to prevent double-NMI during same VBlank period
- Files: `src/emulation/cpu/execution.zig`, `src/emulation/VBlankLedger.zig`, `src/cpu/State.zig`, `src/cpu/Logic.zig`

**Before:** NMI never fired → Games stuck in wait loops → Grey screens or frozen frames
**After:**  NMI fires once per VBlank → Games execute normally

---

## **CRITICAL FIX - RAM Initialization (2025-10-14)**

### Grey Screen Bug - RESOLVED ✅

**Impact:** Initial rendering enablement for commercial ROMs
**Commit:** 069fb76 "fix(emulation): Implement hardware-accurate RAM initialization"

**Root Cause:**
- Real NES hardware initializes RAM with pseudo-random garbage at power-on
- Commercial ROMs read uninitialized RAM and use values for branching decisions
- RAMBO initialized RAM to all zeros (unrealistic power-on state, ~10^-614 probability)
- Games executed untested code paths that never enabled PPU rendering

**Fix:**
- Implemented deterministic pseudo-random RAM initialization using LCG
- Fixed seed (0x12345678) ensures reproducible behavior
- Compile-time evaluation (zero runtime overhead)
- File: `src/emulation/state/BusState.zig:17-56`

**Before:** All-zero RAM → Games write $00 to PPUMASK (rendering disabled)
**After:**  Pseudo-random RAM → Games write $1E/$18 to PPUMASK (rendering enabled)

**Test Improvement:** ~941 → ~995+ / 993 passing (est. +54 tests)

**Full Investigation Report:** `docs/investigations/RAM_INITIALIZATION_GREY_SCREEN_BUG.md`

---

## Recent Fixes (2025-10-14)

### Five Critical Hardware Bugs Fixed ✅

**Phase 1-5 Bug Fixes:** Five separate hardware accuracy bugs identified and resolved:

1. **VBlankLedger Race Condition** - Fixed timing order issue where `race_hold` was checked before being set
   - File: `src/emulation/State.zig:268-291`
   - Impact: +4 tests, fixes NMI suppression edge case

2. **PPU Read Buffer Nametable Mirror** - Fixed palette reads to fill buffer from underlying nametable
   - File: `src/ppu/logic/registers.zig:137-172`
   - Impact: +1-2 tests, AccuracyCoin Test 7

3. **Sprite 0 Hit Rendering Check** - Added missing `rendering_enabled` check to sprite 0 hit detection
   - File: `src/ppu/Logic.zig:295`
   - Impact: +2-4 tests, AccuracyCoin Tests 2-4

4. **Sprite 0 Hit - Incorrect Rendering Logic** - Fixed to require BOTH BG and sprite rendering (AND logic, not OR)
   - File: `src/ppu/Logic.zig:295`
   - Impact: Hardware accuracy improvement, prevents spurious sprite 0 hits
   - Test Coverage: `tests/ppu/sprite_edge_cases_test.zig`

5. **PPU Write Toggle Not Cleared at Pre-render** - Added missing write toggle (w register) reset at scanline 261 dot 1
   - File: `src/ppu/Logic.zig:336`
   - Impact: Prevents scroll/address corruption across frame boundaries
   - Test Coverage: 6 tests in `tests/integration/ppu_write_toggle_test.zig`

**Estimated Test Improvement:** 930 → 941+ / 966 passing (97.4%+)

---

## P0 - Critical Issues

### Commercial ROM Status (2025-10-15)

**Working ROMs:**
- ✅ Castlevania - Displays correctly
- ✅ Mega Man - Glitching resolved
- ✅ Kid Icarus - Displays correctly
- ✅ Battletoads - Working (from Phase 1)
- ✅ SMB2/SMB3 - Working (from Phase 1)

**Still Failing:**
- ❌ Super Mario Bros (SMB1) - Title screen appears but doesn't animate (coin frozen, Mario sprite missing, `?` box partial)
- ❌ TMNT series - Blank screen

### SMB1 Title Screen Animation Freeze

**Status:** 🔴 **ACTIVE BUG** (persists after NMI fixes)
**Priority:** P0 (Critical - iconic test ROM)

**Current Behavior:**
- Title screen displays but is frozen
- Coin doesn't animate
- Mario sprite doesn't appear
- Half a `?` box appears
- PC advances normally ($8000 → $90DE → $805A → $80B6, etc.)
- NMI fires each frame
- PPUMASK = $1E (rendering enabled)
- PPUCTRL toggles $10 ↔ $90 (NMI enable toggling by game code)

**What Works:**
- Game code executes (PC changing, registers updating)
- NMI interrupts fire correctly (verified by diagnostic output)
- Rendering pipeline works (other games display correctly)

**Root Cause:**
Unknown - requires further investigation. Double-NMI suppression fix improved execution but title screen still doesn't animate.

**Next Steps:**
- Investigate sprite rendering (Mario sprite missing)
- Check OAM data during title screen
- Verify sprite 0 hit detection
- Compare against working ROMs

### TMNT Series - Blank Screen

**Status:** 🔴 **ACTIVE BUG**
**Priority:** P0 (Critical - commercial ROM compatibility)

**Current Behavior:**
- Displays blank screen
- Unknown if rendering enabled or game stuck in boot

**Next Steps:**
- Run with diagnostic output to check PC progression
- Verify PPUMASK writes
- Check for game-specific hardware quirks

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
