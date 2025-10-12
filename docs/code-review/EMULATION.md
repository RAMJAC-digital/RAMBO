# Emulation Core Code Review

**Audit Date:** 2025-10-11
**Status:** Excellent

## 1. Overall Assessment

The emulation core, centered around `EmulationState` and `MasterClock`, is the heart of the new architecture and is exceptionally well-designed. The decision to use `EmulationState` as a direct data owner for all components (CPU, PPU, APU, Cartridge, etc.) and `MasterClock` as the single source of timing truth has resulted in a clean, deterministic, and highly maintainable system.

The core `tick()` loop correctly orchestrates the components with cycle-level precision, and the separation of concerns is clear. The system is free of complex pointer wiring and global state, making it robust and easy to reason about.

The issues identified are minor and relate to final consolidation and the removal of the last few legacy patterns.

## 2. Issues and Inconsistencies

- **Fragmented Sub-State:**
  - While `EmulationState` is a great aggregator, some of its state is still defined in separate files within `src/emulation/state/`. For example, `BusState.zig`, `Timing.zig`, and the peripheral states (`OamDma.zig`, etc.).
  - **Opportunity:** For a truly flat state structure, these smaller structs could be defined directly within `EmulationState.zig` or moved to a single `src/emulation/types.zig` file to reduce file fragmentation.

- **Legacy Test Helpers:**
  - `EmulationState` contains several test helpers (`testSetVBlank`, `tickCpuWithClock`) that are either deprecated or add a minor layer of abstraction over the core `tick()` loop. While useful for testing, they slightly pollute the main state definition.
  - The `syncDerivedSignals` function is explicitly marked as deprecated and should be removed.

- **`EmulationState.reset()` vs. `power_on()`:**
  - The presence of both `reset()` and `power_on()` is correct, as they model two different hardware events. However, their implementations are nearly identical. The distinction (PPU warm-up period) is handled by the `warmup_complete` flag, but the code could be slightly clarified to make the difference more explicit.

## 3. Dead Code and Legacy Artifacts

- **`src/emulation/helpers.zig`:** This file contains wrappers like `emulateFrame` and `emulateCpuCycles`. While useful for tests, this logic is high-level and might be better placed directly within the test files that use it, or in a dedicated `test/harness/helpers.zig` module, rather than in the core `src/emulation` source.
- **`src/emulation/state/Timing.zig`:** This file contains the `TimingStep` struct and `TimingHelpers`. This was part of the clock refactoring and is good, but it could be merged into `MasterClock.zig` to keep all timing-related definitions in one place.
- **`EmulationState.syncDerivedSignals()`:** This is explicitly deprecated and must be removed.

## 4. Actionable Development Plan

1.  **Consolidate State Definitions:**
    - Move the struct definitions from `src/emulation/state/BusState.zig`, `OamDma.zig`, `DmcDma.zig`, and `ControllerState.zig` directly into `EmulationState.zig` as private nested structs. This will make `EmulationState.zig` the single source of truth for the entire emulator's data layout.
    - Move the `TimingStep` and `TimingHelpers` from `src/emulation/state/Timing.zig` into `src/emulation/MasterClock.zig`.

2.  **Clean Up `EmulationState` API:**
    - Delete the deprecated `syncDerivedSignals` function.
    - Move the test-specific helpers (`tickCpuWithClock`, `emulateFrame`, `emulateCpuCycles`) from `EmulationState.zig` and `helpers.zig` into the `src/test/Harness.zig` file. The test harness is the appropriate place for such high-level test orchestration logic.

3.  **Clarify `reset()` vs. `power_on()`:**
    - Add comments to both `reset()` and `power_on()` in `EmulationState.zig` to clarify the difference, specifically mentioning that `power_on` involves a PPU warm-up period where I/O registers are ignored, while `reset` does not.
    - Consider creating a private `_internal_reset()` function that both methods can call to share the common reset logic, making the distinction even clearer.

4.  **Finalize Bus Routing Logic:**
    - The bus routing logic in `src/emulation/bus/routing.zig` is clean and efficient. Conduct a final review to ensure all memory-mapped registers are covered and that open bus behavior is correctly implemented for all unmapped reads.
    - The `test_ram` feature is great for testing but ensure it is fully disabled in release builds using a `comptime` check to prevent any performance impact.
