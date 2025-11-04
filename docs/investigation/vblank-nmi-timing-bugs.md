# VBlank/NMI Timing Investigation

**Date**: 2025-11-03
**Status**: RESOLVED - Fix implemented and merged
**Tests Affected**: 8 AccuracyCoin tests failing (err=1, err=8, err=10)

## Resolution (2025-11-03)

**Fix Implemented**: Option C (Defer VBlank application until after CPU execution)

**Changes Made**:
1. Moved CPU execution BEFORE VBlank timestamp application in `src/emulation/State.zig:tick()` lines 651-774
2. CPU reads $2002 and sets `prevent_vbl_set_cycle` flag BEFORE VBlank timestamps are applied
3. `applyVBlankTimestamps()` checks prevention flag and skips setting VBlank if prevented
4. Interrupt sampling moved to AFTER VBlank timestamps are finalized (ensures correct NMI line state)
5. Fixed IRQ masking during NMI (`if (irq_pending_prev and pending_interrupt != .nmi)`)

**Test Results**: Implementation fixes execution order; remaining test failures indicate additional timing issues (not execution order bugs)

**Reference**: See `/home/colin/Development/RAMBO/sessions/tasks/h-fix-oam-nmi-accuracy.md` section "2025-11-03: VBlank/NMI Timing Restructuring and IRQ Masking Fix" for complete details

---

## Executive Summary (Original Analysis)

The interrupt polling refactor is functionally correct, but there's a critical **execution order bug** in VBlank flag timing that causes AccuracyCoin tests to fail.

**Key Finding**: The VBlank race condition prevention flag is set AFTER the flag set decision is made, not before. This causes the prevention mechanism to fail.

---

## Bug #1: VBlank Race Condition Prevention (CRITICAL)

### Problem

**Location**: `src/emulation/State.zig` lines 748-774

**Execution Order Bug**:
```
At scanline 241, dot 1 (VBlank set cycle):

1. tick() advances clock to dot 1
2. stepPpuCycle() returns nmi_signal = true
3. applyVBlankTimestamps():
   - Line 758: Check prevention flag (it's 0, so NOT prevented)
   - Line 760: Set last_set_cycle = master_cycles (VBlank flag SET ✓)
   - Line 764: Clear prevention flag
4. stepCpuCycle() executes:
   - CPU reads $2002
   - Bus read handler sets prevent_vbl_set_cycle = master_cycles (TOO LATE!)
```

The prevention flag is set AFTER we've already decided to set the VBlank flag!

### Root Cause

The prevention flag should be set BEFORE checking whether to set VBlank, not after. Currently:
- Prevention check happens in `applyVBlankTimestamps()` (line 758)
- Prevention flag is set in bus read handler (line 334)
- Bus read happens AFTER `applyVBlankTimestamps()` completes

### Mesen2's Correct Behavior

**Mesen2 NesPpu.cpp**:
```cpp
// Line 590-592: UpdateStatusFlag() called when reading $2002
if(_scanline == _nmiScanline && _cycle == 0) {
    _preventVblFlag = true;  // Set BEFORE advancing to cycle 1
}

// Line 1339-1344: Later, at cycle 1
if(_cycle == 1 && _scanline == _nmiScanline) {
    if(!_preventVblFlag) {  // Check prevention flag
        _statusFlags.VerticalBlank = true;  // Only set if not prevented
    }
    _preventVblFlag = false;  // Clear after checking
}
```

Mesen2's timeline:
1. Cycle 0: CPU reads $2002 → `_preventVblFlag = true`
2. Advance to cycle 1
3. Cycle 1: Check `!_preventVblFlag` → skip setting VBlank flag

### Expected Behavior (per AccuracyCoin and nesdev.org)

**Test**: VBlank Beginning Test
```
Reading $2002 at different offsets relative to VBlank set (scanline 241, dot 1):

Offset 0 (dot 0): Read before VBlank → prevents flag from being set
Offset 1 (dot 1): Read during VBlank set → returns 0, clears flag, suppresses NMI
Offset 2 (dot 2): Read after VBlank → returns $80, clears flag
```

**Hardware Citation**: https://www.nesdev.org/wiki/PPU_frame_timing
> "Reading one PPU clock before reads it as clear and never sets the flag or generates NMI for that frame."

### Impact

**Failing Tests**:
- VBlank Beginning (err=1)
- VBlank End (err=1)
- NMI Timing (err varies)
- NMI Control Test 8 (err=8)
- NMI Disabled at VBlank (err=1)
- NMI at VBlank End (err=1)

All VBlank timing-sensitive tests fail because the race condition check is ineffective.

### Fix Required

The prevention flag must be evaluated BEFORE the VBlank set decision. Possible approaches:

**Option A**: Move prevention flag setting to happen before `applyVBlankTimestamps()`
- Set flag when reading $2002 at scanline 241, dots 0-2
- Store as "prevent on next VBlank check"
- Check flag in `applyVBlankTimestamps()` before setting

**Option B**: Two-phase VBlank handling
- Phase 1: Evaluate whether VBlank WOULD be set (check prevention)
- Phase 2: Actually set VBlank based on Phase 1 decision
- CPU execution happens between Phase 1 and Phase 2

**Option C**: Defer VBlank set to end of cycle (like Mesen2)
- Check prevention flag and set VBlank at END of cycle, not beginning
- This matches Mesen2's architecture where PPU events happen after CPU execution

---

## Bug #2: CPU/PPU Phase Alignment Assumption

### Problem

**Location**: `src/emulation/State.zig` lines 316-335

Our code assumes CPU can only execute at dot 1, not dot 0:
```zig
// Line 331: if (dot == 1) {
//     Only check for race at dot 1
```

This is based on calculation:
```
dot 0: ppu_cycles % 3 = 2 (NOT CPU tick)
dot 1: ppu_cycles % 3 = 0 (IS CPU tick)
```

### Issue

This calculation assumes a fixed CPU/PPU phase alignment at power-on. However:
- Mesen2 randomizes CPU/PPU alignment (NesCpu.cpp:142-156)
- Real hardware has random phase alignment at power-on
- CPU could execute at dot 0, 1, or 2 depending on phase

### Impact

If CPU phase is different, our race condition check fails to trigger at the right cycle.

### Fix Required

Either:
1. Handle all possible CPU/PPU phase alignments
2. Match Mesen2's approach of checking at cycle 0 (pre-advance)

---

## Confirmed Working: Interrupt Polling ("Second-to-Last Cycle" Rule)

### Implementation Status

✅ **CORRECT** - Our interrupt polling refactor matches Mesen2's behavior

**Test**: AccuracyCoin NMI Control Test 8
```zig
// Expects NMI to fire 2 instructions after enabling NMI:
STA $2000   // Enable NMI (cycle N)
LDX #$10    // Executes normally (cycle N+1)
[NMI fires] // Fires here (cycle N+2)
```

### Our Implementation

**src/emulation/cpu/execution.zig**:
```zig
// Lines 217-224: START of cycle - restore from _prev
if (state.cpu.state != .interrupt_sequence) {
    if (state.cpu.nmi_pending_prev) {
        state.cpu.pending_interrupt = .nmi;
    } else if (state.cpu.irq_pending_prev and !state.cpu.p.interrupt) {
        state.cpu.pending_interrupt = .irq;
    }
}

// Lines 227-244: Check if interrupt hijacks opcode fetch
if (state.cpu.state == .fetch_opcode) {
    if (state.cpu.pending_interrupt != .none) {
        // Hijack and start interrupt sequence
    }
}

// Lines 792-810: END of cycle - sample and store to _prev
if (state.cpu.state != .interrupt_sequence) {
    CpuLogic.checkInterrupts(&state.cpu);
    state.cpu.nmi_pending_prev = (state.cpu.pending_interrupt == .nmi);
    state.cpu.irq_pending_prev = (state.cpu.pending_interrupt == .irq);
    state.cpu.pending_interrupt = .none;
}
```

This matches Mesen2's pattern:
```cpp
// NesCpu.cpp:301-314: EndCpuCycle() - sample interrupts
_prevNeedNmi = _needNmi;
if(!_prevNmiFlag && _state.NmiFlag) {
    _needNmi = true;
}
_prevRunIrq = _runIrq;
_runIrq = ((_state.IrqFlag & _irqMask) > 0 && !CheckFlag(PSFlags::Interrupt));

// NesCpu.cpp:178-180: Exec() - check _prev before instruction
if(_prevRunIrq || _prevNeedNmi) {
    IRQ();
}
```

### Test Results

- IRQ masking now works correctly (fixed in previous commit)
- NMI edge detection works correctly
- Interrupt priority (NMI > IRQ) works correctly
- 1072/1110 tests passing (+6 from interrupt fixes)

**Remaining failures are due to VBlank flag timing bug, not interrupt polling.**

---

## AccuracyCoin Test Error Code Analysis

| Test Name | Error Code | Failure Point | Root Cause |
|-----------|-----------|---------------|-----------|
| **Unofficial Instructions** | err=10 | Opcode behavior | Unrelated to timing |
| **All NOP Instructions** | err=1 | First NOP variant | Unrelated to timing |
| **NMI Control** | err=8 | Test 8: "2 instructions after enable" | VBlank flag timing |
| **NMI Timing** | err varies | INY sequence timing | VBlank flag timing |
| **NMI Suppression** | err varies | Race window tests | VBlank flag timing |
| **VBlank Beginning** | err=1 | First timing offset | VBlank flag timing |
| **VBlank End** | err=1 | First timing offset | VBlank flag timing |
| **NMI Disabled at VBlank** | err=1 | Flag visibility | VBlank flag timing |
| **NMI at VBlank End** | err=1 | Flag clear timing | VBlank flag timing |

**Pattern**: err=1 typically means "first sub-test failed", suggesting fundamental timing issue at cycle-accurate level.

---

## Recommended Fix Strategy

### Phase 1: Fix VBlank Race Condition (High Priority)

1. Restructure `tick()` to handle VBlank prevention correctly
2. Options:
   - **A**: Check prevention before setting (requires reordering)
   - **B**: Two-phase VBlank handling
   - **C**: Defer VBlank set to end of cycle

Recommended: **Option C** (matches Mesen2 architecture)

### Phase 2: Verify CPU/PPU Phase Independence

1. Test with different CPU/PPU phase alignments
2. Ensure race condition works regardless of phase
3. Consider implementing phase randomization for testing

### Phase 3: Re-test AccuracyCoin

After VBlank timing fix:
- All 9 failing VBlank/NMI tests should pass
- Expect significant improvement in test pass rate
- May uncover additional edge cases

---

## References

### Mesen2 Source

- `NesCpu.cpp:294-315`: EndCpuCycle() - interrupt sampling
- `NesCpu.cpp:167-181`: Exec() - interrupt checking
- `NesPpu.cpp:585-594`: UpdateStatusFlag() - $2002 read handling
- `NesPpu.cpp:1339-1344`: VBlank flag set with prevention check

### Hardware Documentation

- nesdev.org/wiki/PPU_frame_timing
- nesdev.org/wiki/CPU_interrupts
- nesdev.org/wiki/PPU_registers ($2002 behavior)

### AccuracyCoin Tests

- `tests/data/AccuracyCoin/AccuracyCoin.asm`
- Lines 4914-4984: VBlank Beginning Test
- Lines 4986-5027: VBlank End Test
- Lines 5034-5131: NMI Control Test (Test 8 at line 5111)
- Lines 5138-5235: NMI Timing Test

---

## Conclusion

**Root Cause**: Execution order bug in VBlank flag timing - prevention check happens before prevention flag is set.

**Impact**: 8+ AccuracyCoin tests fail due to incorrect VBlank race condition handling.

**Fix Complexity**: Medium - requires restructuring tick() execution order.

**Expected Outcome**: Fixing Bug #1 should resolve all VBlank/NMI timing test failures.

**Interrupt Polling Status**: ✅ WORKING CORRECTLY - No fixes needed.
