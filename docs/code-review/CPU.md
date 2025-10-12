# CPU Code Review

**Audit Date:** 2025-10-11
**Status:** Excellent

## 1. Overall Assessment

The CPU implementation is the most mature and well-architected component in the RAMBO codebase. It strictly and correctly adheres to the State/Logic separation pattern, with pure functions for opcodes and a clean microstep-based execution engine. The use of a `DispatchEntry` struct in `dispatch.zig` to link opcodes to their metadata and pure function implementations is clean and efficient.

The code is highly testable, accurate, and demonstrates a deep understanding of 6502 hardware behavior, including unofficial opcodes and timing quirks. The identified issues are minor and relate to potential simplification and clarification rather than functional correctness.

## 2. Issues and Inconsistencies

- **`dispatch.zig` Complexity:**
  - The `buildDispatchTable()` function in `src/cpu/dispatch.zig` is large and contains a lot of boilerplate for assigning opcodes to their functions. While the use of category-specific helper functions is good, the sheer volume of assignments makes it hard to read.
  - **Opportunity:** This could be simplified using a `comptime` loop over a more data-driven structure that maps opcodes directly to their function and metadata, reducing the line count significantly.

- **Legacy `CpuLogic.reset()` Function:**
  - `src/cpu/Logic.zig` contains a `reset()` function that is noted as "not used in new architecture." This is a legacy artifact from before the `EmulationState.reset()` method took over this responsibility. It should be removed.

- **RMW Dummy Write Clarity:**
  - The Read-Modify-Write (RMW) instruction sequence involves a "dummy write" of the original value before the modified value is written. This is critical for hardware accuracy. While the microsteps in `src/emulation/cpu/execution.zig` appear to implement this correctly, the logic could be more explicitly commented to clarify *why* this seemingly redundant write is necessary.

- **`variants.zig` Unofficial Opcode Duplication:**
  - The `Cpu` type factory in `src/cpu/variants.zig` re-implements many unofficial opcodes that are not variant-dependent (e.g., `lax`, `sax`, `slo`). Only the opcodes that truly differ between CPU revisions (like `lxa` and `xaa` with their magic constants) should be in this file. The rest should live in `src/cpu/opcodes/unofficial.zig` to avoid duplication.

## 3. Dead Code and Legacy Artifacts

- **`src/cpu/Logic.zig` -> `reset()`:** This function is explicitly marked as unused and should be deleted.
- **`src/cpu/dispatch.zig` -> `build*Opcodes` helpers:** While not dead code, these functions are boilerplate that could be replaced by a more data-driven, comptime approach, making the file much smaller and easier to maintain.

## 4. Actionable Development Plan

1.  **Refactor `variants.zig`:**
    - Move all non-variant-specific unofficial opcode implementations from `src/cpu/variants.zig` to `src/cpu/opcodes/unofficial.zig`.
    - Keep only the truly variant-dependent opcodes (`lxa`, `xaa`) inside the `Cpu()` type factory. This will centralize the opcode logic and make the variant-specific differences explicit.

2.  **Simplify `dispatch.zig`:**
    - **(Optional, Low Priority)** Explore a `comptime`-based, data-driven approach to building the dispatch table. This would involve creating a static array of structs that maps an opcode byte to its function pointer and metadata, then using a `comptime` loop to generate the final `DISPATCH_TABLE`. This would reduce the file size from ~1300 lines to a few hundred.

3.  **Remove Legacy `CpuLogic.reset()`:**
    - Delete the `reset` function from `src/cpu/Logic.zig` to eliminate the final piece of legacy API from the CPU module.

4.  **Add Explanatory Comments for RMW Dummy Writes:**
    - In `src/emulation/cpu/microsteps.zig`, add a brief comment to the `rmwDummyWrite` function explaining its purpose: to emulate the hardware behavior where the original value is written back to the bus before the modified value, which is critical for cycle-accurate side effects on memory-mapped I/O.

5.  **Final Review of Unofficial Opcodes:**
    - Conduct a final pass over the implementations in `src/cpu/opcodes/unofficial.zig` and `src/cpu/variants.zig`, comparing them against detailed hardware references (like Visual6502) to ensure the cycle-by-cycle behavior and flag manipulations are 100% accurate.
