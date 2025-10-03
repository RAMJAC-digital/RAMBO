# 09 - Dead and Legacy Code Review

**Date:** 2025-10-03
**Status:** In Progress

## 1. Summary

As a project evolves, it's common for some code to become obsolete. Identifying and removing this dead and legacy code is an important part of maintaining a clean and understandable codebase.

This review identifies code that appears to be unused, legacy, or no longer relevant to the project's new hybrid architecture.

## 2. Actionable Items

### 2.1. Remove Old I/O Architecture Files

*   **Action:** The `src/io/Architecture.zig` and `src/io/Runtime.zig` files appear to be part of the old, fully asynchronous architecture. They should be removed and replaced with the new `libxev`-based I/O implementation.
*   **Rationale:** These files are no longer relevant to the project's new hybrid architecture. Removing them will reduce confusion and ensure that developers are working with the correct I/O model.
*   **Code References:**
    *   `src/io/Architecture.zig`
    *   `src/io/Runtime.zig`
*   **Status:** **TODO**.

### 2.2. Separate Debugging Tests from the Main Test Suite

*   **Action:** The `tests/cpu/dispatch_debug_test.zig`, `tests/cpu/rmw_debug_test.zig`, and `tests/cpu/cycle_trace_test.zig` files appear to be debugging helpers. They should be moved to a separate `tests/debug` directory and excluded from the main `zig test` run.
*   **Rationale:** Debugging tests are a valuable tool for development, but they should not be part of the main test suite. Separating them will make the test results cleaner and more focused on the core functionality of the emulator.
*   **Code References:**
    *   `tests/cpu/dispatch_debug_test.zig`
    *   `tests/cpu/rmw_debug_test.zig`
    *   `tests/cpu/cycle_trace_test.zig`
*   **Status:** **TODO**.

### 2.3. Conduct a Full Code Audit for Unused Code

*   **Action:** Perform a full audit of the codebase to identify any other unused functions, variables, or imports. The Zig compiler can help with this by issuing warnings for unused code.
*   **Rationale:** Removing unused code makes the codebase smaller, cleaner, and easier to maintain.
*   **Status:** **TODO**.
