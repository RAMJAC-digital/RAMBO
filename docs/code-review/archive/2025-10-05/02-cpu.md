# 02 - CPU Implementation Review

**Date:** 2025-10-05
**Status:** ✅ Good

## 1. Summary

The CPU implementation is robust, cycle-accurate, and well-tested. The State/Logic separation is correctly implemented, and the instruction set coverage, including unofficial opcodes, is excellent. The use of a `comptime`-generated dispatch table in `src/cpu/dispatch.zig` is efficient and clean.

However, there are several areas for improvement, primarily related to code organization and adherence to hardware-specific behavior for unstable opcodes.

## 2. Actionable Items

### 2.1. Refactor Massive Dispatch Function

-   **Status:** 🟡 **TODO**
-   **Issue:** The `buildDispatchTable` function in `src/cpu/dispatch.zig` is over 1,200 lines long. While it is `comptime`-generated and has no runtime cost, its size makes it difficult to read and maintain.
-   **Action:** Refactor the function by extracting opcode groups into smaller, focused helper functions (e.g., `buildLoadStoreOpcodes`, `buildArithmeticOpcodes`, `buildBranchOpcodes`).
-   **Rationale:** Improves readability and maintainability of a critical piece of the CPU core.
-   **Code Reference:** `src/cpu/dispatch.zig`

### 2.2. Consolidate `execution.zig` and `dispatch.zig`

-   **Status:** 🟡 **TODO**
-   **Issue:** The files `execution.zig` and `dispatch.zig` have significant conceptual overlap. `dispatch.zig` builds the table of function pointers, and `execution.zig` defines the micro-steps that are pointed to. This separation is not strictly necessary.
-   **Action:** Merge the contents of `execution.zig` into `dispatch.zig`. The micro-step functions can become file-local (`static inline`) functions within `dispatch.zig`, clarifying that they exist only to support the dispatch table's construction.
-   **Rationale:** Reduces file count and co-locates the dispatch table with the functions it dispatches to, improving code organization.
-   **Code References:** `src/cpu/dispatch.zig`, `src/cpu/execution.zig`

### 2.3. Unstable Opcode Configuration

-   **Status:** 🔴 **High Priority TODO**
-   **Issue:** The implementation of unstable unofficial opcodes (e.g., `XAA`, `LXA`, `SHA`) in `src/cpu/instructions/unofficial.zig` uses hardcoded "magic" constants (e.g., `const magic: u8 = 0xEE;`). The behavior of these opcodes varies between different 6502 revisions. To pass the full AccuracyCoin test suite, the emulator must be able to replicate the behavior of specific CPU revisions.
-   **Action:** Modify the implementation of these opcodes to be configurable based on the `CpuModel` struct in `src/config/Config.zig`. The magic constants and behavioral variations should be selected based on the configured `CpuVariant`.
-   **Rationale:** Essential for achieving 100% hardware accuracy and passing the AccuracyCoin test suite.
-   **Code References:** `src/cpu/instructions/unofficial.zig`, `src/config/Config.zig`

### 2.4. Refactor Shift/Rotate Instructions

-   **Status:** 🟡 **TODO**
-   **Issue:** The shift and rotate instructions (`ASL`, `LSR`, `ROL`, `ROR`) in `src/cpu/instructions/shifts.zig` contain duplicated logic for handling accumulator vs. memory addressing modes.
-   **Action:** Create `inline` helper functions to reduce code duplication. For example, a single `performShift(value: u8, op: ShiftOp) u8` helper could encapsulate the core logic, with the main instruction functions handling the memory/register access.
-   **Rationale:** Reduces code size, centralizes common logic, and improves maintainability.
-   **Code Reference:** `src/cpu/instructions/shifts.zig`
