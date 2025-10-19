# Indirect Indexed Addressing Fix (CORRECTED)
**Date:** 2025-10-19
**Status:** ✅ FIXED - Correct implementation completed

---

## Summary

Fixed bug in indirect indexed addressing mode `($00),Y` where the dummy read value was discarded even when it was the actual operand value (non-page-crossing case).

## Original Incorrect Fix (Reverted)

**WRONG APPROACH** (commit 0347bf9):
- Changed threshold from 4→5 for non-page-cross
- Added cycle 5 to switch statement
- Added extra `busRead()` in `fixHighByte`

**Problem**: This added an extra cycle to ALL indirect_indexed instructions, breaking cycle-accurate timing.

## Root Cause Analysis

### The Real Bug

In `addYCheckPage` (microsteps.zig:145-163), the dummy read value was always discarded:

```zig
// BEFORE (WRONG):
const dummy_addr = (base & 0xFF00) | (state.cpu.effective_address & 0x00FF);
_ = state.busRead(dummy_addr);  // Read value...
state.cpu.temp_value = state.bus.open_bus;  // ...then throw it away!
```

### Hardware Behavior

**When page NOT crossed:**
- `dummy_addr` == `effective_address` (same page)
- The "dummy" read IS the actual operand read
- Must use the value, not discard it

**When page crossed:**
- `dummy_addr` != `effective_address` (different pages)
- The dummy read is genuinely wrong
- Discard value, `fixHighByte` will re-read

### Cycle Counts (6502 Hardware)

**No Page Cross**: 5 cycles total
```
Cycle 0: Fetch ZP pointer
Cycle 1: Fetch pointer low byte
Cycle 2: Fetch pointer high byte
Cycle 3: Add Y, read from calculated address (temp_value = value read)
Cycle 4: Execute (uses temp_value)
```

**Page Cross**: 6 cycles total
```
Cycle 0: Fetch ZP pointer
Cycle 1: Fetch pointer low byte
Cycle 2: Fetch pointer high byte
Cycle 3: Add Y, dummy read at wrong address (temp_value = open_bus)
Cycle 4: Fix high byte, read from correct address (temp_value = value read)
Cycle 5: Execute (uses temp_value)
```

## The Correct Fix

### 1. Fix addYCheckPage (microsteps.zig:145-163)

```zig
pub fn addYCheckPage(state: anytype) bool {
    const base = (@as(u16, state.cpu.operand_high) << 8) | @as(u16, state.cpu.temp_value);
    state.cpu.effective_address = base +% state.cpu.y;
    state.cpu.page_crossed = (base & 0xFF00) != (state.cpu.effective_address & 0xFF00);

    const dummy_addr = (base & 0xFF00) | (state.cpu.effective_address & 0x00FF);
    const dummy_value = state.busRead(dummy_addr);

    // CRITICAL: When page NOT crossed, the dummy read IS the actual read
    if (!state.cpu.page_crossed) {
        state.cpu.temp_value = dummy_value; // Use the value we just read
    } else {
        state.cpu.temp_value = state.bus.open_bus; // Page crossed: value discarded
    }

    return false;
}
```

### 2. Keep Original Thresholds (execution.zig:631)

```zig
// CORRECT (kept as-is):
const threshold: u8 = if (state.cpu.page_crossed) 5 else 4;
```

### 3. Simplify fixHighByte (microsteps.zig:70-81)

```zig
pub fn fixHighByte(state: anytype) bool {
    if (state.cpu.page_crossed) {
        state.cpu.temp_value = state.busRead(state.cpu.effective_address);
    }
    // Page not crossed: temp_value already correct from addYCheckPage
    return false;
}
```

## Validation

### Test: Manual Indirect Indexed Addressing
```zig
// Setup: $00-$01 points to $A32D
h.state.bus.ram[0x00] = 0x2D;
h.state.bus.ram[0x01] = 0xA3;

// Results:
Y=0x00: reads 0x47 from $A32D ✅
Y=0x01: reads 0xF6 from $A32E ✅
Y=0x02: reads 0x2D from $A32F ✅
```

**Before fix**: Would read `open_bus` (garbage) for all these
**After fix**: Reads correct values from memory

### AccuracyCoin Status

The AccuracyCoin DUMMY WRITE CYCLES test still fails with ErrorCode=0x02, but this is **NOT** related to indirect_indexed addressing.

**Actual cause**: RMW dummy writes not implemented (known issue, documented in test header).

## Impact

**Fixed**:
- ✅ `LDA ($nn),Y` reads correct values
- ✅ All indirect_indexed instructions work properly
- ✅ Cycle timing matches hardware (5 or 6 cycles)

**Not affected by this fix**:
- ❌ RMW dummy writes (separate unimplemented feature)
- ❌ AccuracyCoin test (fails for different reason)

## Files Modified

1. **src/emulation/cpu/microsteps.zig** (lines 145-163)
   - Modified `addYCheckPage` to conditionally use dummy read value

2. **src/emulation/cpu/microsteps.zig** (lines 70-81)
   - Simplified `fixHighByte` (removed incorrect extra read)

3. **src/emulation/cpu/execution.zig** (lines 522-545)
   - Kept original threshold logic (4/5, not 5/6)
   - Kept original cycle switch (4 only, not 4,5)

## Related Documentation

- **Incorrect fix**: `docs/sessions/2025-10-19-indirect-indexed-fix.md` (SUPERSEDED)
- **Investigation**: `docs/sessions/2025-10-19-BUG-FOUND.md`
- **Code review**: Identified timing issue in commit 0347bf9

---

**Key Lesson**: When fixing addressing mode bugs, maintain exact cycle counts per nesdev.org specification. Adding or removing cycles breaks timing-sensitive code even if the values read are correct.
