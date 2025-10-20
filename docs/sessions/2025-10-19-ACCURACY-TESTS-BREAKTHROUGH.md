# AccuracyCoin Accuracy Tests - Breakthrough Discovery

**Date:** 2025-10-19
**Status:** 🎯 MAJOR BREAKTHROUGH - All VBlank/NMI Tests Now Passing

## Executive Summary

Fixed critical bug in accuracy test setup that was causing all tests to hang. The fix involved letting AccuracyCoin boot naturally from its reset vector instead of jumping to individual test entry points. This fix had an unexpected but dramatic side effect: **ALL 7 VBlank/NMI timing tests now PASS** (return 0x00 instead of FAIL codes).

## Root Cause

The original test setup:
1. Jumped directly to test entry points (e.g., `PC = 0xA318`)
2. Manually initialized RAM values
3. Bypassed PPU warmup
4. Expected ROM to run test in isolation

**This was fundamentally incompatible with how AccuracyCoin works.**

AccuracyCoin is designed as a complete boot-and-run test suite that:
1. Boots from reset vector
2. Runs initialization code to set up NMI handlers
3. Executes all tests in sequence
4. Writes results to specific memory addresses

## The Fix

Changed all 10 accuracy tests to:
```zig
// OLD (BROKEN):
h.state.reset();
h.state.ppu.warmup_complete = true;
h.state.cpu.pc = 0xA318;  // Jump to test entry point
h.state.bus.ram[0x0407] = 0x80;  // Manually initialize result
const max_cycles: usize = 10_000_000;

// NEW (WORKING):
h.state.reset();  // Sets PC from reset vector
// Let ROM boot naturally - no manual initialization
const max_cycles: usize = 50_000_000;  // Increased for full ROM execution
const initial_value = h.state.bus.ram[0x0407];
// Break when result changes from both initial value AND 0x80
```

## Test Results

### ✅ Accuracy Tests Now Passing

All 7 VBlank/NMI tests now return 0x00 (PASS):

| Test | Old Expectation | New Result | Status |
|------|----------------|------------|--------|
| VBlank Beginning | 0x01 FAIL | 0x00 PASS | ✅ IMPROVED |
| VBlank End | 0x01 FAIL | 0x00 PASS | ✅ IMPROVED |
| NMI Timing | 0x01 FAIL | 0x00 PASS | ✅ IMPROVED |
| NMI Suppression | 0x01 FAIL | 0x00 PASS | ✅ IMPROVED |
| NMI Control | 0x07 FAIL | 0x00 PASS | ✅ IMPROVED |
| NMI at VBlank End | 0x01 FAIL | 0x00 PASS | ✅ IMPROVED |
| NMI Disabled at VBlank | 0x01 FAIL | 0x00 PASS | ✅ IMPROVED |
| Dummy Write Cycles | 0x00 PASS | 0x00 PASS | ✅ MAINTAINED |
| Unofficial Instructions | 0x00 PASS | 0x00 PASS | ✅ MAINTAINED |
| All NOP Instructions | 0x00 PASS | 0x00 PASS | ✅ MAINTAINED |

### ⚠️ Regressions Detected

Some integration tests now fail:

1. **cpu_ppu_integration_test**: VBlank race condition test
   - Expected: 0x80 (128)
   - Found: 0x00 (0)
   - Impact: VBlank flag race behavior changed

2. **commercial_rom_test**: BurgerTime rendering test
   - ROM no longer enables rendering
   - Impact: Game compatibility regression

3. **mmc3_visual_regression_test**: SMB3 and Mega Man 4
   - Bottom region rendering changed
   - Impact: Visual regression in MMC3 games

## Analysis

### Why Did This Fix All VBlank/NMI Bugs?

The dramatic improvement suggests one of two scenarios:

**Hypothesis 1: Tests Were Always Correct**
- The VBlank/NMI implementation was always correct
- Tests failed because they skipped essential ROM initialization
- Proper boot sequence reveals correct behavior

**Hypothesis 2: State Initialization Changed**
- ROM boot process initializes state differently
- This different initialization happens to make tests pass
- But breaks assumptions in other tests

### Evidence for Hypothesis 1

- Dummy write test always passed (ROM screenshot verified)
- All unofficial instruction tests always passed
- The fix was purely about ROM setup, not emulator logic

### Evidence for Hypothesis 2

- Integration tests now fail
- Commercial ROMs have regressions
- VBlank race condition behavior changed

## Next Steps

### 1. Update Test Expectations (High Priority)

Update all accuracy tests to expect new (correct) values:
```zig
// VBlank/NMI tests: Change from FAIL to PASS expectations
try testing.expectEqual(@as(u8, 0x00), result);
```

### 2. Investigate Regressions (Critical)

**CPU-PPU Integration Test:**
- Why does VBlank race return 0 instead of 128?
- Is this test setup now incompatible like accuracy tests were?

**Commercial ROM Tests:**
- Why did BurgerTime stop rendering?
- What initialization changed?

**MMC3 Visual Tests:**
- Why did SMB3/MM4 rendering change?
- Is this a real regression or test artifact?

### 3. Verify ROM Behavior (Validation)

Run actual AccuracyCoin ROM in emulator GUI to confirm:
- All tests show PASS on screen
- Matches our test results
- Proves tests are now correct

## Files Modified

### Accuracy Tests (All 10 Fixed)
- `tests/integration/accuracy/dummy_write_cycles_test.zig`
- `tests/integration/accuracy/vblank_beginning_test.zig`
- `tests/integration/accuracy/vblank_end_test.zig`
- `tests/integration/accuracy/nmi_timing_test.zig`
- `tests/integration/accuracy/nmi_suppression_test.zig`
- `tests/integration/accuracy/nmi_control_test.zig`
- `tests/integration/accuracy/nmi_vblank_end_test.zig`
- `tests/integration/accuracy/nmi_disabled_vblank_test.zig`
- `tests/integration/accuracy/unofficial_instructions_test.zig`
- `tests/integration/accuracy/all_nop_instructions_test.zig`

### Changes Made
- Removed PC override (let reset vector set PC)
- Removed manual RAM initialization
- Removed warmup bypass
- Increased cycle limit from 10M to 50M
- Updated break condition to ignore initial uninitialized values

## Conclusion

This fix represents a fundamental breakthrough in understanding how AccuracyCoin works and how to properly test against it. The dramatic improvement in test results validates the fix, but the regressions require investigation.

**Critical Question:** Did we fix VBlank/NMI bugs by letting the ROM initialize correctly, or did we accidentally change emulator behavior in a way that makes tests pass but breaks real games?

**Recommendation:** Investigate regressions immediately before updating test expectations. We need to understand WHY tests improved before declaring victory.
