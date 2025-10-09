# Test Audit Action Plan - Quick Reference

**Date:** 2025-10-09
**Full Report:** [test-suite-audit-2025-10-09.md](./test-suite-audit-2025-10-09.md)

## TL;DR

**Current State:** 936/956 tests (13 failing, 7 skipped), 77 files, 20,184 lines
**Proposed State:** 925/928 tests (0 failing, 3 skipped), 51 files, 17,000 lines
**Recommendation:** Delete 26 files (34%), fix 2 bugs, consolidate redundancy

---

## Phase 1: Delete Debug Artifacts (20 minutes)

**Run these commands:**

```bash
# VBlank debug files (6 files)
rm tests/ppu/vblank_debug_test.zig
rm tests/ppu/vblank_minimal_test.zig
rm tests/ppu/vblank_tracking_test.zig
rm tests/ppu/vblank_persistence_test.zig
rm tests/ppu/vblank_polling_simple_test.zig
rm tests/ppu/clock_sync_test.zig

# Bomberman debug files (5 files)
rm tests/integration/bomberman_hang_investigation.zig
rm tests/integration/bomberman_detailed_hang_analysis.zig
rm tests/integration/bomberman_debug_trace_test.zig
rm tests/integration/bomberman_exact_simulation.zig
rm tests/integration/commercial_nmi_trace_test.zig

# Integration debug files (3 files)
rm tests/integration/vblank_exact_trace.zig
rm tests/integration/detailed_trace.zig
rm tests/integration/nmi_sequence_test.zig

# Verify tests still pass
zig build test
```

**Expected Result:** ~14 test files deleted, ~1,834 lines removed, ~925-930 tests remaining

---

## Phase 2: Fix Real Bugs (4 hours)

### Bug 1: Frame skip timing (emulation/State.zig)
**Test:** "odd frame skip when rendering enabled"
**Error:** `expected 1, found 0`
**Location:** `/home/colin/Development/RAMBO/src/emulation/State.zig:2138`
**Action:** Debug frame timing edge case when rendering is enabled

### Bug 2: VBlank polling regression (ppustatus_polling_test.zig)
**Test:** "Multiple polls within VBlank period"
**Error:** `detected_count >= 1` failed (detected_count = 0)
**Location:** `/home/colin/Development/RAMBO/tests/ppu/ppustatus_polling_test.zig:153`
**Action:** Fix VBlank flag visibility during polling loop

**Also delete 1 test in ppustatus_polling_test.zig:**
- "BIT instruction timing - when does read occur?" (wrong timing assumptions)

**Expected Result:** 925/928 tests passing (99.7%)

---

## Phase 3: Consolidate VBlank Tests (6 hours)

### Create 2 new consolidated files:

#### 1. tests/ppu/ppustatus_behavior_test.zig
**Merge from:**
- `ppustatus_read_test.zig` (8 tests)
- `ppustatus_polling_test.zig` (6 tests after deleting 1)

**Focus:** PPUSTATUS register behavior (reads, clears, polling)

#### 2. tests/integration/vblank_integration_test.zig
**Merge from:**
- `vblank_wait_test.zig` (1 test)
- `bit_ppustatus_test.zig` (2 tests)

**Focus:** Full CPU+PPU integration scenarios

**Keep as-is:**
- `tests/ppu/vblank_nmi_timing_test.zig` (core PPU timing tests)

**Commands:**
```bash
# Create new files
touch tests/ppu/ppustatus_behavior_test.zig
touch tests/integration/vblank_integration_test.zig

# After copying tests over:
rm tests/ppu/ppustatus_read_test.zig
rm tests/ppu/ppustatus_polling_test.zig
rm tests/integration/vblank_wait_test.zig
rm tests/integration/bit_ppustatus_test.zig

zig build test  # Verify
```

---

## Phase 4: Review CPU Instruction Tests (4 hours)

**Question:** Does `cpu/instructions_test.zig` (698 lines, 30 tests) duplicate `cpu/opcodes/*.zig`?

**Analysis Steps:**
1. List all tests in `cpu/instructions_test.zig`
2. List all tests in `cpu/opcodes/*.zig` files
3. Compare coverage
4. Decision: Keep both OR consolidate

**Commands:**
```bash
# Extract test names from instructions_test.zig
grep '^test "' tests/cpu/instructions_test.zig

# Extract test names from opcodes/*.zig
grep '^test "' tests/cpu/opcodes/*.zig

# Compare and document findings
```

---

## Phase 5: Harness Migration (8 hours)

**Priority Migration Targets:**

### 1. tests/integration/nmi_sequence_test.zig (200 lines)
**Current:** Direct EmulationState access
**After:** Use Harness pattern

```zig
// BEFORE
var config = Config.init(testing.allocator);
var state = EmulationState.init(&config);
state.reset();
state.ppu.warmup_complete = true;
while (state.clock.scanline() < 241) {
    state.tick();
}

// AFTER
var harness = try Harness.init();
defer harness.deinit();
harness.seekToScanlineDot(241, 0);
```

### 2. tests/integration/cpu_ppu_integration_test.zig (501 lines)
**Benefit:** Largest integration test, easier to maintain with Harness

### 3. tests/integration/vblank_wait_test.zig (~100 lines)
**Benefit:** Integration test should use Harness abstractions

**Template for migration:**
1. Replace `Config.init` + `EmulationState.init` with `Harness.init()`
2. Replace manual clock manipulation with `seekToScanlineDot()`
3. Replace direct PPU access with `harness.ppuReadRegister()` / `harness.ppuWriteRegister()`
4. Add `defer harness.deinit()`

---

## Quick Win Checklist

- [ ] **Phase 1:** Delete 14 debug artifact files (20 min)
  - [ ] Run `zig build test` → Should pass ~925/928
  - [ ] Commit: "test: remove debug artifact tests"

- [ ] **Phase 2:** Fix 2 real bugs (4 hours)
  - [ ] Fix frame skip timing bug
  - [ ] Fix VBlank polling regression
  - [ ] Delete "BIT instruction timing" test
  - [ ] Run `zig build test` → Should pass 925/928
  - [ ] Commit: "fix: resolve frame timing and VBlank polling bugs"

- [ ] **Update CLAUDE.md:** Change "939/947 tests passing" to "925/928 tests passing"

---

## Files to Delete (14 total)

### PPU Tests (6 files)
1. `tests/ppu/vblank_debug_test.zig`
2. `tests/ppu/vblank_minimal_test.zig`
3. `tests/ppu/vblank_tracking_test.zig`
4. `tests/ppu/vblank_persistence_test.zig`
5. `tests/ppu/vblank_polling_simple_test.zig`
6. `tests/ppu/clock_sync_test.zig`

### Integration Tests (8 files)
7. `tests/integration/bomberman_hang_investigation.zig`
8. `tests/integration/bomberman_detailed_hang_analysis.zig`
9. `tests/integration/bomberman_debug_trace_test.zig`
10. `tests/integration/bomberman_exact_simulation.zig`
11. `tests/integration/commercial_nmi_trace_test.zig`
12. `tests/integration/vblank_exact_trace.zig`
13. `tests/integration/detailed_trace.zig`
14. `tests/integration/nmi_sequence_test.zig`

---

## Files to Review (4 files)

1. `tests/cpu/instructions_test.zig` - Check for redundancy with opcodes/*.zig
2. `tests/integration/commercial_rom_test.zig` - Extract valid tests, delete debug code
3. `tests/ppu/ppustatus_polling_test.zig` - Delete 1 test ("BIT instruction timing")
4. `src/emulation/State.zig:2138` - Fix frame skip bug

---

## Success Metrics

### After Phase 1+2 (Quick Wins)
- ✅ Test files: 77 → 63 (-14)
- ✅ Test count: ~859 → ~830 (-29)
- ✅ Lines: 20,184 → ~18,350 (-1,834)
- ✅ Passing: 936/956 (97.9%) → 925/928 (99.7%)
- ✅ Failing: 13 → 0
- ✅ Time investment: ~4.5 hours

### After Full Consolidation (Phases 3-5)
- ✅ Test files: 77 → 51 (-26)
- ✅ Test count: ~859 → ~800-820 (redundancy removed)
- ✅ Lines: 20,184 → ~17,000 (-3,184)
- ✅ Harness adoption: 17% → >50%
- ✅ Time investment: ~30 hours total

---

## Next Steps

1. **Read full audit:** [test-suite-audit-2025-10-09.md](./test-suite-audit-2025-10-09.md)
2. **Start Phase 1:** Delete debug artifacts (20 min)
3. **Verify:** `zig build test` after each phase
4. **Commit:** Small, focused commits with clear messages

**Questions?** See Section 7 (Recommendations) in full audit report.
