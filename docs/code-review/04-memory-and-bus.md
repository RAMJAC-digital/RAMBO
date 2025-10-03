# 04 - Memory and Bus Review

**Date:** 2025-10-03
**Status:** In Progress

## 1. Summary

The memory and bus implementation is well-structured and correctly handles many of the NES's memory-mapping intricacies, including RAM mirroring and the cartridge/mapper system. The use of a vtable for mappers is a good, idiomatic Zig pattern for polymorphism.

However, the current implementation can be improved by refactoring it to be a pure state machine, which will make it more testable and align it with the new hybrid architecture. Additionally, there are opportunities to improve safety and simplify the design.

## 2. Actionable Items

### 2.1. Refactor Bus to a Pure State Machine

*   **Action:** The `Bus` struct in `src/bus/Bus.zig` currently contains pointers to the `Cartridge` and `Ppu`, which it does not own. This should be refactored into a pure `BusState` struct that contains the bus's data (e.g., RAM, open bus value) and a separate set of pure functions that operate on this state. The `EmulationState` will be responsible for holding all the component states.
*   **Rationale:** This change is fundamental to the new hybrid architecture. It will make the bus's behavior deterministic and allow the entire emulator state to be serialized for save states.
*   **Code References:**
    *   `src/bus/Bus.zig`: The `Bus` struct.
*   **Status:** **TODO**.

### 2.2. Replace VTable with Comptime Generics

*   **Action:** The `Mapper` interface in `src/cartridge/Mapper.zig` and the `ChrProvider` in `src/memory/ChrProvider.zig` use a vtable for polymorphism. While this works, a more idiomatic and safer approach in Zig is to use comptime generics (duck typing).
*   **Rationale:** Comptime generics provide compile-time polymorphism with no runtime overhead. This is safer than vtables because the compiler can verify that the types have the required functions at compile time, eliminating the risk of runtime errors due to incorrect vtable pointers.
*   **Code References:**
    *   `src/cartridge/Mapper.zig`: The `Mapper` struct.
    *   `src/memory/ChrProvider.zig`: The `ChrProvider` struct.
*   **Status:** **TODO**.

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
