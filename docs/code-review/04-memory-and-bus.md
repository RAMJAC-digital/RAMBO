# 04 - Memory and Bus Review

**Date:** 2025-10-05
**Status:** ✅ Good

## 1. Summary

The memory bus implementation is clean, efficient, and correctly follows the project's core architectural patterns. The State/Logic separation is well-executed, and the use of `comptime` generics for the cartridge interface is a major success.

The bus correctly handles RAM mirroring, PPU register mirroring, and ROM write protection. The open bus model is functional, though it could be refined for greater accuracy.

## 2. Actionable Items

### 2.1. Simplify Cartridge Loading

-   **Status:** 🟡 **TODO**
-   **Issue:** The cartridge loading logic is currently split between `src/cartridge/Cartridge.zig` (which handles parsing the in-memory data) and `src/cartridge/loader.zig` (which handles reading the file from disk). This separation is minor but adds a small amount of cognitive overhead.
-   **Action:** Consolidate the file-reading logic from `loader.zig` into `Cartridge.zig` as a static `loadFromFile` function. This would make `Cartridge.zig` the single source of truth for all cartridge creation.
-   **Rationale:** A single, cohesive cartridge loading module is easier to understand and maintain.
-   **Code References:** `src/cartridge/Cartridge.zig`, `src/cartridge/loader.zig`

### 2.2. Implement a More Accurate Open Bus Model

-   **Status:** 🟡 **TODO**
-   **Issue:** The current open bus model in `src/bus/State.zig` and `Logic.zig` is a good start, where the bus holds the last value read or written. However, the true behavior of the NES open bus is more complex. The value on the bus can be affected by which component last drove it, and some registers (like the PPU's) can have their own internal latches that behave differently.
-   **Action:** Research and implement a more accurate open bus model. This may involve tracking the last driving component or having different open bus behaviors for different memory regions. The NESdev Wiki and forums are good resources for this.
-   **Rationale:** Accurate open bus behavior is required for some edge-case scenarios in games and is a key part of achieving 100% cycle-accuracy.
-   **Code References:** `src/bus/State.zig`, `src/bus/Logic.zig`

### 2.3. Replace `anytype` in Bus Logic

-   **Status:** 🔴 **High Priority TODO**
-   **Issue:** The `read` and `write` functions in `src/bus/Logic.zig` still use `anytype` for the `cartridge` and `ppu` parameters. While this was a pragmatic choice during the `comptime` generics refactoring, it reduces type safety and makes the code harder for tools (like IDEs) to analyze.
-   **Action:** Replace `anytype` with concrete types. The `cartridge` parameter can be made generic (`cartridge: anytype`), but the `ppu` parameter should be a concrete `*PpuState`.
    ```zig
    // Change this:
    pub fn read(state: *BusState, cartridge: anytype, ppu: anytype, address: u16) u8

    // To this:
    pub fn read(state: *BusState, cartridge: anytype, ppu: *PpuState, address: u16) u8
    ```
-   **Rationale:** Improves type safety, enables better static analysis, and enhances IDE support for code completion and analysis.
-   **Code Reference:** `src/bus/Logic.zig`
