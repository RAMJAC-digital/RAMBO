# PPU Code Review

**Audit Date:** 2025-10-11
**Status:** Very Good

## 1. Overall Assessment

The PPU implementation is robust, well-structured, and closely follows the project's State/Logic separation architecture. The logic is correctly broken down into sub-modules for memory, registers, scrolling, background, and sprites, making it easy to navigate and understand. The use of a `VBlankLedger` to handle the NMI race condition is a sophisticated and correct solution to a common and difficult problem in NES emulation.

The PPU appears to be one of the most complete and modern components in the codebase. The identified issues are minor and focus on potential simplifications and final cleanups rather than significant architectural flaws.

## 2. Issues and Inconsistencies

- **Redundant `Ppu.zig` Facade:**
  - The file `src/emulation/Ppu.zig` acts as a facade for the PPU's `tick` function. This adds an unnecessary layer of indirection. `EmulationState.tick()` could call the core `PpuLogic.tick()` function directly.
  - The `TickFlags` struct is defined in `emulation/Ppu.zig` but is conceptually part of the PPU's output. It would be better placed within the PPU module itself.

- **VBlank Flag Management Cleanup:**
  - The `PpuStatus` struct in `src/ppu/State.zig` still contains a `_reserved: bool` field (bit 7) that was previously the `vblank` flag. The comment correctly notes its removal, but the field itself can be removed to finalize the migration to the `VBlankLedger`.
  - The `EmulationState` contains several deprecated test helpers (`testSetVBlank`, `testClearVBlank`) that manually manipulate VBlank state. The comments indicate they should be removed, and this should be done to prevent their use in new tests.

- **`ppu_a12_state` Ownership:**
  - The `ppu_a12_state` flag, used for MMC3 IRQ timing, is currently owned by `EmulationState`. While it is related to the PPU address bus, its state is tightly coupled with the PPU's rendering cycle. It would be more cohesive to move this flag into the `PpuState` struct.

## 3. Dead Code and Legacy Artifacts

- **`src/emulation/Ppu.zig`:** This file can be removed entirely if `EmulationState` calls `PpuLogic.tick()` directly.
- **`EmulationState.testSetVBlank`, `EmulationState.testClearVBlank`:** These are deprecated test helpers that should be removed.
- **`PpuStatus._reserved`:** This field is a remnant of the pre-VBlankLedger design and should be deleted.

## 4. Actionable Development Plan

1.  **Streamline PPU Tick Interface:**
    - Move the `TickFlags` struct from `src/emulation/Ppu.zig` to a more appropriate location, such as `src/ppu/State.zig` or a new `src/ppu/types.zig`.
    - Modify `EmulationState.stepPpuCycle()` to call `PpuLogic.tick()` directly instead of going through `PpuRuntime.tick()`.
    - Delete the now-redundant `src/emulation/Ppu.zig` file.

2.  **Finalize `PpuState` Struct:**
    - Remove the `_reserved` field from the `PpuStatus` packed struct in `src/ppu/State.zig`.
    - Move the `ppu_a12_state` flag from `EmulationState` into `PpuState`. This will involve updating `EmulationState.stepPpuCycle` to pass a mutable reference to `PpuState` so the flag can be updated.

3.  **Remove Deprecated Test Helpers:**
    - Delete the `testSetVBlank` and `testClearVBlank` functions from `src/emulation/State.zig`.
    - Search the `tests/` directory for any remaining usages of these functions and update them to use the `VBlankLedger` API directly (e.g., `harness.state.vblank_ledger.recordVBlankSet(...)`).

4.  **Enhance Palette Logic:**
    - The `src/ppu/palette.zig` file is simple and effective. Consider adding functions to handle color emphasis (from `PPUMASK` bits 5-7), which tints the entire screen. This would complete the palette emulation.

5.  **Review Sprite Evaluation Logic:**
    - The sprite evaluation logic in `src/ppu/logic/sprites.zig` is complex. Conduct a focused review of the sprite overflow bug implementation and the diagonal OAM scan pattern to ensure it perfectly matches hardware behavior as documented on the NesDev wiki.
