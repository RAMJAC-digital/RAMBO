# 05 - Async and I/O Review

**Date:** 2025-10-05
**Status:** ✅ Good

## 1. Summary

The project has successfully transitioned from its old, obsolete I/O architecture to a new, clean design centered around the `mailboxes` system and `libxev`. This new architecture is sound, thread-safe, and aligns with modern best practices for multi-threaded applications.

The `src/io/` directory is now a placeholder, and the core communication logic resides in `src/mailboxes/`. The `main.zig` file demonstrates a proof-of-concept integration with `libxev` for timer-driven emulation, which is a solid foundation for the full implementation.

## 2. Mailbox Architecture

-   **Status:** ✅ **Excellent**
-   **Analysis:** The `src/mailboxes/` implementation provides a clean and effective way to handle inter-thread communication:
    -   **`FrameMailbox`:** A classic double-buffer (or mailbox swap) pattern for video frames. This is a simple, efficient, and lock-free (for the reader/writer, with a mutex only on the swap) way to pass completed frames from the emulation thread to the render thread.
    -   **`ConfigMailbox`:** A single-value mailbox for low-frequency commands like pause, reset, etc. The use of a mutex is appropriate here, as these are not on the hot path.
    -   **`WaylandEventMailbox`:** A double-buffered queue for UI events, which is a standard and robust pattern for GUI applications.
-   **Conclusion:** The mailbox system is well-designed and correctly implemented.

## 3. `libxev` Integration

-   **Status:** ✅ **Good (Proof of Concept)**
-   **Analysis:** The `main.zig` file demonstrates a correct, timer-driven emulation loop using `libxev`. The `emulationThreadFn` spawns a `libxev` loop and uses a periodic timer to call `emulateFrame`, ensuring that the emulation runs at a consistent speed (e.g., 60 FPS for NTSC).
-   **Observations:** This is currently a proof of concept. The main thread simply waits, and there is no actual rendering or UI thread yet. However, the foundation is solid.

## 4. Actionable Items

### 4.1. Complete `libxev` Integration

-   **Status:** 🟡 **TODO**
-   **Issue:** The current `libxev` integration in `main.zig` is a placeholder to demonstrate the timer-driven emulation loop. A full implementation requires a UI/render thread and proper event handling.
-   **Action:** As part of the video subsystem implementation (the next major project phase), the following need to be implemented:
    1.  **Render Thread:** A dedicated thread for rendering the frames from the `FrameMailbox` to the screen (e.g., using Wayland and Vulkan as planned).
    2.  **UI Event Handling:** The main thread should process events from the `WaylandEventMailbox` and dispatch them appropriately (e.g., handling keyboard input, window close events).
    3.  **File I/O:** Use `libxev`'s async file I/O for loading ROMs and save states to avoid blocking the main thread.
-   **Rationale:** Completing the `libxev` integration is the core of the video and I/O subsystem and is the next major step for the project.
-   **Code Reference:** `src/main.zig`

### 4.2. Implement Real-Time Safe Allocator

-   **Status:** 🔴 **High Priority TODO**
-   **Issue:** The original code review (`05-async-and-io.md` from the archive) mentioned the need for a real-time safe allocator. While the core emulation loop currently performs no allocations, this is a critical safety measure to enforce as the project grows.
-   **Action:** Implement an `RtAllocator` that pre-allocates all necessary memory at startup. The emulation thread should then be given this allocator, and all its functions should be audited to ensure they only use this pre-allocated memory. Any attempt to use a general-purpose allocator in the RT loop should be a compile error.
-   **Rationale:** Guarantees that the real-time emulation thread will never be stalled by unpredictable memory allocation, which is essential for preventing audio stuttering and maintaining smooth emulation.
