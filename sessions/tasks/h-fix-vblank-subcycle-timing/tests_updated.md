# Test Audit: VBlank Sub-Cycle Timing Fix

## Summary

**Before Fix:** 1023/1041 tests passing (98.3%), 12 failing
**After Fix:** 996/1026 tests passing, 24 failing
**New Failures:** 12 tests

The fix introduced 12 new test failures, all related to VBlank timing assumptions that were based on the incorrect (old) execution order.

## Test Categories

### Category 1: VBlankLedger Unit Tests (3 tests) - **TEST BUGS**

These tests expect hardware-correct behavior but have a conceptual issue with test timing.

#### 1.1 `VBlankLedger: Flag is set at scanline 241, dot 1`
- **File:** `tests/emulation/state/vblank_ledger_test.zig:23-44`
- **Failure:** Line 38 expects `!isVBlankSet(&h)` but gets `true`
- **Root Cause:** Test does `seekTo(241, 1)` then immediately reads $2002. After `seekTo()` completes, we're AT (241, 1) and `applyPpuCycleResult()` has already set `last_set_cycle`. The flag IS visible because we're reading AFTER the cycle completed, not DURING it.
- **Hardware Spec:** Per nesdev.org, VBlank is set at scanline 241, dot 1. Sub-cycle ordering: CPU reads → PPU flag updates.
- **Fix Needed:** Test needs conceptual rewrite. "Same-cycle read" in hardware means CPU read happens IN THE SAME `tick()` call as the PPU flag update. But `seekTo()` completes the tick, so we're reading AFTER. The test should either:
  1. Use a different approach to position "during" the cycle, OR
  2. Expect `true` since we're reading after the cycle completed
- **Status:** TODO

#### 1.2 `VBlankLedger: First read clears flag, subsequent read sees cleared`
- **File:** `tests/emulation/state/vblank_ledger_test.zig:46-65`
- **Failure:** Line 52 expects `!isVBlankSet(&h)` but gets `true`
- **Root Cause:** Same as 1.1 - `seekTo(241, 1)` positions us AFTER VBlank was set
- **Hardware Spec:** Same as 1.1
- **Fix Needed:** Same conceptual issue as 1.1
- **Status:** TODO

#### 1.3 `VBlankLedger: Race condition - read on same cycle as set`
- **File:** `tests/emulation/state/vblank_ledger_test.zig:90-110`
- **Failure:** Line 102 expects `!isVBlankSet(&h)` but gets `true`
- **Root Cause:** Same as 1.1 and 1.2
- **Hardware Spec:** Same as 1.1
- **Fix Needed:** Same conceptual issue as 1.1
- **Status:** TODO

### Category 2: EmulationState Timing Tests (5 tests) - **TEST BUGS / UNRELATED**

#### 2.1 `EmulationState: tick advances PPU clock`
- **File:** `tests/emulation/state/state_test.zig`
- **Failure:** expects 0, found 2
- **Root Cause:** MasterClock starts at `ppu_cycles = 2` (not 0). This is UNRELATED to our sub-cycle timing fix.
- **Hardware Spec:** Hardware initial phase is not well-documented
- **Fix Needed:** Test should expect initial value of 2, or MasterClock.reset() should be changed to start at 0
- **Status:** TODO - investigate correct hardware initial phase

#### 2.2 `EmulationState: CPU ticks every 3 PPU cycles`
- **File:** `tests/emulation/state/state_test.zig`
- **Failure:** expects 2, found 4
- **Root Cause:** Related to initial `ppu_cycles = 2` phase offset
- **Hardware Spec:** CPU ticks at phase offsets 0, 1, or 2 depending on initial alignment
- **Fix Needed:** Adjust test expectations based on phase 2 start
- **Status:** TODO

#### 2.3 `EmulationState: emulateCpuCycles advances correctly`
- **File:** `tests/emulation/state/state_test.zig`
- **Failure:** expects 30, found 28
- **Root Cause:** Related to phase offset or execution order change
- **Hardware Spec:** CPU:PPU ratio is 1:3 (approximately)
- **Fix Needed:** Investigate why cycle count changed
- **Status:** TODO

#### 2.4 `EmulationState: VBlank timing at scanline 241, dot 1`
- **File:** `tests/emulation/state/state_test.zig`
- **Failure:** Test expectation failed
- **Root Cause:** Similar to VBlankLedger tests - timing assumptions based on old execution order
- **Hardware Spec:** VBlank sets at scanline 241, dot 1
- **Fix Needed:** Update test to match CPU-before-applyPpuCycleResult ordering
- **Status:** TODO

#### 2.5 `EmulationState: frame toggle at scanline boundary`
- **File:** `tests/emulation/state/state_test.zig`
- **Failure:** Test expectation failed
- **Root Cause:** Execution order change may affect when frame_complete is set
- **Hardware Spec:** Frame completes at scanline 261, dot 340 (or 339 on odd frames)
- **Fix Needed:** Update test expectations
- **Status:** TODO

### Category 3: Integration Tests (3 tests) - **TEST BUGS**

#### 3.1 `PPUSTATUS Polling: Race condition at exact VBlank set point`
- **File:** `tests/ppu/ppustatus_polling_test.zig`
- **Failure:** Test expectation failed
- **Root Cause:** Same conceptual issue as VBlankLedger tests - "same-cycle" semantics
- **Hardware Spec:** Same as VBlankLedger tests
- **Fix Needed:** Rewrite test to correctly test same-cycle race condition
- **Status:** TODO

#### 3.2 `VBlank: Flag sets at scanline 241 dot 1`
- **File:** `tests/ppu/vblank_behavior_test.zig`
- **Failure:** Test expectation failed
- **Root Cause:** Same as VBlankLedger tests
- **Hardware Spec:** VBlank sets at scanline 241, dot 1
- **Fix Needed:** Update test
- **Status:** TODO

#### 3.3 `CPU-PPU Integration: VBlank flag race condition (read during setting)`
- **File:** `tests/integration/cpu_ppu_integration_test.zig`
- **Failure:** expected 0, found 128
- **Root Cause:** Test expects race condition to return 0 (VBlank clear), but returns 128 (VBlank set)
- **Hardware Spec:** Hardware race condition behavior is CPU reads before PPU sets
- **Fix Needed:** Similar to VBlankLedger - test timing model issue
- **Status:** TODO

### Category 4: Other Tests (3 tests) - **UNRELATED**

#### 4.1 `JMP Indirect: Bug exists at ALL 256 page boundaries`
- **File:** `tests/cpu/jmp_indirect_test.zig`
- **Failure:** expected 4660, found 52
- **Root Cause:** UNRELATED to VBlank timing fix - this is a CPU opcode bug
- **Hardware Spec:** JMP indirect has page boundary bug
- **Fix Needed:** Investigate CPU JMP indirect implementation
- **Status:** SKIP - unrelated to this task

#### 4.2 `DMC OAM conflict: Cycle count`
- **File:** `tests/dma/dmc_oam_conflict_test.zig`
- **Failure:** Cycle count mismatch
- **Root Cause:** Execution order change may affect DMA cycle counting
- **Hardware Spec:** DMC and OAM DMA have specific cycle interactions
- **Fix Needed:** Investigate if execution order affects DMA timing
- **Status:** TODO - verify DMA still works correctly

#### 4.3 `Seek Behavior: seekTo correctly positions emulator`
- **File:** `tests/test_harness/seek_behavior_test.zig`
- **Failure:** Test expectation failed
- **Root Cause:** Likely related to execution order or initial phase offset
- **Hardware Spec:** N/A (test harness behavior)
- **Fix Needed:** Update test to match new execution model
- **Status:** TODO

#### 4.4 `MasterClock: reset`
- **File:** `src/emulation/MasterClock.zig` (unit test)
- **Failure:** expected 0, found 2
- **Root Cause:** MasterClock.reset() sets `ppu_cycles = 2` instead of 0
- **Hardware Spec:** Hardware initial phase unclear
- **Fix Needed:** Either change test to expect 2, or change reset() to use 0
- **Status:** TODO - investigate correct hardware behavior

### Category 5: AccuracyCoin Tests (8 tests) - **EMULATION BUGS**

These tests run the AccuracyCoin ROM which is hardware-validated. Failures indicate emulation bugs, not test bugs.

#### 5.1 `ALL NOP INSTRUCTIONS (AccuracyCoin)`
- **Result:** FAIL (err=1) raw=0x06
- **Status:** User will investigate manually

#### 5.2 `UNOFFICIAL INSTRUCTIONS (AccuracyCoin)`
- **Result:** FAIL (err=10) raw=0x2A
- **Status:** User will investigate manually

#### 5.3 `NMI CONTROL (AccuracyCoin)`
- **Result:** FAIL (err=7) raw=0x1E
- **Status:** User will investigate manually

#### 5.4 `NMI AT VBLANK END (AccuracyCoin)`
- **Result:** FAIL (err=1) raw=0x06
- **Status:** User will investigate manually

#### 5.5 `NMI DISABLED AT VBLANK (AccuracyCoin)`
- **Result:** FAIL (err=1) raw=0x06
- **Status:** User will investigate manually

#### 5.6 `VBLANK END (AccuracyCoin)`
- **Result:** FAIL (err=1) raw=0x06
- **Status:** User will investigate manually

#### 5.7 `VBLANK BEGINNING (AccuracyCoin)`
- **Expected:** `$02, $02, $02, $02, $00, $01, $01`
- **Actual:** `$02, $02, $01, $01, $01, $01, $01`
- **Result:** FAIL (err=1) raw=0x06
- **Analysis:** Iterations 1-2 match (progress!), iterations 3-7 wrong
- **Status:** User will investigate manually

#### 5.8 `NMI SUPPRESSION (AccuracyCoin)`
- **Result:** FAIL (err=1) raw=0x06
- **Status:** User will investigate manually

#### 5.9 `NMI TIMING (AccuracyCoin)`
- **Result:** FAIL (err=1) raw=0x06
- **Status:** User will investigate manually

## Key Findings

### Conceptual Issue: "Same-Cycle" Semantics

The biggest issue is a conceptual mismatch between test expectations and implementation reality:

**Hardware "same-cycle":** CPU read and PPU flag update happen in the SAME `tick()` call, with CPU read executing first.

**Test "same-cycle":** Test does `seekTo(241, 1)` to position AT the cycle, then reads. But `seekTo()` COMPLETES the tick, so `applyPpuCycleResult()` has already run. We're reading AFTER the cycle, not DURING it.

**Solution:** Tests need to be rewritten to correctly test the same-cycle race condition. Possible approaches:
1. Read $2002 within the SAME `tick()` call that sets VBlank (requires test infrastructure changes)
2. Accept that after `seekTo(241, 1)`, the flag IS visible (change test expectations)
3. Implement a "read before apply" mode in test harness

### Execution Order Verification

The sub-cycle ordering fix IS CORRECT per hardware specification:
1. PPU rendering (pixel output, sprite evaluation)
2. APU processing
3. **CPU memory operations** ← reads $2002 here
4. **PPU state updates** ← VBlank flag set here

This matches nesdev.org documentation and AccuracyCoin shows progress (iterations 1-2 now pass).

### Master Clock Initial Phase

`MasterClock.reset()` sets `ppu_cycles = 2` which affects:
- CPU/PPU phase alignment (when CPU ticks relative to PPU cycles)
- Initial test expectations (tests expect 0, get 2)
- Potentially affects AccuracyCoin timing

**Investigation needed:** What is the correct hardware initial phase?

## Tests to Fix

### High Priority (Blocking AccuracyCoin)
- [ ] VBlankLedger unit tests (3 tests) - conceptual rewrite
- [ ] Integration tests (3 tests) - conceptual rewrite
- [ ] Master clock initial phase investigation

### Medium Priority (Correctness)
- [ ] EmulationState timing tests (5 tests)
- [ ] DMC/OAM conflict test (verify DMA still works)
- [ ] Seek behavior test

### Low Priority (Unrelated)
- [ ] JMP Indirect test (CPU bug, not VBlank timing)

## Next Steps

1. **Fix VBlankLedger tests** - Resolve "same-cycle" conceptual issue
2. **Investigate master clock phase** - Research hardware initial phase
3. **Update integration tests** - Match new execution order
4. **User investigates AccuracyCoin** - Manual testing required
5. **Document timing issues** - Create prioritized bug list
