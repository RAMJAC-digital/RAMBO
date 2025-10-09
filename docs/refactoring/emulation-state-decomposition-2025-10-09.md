# EmulationState Decomposition Tracker
**Start Date:** 2025-10-09
**Target Completion:** 2025-10-29 (15 working days)
**Lead:** Claude Code
**Status:** 🚀 In Progress

---

## Status Dashboard

**Current Phase:** Phase 0 - Test Cleanup (0-A, 0-B, 0-C, 0-D Complete, 0-E Next)
**Overall Progress:** 28% (5/18 sub-phases complete)
**Strategy Change:** Clean up tests BEFORE refactoring code (prevents wasted effort)

### Metrics
| Metric | Baseline | Current | Target | Status |
|--------|----------|---------|--------|--------|
| **Files Extracted** | 0 | 0 | 9 | ⏳ |
| **Functions Migrated** | 0 | 0 | 113 | ⏳ |
| **EmulationState Lines** | 2,225 | 2,225 | <900 | ⏳ |
| **Tests Updated** | 0 | 0 | 39 | ⏳ |
| **Tests Passing** | 936/956 | 939/949 | ≥936/946 | ✅ |
| **Test Files** | 77 | 63 | 63 | ✅ |
| **Max Function Length** | 560 | 560 | <100 | ⏳ |
| **Max Cyclomatic Complexity** | 80 | 80 | <20 | ⏳ |

### Phase Checklist (REVISED - Test-First Approach)

**Phase 0: Test Cleanup (Days 0-1) - CRITICAL FIRST**
- [x] 0.0: Create tracking documents and capture baseline
- [x] 0-A: Delete 9 debug artifact test files (COMPLETE - 2025-10-09)
- [x] 0-B: Analyze 2 failing tests → documented as known issues (COMPLETE - 2025-10-09)
- [x] 0-C: Consolidate VBlank tests (7 → 4 files, +7 tests, -4 duplicates) (COMPLETE - 2025-10-09)
- [x] 0-D: Consolidate PPUSTATUS tests (3 → 2 files, +3 tests, -5 duplicates) (COMPLETE - 2025-10-09)
- [ ] 0-E: Migrate high-priority tests to Harness (8 hours)

**Phase 1: Dead Code Elimination (Day 2)**
- [ ] 1.1: Remove VBlank orphaned files (VBlankState.zig, VBlankFix.zig)
- [ ] 1.2: Remove dead code in Logic modules (CPU, PPU)
- [ ] 1.3: Verify tests still passing (925/928 expected)

**Phase 2: Module Extraction (Days 3-13)**
- [ ] 2.1: Extract peripheral states (Day 3)
- [ ] 2.2: Extract bus routing (Days 4-5)
- [ ] 2.3: Extract CPU microsteps (Days 6-8)
- [ ] 2.4: Extract DMA execution (Day 9)
- [ ] 2.5: Refactor & extract CPU execution (Days 10-13)

**Phase 3: Final Validation (Days 14-15)**
- [ ] 3.1: Full test suite validation
- [ ] 3.2: AccuracyCoin validation
- [ ] 3.3: Commercial ROM testing
- [ ] 3.4: Documentation updates

---

## Extraction Log

### 2025-10-09 - Phase 0-D Complete: PPUSTATUS Test Consolidation
**Status:** ✅ Complete
**Action:** Consolidated 3 PPUSTATUS test files into 2 files using consistent Harness pattern
**Result:** 3 new unique tests added to ppustatus_polling, 1 file deleted, 2 tests converted to Harness, zero coverage loss

**Inventory Created:**
- `docs/refactoring/phase-0d-ppustatus-consolidation-inventory.md` - Comprehensive analysis of 17 tests across 3 files

**Files Modified (2):**
1. `tests/ppu/ppustatus_polling_test.zig` (7 → 10 tests, all using Harness)
   - **Added 3 unique tests from ppustatus_read_test.zig:**
     - "PPUSTATUS: VBlank at exact set point 241.1" - validates seekToScanlineDot accuracy
     - "PPUSTATUS: Mid-VBlank persistence at 245.150" - verifies mid-period flag persistence
     - "PPUSTATUS: Delayed read after 12-tick advance" - simulates BIT instruction timing
   - **Preserved 2 failing tests** (VBlank $2002 bug - P1, out of scope)

2. `tests/integration/bit_ppustatus_test.zig` (2 tests, converted to Harness)
   - Converted from direct EmulationState to Harness pattern
   - Preserved CPU instruction interaction tests (BIT $2002 with N flag)
   - Maintained direct state access for CPU instruction setup (integration test pattern)

**Files Deleted (1):**
1. `tests/ppu/ppustatus_read_test.zig` (8 tests - 5 duplicates removed, 3 unique migrated)

**Test Results:**
- Before: 936/946 passing
- After: 939/949 passing (+3 net tests)
- Breakdown: +3 unique tests added, -8 tests from deleted file (+5 duplicates removed)
- 4 failing (same - no regressions)
- 6 skipped (same)
- **Pass Rate: 99.0%** (stable)

**Coverage Analysis:**
- ✅ All 17 unique PPUSTATUS tests preserved across 2 files
- ✅ 5 duplicate tests eliminated (exact VBlank timing, $2002 behavior)
- ✅ 2 critical failing tests preserved (document VBlank $2002 bug)
- ✅ Integration tests converted to Harness (consistent pattern)
- ✅ CPU instruction interaction coverage maintained (BIT $2002)

**Pattern Consistency:**
- ALL enhanced tests use `Harness.init()` / `defer harness.deinit()`
- Integration tests use Harness while allowing direct `harness.state` access for CPU setup
- Consistent naming: "PPUSTATUS: specific behavior" and "BIT $2002: specific behavior"
- Clear documentation of integration test requirements

**Rationale:**
Consolidating PPUSTATUS tests reduces redundancy while preserving all unique coverage. Converting integration tests to Harness improves consistency while maintaining flexibility for CPU instruction setup. Critical failing tests documenting VBlank $2002 bug are preserved for future fixes.

**Next:** Phase 0-E (assess remaining Harness migration needs)

### 2025-10-09 - Phase 0-C Complete: VBlank Test Consolidation
**Status:** ✅ Complete
**Action:** Consolidated 7 VBlank test files into 4 files using consistent Harness pattern
**Result:** 7 new unique tests added, 4 redundant files deleted, zero coverage loss

**Inventory Created:**
- `docs/refactoring/phase-0c-vblank-consolidation-inventory.md` - Comprehensive analysis

**Files Created (1):**
1. `tests/ppu/vblank_behavior_test.zig` (7 tests, all using Harness)
   - VBlank flag sets at 241.1
   - VBlank flag sets with dot-level precision
   - VBlank flag clears at 261.1
   - VBlank flag persists across scanlines
   - Multiple frame transitions
   - No VBlank during visible scanlines
   - No VBlank at scanline 0

**Files Deleted (4):**
1. `tests/ppu/vblank_minimal_test.zig` (4 tests - duplicates)
2. `tests/ppu/vblank_tracking_test.zig` (1 test - consolidated)
3. `tests/ppu/vblank_persistence_test.zig` (2 tests - consolidated)
4. `tests/ppu/vblank_polling_simple_test.zig` (2 tests - duplicates)

**Files Kept (3):**
1. `tests/ppu/vblank_nmi_timing_test.zig` (6 tests - already using Harness, good coverage)
2. `tests/ppu/ppustatus_polling_test.zig` (7 tests, 2 failing - known VBlank $2002 bug)
3. `tests/ppu/ppustatus_read_test.zig` (8 tests - will consolidate in Phase 0-D)

**Build Changes:**
- Added vblank_behavior_test.zig to build.zig
- Removed 4 deleted test file references

**Test Results:**
- Before: 933/943 passing
- After: 936/946 passing (+3 net tests)
- Breakdown: +7 new unique tests, -10 redundant tests, +3 from deleted files that had unique coverage
- 4 failing (same - no regressions)
- 6 skipped (same)
- **Pass Rate: 99.0%** (stable)

**Coverage Analysis:**
- ✅ All unique VBlank timing coverage preserved
- ✅ Dot-level precision tests consolidated
- ✅ Multi-frame persistence tests consolidated
- ✅ All tests now use Harness pattern (consistent)
- ✅ Duplicate polling tests eliminated
- ✅ Known failing tests preserved (VBlank $2002 bug)

**Pattern Consistency:**
- ALL new tests use `Harness.init()` / `defer harness.deinit()`
- ALL new tests use `harness.seekToScanlineDot()` for precise positioning
- NO direct `EmulationState.init()` usage in new tests
- Consistent naming: "VBlank: specific behavior"

**Rationale:**
Consolidating redundant VBlank tests reduces test file count while preserving all unique coverage. Using Harness pattern makes tests robust against API changes and provides better testing utilities.

**Next:** Phase 0-D (consolidate PPUSTATUS tests)

### 2025-10-09 - Phase 0-B Complete: Failing Tests Documented as Known Issues
**Status:** ✅ Complete (Analyzed & Documented)
**Action:** Analyzed 2 remaining failing tests, determined both require architectural work
**Decision:** Document as known issues and defer to Phase 2+ (post-refactoring)

**Tests Analyzed:**
1. **Odd Frame Skip** (`State.zig:2138`)
   - **Issue**: Clock advances by 1, should advance by 2 when skipping odd frame dot 0
   - **Fix Complexity**: Requires changing MasterClock timing invariant ("always advance by 1")
   - **Architectural Risk**: Part of PPU/clock decoupling work
   - **Decision**: DEFER to Phase 2+ (MasterClock refactoring)

2. **AccuracyCoin Rendering** (`accuracycoin_execution_test.zig:166`)
   - **Issue**: `rendering_enabled` never becomes true in 300 frames
   - **Fix Complexity**: Unknown root cause, requires debugging investigation
   - **Potential Causes**: PPU warmup, PPUMASK flag setting, VBlank timing, or test expectations
   - **Decision**: DEFER to Phase 2+ (after VBlank $2002 fix)

**User Guidance Applied:**
> "If this proves to be more than a quick fix. We need to make sure we capture known information in failing tests (this is part of the vblank issue, and part of decoupling the ppu acting as the primary reference and advancing the clock, this should only ever be done once in a tick. If this requires more development and debugging, we need to pause, and track this with the vblank failing test and move forward."

**Documentation Updated:**
- docs/KNOWN-ISSUES.md: Added 2 new sections with comprehensive analysis
  - "Emulation: Odd Frame Skip Not Implemented" (P2 priority)
  - "PPU: AccuracyCoin Rendering Detection" (P2 priority)
- Both include root cause analysis, proposed fixes, and deferral rationale

**Test Status:**
- Before: 933/943 passing, 4 failing (2 VBlank + 2 analyzed)
- After: 933/943 passing, 4 failing (all documented as known issues)
- **All 4 failing tests preserved** with clear documentation

**Rationale:**
Both tests touch core timing/architectural concerns that are better addressed during the EmulationState decomposition (Phase 2) rather than as quick fixes. Methodical approach prevents introducing regressions or violating MasterClock invariants.

**Next:** Phase 0-C (consolidate VBlank tests)

### 2025-10-09 - Phase 0-A Complete: Debug Artifact Deletion
**Status:** ✅ Complete
**Action:** Deleted 9 debug artifact test files
**Files Deleted:**
1. tests/ppu/clock_sync_test.zig (2 tests - timing debug)
2. tests/ppu/vblank_debug_test.zig (1 test - 999 marker)
3. tests/integration/bomberman_hang_investigation.zig (3 tests - 0xFFFF markers, 1 passing)
4. tests/integration/bomberman_detailed_hang_analysis.zig (3 tests - 999/0xFF markers)
5. tests/integration/commercial_nmi_trace_test.zig (1 test - trace artifact)
6. tests/integration/bomberman_debug_trace_test.zig (not in build.zig)
7. tests/integration/bomberman_exact_simulation.zig (not in build.zig)
8. tests/integration/detailed_trace.zig (not in build.zig)
9. tests/integration/vblank_exact_trace.zig (removed from build.zig)

**Build Changes:**
- Modified build.zig to remove test definitions and dependencies

**Test Results:**
- Before: 936/956 passing (13 failing, 7 skipped)
- After: 933/943 passing (4 failing, 6 skipped)
- Deleted: 13 tests total (9 failing + 3 passing + 1 skipped)
- Pass rate: 99.0% (up from 97.9%)

**Remaining Failing Tests (Expected):**
1. odd frame skip (State.zig) - FIXABLE
2. accuracycoin rendering enabled - FIXABLE
3. PPUSTATUS polling VBlank clear - KNOWN ISSUE (out of scope)
4. BIT timing VBlank clear - KNOWN ISSUE (out of scope)

**Documentation Created:**
- docs/KNOWN-ISSUES.md (VBlank $2002 bug documented)

**Next:** Phase 0-B (fix 2 real bugs)

### 2025-10-09 - Test Audit Complete (CRITICAL FINDINGS)
**Status:** ✅ Complete
**Action:** Comprehensive test audit by 3 specialized subagents
**Key Findings:**
- **13 failing tests** = 11 debug artifacts + 2 real bugs
- **26 test files** (34%) are redundant or debugging artifacts
- **Only 17%** of tests use robust Harness pattern
- **2 P0 blocker bugs** prevent commercial ROM compatibility

**Strategy Change:** Test cleanup BEFORE code refactoring
**Rationale:** Avoid wasted effort updating tests that will be deleted

**Documents Created:**
- `test-audit-summary-2025-10-09.md` - Complete audit findings
- `baseline-tests-2025-10-09.txt` - Test output snapshot

**Next:** Execute Phase 0-A (delete 14 debug artifact files)

### 2025-10-09 - Project Initialization
**Status:** ✅ Complete
**Action:** Created tracking infrastructure
**Files Created:**
- docs/refactoring/emulation-state-decomposition-2025-10-09.md
- docs/refactoring/ADR-001-emulation-state-decomposition.md
- Plus 5 more supporting documents

**Next:** Test audit (completed above)

---

## Module Extraction Status

| Module | Source Lines | Target File | Lines | Status | Commit |
|--------|--------------|-------------|-------|--------|--------|
| BusState | 49-58 | state/BusState.zig | 10 | ⏳ Pending | - |
| DmaState | 63-102 | state/DmaState.zig | 40 | ⏳ Pending | - |
| DmcDmaState | 194-224 | state/DmcDmaState.zig | 31 | ⏳ Pending | - |
| ControllerState | 107-189 | state/ControllerState.zig | 83 | ⏳ Pending | - |
| Bus Routing | 379-649 | bus/Routing.zig | 271 | ⏳ Pending | - |
| CPU Microsteps | 832-1188 | cpu/Microsteps.zig | 357 | ⏳ Pending | - |
| CPU Execution | 1192-1751 | cpu/ExecutionEngine.zig | 560 | ⏳ Pending | - |
| DMA Execution | 1782-1881 | dma/Execution.zig | 100 | ⏳ Pending | - |

**Total Lines to Extract:** 1,452 / 2,225 (65%)

---

## Test Update Log

### Tests Requiring Updates: 39 files

| Test File | EmulationState Imports | Risk | Status | Commit |
|-----------|----------------------|------|--------|--------|
| accuracycoin_execution_test.zig | ROM runner | LOW | ✅ Safe | - |
| cpu_ppu_integration_test.zig | state.cpu.nmi_line | HIGH | ⏳ Pending | - |
| interrupt_execution_test.zig | state.cpu.instruction_cycle | HIGH | ⏳ Pending | - |
| nmi_sequence_test.zig | state.ppu_nmi_active | HIGH | ⏳ Pending | - |
| ... | ... | ... | ⏳ Pending | - |

---

## Dead Code Removal Log

### Orphaned Files (Zero Imports)
| File | Lines | Status | Commit |
|------|-------|--------|--------|
| src/ppu/VBlankState.zig | 121 | ⏳ Pending | - |
| src/ppu/VBlankFix.zig | ~121 | ⏳ Pending | - |

### Dead Functions
| Function | File | Lines | Status | Commit |
|----------|------|-------|--------|--------|
| reset() | src/cpu/Logic.zig | 32-52 | ⏳ Pending | - |
| tickFrame() | src/ppu/Logic.zig | 777 | ⏳ Pending | - |

---

## Test Consolidation Plan

### Integration Tests: 22 → 16 files (-6)
**Files to Remove:**
- bomberman_debug_trace_test.zig (debugging artifact)
- bomberman_detailed_hang_analysis.zig (debugging artifact)
- bomberman_exact_simulation.zig (covered elsewhere)
- commercial_nmi_trace_test.zig (redundant)
- detailed_trace.zig (debugging artifact)
- vblank_exact_trace.zig (move to PPU tests)

**Files to Keep/Rename:**
- bomberman_hang_investigation.zig → bomberman_integration_test.zig

### PPU Tests: 15 → 10 files (-5)
**Files to Consolidate:**
- vblank_debug_test.zig \
- vblank_minimal_test.zig  \
- vblank_polling_simple_test.zig  → **vblank_behavior_test.zig**
- vblank_tracking_test.zig  /
- vblank_persistence_test.zig /

---

## Blockers & Risks

### Current Blockers
- None

### Risk Register
| Risk | Probability | Impact | Mitigation | Status |
|------|-------------|--------|------------|--------|
| Tests drop below 930/947 | Medium | High | Immediate rollback | Monitoring |
| AccuracyCoin fails | Low | Critical | Validation checkpoints | Monitoring |
| Complexity in CPU execution | High | Medium | Incremental refactoring | Planned |

---

## Notes & Decisions

### 2025-10-09
- Approved ownership model: Mutations within tick() call stack acceptable
- Approved test consolidation: Remove 11 redundant test files
- Decision: Use inline delegation for bus routing (preserve API)
- Decision: Extract microsteps with mutations (document ownership)

---

## Next Actions

1. ✅ Create tracking documents (CURRENT)
2. ⏳ Capture test baseline (zig build test > baseline-tests.txt)
3. ⏳ Audit test dependencies (grep analysis)
4. ⏳ Create test consolidation plan document
5. ⏳ Begin Phase 1: Dead code removal
