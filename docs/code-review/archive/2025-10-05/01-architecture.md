# 01 - Architecture Review

**Date:** 2025-10-05
**Status:** ✅ Verified

## 1. Summary

The project's hybrid architecture has been successfully implemented and verified. The core principle of separating the synchronous emulation core from the asynchronous I/O layer is consistently followed.

-   **Synchronous Core:** The `EmulationState` struct and its `tick()` function correctly orchestrate the CPU, PPU, and Bus components in a deterministic, single-threaded loop. This design is RT-safe and suitable for cycle-accurate emulation.
-   **Asynchronous I/O:** The new `mailboxes` system provides a sound, thread-safe foundation for handling video, input, and configuration updates. The use of `libxev` in `main.zig` demonstrates the intended timer-driven approach, though it is not yet fully integrated with a UI frontend.

## 2. State/Logic Separation Pattern

-   **Status:** ✅ **Excellent**
-   **Analysis:** The State/Logic separation pattern is the cornerstone of the architecture and has been applied rigorously to all core components:
    -   `src/cpu/` (State.zig, Logic.zig)
    -   `src/ppu/` (State.zig, Logic.zig)
    -   `src/bus/` (State.zig, Logic.zig)
-   **Benefits Realized:**
    -   **Determinism:** The emulation core is a pure state machine (`next_state = f(current_state)`), making execution predictable and reproducible.
    -   **Testability:** The separation allows for isolated unit testing of logic functions with mock state.
    -   **Serialization:** The pure data `State` structs enable the robust snapshot system, as the entire emulator state can be saved and loaded easily.

## 3. `comptime` Polymorphism

-   **Status:** ✅ **Excellent**
-   **Analysis:** The project has successfully replaced runtime V-tables with `comptime` duck typing for the cartridge mapper interface. The `Cartridge(MapperType)` generic function in `src/cartridge/Cartridge.zig` is a clean and idiomatic Zig implementation.
-   **Benefits Realized:**
    -   **Zero-Cost Abstraction:** Mapper method calls are resolved at compile time, resulting in direct function calls with no runtime overhead from V-table lookups.
    -   **Type Safety:** The compiler enforces the mapper interface at compile time, preventing a class of runtime errors.

## 4. Threading and Communication

-   **Status:** ✅ **Good**
-   **Analysis:** The `src/mailboxes/` directory introduces a clean, modern approach to inter-thread communication, replacing the obsolete `src/io/` architecture.
    -   `FrameMailbox`: A standard double-buffer pattern for passing video frames from the emulation thread to the (future) render thread.
    -   `ConfigMailbox`: A single-value mailbox for sending commands like `pause`, `reset`, etc., to the emulation thread.
    -   `WaylandEventMailbox`: A double-buffered queue for UI events.
-   **Observations:** The use of `std.Thread.Mutex` is appropriate for the non-hot-path nature of these mailboxes (swapping buffers or updating config happens infrequently).

## 5. Actionable Items

None. The architecture is sound and well-implemented. All previous architectural action items have been successfully addressed.
