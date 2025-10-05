# 03 - PPU Implementation Review

**Date:** 2025-10-05
**Status:** ✅ Good

## 1. Summary

The PPU implementation is impressive, demonstrating a deep understanding of the hardware's intricacies. The State/Logic separation is correctly applied, and the rendering pipeline for both background and sprites is complete and well-tested, as verified by the passing PPU test suite.

The timing of events within the PPU tick appears to be cycle-accurate, correctly handling VBlank/NMI timing, pre-render scanline events, and odd-frame skipping. The sprite evaluation and rendering logic is also robust.

However, there are still some `TODO` items from the original review that need to be addressed to achieve full hardware accuracy.

## 2. Actionable Items

### 2.1. Implement Granular PPU `tick` Function

-   **Status:** 🟡 **TODO**
-   **Issue:** The current `Ppu.tick()` function in `src/ppu/Logic.zig` is a large monolithic function that handles all PPU events for a given cycle. While functional, it can be difficult to follow the complex interactions between different PPU phases (fetch, render, evaluate).
-   **Action:** Break down the `tick` function into smaller, more focused functions that correspond to the PPU's internal pipeline stages (e.g., `fetchNametableByte`, `evaluateSprites`, `renderPixel`). The main `tick` function would then dispatch to these helpers based on the current `scanline` and `dot`.
-   **Rationale:** A more granular `tick` function will make the PPU's complex rendering pipeline easier to understand, debug, and verify against hardware documentation like Visual 2C02.
-   **Code Reference:** `src/ppu/Logic.zig`

### 2.2. Cycle-Accurate PPU/CPU Interaction

-   **Status:** 🟡 **TODO**
-   **Issue:** The PPU and CPU interact in several critical, cycle-sensitive ways (e.g., NMI generation, DMA, register reads/writes during rendering). While the current implementation handles NMI timing correctly, a more thorough audit is needed to ensure all interactions are cycle-accurate.
-   **Action:** Audit and create specific tests for the following interactions:
    -   **NMI Timing:** Verify NMI is asserted at the exact correct PPU cycle (scanline 241, dot 1) and that the CPU sees it on the next CPU cycle.
    -   **Register Access:** Reading from registers like `$2002` (PPUSTATUS) and `$2007` (PPUDATA) can be affected by the PPU's rendering state. Tests should be created to verify this behavior (e.g., reading `$2002` at the exact moment VBlank is set).
    -   **DMA Timing:** OAM DMA (`$4014`) stalls the CPU for 513-514 cycles. This needs to be implemented and tested.
-   **Rationale:** Cycle-accurate interaction between the CPU and PPU is essential for many games to function correctly, especially those with advanced graphical effects or copy protection.

### 2.3. Four-Screen Mirroring

-   **Status:** 🟡 **TODO**
-   **Issue:** The `mirrorNametableAddress` function in `src/ppu/Logic.zig` has a placeholder for four-screen mirroring. It currently falls back to 2KB mirroring, which is incorrect for cartridges that provide their own extra VRAM.
-   **Action:** Implement proper four-screen mirroring. This will likely require the `Cartridge` to expose a flag indicating it provides four-screen VRAM, and the PPU will need to be able to access this extra memory, likely via a separate VRAM bus or by having the cartridge handle those memory ranges.
-   **Rationale:** While less common, some cartridges use four-screen mirroring, and supporting it is necessary for full compatibility.
-   **Code References:** `src/ppu/Logic.zig`, `src/cartridge/Cartridge.zig`

### 2.4. Implement or Skip TODO PPU Tests

-   **Status:** 🟡 **TODO**
-   **Issue:** The test file `tests/ppu/sprite_rendering_test.zig` contains 12 empty test scaffolds. These tests currently pass (as they do nothing), which can be misleading.
-   **Action:** Since these are integration tests that likely require a full video subsystem to verify output, they should be explicitly skipped for now. Add `return error.SkipZigTest;` to each empty test body with a comment explaining that they will be implemented with the video subsystem in a future phase.
-   **Rationale:** Prevents running empty, passing tests and clearly documents the dependency on the video backend, making the test suite status more accurate.
-   **Code Reference:** `tests/ppu/sprite_rendering_test.zig`
