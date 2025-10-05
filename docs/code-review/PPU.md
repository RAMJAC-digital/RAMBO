# PPU Implementation Status - 2025-10-05

**Status:** 🟡 **Good, but with pending high-impact tasks.**

## 1. Summary

The PPU implementation is robust and well-tested at the unit level. The State/Logic separation is correctly applied, and the rendering pipeline for both background and sprites is complete. The 79 passing PPU tests provide strong confidence in the correctness of the rendering logic itself.

However, several critical, system-level features required for full hardware accuracy and game compatibility are still pending.

## 2. Actionable Items

### 2.1. Implement Cycle-Accurate PPU/CPU DMA (High Priority)

-   **Status:** 🔴 **TODO**
-   **Issue:** OAM DMA (triggered by a write to CPU register `$4014`) is not yet implemented. This process is crucial as it stalls the CPU for 513-514 cycles while copying sprite data into the PPU's OAM.
-   **Action:** Implement the OAM DMA transfer logic, ensuring the CPU is correctly stalled for the required duration.
-   **Rationale:** This is not an edge case; it is the primary mechanism for loading sprite data. Almost every game uses it every single frame. Its absence is a major blocker for displaying sprites correctly.

### 2.2. Implement Granular PPU `tick` Function

-   **Status:** 🟡 **TODO**
-   **Issue:** The current `Ppu.tick()` function in `src/ppu/Logic.zig` is a large monolithic function.
-   **Action:** Break down the `tick` function into smaller, more focused functions that correspond to the PPU's internal pipeline stages (e.g., `fetchNametableByte`, `evaluateSprites`, `renderPixel`).
-   **Rationale:** A more granular `tick` function will make the PPU's complex rendering pipeline easier to understand, debug, and verify against hardware documentation.

### 2.3. Implement Four-Screen Mirroring

-   **Status:** 🟡 **TODO**
-   **Issue:** The `mirrorNametableAddress` function in `src/ppu/Logic.zig` has a placeholder for four-screen mirroring.
-   **Action:** Implement proper four-screen mirroring, which will require coordination with the `Cartridge` module to handle the extra VRAM.
-   **Rationale:** While less common, some cartridges use four-screen mirroring, and supporting it is necessary for full compatibility.

### 2.4. Skip Empty PPU Tests

-   **Status:** 🟡 **TODO**
-   **Issue:** The test file `tests/ppu/sprite_rendering_test.zig` contains empty test scaffolds that pass misleadingly.
-   **Action:** Add `return error.SkipZigTest;` to each empty test body with a comment explaining that they will be implemented with the video subsystem.
-   **Rationale:** Makes the test suite status more accurate and documents the dependency on the video backend.
