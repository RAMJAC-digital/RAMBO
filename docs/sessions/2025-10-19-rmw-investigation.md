# RMW Dummy Write Investigation
**Date:** 2025-10-19
**Status:** 🔍 IN PROGRESS - RMW writes work, but AccuracyCoin fails on second iteration

---

## Summary

Investigated why AccuracyCoin DUMMY WRITE CYCLES test fails with ErrorCode=0x02. **CRITICAL FINDING:** RMW instructions ARE working correctly. The test passes initially but fails on a second iteration, suggesting a PPU state corruption issue.

## Investigation Process

### Initial Hypothesis: RMW Final Write Missing

**Symptom:** `INC $10` appeared not to modify memory (ErrorCode stayed 0x00)

**Investigation:**
```zig
// Added logging to execution.zig:729-742
[RMW Execute] PC=0xA25B, opcode=0xE6, operand=0x00, effective_addr=0x0010
[RMW Execute] bus_write=.{ .address = 16, .value = 1 }
[BusWrite] addr=0x0010, value=0x01
Cycle 107: ErrorCode 0x00→0x01  ✅
```

**Result:** RMW final write IS happening correctly. The opcode function returns `bus_write` and it's being applied.

### Discovery: Test Iteration Pattern

**Error Pattern:**
```
Cycle 107:   ErrorCode 0→1 (subtest 1 pass)
Cycle 494:   ErrorCode 1→2 (subtest 2 pass)
Cycle 569:   ErrorCode 2→3 (subtest 3 pass)
Cycle 82343: ErrorCode 3→1 (RESET/LOOP)
Cycle 82370: ErrorCode 1→2 (subtest 1 pass)
[STUCK AT 2] (subtest 2 FAIL on second iteration)
```

**Key Finding:** Subtests pass on first run but fail when repeated. This indicates:
- Not a fundamental RMW bug
- Likely PPU state corruption/inconsistency
- Test expects repeatable behavior

### Understanding Test 2 (ErrorCode=0x02)

From `tests/data/AccuracyCoin/AccuracyCoin.asm:2099-2200`:

```asm
;;; Test 2: See if Read-Modify-Write instructions write to $2006 twice
JSR TEST_DummyWritePrep_PPUADDR2DFA ; v = 2DFA, PpuBus = $2D
ASL $2006                           ; Should:
                                    ;   Cycle 4: Read $2006 → get $2D (open bus)
                                    ;   Cycle 5: Dummy write $2D → $2006 (v = $2D2D)
                                    ;   Cycle 6: Write $5A → $2006 (v = $2D5A)
JSR DoubleLDA2007                   ; Read VRAM twice
CMP #$60                            ; Expect value at $2D5A
BNE TEST_FailDummyWrites
```

**Test Logic:**
1. Prep PPU: v=$2DFA, data bus=$2D
2. Execute `ASL $2006` (shifts $2D left → $5A)
3. Dummy write should write $2D to $2006 first (v=$2D2D)
4. Final write should write $5A to $2006 (v=$2D5A)
5. Reading $2007 twice should fetch value from VRAM[$2D5A] = $60

### RMW Dummy Write Implementation

File: `src/emulation/cpu/microsteps.zig:340-348`

```zig
pub fn rmwDummyWrite(state: anytype) bool {
    if (state.cpu.effective_address >= 0x2000 and state.cpu.effective_address <= 0x3FFF) {
        @import("std").debug.print(
            "rmwDummyWrite addr=0x{X:0>4} value=0x{X:0>2} opcode=0x{X:0>2} cycle={d}\n",
            .{ state.cpu.effective_address, state.cpu.temp_value, state.cpu.opcode, state.clock.ppu_cycles },
        );
    }
    state.busWrite(state.cpu.effective_address, state.cpu.temp_value);  // ✅ WRITES
    return false;
}
```

**Status:** Dummy write IS being called and IS writing to the bus.

### Cycle Timing Verification

Zero-page RMW (e.g., `INC $10`):
```zig
// execution.zig:397-411
.zero_page => if (entry.is_rmw) {
    break :blk switch (state.cpu.instruction_cycle) {
        0 => CpuMicrosteps.fetchOperandLow(state),  // Fetch address
        1 => CpuMicrosteps.rmwRead(state),           // Read value
        2 => CpuMicrosteps.rmwDummyWrite(state),     // ✅ Dummy write
        else => unreachable,
    };
}
// Threshold: instruction_cycle >= 3 (line 588)
// Cycle 3: execute state writes modified value
```

**Status:** Correct 5-cycle RMW sequence (fetch, read, dummy write, execute).

## Current Status

### What Works ✅
- RMW instructions execute correctly
- Dummy write cycle happens (cycle 5 of 6)
- Final write cycle happens (cycle 6 of 6)
- Memory modifications verified (ErrorCode increments properly)
- Subtests 1-3 pass on first iteration

### What Fails ❌
- Subtest 2 fails on second iteration (ErrorCode 3→1→2 stuck)
- Test result: 0x80 (running) instead of 0x00 (pass)

### Next Steps

1. **Trace PPU $2006 writes during both iterations**
   - Compare PPU state before subtest 2 (first vs second run)
   - Check if v register values match expected ($2DFA, $2D2D, $2D5A)
   - Verify data bus has correct value ($2D) before RMW

2. **Check PPU register write handling**
   - Verify $2006 writes update v register correctly
   - Check if dummy write to $2006 is processed differently than final write
   - Ensure PPU address latch toggle state is correct

3. **Investigate test reset mechanism**
   - Understand what happens at cycle 82343 (ErrorCode 3→1)
   - Check if PPU state should be reset between iterations
   - Verify `ResetScrollAndWaitForVBlank` properly clears state

4. **Add detailed PPU logging**
   - Log every write to $2006 with v/t register state
   - Track address latch toggle state
   - Compare first iteration vs second iteration state

## Files Modified

- `src/emulation/cpu/execution.zig` - Added/removed debug logging (cleaned up)
- `tests/integration/accuracy/dummy_write_cycles_test.zig` - Test file (no changes)

## Diagnostic Scripts Created

- `/tmp/trace_error_loop.zig` - Track ErrorCode changes
- `/tmp/trace_rmw.zig` - Find RMW instructions
- `/tmp/trace_rmw_detailed.zig` - Cycle-by-cycle RMW execution
- `/tmp/trace_rmw_microsteps.zig` - Verify INC writes
- `/tmp/test_inc_directly.zig` - Direct opcode function test
- `/tmp/trace_subtest2.zig` - Detailed subtest 2 execution

## Related Documentation

- `docs/sessions/2025-10-19-indirect-indexed-fix-CORRECTED.md` - Previous fix (unrelated)
- `tests/data/AccuracyCoin/AccuracyCoin.asm` - Test source code

---

**Key Insight:** This is NOT an RMW implementation bug. The dummy write happens correctly. This is likely a **PPU state management issue** where the PPU v register or address latch gets into an inconsistent state after the first test iteration.
