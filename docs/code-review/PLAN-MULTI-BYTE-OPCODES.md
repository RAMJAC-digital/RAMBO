# Development Plan: Multi-Byte & Control Flow Opcodes

**Date:** 2025-10-05
**Status:** Proposed

## 1. Goal

Implement the four remaining critical control flow opcodes (`JSR`, `RTS`, `RTI`, `BRK`) in a way that is fully compatible with the existing tick-accurate, pure functional CPU architecture. The implementation must keep opcode logic stateless and isolate all side effects to the execution engine.

## 2. Chosen Approach: Microstep Decomposition

Instead of making the `OpcodeResult` delta structure more complex to handle multiple stack operations, we will treat these instructions as a sequence of **microsteps**, identical to how addressing modes are currently handled. The entire logic of the instruction will be encoded in its microstep sequence.

**Why this approach is superior:**

*   **Preserves Architectural Purity:** The `opcodes` module remains entirely pure. The `execute_pure` function for these opcodes will simply be `Opcodes.nop`.
*   **Cycle-Accurate by Design:** Each microstep naturally corresponds to one CPU cycle, making it easy to model the hardware's behavior precisely.
*   **Leverages Existing Engine:** The execution engine in `src/cpu/Logic.zig` is already built to process microstep sequences. No changes to the main `tick()` loop are required.
*   **Simplicity:** It avoids complicating the `OpcodeResult` struct and the interface for the 252 opcodes that are already implemented and working.

## 3. Step-by-Step Implementation Plan

### Step 1: Create New Microstep Functions

New helper functions will be added to `src/cpu/execution.zig`. These functions will perform single, atomic actions on the CPU state, such as pushing a single byte to the stack.

**Functions to be created:**

*   `pushPch(state: *CpuState, bus: *Bus) -> bool`: Pushes the high byte of the program counter to the stack.
*   `pushPcl(state: *CpuState, bus: *Bus) -> bool`: Pushes the low byte of the program counter to the stack.
*   `pushStatus(state: *CpuState, bus: *Bus) -> bool`: Pushes the status register (with B flag modifications for BRK) to the stack.
*   `pullPcl(state: *CpuState, bus: *Bus) -> bool`: Pulls a byte from the stack into the low byte of the program counter.
*   `pullPch(state: *CpuState, bus: *Bus) -> bool`: Pulls a byte from the stack into the high byte of the program counter.
*   `pullStatus(state: *CpuState, bus: *Bus) -> bool`: Pulls a byte from the stack into the status register.
*   `setPcFromAddress(state: *CpuState, bus: *Bus) -> bool`: Sets the PC from the `effective_address` (for JSR).
*   `incrementPcAfterPull(state: *CpuState, bus: *Bus) -> bool`: Increments the PC after it has been restored (for RTS).
*   `fetchIrqVector(state: *CpuState, bus: *Bus) -> bool`: Fetches the address from the IRQ/BRK vector ($FFFE/$FFFF) and sets the PC.

### Step 2: Define New Microstep Sequences

In `src/cpu/addressing.zig`, we will define new `[]const MicrostepFn` sequences for each of the four opcodes.

*   **JSR (6 cycles):**
    1.  `fetchAbsLow` (Fetch low byte of target address)
    2.  `stackDummyRead` (Internal operation, no state change)
    3.  `pushPch` (Push current PC high byte)
    4.  `pushPcl` (Push current PC low byte)
    5.  `fetchAbsHighAndSetPc` (Fetch high byte & set PC to target address)
    6.  Instruction complete.

*   **RTS (6 cycles):**
    1.  `stackDummyRead`
    2.  `stackDummyRead`
    3.  `pullPcl` (Pull low byte of return address)
    4.  `pullPch` (Pull high byte of return address)
    5.  `incrementPcAfterPull` (Dummy read, then increment final PC)
    6.  Instruction complete.

*   **RTI (6 cycles):**
    1.  `stackDummyRead`
    2.  `stackDummyRead`
    3.  `pullStatus` (Pull status register)
    4.  `pullPcl` (Pull PC low byte)
    5.  `pullPch` (Pull PC high byte)
    6.  Instruction complete.

*   **BRK (7 cycles):**
    1.  `fetchOpcode` (Reads padding byte, increments PC)
    2.  `pushPch`
    3.  `pushPcl`
    4.  `pushStatus` (with B flag set)
    5.  `fetchIrqVectorLow`
    6.  `fetchIrqVectorHighAndSetPc`
    7.  Instruction complete.

### Step 3: Update Dispatch Table

In `src/cpu/dispatch.zig`, the entries for the four opcodes will be modified to use their new microstep sequences and a `nop` executor.

**Example for JSR (0x20):**
```zig
// In buildJumpOpcodes()
table[0x20] = .{ 
    .addressing_steps = &addressing.jsr_steps, // New sequence
    .execute_pure = Opcodes.nop, // No execution logic needed here
    .info = decode.OPCODE_TABLE[0x20],
}; 
```

### Step 4: Testing Strategy

Since these instructions are complex and stateful, they must be tested with integration-style tests that verify the state at each cycle.

1.  **Create New Test File:** `tests/cpu/opcodes/control_flow_test.zig`.
2.  **Write Cycle-by-Cycle Tests:**
    *   For each opcode, create a test that calls `Cpu.Logic.tick()` repeatedly.
    *   After each tick, assert the expected state of `PC`, `SP`, and relevant memory locations on the stack.
3.  **Test Cases:**
    *   **JSR/RTS:** Test that a `JSR` followed by an `RTS` returns control to the instruction immediately after the `JSR`.
    *   **Stack Integrity:** Verify that the stack pointer is correctly decremented and incremented.
    *   **Stack Values:** Verify that the correct PC and Status values are pushed to and pulled from the stack.
    *   **RTI:** Test that `RTI` correctly restores all processor flags from a value pushed by `BRK`.
    *   **BRK:** Test that `BRK` correctly pushes PC+2 and status, then jumps to the IRQ vector address.

## 4. Documentation

Upon completion, the following documents will be updated:

*   `docs/code-review/CPU.md`: Mark the opcodes as implemented.
*   `docs/code-review/STATUS.md`: Mark the task as complete.
*   `src/cpu/opcodes/mod.zig`: Add the new opcodes to the documentation.
