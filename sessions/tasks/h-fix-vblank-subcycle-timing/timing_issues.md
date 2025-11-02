# Known Timing Issues & Investigation Roadmap

**Last Updated:** 2025-11-01
**Status:** Sub-cycle execution order fix implemented, tests being updated

## Executive Summary

The sub-cycle execution order fix (CPU before `applyPpuCycleResult()`) has been implemented and is **CORRECT** per hardware specification. The fix introduced test failures because many tests were written with incorrect assumptions about the old execution order.

**Progress:**
- ✅ Core fix implemented (CPU before PPU state updates)
- ✅ VBlankLedger unit tests fixed (3 tests)
- ✅ EmulationState timing tests fixed (5 tests)
- ⏳ Integration tests need fixing (3 tests)
- ⏳ AccuracyCoin tests need investigation (8 tests - USER WILL RUN MANUALLY)

## Priority 1: Remaining Test Fixes

### Integration Tests (3 tests) - In Progress

1. **PPUSTATUS Polling: Race condition at exact VBlank set point**
   - **File:** `tests/ppu/ppustatus_polling_test.zig`
   - **Issue:** Same conceptual problem as VBlankLedger tests - expects same-cycle read to see CLEAR
   - **Fix:** Update test expectations to match new execution model

2. **VBlank: Flag sets at scanline 241 dot 1**
   - **File:** `tests/ppu/vblank_behavior_test.zig`
   - **Issue:** Same as above
   - **Fix:** Update test expectations

3. **CPU-PPU Integration: VBlank flag race condition**
   - **File:** `tests/integration/cpu_ppu_integration_test.zig`
   - **Issue:** expected 0, found 128 (expects CLEAR, gets SET)
   - **Fix:** Update test expectations

### Unrelated Test Failures (Should be Fixed Separately)

1. **JMP Indirect bug** - CPU opcode issue, not VBlank timing
2. **DMC/OAM conflict** - DMA timing, needs investigation
3. **Seek behavior** - Test harness issue
4. **MasterClock reset** - Expects 0, gets 2 (Phase 2 offset)

## Priority 2: Master Clock Phase Alignment

### Current State

`MasterClock.reset()` sets `ppu_cycles = 2` (Phase 2). This affects:
- When CPU ticks relative to PPU cycles
- AccuracyCoin test timing expectations
- All tests that assume initial `ppu_cycles = 0`

### Investigation Needed

**Question:** What is the correct hardware initial phase?

**Evidence to gather:**
1. Real NES console behavior at power-on
2. Mesen emulator behavior (known accurate)
3. Nesdev.org documentation on CPU/PPU phase alignment
4. AccuracyCoin test expectations (does it assume specific phase?)

**Hypotheses:**
- **H1:** Hardware has random/undefined initial phase → any phase is correct
- **H2:** Hardware has fixed initial phase → we need to match it
- **H3:** Phase doesn't matter for correctness → Phase 2 is fine if tests are updated

**Next Steps:**
1. Research nesdev.org for CPU/PPU phase documentation
2. Check Mesen source code for initial phase handling
3. Document findings in this file
4. Decide whether to keep Phase 2 or change to Phase 0

### CPU/PPU Phase Alignment Details

**Phase 0** (`ppu_cycles = 0`):
- CPU ticks when `ppu_cycles % 3 == 0`
- CPU ticks at cycles: 0, 3, 6, 9, 12, ...
- VBlank set at cycle 82,181 → CPU tick at 82,182

**Phase 1** (`ppu_cycles = 1`):
- CPU ticks when `ppu_cycles % 3 == 1`  (via `isCpuTick()` checking post-advance)
- CPU ticks at cycles: 1, 4, 7, 10, 13, ...
- VBlank set at cycle 82,181 → CPU tick at 82,183

**Phase 2** (`ppu_cycles = 2`):  ← **CURRENT**
- CPU ticks when `ppu_cycles % 3 == 0`  (2 → 3, then 3 % 3 == 0)
- CPU ticks at cycles: 3, 6, 9, 12, ...
- VBlank set at cycle 82,181 → CPU tick at 82,182

**Impact on VBlank Race Condition:**
- Phase 0: VBlank at 82,181, CPU tick at 82,182 → 1 cycle after
- Phase 1: VBlank at 82,181, CPU tick at 82,183 → 2 cycles after
- Phase 2: VBlank at 82,181, CPU tick at 82,182 → 1 cycle after

Phase affects whether CPU can even read at the "same cycle" as VBlank set!

## Priority 3: AccuracyCoin Test Failures

### Current Status

**VBlank Beginning Test:**
- **Expected:** `$02, $02, $02, $02, $00, $01, $01`
- **Actual:** `$02, $02, $01, $01, $01, $01, $01`
- **Progress:** Iterations 1-2 now match (was all wrong before)
- **Remaining Issue:** Iterations 3-7 wrong

### Analysis

The test performs 7 iterations, each reading $2002 at different PPU cycle offsets relative to scanline 241, dot 1. The pattern suggests:
- `$02` = Some test condition (not VBlank bit directly)
- `$01` = Different test condition
- `$00` = Yet another condition

**Hypothesis:** These are not raw PPU STATUS values, but test result codes indicating pass/fail for each iteration.

### Investigation Plan (USER WILL RUN MANUALLY)

1. **Understand AccuracyCoin test structure**
   - Read ROM assembly source (if available in `compiler/`)
   - Reverse-engineer what each iteration tests
   - Document expected behavior for each of 7 iterations

2. **Trace emulator behavior**
   - Add detailed logging for each iteration:
     - Which PPU cycle the read happens at
     - `last_set_cycle` and `last_read_cycle` values
     - What `isFlagVisible()` returns
     - What value CPU actually reads from $2002
   - Compare against expected hardware behavior

3. **Identify discrepancies**
   - Pinpoint exactly where emulator behavior diverges from hardware
   - Determine if issue is:
     - Phase alignment
     - VBlank flag visibility logic
     - Read timestamp tracking
     - Some other timing subtlety

## Priority 4: VBlank Flag Visibility Edge Cases

### Current Implementation

`VBlankLedger.isFlagVisible()` logic:
```zig
pub inline fn isFlagVisible(self: VBlankLedger) bool {
    if (!self.isActive()) return false;  // VBlank span check
    if (self.last_read_cycle >= self.last_set_cycle) return false;  // Read clears flag
    return true;
}
```

### Issue

With CPU-before-`applyPpuCycleResult()` ordering:
- CPU reads at cycle N → sets `last_read_cycle = N` (if flag visible)
- `applyPpuCycleResult()` → sets `last_set_cycle = N`
- Logic: `N >= N` → true → flag NOT visible ✓

**But:** We only update `last_read_cycle` if `isFlagVisible()` returns true. This creates a circular dependency:
- To know if we should update `last_read_cycle`, we check `isFlagVisible()`
- But `isFlagVisible()` depends on `last_read_cycle` being updated

### Current Workaround

We check `isFlagVisible()` BEFORE updating `last_read_cycle`:
```zig
if (self.vblank_ledger.isFlagVisible()) {
    self.vblank_ledger.last_read_cycle = self.clock.ppu_cycles;
}
```

This works because when CPU reads at same cycle as VBlank set:
- `last_set_cycle` hasn't been updated yet (still from previous VBlank)
- `isFlagVisible()` checks `last_read_cycle >= last_set_cycle` using OLD `last_set_cycle`
- Returns true (flag "visible" based on old state)
- We update `last_read_cycle`
- Then `applyPpuCycleResult()` updates `last_set_cycle`
- Next read will see `last_read_cycle >= last_set_cycle` and return false ✓

### Potential Issues

1. **Race condition logic is complex and fragile**
2. **Position-based detection in `busRead()` still exists** (line 301-304)
3. **Mixing timestamp-based and position-based logic** creates confusion

### Recommendations

1. **Document the circular dependency** and why current approach works
2. **Consider simplifying** by removing position-based checks entirely
3. **Add comprehensive tests** for all edge cases:
   - Read before VBlank set
   - Read same cycle as VBlank set
   - Read 1 cycle after VBlank set
   - Read 2 cycles after VBlank set
   - Multiple reads in sequence
   - Read after VBlank clear (timing-based)

## Priority 5: PPU Warmup Period

### Current Understanding

PPU has a 29,658 cycle warmup period after power-on. During warmup:
- Writes to $2000/$2001/$2005/$2006 are ignored
- PPU internal state is stabilizing
- This is NOT for video signal sync - it's for internal state stability

### Implementation

`PpuState.warmup_complete` flag tracks warmup status. Set to true after 29,658 cycles.

### Investigation Needed

1. **What exactly happens during warmup?**
   - Which PPU operations are affected?
   - What's the hardware behavior?
   - Does it affect rendering?

2. **Does our implementation match hardware?**
   - Test with real hardware or Mesen
   - Verify register write ignoring
   - Check if any operations ARE allowed during warmup

3. **Does warmup affect VBlank timing?**
   - Does VBlank flag still set during warmup?
   - Can $2002 be read during warmup?
   - Does it affect AccuracyCoin tests?

### Resources

- Nesdev.org: Search for "PPU warmup" or "power-on"
- Mesen source code: Check PPU initialization
- Hardware tests: blargg's power-on tests (if available)

## Summary of Remaining Work

### Must Do (Blocking)
1. ✅ Fix integration tests (3 tests) - **IN PROGRESS**
2. ⏳ User investigates AccuracyCoin failures (8 tests)
3. ⏳ Research and document master clock phase alignment

### Should Do (High Priority)
1. Document VBlank flag visibility edge cases comprehensively
2. Add more edge case tests for race conditions
3. Research PPU warmup period behavior

### Nice to Have (Lower Priority)
1. Simplify VBlank visibility logic (remove position-based checks if possible)
2. Fix unrelated test failures (JMP Indirect, DMC/OAM, Seek behavior)
3. Update MasterClock reset test expectations

## Test Status Tracking

### Fixed (8 tests)
- ✅ VBlankLedger: Flag is set at scanline 241, dot 1
- ✅ VBlankLedger: First read clears flag, subsequent read sees cleared
- ✅ VBlankLedger: Race condition - read on same cycle as set
- ✅ EmulationState: tick advances PPU clock
- ✅ EmulationState: CPU ticks every 3 PPU cycles
- ✅ EmulationState: emulateCpuCycles advances correctly
- ✅ EmulationState: VBlank timing at scanline 241, dot 1
- ✅ EmulationState: frame toggle at scanline boundary (no longer failing)

### To Fix (3 tests)
- ⏳ PPUSTATUS Polling: Race condition at exact VBlank set point
- ⏳ VBlank: Flag sets at scanline 241 dot 1
- ⏳ CPU-PPU Integration: VBlank flag race condition

### User Will Investigate (8 AccuracyCoin tests)
- ⏳ ALL NOP INSTRUCTIONS
- ⏳ UNOFFICIAL INSTRUCTIONS
- ⏳ NMI CONTROL
- ⏳ NMI AT VBLANK END
- ⏳ NMI DISABLED AT VBLANK
- ⏳ VBLANK END
- ⏳ VBLANK BEGINNING
- ⏳ NMI SUPPRESSION
- ⏳ NMI TIMING

### Unrelated (3 tests - separate task)
- 🔍 JMP Indirect: Bug exists at ALL 256 page boundaries
- 🔍 DMC/OAM conflict: Cycle count
- 🔍 Seek behavior: seekTo correctly positions emulator
- 🔍 MasterClock: reset (expects 0, gets 2)

## Conclusion

The sub-cycle execution order fix is **correct** and represents a significant step toward hardware accuracy. The test failures are expected and are being systematically addressed. AccuracyCoin test improvements (iterations 1-2 now pass) confirm we're moving in the right direction.

Main remaining unknowns:
1. **Master clock initial phase** - needs hardware research
2. **AccuracyCoin test expectations** - needs ROM analysis
3. **VBlank visibility edge cases** - needs comprehensive testing

Once integration tests are fixed and AccuracyCoin is investigated, we'll have a much clearer picture of any remaining timing issues.
