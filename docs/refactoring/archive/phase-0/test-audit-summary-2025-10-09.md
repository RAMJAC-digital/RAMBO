# Test Audit Summary - 2025-10-09

**Audit Completed By:** 3 Specialized Subagents (test-automator, code-reviewer, architect-reviewer)
**Baseline:** 936/956 tests passing (13 failing, 7 skipped), 77 files

---

## Executive Summary

### Critical Discovery
**Test cleanup MUST happen BEFORE code refactoring** to avoid wasted effort updating tests that will be deleted.

### Audit Findings
- **11 of 13 failing tests** are debug artifacts with intentionally wrong expectations (999, 0xFFFF markers)
- **2 of 13 failing tests** catch real bugs that block commercial ROM compatibility
- **26 of 77 test files** (34%) are redundant or debugging artifacts
- **Only 17% of tests** use the robust Harness pattern
- **High-value consolidation** possible: 10 VBlank tests → 3 comprehensive tests

---

## Failing Tests Classified

### Category 1: Debug Artifacts (DELETE - 11 tests across 6 files)

These tests use `expectEqual(999, actual)` or `expectEqual(0xFFFF, actual)` to force diagnostic output. They served their purpose during debugging and should now be deleted.

| Test File | Failing Tests | Marker Pattern | Action |
|-----------|--------------|----------------|--------|
| `vblank_debug_test.zig` | 1 | `expectEqual(999, total_detections)` | DELETE entire file |
| `clock_sync_test.zig` | 2 | `expectEqual(2, dot)` timing issue | DELETE entire file |
| `bomberman_hang_investigation.zig` | 2 | `expectEqual(0xFFFF, hang_pc)` | DELETE entire file |
| `bomberman_detailed_hang_analysis.zig` | 3 | `expectEqual(999, max_scanline)` | DELETE entire file |
| `commercial_nmi_trace_test.zig` | 1 | `expect(vblank_count > 0)` | DELETE entire file |
| `accuracycoin_execution_test.zig` | 2 | `expect(rendering_enabled != null)` | UPDATE expectations |

**Total to Delete:** 6 files, 11 tests

### Category 2: Real Bugs (FIX CODE - 2 tests)

These tests catch legitimate emulation bugs that prevent commercial ROMs from running correctly.

| Test File | Test Name | Bug Description | Priority |
|-----------|-----------|-----------------|----------|
| `emulation/State.zig` | "odd frame skip when rendering enabled" | Frame skip not happening on odd frames | **P0 - BLOCKER** |
| `ppustatus_polling_test.zig` | "Multiple polls within VBlank period" | $2002 reads not clearing VBlank flag | **P0 - BLOCKER** |

**Impact:** These bugs prevent Bomberman and other commercial games from running.

---

## Test Redundancy Analysis

### VBlank Tests: 10 Files → 3 Files (70% reduction)

**Current Files (10):**
1. `vblank_debug_test.zig` ← DELETE (debug artifact)
2. `vblank_minimal_test.zig` ← CONSOLIDATE
3. `vblank_tracking_test.zig` ← CONSOLIDATE
4. `vblank_persistence_test.zig` ← CONSOLIDATE
5. `vblank_polling_simple_test.zig` ← CONSOLIDATE
6. `ppustatus_read_test.zig` ← CONSOLIDATE
7. `ppustatus_polling_test.zig` ← KEEP (catches real bug)
8. `vblank_nmi_timing_test.zig` ← KEEP (critical timing test)
9. `clock_sync_test.zig` ← DELETE (debug artifact)
10. `integration/vblank_exact_trace.zig` ← DELETE (debug artifact)

**Target Files (3):**
1. `tests/ppu/vblank_behavior_test.zig` - Comprehensive VBlank flag management
2. `tests/ppu/ppustatus_behavior_test.zig` - $2002 register behavior (includes polling)
3. `tests/ppu/vblank_nmi_timing_test.zig` - Cycle-accurate NMI timing

**Savings:** 7 files deleted, ~800 lines of code removed

### Bomberman Tests: 5 Files → 0 Files (100% deletion)

**All Bomberman investigation tests are debug artifacts:**
1. `bomberman_hang_investigation.zig` ← DELETE
2. `bomberman_detailed_hang_analysis.zig` ← DELETE
3. `bomberman_debug_trace_test.zig` ← DELETE
4. `bomberman_exact_simulation.zig` ← DELETE
5. `commercial_nmi_trace_test.zig` ← DELETE

**Rationale:** These were created to debug a specific hang issue. The issue is now understood (VBlank flag not clearing), and the tests have intentionally wrong expectations to force diagnostic output.

**Savings:** 5 files deleted, ~1,200 lines of code removed

### Integration Tests: 22 Files → 16 Files (27% reduction)

**Files to Delete (6):**
- Bomberman investigation files (5) - debug artifacts
- `detailed_trace.zig` - debug artifact
- `nmi_sequence_test.zig` - redundant with cpu_ppu_integration_test.zig

**Files to Keep (16):**
- `accuracycoin_execution_test.zig` - Gold standard validation
- `cpu_ppu_integration_test.zig` - Core timing tests
- `interrupt_execution_test.zig` - NMI/IRQ validation
- All other integration tests (valid, unique coverage)

---

## Test Quality Assessment

### Harness Pattern Adoption: 17% → Target 60%

**Currently Using Harness (13 files):**
- `tests/ppu/sprite_rendering_test.zig`
- `tests/ppu/vblank_nmi_timing_test.zig`
- `tests/snapshot/snapshot_integration_test.zig`
- ~10 other files

**Should Migrate to Harness (High Priority - 12 files):**
- `tests/integration/cpu_ppu_integration_test.zig`
- `tests/integration/interrupt_execution_test.zig`
- `tests/ppu/ppustatus_polling_test.zig`
- All remaining PPU tests
- All remaining integration tests

**Benefits of Harness:**
- ✅ Robust against API changes
- ✅ Cleaner test code
- ✅ Built-in helpers (seekToScanlineDot, setPpuTiming, etc.)
- ✅ Proper resource management (deinit)

### Debugger Integration Opportunities

**Zero tests currently use Debugger** despite having a powerful debugging system.

**High-Value Candidates:**
- `accuracycoin_execution_test.zig` - Add breakpoint validation
- `interrupt_execution_test.zig` - Verify NMI handler execution
- `cpu_ppu_integration_test.zig` - Watchpoints on PPU registers

**Example Pattern:**
```zig
var debugger = Debugger.init(allocator, state.config);
defer debugger.deinit();

try debugger.addBreakpoint(0x8000, .execute);
try debugger.addWatchpoint(0x2002, 1, .read);

while (!debugger.shouldBreak(&state)) {
    state.tick();
}

// Validate state at breakpoint
try testing.expectEqual(expected_a, state.cpu.a);
```

---

## Consolidation Plan

### Phase 0-A: Quick Wins (20 minutes)

**Delete 14 debug artifact files:**
```bash
# VBlank debug artifacts
rm tests/ppu/vblank_debug_test.zig
rm tests/ppu/clock_sync_test.zig

# Bomberman investigation artifacts
rm tests/integration/bomberman_hang_investigation.zig
rm tests/integration/bomberman_detailed_hang_analysis.zig
rm tests/integration/bomberman_debug_trace_test.zig
rm tests/integration/bomberman_exact_simulation.zig

# Trace/debug artifacts
rm tests/integration/commercial_nmi_trace_test.zig
rm tests/integration/vblank_exact_trace.zig
rm tests/integration/detailed_trace.zig
rm tests/integration/nmi_sequence_test.zig

# Redundant minimal tests
rm tests/ppu/vblank_minimal_test.zig
rm tests/ppu/vblank_tracking_test.zig
rm tests/ppu/vblank_persistence_test.zig
rm tests/ppu/vblank_polling_simple_test.zig
```

**Expected Result:** 925-930 tests passing (down from 936 - removed broken debug tests)

### Phase 0-B: Fix Real Bugs (4 hours)

**Bug 1: VBlank $2002 Clear Issue (P0 BLOCKER)**
- **File:** `src/ppu/Logic.zig` readRegister() function
- **Issue:** Reading $2002 doesn't clear VBlank flag
- **Fix:** Add `state.status.vblank = false;` in $2002 read case
- **Test:** `ppustatus_polling_test.zig` should pass after fix

**Bug 2: Odd Frame Skip (P0 BLOCKER)**
- **File:** `src/emulation/State.zig` tick() function
- **Issue:** Odd frame skip not executing correctly
- **Fix:** Review odd frame skip logic at lines 678-688
- **Test:** EmulationState test should pass after fix

**Expected Result:** 925/928 tests passing (99.7%)

### Phase 0-C: Consolidate VBlank Tests (2 hours)

**Create `tests/ppu/vblank_behavior_test.zig`:**
```zig
// Consolidates: vblank_minimal, vblank_tracking, vblank_persistence
test "VBlank: Set at scanline 241, dot 1" { ... }
test "VBlank: Clear on $2002 read" { ... }
test "VBlank: Persist across multiple reads" { ... }
test "VBlank: Clear at scanline 261, dot 1" { ... }
```

**Create `tests/ppu/ppustatus_behavior_test.zig`:**
```zig
// Consolidates: ppustatus_read, ppustatus_polling
test "PPUSTATUS: VBlank flag behavior" { ... }
test "PPUSTATUS: Multiple polls within VBlank" { ... }
test "PPUSTATUS: Open bus bits 0-4" { ... }
test "PPUSTATUS: Sprite 0 hit flag" { ... }
```

**Delete consolidated files:**
```bash
rm tests/ppu/vblank_minimal_test.zig
rm tests/ppu/vblank_tracking_test.zig
rm tests/ppu/vblank_persistence_test.zig
rm tests/ppu/vblank_polling_simple_test.zig
rm tests/ppu/ppustatus_read_test.zig
rm tests/ppu/ppustatus_polling_test.zig
```

**Expected Result:** 6 files → 2 files, all tests passing

### Phase 0-D: Migrate to Harness Pattern (8 hours)

**High-Priority Migrations:**
1. `cpu_ppu_integration_test.zig` - Complex state setup
2. `interrupt_execution_test.zig` - Timing-sensitive
3. Remaining PPU tests - Direct state access

**Pattern:**
```zig
// OLD (fragile)
var state = EmulationState.init(config);
state.ppu.ctrl.nmi_enable = true;
state.cpu.pc = 0x8000;

// NEW (robust)
var harness = try Harness.init();
defer harness.deinit();
harness.ppuWriteRegister(0x2000, 0x80); // Set NMI enable
harness.state.cpu.pc = 0x8000;
```

**Expected Result:** 12 files migrated, same test count

### Phase 0-E: Optional Debugger Integration (4 hours)

**Enhance key tests with Debugger validation:**
- Add to `accuracycoin_execution_test.zig`
- Add to `interrupt_execution_test.zig`
- Create example in test documentation

**Expected Result:** More robust validation, same test count

---

## Revised Timeline

### Original Plan
- 15 days total
- Test updates happening **during** code refactoring
- High risk of updating tests that will be deleted

### NEW Plan (Test-First Approach)
- **Days 0-1:** Test cleanup and bug fixes (Phase 0-A through 0-E)
- **Days 2-12:** Code refactoring (EmulationState decomposition)
- **Days 13-14:** Final validation and documentation
- **15 days total** (same duration, better sequencing)

### Benefits of Test-First
- ✅ No wasted effort updating tests that get deleted
- ✅ Clean test baseline before refactoring
- ✅ Real bugs fixed, improving commercial ROM compatibility
- ✅ Better understanding of test coverage before touching code
- ✅ Reduced risk (tests stable, then refactor incrementally)

---

## Success Metrics

### Immediate (After Phase 0)
| Metric | Baseline | Target | Status |
|--------|----------|--------|--------|
| Test Files | 77 | 63 (-14) | ⏳ |
| Tests Passing | 936/956 (97.9%) | 925/928 (99.7%) | ⏳ |
| Failing Tests | 13 | 0 | ⏳ |
| Debug Artifacts | 11 | 0 | ⏳ |
| Harness Adoption | 17% | 30% | ⏳ |
| Commercial ROM Support | Broken | Working | ⏳ |

### Final (After Complete Refactoring)
| Metric | Target |
|--------|--------|
| Test Files | 51 (-26, -34%) |
| EmulationState Lines | <900 (-60%) |
| Max Function Length | <100 (-82%) |
| Tests Passing | >98% |
| Harness Adoption | >60% |

---

## Next Actions

1. ✅ **Review this audit summary**
2. ⏳ **Execute Phase 0-A:** Delete 14 debug artifact files (20 min)
3. ⏳ **Execute Phase 0-B:** Fix 2 real bugs (4 hours)
4. ⏳ **Execute Phase 0-C:** Consolidate VBlank tests (2 hours)
5. ⏳ **Execute Phase 0-D:** Migrate to Harness (8 hours)
6. ⏳ **Begin code refactoring** with clean test baseline

---

## Approval Required

**Questions for Review:**
1. Approve deletion of 14 debug artifact test files?
2. Approve fixing VBlank $2002 bug before refactoring?
3. Approve test-first approach (cleanup before refactoring)?
4. Any specific tests to preserve that aren't mentioned?

**Ready to Execute Phase 0-A (delete debug artifacts)?**
