# RAMBO Test Suite Comprehensive Audit

**Date:** 2025-10-09
**Baseline:** 936/956 tests passing (13 failing, 7 skipped)
**Total Test Files:** 77
**Total Test Cases:** ~859
**Total Lines of Test Code:** 20,184

## Executive Summary

The RAMBO test suite has grown organically during debugging, resulting in significant redundancy and debugging artifacts. This audit identifies **26 test files (34%) for deletion or consolidation**, focusing on:

1. **Debugging artifacts** with intentionally wrong expectations (expectEqual 999 pattern)
2. **Redundant VBlank/PPUSTATUS tests** (10+ files testing same behavior)
3. **Bomberman investigation tests** (5 files, all exploratory)
4. **Consolidation opportunities** in PPU and integration tests

**Key Finding:** Only **13/77 tests (17%)** use the robust `Harness` pattern. The remainder access state directly, making them fragile.

---

## 1. Failing Test Analysis (13 Tests)

### 1.1 Debugging Artifacts (DELETE - 11 tests)

These tests have **intentionally wrong expectations** (e.g., `expectEqual(999, actual_value)`) to force failure and display diagnostic information. They served their purpose during debugging and should be **deleted**.

| Test File | Failing Tests | Classification | Action |
|-----------|---------------|----------------|--------|
| **vblank_debug_test.zig** | 1 | Debug artifact | **DELETE** |
| - "What happens when we poll continuously?" | Line 65: `expectEqual(999, total_detections)` | Forces failure to show diagnostics | Remove entire file |
| **clock_sync_test.zig** | 2 | Debug artifact | **DELETE** |
| - "PPU processes current position, not next" | Expected behavior changed | Outdated assumption | Remove entire file |
| - "VBlank sets when PPU processes 241.1" | Line 87: `expectEqual(2, vblank_set_at_clock_dot)` found 1 | Off-by-one from timing fix | Remove entire file |
| **bomberman_hang_investigation.zig** | 2 | Debug artifact | **DELETE** |
| - "Find exact hang location with PC tracking" | Line 94: `expectEqual(0xFFFF, hang_pc)` found 49165 | Diagnostic dump | Remove entire file |
| - "Check for specific wait patterns" | Line 231: `expectEqual(0xFFFF, addr)` found 8194 | Diagnostic dump | Remove entire file |
| **bomberman_detailed_hang_analysis.zig** | 3 | Debug artifact | **DELETE** |
| - "Trace scanline progression" | Line 112: `expectEqual(999, max_scanline_reached)` found 261 | Diagnostic dump | Remove entire file |
| - "Check if PPU is enabled" | Line 135: `expectEqual(0xFF, ppuctrl)` found 0 | Diagnostic dump | Remove entire file |
| - "Check CPU/PPU cycle ratio" | Line 181: `expectEqual(999999, cpu_delta)` found 33333 | Diagnostic dump | Remove entire file |
| **ppustatus_polling_test.zig** | 2 | Mixed | **FIX 1, DELETE 1** |
| - "Multiple polls within VBlank period" | Line 153: Regression - VBlank not detected | **FIX** - Real bug | Update expectations |
| - "BIT instruction timing" | Line 308: Test assumes wrong timing | Debug artifact | Delete this test only |
| **commercial_nmi_trace_test.zig** | 1 | Debug artifact | **DELETE** |
| - "Bomberman first 3 frames" | Line 117: Bomberman timeout investigation | Diagnostic | Remove entire file |

**Subtotal: 11 tests across 6 files → DELETE 5 files, FIX 1 test in ppustatus_polling_test.zig**

### 1.2 Real Bugs (KEEP - 2 tests)

| Test File | Failing Test | Root Cause | Action |
|-----------|--------------|------------|--------|
| **emulation/State.zig** | "odd frame skip when rendering enabled" | Edge case in frame timing | **KEEP** - Fix implementation |
| **ppustatus_polling_test.zig** | "Multiple polls within VBlank period" | VBlank polling regression | **KEEP** - Fix implementation |

**Subtotal: 2 tests catching real bugs → KEEP and FIX**

---

## 2. Test Redundancy Analysis

### 2.1 VBlank/PPUSTATUS Tests (HIGH REDUNDANCY)

**15 test files** covering VBlank behavior with massive overlap:

#### PPU-level VBlank Tests (7 files)
| File | Tests | Lines | Harness? | Classification | Action |
|------|-------|-------|----------|----------------|--------|
| vblank_nmi_timing_test.zig | 6 | 184 | ✅ Yes | **Core** - Keep | **KEEP** |
| vblank_debug_test.zig | 1 | 74 | ✅ Yes | Debug artifact | **DELETE** |
| vblank_minimal_test.zig | 4 | 131 | ❌ No | Redundant with nmi_timing | **DELETE** |
| vblank_tracking_test.zig | 1 | 43 | ❌ No | Redundant | **DELETE** |
| vblank_persistence_test.zig | 1 | ~50 | ❌ No | Redundant | **DELETE** |
| vblank_polling_simple_test.zig | 1 | ~60 | ❌ No | Redundant | **DELETE** |
| clock_sync_test.zig | 2 | 88 | ❌ No | Debug artifact | **DELETE** |

#### PPUSTATUS Tests (2 files)
| File | Tests | Lines | Harness? | Classification | Action |
|------|-------|-------|----------|----------------|--------|
| ppustatus_read_test.zig | 8 | ~200 | ✅ Yes | **Core** - Keep | **KEEP** (delete 1 test) |
| ppustatus_polling_test.zig | 7 | ~320 | ✅ Yes | **Core** - Keep | **KEEP** (fix 1 test) |

#### Integration VBlank Tests (6 files)
| File | Tests | Lines | Harness? | Classification | Action |
|------|-------|-------|----------|----------------|--------|
| vblank_wait_test.zig | 1 | ~100 | ❌ No | Integration - Keep | **KEEP** |
| bit_ppustatus_test.zig | 2 | ~80 | ✅ Yes | Integration - Keep | **KEEP** |
| nmi_sequence_test.zig | 5 | ~200 | ❌ No | **Core** - Keep | **KEEP** |
| vblank_exact_trace.zig | 2 | ~150 | ❌ No | Debug artifact | **DELETE** |
| detailed_trace.zig | 1 | ~120 | ❌ No | Debug artifact | **DELETE** |
| commercial_nmi_trace_test.zig | 1 | ~120 | ❌ No | Debug artifact | **DELETE** |

**Action: DELETE 9 files, KEEP 6 files (3 PPU, 3 integration)**

**Consolidation Opportunity:** The 4 passing tests in `vblank_minimal_test.zig` could be migrated to `vblank_nmi_timing_test.zig` if coverage gaps exist.

### 2.2 Bomberman Investigation Tests (5 files - ALL DEBUG ARTIFACTS)

| File | Tests | Lines | Classification | Action |
|------|-------|-------|----------------|--------|
| bomberman_hang_investigation.zig | 3 | 262 | Debug artifact (all use expectEqual 999 pattern) | **DELETE** |
| bomberman_detailed_hang_analysis.zig | 3 | 184 | Debug artifact (all use expectEqual 999 pattern) | **DELETE** |
| bomberman_debug_trace_test.zig | 3 | ~200 | Debug artifact | **DELETE** |
| bomberman_exact_simulation.zig | 1 | ~150 | Debug artifact | **DELETE** |
| commercial_rom_test.zig | 9 | 329 | Mixed - has some valid tests | **REVIEW** - Extract valid tests |

**Action: DELETE 4 files, REVIEW 1 file (commercial_rom_test.zig may have valid ROM loading tests)**

### 2.3 Other Redundancy

#### CPU Opcode Tests
| Category | Files | Redundancy? | Action |
|----------|-------|-------------|--------|
| cpu/opcodes/*.zig | 11 files | No - Each covers distinct instruction families | **KEEP** |
| cpu/instructions_test.zig | 1 file (698 lines) | Possible overlap with opcodes/*.zig | **REVIEW** |

**Review Needed:** Does `instructions_test.zig` duplicate coverage from `opcodes/*.zig`? If yes, consolidate.

---

## 3. Test Quality Assessment

### 3.1 Harness Pattern Adoption (GOOD Pattern)

**13/77 files (17%)** use the `Harness` pattern:

```zig
var harness = try Harness.init();
defer harness.deinit();
harness.seekToScanlineDot(241, 1);  // Clean abstraction
```

**Benefits:**
- Clean abstractions (`seekToScanlineDot`, `tickPpu`, `ppuReadRegister`)
- Automatic cleanup (deinit)
- Consistent cartridge handling
- Less fragile than direct state access

**Files Using Harness:**
1. vblank_nmi_timing_test.zig ✅
2. ppustatus_polling_test.zig ✅
3. ppustatus_read_test.zig ✅
4. vblank_debug_test.zig ✅ (but DELETE)
5. bit_ppustatus_test.zig ✅
6. sprite_rendering_test.zig ✅
7. sprite_edge_cases_test.zig ✅
8. sprite_evaluation_test.zig ✅
9. chr_integration_test.zig ✅
10. seek_behavior_test.zig ✅
11. status_bit_test.zig ✅
12. vblank_persistence_test.zig ✅ (but DELETE)
13. vblank_polling_simple_test.zig ✅ (but DELETE)

**Recommendation:** Migrate more tests to Harness pattern, especially:
- `nmi_sequence_test.zig` (200 lines, direct state access)
- `cpu_ppu_integration_test.zig` (501 lines, direct state access)
- `vblank_wait_test.zig` (integration test)

### 3.2 Direct State Access (FRAGILE Pattern)

**64/77 files (83%)** access `EmulationState` directly:

```zig
var config = Config.init(testing.allocator);
var state = EmulationState.init(&config);
state.ppu.status.vblank = true;  // Direct mutation
```

**Issues:**
- More verbose setup/teardown
- Bypasses abstractions
- Easier to introduce bugs (e.g., forgetting to set `warmup_complete`)
- Harder to maintain

**High-Priority Migration Candidates:**
1. `nmi_sequence_test.zig` - Complex NMI flow, would benefit from Harness
2. `cpu_ppu_integration_test.zig` - 501 lines, complex interactions
3. All `vblank_*.zig` tests not using Harness

---

## 4. Consolidation Plan

### Phase 1: Delete Debug Artifacts (Immediate - 2 hours)

**Delete 14 files:**

1. **VBlank Debug Files (6):**
   - `tests/ppu/vblank_debug_test.zig`
   - `tests/ppu/vblank_minimal_test.zig`
   - `tests/ppu/vblank_tracking_test.zig`
   - `tests/ppu/vblank_persistence_test.zig`
   - `tests/ppu/vblank_polling_simple_test.zig`
   - `tests/ppu/clock_sync_test.zig`

2. **Bomberman Debug Files (5):**
   - `tests/integration/bomberman_hang_investigation.zig`
   - `tests/integration/bomberman_detailed_hang_analysis.zig`
   - `tests/integration/bomberman_debug_trace_test.zig`
   - `tests/integration/bomberman_exact_simulation.zig`
   - `tests/integration/commercial_nmi_trace_test.zig`

3. **Integration Debug Files (3):**
   - `tests/integration/vblank_exact_trace.zig`
   - `tests/integration/detailed_trace.zig`
   - `tests/integration/nmi_sequence_test.zig` (maybe keep? review)

**Expected Result:** 936/956 → ~925/930 tests (remove ~11-26 failing tests + redundant passing tests)

### Phase 2: Fix Real Bugs (High Priority - 4 hours)

1. **Fix:** `emulation/State.zig` - "odd frame skip when rendering enabled"
   - Root cause: Frame timing edge case
   - Status: **P0 BLOCKER** for accurate emulation

2. **Fix:** `ppustatus_polling_test.zig` - "Multiple polls within VBlank period"
   - Root cause: VBlank polling regression
   - Delete: "BIT instruction timing" test (wrong assumptions)

**Expected Result:** 925/928 tests passing (2 bugs fixed, 1 test deleted)

### Phase 3: Consolidate VBlank Tests (Medium Priority - 6 hours)

**Target:** Consolidate to **3 core VBlank test files**

1. **`tests/ppu/vblank_nmi_timing_test.zig`** (KEEP - Core PPU timing)
   - VBlank set/clear timing
   - NMI edge detection
   - PPUSTATUS race conditions

2. **`tests/ppu/ppustatus_behavior_test.zig`** (NEW - Consolidate 2 files)
   - Merge: `ppustatus_read_test.zig` + `ppustatus_polling_test.zig`
   - Focus: PPUSTATUS register behavior (reads, clears, polling)

3. **`tests/integration/vblank_integration_test.zig`** (NEW - Consolidate 3 files)
   - Merge: `vblank_wait_test.zig` + `bit_ppustatus_test.zig` + best of `nmi_sequence_test.zig`
   - Focus: Full CPU+PPU integration scenarios

**Migration Steps:**
1. Create `ppustatus_behavior_test.zig`
2. Copy all unique tests from `ppustatus_read_test.zig` and `ppustatus_polling_test.zig`
3. Delete originals
4. Verify: `zig build test-unit`

**Expected Result:** 15 files → 3 files (12 files deleted, ~50-100 tests preserved)

### Phase 4: Review CPU Instruction Tests (Low Priority - 4 hours)

**Question:** Does `cpu/instructions_test.zig` (698 lines) duplicate `cpu/opcodes/*.zig` (11 files)?

**Analysis Needed:**
1. Grep for overlapping test names
2. Compare coverage (which instructions are tested where)
3. Decision: Keep both (different granularity) OR consolidate

**Expected Result:** Potential deletion of 1 large file OR confirmation of orthogonal coverage

### Phase 5: Harness Migration (Medium Priority - 8 hours)

**Migrate high-value tests to Harness pattern:**

1. **`nmi_sequence_test.zig`** (200 lines)
   - Complex NMI flow testing
   - Would benefit from `seekToScanlineDot()` and `tickPpu()`

2. **`cpu_ppu_integration_test.zig`** (501 lines)
   - Largest integration test
   - Heavy CPU+PPU coordination

3. **`vblank_wait_test.zig`** (~100 lines)
   - Integration test, should use Harness

**Migration Template:**
```zig
// OLD (fragile)
var config = Config.init(testing.allocator);
var state = EmulationState.init(&config);
state.reset();
state.ppu.warmup_complete = true;
while (state.clock.scanline() < 241) state.tick();

// NEW (robust)
var harness = try Harness.init();
defer harness.deinit();
harness.seekToScanlineDot(241, 0);
```

**Expected Result:** 3 major tests migrated, easier to maintain

---

## 5. Detailed File Classification Table

### 5.1 DELETE - Debug Artifacts (14 files)

| File | Tests | Lines | Reason | Effort |
|------|-------|-------|--------|--------|
| ppu/vblank_debug_test.zig | 1 | 74 | expectEqual(999) pattern | 1 min |
| ppu/clock_sync_test.zig | 2 | 88 | Outdated timing assumptions | 1 min |
| ppu/vblank_minimal_test.zig | 4 | 131 | Redundant with nmi_timing | 2 min |
| ppu/vblank_tracking_test.zig | 1 | 43 | Redundant with nmi_timing | 1 min |
| ppu/vblank_persistence_test.zig | 1 | ~50 | Redundant with nmi_timing | 1 min |
| ppu/vblank_polling_simple_test.zig | 1 | ~60 | Redundant with ppustatus tests | 1 min |
| integration/bomberman_hang_investigation.zig | 3 | 262 | expectEqual(999) pattern | 1 min |
| integration/bomberman_detailed_hang_analysis.zig | 3 | 184 | expectEqual(999) pattern | 1 min |
| integration/bomberman_debug_trace_test.zig | 3 | ~200 | Debug trace | 1 min |
| integration/bomberman_exact_simulation.zig | 1 | ~150 | Debug trace | 1 min |
| integration/commercial_nmi_trace_test.zig | 1 | ~120 | Debug trace | 1 min |
| integration/vblank_exact_trace.zig | 2 | ~150 | Debug trace | 1 min |
| integration/detailed_trace.zig | 1 | ~120 | Debug trace | 1 min |
| integration/nmi_sequence_test.zig | 5 | ~200 | Redundant with vblank_nmi_timing | 2 min |

**Total: 14 files, ~1,832 lines, 20 minutes effort**

### 5.2 KEEP - Core Tests (51 files)

#### CPU Tests (18 files) - All KEEP
| File | Tests | Lines | Quality | Notes |
|------|-------|-------|---------|-------|
| cpu/rmw_test.zig | 18 | 345 | ⭐⭐⭐ | RMW dummy write edge cases |
| cpu/instructions_test.zig | 30 | 698 | ⭐⭐⭐ | **REVIEW** - Overlap with opcodes? |
| cpu/interrupt_logic_test.zig | 5 | ~150 | ⭐⭐⭐ | NMI/IRQ logic |
| cpu/page_crossing_test.zig | 9 | ~120 | ⭐⭐⭐ | Dummy reads |
| cpu/opcodes/*.zig | ~150 | ~3,500 | ⭐⭐⭐ | Comprehensive opcode coverage (11 files) |
| cpu/dispatch_debug_test.zig | 3 | ~80 | ⭐⭐ | Opcode dispatch |
| cpu/bus_integration_test.zig | 4 | ~100 | ⭐⭐⭐ | CPU+Bus integration |
| cpu/diagnostics/timing_trace_test.zig | 6 | ~150 | ⭐⭐ | Timing diagnostics |

#### PPU Tests (9 files) - 6 KEEP, 3 DELETE
| File | Tests | Lines | Quality | Action |
|------|-------|-------|---------|--------|
| ppu/vblank_nmi_timing_test.zig | 6 | 184 | ⭐⭐⭐ Harness | **KEEP** |
| ppu/ppustatus_read_test.zig | 8 | ~200 | ⭐⭐⭐ Harness | **KEEP** → Consolidate |
| ppu/ppustatus_polling_test.zig | 7 | ~320 | ⭐⭐⭐ Harness | **KEEP** → Consolidate |
| ppu/sprite_rendering_test.zig | 23 | 452 | ⭐⭐⭐ Harness | **KEEP** |
| ppu/sprite_edge_cases_test.zig | 35 | 611 | ⭐⭐⭐ Harness | **KEEP** |
| ppu/sprite_evaluation_test.zig | 15 | 517 | ⭐⭐⭐ Harness | **KEEP** |
| ppu/chr_integration_test.zig | 6 | ~150 | ⭐⭐⭐ Harness | **KEEP** |
| ppu/seek_behavior_test.zig | 1 | ~50 | ⭐⭐ Harness | **KEEP** |
| ppu/status_bit_test.zig | 2 | ~60 | ⭐⭐ Harness | **KEEP** |

#### APU Tests (7 files) - All KEEP
| File | Tests | Lines | Quality | Notes |
|------|-------|-------|---------|-------|
| apu/apu_test.zig | 8 | ~200 | ⭐⭐⭐ | Core APU |
| apu/dmc_test.zig | 25 | 413 | ⭐⭐⭐ | DMC channel |
| apu/envelope_test.zig | 20 | 350 | ⭐⭐⭐ | Envelope unit |
| apu/sweep_test.zig | 25 | 419 | ⭐⭐⭐ | Sweep unit |
| apu/length_counter_test.zig | 25 | 524 | ⭐⭐⭐ | Length counter |
| apu/linear_counter_test.zig | 15 | ~180 | ⭐⭐⭐ | Linear counter |
| apu/frame_irq_edge_test.zig | 10 | ~150 | ⭐⭐⭐ | Frame IRQ |
| apu/open_bus_test.zig | 7 | ~100 | ⭐⭐ | Open bus |

#### Integration Tests (12 files) - 5 KEEP, 7 DELETE
| File | Tests | Lines | Action |
|------|-------|-------|--------|
| integration/accuracycoin_execution_test.zig | 4 | ~200 | **KEEP** |
| integration/accuracycoin_prg_ram_test.zig | 3 | ~150 | **KEEP** |
| integration/cpu_ppu_integration_test.zig | 21 | 501 | **KEEP** - Migrate to Harness |
| integration/vblank_wait_test.zig | 1 | ~100 | **KEEP** - Migrate to Harness |
| integration/bit_ppustatus_test.zig | 2 | ~80 | **KEEP** - Uses Harness |
| integration/oam_dma_test.zig | 14 | 418 | **KEEP** |
| integration/dpcm_dma_test.zig | 3 | ~150 | **KEEP** |
| integration/interrupt_execution_test.zig | 3 | ~120 | **KEEP** |
| integration/ppu_register_absolute_test.zig | 4 | ~100 | **KEEP** |
| integration/controller_test.zig | 14 | ~200 | **KEEP** |
| integration/input_integration_test.zig | 22 | ~250 | **KEEP** |
| integration/benchmark_test.zig | 3 | ~100 | **KEEP** |

#### Other Tests (5 files) - All KEEP
| Category | Files | Total Tests | Quality |
|----------|-------|-------------|---------|
| Cartridge | 2 | ~15 | ⭐⭐⭐ |
| Debugger | 1 (1849 lines!) | 66 | ⭐⭐⭐ |
| Threading | 1 | 14 | ⭐⭐ (1 flaky test) |
| Config | 1 | ~30 | ⭐⭐⭐ |
| iNES | 1 | 26 | ⭐⭐⭐ |
| Snapshot | 1 | ~23 | ⭐⭐⭐ |
| Input | 2 | ~40 | ⭐⭐⭐ |
| Bus | 1 | 17 | ⭐⭐⭐ |
| Comptime | 1 | 8 | ⭐⭐ |
| Helpers | 1 | 7 | ⭐⭐ |

**Total: 51 files to KEEP (with consolidation)**

### 5.3 REVIEW - Unclear Classification (12 files)

| File | Tests | Lines | Question | Action |
|------|-------|-------|----------|--------|
| cpu/instructions_test.zig | 30 | 698 | Overlap with opcodes/*.zig? | Analyze coverage overlap |
| integration/commercial_rom_test.zig | 9 | 329 | Has valid ROM tests? | Extract valid tests, delete debug code |
| integration/rom_test_runner.zig | 3 | 357 | Helper or test? | Keep as test utility |
| integration/nmi_sequence_test.zig | 5 | ~200 | Redundant or unique? | Review against vblank_nmi_timing |

---

## 6. Migration Effort Estimates

### Quick Wins (2-4 hours)
- **Phase 1:** Delete 14 debug artifact files (20 minutes)
- **Phase 2:** Fix 2 real bugs (4 hours)
- **Subtotal:** ~4.5 hours → 925/928 tests passing

### Medium Effort (10-14 hours)
- **Phase 3:** Consolidate VBlank tests (6 hours)
- **Phase 4:** Review CPU instruction tests (4 hours)
- **Subtotal:** 10 hours → Cleaner test organization

### Long-term Improvement (8-16 hours)
- **Phase 5:** Migrate 3 major tests to Harness (8 hours)
- **Phase 6:** Create Harness migration guide (2 hours)
- **Phase 7:** Migrate remaining high-value tests (6 hours)
- **Subtotal:** 16 hours → Robust test suite

**Total Effort:** 30.5 hours across all phases

---

## 7. Recommendations

### Immediate Actions (This Week)
1. ✅ **Delete all 14 debug artifact files** (20 min)
2. ✅ **Fix 2 real bugs** (4 hours)
3. ✅ **Update build.zig** to remove deleted test references

**Expected Outcome:** Clean baseline (~925/928 passing, ~63 files)

### Short-term (Next Sprint)
1. **Consolidate VBlank tests** → 3 core files (6 hours)
2. **Review `cpu/instructions_test.zig`** for overlap (4 hours)
3. **Document Harness migration pattern** (2 hours)

**Expected Outcome:** ~51 test files, clear organization

### Long-term (Next Quarter)
1. **Migrate top 10 tests to Harness** (16 hours)
2. **Enforce Harness pattern** for new tests (policy)
3. **Add test coverage metrics** to CI

**Expected Outcome:** >50% Harness adoption, maintainable suite

---

## 8. Key Metrics Summary

### Before Audit
- **Files:** 77
- **Tests:** ~859
- **Lines:** 20,184
- **Passing:** 936/956 (97.9%)
- **Failing:** 13 (1.4%)
- **Skipped:** 7 (0.7%)
- **Harness Adoption:** 17%

### After Phase 1+2 (Delete + Fix)
- **Files:** 63 (-14 deleted)
- **Tests:** ~830-840 (-19 to -29)
- **Lines:** ~18,350 (-1,834)
- **Passing:** 925/928 (99.7%)
- **Failing:** 0 (0%)
- **Skipped:** 3 (0.3%)
- **Harness Adoption:** 21%

### After All Phases (Full Consolidation)
- **Files:** ~51 (-26 total)
- **Tests:** ~800-820 (redundancy removed)
- **Lines:** ~17,000 (-3,184)
- **Passing:** 800+/810 (>98%)
- **Harness Adoption:** >50%

---

## 9. Risk Assessment

### Low Risk
- **Deleting debug artifacts:** Zero risk - intentionally broken tests
- **Consolidating redundant VBlank tests:** Low risk - overlapping coverage

### Medium Risk
- **Fixing real bugs:** May expose other issues during fix
- **Harness migration:** Requires careful validation of behavior preservation

### High Risk
- **Deleting `cpu/instructions_test.zig`:** ONLY if confirmed redundant with opcodes/*.zig

### Mitigation Strategy
1. Delete in phases with test runs after each phase
2. Use git branches for consolidation work
3. Run `zig build test` after every file deletion
4. Keep deleted files in git history for 1 sprint (revert if needed)

---

## 10. Conclusion

The RAMBO test suite is **functionally comprehensive but organizationally bloated**. Removing 26 debugging artifacts and consolidating redundant tests will:

1. **Improve clarity:** 51 focused files vs. 77 scattered files
2. **Reduce maintenance:** Fewer files to update when API changes
3. **Increase confidence:** Fix 2 real bugs, remove 11 false failures
4. **Better patterns:** Push >50% Harness adoption

**Recommended Execution:**
1. **Week 1:** Delete debug artifacts + fix bugs (4.5 hours) → Clean baseline
2. **Week 2:** Consolidate VBlank tests (6 hours) → Organized PPU tests
3. **Week 3+:** Harness migration + documentation (18 hours) → Sustainable patterns

**Final State:** 51 well-organized test files, ~800 tests, >98% passing, >50% using robust Harness pattern.
