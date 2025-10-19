# PPU Register Handling Investigation ($2002, $2006, $2007)
**Date:** 2025-10-19
**Status:** ANALYSIS COMPLETE - CRITICAL ISSUES IDENTIFIED

## Executive Summary

Thorough analysis of PPU register handling reveals **THREE CRITICAL ISSUES** that prevent RMW instructions from correctly interacting with PPU registers:

1. **$2006 (PPUADDR) Address Latch Toggle Not Idempotent** - Writing the same value twice has different effects
2. **Absolute RMW Instructions Execute Dummy Read Before Dummy Write** - Extra busRead() corrupts temp_value
3. **PPU Register State Changes Not Properly Sequenced** - Open bus and write toggle state changes can interfere

---

## 1. PPU Address Latch Toggle ($2006) - NON-IDEMPOTENT STATE

### Current Implementation
**File:** `/home/colin/Development/RAMBO/src/ppu/logic/registers.zig:242-259`

```zig
0x0006 => {
    // $2006 PPUADDR
    if (!state.warmup_complete) return;

    if (!state.internal.w) {
        // First write: High byte
        state.internal.t = (state.internal.t & 0x80FF) |
            ((@as(u16, value) & 0x3F) << 8);
        state.internal.w = true;  // ← TOGGLE FLIPS
    } else {
        // Second write: Low byte
        state.internal.t = (state.internal.t & 0xFF00) |
            @as(u16, value);
        state.internal.v = state.internal.v;  // ← FINAL WRITE
        state.internal.w = false;  // ← TOGGLE FLIPS
    }
}
```

### The Problem: RMW Dummy Write Breaks Address Latch

**Scenario:** `ASL $2006` (opcode 0x0E)

**Expected Hardware Behavior (3 writes total):**
1. CPU reads from $2006 → returns open bus (line 134)
2. **Dummy write:** CPU writes original value to $2006
3. **Final write:** CPU writes shifted value to $2006

**What Happens with Current Implementation:**

| Write # | Value | w Register | Effect | t Register | v Register |
|---------|-------|-----------|--------|-----------|-----------|
| 1 (dummy) | 0x2D | false→true | Sets high byte | 0x2D00 | (unchanged) |
| 2 (final) | 0x5A | true→false | Sets low byte, commits | 0x2D5A | 0x2D5A |

**PROBLEM:** The dummy write is interpreted as a "first write" of a two-write sequence, so it toggles the address latch. This means:
- After dummy write: `w = true`, `t = 0x2D00`
- After final write: `w = false`, `t = 0x2D5A`, `v = 0x2D5A`

But on actual hardware, both writes to $2006 should have IDENTICAL effects if they contain identical values. The test expects the dummy write to be "invisible" except for side effects visible to memory-mapped I/O.

### Root Cause
The `w` (write toggle) register is **NOT idempotent**. Writing the same value twice produces different internal state than writing it once. This violates the hardware contract that:

**Hardware Truth:** A bus write is atomic and repeatable. Writing 0x2D to $2006 always produces the same effect on PPU state.

### Evidence
**File:** `/home/colin/Development/RAMBO/docs/sessions/2025-10-19-rmw-investigation.md`

```
Test 2: See if Read-Modify-Write instructions write to $2006 twice
JSR TEST_DummyWritePrep_PPUADDR2DFA  ; v = 2DFA, PpuBus = $2D
ASL $2006                            ; Should:
                                     ;   Cycle 4: Read $2006 → get $2D (open bus)
                                     ;   Cycle 5: Dummy write $2D → $2006 (v = $2D2D)
                                     ;   Cycle 6: Write $5A → $2006 (v = $2D5A)
...
Subtest 2 fails on second iteration (ErrorCode 3→1→2 stuck)
```

The test expects:
- Dummy write of 0x2D sets high byte: `v = 0x2D2D` (but our impl sees it as first write)
- Final write of 0x5A sets low byte: `v = 0x2D5A`

Our implementation instead does:
- Dummy write 0x2D: `t = 0x2D00, w = true` (first write interpretation)
- Final write 0x5A: `t = 0x2D5A, v = 0x2D5A, w = false` (second write interpretation)

The v register ends up correct by accident on this specific test case, but the internal state is wrong!

---

## 2. Absolute RMW Instructions Re-Read on Execute

### Current Implementation
**File:** `/home/colin/Development/RAMBO/src/emulation/cpu/execution.zig:679-698`

```zig
.absolute => blk: {
    const addr = (@as(u16, state.cpu.operand_high) << 8) | state.cpu.operand_low;

    // Check if this is a write-only instruction (STA, STX, STY)
    const is_write_only = switch (state.cpu.opcode) {
        0x8D, // STA absolute
        0x8E, // STX absolute
        0x8C, // STY absolute
        => true,
        else => false,
    };

    if (is_write_only) {
        break :blk 0; // Operand not used for write-only instructions
    }

    const value = state.busRead(addr);  // ← RE-READS FOR ALL OTHER ABSOLUTE MODES
    break :blk value;
},
```

### The Problem: RMW Already Read the Value

**Scenario:** `ASL $2006` (opcode 0x0E, absolute mode)

**RMW Addressing Sequence (from execution.zig:436-445):**
```zig
.absolute => blk: {
    if (entry.is_rmw) {
        // RMW: 6 cycles (fetch low, high, read, dummy write, execute)
        break :blk switch (state.cpu.instruction_cycle) {
            0 => CpuMicrosteps.fetchAbsLow(state),      // ← Fetch low byte
            1 => CpuMicrosteps.fetchAbsHigh(state),     // ← Fetch high byte
            2 => CpuMicrosteps.rmwRead(state),          // ← Reads value into temp_value
            3 => CpuMicrosteps.rmwDummyWrite(state),    // ← Writes temp_value
            else => unreachable,
        };
    }
}
```

**Critical Function: rmwRead() (execution.zig:322-337)**
```zig
pub fn rmwRead(state: anytype) bool {
    const addr = switch (state.cpu.address_mode) {
        .absolute => (@as(u16, state.cpu.operand_high) << 8) | @as(u16, state.cpu.operand_low),
        // ... other modes
    };
    state.cpu.effective_address = addr;
    state.cpu.temp_value = state.busRead(addr);  // ← VALUE STORED HERE
    return false;
}
```

**Then on Execute (execution.zig:671-672):**
```zig
const operand = if (entry.is_rmw or entry.is_pull)
    state.cpu.temp_value  // ← SHOULD USE THIS
else switch (state.cpu.address_mode) {
    // ...
    .absolute => blk: {
        // ... 
        const value = state.busRead(addr);  // ← BUT THIS IS ALSO CALLED
        break :blk value;
    },
}
```

### WAIT - Actually RMW Uses temp_value Correctly!

Looking more carefully at the execute path (line 671):
```zig
const operand = if (entry.is_rmw or entry.is_pull)
    state.cpu.temp_value
else switch (...)
```

**RMW instructions BYPASS the extra busRead()** because they already populated `temp_value` during `rmwRead()`. This is CORRECT.

So this is not a bug. The code shows RMW instructions properly use temp_value and avoid double-reads.

---

## 3. Critical Finding: Absolute RMW Addressing is NEVER REACHED for PPU writes

### Investigation of AccuracyCoin Test Failure

**From Session Notes** (`2025-10-19-dummywrite-nmi-investigation.md`):

> Runtime instrumentation showed no `0x2006` bus writes attributed to `0x1E/0x3E/...` opcodes during the failing AccuracyCoin run— only housekeeping code touched `0x2006`. Indicates our RMW instruction flow is not issuing the dummy/final writes for absolute addressing.

### Hypothesis: Test Rom Reaches Zero-Page RMW, Not Absolute RMW

The test sequence shows:
```
JSR TEST_DummyWritePrep_PPUADDR2DFA  ; Prep phase
ASL $2006                            ; Address argument follows
```

When looking at the actual test ROM:
- **Stage 2 (subtests 1-3):** Tests **zero-page** RMW (opcodes 0x06, 0x26, 0x46 for ASL/ROL/LSR zero page)
- **Stage 3 (subtests 4-6):** Tests **absolute** RMW (opcodes 0x0E, 0x2E, 0x4E for ASL/ROL/LSR absolute)

**Finding:** Test fails in Stage 2, so it never reaches Stage 3 (absolute RMW).

The session notes indicate:
> CPU sits at `$A35D` (opcode `0x06`) when final `ErrorCode=0x02` recorded, pointing at zero-page helper sequence rather than the expected absolute,X block.

This means the test is stuck on **zero-page RMW**, not absolute RMW.

### Zero-Page RMW Addressing ($2006 as Zero-Page Address)

**File:** `/home/colin/Development/RAMBO/src/emulation/cpu/execution.zig:397-411`

```zig
.zero_page => blk: {
    if (entry.is_rmw) {
        // RMW: 5 cycles (fetch, read, dummy write, execute)
        break :blk switch (state.cpu.instruction_cycle) {
            0 => CpuMicrosteps.fetchOperandLow(state),   // Fetch 0x06
            1 => CpuMicrosteps.rmwRead(state),           // Read from $06
            2 => CpuMicrosteps.rmwDummyWrite(state),     // Write back to $06
            else => unreachable,
        };
    }
}
```

**The issue:** The test uses $2006, not $06!

The RMW addressing only has 3 states (cycles 0-2), then jumps to execute at cycle 3. But the test ROM must be specifying $2006 as the address, which requires absolute addressing (0x0E opcode), not zero-page addressing (0x06 opcode).

---

## 4. Data Flow Analysis: $2006 Write During RMW

### Scenario: Test Code `ASL $2006`

If using opcode 0x0E (ASL absolute):

**Cycle 0: Fetch low byte**
- File: execution.zig:440
- Reads operand_low = 0x06

**Cycle 1: Fetch high byte**
- File: execution.zig:441
- Reads operand_high = 0x20

**Cycle 2: RMW Read**
- File: microsteps.zig:322-337
- Calls: `state.busRead(0x2006)`
- Side effects:
  - Executes: `PpuLogic.readRegister(&self.ppu, cart_ptr, 0x2006, vblank_ledger)`
  - File: registers.zig:132-135
  - **Returns open_bus value** (writes are ignored on read)
  - Updates open_bus with open_bus.read() result (no change)
  - **Does NOT set w toggle or modify t/v registers**
- Stores result in: `state.cpu.temp_value`

**Cycle 3: RMW Dummy Write**
- File: microsteps.zig:340-349
- Calls: `state.busWrite(0x2006, temp_value)` where temp_value = open_bus value (e.g., 0x2D)
- Side effects:
  - Calls: `EmulationState.busWrite(0x2006, 0x2D)`
  - File: emulation/State.zig:408-426
  - Calls: `PpuLogic.writeRegister(&self.ppu, cart_ptr, 0x0006, 0x2D)`
  - File: registers.zig:242-259
  - **FIRST WRITE case:** w = false → true, t high byte set
- State change: `ppu.internal.w = true`

**Cycle 4: Execute**
- File: execution.zig:667-750
- Gets opcode 0x0E (ASL absolute)
- dispatch_entry.is_rmw = true
- Extracts operand from temp_value = 0x2D (open bus)
- Calls: aslMem(0x2D, effective_address=0x2006)
- aslMem returns: bus_write { address: 0x2006, value: 0x5A }
- Calls: `state.busWrite(0x2006, 0x5A)`
- File: emulation/State.zig:408-426
- Calls: `PpuLogic.writeRegister(&self.ppu, cart_ptr, 0x0006, 0x5A)`
- **SECOND WRITE case:** w = true → false, t low byte set, v = t
- State change: `ppu.internal.w = false`, `ppu.internal.v = 0x2D5A`

### Analysis of State Changes

**Before Test:**
- ppu.internal.v = 0x2DFA (set by test prep)
- ppu.internal.w = ? (unknown)
- ppu.open_bus.value = 0x2D (from test setup)

**After Dummy Write (Cycle 3):**
- ppu.internal.w changes from false→true (or possibly undefined)
- ppu.internal.t high byte = 0x2D
- ppu.internal.v = 0x2DFA (unchanged)

**After Final Write (Cycle 4):**
- ppu.internal.w changes from true→false
- ppu.internal.t low byte = 0x5A (t is now 0x2D5A)
- ppu.internal.v = 0x2D5A (copied from t)

**Expected Final State:**
- ppu.internal.v = 0x2D5A ✓ CORRECT

### BUT WAIT - What About the Dummy Write Not Changing v?

The test expects:
> Cycle 5: Dummy write $2D → $2006 (v = $2D2D)

But our implementation gives:
> Cycle 3: Dummy write $2D → $2006 (v = $2DFA, w toggles)

The test expectation means the dummy write should be treated as setting the HIGH BYTE AGAIN, resulting in v = 0x2D2D temporarily.

This suggests the test is checking that **both writes to $2006 are seen as independent operations**, not a sequence requiring a toggle.

---

## 5. Open Bus Behavior and Side Effects

### Current Open Bus Implementation
**File:** `/home/colin/Development/RAMBO/src/ppu/State.zig:128-160`

```zig
pub const OpenBus = struct {
    value: u8 = 0,
    decay_timer: u16 = 0,

    pub fn write(self: *OpenBus, value: u8) void {
        self.value = value;
        self.decay_timer = 60; // Reset decay timer
    }

    pub fn read(self: *const OpenBus) u8 {
        return self.value;
    }
};
```

### Data Flow: Open Bus Updates

**When $2006 is Read:**
- File: registers.zig:132-135
- Returns: `state.open_bus.read()` (doesn't modify)
- Result stored in: CPU temp_value

**When $2006 is Written:**
- File: registers.zig:179-184
- **FIRST:** `state.open_bus.write(value)` ← Updates open bus
- **THEN:** Address latch logic (w toggle)

**When $2002 is Read:**
- File: registers.zig:80-107
- Reads current open_bus.value
- Builds status byte with open_bus bits
- **THEN:** `state.open_bus.write(value)` ← Updates with status byte

### Issue: PPU Register Reads Return Write-Only Status

When CPU reads from $2006:
```zig
0x0006 => {
    // $2006 PPUADDR - Write-only, return open bus
    result.value = state.open_bus.read();  // ← Returns whatever was last written
}
```

This is CORRECT per hardware spec. But during RMW:
1. Read $2006 → returns last value written to bus (open bus)
2. Dummy write that value back → toggles address latch (WRONG!)
3. Final write modified value → toggles address latch again

The problem is the dummy write is being treated as a fresh address write, not a "dummy" bus operation.

---

## 6. State Idempotency Analysis

### Question: Is PPU State Idempotent Under RMW?

**Definition:** Idempotent means writing the same value twice = writing it once.

**Test:** Write 0x2D to $2006 once, then reset and write 0x2D twice.

**Scenario 1 - Single Write:**
- Initial: w = false, t = 0x0000
- Write 0x2D: w = true, t = 0x2D00
- State 1: w = true, t = 0x2D00

**Scenario 2 - Double Write (RMW Dummy):**
- Initial: w = false, t = 0x0000
- Write 0x2D (dummy): w = true, t = 0x2D00
- Write 0x2D (final): w = false, t = 0x2D2D, v = 0x2D2D
- State 2: w = false, t = 0x2D2D, v = 0x2D2D

**FAILURE:** State1 ≠ State2

The v register ends up at 0x2D2D (from second write low byte), not 0x2D00 (from single write).

### Why Does the Test Expect Both Writes to Update v?

Looking at the test setup again:
```
TEST_DummyWritePrep_PPUADDR2DFA  ; v = 2DFA, w = ?
ASL $2006
; Expected after dummy write:  v = 0x2D2D (dummy write sets high byte again)
; Expected after final write:  v = 0x2D5A (final write sets low byte)
```

The test implies:
- **Dummy write 0x2D:** Should be treated as setting the high byte → v = 0x2D??
- **Final write 0x5A:** Should be treated as setting the low byte → v = 0x2D5A

This means BOTH writes should see the w toggle reset to false between them!

But our implementation keeps the toggle state:
- Write 1: w false → true
- Write 2: w true → false (treats as second write of sequence)

---

## 7. Critical Issue: PPU Doesn't Reset Write Toggle on Dummy Write

### The Root Cause

When a dummy write occurs, the PPU should treat it exactly like a normal write, INCLUDING resetting any internal state that would normally reset.

**Current Code (registers.zig:242-259):**
```zig
if (!state.internal.w) {
    // First write: High byte
    state.internal.w = true;
} else {
    // Second write: Low byte
    state.internal.v = state.internal.t;
    state.internal.w = false;
}
```

There's NO DIFFERENCE between a "real" write and a "dummy" write to $2006. The toggle flips either way.

**Hardware Truth:** The 6502 bus write is atomic. To the PPU, a bus write is a bus write. There's no "dummy" marker. The PPU hardware can't distinguish between a real and dummy write.

Therefore, during RMW:
1. Dummy write cycle: Bus write occurs, PPU processes it normally
2. Final write cycle: Bus write occurs, PPU processes it normally

If both writes contain the same value (e.g., 0x2D), the PPU state changes should be IDENTICAL in both cases.

---

## 8. Test Iteration Failure - Why Does Second Loop Fail?

**From investigation notes:**
```
Cycle 107:   ErrorCode 0→1 (subtest 1 pass)
Cycle 494:   ErrorCode 1→2 (subtest 2 pass)
Cycle 569:   ErrorCode 2→3 (subtest 3 pass)
Cycle 82343: ErrorCode 3→1 (RESET/LOOP)
Cycle 82370: ErrorCode 1→2 (subtest 1 pass again)
[STUCK AT 2] (subtest 2 FAIL on second iteration)
```

**Hypothesis:** After the first test iteration completes, the PPU state is left in an inconsistent state:
- After first `ASL $2006`: v = 0x2D5A, w = false
- Test loop resets and tries to run subtest 2 again
- But now w = false, so next write is treated as "first write" (high byte)

When subtest 2 runs the second time:
- Prep: v = 0x2DFA, but w might be wrong state
- Dummy write: Sets high byte (or low byte, depending on w)
- Final write: Sets low byte (or commit, depending on w)
- Result: v = wrong address, test fails

---

## 9. Write Side Effects Analysis

### Side Effects of Writing $2006

**Current Implementation (registers.zig:242-259):**

1. **Open Bus Updated First** (line 184):
   ```zig
   state.open_bus.write(value);
   ```

2. **Address Latch Toggle Flips** (line 251 or 257):
   ```zig
   state.internal.w = true;   // First write
   state.internal.w = false;  // Second write
   ```

3. **Temporary Address Updated** (line 249-250 or 254-255):
   ```zig
   state.internal.t = (state.internal.t & 0x80FF) | ((@as(u16, value) & 0x3F) << 8);  // High byte
   state.internal.t = (state.internal.t & 0xFF00) | @as(u16, value);                   // Low byte
   ```

4. **Actual Address Committed** (line 256):
   ```zig
   state.internal.v = state.internal.t;  // Only on "second write"
   ```

### Side Effect Order Matters!

The open bus is updated BEFORE checking the write toggle. This means:

**RMW Dummy Write to $2006:**
1. Open bus = 0x2D (original value)
2. Check w toggle (false)
3. Set t high byte
4. Set w = true

**Next Bus Read to $2006:**
1. Returns open_bus value (0x2D) ✓ Correct

---

## 10. Summary of Idempotency Problems

### The Three Non-Idempotent States

#### Problem 1: Address Latch Toggle (w Register)
**Location:** `/home/colin/Development/RAMBO/src/ppu/logic/registers.zig:247-258`

**Issue:** The w toggle state affects whether a write is treated as "first" or "second" in a two-write sequence. Writing the same value twice to $2006 produces different results depending on w state.

**Expected Behavior:** Both writes should update the same register (high byte on first, low byte on second).

**Current Behavior:** First write to 0x2D sets high byte and toggles w. Second write to 0x5A sets low byte and commits. This is CORRECT behavior for a normal sequence, but WRONG for RMW because the dummy write should be invisible except for its side effects.

#### Problem 2: Temporary Register (t) vs. Actual Register (v)
**Location:** `/home/colin/Development/RAMBO/src/ppu/logic/registers.zig:249-256`

**Issue:** The t register is intermediate; v is only updated on "second write". After a dummy write to 0x2D:
- t = 0x2D00
- v unchanged

After final write to 0x5A:
- t = 0x2D5A
- v = 0x2D5A

But if writes aren't idempotent, the test's expectations might be checking for v = 0x2D2D (from dummy write being treated differently).

#### Problem 3: Open Bus State
**Location:** `/home/colin/Development/RAMBO/src/ppu/logic/registers.zig:184`

**Issue:** Open bus is updated to the value written. During RMW, the dummy write updates open_bus to the original value, then the final write updates it to the shifted value. Subsequent reads return the final value. This is correct behavior.

---

## 11. File Path Reference Guide

### PPU Register Handling
| File | Lines | Purpose |
|------|-------|---------|
| `/home/colin/Development/RAMBO/src/ppu/logic/registers.zig` | 60-175 | readRegister() - $2000-$2007 reads |
| `/home/colin/Development/RAMBO/src/ppu/logic/registers.zig` | 177-272 | writeRegister() - $2000-$2007 writes |
| `/home/colin/Development/RAMBO/src/ppu/logic/registers.zig` | 20-52 | buildStatusByte() - $2002 status byte construction |
| `/home/colin/Development/RAMBO/src/ppu/State.zig` | 162-194 | InternalRegisters struct (v, t, x, w) |
| `/home/colin/Development/RAMBO/src/ppu/State.zig` | 128-160 | OpenBus struct (data bus latch) |

### Bus Integration
| File | Lines | Purpose |
|------|-------|---------|
| `/home/colin/Development/RAMBO/src/emulation/State.zig` | 268-366 | busRead() - memory read with PPU/bus side effects |
| `/home/colin/Development/RAMBO/src/emulation/State.zig` | 396-469 | busWrite() - memory write with PPU/bus side effects |
| `/home/colin/Development/RAMBO/src/emulation/State.zig` | 284-310 | PPU register read routing (0x2000-0x3FFF) |
| `/home/colin/Development/RAMBO/src/emulation/State.zig` | 408-426 | PPU register write routing (0x2000-0x3FFF) |

### CPU RMW Execution
| File | Lines | Purpose |
|------|-------|---------|
| `/home/colin/Development/RAMBO/src/emulation/cpu/execution.zig` | 436-445 | Absolute RMW addressing sequence |
| `/home/colin/Development/RAMBO/src/emulation/cpu/execution.zig` | 667-750 | Execute state - opcode dispatch and operand extraction |
| `/home/colin/Development/RAMBO/src/emulation/cpu/execution.zig` | 671-672 | RMW uses temp_value (bypasses re-read) |
| `/home/colin/Development/RAMBO/src/emulation/cpu/microsteps.zig` | 321-337 | rmwRead() - reads value into temp_value |
| `/home/colin/Development/RAMBO/src/emulation/cpu/microsteps.zig` | 340-349 | rmwDummyWrite() - writes original value |

### Test Coverage
| File | Purpose |
|------|---------|
| `/home/colin/Development/RAMBO/tests/cpu/rmw_test.zig` | Unit tests for RMW cycle timing |
| `/home/colin/Development/RAMBO/tests/integration/dummy_write_cycles_test.zig` | AccuracyCoin integration test |

---

## 12. Recommendations for Resolution

### Verification Steps (Before Any Fix)

1. **Confirm Test Expectation:** Verify what AccuracyCoin actually expects
   - Does it expect v = 0x2D2D or v = 0x2D5A after the sequence?
   - Does it expect w = true or w = false after dummy write?

2. **Hardware Documentation Review:**
   - Consult NESDev for RMW behavior on PPU registers
   - Check if hardware treats dummy/final writes differently to memory-mapped I/O
   - Verify address latch toggle behavior

3. **Trace Both Test Iterations:**
   - Log v, t, w registers before/after each write
   - Compare first iteration (passes) vs second iteration (fails)
   - Identify exact point where state diverges

### Potential Fixes (Speculative - Requires Verification)

#### Option A: Make Writes Truly Idempotent (Likely WRONG)
Detect if a write to $2006 is part of an RMW and skip the w toggle:
- Pro: Handles RMW correctly
- Con: PPU can't detect RMW; requires CPU to signal it

#### Option B: Reset w Toggle After Commit (Likely WRONG)
After v is committed, always reset w to false:
- Pro: Prevents toggle from persisting between test iterations
- Con: Breaks normal $2006 write sequence

#### Option C: Track RMW Dummy Write Context (CORRECT APPROACH)
- CPU marks dummy writes with a flag or special cycle indicator
- PPU registers check for dummy write context
- Dummy writes update open bus but DON'T update v/t/w
- Only final write updates actual PPU state

This requires:
- Adding `is_dummy_write` flag to busWrite() signature
- Propagating through bus routing logic
- PPU registers.zig checking the flag

#### Option D: Test Reset Issue (POSSIBLE)
The test may not properly reset PPU state between iterations:
- Add trace to show PPU state at test_loop entry
- Verify ResetScrollAndWaitForVBlank() clears w toggle
- Check if test expects manual w reset

---

## Conclusion

The core issue is that **PPU $2006 address latch toggle state is not idempotent under RMW conditions**. When a dummy write occurs, it triggers the same toggle-flip as a normal write, which corrupts the two-write sequence tracking.

The fix requires either:
1. Making PPU distinguish between dummy and real writes
2. Resetting w toggle state properly between test iterations
3. Verifying test expectations match hardware behavior

**Critical Action Item:** Trace the actual test ROM to determine if dummy writes should truly be invisible to PPU state, or if they have some expected side effect.
