# Phase 0-E: Harness Migration & Holistic Test Improvements

**Date:** 2025-10-09
**Purpose:** Comprehensive analysis of test patterns and Harness migration opportunities
**Process:** Holistic review - identify patterns, improvements, and high-value migrations

---

## Current State

**Test Files:** 63 total
**Harness Adoption:** 13/63 files (21%)
**EmulationState Direct:** 21 files
**Other Patterns:** 29 files (helpers, unit tests, etc.)

---

## Files Using Direct EmulationState (21 files)

### High-Priority Candidates (Integration Tests - 8 files)

| File | Tests | Complexity | Migration Value | Priority |
|------|-------|------------|-----------------|----------|
| `cpu_ppu_integration_test.zig` | ? | Medium | High | **P0** |
| `interrupt_execution_test.zig` | ? | Medium | High | **P0** |
| `nmi_sequence_test.zig` | ? | Medium | High | **P0** |
| `vblank_wait_test.zig` | ? | Low | High | **P0** |
| `ppu_register_absolute_test.zig` | ? | Low | Medium | P1 |
| `oam_dma_test.zig` | ? | Medium | Medium | P1 |
| `dpcm_dma_test.zig` | ? | Medium | Medium | P1 |
| `commercial_rom_test.zig` | ? | Low | Low | P2 |

### Medium-Priority Candidates (PPU Tests - 1 file)

| File | Tests | Complexity | Migration Value | Priority |
|------|-------|------------|-----------------|----------|
| `seek_behavior_test.zig` | ? | Low | High | **P0** |

### Low-Priority Candidates (Specialized/Complex - 12 files)

| File | Reason for Low Priority | Keep Pattern |
|------|-------------------------|--------------|
| `accuracycoin_test.zig` | ROM loading infrastructure | ✅ Keep |
| `prg_ram_test.zig` | Cartridge-specific testing | ✅ Keep |
| `bus_integration_test.zig` | Bus-level testing | Review |
| `open_bus_test.zig` | APU open bus behavior | Review |
| `timing_trace_test.zig` | Diagnostic/debugging tool | ✅ Keep |
| `instructions_test.zig` | CPU instruction suite | Review |
| `control_flow_test.zig` | CPU control flow | Review |
| `rmw_test.zig` | CPU read-modify-write | Review |
| `debugger_test.zig` | Debugger functionality | ✅ Keep |
| `rom_test_runner.zig` | ROM testing infrastructure | ✅ Keep |
| `snapshot_integration_test.zig` | Snapshot functionality | ✅ Keep |
| `threading_test.zig` | Thread safety testing | ✅ Keep |

---

## Holistic Test Improvements

### Pattern 1: Inconsistent Test Initialization

**Problem:** Some tests use manual setup, others use helpers
**Impact:** Code duplication, harder to maintain
**Solution:** Standardize on Harness pattern for integration tests

### Pattern 2: Direct State Manipulation

**Problem:** Tests directly manipulate `state.cpu.pc`, `state.ppu.status.vblank`
**Impact:** Brittle tests, coupled to implementation details
**Solution:** Harness provides abstraction layer

### Pattern 3: Timing Helpers Scattered

**Problem:** `seekToScanlineDot()` logic duplicated across tests
**Impact:** Inconsistent behavior, harder to update
**Solution:** Harness centralizes timing helpers

### Pattern 4: Test Documentation Quality

**Problem:** Many tests lack clear documentation of what they validate
**Impact:** Hard to understand coverage, hard to maintain
**Solution:** Standardize test documentation format

---

## Migration Strategy

### Phase 0-E Goals (High-Value, Low-Effort)

Focus on **integration tests** that benefit most from Harness:
1. CPU/PPU integration tests (3 files)
2. Interrupt/NMI tests (2 files)
3. VBlank wait test (1 file)
4. PPU seek behavior test (1 file)

**Target:** Migrate 7 high-priority files
**Estimated Time:** 4-6 hours
**Expected Benefit:** Standardized integration test pattern

### Files to Migrate (Priority Order)

**P0 - Critical Integration Tests (7 files):**
1. `tests/ppu/seek_behavior_test.zig` - PPU timing validation
2. `tests/integration/vblank_wait_test.zig` - VBlank polling patterns
3. `tests/integration/cpu_ppu_integration_test.zig` - CPU/PPU coordination
4. `tests/integration/interrupt_execution_test.zig` - Interrupt handling
5. `tests/integration/nmi_sequence_test.zig` - NMI timing
6. `tests/integration/ppu_register_absolute_test.zig` - PPU register access
7. `tests/integration/oam_dma_test.zig` - OAM DMA timing

**P1 - Consider for Later (optional):**
- `tests/integration/dpcm_dma_test.zig` - DPCM DMA timing
- `tests/bus/bus_integration_test.zig` - Bus routing
- `tests/cpu/instructions_test.zig` - CPU instruction suite

**P2 - Keep Existing Pattern:**
- All ROM loading tests (accuracycoin, commercial_rom, rom_test_runner)
- Debugger/snapshot/threading tests (specialized infrastructure)
- Diagnostic tests (timing_trace)

---

## Analysis Process

### Step 1: Read Each Test File
For each P0 file:
- Count number of tests
- Identify direct state access patterns
- Check for timing-sensitive code
- Assess migration complexity

### Step 2: Categorize Patterns
- **Simple migration:** Test only uses seekToScanlineDot, ppuRead/Write
- **Medium migration:** Test accesses cpu.pc, ppu.status directly
- **Complex migration:** Test requires CPU instruction setup (like bit_ppustatus)

### Step 3: Identify Improvements
- Can we consolidate duplicate tests?
- Can we improve test documentation?
- Can we add missing coverage?

---

## Expected Results

**Before Phase 0-E:**
- Harness adoption: 13/63 files (21%)
- Mixed patterns across integration tests
- Some test duplication

**After Phase 0-E:**
- Harness adoption: 20/63 files (32%)
- Consistent pattern for integration tests
- Clear documentation of test coverage
- Potential test count reduction (duplicates removed)

---

## Holistic Assessment & Recommendation

### Current Achievement (Phases 0-A through 0-D)
- ✅ Test files reduced: 77 → 63 (**target reached!**)
- ✅ Tests passing improved: 936/946 → 939/949
- ✅ Harness adoption: 7 → 13 files (+86% growth)
- ✅ Zero coverage loss across all consolidations
- ✅ Consistent patterns established

### Phase 0-E Migration Scope Analysis

**49 tests across 7 files** require migration to Harness. However:

**Complexity Factors:**
1. `vblank_wait_test.zig` - Custom ROM creation (24 lines of setup)
2. `cpu_ppu_integration_test.zig` - 21 tests (largest file)
3. `oam_dma_test.zig` - 14 tests (DMA timing validation)
4. `nmi_sequence_test.zig` - 5 tests (NMI timing critical)
5. `interrupt_execution_test.zig` - 3 tests
6. `ppu_register_absolute_test.zig` - 4 tests
7. `seek_behavior_test.zig` - 1 test (EASY - direct Harness equivalent)

**Estimated Effort:** 12-16 hours (not 8 hours)
**Risk:** High - many timing-sensitive integration tests

### Recommendation: **DEFER Phase 0-E to Post-Phase 2**

**Rationale:**

1. **Primary Goal Achieved** - Test file count target (63 files) reached
2. **Diminishing Returns** - Remaining migrations are complex integration tests
3. **Risk vs Reward** - High risk of breaking timing-sensitive tests for marginal benefit
4. **Better Timing** - After EmulationState decomposition (Phase 2), API will be more stable
5. **Test Infrastructure Needs** - Some migrations need Harness enhancements (ROM loading helpers)

**Alternative: Quick Win - Migrate 1 Easy File Only**

If any migration desired in Phase 0:
- **Migrate:** `seek_behavior_test.zig` (1 test, 5-minute effort, zero risk)
- **Result:** Harness adoption 13 → 14 files
- **Defer:** Remaining 48 tests to post-Phase 2

### Revised Phase 0-E Scope

**Option A (Recommended): Assessment Only**
- ✅ Create comprehensive inventory (DONE)
- ✅ Document migration complexity
- ✅ Defer to post-Phase 2
- **Time:** 1 hour (complete)

**Option B: Minimal Migration**
- ✅ Assessment (above)
- Migrate seek_behavior_test.zig only (1 test)
- Defer remaining 48 tests
- **Time:** 1.5 hours

**Option C: Full Migration (NOT RECOMMENDED)**
- Migrate all 49 tests
- High risk, long duration
- **Time:** 12-16 hours

## Next Steps

1. ✅ Create this inventory
2. ✅ Holistic assessment complete
3. ⏳ **Decision Point:** Choose Option A, B, or C
4. ⏳ Update tracking document with decision
5. ⏳ Commit Phase 0-E assessment

---

## Notes

**Harness Benefits:**
- Abstraction over EmulationState (robust against API changes)
- Centralized timing helpers (seekToScanlineDot)
- Consistent test pattern (easier to read/maintain)
- Better test isolation (Harness.deinit() cleanup)

**When NOT to Migrate:**
- ROM loading infrastructure (different concern)
- Debugger/snapshot/threading (specialized testing)
- Diagnostic/tracing tests (intentionally low-level)
- Tests requiring direct state manipulation for CPU instructions

**Migration Pattern:**
```zig
// Before
var config = Config.Config.init(testing.allocator);
defer config.deinit();
var state = EmulationState.init(&config);
state.reset();

// After
var harness = try Harness.init();
defer harness.deinit();
// Use harness.state when needed, harness.seekToScanlineDot(), etc.
```
