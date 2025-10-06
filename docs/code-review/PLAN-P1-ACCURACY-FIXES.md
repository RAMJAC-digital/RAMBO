# Development Plan: P1 Accuracy Fixes

**Date:** 2025-10-05
**Status:** Proposed

## 1. Goal

This plan details the implementation of the three Priority 1 tasks outlined in `STATUS.md`. The objective is to significantly improve the emulator's hardware accuracy and type safety, bringing it closer to passing the `AccuracyCoin.nes` test suite. All work must adhere to the project's existing architecture: isolated state, pure functions for logic, and a tick-accurate execution model.

## 2. Task 1: Unstable Opcode Configuration

-   **Priority:** 1.1
-   **Goal:** Make the behavior of unstable unofficial opcodes (e.g., `XAA`, `LXA`, `SHA`) dependent on the CPU variant defined in the configuration, rather than being hardcoded.

### Implementation Plan

This will be achieved by passing a pointer to the `CpuModel` into the pure opcode functions.

1.  **Modify `src/cpu/State.zig`:** The `CpuCoreState` struct will be updated to include a pointer to the configuration. This adds a negligible 8-byte overhead to the struct.

    ```zig
    // In src/cpu/State.zig
    pub const CpuCoreState = struct {
        // ... existing fields (a, x, y, etc.)
        config: *const Config.CpuModel, // NEW
    };
    ```

2.  **Modify `src/cpu/Logic.zig`:** The `toCoreState` helper function will be updated to correctly populate this new pointer from the main `EmulationState`.

    ```zig
    // In src/cpu/Logic.zig -> toCoreState()
    fn toCoreState(state: *const CpuState) CpuCoreState {
        return .{
            // ... existing fields ...
            config: &state.config.cpu, // Pass pointer to CPU-specific config
        };
    }
    ```

3.  **Update Opcode Implementations (`src/cpu/opcodes/unofficial.zig`):** The relevant pure opcode functions will be updated to use the configuration.

    ```zig
    // Example for LXA
    pub fn lxa(state: CpuState, operand: u8) OpcodeResult {
        // Magic constant is now read from config instead of being hardcoded
        const magic = state.config.unstable_opcodes.lxa_magic;
        const result = (state.a | magic) & operand;
        // ...
    }
    ```

### Testing Strategy

1.  Create a new test file: `tests/cpu/opcodes/unstable_variants_test.zig`.
2.  Write tests that initialize multiple `EmulationState` objects, each with a different `Config` (e.g., one for `rp2a03g` and one for `rp2a03h`).
3.  Execute the same unstable opcode (like `LXA` or `SHA`) in each state.
4.  Assert that the resulting register values or memory writes differ according to the known hardware behaviors of each CPU variant.

## 3. Task 2: Cycle-Accurate OAM DMA

-   **Priority:** 1.2
-   **Goal:** Implement the OAM DMA transfer initiated by a write to CPU register `$4014`. This process must stall the CPU for the correct number of cycles (513 or 514) while the PPU copies 256 bytes of data into its OAM.

### Implementation Plan

The main emulation loop will mediate the DMA transfer, preserving component isolation.

1.  **Create `DmaState` in `src/bus/State.zig`:** A new struct will be added to the `BusState` to track the DMA process.

    ```zig
    // In src/bus/State.zig
    pub const DmaState = struct {
        active: bool = false,
        source_page: u8 = 0,
        cycle_count: u16 = 0,
    };

    // Add to BusState
    pub const BusState = struct {
        // ... existing fields ...
        dma: DmaState = .{},
    };
    ```

2.  **Trigger DMA in `src/bus/Logic.zig`:** In the bus `write` function, add a case for address `$4014`. This case will set `state.dma.active = true`, store the written value in `state.dma.source_page`, and reset `state.dma.cycle_count`.

3.  **Add Stall Flag in `src/cpu/State.zig`:** A `dma_stall: bool = false` flag will be added to `CpuState`.

4.  **Orchestrate in `src/emulation/State.zig`:** The main `EmulationState.tick()` function will be modified:
    *   At the start of the loop, it will check if `self.bus.dma.active` is true.
    *   If true, it will **not** tick the CPU. It will only tick the PPU.
    *   It will perform the 256 byte-copy operations (1 read from CPU bus, 1 write to PPU OAM per byte) over the course of 512 cycles.
    *   It will account for the initial 1-2 setup cycles to achieve a total stall of 513 or 514 cycles.
    *   Once complete, it will set `self.bus.dma.active = false`.

5.  **Respect Stall in `src/cpu/Logic.zig`:** The CPU `tick()` function will check for the `dma_stall` flag at its entry point and do nothing if it is set.

### Testing Strategy

1.  Create a new test file: `tests/integration/dma_test.zig`.
2.  Write a test that prepares a 256-byte block of data in CPU RAM (e.g., at `$0200`).
3.  Write the page number (`0x02`) to the DMA register `$4014`.
4.  Tick the `EmulationState` for ~520 cycles.
5.  Assert that the CPU's internal cycle counter has not advanced, while the PPU's has.
6.  Assert that the 256 bytes in the PPU's `oam` now match the source data from CPU RAM.

## 4. Task 3: Replace `anytype` in Bus Logic

-   **Priority:** 1.3
-   **Goal:** Enhance type safety by replacing the `ppu: anytype` parameter in `src/bus/Logic.zig` functions with a concrete, optional pointer `ppu: ?*Ppu.State`.

### Implementation Plan

This is a straightforward refactoring with significant compiler assistance.

1.  **Modify Signatures in `src/bus/Logic.zig`:** Change the function signatures for `read`, `write`, `peekMemory`, `read16`, and `read16Bug` to use `ppu: ?*Ppu.State`.

2.  **Simplify Logic:** Remove the `@typeInfo` branching for the `ppu` parameter and replace it with a simple `if (ppu) |p| { ... }` check.

3.  **Fix a Latent Bug:** While editing, ensure the PPU register access correctly masks the address (`address & 0x0007`) to handle register mirroring, which is currently missing.

    ```zig
    // In src/bus/Logic.zig -> readInternal
    0x2000...0x3FFF => blk: {
        if (ppu) |p| {
            // Add correct address masking
            break :blk p.readRegister(address & 0x0007);
        }
        break :blk state.open_bus.read();
    },
    ```

4.  **Update Call Sites:** The Zig compiler will fail at every location where the old function signature is still used. Manually update each call site (primarily in `src/cpu/execution.zig`, `src/emulation/State.zig`, and tests) to pass the correct PPU pointer.

### Testing Strategy

-   The existing test suite is the primary validation tool. After refactoring, run `zig build test`. If all tests pass, the refactoring was successful. The strictness of the type checker makes this a low-risk change.
