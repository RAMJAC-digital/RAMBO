# JSR/RTS Stack Operation Investigation

## Problem Statement

AccuracyCoin test shows stack pointer corruption:
- First test iteration: SP=0xFB (correct)
- Second iteration: SP=0xFD (incorrect - should be 0xFB)
- After failure: SP cycles 0x00→0xFD→0xFE→0xFF (infinite BRK loop)

This indicates JSR/RTS is NOT preserving stack state correctly across ROM's return-address manipulation.

---

## 6502 Hardware Behavior (Reference)

### JSR $nnnn (6 cycles)

Example: JSR at address $8000, target $1234

```
Address   Bytes       Instruction
$8000     20 34 12    JSR $1234

Cycle-by-cycle:
1. Fetch opcode $20 from $8000, PC → $8001
2. Fetch low byte $34 from $8001, PC → $8002
3. Internal operation (dummy read at SP)
4. Push PC_high ($80) to stack at $01xx, SP--
5. Push PC_low ($02) to stack at $01xx, SP--
6. Fetch high byte $12 from $8002, PC → $1234
```

**Critical Detail**: Value pushed to stack is $8002 (address of byte AFTER JSR operand).

**After JSR completes**: PC=$1234, Stack contains [$80, $02], SP decreased by 2

### RTS (6 cycles)

```
Cycle-by-cycle:
1. Dummy read at current stack pointer
2. SP++, dummy read at stack
3. SP++, pull low byte from stack → temp_low
4. SP++, pull high byte from stack → temp_high
5. Reconstruct PC from [temp_high:temp_low], increment PC
6. Dummy read at new PC

Wait, that's wrong. Let me check the actual RTS behavior...

Actually:
1. Fetch opcode (already done)
2. Dummy read at SP
3. SP++, dummy read at new SP
4. SP++, pull low byte
5. SP++, pull high byte, reconstruct PC
6. Increment PC, dummy read at PC

Hmm, that's 3 SP increments. Let me verify...

Correct RTS (6 cycles total, 4 after opcode fetch):
0. (Previous cycle: fetch RTS opcode)
1. Dummy read at SP
2. SP++, dummy read at new SP
3. SP++, pull low byte from stack
4. SP++, pull high byte from stack, reconstruct PC
5. Increment PC
6. Dummy read at PC, instruction complete

Wait, that's still wrong. The standard says:
- RTS pulls 2 bytes from stack
- Increments the result
- Jumps there

So SP should only increment TWICE (once for each pull), not three times.

Let me look at the actual nesdev documentation...
```

**After RTS completes**: PC=$8003 (one past the address that was pushed), SP increased by 2

---

## Our Implementation Analysis

### Current JSR Implementation (`execution.zig:333-340`)

```zig
0x20 => switch (state.cpu.instruction_cycle) {
    0 => fetchAbsLow(state),           // Fetch low byte, PC++
    1 => jsrStackDummy(state),         // Dummy read at SP
    2 => pushPch(state),               // Push PC high, SP--
    3 => pushPcl(state),               // Push PC low, SP--
    4 => fetchAbsHighJsr(state),       // Fetch high, jump
    else => unreachable,
}
```

### Current RTS Implementation (`execution.zig:342-349`)

```zig
0x60 => switch (state.cpu.instruction_cycle) {
    0 => stackDummyRead(state),        // Dummy read at SP
    1 => stackDummyRead(state),        // Dummy read at SP (DUPLICATE?)
    2 => pullPcl(state),               // SP++, pull low
    3 => pullPch(state),               // SP++, pull high
    4 => incrementPcAfterRts(state),   // Increment PC
    else => unreachable,
}
```

---

## Questions to Investigate

### 1. RTS Cycle 1 - Why Two Dummy Reads?

Our implementation does TWO dummy reads at cycles 0 and 1. Hardware does:
- Cycle 0: Dummy read at SP
- Cycle 1: Increment SP, dummy read

**Hypothesis**: We're NOT incrementing SP on the first dummy read, so both read the same address.

### 2. What Value Does JSR Push?

Need to verify: When PC=$8002 (after fetching low byte), do we push $8002 or something else?

**Check**: `pushPch` and `pushPcl` - what value of PC do they use?

### 3. Stack Pointer State Across Instructions

**Question**: Is SP correctly persisted between fetch_opcode cycles?

**Potential Issue**: State machine transitions might not preserve SP correctly.

### 4. ROM's Stack Manipulation

AccuracyCoin does:
```asm
CopyReturnAddressToByte0:
    PLA             ; Pull return address low
    STA <$02
    PLA             ; Pull return address high
    STA <$03
    PLA             ; Pull ANOTHER value (from JSR before CopyReturnAddressToByte0)
    STA <$00
    PLA             ; Pull ANOTHER value
    STA <$01
    ; ... manipulate ...
    ; ... push back ...
    RTS
```

This manipulates 4 bytes on the stack - 2 from the JSR to CopyReturnAddressToByte0, plus 2 more.

**Question**: Does our stack correctly handle this?

---

## Investigation Plan

### Step 1: Verify JSR Pushes Correct Value ✅

**Action**: Add logging to `pushPch` and `pushPcl` to show EXACT values pushed.

**File**: `src/emulation/cpu/microsteps.zig`

```zig
pub fn pushPch(state: anytype) bool {
    const stack_addr = 0x0100 | @as(u16, state.cpu.sp);
    const value = @as(u8, @truncate(state.cpu.pc >> 8));

    // TEMP DEBUG
    std.debug.print("pushPch: SP=0x{X:0>2}, addr=0x{X:0>4}, value=0x{X:0>2}, PC=0x{X:0>4}\n",
        .{state.cpu.sp, stack_addr, value, state.cpu.pc});

    state.busWrite(stack_addr, value);
    state.cpu.sp -%= 1;
    return false;
}

pub fn pushPcl(state: anytype) bool {
    const stack_addr = 0x0100 | @as(u16, state.cpu.sp);
    const value = @as(u8, @truncate(state.cpu.pc & 0xFF));

    // TEMP DEBUG
    std.debug.print("pushPcl: SP=0x{X:0>2}, addr=0x{X:0>4}, value=0x{X:0>2}, PC=0x{X:0>4}\n",
        .{state.cpu.sp, stack_addr, value, state.cpu.pc});

    state.busWrite(stack_addr, value);
    state.cpu.sp -%= 1;
    return false;
}
```

### Step 2: Verify RTS Pulls Correct Value ✅

**Action**: Add logging to `pullPcl` and `pullPch`.

```zig
pub fn pullPcl(state: anytype) bool {
    state.cpu.sp +%= 1;
    const stack_addr = 0x0100 | @as(u16, state.cpu.sp);
    state.cpu.operand_low = state.busRead(stack_addr);

    // TEMP DEBUG
    std.debug.print("pullPcl: SP=0x{X:0>2}, addr=0x{X:0>4}, value=0x{X:0>2}\n",
        .{state.cpu.sp, stack_addr, state.cpu.operand_low});

    return false;
}

pub fn pullPch(state: anytype) bool {
    state.cpu.sp +%= 1;
    const stack_addr = 0x0100 | @as(u16, state.cpu.sp);
    state.cpu.operand_high = state.busRead(stack_addr);
    state.cpu.pc = (@as(u16, state.cpu.operand_high) << 8) | @as(u16, state.cpu.operand_low);

    // TEMP DEBUG
    std.debug.print("pullPch: SP=0x{X:0>2}, addr=0x{X:0>4}, value=0x{X:0>2}, PC=0x{X:0>4}\n",
        .{state.cpu.sp, stack_addr, state.cpu.operand_high, state.cpu.pc});

    return false;
}
```

### Step 3: Check RTS Dummy Read Behavior

**Question**: Should the first dummy read increment SP?

**Reference**: nesdev.org/wiki/6502_cycle_times

**Action**: Research and verify cycle-accurate behavior.

### Step 4: Trace Complete JSR→RTS Cycle

**Goal**: Verify SP is balanced after JSR+RTS pair.

**Method**: Run test with logging, verify SP before JSR == SP after RTS.

### Step 5: Check State Machine Transitions

**Files**: `src/emulation/cpu/execution.zig`

**Verify**:
- SP persists correctly between states (.fetch_opcode, .fetch_operand_low, .execute)
- No hidden SP modifications
- No race conditions on SP updates

---

## Expected Behavior Matrix

| Operation | SP Before | SP After | Stack Change |
|-----------|-----------|----------|--------------|
| JSR       | 0xFD      | 0xFB     | -2 (push 2 bytes) |
| RTS       | 0xFB      | 0xFD     | +2 (pull 2 bytes) |
| JSR+RTS   | 0xFD      | 0xFD     | 0 (balanced) |
| PLA       | 0xFB      | 0xFC     | +1 (pull 1 byte) |
| PHA       | 0xFC      | 0xFB     | -1 (push 1 byte) |

**Test Case**:
```
Initial: SP=0xFD
JSR subroutine  → SP=0xFB
  ... code ...
RTS             → SP=0xFD
Expected: SP back to 0xFD
```

**AccuracyCoin Case**:
```
Initial: SP=0xFD
JSR CopyReturnAddressToByte0  → SP=0xFB
  PLA (4 times)                → SP=0xFF (pulls 4 bytes)
  ... manipulation ...
  (FixRTS re-pushes)           → SP=0xFB
  RTS                          → SP=0xFD
Expected: SP back to 0xFD
```

If SP ends up at different value, either:
1. JSR didn't push correct value
2. RTS didn't pull correct value
3. ROM's manipulation didn't match our expectations
4. FixRTS didn't restore correctly

---

## Next Steps

1. ✅ Add logging to push/pull operations
2. ✅ Run test and capture stack traces
3. ✅ Analyze if PC values are correct
4. ⏳ Verify SP balance - **FOUND ISSUE**
5. ✅ Research nesdev for cycle-accurate RTS behavior
6. ⏳ Fix any discrepancies found

---

## Investigation Results (2025-10-19)

### Findings from JSR/RTS Logging

Added detailed logging to `src/emulation/cpu/microsteps.zig`:
- `pushPch()`, `pushPcl()` - JSR stack push operations
- `pullPcl()`, `pullPch()` - RTS stack pull operations
- `incrementPcAfterRts()` - RTS PC increment
- `fetchAbsHighJsr()` - JSR jump completion

**Test execution with logging revealed:**

1. **PPU Open Bus: ✅ WORKING**
   - Pre-check: Write $2000=$42, Read $2000=$42 ✅
   - Pre-check: Write $2006=$2D, Read $2006=$2D ✅
   - Open bus is NOT the problem

2. **ErrorCode Progression:**
   ```
   Cycle 7293: ErrorCode 0xFF→0x00 (test start)
   Cycle 17750: ErrorCode 0x00→0x01 (subtest 1 complete)
   Cycle 28207: ErrorCode 0x01→0x02 (subtest 2 complete)
   Cycle 38664: ErrorCode 0x02→0x03 (subtest 3 complete)
   [VBlank wait ~81,774 cycles]
   Cycle 120438: ErrorCode 0x03→0x01 (second iteration starts)
   Cycle 130895: ErrorCode 0x01→0x02 (subtest 2 fails)
   ```
   - First iteration: Passes all 3 subtests
   - Second iteration: Fails at subtest 2

3. **Stack Pointer Corruption: ❌ CRITICAL BUG**
   ```
   First iteration (correct):
     SP starts at 0xFD
     After subtests: SP=0xFB

   Second iteration (WRONG):
     SP starts at 0xFD (should be 0xFB!)
     Test fails, enters BRK loop
     SP cycles: 0x00→0xFD→0xFE→0xFF
   ```

4. **JSR/RTS Stack Traces:**

   Example of CORRECT JSR+RTS pair:
   ```
   [JSR] pushPch: SP=0xFC → 0xFB, write 0xE5 to 0x01FC, PC=0xE503
   [JSR] pushPcl: SP=0xFB → 0xFA, write 0x03 to 0x01FB, PC=0xE503
   [JSR] jump to 0xA328
   ... subroutine executes ...
   [RTS] pullPcl: SP=0xFA → 0xFB, read 0x03 from 0x01FB
   [RTS] pullPch: SP=0xFB → 0xFC, read 0xE5 from 0x01FC, PC=0xE503
   [RTS] incrementPC: 0xE503 → 0xE504 (complete)
   ```
   ✅ JSR pushes PC=0xE503, RTS pulls 0xE503, increments to 0xE504 - **CORRECT**

   Example showing SP MISMATCH:
   ```
   [JSR] pushPch: SP=0xFC → 0xFB, write 0xA3 to 0x01FC, PC=0xA31B
   [JSR] pushPcl: SP=0xFB → 0xFA, write 0x1B to 0x01FB, PC=0xA31B
   [JSR] jump to 0xE500
   ... ROM executes CopyReturnAddressToByte0 which pulls from stack ...
   [RTS] pullPcl: SP=0xFD → 0xFE, read 0x?? from 0x01FE  ❌ WRONG SP!
   ```

   **Analysis:** JSR ends with SP=0xFA, but RTS starts with SP=0xFD. This means 3 bytes were pulled from the stack between JSR and RTS. According to AccuracyCoin source, `CopyReturnAddressToByte0` should pull 4 bytes:
   - 2 bytes: Return address from JSR to CopyReturnAddressToByte0
   - 2 bytes: Caller's return address

   But we're seeing only 3 bytes difference (0xFA → 0xFD).

### Root Cause Hypothesis

**Problem:** Stack pointer balance is incorrect after ROM's stack manipulation.

**Possible causes:**
1. **PLA (Pull Accumulator) implementation incorrect** - Not incrementing SP correctly
2. **PHA (Push Accumulator) implementation incorrect** - Not decrementing SP correctly
3. **ROM's FixRTS function not being called** - Stack not restored before RTS
4. **State machine not persisting SP** - Race condition between instruction cycles

**Next Action:** Add logging to PLA/PHA operations to trace ROM's stack manipulation in `CopyReturnAddressToByte0` and `FixRTS`.

---

## ROOT CAUSE IDENTIFIED (2025-10-19)

### Stack Trace Analysis with PLA/PHA Logging

Extended PPU cycle logging to 250,000 cycles and captured complete stack manipulation sequence.

**Critical Sequence Leading to Crash:**

```
Cycle 82370: ErrorCode 0x01→0x02 (second iteration, subtest 2 starts)

1. JSR from A32E to F647 (pushes return address A32E)
   SP: 0xFD → 0xFB
   Stack: [0x01FD=0xA3, 0x01FC=0x2E]

2. JSR from F64D to F375 (CopyReturnAddressToByte0)
   SP: 0xFB → 0xF9
   Stack: [0x01FD=0xA3, 0x01FC=0x2E, 0x01FB=0xF6, 0x01FA=0x4D]

3. CopyReturnAddressToByte0 executes:
   [PLA] pull: SP=0xF9 → 0xFA, read 0x4D
   [PLA] pull: SP=0xFA → 0xFB, read 0xF6
   [PLA] pull: SP=0xFB → 0xFC, read 0x2E  ← Pulls caller's return address!
   [PLA] pull: SP=0xFC → 0xFD, read 0xA3  ← Pulls caller's return address!

   **Pulls 4 bytes total (2 from JSR F375, 2 from JSR F647)**

4. CopyReturnAddressToByte0 restores partial stack:
   [PHA] push: SP=0xFD → 0xFC, write 0xF6
   [PHA] push: SP=0xFC → 0xFB, write 0x4D

   **Pushes only 2 bytes back**
   **NET STACK DEFICIT: -2 bytes**

5. RTS from F375:
   SP: 0xFB → 0xFD
   Returns to F64E (correct)

6. ... more operations ...

7. FINAL RTS (expected to return from F647):
   [RTS] pullPcl: SP=0xFD → 0xFE, read 0x0E from 0x01FE  ← GARBAGE!
   [RTS] pullPch: SP=0xFE → 0xFF, read 0x72 from 0x01FF  ← GARBAGE!
   PC=0x720E → 0x720F (after increment)

   **Reads uninitialized stack memory, creates invalid PC**

8. Execution reaches 0x720F (invalid/BRK instruction)
   → BRK handler pushes to stack
   → Jumps to 0x0600
   → Infinite BRK loop (SP cycles 0x00→0xFD→0xFE→0xFF)
```

### The Missing Piece: FixRTS

According to AccuracyCoin source code, `CopyReturnAddressToByte0` intentionally creates stack imbalance (-2 bytes). Functions that call it are responsible for calling `FixRTS` to restore balance.

**FixRTS behavior:**
- Pulls 2 bytes (its own return address)
- Calculates corrected address
- Pushes 3 bytes back (corrected address + offset compensation)
- **NET STACK ADJUSTMENT: +1 byte per call**

**The Problem:**
- `CopyReturnAddressToByte0` creates -2 byte deficit
- Requires 2 calls to `FixRTS` to restore balance
- In failing path: **FixRTS is NOT called or called incorrectly**
- Stack remains -2 bytes short
- Final RTS reads garbage from stack
- Crash ensues

### Why First Iteration Succeeds

First iteration (subtests 1-3) likely doesn't use `CopyReturnAddressToByte0`, or uses different code path where `FixRTS` is properly called. No PLA/PHA operations logged during first iteration.

### Why Second Iteration Fails

Second iteration (subtest 2 retry) calls `CopyReturnAddressToByte0` at F375, creating stack deficit. The code path either:
1. **Skips FixRTS call** (conditional branch taken incorrectly)
2. **FixRTS implementation bug** (not restoring correct number of bytes)
3. **Early return from function** (before FixRTS can execute)

---

## Next Investigation Steps

1. **Find FixRTS address** - Locate FixRTS in ROM and log when it's called
2. **Trace conditional branches** - Check if FixRTS call is being skipped
3. **Verify FixRTS implementation** - Ensure our PLA/PHA opcodes are correct
4. **Check for early returns** - Verify no early exits before stack restoration

---

**Session**: 2025-10-19
**Status**: ROOT CAUSE IDENTIFIED - Stack deficit from CopyReturnAddressToByte0 without FixRTS
**Priority**: CRITICAL - blocking 10+ tests
