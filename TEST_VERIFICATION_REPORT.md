# Test Count Verification Report
**Generated:** 2025-10-07
**Purpose:** Verify all test-related claims in CLAUDE.md and documentation against actual test execution

---

## EXECUTIVE SUMMARY

### Actual Test Results (from `zig build test`)
- **885 tests PASSED**
- **1 test SKIPPED** (threading_test.zig - compilation error)
- **Build Status:** 97/100 steps succeeded; 1 failed

### Total Test Declarations Found
- **Tests directory:** 649 test declarations across 53 files
- **Src directory (embedded tests):** 201 test declarations across 37 files
- **GRAND TOTAL:** 850 test declarations

### Reconciliation
- **Build reports:** 885/886 tests
- **Source files contain:** 850 test declarations
- **Difference:** ~35 tests may be generated programmatically or counted differently

---

## KEY FINDING

**There are MAJOR DISCREPANCIES between documentation claims and actual test counts.**

The documentation significantly understates the total test count in several categories:
- CPU tests: Documented 105, Actual 264+ (151% more)
- Integration tests: Documented 35, Actual 94 (168% more)
- Cartridge tests: Documented 2, Actual 13 (550% more)
- Several test categories not mentioned at all (Threading, iNES, Config)

---

## DETAILED COMPARISON: DOCUMENTED vs ACTUAL

### Overall Test Count Claims

| Documentation Location | Documented | Actual | Status |
|------------------------|-----------|--------|--------|
| CLAUDE.md Line 15 | "887/888 tests passing (99.9%)" | **885/886 passing** | ❌ INCORRECT |
| CLAUDE.md Line 238 | "Total: 876/878 tests passing (99.8%)" | **885/886 passing** | ❌ INCORRECT |

---

## CATEGORY-BY-CATEGORY BREAKDOWN

### CPU Tests

| Source | Documented | Actual | Status |
|--------|-----------|--------|--------|
| CLAUDE.md Line 239 | "105 unit + integration tests" | **264 tests** in tests/cpu/ | ❌ **SEVERELY UNDERSTATED** |

**Actual CPU Test Files:**
```
tests/cpu/
├── instructions_test.zig           30 tests
├── rmw_test.zig                    18 tests
├── page_crossing_test.zig           9 tests
├── bus_integration_test.zig         4 tests
├── dispatch_debug_test.zig          3 tests
└── diagnostics/
    └── timing_trace_test.zig        6 tests

tests/cpu/opcodes/
├── unofficial_test.zig             45 tests
├── loadstore_test.zig              21 tests
├── compare_test.zig                18 tests
├── arithmetic_test.zig             17 tests
├── transfer_test.zig               16 tests
├── shifts_test.zig                 16 tests
├── incdec_test.zig                 15 tests
├── branch_test.zig                 12 tests
├── control_flow_test.zig           12 tests
├── logical_test.zig                 9 tests
├── jumps_test.zig                   7 tests
└── stack_test.zig                   6 tests

TOTAL: 264 tests
```

**Additional CPU tests in src/:**
- src/cpu/constants.zig: 6 tests
- src/cpu/decode.zig: 5 tests
- src/cpu/variants.zig: 5 tests

**CPU GRAND TOTAL: ~280 tests** (documented as 105)

---

### PPU Tests

| Source | Documented | Actual | Status |
|--------|-----------|--------|--------|
| CLAUDE.md Line 240 | "79 tests" | **79 tests** | ✅ **CORRECT** |

**Actual PPU Test Files:**
```
tests/ppu/
├── sprite_edge_cases_test.zig      35 tests
├── sprite_rendering_test.zig       23 tests
├── sprite_evaluation_test.zig      15 tests
└── chr_integration_test.zig         6 tests

TOTAL: 79 tests
```

**Additional PPU tests in src/:**
- src/ppu/timing.zig: 6 tests
- src/ppu/palette.zig: 5 tests

**PPU GRAND TOTAL: ~90 tests** (documented as 79)

---

### APU Tests

| Source | Documented | Actual | Status |
|--------|-----------|--------|--------|
| CLAUDE.md Line 568 | "131/131 tests passing (100%)" | **135 tests** | ❌ UNDERSTATED |

**Actual APU Test Files:**
```
tests/apu/
├── dmc_test.zig                    25 tests
├── length_counter_test.zig         25 tests
├── sweep_test.zig                  25 tests
├── envelope_test.zig               20 tests
├── linear_counter_test.zig         15 tests
├── frame_irq_edge_test.zig         10 tests
├── apu_test.zig                     8 tests
└── open_bus_test.zig                7 tests

TOTAL: 135 tests (documented as 131)
```

---

### Debugger Tests

| Source | Documented | Actual | Status |
|--------|-----------|--------|--------|
| CLAUDE.md Line 241 | "62 tests" | **62 tests** | ✅ **CORRECT** |

**Actual:**
- tests/debugger/debugger_test.zig: 62 tests
- src/debugger/Debugger.zig: 4 tests

**TOTAL: ~66 tests** (documented as 62)

---

### Controller Tests

| Source | Documented | Actual | Status |
|--------|-----------|--------|--------|
| CLAUDE.md Line 242 | "14 tests" | **14 tests** | ✅ **CORRECT** |

**Actual:**
- tests/integration/controller_test.zig: 14 tests

---

### Input System Tests

| Source | Documented | Actual | Status |
|--------|-----------|--------|--------|
| CLAUDE.md Line 243 | "41 tests (21 ButtonState + 20 KeyboardMapper)" | **40 tests (19 + 21)** | ❌ SLIGHTLY INCORRECT |

**Actual:**
- tests/input/button_state_test.zig: 19 tests (documented as 21)
- tests/input/keyboard_mapper_test.zig: 21 tests (documented as 20)

**TOTAL: 40 tests** (documented as 41)

---

### Mailbox Tests

| Source | Documented | Actual | Status |
|--------|-----------|--------|--------|
| CLAUDE.md Line 244 | "6 tests (ControllerInputMailbox)" | **50+ tests** | ❌ **SEVERELY UNDERSTATED** |

**Actual mailbox tests in src/mailboxes/:**
```
src/mailboxes/
├── XdgInputEventMailbox.zig         7 tests
├── SpscRingBuffer.zig               7 tests
├── RenderStatusMailbox.zig          7 tests
├── XdgWindowEventMailbox.zig        6 tests
├── SpeedControlMailbox.zig          6 tests
├── EmulationStatusMailbox.zig       6 tests
├── ControllerInputMailbox.zig       6 tests
├── EmulationCommandMailbox.zig      5 tests
├── FrameMailbox.zig                 4 tests
├── ConfigMailbox.zig                2 tests
└── Mailboxes.zig                    1 test

TOTAL: 57 mailbox tests (documented as 6)
```

---

### Bus & Memory Tests

| Source | Documented | Actual | Status |
|--------|-----------|--------|--------|
| CLAUDE.md Line 245 | "17 tests" | **17 tests** | ✅ **CORRECT** |

**Actual:**
- tests/bus/bus_integration_test.zig: 17 tests

---

### Cartridge Tests

| Source | Documented | Actual | Status |
|--------|-----------|--------|--------|
| CLAUDE.md Line 246 | "2 tests (NROM loader/validation)" | **13 tests** in tests/ + **27 tests** in src/ | ❌ **SEVERELY UNDERSTATED** |

**Actual Test Files:**
```
tests/cartridge/
├── prg_ram_test.zig                11 tests
└── accuracycoin_test.zig            2 tests

src/cartridge/
├── ines.zig                         9 tests
├── Cartridge.zig                    9 tests
├── mappers/Mapper0.zig              8 tests
├── mappers/registry.zig             5 tests
├── loader.zig                       2 tests
└── ines/mod.zig                     2 tests

TOTAL: 48 tests (documented as 2)
```

---

### Integration Tests

| Source | Documented | Actual | Status |
|--------|-----------|--------|--------|
| CLAUDE.md Line 249 | "35 tests" | **94 tests** | ❌ **SEVERELY UNDERSTATED** |

**Actual Integration Test Files:**
```
tests/integration/
├── input_integration_test.zig      22 tests
├── cpu_ppu_integration_test.zig    21 tests
├── controller_test.zig             14 tests
├── oam_dma_test.zig                14 tests
├── ppu_register_absolute_test.zig   4 tests
├── accuracycoin_execution_test.zig  4 tests
├── accuracycoin_prg_ram_test.zig    3 tests
├── benchmark_test.zig               3 tests
├── dpcm_dma_test.zig                3 tests
├── rom_test_runner.zig              3 tests
├── bit_ppustatus_test.zig           2 tests
└── vblank_wait_test.zig             1 test

TOTAL: 94 tests (documented as 35)
```

---

### Snapshot Tests

| Source | Documented | Actual | Status |
|--------|-----------|--------|--------|
| CLAUDE.md Line 248 | "8/9 tests (1 failing)" | **9 tests** in tests/ + **14 tests** in src/ | ⚠️ UNDERSTATED |

**Actual:**
```
tests/snapshot/
└── snapshot_integration_test.zig    9 tests

src/snapshot/
├── binary.zig                       6 tests
├── checksum.zig                     3 tests
├── cartridge.zig                    3 tests
└── Snapshot.zig                     2 tests

TOTAL: 23 tests (documented as 8/9)
```

---

### Comptime Tests

| Source | Documented | Actual | Status |
|--------|-----------|--------|--------|
| CLAUDE.md Line 250 | "8 compile-time validation suites" | **8 tests** | ✅ **CORRECT** |

**Actual:**
- tests/comptime/poc_mapper_generics.zig: 8 tests

---

### UNDOCUMENTED TEST CATEGORIES

These test categories exist but are **NOT mentioned** in CLAUDE.md test status section:

#### Threading Tests
- tests/threads/threading_test.zig: **14 tests** (1 skipped due to compilation error)
- src/threads/EmulationThread.zig: 3 tests
- src/threads/RenderThread.zig: 2 tests
- **TOTAL: ~19 tests**

#### iNES Tests
- tests/ines/ines_test.zig: **26 tests**

#### Config Tests
- tests/config/parser_test.zig: **15 tests**
- src/config/Config.zig: 15 tests
- **TOTAL: ~30 tests**

#### Emulation State Tests
- src/emulation/State.zig: **12 tests**
- src/emulation/MasterClock.zig: 15 tests
- **TOTAL: ~27 tests**

#### Timing Tests
- src/timing/FrameTimer.zig: **4 tests**

#### Benchmark Tests
- src/benchmark/Benchmark.zig: **8 tests**

#### Memory Tests
- src/memory/CartridgeChrAdapter.zig: **3 tests**

#### Main Tests
- src/main.zig: **2 tests**

**Total undocumented tests: ~144 tests**

---

## ACTUAL TEST CATEGORY SUMMARY

| Category | Tests in tests/ | Tests in src/ | Total | Documented |
|----------|----------------|---------------|-------|------------|
| **CPU** | 264 | 16 | ~280 | 105 |
| **PPU** | 79 | 11 | ~90 | 79 |
| **APU** | 135 | 0 | 135 | 131 |
| **Debugger** | 62 | 4 | ~66 | 62 |
| **Controller** | 14 | 0 | 14 | 14 |
| **Input System** | 40 | 0 | 40 | 41 |
| **Mailboxes** | 0 | 57 | 57 | 6 |
| **Bus & Memory** | 17 | 3 | ~20 | 17 |
| **Cartridge** | 13 | 35 | ~48 | 2 |
| **Integration** | 94 | 0 | 94 | 35 |
| **Snapshot** | 9 | 14 | ~23 | 8 |
| **Comptime** | 8 | 0 | 8 | 8 |
| **Threading** | 14 | 5 | ~19 | NOT MENTIONED |
| **iNES** | 26 | 0 | 26 | NOT MENTIONED |
| **Config** | 15 | 15 | ~30 | NOT MENTIONED |
| **Emulation** | 0 | 27 | ~27 | NOT MENTIONED |
| **Timing** | 0 | 4 | 4 | NOT MENTIONED |
| **Benchmark** | 0 | 8 | 8 | NOT MENTIONED |
| **Other** | 0 | 2 | 2 | NOT MENTIONED |
| **TOTAL** | **649** | **201** | **~850** | **508** |

---

## FAILING/SKIPPED TESTS

### 1. Threading Test Compilation Error

**File:** `tests/threads/threading_test.zig`

**Error Messages:**
```
tests/threads/threading_test.zig:65:11: error: unused local constant
    const initial_count = mailboxes.frame.getFrameCount();
          ^~~~~~~~~~~~~
tests/threads/threading_test.zig:326:43: error: use of undeclared identifier 'initial_count'
    const frames_first_half = mid_count - initial_count;
                                          ^~~~~~~~~~~~~
```

**Root Cause:** Variable `initial_count` declared on line 65 but never used in that test function, then incorrectly referenced on line 326 in a different test function where it's not in scope.

**Impact:**
- 1 test file fails compilation
- 14 tests not executed
- Build step fails (97/100 steps succeeded)

**Severity:** LOW - Simple code error, easy to fix

**Fix Required:** Either use `initial_count` in the first test, or declare it in the second test where it's needed.

---

## CRITICAL DISCREPANCIES SUMMARY

### 1. Total Test Count Significantly Understated
- **Documented:** 887/888 tests
- **Actual (build):** 885/886 tests passing + 14 not run = ~900 total
- **Actual (source):** 850 test declarations found
- **Discrepancy:** ~50-60 tests difference

### 2. CPU Tests Severely Understated (151% error)
- **Documented:** 105 tests
- **Actual:** 280+ tests
- **Missing:** 175 tests not counted

### 3. Integration Tests Severely Understated (168% error)
- **Documented:** 35 tests
- **Actual:** 94 tests
- **Missing:** 59 tests not counted

### 4. Mailbox Tests Severely Understated (850% error)
- **Documented:** 6 tests
- **Actual:** 57 tests
- **Missing:** 51 tests not counted

### 5. Cartridge Tests Severely Understated (2300% error)
- **Documented:** 2 tests
- **Actual:** 48 tests
- **Missing:** 46 tests not counted

### 6. Major Test Categories Completely Undocumented
The following categories exist but are not mentioned in CLAUDE.md:
- Threading: ~19 tests
- iNES: 26 tests
- Config: ~30 tests
- Emulation: ~27 tests
- Timing: 4 tests
- Benchmark: 8 tests

**Total undocumented: ~144 tests**

---

## RECONCILIATION: WHY THE NUMBERS DON'T MATCH

### Build Reports vs Source Declarations

**Build output:** 885/886 tests passed
**Source files:** 850 test declarations found

**Difference:** ~35 tests

**Possible explanations:**
1. **Comptime-generated tests** - Some tests may be generated programmatically
2. **Multiple test configurations** - Some tests may run multiple times with different settings
3. **Test infrastructure** - Some tests may be in build.zig or other non-source locations
4. **Counting methodology** - Simple `grep "^test "` may miss some test declarations

### Documentation vs Reality

**Documented total:** 508 tests (sum of all documented categories)
**Actual total:** 850+ test declarations

**Difference:** ~342 tests

**Root cause:** Documentation is severely out of date and doesn't account for:
- Tests embedded in src/ files (201 tests)
- New test categories added during development
- Test suite expansion over time

---

## RECOMMENDATIONS

### IMMEDIATE ACTIONS

1. **Fix threading test compilation error**
   - File: `tests/threads/threading_test.zig`
   - Lines: 65, 326
   - Fix: Properly scope the `initial_count` variable
   - Impact: Will restore 14 tests and achieve 899/900 tests passing

2. **Update CLAUDE.md test counts** (All sections)
   - Update total test count: 887/888 → 885/886 (or 899/900 after fix)
   - Update CPU tests: 105 → 280+
   - Update Integration tests: 35 → 94
   - Update Mailbox tests: 6 → 57
   - Update Cartridge tests: 2 → 48
   - Update APU tests: 131 → 135

3. **Add missing test categories to documentation**
   - Threading tests: ~19 tests
   - iNES tests: 26 tests
   - Config tests: ~30 tests
   - Emulation tests: ~27 tests
   - Timing tests: 4 tests
   - Benchmark tests: 8 tests

### ONGOING MAINTENANCE

4. **Create automated test counting script**
   - Parse both tests/ and src/ directories
   - Generate accurate counts by category
   - Run as part of CI/CD pipeline
   - Auto-update documentation or fail build if drift detected

5. **Establish test documentation policy**
   - All new tests must be added to category counts
   - Documentation updates required in same PR as test additions
   - Regular audits (monthly) to prevent drift

6. **Standardize test organization**
   - Document rationale for tests in src/ vs tests/
   - Consider moving all tests to tests/ for consistency
   - Or document clearly which modules should have embedded tests

---

## CONCLUSION

The test suite is **significantly larger and more comprehensive** than documented:
- **Actual:** 850+ tests across 90+ files
- **Documented:** 508 tests across select categories

**The emulator has MORE test coverage than the documentation suggests**, which is positive from a quality perspective but negative from a documentation accuracy perspective.

**Priority:** Update documentation to reflect reality and establish automated verification to prevent future drift.

---

## APPENDIX A: Complete Test File List

### Tests Directory (649 tests across 53 files)

**CPU Tests (264 tests):**
```
tests/cpu/instructions_test.zig              30
tests/cpu/rmw_test.zig                       18
tests/cpu/page_crossing_test.zig              9
tests/cpu/bus_integration_test.zig            4
tests/cpu/dispatch_debug_test.zig             3
tests/cpu/diagnostics/timing_trace_test.zig   6
tests/cpu/opcodes/unofficial_test.zig        45
tests/cpu/opcodes/loadstore_test.zig         21
tests/cpu/opcodes/compare_test.zig           18
tests/cpu/opcodes/arithmetic_test.zig        17
tests/cpu/opcodes/transfer_test.zig          16
tests/cpu/opcodes/shifts_test.zig            16
tests/cpu/opcodes/incdec_test.zig            15
tests/cpu/opcodes/branch_test.zig            12
tests/cpu/opcodes/control_flow_test.zig      12
tests/cpu/opcodes/logical_test.zig            9
tests/cpu/opcodes/jumps_test.zig              7
tests/cpu/opcodes/stack_test.zig              6
```

**PPU Tests (79 tests):**
```
tests/ppu/sprite_edge_cases_test.zig         35
tests/ppu/sprite_rendering_test.zig          23
tests/ppu/sprite_evaluation_test.zig         15
tests/ppu/chr_integration_test.zig            6
```

**APU Tests (135 tests):**
```
tests/apu/dmc_test.zig                       25
tests/apu/length_counter_test.zig            25
tests/apu/sweep_test.zig                     25
tests/apu/envelope_test.zig                  20
tests/apu/linear_counter_test.zig            15
tests/apu/frame_irq_edge_test.zig            10
tests/apu/apu_test.zig                        8
tests/apu/open_bus_test.zig                   7
```

**Integration Tests (94 tests):**
```
tests/integration/input_integration_test.zig         22
tests/integration/cpu_ppu_integration_test.zig       21
tests/integration/controller_test.zig                14
tests/integration/oam_dma_test.zig                   14
tests/integration/ppu_register_absolute_test.zig      4
tests/integration/accuracycoin_execution_test.zig     4
tests/integration/accuracycoin_prg_ram_test.zig       3
tests/integration/benchmark_test.zig                  3
tests/integration/dpcm_dma_test.zig                   3
tests/integration/rom_test_runner.zig                 3
tests/integration/bit_ppustatus_test.zig              2
tests/integration/vblank_wait_test.zig                1
```

**Other Test Files:**
```
tests/debugger/debugger_test.zig             62
tests/input/keyboard_mapper_test.zig         21
tests/input/button_state_test.zig            19
tests/ines/ines_test.zig                     26
tests/bus/bus_integration_test.zig           17
tests/config/parser_test.zig                 15
tests/threads/threading_test.zig             14
tests/cartridge/prg_ram_test.zig             11
tests/snapshot/snapshot_integration_test.zig  9
tests/comptime/poc_mapper_generics.zig        8
tests/cartridge/accuracycoin_test.zig         2
```

### Source Directory (201 tests across 37 files)

**Highest test counts:**
```
src/emulation/MasterClock.zig                15
src/config/Config.zig                        15
src/emulation/State.zig                      12
src/cartridge/ines.zig                        9
src/cartridge/Cartridge.zig                   9
src/cartridge/mappers/Mapper0.zig             8
src/benchmark/Benchmark.zig                   8
```

**Mailbox tests (57 total):**
```
src/mailboxes/XdgInputEventMailbox.zig        7
src/mailboxes/SpscRingBuffer.zig              7
src/mailboxes/RenderStatusMailbox.zig         7
src/mailboxes/XdgWindowEventMailbox.zig       6
src/mailboxes/SpeedControlMailbox.zig         6
src/mailboxes/EmulationStatusMailbox.zig      6
src/mailboxes/ControllerInputMailbox.zig      6
src/mailboxes/EmulationCommandMailbox.zig     5
src/mailboxes/FrameMailbox.zig                4
src/mailboxes/ConfigMailbox.zig               2
src/mailboxes/Mailboxes.zig                   1
```

**Other source tests:**
```
src/ppu/timing.zig                            6
src/ppu/palette.zig                           5
src/snapshot/binary.zig                       6
src/snapshot/checksum.zig                     3
src/snapshot/cartridge.zig                    3
src/snapshot/Snapshot.zig                     2
src/cpu/constants.zig                         6
src/cpu/decode.zig                            5
src/cpu/variants.zig                          5
src/cartridge/mappers/registry.zig            5
src/timing/FrameTimer.zig                     4
src/debugger/Debugger.zig                     4
src/threads/EmulationThread.zig               3
src/threads/RenderThread.zig                  2
src/memory/CartridgeChrAdapter.zig            3
src/cartridge/loader.zig                      2
src/cartridge/ines/mod.zig                    2
src/main.zig                                  2
```

---

**END OF REPORT**
