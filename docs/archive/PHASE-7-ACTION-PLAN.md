# Phase 7: Sprite Implementation - Revised Action Plan

**Date:** 2025-10-04
**Status:** READY FOR PHASE 7A (Test Infrastructure)
**Critical Finding:** QA review identified insufficient test coverage - must create test infrastructure BEFORE sprite implementation

---

## Executive Summary

Based on comprehensive code reviews by three specialist agents (backend-architect, performance-engineer, qa-code-review-pro), Phase 7 must be restructured into three sub-phases:

**Original Plan:** 29-42 hours (sprite implementation only)
**Revised Plan:** 85-118 hours (test infrastructure + implementation + validation)

**CRITICAL:** Do NOT start sprite implementation until Phase 7A (test infrastructure) is complete.

---

## Phase 7 Restructuring

### Phase 7A: Test Infrastructure ⚠️ **BLOCKING - MUST BE FIRST**
**Duration:** 28-38 hours
**Tests Added:** 70-80 tests
**Current Coverage:** 496 tests → 566-576 tests (77%)

### Phase 7B: Sprite Implementation
**Duration:** 29-42 hours
**Tests Added:** 50 tests
**Current Coverage:** 566-576 tests → 616-626 tests (84%)

### Phase 7C: Validation & Integration
**Duration:** 28-38 hours
**Tests Added:** 52 tests
**Current Coverage:** 616-626 tests → 668-678 tests (92%)

**Total Phase 7:** 85-118 hours, 172-182 new tests

---

## Phase 7A: Test Infrastructure (NEXT PRIORITY)

### Objective
Create comprehensive test foundation to catch regressions and validate sprite implementation correctness.

### Sub-Phase 7A.1: Bus Integration Tests (8-12 hours)

**Priority:** CRITICAL - Zero bus integration tests currently exist

**Test File:** `tests/bus/bus_integration_test.zig` (NEW)

**Required Tests (15-20 tests):**

1. **RAM Mirroring Tests (4 tests)**
   ```zig
   test "Bus: Write to $0000 visible at all mirrors" {
       // Write 0x42 to $0100
       // Verify visible at $0500, $0900, $0D00, $1100, $1500, $1900, $1D00
   }

   test "Bus: RAM mirroring boundary ($1FFF → $0000)" { }
   test "Bus: Mirroring preserves data across all regions" { }
   test "Bus: Write to mirror affects base address" { }
   ```

2. **PPU Register Mirroring Tests (3 tests)**
   ```zig
   test "Bus: PPU registers mirrored every 8 bytes" {
       // Write to $2000, verify mirrored at $2008, $2010, ..., $3FF8
   }

   test "Bus: PPU mirroring boundary ($3FFF → $2000)" { }
   test "Bus: All PPU mirrors route to same register" { }
   ```

3. **ROM Write Protection Tests (2 tests)**
   ```zig
   test "Bus: ROM write does not modify cartridge" {
       // Attempt write to $8000-$FFFF
       // Verify ROM unchanged
   }

   test "Bus: ROM write triggers open bus update" { }
   ```

4. **Open Bus Behavior Tests (4 tests)**
   ```zig
   test "Bus: Read from unmapped address returns last bus value" { }
   test "Bus: Open bus decays over time" { }
   test "Bus: PPU status bits 0-4 are open bus" { }
   test "Bus: Controller bits 5-7 are open bus" { }
   ```

5. **Cartridge Routing Tests (4 tests)**
   ```zig
   test "Bus: $4020-$7FFF routes to cartridge expansion" { }
   test "Bus: $8000-$FFFF routes to cartridge ROM" { }
   test "Bus: PRG-RAM write through bus to cartridge" { }
   test "Bus: Mapper register writes route correctly" { }
   ```

**Acceptance Criteria:**
- [ ] All 15-20 bus integration tests passing
- [ ] Zero regressions in existing 17 bus tests
- [ ] Bus behavior validated before adding sprite complexity

**Estimated Effort:** 8-12 hours

---

### Sub-Phase 7A.2: CPU-PPU Integration Tests (12-16 hours)

**Priority:** CRITICAL - Zero integration tests currently exist

**Test File:** `tests/integration/cpu_ppu_integration_test.zig` (NEW)

**Required Tests (20-25 tests):**

1. **NMI Triggering Tests (5 tests)**
   ```zig
   test "Integration: PPU VBlank triggers CPU NMI" {
       // Enable NMI (PPUCTRL bit 7)
       // Advance to VBlank (scanline 241, dot 1)
       // Verify CPU NMI sequence begins
   }

   test "Integration: NMI suppression via $2002 read" {
       // Read $2002 on exact VBlank set cycle
       // Verify NMI suppressed
   }

   test "Integration: NMI disabled mid-VBlank" { }
   test "Integration: NMI during CPU instruction execution" { }
   test "Integration: Multiple NMI edge detection" { }
   ```

2. **PPU Register Access Tests (6 tests)**
   ```zig
   test "Integration: CPU write to $2000 updates PPUCTRL" { }
   test "Integration: CPU write to $2006 updates PPUADDR" {
       // Two writes required (high byte, low byte)
       // Verify address latch behavior
   }

   test "Integration: CPU read from $2002 clears VBlank flag" { }
   test "Integration: CPU read from $2002 resets address latch" { }
   test "Integration: $2007 access during rendering" {
       // Different behavior during rendering vs VBlank
   }
   test "Integration: $2007 read buffer behavior" { }
   ```

3. **DMA Suspension Tests (4 tests)**
   ```zig
   test "Integration: $4014 write suspends CPU" {
       // Write to $4014
       // Verify CPU suspended for 513-514 cycles
   }

   test "Integration: DMA odd/even cycle alignment" {
       // Odd CPU cycle: 514 cycles
       // Even CPU cycle: 513 cycles
   }

   test "Integration: DMA copies 256 bytes to OAM" { }
   test "Integration: DMA during rendering edge case" { }
   ```

4. **Rendering Effects on Register Behavior (5 tests)**
   ```zig
   test "Integration: $2007 increment during rendering" {
       // Rendering enabled: Coarse X/Y increment (wrong behavior)
       // VBlank: Normal address increment
   }

   test "Integration: OAMADDR corruption during rendering" { }
   test "Integration: Scroll register writes during rendering" { }
   test "Integration: PPUCTRL changes during rendering" { }
   test "Integration: Address latch behavior during rendering" { }
   ```

5. **Race Condition Edge Cases (5 tests)**
   ```zig
   test "Integration: VBlank flag read/clear race" { }
   test "Integration: Address latch reset race" { }
   test "Integration: OAM write during sprite evaluation" { }
   test "Integration: Palette write during rendering" { }
   test "Integration: Scroll write during rendering" { }
   ```

**Acceptance Criteria:**
- [ ] All 20-25 CPU-PPU integration tests passing
- [ ] NMI triggering validated
- [ ] Register access timing correct
- [ ] DMA suspension accurate

**Estimated Effort:** 12-16 hours

---

### Sub-Phase 7A.3: Expanded Sprite Test Coverage (8-10 hours)

**Priority:** HIGH - Current 38 tests insufficient

**Test Files:**
- `tests/ppu/sprite_evaluation_test.zig` (EXPAND)
- `tests/ppu/sprite_rendering_test.zig` (EXPAND)
- `tests/ppu/sprite_edge_cases_test.zig` (NEW)

**Required Additional Tests (35 tests):**

1. **Sprite 0 Hit Edge Cases (8 tests) - NEW**
   ```zig
   test "Sprite 0 Hit: Not set at X=255 (hardware limitation)" { }
   test "Sprite 0 Hit: Timing with background scroll" { }
   test "Sprite 0 Hit: With sprite priority=1 (behind background)" { }
   test "Sprite 0 Hit: Detection on first non-transparent pixel" { }
   test "Sprite 0 Hit: Earliest detection at cycle 2 (not cycle 1)" { }
   test "Sprite 0 Hit: With left column clipping enabled" { }
   test "Sprite 0 Hit: Clearing mid-frame behavior" { }
   test "Sprite 0 Hit: Sprite 0 not in secondary OAM slot 0" { }
   ```

2. **Overflow Hardware Bug Tests (6 tests) - NEW**
   ```zig
   test "Sprite Overflow: False positive with n+1 increment bug" { }
   test "Sprite Overflow: Diagonal OAM scan pattern" { }
   test "Sprite Overflow: Mixed sprite heights (8x8 vs 8x16)" { }
   test "Sprite Overflow: With rendering disabled" { }
   test "Sprite Overflow: Correct detection vs buggy detection" { }
   test "Sprite Overflow: Clear at pre-render scanline" { }
   ```

3. **8×16 Mode Comprehensive Tests (10 tests) - NEW**
   ```zig
   test "Sprite 8x16: Top half tile selection" { }
   test "Sprite 8x16: Bottom half tile selection" { }
   test "Sprite 8x16: Pattern table from tile bit 0" { }
   test "Sprite 8x16: Vertical flip across both tiles" { }
   test "Sprite 8x16: Row calculation for bottom half" { }
   test "Sprite 8x16: In-range detection (16 pixel height)" { }
   test "Sprite 8x16: Pattern address calculation top half" { }
   test "Sprite 8x16: Pattern address calculation bottom half" { }
   test "Sprite 8x16: Rendering both tiles correctly" { }
   test "Sprite 8x16: Switching to 8x8 mid-frame" { }
   ```

4. **Transparency Edge Cases (6 tests) - NEW**
   ```zig
   test "Sprite Transparency: Transparent over opaque background" { }
   test "Sprite Transparency: Opaque over transparent background" { }
   test "Sprite Transparency: Multiple overlapping transparent sprites" { }
   test "Sprite Transparency: Color 0 always transparent" { }
   test "Sprite Transparency: Priority with transparent pixels" { }
   test "Sprite Transparency: Sprite 0 hit with transparent pixels" { }
   ```

5. **Additional Timing Tests (5 tests) - NEW**
   ```zig
   test "Sprite Timing: Evaluation only on visible scanlines" { }
   test "Sprite Timing: Fetch on pre-render scanline for scanline 0" { }
   test "Sprite Timing: No evaluation during VBlank" { }
   test "Sprite Timing: Secondary OAM clear exact cycle count" { }
   test "Sprite Timing: Sprite fetch garbage read timing" { }
   ```

**Acceptance Criteria:**
- [ ] 35 additional sprite edge case tests created
- [ ] All tests compile successfully
- [ ] Tests document expected failures (implementation pending)
- [ ] Total sprite tests: 73 (38 existing + 35 new)

**Estimated Effort:** 8-10 hours

---

### Phase 7A Summary

**Total Duration:** 28-38 hours
**Total New Tests:** 70-80 tests
**Coverage Increase:** 496 tests → 566-576 tests (77%)

**Deliverables:**
- ✅ 15-20 bus integration tests passing
- ✅ 20-25 CPU-PPU integration tests passing
- ✅ 35 additional sprite edge case tests created
- ✅ Solid test foundation for sprite implementation
- ✅ Zero critical gaps in test coverage

**Phase 7A Completion Criteria:**
- [ ] All bus integration tests passing
- [ ] All CPU-PPU integration tests passing
- [ ] All sprite edge case tests created (expected failures documented)
- [ ] Build system updated with new test categories
- [ ] Documentation updated with test coverage report

**Next:** Phase 7B (Sprite Implementation) can begin

---

## Phase 7B: Sprite Implementation (Original Plan)

**Duration:** 29-42 hours
**Prerequisites:** ✅ Phase 7A complete

### Sub-Phase 7B.1: Sprite Evaluation (8-12 hours)

**Implementation:** `src/ppu/State.zig`, `src/ppu/Logic.zig`

**Tasks:**
1. Add sprite evaluation state to PpuState
2. Implement clearSecondaryOam() (cycles 1-64)
3. Implement isSpriteInRange()
4. Implement evaluateSprites() (cycles 65-256)
5. Implement overflow detection (with hardware bug)

**Tests:** 15 existing evaluation tests + 15 new edge case tests = 30 tests should pass

**Acceptance Criteria:**
- [ ] Secondary OAM clearing verified (cycles 1-64)
- [ ] Sprite in-range detection 100% accurate
- [ ] 8-sprite limit enforced
- [ ] Overflow flag behavior matches hardware (including bugs)
- [ ] All timing constraints validated

---

### Sub-Phase 7B.2: Sprite Fetching (6-8 hours)

**Implementation:** `src/ppu/State.zig`, `src/ppu/Logic.zig`

**Tasks:**
1. Add SpriteState struct with shift registers
2. Implement getSpritePatternAddress() (8×8 mode)
3. Implement getSprite16PatternAddress() (8×16 mode)
4. Implement fetchSprites() (cycles 257-320)
5. Implement vertical flip support

**Tests:** 23 existing rendering tests + 12 new pattern tests = 35 tests should pass

**Acceptance Criteria:**
- [ ] Pattern address calculation 100% accurate
- [ ] Garbage nametable fetches occur at correct cycles
- [ ] Pattern data fetched correctly
- [ ] Shift registers loaded correctly
- [ ] 8×8 and 8×16 modes both working

---

### Sub-Phase 7B.3: Sprite Rendering (8-12 hours)

**Implementation:** `src/ppu/Logic.zig`

**Tasks:**
1. Implement getSpritePixel()
2. Integrate sprite + background pixels
3. Implement sprite priority system
4. Implement sprite 0 hit detection
5. Implement horizontal flip support

**Tests:** 38 existing sprite tests + 22 new rendering tests = 60 tests should pass

**Acceptance Criteria:**
- [ ] Sprites render at correct X/Y positions
- [ ] Priority system correct
- [ ] Sprite 0 hit detection accurate (including edge cases)
- [ ] Palette selection working
- [ ] Horizontal/vertical flip working
- [ ] Transparency handled correctly

---

### Sub-Phase 7B.4: OAM DMA (3-4 hours)

**Implementation:** `src/bus/Logic.zig`

**Tasks:**
1. Implement $4014 write handler
2. Implement 256-byte copy from CPU RAM to OAM
3. Implement CPU suspension (513-514 cycles)
4. Handle odd/even cycle alignment

**Tests:** 8 new OAM DMA tests should pass

**Acceptance Criteria:**
- [ ] $4014 write triggers DMA
- [ ] 256 bytes copied correctly
- [ ] CPU suspended for correct cycle count
- [ ] Alignment handled correctly

---

### Phase 7B Summary

**Total Duration:** 29-42 hours (original estimate)
**Total New Tests:** 50 tests (added during implementation)
**Coverage Increase:** 566-576 tests → 616-626 tests (84%)

**Deliverables:**
- ✅ All 123 sprite tests passing (15 evaluation + 23 rendering + 35 edge cases + 8 DMA + 42 new)
- ✅ Sprite system fully functional
- ✅ OAM DMA working
- ✅ Ready for validation phase

**Phase 7B Completion Criteria:**
- [ ] All sprite evaluation tests passing (30 tests)
- [ ] All sprite fetching tests passing (35 tests)
- [ ] All sprite rendering tests passing (60 tests)
- [ ] All OAM DMA tests passing (8 tests)
- [ ] All 23 background rendering tests still passing (no regression)
- [ ] Visual verification with test ROMs

**Next:** Phase 7C (Validation & Integration)

---

## Phase 7C: Validation & Integration (NEW)

**Duration:** 28-38 hours
**Prerequisites:** ✅ Phase 7B complete

### Sub-Phase 7C.1: Regression Test Suite (16-20 hours)

**Priority:** HIGH - Prevents future regressions

**Test Files:**
- `tests/regression/cpu_regressions_test.zig` (NEW)
- `tests/regression/ppu_regressions_test.zig` (NEW)
- `tests/regression/timing_regressions_test.zig` (NEW)
- `tests/regression/integration_regressions_test.zig` (NEW)

**Required Tests (40 tests):**

1. **CPU Regressions (10 tests)**
   - Historical CPU bugs that were fixed
   - Edge cases that caused issues
   - Timing-sensitive instruction sequences

2. **PPU Regressions (10 tests)**
   - Background rendering regressions
   - Sprite rendering regressions
   - Register access regressions

3. **Timing Regressions (10 tests)**
   - Cycle-accurate timing edge cases
   - NMI timing regressions
   - DMA timing regressions

4. **Integration Regressions (10 tests)**
   - CPU-PPU interaction regressions
   - Bus routing regressions
   - Cartridge integration regressions

**Acceptance Criteria:**
- [ ] 40 regression tests created
- [ ] All regression tests passing
- [ ] Historical bugs documented in tests
- [ ] CI integration configured

**Estimated Effort:** 16-20 hours

---

### Sub-Phase 7C.2: AccuracyCoin Automated Testing (16-20 hours)

**Priority:** HIGH - Gold standard for NES accuracy

**Test File:** `tests/acceptance/accuracycoin_test.zig` (EXPAND)

**Required Tests (12 tests):**

1. **CPU Accuracy Tests (4 tests)**
   ```zig
   test "AccuracyCoin: CPU instruction accuracy" {
       // Execute AccuracyCoin CPU test suite
       // Parse results from frame buffer
       // Verify all 151 official opcodes pass
   }

   test "AccuracyCoin: CPU timing accuracy" { }
   test "AccuracyCoin: CPU edge cases" { }
   test "AccuracyCoin: Unofficial opcodes" { }
   ```

2. **PPU Accuracy Tests (4 tests)**
   ```zig
   test "AccuracyCoin: PPU background rendering accuracy" { }
   test "AccuracyCoin: PPU sprite rendering accuracy" {
       // Requires sprite implementation complete
   }
   test "AccuracyCoin: PPU timing accuracy" { }
   test "AccuracyCoin: PPU register behavior" { }
   ```

3. **Full Suite Tests (4 tests)**
   ```zig
   test "AccuracyCoin: Full 128-test suite execution" {
       // Automated execution of all tests
       // Result parsing from frame buffer
       // Pass/fail reporting
   }

   test "AccuracyCoin: Test result parsing" { }
   test "AccuracyCoin: CI integration" { }
   test "AccuracyCoin: Regression detection" { }
   ```

**Implementation:**
- Result parser (parse test results from PPU framebuffer)
- Automated test execution
- CI integration

**Acceptance Criteria:**
- [ ] 12 AccuracyCoin tests created
- [ ] Automated test execution working
- [ ] Result parsing accurate
- [ ] All CPU tests passing
- [ ] All PPU tests passing (requires sprite implementation)

**Estimated Effort:** 16-20 hours

---

### Sub-Phase 7C.3: Visual Regression Testing (8-12 hours)

**Priority:** MEDIUM - Validates visual correctness

**Test Files:**
- `tests/visual/screenshot_comparison_test.zig` (NEW)
- `tests/visual/test_rom_verification_test.zig` (NEW)

**Required Tests:**

1. **Screenshot Comparison (6 tests)**
   - Render reference frames
   - Compare pixel-by-pixel
   - Detect visual regressions

2. **Test ROM Verification (6 tests)**
   - Execute sprite test ROMs
   - Verify visual output matches expected
   - Manual playability testing

**Implementation:**
- Reference screenshot database
- Pixel comparison utilities
- Visual diff reporting

**Acceptance Criteria:**
- [ ] Screenshot comparison working
- [ ] Test ROM verification automated
- [ ] Visual regressions detected

**Estimated Effort:** 8-12 hours (if time permits)

---

### Phase 7C Summary

**Total Duration:** 28-38 hours
**Total New Tests:** 52 tests
**Coverage Increase:** 616-626 tests → 668-678 tests (92%)

**Deliverables:**
- ✅ 40 regression tests passing
- ✅ 12 AccuracyCoin tests passing
- ✅ Visual regression testing working
- ✅ Sprite system fully validated
- ✅ Production-ready quality

**Phase 7C Completion Criteria:**
- [ ] All regression tests passing
- [ ] AccuracyCoin CPU tests passing
- [ ] AccuracyCoin PPU tests passing (sprite-dependent)
- [ ] Visual regression tests passing
- [ ] Full test suite: 668-678 tests passing (92% coverage)

**Next:** Phase 8 (Video Display System)

---

## Overall Phase 7 Summary

### Timeline Comparison

**Original Plan:**
- Phase 7 (Sprite Implementation): 29-42 hours

**Revised Plan:**
- Phase 7A (Test Infrastructure): 28-38 hours
- Phase 7B (Sprite Implementation): 29-42 hours
- Phase 7C (Validation): 28-38 hours
- **Total: 85-118 hours**

### Test Coverage Progression

| Phase | Tests | Coverage | Cumulative Hours |
|-------|-------|----------|------------------|
| Start | 496 | 68% | 0 |
| After 7A | 566-576 | 77% | 28-38 |
| After 7B | 616-626 | 84% | 57-80 |
| After 7C | 668-678 | 92% | 85-118 |

### Quality Improvement

**Before Phase 7:**
- 0 bus integration tests
- 0 CPU-PPU integration tests
- 38 sprite tests (insufficient)
- 0 regression tests
- 1 AccuracyCoin test (loading only)

**After Phase 7:**
- 15-20 bus integration tests ✅
- 20-25 CPU-PPU integration tests ✅
- 123 sprite tests (comprehensive) ✅
- 40 regression tests ✅
- 12 AccuracyCoin tests (automated execution) ✅

---

## Critical Success Factors

### Phase 7A Success (Test Infrastructure)
- [ ] All bus integration tests passing
- [ ] All CPU-PPU integration tests passing
- [ ] All sprite edge case tests created
- [ ] Zero regressions in existing tests
- [ ] Build system supports new test categories

### Phase 7B Success (Sprite Implementation)
- [ ] All 123 sprite tests passing
- [ ] All background tests still passing
- [ ] Visual verification with test ROMs
- [ ] Performance target met (60 FPS)

### Phase 7C Success (Validation)
- [ ] All regression tests passing
- [ ] AccuracyCoin tests passing
- [ ] Visual regression tests passing
- [ ] Production-ready quality achieved

---

## Risk Mitigation

### Critical Risks

**Risk 1: Starting sprite implementation without test infrastructure**
- **Impact:** HIGH - Regressions likely, validation difficult
- **Mitigation:** **BLOCKING** - Phase 7A MUST be complete first
- **Status:** Addressed in revised plan

**Risk 2: Insufficient sprite test coverage**
- **Impact:** HIGH - Edge cases missed, bugs in production
- **Mitigation:** 35 additional edge case tests in Phase 7A
- **Status:** Addressed in revised plan

**Risk 3: No regression prevention**
- **Impact:** MEDIUM - Breaking existing features during sprite work
- **Mitigation:** 40 regression tests in Phase 7C
- **Status:** Addressed in revised plan

### Medium Risks

**Risk 4: AccuracyCoin validation too late**
- **Impact:** MEDIUM - Accuracy issues discovered late
- **Mitigation:** Automated AccuracyCoin testing in Phase 7C
- **Status:** Addressed in revised plan

**Risk 5: Performance degradation**
- **Impact:** LOW - Performance review shows 3x headroom
- **Mitigation:** Profiling during Phase 7B, optimization if needed
- **Status:** Low risk based on performance review

---

## Next Steps

### Immediate Actions (Next Session)

1. **Begin Phase 7A.1: Bus Integration Tests**
   - Create `tests/bus/bus_integration_test.zig`
   - Implement 15-20 bus integration tests
   - Verify all tests passing
   - **Duration:** 8-12 hours

2. **Continue Phase 7A.2: CPU-PPU Integration Tests**
   - Create `tests/integration/cpu_ppu_integration_test.zig`
   - Implement 20-25 integration tests
   - Verify all tests passing
   - **Duration:** 12-16 hours

3. **Complete Phase 7A.3: Expand Sprite Tests**
   - Create `tests/ppu/sprite_edge_cases_test.zig`
   - Add 35 edge case tests
   - Document expected failures
   - **Duration:** 8-10 hours

### Phase 7A Completion

**When Phase 7A is complete:**
- [ ] 566-576 tests passing (77% coverage)
- [ ] Solid test foundation established
- [ ] Zero critical testing gaps
- [ ] Ready to begin sprite implementation

**Then proceed to Phase 7B (Sprite Implementation)**

---

## Conclusion

The QA review identified **critical testing gaps** that would have caused significant issues during sprite implementation. The revised Phase 7 plan addresses these gaps by:

1. **Creating test infrastructure FIRST** (Phase 7A)
2. **Implementing sprites against comprehensive tests** (Phase 7B)
3. **Validating with regression and acceptance tests** (Phase 7C)

This approach adds **56-76 hours** to the original estimate but ensures **production-ready quality** and prevents costly regressions.

**Recommendation:** Proceed with Phase 7A immediately. Do NOT start sprite implementation without test infrastructure.

---

**Document Status:** READY FOR IMPLEMENTATION
**Next Action:** Begin Phase 7A.1 (Bus Integration Tests)
**Prepared by:** Claude Code (synthesizing reviews from backend-architect, performance-engineer, qa-code-review-pro)
**Date:** 2025-10-04
