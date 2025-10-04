# 05 - Async and I/O Review

**Date:** 2025-10-03
**Status:** In Progress

## 1. Summary

The I/O architecture defined in `src/io/Architecture.zig` and `src/io/Runtime.zig` is a well-thought-out plan for a modern, multi-threaded emulator. The use of `libxev` for asynchronous I/O, lock-free SPSC queues for communication, and a clear separation of concerns between the real-time (RT) and I/O threads is an excellent design.

However, the implementation is currently incomplete. This review provides actionable recommendations for completing the async I/O layer and ensuring it is robust, efficient, and well-integrated with the rest of the emulator.

## 2. Actionable Items

### 2.1. Complete `libxev` Integration

*   **Action:** The current code has placeholders for `libxev` integration. This needs to be fully implemented. This includes creating the `libxev` event loop, setting up timers for frame pacing, and using `libxev`'s async file I/O for loading ROMs.
*   **Rationale:** `libxev` is the cornerstone of the new I/O architecture. Its proper integration is essential for achieving a responsive, non-blocking user experience.
*   **Code References:**
    *   `src/io/Runtime.zig`: The `ioThreadMain` function and the `IoContext` struct.
*   **Status:** **TODO**.

### 2.2. Implement the Full Triple-Buffering Logic

*   **Action:** The `TripleBuffer` struct in `src/io/Architecture.zig` is a good start, but the logic for managing the three buffers (write, ready, display) needs to be fully implemented and tested. This includes the logic for the render thread to acquire the ready buffer and release the display buffer.
*   **Rationale:** A correct triple-buffering implementation is crucial for tear-free rendering and smooth frame pacing.
*   **Code References:**
    *   `src/io/Architecture.zig`: The `TripleBuffer` struct.
*   **Status:** **TODO**.

### 2.3. Implement the Command Queue

*   **Action:** The `CommandQueue` is currently implemented with a mutex. While this is acceptable for infrequent commands, a lock-free MPSC (Multiple Producer, Single Consumer) queue would be more performant and avoid potential priority inversion issues.
*   **Rationale:** A lock-free queue will ensure that the I/O threads can send commands to the RT thread without blocking, which is important for maintaining the RT thread's real-time guarantees.
*   **Code References:**
    *   `src/io/Architecture.zig`: The `CommandQueue` struct.
*   **Status:** **TODO**.

### 2.4. Thread Priorities and Affinities

*   **Action:** The `Runtime.zig` file includes logic for setting thread priorities and affinities. This needs to be thoroughly tested on all target platforms (Linux, Windows, macOS) to ensure it works as expected.
*   **Rationale:** Correctly setting thread priorities is critical for ensuring that the RT thread gets the CPU time it needs to run the emulation without stuttering.
*   **Code References:**
    *   `src/io/Runtime.zig`: The `configureRtThread` function.
*   **Status:** **TODO**.

### 2.5. Implement a Real-Time Safe Allocator

*   **Action:** The `RtAllocator` in `src/io/Architecture.zig` is a placeholder. A real implementation is needed that pre-allocates all necessary memory at startup and provides a safe way for the RT thread to access it without performing any runtime allocations.
*   **Rationale:** The RT thread must never allocate memory at runtime, as this can lead to unpredictable latency and break real-time guarantees.
*   **Code References:**
    *   `src/io/Architecture.zig`: The `RtAllocator` struct.
*   **Status:** **TODO**.
