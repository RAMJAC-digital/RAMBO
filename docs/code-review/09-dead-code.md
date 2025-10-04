# 09 - Dead and Legacy Code Review

**Date:** 2025-10-05
**Status:** ✅ Good

## 1. Summary

The project is remarkably clean, with very little dead or legacy code. The previous major refactoring phases successfully removed the old asynchronous I/O architecture (`src/io/Architecture.zig` and `src/io/Runtime.zig`), which was the primary source of legacy code.

This review identifies a few remaining areas for minor cleanup, mostly related to placeholder directories and the organization of tests.

## 2. Actionable Items

### 2.1. Add READMEs to Placeholder Directories

-   **Status:** 🟡 **TODO**
-   **Issue:** The `src/apu/`, `src/io/`, and `src/mappers/` directories are empty placeholders for future work. While this is fine, they provide no context for new developers.
-   **Action:** Add a `README.md` file to each of these directories. The README should briefly explain the directory's purpose and note that the implementation is pending a future development phase (e.g., "This directory will contain the APU (Audio Processing Unit) implementation, scheduled for Phase 9.").
-   **Rationale:** Improves project clarity and provides a clear roadmap for new developers browsing the source tree.
-   **Code References:** `src/apu/`, `src/io/`, `src/mappers/`

### 2.2. Remove Unused Type Aliases from `root.zig`

-   **Status:** 🟡 **TODO**
-   **Issue:** The main library file, `src/root.zig`, exports several `*Type` aliases (`CpuType`, `BusType`, `PpuType`, `CartridgeType`) that are redundant. The component modules themselves (`Cpu`, `Bus`, etc.) are already exported, and their `State` structs can be accessed directly (e.g., `rambo.cpu.State`).
-   **Action:** Remove the following lines from `src/root.zig`:
    ```zig
    pub const CpuType = Cpu.State.CpuState;
    pub const BusType = Bus.State.BusState;
    pub const CartridgeType = Cartridge.NromCart;
    pub const PpuType = Ppu.State.PpuState;
    ```
    Then, update all test files that use these aliases to use the full path (e.g., change `CpuType` to `rambo.cpu.State`).
-   **Rationale:** Simplifies the public API, removes redundancy, and encourages a more explicit and clear way of referencing component state types.
-   **Code Reference:** `src/root.zig`, `tests/**/*.zig`

### 2.3. Remove `PpuLogic` from Public API

-   **Status:** 🟡 **TODO**
-   **Issue:** The internal `PpuLogic` module is exposed in the public API via `root.zig`. This module contains the pure functions that operate on `PpuState` and is only needed for unit testing, not for public consumption by users of the RAMBO library.
-   **Action:** Remove the line `pub const PpuLogic = @import("ppu/Logic.zig");` from `src/root.zig`.
-   **Rationale:** Encapsulates internal implementation details and cleans up the public API of the library.
-   **Code Reference:** `src/root.zig`
