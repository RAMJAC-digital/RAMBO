# VBlank Logic Refactor Session — 2025-10-15

## Objective
Refactor the PPU VBlank and NMI logic to fix a critical bug preventing commercial ROMs like Super Mario Bros. from rendering. The goal was to enforce a clear separation of concerns, eliminate stateful side effects, and establish a deterministic, hardware-accurate update order.

## Problem Analysis
The previous implementation had a tightly-coupled and complex architecture for managing the VBlank flag:

1.  **Stateful Side Effects:** A CPU read of `$2002` triggered a deep call chain (`EmulationState` -> `BusRouting` -> `PpuLogic` -> `registers.zig`) that directly mutated the `VBlankLedger` state. This made the flow of data difficult to trace and debug.
2.  **Lack of Central Orchestration:** State changes to the `VBlankLedger` were initiated from multiple, disconnected parts of the codebase (the PPU timing tick and the CPU read handler), leading to race conditions and bugs.
3.  **The Bug:** The game's initialization loop continuously reads `$2002`, waiting for the VBlank flag to be set and then cleared. The complex, stateful logic failed to clear the flag correctly under these rapid polling conditions, causing the game to loop infinitely and never enable rendering.

## Architectural Changes Implemented

To solve this, the entire VBlank mechanism was refactored into a clean, centrally-orchestrated model.

### 1. `VBlankLedger.zig` Became a Pure Data Struct
The ledger was simplified to only store timestamps of critical events. All complex logic was removed.

```zig
// src/emulation/VBlankLedger.zig
pub const VBlankLedger = struct {
    last_set_cycle: u64 = 0,
    last_clear_cycle: u64 = 0,
    last_read_cycle: u64 = 0,
    // ... reset function ...
};
```

### 2. `EmulationState.zig` as the Single Source of Truth
`EmulationState` is now the **only** module that can modify the `VBlankLedger`.

*   **PPU Tick:** When the PPU's `tick()` function signals a VBlank event (`nmi_signal` or `vblank_clear`), `EmulationState` updates the appropriate timestamp (`last_set_cycle` or `last_clear_cycle`).
*   **CPU Read:** The main `busRead` logic was moved directly into `EmulationState`. When it detects a read from the PPU register range, it calls the PPU's `readRegister` function. If that function signals that `$2002` was read, `EmulationState` updates the `last_read_cycle` timestamp itself.

### 3. PPU Logic Became Pure Functions

*   **`ppu/Logic.zig`:** The `tick()` function no longer mutates any external state. It simply returns event flags to `EmulationState`.
*   **`ppu/logic/registers.zig`:** The `readRegister()` function is now a pure consumer of state. It takes the `VBlankLedger` by value (`const`), computes the VBlank status based on the timestamps, and returns a `PpuReadResult` struct containing the value and a flag indicating if `$2002` was read. It no longer has any mutating side effects.

```zig
// New logic in readRegister for $2002
const vblank_active = (vblank_ledger.last_set_cycle > vblank_ledger.last_clear_cycle) and
                      (vblank_ledger.last_set_cycle > vblank_ledger.last_read_cycle);
```

## Justification

This new architecture provides several key benefits:

*   **Determinism:** All state changes are now explicitly ordered and controlled by the main `tick()` loop in `EmulationState`. There are no hidden side effects.
*   **Separation of Concerns:** Each module has a single responsibility:
    *   `EmulationState`: Orchestrates and mutates state.
    *   `PPU Tick Logic`: Produces timing events.
    *   `PPU Register Logic`: Consumes state to produce a value.
*   **Debuggability:** The data flow is now unidirectional and easy to trace, making it significantly easier to reason about the system's behavior and debug future issues.

## Expected Outcome
This refactoring is expected to resolve the infinite loop in Super Mario Bros. and other affected ROMs, allowing them to complete their initialization and enable rendering. The next step is to run the verification tests.

## Files Modified
- `src/emulation/VBlankLedger.zig` (rewritten)
- `src/ppu/logic/registers.zig` (refactored)
- `src/emulation/State.zig` (refactored)
- `src/ppu/Logic.zig` (signature updated)
