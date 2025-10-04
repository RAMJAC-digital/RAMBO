# 02 - CPU Implementation Review

**Date:** 2025-10-03
**Status:** In Progress

## 1. Summary

The CPU implementation is a cycle-accurate, state-machine-based design, which is a solid foundation for the emulator. The use of a dispatch table (`dispatch.zig`) is a good pattern for handling opcodes. The code is generally well-structured and follows Zig conventions.

However, there are several areas where the implementation can be improved to align better with the new hybrid architecture, enhance safety, and improve maintainability.

## 2. Actionable Items

### 2.1. Refactor CPU to a Pure State Machine

*   **Action:** The current `Cpu.zig` mixes state and logic. Refactor this into a pure `CpuState` struct (containing only data) and a separate set of pure functions that operate on that state. This aligns with the `final-hybrid-architecture.md` document.
*   **Rationale:** Separating state from logic makes the code more modular, easier to test, and enables features like save states by allowing the entire emulator state to be serialized.
*   **Code References:**
    *   `src/cpu/Cpu.zig`: The `Cpu` struct should be split into `CpuState` and `CpuLogic` (or similar).
*   **Status:** **DONE** (Completed in Phase 1, commit 1ceb301)
*   **Implementation:**
    *   Created `src/cpu/State.zig` with pure `CpuState` struct
    *   Created `src/cpu/Logic.zig` with pure functions
    *   Module re-exports: `Cpu.State.CpuState`, `Cpu.Logic`
    *   All 375 tests passing with new architecture

### 2.2. Simplify the Dispatch Mechanism

*   **Action:** The current dispatch mechanism in `Cpu.zig`'s `tick` function is a bit complex, with multiple `if (self.state == ...)` checks. This can be simplified by moving the state-specific logic into the `execution.zig` file and having a single `switch` statement in the main `tick` function.
*   **Rationale:** A simpler, more centralized dispatch mechanism is easier to understand and maintain.
*   **Code References:**
    *   `src/cpu/Cpu.zig`: The `tick` function.
    *   `src/cpu/execution.zig`: This file should contain the main `switch` statement for the CPU's execution state.
*   **Status:** **TODO**.

### 2.3. Unstable Opcode Configuration

*   **Action:** The `architecture-review-summary.md` and `final-hybrid-architecture.md` documents highlight that some unofficial opcodes have behavior that varies between CPU revisions. The implementation of these opcodes in `src/cpu/instructions/unofficial.zig` should be updated to be configurable based on the `HardwareConfig`.
*   **Rationale:** To achieve true hardware accuracy, the emulator must be able to replicate the behavior of specific CPU revisions. This is a requirement for passing the AccuracyCoin test suite.
*   **Code References:**
    *   `src/cpu/instructions/unofficial.zig`: The `xaa`, `lxa`, `sha`, `shx`, `shy`, and `tas` functions need to be made configurable.
    *   `src/config/Config.zig`: The `CpuConfig` struct should be extended to include configuration for unstable opcode behavior.
*   **Status:** **TODO**.

### 2.4. Remove `anytype` from `tick` and `reset`

*   **Action:** The `tick` and `reset` functions in `src/cpu/Cpu.zig` accept `bus: anytype`. This should be replaced with a concrete `*Bus` type.
*   **Rationale:** Using `anytype` reduces type safety and makes the code harder to analyze. The CPU should operate on a well-defined bus interface.
*   **Code References:**
    *   `src/cpu/Cpu.zig`: The `tick` and `reset` function signatures.
*   **Status:** **DEFERRED** (Strategic use of anytype in mapper methods)
*   **Resolution Notes:**
    *   CPU functions now use properly typed `*BusState` parameters
    *   Mapper methods strategically use `cart: anytype` to break circular dependencies
    *   This follows Zig stdlib patterns (e.g., ArrayList, HashMap) for duck-typed interfaces
    *   Comptime verification ensures type safety without runtime overhead
    *   See Phase 3 (commit 2dc78b8) for complete comptime generics implementation
*   **Rationale for Strategic anytype:**
    *   Prevents circular import dependencies (Bus → Cartridge → Mapper → Bus)
    *   Enables duck-typed polymorphism (idiomatic Zig pattern)
    *   Compile-time interface verification maintains type safety
    *   Zero runtime overhead compared to concrete types

### 2.5. Consolidate `execution.zig` and `dispatch.zig`

*   **Action:** The `execution.zig` and `dispatch.zig` files have a lot of conceptual overlap. Consider merging them into a single, more cohesive module that handles all aspects of instruction execution and dispatch.
*   **Rationale:** This would reduce the number of files and make the CPU's execution logic easier to follow.
*   **Status:** **TODO**.
