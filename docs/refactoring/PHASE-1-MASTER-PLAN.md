# RAMBO Phase 1 Refactoring - Master Plan

**Date:** 2025-10-09
**Status:** Ready for Development
**Phase 0 Completion:** ✅ Complete (939/947 tests passing, 99.2%)
**Baseline:** 22,748 lines across 87 files
**Target:** Improved modularity with zero functional changes

---

## Executive Summary

This Phase 1 refactoring addresses **critical file size and complexity issues** through systematic decomposition while maintaining **100% API compatibility** and **zero functional changes**. The project has grown organically to a point where several files have become difficult to navigate (2,225 lines, 1,857 lines, 1,243 lines). This refactoring will establish a sustainable structure for continued development.

### Core Principles

1. **Zero Functional Changes** - No behavior modifications, pure code organization
2. **Zero API Breakage** - All public functions preserved through inline delegation
3. **Zero Test Modifications** - Tests should continue passing without changes (except 3 trivial import updates)
4. **Zero Performance Impact** - Inline functions ensure no runtime overhead

### Success Criteria

- ✅ All 939/947 tests continue passing
- ✅ No files exceed 800 lines
- ✅ All public APIs preserved
- ✅ AccuracyCoin test ROM still passes
- ✅ Build time unchanged or improved

---

## Phase 0 Achievement Summary

**Status:** ✅ **COMPLETE** - Ready for Phase 1

Phase 0 cleaned up the test suite and established readiness:

- ✅ Deleted 9 debug artifact test files
- ✅ Consolidated 7 VBlank test files → 4 files
- ✅ Consolidated 3 PPUSTATUS test files → 2 files
- ✅ Migrated 5 integration tests to TestHarness pattern
- ✅ Documented 4 failing tests as known issues
- ✅ Test file count: 77 → 64 files (-17% reduction)
- ✅ Test pass rate: 97.9% → 99.2% (+1.3% improvement)

**Phase 0 Documentation:**
- `docs/refactoring/phase-0-completion-assessment.md` - Complete assessment
- `docs/refactoring/emulation-state-decomposition-2025-10-09.md` - Tracking document
- `docs/refactoring/ADR-001-emulation-state-decomposition.md` - Architecture decision record

---

## Critical Files Requiring Decomposition

### Priority Classification

| Priority | File | Lines | Complexity | Risk | Impact |
|----------|------|-------|------------|------|--------|
| **P0** | src/emulation/State.zig | 2,225 | Critical | Medium | Very High |
| **P0** | src/video/VulkanLogic.zig | 1,857 | High | Low | High |
| **P1** | src/debugger/Debugger.zig | 1,243 | High | Medium | High |
| **P1** | src/config/Config.zig | 782 | Medium | Low | Medium |
| **P1** | src/ppu/Logic.zig | 779 | Medium | Low | Medium |
| **P2** | src/cpu/variants.zig | 563 | Medium | Medium | Low |
| **P2** | src/cpu/dispatch.zig | 532 | Medium | Low | Low |
| **P2** | src/emulation/MasterClock.zig | 474 | Low | Low | Low |
| **P2** | src/cpu/decode.zig | 454 | Low | Low | Low |
| **P2** | src/apu/Logic.zig | 453 | Low | Low | Low |

---

## Phase 1 Scope Definition

### What IS In Scope ✅

1. **File Decomposition:**
   - Extract large files into focused modules
   - Create subdirectories for related functionality
   - Improve navigation and discoverability

2. **Dead Code Removal:**
   - Delete orphaned files (VBlankState.zig, VBlankFix.zig)
   - Remove deprecated functions
   - Clean up unused imports

3. **Naming Consistency:**
   - Standardize file naming conventions
   - Clarify module boundaries
   - Resolve naming ambiguities

4. **API Preservation:**
   - Maintain all public function signatures
   - Use inline delegation wrappers
   - Keep test compatibility

### What IS NOT In Scope ❌

1. **Functional Changes:**
   - No algorithm modifications
   - No timing adjustments
   - No bug fixes (except test cleanup)

2. **Architecture Changes:**
   - No State/Logic pattern violations
   - No ownership model changes
   - No threading model changes

3. **Performance Optimization:**
   - No algorithmic improvements
   - No cache optimizations
   - No memory layout changes

4. **New Features:**
   - No mapper additions
   - No APU audio output
   - No debugger enhancements

---

## Detailed Decomposition Plans

### 1. src/emulation/State.zig (2,225 lines) - P0 CRITICAL

**Current Issues:**
- Monster 559-line `executeCpuCycle()` function
- 35+ CPU microstep helpers leaked into EmulationState
- 6+ mixed responsibilities in one file
- Hardest file to navigate in entire codebase

**Extraction Plan:** (4 phases, ~12 days)

#### Phase 1.1: Pure Data Structures (Days 1-3, Zero Risk)

Extract to new files:
```
src/emulation/state/
├── CycleResults.zig         # 16 lines (PpuCycleResult, CpuCycleResult, ApuCycleResult)
├── BusState.zig            # 15 lines (RAM, open_bus, test_ram)
└── peripherals/
    ├── OamDma.zig          # 80 lines (DmaState struct + methods)
    ├── DmcDma.zig          # 90 lines (DmcDmaState struct + methods)
    └── ControllerState.zig # 85 lines (ControllerState struct + methods)
```

**Result:** 2,225 → 1,956 lines (-12% reduction)
**Risk:** 🟢 **MINIMAL** - Pure data extraction
**Tests Affected:** 3 files (trivial import updates)

#### Phase 1.2: Bus Routing Logic (Days 4-8, Medium Risk)

Extract to new files:
```
src/emulation/bus/
├── Logic.zig               # 280 lines (busRead, busWrite, busRead16, etc.)
└── README.md               # Documentation
```

**EmulationState keeps inline delegation:**
```zig
pub inline fn busRead(self: *EmulationState, address: u16) u8 {
    return bus.Logic.busRead(self, address);
}
```

**Result:** 1,956 → 1,676 lines (-18% reduction)
**Risk:** 🟡 **MEDIUM** - Heavy test usage
**Tests Affected:** 0 (inline delegation preserves API)

#### Phase 1.3: CPU Microsteps (Days 9-12, High Risk)

Extract to new files:
```
src/emulation/cpu/
├── Microsteps.zig          # 320 lines (35+ addressing mode helpers)
└── README.md               # Documentation
```

**Result:** 1,676 → 1,356 lines (-40% reduction)
**Risk:** 🔴 **HIGH** - Complex CPU logic
**Tests Affected:** 0 (functions stay private to emulation)

#### Phase 1.4: CPU Execution Engine (Days 13-15, High Risk)

Extract to new file:
```
src/emulation/cpu/
└── ExecutionLogic.zig      # 600 lines (executeCpuCycle refactored)
```

**Result:** 1,356 → 756 lines (-66% reduction from baseline!)
**Risk:** 🔴 **HIGH** - Core execution logic
**Tests Affected:** 0 (private implementation)

**Detailed Extraction Plan:** `docs/refactoring/state-zig-extraction-plan.md`
**Architecture Audit:** `docs/refactoring/state-zig-architecture-audit.md`

---

### 2. src/video/VulkanLogic.zig (1,857 lines) - P0 CRITICAL

**Current Issues:**
- Largest single file in entire codebase
- Monolithic Vulkan renderer
- Multiple distinct responsibilities mixed together

**Extraction Plan:** (6 modules)

```
src/video/vulkan/
├── mod.zig                 # Public API re-exports
├── Instance.zig            # Instance + extensions (~200 lines)
├── Device.zig              # Physical/logical device selection (~250 lines)
├── Swapchain.zig           # Swapchain management (~300 lines)
├── Pipeline.zig            # Graphics pipeline + shaders (~400 lines)
├── Commands.zig            # Command buffers + recording (~350 lines)
└── Texture.zig             # Texture/image management (~200 lines)
```

**VulkanLogic.zig becomes orchestrator** (~157 lines):
```zig
pub const VulkanLogic = struct {
    // Inline delegation to specialized modules
    pub inline fn init(...) { return Instance.init(...); }
    pub inline fn createDevice(...) { return Device.create(...); }
    // etc.
};
```

**Result:** 1,857 → 157 lines (-91% reduction!)
**Risk:** 🟢 **LOW** - Video subsystem isolated from emulation
**Tests Affected:** 0 (video tests use high-level API)

**Estimated Effort:** 8-10 hours

---

### 3. src/debugger/Debugger.zig (1,243 lines) - P1 HIGH

**Current Issues:**
- Monolithic debugger mixing state and logic
- Should follow project's State/Logic pattern
- Multiple distinct responsibilities

**Extraction Plan:** (State/Logic split + modules)

```
src/debugger/
├── Debugger.zig            # Public API facade (~50 lines)
├── State.zig               # DebuggerState structure (~200 lines)
├── Logic.zig               # Core debugger operations (~150 lines)
├── breakpoints/
│   ├── Breakpoints.zig     # Breakpoint management (~150 lines)
│   └── Watchpoints.zig     # Watchpoint management (~150 lines)
├── history/
│   ├── History.zig         # Execution history (~200 lines)
│   └── Trace.zig           # Instruction tracing (~150 lines)
└── stepping/
    └── Stepping.zig        # Step over/into/out (~150 lines)
```

**Result:** 1,243 → ~1,200 lines (organized, not reduced)
**Risk:** 🟡 **MEDIUM** - Debugger used by emulation thread
**Tests Affected:** 1 file (debugger_test.zig imports)

**Estimated Effort:** 10-12 hours

---

### 4. src/config/Config.zig (782 lines) - P1 MEDIUM

**Current Issues:**
- Mixes types, state, and parsing logic
- Should separate concerns

**Extraction Plan:**

```
src/config/
├── Config.zig              # Public API facade (~50 lines)
├── types.zig               # Type definitions (~200 lines)
├── State.zig               # Config state structure (~150 lines)
├── defaults.zig            # Default values (~100 lines)
└── parser.zig              # Already exists (~282 lines)
```

**Result:** 782 → ~50 lines (facade) + organized modules
**Risk:** 🟢 **LOW** - Config loaded once at startup
**Tests Affected:** 0 (facade preserves API)

**Estimated Effort:** 4-6 hours

---

### 5. Dead Code Removal - P0 IMMEDIATE

**Orphaned Files (Zero imports, safe to delete):**

1. ✅ **src/ppu/VBlankState.zig** (120 lines)
   - Experimental VBlank implementation from Oct 8
   - Superseded by working logic
   - Zero imports across codebase

2. ✅ **src/ppu/VBlankFix.zig** (136 lines)
   - Another experimental VBlank implementation
   - Superseded by working logic
   - Zero imports across codebase

**Impact:** -256 lines with zero breakage

**Verification:**
```bash
# Verify zero usage
grep -r "VBlankState\|VBlankFix" src tests
# Should return no results

# Delete files
rm src/ppu/VBlankState.zig src/ppu/VBlankFix.zig

# Verify tests still pass
zig build test
```

**Deprecated Functions:**

3. ✅ **src/cpu/Logic.zig::reset()** (marked as unused)
   - Comment: "kept for reference but not used in new architecture"
   - Action: Delete or move to tests

**Estimated Effort:** 30 minutes

**Detailed Analysis:** `docs/refactoring/ppu-subsystem-audit-2025-10-09.md`

---

### 6. Quick Wins - P1 LOW EFFORT

#### 6.1 APU Pulse Channel Duplication

**Issue:** writePulse1/writePulse2 duplicate 62 lines in Logic.zig

**Solution:** Extract to Pulse.zig component
```
src/apu/
└── Pulse.zig               # 80 lines (unified pulse channel logic)
```

**Result:** Logic.zig: 453 → 391 lines (-14% reduction)
**Effort:** 2-3 hours

#### 6.2 CPU variants.zig Decomposition

**Issue:** 563 lines mixing concerns

**Solution:**
```
src/cpu/variants/
├── mod.zig                 # Type factory (~150 lines)
├── config.zig              # Variant configurations (~50 lines)
└── unofficial.zig          # Variant-dependent opcodes (~400 lines)
```

**Result:** 563 → 150 lines (facade)
**Effort:** 4-6 hours

#### 6.3 Mailbox Naming Consistency

**Issue:** Minor inconsistencies in naming conventions

**Solution:** Standardize on pattern: `[Purpose][Type]Mailbox.zig`

**Effort:** 1 hour

---

## Risk Assessment & Mitigation

### Risk Categories

#### 🟢 Zero Risk (Pure Data Extraction)
- State.zig Phase 1.1 (data structures)
- Orphaned file deletion
- Config.zig type extraction

**Mitigation:** None needed - straightforward extraction

#### 🟡 Medium Risk (Logic with Heavy Test Usage)
- State.zig Phase 1.2 (bus routing)
- Debugger decomposition
- CPU variants extraction

**Mitigation:**
- Inline delegation wrappers preserve API
- Run tests after each extraction
- Use git branches for easy rollback

#### 🔴 High Risk (Core Execution Logic)
- State.zig Phases 1.3 & 1.4 (CPU execution)
- VulkanLogic decomposition

**Mitigation:**
- Incremental extraction (one module at a time)
- Comprehensive test validation after each step
- Keep microsteps private (no public API exposure)
- AccuracyCoin validation after completion

### Test Impact Analysis

**20 test files use EmulationState directly:**

```
Phase 1.1 Impact (Data Structures):
- 3 files need trivial import updates
- Zero behavior changes

Phase 1.2 Impact (Bus Routing):
- 0 files need changes (inline delegation)
- Zero behavior changes

Phase 1.3/1.4 Impact (CPU Logic):
- 0 files need changes (private implementation)
- Zero behavior changes
```

**Detailed Analysis:** 20 test files reviewed, all using high-level API

---

## Validation Strategy

### Per-Module Validation

After each extraction:

```bash
# 1. Build verification
zig build

# 2. Full test suite
zig build test

# 3. Specific subsystem tests
zig build test-unit        # Quick smoke test (< 1 second)
zig build test-integration # Full validation (< 10 seconds)

# 4. AccuracyCoin validation (critical!)
./zig-out/bin/RAMBO --test-rom test/AccuracyCoin.nes

# 5. Commercial ROM spot check
./zig-out/bin/RAMBO test/Super\ Mario\ Bros.nes
```

### Exit Criteria (Each Phase)

✅ All 939/947 tests passing (no regressions)
✅ AccuracyCoin test ROM passes
✅ Build completes without warnings
✅ No increase in compilation time
✅ Code review approval (human verification)

### Rollback Strategy

```bash
# Each phase gets its own branch
git checkout -b phase-1.1-data-structures
git checkout -b phase-1.2-bus-routing
# etc.

# If validation fails:
git checkout main
git branch -D phase-1.x-failed-branch
# Start over with lessons learned
```

---

## Implementation Timeline

### Phase 1 Schedule (20 working days, ~120 hours)

| Phase | Duration | Risk | Validation Time |
|-------|----------|------|-----------------|
| **Week 1: Foundation** | | | |
| 1.0 Dead Code Removal | 0.5 days | 🟢 Zero | 1 hour |
| 1.1 State.zig Data Structures | 2.5 days | 🟢 Zero | 2 hours |
| **Week 2: Bus & Logic** | | | |
| 1.2 State.zig Bus Routing | 3 days | 🟡 Medium | 3 hours |
| 1.3 Config.zig Decomposition | 1 day | 🟢 Low | 1 hour |
| **Week 3: Core Execution** | | | |
| 1.4 State.zig CPU Microsteps | 3 days | 🔴 High | 4 hours |
| 1.5 State.zig CPU Execution | 2 days | 🔴 High | 4 hours |
| **Week 4: Video & Debugger** | | | |
| 1.6 VulkanLogic Decomposition | 3 days | 🟡 Medium | 2 hours |
| 1.7 Debugger Decomposition | 3 days | 🟡 Medium | 2 hours |
| **Week 5: Polish** | | | |
| 1.8 Quick Wins (APU, CPU) | 1 day | 🟢 Low | 1 hour |
| 1.9 Final Validation | 0.5 days | N/A | 4 hours |
| 1.10 Documentation Update | 0.5 days | N/A | 1 hour |

**Total:** 20 days, ~120 hours development + 25 hours validation

---

## Success Metrics

### Quantitative Metrics

| Metric | Baseline | Target | Measurement |
|--------|----------|--------|-------------|
| **Largest File** | 2,225 lines | <800 lines | src/emulation/State.zig |
| **Files >800 Lines** | 5 files | 0 files | All source files |
| **Avg File Size** | 261 lines | <200 lines | src/ directory |
| **Test Pass Rate** | 99.2% (939/947) | ≥99.2% | zig build test |
| **Build Time** | Baseline | ≤110% | zig build (clean) |
| **AccuracyCoin** | PASSING | PASSING | Test ROM execution |

### Qualitative Metrics

- ✅ **Navigation:** Find any function in <10 seconds
- ✅ **Comprehension:** Understand module purpose from filename
- ✅ **Maintenance:** Make changes without hunting through 2000-line files
- ✅ **Testing:** Identify relevant tests for any code change
- ✅ **Documentation:** Clear module responsibilities

---

## Documentation Deliverables

### Required Documentation

1. ✅ **Phase 1 Master Plan** (this document)
2. ✅ **State.zig Architecture Audit** (completed by subagent)
3. ✅ **State.zig Extraction Plan** (completed by subagent)
4. ✅ **CPU Subsystem Audit** (completed by subagent)
5. ✅ **PPU Subsystem Audit** (completed by subagent)
6. ✅ **APU Subsystem Audit** (completed by subagent)
7. ⏳ **Migration Guide** (for future contributors)
8. ⏳ **API Compatibility Matrix** (old imports → new imports)
9. ⏳ **Phase 1 Completion Report** (post-implementation)

### Updated Documentation

- ✅ `CLAUDE.md` - Update architecture section
- ✅ `docs/CURRENT-STATUS.md` - Update file counts
- ✅ `docs/README.md` - Add Phase 1 reference
- ✅ `docs/refactoring/` - Archive Phase 0 docs

---

## Appendix A: File Size Analysis

### Current State (Top 20 Largest Files)

| Rank | File | Lines | Status |
|------|------|-------|--------|
| 1 | src/emulation/State.zig | 2,225 | 🔴 P0 Decompose |
| 2 | src/video/VulkanLogic.zig | 1,857 | 🔴 P0 Decompose |
| 3 | src/debugger/Debugger.zig | 1,243 | 🟡 P1 Decompose |
| 4 | src/config/Config.zig | 782 | 🟡 P1 Decompose |
| 5 | src/ppu/Logic.zig | 779 | 🟢 Acceptable |
| 6 | src/cpu/variants.zig | 563 | 🟡 P2 Optional |
| 7 | src/cpu/dispatch.zig | 532 | 🟢 Recently refactored |
| 8 | src/emulation/MasterClock.zig | 474 | 🟢 Acceptable |
| 9 | src/cpu/decode.zig | 454 | 🟢 Acceptable |
| 10 | src/apu/Logic.zig | 453 | 🟢 Acceptable |

### Target State (After Phase 1)

| File | Current | Target | Reduction |
|------|---------|--------|-----------|
| State.zig | 2,225 | ~750 | -66% |
| VulkanLogic.zig | 1,857 | ~160 | -91% |
| Debugger.zig | 1,243 | ~50 | -96% |
| Config.zig | 782 | ~50 | -94% |
| variants.zig | 563 | ~150 | -73% |
| APU Logic.zig | 453 | ~390 | -14% |

**Total Reduction:** ~5,800 lines reorganized into focused modules

---

## Appendix B: Test Dependencies

### EmulationState Test Usage (20 files)

**Integration Tests (13 files):**
- accuracycoin_execution_test.zig
- cpu_ppu_integration_test.zig
- interrupt_execution_test.zig
- nmi_sequence_test.zig
- ppu_register_absolute_test.zig
- vblank_wait_test.zig
- bit_ppustatus_test.zig
- controller_integration_test.zig
- dmc_dma_conflict_test.zig
- oam_dma_timing_test.zig
- dma_execution_test.zig
- bus_integration_test.zig
- rom_loading_integration_test.zig

**Unit Tests (7 files):**
- State_test.zig (inline tests in State.zig)
- seek_behavior_test.zig
- ppustatus_polling_test.zig
- clock_synchronization_test.zig
- sprite_evaluation_test.zig
- sprite_fetch_test.zig
- sprite_edge_cases_test.zig

**Impact:** Phase 1.1 requires 3 files update imports, rest unchanged

---

## Appendix C: Key Design Decisions

### ADR References

1. **ADR-001:** EmulationState Decomposition Strategy
   - File: `docs/refactoring/ADR-001-emulation-state-decomposition.md`
   - Decision: Extract using inline delegation pattern
   - Rationale: Preserves API, zero test changes

2. **State/Logic Separation:** Maintained throughout
   - State modules: Pure data structures
   - Logic modules: Pure functions
   - Never mixed in refactoring

3. **Inline Delegation Pattern:**
   ```zig
   // Old API (preserved)
   pub inline fn busRead(self: *EmulationState, addr: u16) u8 {
       return bus.Logic.busRead(self, addr);
   }
   // Zero performance overhead due to `inline`
   ```

4. **Private vs Public:**
   - Microsteps stay private (no external usage)
   - Bus functions stay public (heavy test usage)
   - Strategy: Minimize public surface area

---

## Conclusion

Phase 1 is **ready for immediate development**. All audits are complete, extraction plans are detailed, and risk mitigation strategies are in place.

### Go/No-Go Checklist

- ✅ Phase 0 complete (939/947 tests passing)
- ✅ All subsystems audited
- ✅ Extraction plans documented with line numbers
- ✅ Risk assessment complete
- ✅ Validation strategy defined
- ✅ Timeline estimated (20 days)
- ✅ Success metrics established
- ✅ Rollback strategy prepared
- ✅ Zero blocking issues identified

### Next Steps

1. **Review this master plan** with human oversight
2. **Approve Phase 1 scope** (or adjust based on priorities)
3. **Create Phase 1 git branch** for tracking
4. **Begin with Week 1 (Foundation):**
   - Dead code removal (30 minutes)
   - State.zig data structures (2.5 days)
5. **Validate continuously** after each extraction
6. **Track progress** in `emulation-state-decomposition-2025-10-09.md`

### Risk Assessment: 🟢 LOW

With proper incremental extraction, comprehensive testing after each step, and inline delegation to preserve APIs, Phase 1 carries **low overall risk** despite touching critical code paths.

**Recommendation:** ✅ **PROCEED WITH PHASE 1**

---

**Document Version:** 1.0
**Last Updated:** 2025-10-09
**Status:** Final - Ready for Development
**Authors:** Claude Code (AI) + Multiple Specialized Auditor Agents
**Review Required:** Human approval before implementation

---

## Quick Reference

**Key Documents:**
- This plan: `docs/refactoring/PHASE-1-MASTER-PLAN.md`
- State.zig audit: `docs/refactoring/state-zig-architecture-audit.md`
- State.zig extraction: `docs/refactoring/state-zig-extraction-plan.md`
- CPU audit: (generated by subagent)
- PPU audit: `docs/refactoring/ppu-subsystem-audit-2025-10-09.md`
- APU audit: (generated by subagent)

**Tracking:**
- Progress: `docs/refactoring/emulation-state-decomposition-2025-10-09.md`
- Phase 0 completion: `docs/refactoring/phase-0-completion-assessment.md`

**Communication:**
- Questions/concerns: Add to GitHub issues or project chat
- Daily updates: Update tracking document
- Blockers: Halt work, document issue, seek review
