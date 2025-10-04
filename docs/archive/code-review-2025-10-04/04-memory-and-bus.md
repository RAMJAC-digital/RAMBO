# 04 - Memory and Bus Review

**Date:** 2025-10-03
**Status:** ✅ MOSTLY COMPLETE (2/4 items done)

## 1. Summary

The memory and bus implementation has been successfully refactored to follow the hybrid State/Logic architecture and uses comptime generics for zero-cost polymorphism. Key improvements completed:

- ✅ Bus refactored to State/Logic separation (Commit 1ceb301)
- ✅ VTables replaced with comptime duck typing (Commit 2dc78b8)
- ⏸️ Cartridge loading remains split (not a priority issue)
- ⏸️ Open bus model is functional (refinement deferred)

The bus is now deterministic, serializable, and integrates cleanly with the hybrid architecture.

## 2. Actionable Items

### 2.1. Refactor Bus to a Pure State Machine ✅ DONE

*   **Action:** ~~The `Bus` struct in `src/bus/Bus.zig` currently contains pointers to the `Cartridge` and `Ppu`, which it does not own. This should be refactored into a pure `BusState` struct that contains the bus's data (e.g., RAM, open bus value) and a separate set of pure functions that operate on this state. The `EmulationState` will be responsible for holding all the component states.~~
*   **Status:** **✅ COMPLETE** (Commit: 1ceb301)
*   **Implementation:**
    *   `src/bus/State.zig`: BusState with RAM, open bus tracking, optional pointers
    *   `src/bus/Logic.zig`: Pure functions (read, write, read16, read16Bug)
    *   `src/bus/Bus.zig`: Module re-exports with clean API
*   **Result:** Bus is now a deterministic state machine, fully serializable

### 2.2. Replace VTable with Comptime Generics ✅ DONE

*   **Action:** ~~The `Mapper` interface in `src/cartridge/Mapper.zig` and the `ChrProvider` in `src/memory/ChrProvider.zig` use a vtable for polymorphism. While this works, a more idiomatic and safer approach in Zig is to use comptime generics (duck typing).~~
*   **Status:** **✅ COMPLETE** (Commit: 2dc78b8)
*   **Implementation:**
    *   ❌ Deleted: `src/cartridge/Mapper.zig` (VTable removed)
    *   ❌ Deleted: `src/memory/ChrProvider.zig` (VTable removed)
    *   ✅ `Cartridge(MapperType)` generic type factory
    *   ✅ Duck-typed mapper methods with `anytype` parameters
    *   ✅ Zero runtime overhead - direct dispatch, fully inlined
*   **Result:** Compile-time polymorphism with zero VTable overhead

### 2.3. Simplify Cartridge Loading

*   **Action:** The cartridge loading logic is currently split between `src/cartridge/Cartridge.zig` and `src/cartridge/loader.zig`. This can be simplified by consolidating the loading logic into a single file.
*   **Rationale:** A single, cohesive cartridge loading module will be easier to understand and maintain.
*   **Code References:**
    *   `src/cartridge/Cartridge.zig`
    *   `src/cartridge/loader.zig`
*   **Status:** **TODO**.

### 2.4. Implement a Proper Open Bus Model

*   **Action:** The current open bus model in `src/bus/Bus.zig` is a good start, but it can be made more accurate. The open bus behavior of the NES is complex and depends on which component last drove the bus. The implementation should be updated to more accurately model this behavior.
*   **Rationale:** Accurate open bus behavior is required for some games and is a key part of cycle-accurate emulation.
*   **Code References:**
    *   `src/bus/Bus.zig`: The `OpenBus` struct and its usage.
*   **Status:** **TODO**.
