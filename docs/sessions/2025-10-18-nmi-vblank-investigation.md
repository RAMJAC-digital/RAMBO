# NMI/VBlank Investigation - 2025-10-18

## Problem Statement

AccuracyCoin ROM shows ALL NMI/VBlank tests failing:
- VBLANK BEGINNING - FAIL
- VBLANK END - FAIL  
- NMI CONTROL - FAIL (7 subtests)
- NMI TIMING - FAIL
- NMI SUPPRESSION - FAIL
- NMI AT VBLANK END - FAIL
- NMI DISABLED AT VBLANK - FAIL

## Investigation Process

### Created Test Harness

Created `tests/ppu/vblank_nmi_timing_test.zig` with 3 AccuracyCoin-based tests:
- Test 1: NMI disabled - no interrupt ✅ PASSES
- Test 2: NMI enabled before VBlank - should fire ❌ FAILS  
- Test 3: Enable NMI during VBlank - should fire immediately ❌ FAILS

### Complete Execution Flow Traced

**VBlank Signal Path:**
1. PPU sets `nmi_signal = true` at scanline 241, dot 1
2. `EmulationState.applyPpuCycleResult()` receives signal
3. Updates `vblank_ledger.last_set_cycle = 82182`
4. Calls `updateNmiLine()`

**updateNmiLine() Function:**
```zig
const vblank_visible = self.vblank_ledger.isFlagVisible();
const nmi_line_should_assert = vblank_visible and
    self.ppu.ctrl.nmi_enable and
    !self.vblank_ledger.race_hold;
self.cpu.nmi_line = nmi_line_should_assert;
```

**CPU Edge Detection:**
```zig
// In executeCycle()
if (state.cpu.state == .fetch_opcode) {
    CpuLogic.checkInterrupts(&state.cpu, vblank_set_cycle);
    // Should detect edge and set pending_interrupt = .nmi
}
```

## ROOT CAUSE FOUND

### Debug Output from Test 2:

```
[VBlank] START at ppu_cycle=82182, scanline=241, dot=1, nmi_enabled=true
[updateNmiLine] visible=true, nmi_enable=true, should_assert=true  ← CORRECT!
[stepCycle] vblank=true, set_cycle=82182, cpu.state=fetch_opcode, cpu.nmi_line=true
```

**Key Finding:** `cpu.nmi_line=true` is SET CORRECTLY!

But then:
- NO `[checkInterrupts]` debug output (never called)
- NO `[stepCycle] About to call executeCycle` output
- Test fails with X=0 (NMI handler never executed)

### Conclusion

`executeCycle()` is **NEVER BEING CALLED** even though:
- VBlank is active (set_cycle=82182)
- NMI is enabled (ppu.ctrl.nmi_enable=true)  
- NMI line is set (cpu.nmi_line=true)
- CPU is in correct state (fetch_opcode)

**Something is preventing `stepCycle()` from reaching `executeCycle()`.**

## Potential Causes

Looking at `execution.zig:stepCycle()`:

```zig
// Line 105-108: CPU halted check
if (state.cpu.halted) {
    return .{};  // Early return
}

// Line 155-158: OAM DMA check  
if (state.dma.active) {
    state.tickDma();
    return .{};  // Early return
}

// Line 161-163: DMC DMA check
if (dmc_is_active) {
    return .{};  // Early return
}

// Line 166: SHOULD reach here
executeCycle(state, current_vblank_set_cycle);
```

**Hypothesis:** One of the early returns (halted, DMA, DMC) is preventing execution.

## Additional Architectural Issues Identified

### 1. Interleaving and Mutations

The code has mutations happening across PPU/CPU boundaries:
- `applyPpuCycleResult()` mutates `cpu.nmi_line`
- This happens BEFORE CPU cycle execution
- Creates interleaving issues in multi-threaded context

### 2. Business Logic Not Functional

`updateNmiLine()` should be a pure function computing the value, not mutating state directly.

Better architecture:
```zig
fn computeNmiLine(vblank_ledger: VBlankLedger, nmi_enable: bool) bool {
    const vblank_visible = vblank_ledger.isFlagVisible();
    return vblank_visible and nmi_enable and !vblank_ledger.race_hold;
}
```

### 3. Call Site Issues

`updateNmiLine()` is called from two places:
- Line 430: PPUCTRL writes (when NMI enable changes)
- Line 749: After VBlank events (nmi_signal or vblank_clear)

But it's being called AFTER state mutations, making debugging difficult.

## Next Steps

### Immediate Actions Needed

1. **Add debug output to identify blocking condition:**
   - Print `state.cpu.halted` value
   - Print `state.dma.active` value
   - Print `dmc_is_active` value
   - Find which early return is happening

2. **Fix the immediate bug** (once identified)

3. **Architectural refactoring** (separate concern):
   - Make business logic functional
   - Reduce cross-boundary mutations
   - Improve testability

### Development Plan

**Phase 1: Fix Immediate Bug**
- Identify why `executeCycle()` isn't called
- Fix the blocking condition
- Verify AccuracyCoin tests pass

**Phase 2: Architectural Cleanup**
- Extract pure functions for NMI line computation
- Centralize state mutations
- Add comprehensive unit tests

**Phase 3: Validation**
- Run full AccuracyCoin suite
- Verify no regressions in existing tests
- Test with commercial ROMs

## Files Modified (Debug Changes)

- `src/emulation/State.zig` - Added debug output to `updateNmiLine()`
- `src/cpu/Logic.zig` - Added debug output to `checkInterrupts()`
- `src/emulation/cpu/execution.zig` - Added debug output to `stepCycle()`
- `tests/ppu/vblank_nmi_timing_test.zig` - Created new test file

**NOTE:** All debug changes should be reverted before committing fixes.
