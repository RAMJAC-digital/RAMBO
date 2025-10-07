# Async & I/O Status - 2025-10-05

**Status:** ✅ **Good Foundation** (Phase 6 Implementation)

> **📘 Phase 8 Architecture Update:**
> This document reviews the Phase 6 implementation. For the authoritative Phase 8 plan:
> - **[`../COMPLETE-ARCHITECTURE-AND-PLAN.md`](../COMPLETE-ARCHITECTURE-AND-PLAN.md)** - Full 3-thread architecture
> - **[`../MAILBOX-ARCHITECTURE.md`](../MAILBOX-ARCHITECTURE.md)** - All 8 mailboxes (includes XdgWindowEventMailbox and XdgInputEventMailbox)

## 1. Summary

The project has successfully transitioned to a clean, modern I/O architecture centered around the `mailboxes` system for inter-thread communication and `libxev` for event handling. This design is sound, thread-safe, and provides a solid foundation for implementing the video, audio, and input subsystems.

The `main.zig` file demonstrates a correct, timer-driven emulation loop using `libxev`, which is the proper way to drive a cycle-accurate emulator at a consistent speed.

## 2. Actionable Items

### 2.1. Complete `libxev` Integration (Future Work)

-   **Status:** 🟡 **TODO**
-   **Issue:** The current `libxev` integration is a proof-of-concept. A full implementation requires a UI/render thread and proper event handling.
-   **Action:** As part of the video subsystem implementation (the next major project phase after the CPU test restoration), the following need to be implemented:
    1.  **Render Thread:** A dedicated thread for rendering the frames from the `FrameMailbox` to the screen (e.g., using Wayland and Vulkan as planned).
    2.  **UI Event Handling:** The main thread should process events from window/input mailboxes and dispatch them appropriately (e.g., handling keyboard input for controllers, window close events). **Phase 8 Note:** `WaylandEventMailbox` is being split into `XdgWindowEventMailbox` and `XdgInputEventMailbox` - see MAILBOX-ARCHITECTURE.md.
    3.  **File I/O:** Use `libxev`'s async file I/O for loading ROMs and save states to avoid blocking the main thread.
-   **Rationale:** This is the core of the video and I/O subsystem and is the next major step for the project **after** the current CPU correctness issues are fully resolved.

### 2.2. Implement Real-Time Safe Allocator

-   **Status:** 🟡 **TODO**
-   **Issue:** While the core emulation loop currently performs no allocations, this is not enforced by the type system. A real-time safe allocator is needed to guarantee that the emulation thread will never be stalled by unpredictable memory allocation from a general-purpose allocator.
-   **Action:** Implement an `RtAllocator` that pre-allocates all necessary memory at startup. The emulation thread should then be given this allocator, and all its functions should be audited to ensure they only use this pre-allocated memory. Any attempt to use a general-purpose allocator in the RT loop should be a compile error.
-   **Rationale:** Guarantees that the real-time emulation thread will never stall, which is essential for preventing audio stuttering and maintaining smooth emulation.
