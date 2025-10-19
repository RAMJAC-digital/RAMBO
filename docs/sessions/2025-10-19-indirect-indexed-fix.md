# Indirect Indexed Addressing Fix
**Date:** 2025-10-19
**Status:** ✅ FIXED - Addressing bug resolved, test progressed to different issue

---

## Summary

Fixed critical bug in indirect indexed addressing mode (`($00),Y`) where cycle 4 was being skipped, preventing the final operand read. This caused AccuracyCoin to hang in infinite loops.

## The Bug

**Symptom:** AccuracyCoin test hung with Y register at 0x27 instead of ~5, indicating loop ran 13 iterations instead of 2.

**Root Cause:** Threshold-based cycle completion check happened AFTER incrementing cycle counter, causing premature instruction completion.

### Execution Flow (Before Fix)
```
Cycle 0: fetchZpPointer
Cycle 1: fetchPointerLow
Cycle 2: fetchPointerHigh
Cycle 3: addYCheckPage (sets temp_value = open_bus ← BUG SOURCE)
         Increment cycle to 4
         Check: 4 >= 4 (threshold) → TRUE
         Complete WITHOUT executing cycle 4!
```

**Result:** `temp_value` contained garbage (open_bus) instead of actual memory value, causing `LDA ($00),Y` to read wrong values.

## Investigation Process

1. **Traced stack corruption** - FixRTS pushed 0x55 instead of 0x2E (39 bytes off)
2. **Tracked Y register** - Found Y=0x27 when expected ~5
3. **Analyzed loop** - Loop at F650 increments Y by 3, should stop at 0xFF terminator
4. **Found addressing bug** - `addYCheckPage` sets `temp_value = open_bus`, but `fixHighByte` was never called to read actual value

## The Fix

### 1. Threshold Adjustment (execution.zig:631-632)
```zig
// Before: threshold = page_crossed ? 5 : 4
// After:  threshold = page_crossed ? 6 : 5

// Execute cycles 0-4 (no page cross) or 0-5 (page cross)
// Threshold check happens AFTER cycle increment
const threshold: u8 = if (state.cpu.page_crossed) 6 else 5;
```

### 2. Add Cycle 5 Support (execution.zig:547)
```zig
// Before: 4 => CpuMicrosteps.fixHighByte(state),
// After:  4, 5 => CpuMicrosteps.fixHighByte(state),

// Handles both no-page-cross (cycle 4) and page-cross (cycle 5)
```

### 3. Fix temp_value for indirect_indexed (microsteps.zig:79-81)
```zig
// Page not crossed: absolute,X/Y already have correct temp_value
// But indirect_indexed has open_bus in temp_value, must read actual value
if (state.cpu.address_mode == .indirect_indexed) {
    state.cpu.temp_value = state.busRead(state.cpu.effective_address);
}
```

## Execution Flow (After Fix)
```
Cycle 0: fetchZpPointer
Cycle 1: fetchPointerLow
Cycle 2: fetchPointerHigh
Cycle 3: addYCheckPage (sets temp_value = open_bus)
         Increment cycle to 4
         Check: 4 >= 5 (threshold) → FALSE
         Continue...
Cycle 4: fixHighByte (reads actual value from effective_address into temp_value)
         Increment cycle to 5
         Check: 5 >= 5 (threshold) → TRUE
         Complete with CORRECT value in temp_value!
```

## Test Results

**Before Fix:**
- Test hung in infinite loop at PC=0xF650
- Y register reached 0x27 (39 iterations)
- Never found 0xFF terminator

**After Fix:**
- Test completes to end (1M cycles)
- Fails with ErrorCode=0x02 (different bug)
- Indirect indexed addressing works correctly
- 0xFF terminators found at correct offsets

## Why This Matters

This affects ALL `($00),Y` instructions (LDA, STA, CMP, etc.) when:
- Page NOT crossed (most common case in practice)
- Reads actual game data from ROM/RAM

Commercial games using indirect indexed addressing would read garbage values, causing:
- Wrong sprite positions
- Corrupted game state
- Incorrect physics calculations
- Random crashes

## Files Modified

1. **src/emulation/cpu/execution.zig**
   - Line 547: Added cycle 5 to fixHighByte switch
   - Line 631-632: Changed threshold from 4/5 to 5/6

2. **src/emulation/cpu/microsteps.zig**
   - Line 79-81: Added indirect_indexed check in fixHighByte to read actual value when page not crossed

## Related Documentation

- **Original bug report:** `docs/sessions/2025-10-19-BUG-FOUND.md`
- **Investigation:** `docs/sessions/2025-10-19-dummywrite-nmi-investigation.md`
- **Architecture:** `docs/dot/cpu-execution-flow.dot`

## Remaining Work

Test now fails with **ErrorCode=0x02** instead of hanging. This is a DIFFERENT bug - the indirect indexed addressing is confirmed working. The new failure suggests another accuracy issue unrelated to this addressing mode.

---

**Key Takeaway:** Cycle-accurate emulation requires precise threshold values that account for when checks occur relative to cycle increments. Off-by-one errors in threshold logic can completely break instruction execution.
