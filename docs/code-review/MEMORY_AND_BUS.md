# Memory and Bus Status - 2025-10-05

**Status:** 🟡 **Good, but with a high-priority type safety issue.**

## 1. Summary

The memory bus implementation is clean, efficient, and correctly follows the project's core architectural patterns. The bus correctly handles RAM mirroring, PPU register mirroring, and ROM access.

The use of `comptime` generics for the cartridge mapper interface is a success, providing a zero-cost abstraction for handling different mapper types.

## 2. Actionable Items

### 2.1. Replace `anytype` in Bus Logic (High Priority)

-   **Status:** 🔴 **TODO**
-   **Issue:** The `read` and `write` functions in `src/bus/Logic.zig` still use `anytype` for the `ppu` parameter. This is a holdover from earlier refactoring and reduces type safety, as the PPU does not have a generic interface like the cartridge does.
-   **Action:** Replace the `ppu: anytype` parameter with a concrete `*PpuState` pointer. This will improve type safety and allow the compiler and IDEs to perform better static analysis.
    ```zig
    // Change this:
    pub fn read(state: *BusState, cartridge: anytype, ppu: anytype, address: u16) u8

    // To this:
    pub fn read(state: *BusState, cartridge: anytype, ppu: *Ppu.State, address: u16) u8
    ```
-   **Rationale:** Improves type safety, enables better static analysis, and enhances IDE support for code completion and analysis.

### 2.2. Implement a More Accurate Open Bus Model

-   **Status:** 🟡 **TODO**
-   **Issue:** The current open bus model is a good start but does not fully replicate the complex behavior of the real NES hardware, where the floating value can be affected by which component last drove the bus.
-   **Action:** Research and implement a more accurate open bus model. This may involve tracking the last driving component or having different open bus behaviors for different memory regions.
-   **Rationale:** Accurate open bus behavior is required for some edge-case scenarios in games and is a key part of achieving 100% cycle-accuracy.

### 2.3. Consolidate Cartridge Loading

-   **Status:** 🟡 **TODO**
-   **Issue:** The cartridge loading logic is split between `src/cartridge/Cartridge.zig` and `src/cartridge/loader.zig`.
-   **Action:** Consolidate the file-reading logic from `loader.zig` into `Cartridge.zig` as a static `loadFromFile` function.
-   **Rationale:** A single, cohesive cartridge loading module is easier to understand and maintain.
