# 03 - PPU Implementation Review

**Date:** 2025-10-03
**Status:** In Progress

## 1. Summary

The PPU implementation in `src/ppu/Ppu.zig` demonstrates a deep understanding of the PPU's hardware intricacies. The register definitions, memory mirroring, and the overall structure are well-conceived. The `tick` function provides a good starting point for a cycle-accurate PPU.

However, the current implementation can be significantly improved by refactoring it into a pure state machine, as outlined in the `final-hybrid-architecture.md` document. This will enhance testability, enable save states, and align the PPU with the project's new architectural direction.

## 2. Actionable Items

### 2.1. Refactor PPU to a Pure State Machine

*   **Action:** Similar to the CPU, refactor the `Ppu.zig` file to separate the PPU's state from its logic. Create a `PpuState` struct that contains all the PPU's data (registers, VRAM, OAM, etc.) and a separate set of pure functions that operate on this state.
*   **Rationale:** This is a core tenet of the new hybrid architecture. It will make the PPU's behavior deterministic and easier to reason about. It also simplifies testing and allows for the entire emulator state to be serialized.
*   **Code References:**
    *   `src/ppu/Ppu.zig`: The `Ppu` struct should be split into `PpuState` and a set of pure functions.
*   **Status:** **DONE** (Completed in Phase 2, commit 73f9279)
*   **Implementation:**
    *   Created `src/ppu/State.zig` with pure `PpuState` struct
    *   Created `src/ppu/Logic.zig` with pure rendering functions
    *   Module re-exports: `Ppu.State.PpuState`, `Ppu.Logic`
    *   Complete background rendering pipeline implemented
    *   VRAM system with proper mirroring and buffering
    *   23 PPU tests passing with new architecture
    *   Direct CHR memory access (no VTable abstraction needed - Phase 3)

### 2.2. Implement a More Granular PPU `tick` Function

*   **Action:** The current `tick` function in `Ppu.zig` is a good start, but it can be made more granular to better represent the PPU's internal pipeline. The `tick` function should be broken down into smaller, more focused functions that handle specific tasks for each PPU cycle (e.g., `fetchNametableByte`, `evaluateSprites`, `renderPixel`).
*   **Rationale:** A more granular `tick` function will make the PPU's complex rendering pipeline easier to understand, debug, and verify against hardware documentation.
*   **Code References:**
    *   `src/ppu/Ppu.zig`: The `tick` function.
*   **Status:** **TODO**.

### 2.3. Complete the PPU Rendering Pipeline

*   **Action:** The current PPU implementation is missing several key features of the rendering pipeline, including sprite evaluation, sprite rendering, and sprite-0-hit detection. These features need to be implemented to achieve accurate rendering.
*   **Rationale:** These are essential for rendering graphics correctly in most NES games.
*   **Status:** **TODO**.

### 2.4. PPU and CPU Interaction

*   **Action:** The PPU and CPU interact in several critical ways (e.g., NMI generation, DMA). The implementation should ensure that these interactions are handled in a cycle-accurate manner. For example, the NMI should be triggered on the correct PPU cycle, and the CPU should be able to read the PPU status register at the correct time.
*   **Rationale:** Cycle-accurate interaction between the CPU and PPU is essential for many games to function correctly.
*   **Status:** **TODO**.

### 2.5. Four-Screen Mirroring

*   **Action:** The `mirrorNametableAddress` function currently has a placeholder for four-screen mirroring. This should be implemented properly, likely by allowing the `ChrProvider` to provide the extra VRAM.
*   **Rationale:** While less common, some cartridges use four-screen mirroring, and supporting it is necessary for full compatibility.
*   **Code References:**
    *   `src/ppu/Ppu.zig`: The `mirrorNametableAddress` function.
*   **Status:** **TODO**.
