# Phase 4 Test Impact & Verification Analysis

**Status:** COMPREHENSIVE ANALYSIS COMPLETE
**Date:** 2025-10-13
**Baseline:** 930/966 tests passing (96.3%)
**Risk Level:** MEDIUM - Facade removal + A12 migration affect multiple test files

---

## Executive Summary

Phase 4 introduces two critical changes:
1. **Facade Removal:** Delete `src/emulation/Ppu.zig` (PpuRuntime wrapper)
2. **A12 Migration:** Move `ppu_a12_state` from EmulationState to PpuState

This analysis identifies **21 test files** directly affected by TestHarness changes, **1 snapshot test** affected by serialization changes, and **0 tests** directly checking A12 state (good news!). The primary impact is through the TestHarness API which wraps PpuRuntime.

**Critical Finding:** TestHarness in `src/test/Harness.zig` directly imports and uses `PpuRuntime` in 3 methods:
- `tickPpu()` - Line 56-61
- `tickPpuCycles()` - Line 63-65
- `tickPpuWithFramebuffer()` - Line 67-72
- `resetPpu()` - Line 97-101 (also accesses `ppu_a12_state`)

**Risk Assessment:**
- **HIGH RISK:** TestHarness methods must be updated (21 tests depend on them)
- **MEDIUM RISK:** Snapshot deserialization initializes `ppu_a12_state` (1 test)
- **LOW RISK:** No tests directly access `ppu_a12_state` from EmulationState

---

## 1. Complete Test Inventory

### 1.1 Total Test Files: 77 files (72 test files + 5 helpers)

**By Category:**
- **Unit Tests:** ~40 files (cpu/, ppu/, apu/, bus/, config/, input/)
- **Integration Tests:** 18 files (integration/)
- **Snapshot Tests:** 1 file (snapshot/)
- **Debugger Tests:** 7 files (debugger/)
- **Threading Tests:** 1 file (threads/)
- **Helpers:** 5 files (FramebufferValidator.zig, Harness.zig, etc.)

### 1.2 Tests Using TestHarness: 21 files

**PPU Tests (9 files):**
1. `tests/ppu/chr_integration_test.zig`
2. `tests/ppu/ppustatus_polling_test.zig`
3. `tests/ppu/seek_behavior_test.zig`
4. `tests/ppu/simple_vblank_test.zig`
5. `tests/ppu/sprite_edge_cases_test.zig`
6. `tests/ppu/sprite_evaluation_test.zig` ⚠️ HEAVY USER (19 calls to tickPpu methods)
7. `tests/ppu/sprite_rendering_test.zig`
8. `tests/ppu/vblank_behavior_test.zig`
9. `tests/ppu/vblank_nmi_timing_test.zig`

**Integration Tests (11 files):**
10. `tests/integration/bit_ppustatus_test.zig`
11. `tests/integration/controller_test.zig`
12. `tests/integration/cpu_ppu_integration_test.zig`
13. `tests/integration/dpcm_dma_test.zig`
14. `tests/integration/input_integration_test.zig`
15. `tests/integration/nmi_sequence_test.zig`
16. `tests/integration/oam_dma_test.zig`
17. `tests/integration/ppu_register_absolute_test.zig`
18. `tests/integration/rom_test_runner.zig`
19. `tests/integration/smb_vblank_reproduction_test.zig`
20. `tests/integration/vblank_wait_test.zig`

**CPU Tests (1 file):**
21. `tests/cpu/page_crossing_test.zig`

### 1.3 Tests Directly Checking ppu_a12_state: 0 files ✅

**Finding:** No test files directly access `harness.state.ppu_a12_state` or `state.ppu_a12_state`.

**Evidence:**
```bash
grep -r "ppu_a12_state" tests/  # Returns 0 matches
```

**Implication:** A12 migration has **ZERO direct test impact**. Only indirect impact through:
- TestHarness.resetPpu() (line 100)
- Snapshot deserialization (src/snapshot/Snapshot.zig:250)

### 1.4 Snapshot Tests: 1 file

**File:** `tests/snapshot/snapshot_integration_test.zig`

**Impact:** Snapshot format includes `ppu_a12_state` field. Migration requires:
1. Update deserialization to initialize `ppu.a12_state` (not `state.ppu_a12_state`)
2. Update serialization to read from `ppu.a12_state` (not `state.ppu_a12_state`)

**Tests Affected:**
- `test "Snapshot Integration: Full round-trip without cartridge"` (line 87)
- `test "Snapshot Integration: Full round-trip with cartridge (reference mode)"` (line 152)
- `test "Snapshot Integration: Multiple save/load cycles"` (line 279)
- All other snapshot tests (they all verify round-trip correctness)

---

## 2. Test Verification Matrix

| Test File | Tests Using Harness | Phase 4 Impact | Update Required | Priority |
|-----------|---------------------|----------------|-----------------|----------|
| **PPU Tests** |
| ppu/sprite_evaluation_test.zig | 19 calls to tickPpu* | Facade removal | YES | CRITICAL |
| ppu/vblank_nmi_timing_test.zig | 5 tests | Facade removal | YES | CRITICAL |
| ppu/vblank_behavior_test.zig | Multiple tests | Facade removal | YES | HIGH |
| ppu/seek_behavior_test.zig | Multiple tests | Facade removal | YES | HIGH |
| ppu/ppustatus_polling_test.zig | Multiple tests | Facade removal | YES | HIGH |
| ppu/simple_vblank_test.zig | Multiple tests | Facade removal | YES | HIGH |
| ppu/sprite_rendering_test.zig | Multiple tests | Facade removal | YES | MEDIUM |
| ppu/sprite_edge_cases_test.zig | Multiple tests | Facade removal | YES | MEDIUM |
| ppu/chr_integration_test.zig | Multiple tests | Facade removal | YES | MEDIUM |
| **Integration Tests** |
| integration/nmi_sequence_test.zig | All tests | Facade removal | YES | CRITICAL |
| integration/cpu_ppu_integration_test.zig | All tests | Facade removal | YES | CRITICAL |
| integration/bit_ppustatus_test.zig | All tests | Facade removal | YES | HIGH |
| integration/vblank_wait_test.zig | All tests | Facade removal | YES | HIGH |
| integration/smb_vblank_reproduction_test.zig | All tests | Facade removal | YES | HIGH |
| integration/oam_dma_test.zig | All tests | Facade removal | YES | MEDIUM |
| integration/ppu_register_absolute_test.zig | All tests | Facade removal | YES | MEDIUM |
| integration/controller_test.zig | Some tests | Facade removal | YES | MEDIUM |
| integration/input_integration_test.zig | Some tests | Facade removal | YES | MEDIUM |
| integration/dpcm_dma_test.zig | Some tests | Facade removal | YES | MEDIUM |
| integration/rom_test_runner.zig | Helper code | Facade removal | YES | LOW |
| **CPU Tests** |
| cpu/page_crossing_test.zig | Few tests | Facade removal | YES | LOW |
| **Snapshot Tests** |
| snapshot/snapshot_integration_test.zig | All 11 tests | A12 migration | YES | CRITICAL |
| **Harness Itself** |
| src/test/Harness.zig | N/A | Both changes | YES | CRITICAL |

**Impact Summary:**
- **CRITICAL Priority:** 5 files (Harness + 4 test files)
- **HIGH Priority:** 7 files
- **MEDIUM Priority:** 8 files
- **LOW Priority:** 2 files

**Total Files Requiring Updates:** 23 files (including Harness)

---

## 3. Edge Case Catalog

### 3.1 VBlank/NMI Tests (Known Fragile)

**Tests:**
- `ppu/vblank_nmi_timing_test.zig` - ALL TESTS ⚠️
- `integration/nmi_sequence_test.zig` - ALL TESTS ⚠️
- `integration/cpu_ppu_integration_test.zig` - "Reading PPUSTATUS clears VBlank but preserves latched NMI"

**Why Critical:**
- These tests verify the **exact VBlank race condition fix** (Phase 3)
- They use `harness.seekToScanlineDot()` to position at scanline 241 dot 0/1
- They tick using `harness.state.tick()` (which calls PpuRuntime internally)

**Phase 4 Risk:** HIGH
- If PpuRuntime removal breaks timing, these tests will fail immediately
- Tests expect VBlank flag at specific cycles (241.1)

**Mitigation:**
1. Run these tests FIRST after Harness update
2. If failures occur, check scanline/dot synchronization
3. Verify `EmulationState.tick()` still calls PPU correctly

### 3.2 Reset Behavior Tests

**Tests:**
- Any test calling `harness.resetPpu()` (found: 0 tests currently)
- `src/test/Harness.zig:resetPpu()` accesses `state.ppu_a12_state` (line 100)

**Why Critical:**
- `resetPpu()` explicitly sets `self.state.ppu_a12_state = false`
- After A12 migration, must become `self.state.ppu.a12_state = false`

**Phase 4 Risk:** MEDIUM
- Only affects resetPpu() method (not heavily used)
- Easy to fix (single line change)

**Mitigation:**
1. Update Harness.resetPpu() during A12 migration
2. Verify no tests call resetPpu() directly (confirmed: 0 tests)

### 3.3 Power-On Tests

**Tests:**
- `emulation/state_test.zig` - Tests EmulationState.init() and power_on()
- Tests verify PPU warm-up period (29,658 cycles)

**Why Critical:**
- PPU warm-up period affects register write behavior
- Tests may check initial PPU state after power-on

**Phase 4 Risk:** LOW
- These tests don't use TestHarness PPU methods
- They use `EmulationState.tick()` directly (unaffected by facade removal)

**Mitigation:**
- No action required (no facade dependency)

### 3.4 Scanline Boundary Tests

**Tests:**
- `emulation/state_test.zig` - "odd frame skip when rendering enabled"
- `emulation/state_test.zig` - "even frame does not skip dot"
- Tests advancing to scanline 261 dot 340 (frame boundary)

**Why Critical:**
- Odd frame skip occurs at 261.340 → 0.1 transition
- Tests verify exact PPU cycle behavior at boundaries

**Phase 4 Risk:** LOW
- These tests use `state.tick()` directly (not harness.tickPpu())
- No facade dependency

**Mitigation:**
- No action required

### 3.5 Cross-Component Tests (CPU + PPU Coordination)

**Tests:**
- `integration/cpu_ppu_integration_test.zig` - ALL TESTS ⚠️
- `integration/oam_dma_test.zig` - DMA suspension during PPU operations
- `integration/dpcm_dma_test.zig` - DMC DMA during PPU rendering

**Why Critical:**
- Tests verify CPU/PPU cycle synchronization
- DMA tests verify CPU suspension during OAM/DPCM transfers
- Timing must remain cycle-accurate

**Phase 4 Risk:** MEDIUM
- Tests use `harness.tickPpu()` indirectly through `harness.state.tick()`
- Facade removal should not affect timing (just API)

**Mitigation:**
1. Verify `EmulationState.tick()` still synchronizes CPU/PPU correctly
2. Run DMA tests to ensure suspension logic intact

---

## 4. Phased Verification Plan

### Phase 4a: Update TestHarness (Facade Removal Only)

**Objective:** Update TestHarness to call PpuLogic directly instead of PpuRuntime

**Steps:**

#### 4a.1 Modify Harness.zig (CRITICAL)

**File:** `src/test/Harness.zig`

**Changes Required:**

```zig
// OLD (lines 56-61):
pub fn tickPpu(self: *Harness) void {
    const scanline = self.state.clock.scanline();
    const dot = self.state.clock.dot();
    _ = PpuRuntime.tick(&self.state.ppu, scanline, dot, self.cartPtr(), null);
    self.state.clock.advance(1);
}

// NEW (Option 1 - Direct PpuLogic call):
pub fn tickPpu(self: *Harness) void {
    self.state.tick(); // Use EmulationState.tick() which already handles PPU
}

// NEW (Option 2 - Inline PPU tick):
pub fn tickPpu(self: *Harness) void {
    const scanline = self.state.clock.scanline();
    const dot = self.state.clock.dot();
    _ = PpuLogic.tick(&self.state.ppu, scanline, dot, self.cartPtr(), null);
    self.state.clock.advance(1);
    // TODO: Handle TickFlags if needed (frame_complete, nmi_signal, etc.)
}
```

**Recommendation:** Use **Option 1** (`self.state.tick()`) for simplicity and consistency.

**Changes for all 3 methods:**
1. `tickPpu()` - Line 56-61
2. `tickPpuCycles()` - Line 63-65
3. `tickPpuWithFramebuffer()` - Line 67-72

**Remove Import:**
```zig
// DELETE line 9:
const PpuRuntime = @import("../emulation/Ppu.zig");
```

#### 4a.2 Verify Harness Compiles

```bash
zig build test-unit
```

**Expected Outcome:** Harness compiles cleanly (no PpuRuntime references)

**If Failures:**
- Check for missed PpuRuntime usages
- Verify EmulationState.tick() is available
- Check import paths

#### 4a.3 Run PPU Unit Tests (Fast Feedback)

```bash
zig build test-unit 2>&1 | grep "ppu/"
```

**Expected Outcome:** All PPU unit tests pass (same as baseline)

**Critical Tests to Check:**
- `ppu/vblank_nmi_timing_test.zig` - VBlank flag timing
- `ppu/sprite_evaluation_test.zig` - Sprite evaluation (19 harness calls)

**If Failures:**
- Check scanline/dot synchronization
- Verify TickFlags handling (if using Option 2)
- Check frame_complete flag propagation

#### 4a.4 Run Integration Tests

```bash
zig build test-integration
```

**Expected Outcome:** All integration tests pass

**Critical Tests to Monitor:**
- `integration/nmi_sequence_test.zig` - NMI signal flow
- `integration/cpu_ppu_integration_test.zig` - CPU/PPU coordination

**If Failures:**
- Check NMI edge detection (VBlankLedger interaction)
- Verify timing synchronization
- Check DMA suspension logic

#### 4a.5 Full Test Suite

```bash
zig build test
```

**Expected Outcome:** **930/966 tests passing** (ZERO REGRESSIONS)

**If Regressions:**
- Identify failing test
- Check if test uses harness.tickPpu() methods
- Debug timing differences
- Consider rollback if >5 new failures

### Phase 4b: A12 State Migration (After 4a Passes)

**Objective:** Move `ppu_a12_state` from EmulationState to PpuState

**Steps:**

#### 4b.1 Modify PpuState

**File:** `src/ppu/State.zig`

**Add Field:**
```zig
pub const PpuState = struct {
    // ... existing fields ...

    /// A12 state tracking (for MMC3 scanline IRQ)
    /// Bit 12 of PPU address - transitions during tile fetches
    /// MMC3 IRQ counter decrements on A12 rising edge (0→1)
    a12_state: bool = false,

    // ... rest of struct ...
};
```

#### 4b.2 Update EmulationState

**File:** `src/emulation/State.zig`

**Remove Field (line 96):**
```zig
// DELETE:
ppu_a12_state: bool = false,
```

**Update All References:**

Search and replace in `src/emulation/State.zig`:
```zig
// OLD:
self.ppu_a12_state = false;  // Lines 196, 226
const old_a12 = self.ppu_a12_state;  // Line 530
self.ppu_a12_state = new_a12;  // Line 534

// NEW:
self.ppu.a12_state = false;
const old_a12 = self.ppu.a12_state;
self.ppu.a12_state = new_a12;
```

**Count:** 4 replacements expected

#### 4b.3 Update Harness.resetPpu()

**File:** `src/test/Harness.zig`

**Update Line 100:**
```zig
// OLD:
self.state.ppu_a12_state = false;

// NEW:
self.state.ppu.a12_state = false;
```

#### 4b.4 Update Snapshot Serialization

**File:** `src/snapshot/Snapshot.zig`

**Update Line 250:**
```zig
// OLD:
.ppu_a12_state = false, // Will be recalculated on next tick

// NEW:
// Remove this field from EmulationState deserialization
// Add to PPU deserialization:
state.ppu.a12_state = false; // Will be recalculated on next tick
```

**Note:** May require larger refactor if A12 state is in separate section

#### 4b.5 Verify Compilation

```bash
zig build
```

**Expected Outcome:** Clean compilation (no ppu_a12_state errors)

**If Failures:**
- Check for missed references (grep "ppu_a12_state" in src/)
- Verify all 4 replacements in State.zig
- Check snapshot code carefully

#### 4b.6 Run Snapshot Tests

```bash
zig build test 2>&1 | grep "snapshot/"
```

**Expected Outcome:** All 11 snapshot tests pass

**If Failures:**
- Check snapshot serialization format
- Verify round-trip correctness
- Check PPU state initialization after load

#### 4b.7 Full Test Suite

```bash
zig build test
```

**Expected Outcome:** **930/966 tests passing** (ZERO REGRESSIONS)

**If Regressions:**
- Most likely in snapshot tests
- Check A12 state initialization
- Verify no MMC3-specific tests broke (unlikely, no MMC3 yet)

### Phase 4c: Integration Verification

**Objective:** Verify combined changes maintain system correctness

#### 4c.1 Run Known-Failing Tests

```bash
zig build test 2>&1 | grep "FAILED"
```

**Expected Outcome:** Same 36 failures as baseline (no new failures)

**Known Failures (from baseline):**
- 2 VBlankLedger tests (race condition - expected)
- ~10 integration tests (test infrastructure issues)
- ~3 threading tests (timing-sensitive)
- Others documented in KNOWN-ISSUES.md

#### 4c.2 Run AccuracyCoin Test

```bash
zig build test 2>&1 | grep "accuracycoin"
```

**Expected Outcome:** AccuracyCoin tests pass (hardware accuracy preserved)

**If Failures:**
- CRITICAL - Phase 4 broke hardware accuracy
- Check PPU timing changes
- Verify cycle-accurate behavior

#### 4c.3 Manual Verification (if needed)

**Test Super Mario Bros:**
```bash
./zig-out/bin/RAMBO tests/data/roms/commercial/smb.nes --inspect
```

**Expected Behavior:**
- Game loads to title screen
- No blank screen (VBlank working)
- No crashes

**If Issues:**
- Check VBlank flag timing
- Verify NMI firing
- Check rendering enabled flag

---

## 5. Test Update Checklist

### CRITICAL Updates (Must Complete Before Any Tests)

- [ ] **Update src/test/Harness.zig**
  - [ ] Remove `PpuRuntime` import (line 9)
  - [ ] Update `tickPpu()` to use `self.state.tick()` (lines 56-61)
  - [ ] Update `tickPpuCycles()` to use `self.state.tick()` (lines 63-65)
  - [ ] Update `tickPpuWithFramebuffer()` to use `self.state.tick()` (lines 67-72)
  - [ ] Update `resetPpu()` to access `self.state.ppu.a12_state` (line 100)

- [ ] **Update src/ppu/State.zig**
  - [ ] Add `a12_state: bool = false` field

- [ ] **Update src/emulation/State.zig**
  - [ ] Remove `ppu_a12_state: bool = false` field (line 96)
  - [ ] Update reset() - line 196
  - [ ] Update power_on() - line 226
  - [ ] Update tick() A12 logic - lines 530, 534

- [ ] **Update src/snapshot/Snapshot.zig**
  - [ ] Remove `ppu_a12_state` from EmulationState deserialization
  - [ ] Add `ppu.a12_state` initialization in PPU deserialization (line 250)

### HIGH Priority Updates (Test-Specific)

- [ ] **Verify no direct ppu_a12_state access in tests**
  - [ ] Run: `grep -r "ppu_a12_state" tests/` (should return 0)

- [ ] **Update any hardcoded PpuRuntime imports**
  - [ ] Search tests for: `@import("../emulation/Ppu.zig")`
  - [ ] Currently: 0 found (good!)

### MEDIUM Priority Updates (Documentation)

- [ ] **Update Phase 4 implementation notes**
  - [ ] Document Harness API changes
  - [ ] Document A12 migration rationale

- [ ] **Update test documentation**
  - [ ] Update test README if it references PpuRuntime
  - [ ] Update any test migration guides

---

## 6. Rollback Procedures

### Rollback Phase 4a (Harness Changes)

**If:** More than 5 new test failures after Harness update

**Steps:**
```bash
# 1. Restore Harness.zig
git checkout src/test/Harness.zig

# 2. Verify rollback
zig build test

# 3. Expected: Back to 930/966 passing
```

**Investigation Before Retry:**
- Examine which tests failed
- Check if EmulationState.tick() differs from old PpuRuntime.tick()
- Consider hybrid approach (keep PpuRuntime but mark deprecated)

### Rollback Phase 4b (A12 Migration)

**If:** Snapshot tests fail or new A12-related errors

**Steps:**
```bash
# 1. Restore all modified files
git checkout src/ppu/State.zig
git checkout src/emulation/State.zig
git checkout src/test/Harness.zig
git checkout src/snapshot/Snapshot.zig

# 2. Verify rollback
zig build test

# 3. Expected: Back to 930/966 passing
```

**Investigation Before Retry:**
- Check snapshot serialization format changes
- Verify A12 state is correctly initialized
- Consider keeping A12 in EmulationState (defer migration)

### Emergency Full Rollback

**If:** Phase 4 causes critical breakage (AccuracyCoin fails, etc.)

**Steps:**
```bash
# 1. Revert entire branch
git reset --hard HEAD~N  # N = number of Phase 4 commits

# 2. Verify baseline
zig build test

# 3. Expected: Back to 930/966 passing
```

---

## 7. Manual Verification Procedures

### 7.1 Verify PPU Timing Accuracy

**Purpose:** Ensure facade removal didn't introduce timing regressions

**Procedure:**
1. Run integration test with timing traces:
   ```bash
   zig build test 2>&1 | grep "cpu_ppu_integration"
   ```

2. Check specific timing points:
   - VBlank flag sets at scanline 241 dot 1 (not 241.0)
   - NMI fires on exact cycle after VBlank set
   - Frame completes at scanline 261 dot 340

3. Manual inspection:
   - Check `EmulationState.tick()` implementation
   - Verify PPU cycle advancement matches old PpuRuntime behavior
   - Confirm TickFlags are handled correctly

**Success Criteria:**
- ✅ All timing tests pass
- ✅ No new timing-related failures
- ✅ VBlank/NMI tests maintain same behavior

### 7.2 Verify Snapshot Compatibility

**Purpose:** Ensure A12 migration doesn't break save states

**Procedure:**
1. Create snapshot before migration:
   ```bash
   # (Run RAMBO, create save state)
   ```

2. Apply Phase 4b changes

3. Load old snapshot:
   - Should either load successfully OR fail gracefully with version error
   - Should NOT crash or corrupt state

4. Create new snapshot and verify:
   ```bash
   zig build test 2>&1 | grep "snapshot_integration"
   ```

**Success Criteria:**
- ✅ Old snapshots fail gracefully (expected - format changed)
- ✅ New snapshots round-trip correctly
- ✅ A12 state initialized to `false` on load

### 7.3 Verify A12 IRQ Behavior (Future MMC3)

**Purpose:** Ensure A12 state is correctly tracked for future MMC3 implementation

**Procedure:**
1. Check A12 state transitions in EmulationState.tick():
   ```zig
   // OLD: self.ppu_a12_state
   // NEW: self.ppu.a12_state
   ```

2. Verify A12 changes still detected:
   - Check tile fetch addresses (background/sprite)
   - Verify rising edge detection (0→1)

3. Manual code review:
   - Search for "a12" in src/emulation/State.zig
   - Verify all references updated

**Success Criteria:**
- ✅ A12 state transitions correctly during rendering
- ✅ Rising edge detection logic intact
- ✅ No references to old `ppu_a12_state` field

### 7.4 Check for Timing Regressions

**Purpose:** Ensure no subtle timing changes from facade removal

**Procedure:**
1. Run benchmark tests:
   ```bash
   zig build bench-release
   ```

2. Compare before/after timing:
   - Frame time should be identical (facade removal is API change only)
   - CPU/PPU cycle ratio should be 1:3 (unchanged)

3. Run commercial ROM tests:
   ```bash
   zig build test 2>&1 | grep "commercial_rom"
   ```

**Success Criteria:**
- ✅ Benchmark performance within 1% of baseline
- ✅ Commercial ROM tests pass (if any)
- ✅ No new timing-sensitive test failures

---

## 8. Risk Mitigation Summary

### High-Risk Areas

| Risk | Mitigation | Contingency |
|------|------------|-------------|
| Harness tickPpu() breaks tests | Use `self.state.tick()` for consistency | Rollback Phase 4a |
| VBlank timing regresses | Run vblank_nmi_timing_test.zig FIRST | Investigate EmulationState.tick() |
| Snapshot format incompatible | Verify round-trip tests immediately | Rollback Phase 4b |
| A12 state not initialized | Check resetPpu() and snapshot load | Fix initialization |

### Medium-Risk Areas

| Risk | Mitigation | Contingency |
|------|------------|-------------|
| Integration tests fail | Check CPU/PPU synchronization | Debug specific test |
| Sprite evaluation breaks | Verify PPU cycle advancement | Check shift/fetch timing |
| DMA tests fail | Verify CPU suspension logic | Check bus interaction |

### Low-Risk Areas

| Risk | Mitigation | Contingency |
|------|------------|-------------|
| Power-on tests fail | No facade dependency | Unlikely to break |
| Threading tests fail | Known flaky tests | Expected failures |
| CPU-only tests fail | No PPU dependency | Unrelated to Phase 4 |

---

## 9. Success Criteria Checklist

### Phase 4a Success (Facade Removal)

- [ ] **Compilation:** `zig build` succeeds with no errors
- [ ] **Test Count:** Exactly 930/966 tests passing (no regressions)
- [ ] **Unit Tests:** All PPU unit tests pass (ppu/)
- [ ] **Integration Tests:** All integration tests pass (integration/)
- [ ] **Critical Tests:** VBlank/NMI timing tests pass
- [ ] **Performance:** Benchmark within 1% of baseline
- [ ] **Code Quality:** No PpuRuntime references in tests/

### Phase 4b Success (A12 Migration)

- [ ] **Compilation:** `zig build` succeeds with no errors
- [ ] **Test Count:** Exactly 930/966 tests passing (no regressions)
- [ ] **Snapshot Tests:** All 11 snapshot tests pass
- [ ] **A12 References:** No `ppu_a12_state` in EmulationState
- [ ] **PPU State:** `a12_state` field exists in PpuState
- [ ] **Reset Logic:** Harness.resetPpu() updates ppu.a12_state

### Phase 4c Success (Integration)

- [ ] **Full Suite:** 930/966 tests passing (ZERO REGRESSIONS)
- [ ] **AccuracyCoin:** Hardware accuracy tests pass
- [ ] **Known Failures:** Same 36 failures as baseline
- [ ] **Manual Tests:** SMB loads and runs correctly
- [ ] **Documentation:** Phase 4 changes documented

---

## 10. Conclusion

**Phase 4 Analysis Complete:** ✅

**Key Findings:**
1. **21 test files** depend on TestHarness PPU methods (facade removal impact)
2. **1 snapshot test** affected by A12 migration (serialization format)
3. **0 tests** directly access ppu_a12_state (minimal direct impact)

**Recommended Approach:**
1. Update TestHarness to use `self.state.tick()` (simplest, most consistent)
2. Remove PpuRuntime.zig facade after Harness update
3. Migrate A12 state to PpuState after facade removal
4. Run phased verification at each step

**Risk Level:** MEDIUM (manageable with careful testing)

**Estimated Time:**
- Phase 4a (Harness update): 1-2 hours
- Phase 4b (A12 migration): 1 hour
- Phase 4c (Verification): 1 hour
- **Total:** 3-4 hours

**Next Steps:**
1. Review this analysis with implementation team
2. Begin Phase 4a (Harness update) in isolated branch
3. Run verification tests after each phase
4. Document any unexpected findings
5. Proceed to Phase 5 (VBlank cleanup) after Phase 4 complete

---

**Document Status:** FINAL
**Confidence Level:** HIGH (comprehensive test inventory complete)
**Approval Required:** Agent 4 (Phase 4 Implementation Specialist)
