# RAMBO Status & Action Plan - 2025-10-05

**Overall Status:** 🟢 **P0 COMPLETE**
**Focus:** P0 Critical Path Complete - 100% CPU Implementation Achieved

## Executive Summary

**P0 Progress:** ✅ **3/3 tasks COMPLETE** (2025-10-05)

A deep code review confirmed the project's pure functional CPU architecture is sound. All critical work completed:
1. ✅ `SBC` instruction bug fixed
2. ✅ 182 opcode unit tests restored (exceeds 166 deleted)
3. ✅ **JSR/RTS/RTI/BRK implementation complete** (microstep decomposition, 12 tests passing)

**Test Status:** 582/583 passing (99.8%) - only 1 cosmetic snapshot metadata issue remains.

**Achievement:** 🎉 **100% CPU implementation (256/256 opcodes)** - All 6502 instructions implemented and tested!

--- 

## P0: Critical Path (Must be completed sequentially)

### ✅ 1. Fix `SBC` Instruction Bug

-   **Status:** ✅ **COMPLETE**
-   **Issue:** `SBC` had incorrect carry logic.
-   **Action:** Re-implemented `SBC` using the standard inverted addition method (`A + ~M + C`).
-   **Verification:** All 570 tests now pass, including the previously failing `arithmetic_test.zig`.

### ✅ 2. Restore CPU Unit Tests

-   **Status:** ✅ **COMPLETE** (2025-10-05)
-   **Result:** 182 opcode tests migrated to pure functional pattern (exceeds 166 deleted)
-   **Test Files Created:**
    -   `tests/cpu/opcodes/arithmetic_test.zig` (17 tests - ADC, SBC)
    -   `tests/cpu/opcodes/branch_test.zig` (12 tests - all branch opcodes)
    -   `tests/cpu/opcodes/compare_test.zig` (18 tests - CMP, CPX, CPY, BIT)
    -   `tests/cpu/opcodes/incdec_test.zig` (15 tests - INC, DEC, INX, INY, DEX, DEY)
    -   `tests/cpu/opcodes/jumps_test.zig` (7 tests - JMP, NOP)
    -   `tests/cpu/opcodes/loadstore_test.zig` (21 tests - LDA, LDX, LDY, STA, STX, STY)
    -   `tests/cpu/opcodes/logical_test.zig` (9 tests - AND, ORA, EOR)
    -   `tests/cpu/opcodes/shifts_test.zig` (16 tests - ASL, LSR, ROL, ROR)
    -   `tests/cpu/opcodes/stack_test.zig` (6 tests - PHA, PHP, PLA, PLP)
    -   `tests/cpu/opcodes/transfer_test.zig` (16 tests - TAX, TXA, TAY, TYA, TSX, TXS)
    -   `tests/cpu/opcodes/unofficial_test.zig` (45 tests - all unofficial opcodes)
-   **Pattern:** Pure functional tests using `PureCpuState → Opcodes.fn(state, operand) → OpcodeResult`
-   **Verification:** 570/571 tests passing (99.8%)

### ✅ 3. Implement Missing Control Flow Opcodes

-   **Status:** ✅ **COMPLETE** (2025-10-05)
-   **Result:** All 4 critical opcodes implemented via microstep decomposition
-   **Opcodes Implemented:**
    -   `JSR` (0x20): Jump to Subroutine - 6 cycles
    -   `RTS` (0x60): Return from Subroutine - 6 cycles
    -   `RTI` (0x40): Return from Interrupt - 6 cycles
    -   `BRK` (0x00): Software Interrupt - 7 cycles
-   **Implementation:**
    -   11 new microstep functions in `src/cpu/execution.zig` (stack ops, helpers)
    -   4 microstep sequences in `src/cpu/addressing.zig` (JSR, RTS, RTI, BRK)
    -   Dispatch table updated in `src/cpu/dispatch.zig`
    -   12 integration tests in `tests/cpu/opcodes/control_flow_test.zig` (ALL PASSING)
-   **Architecture:**
    -   Microstep-only approach (no execute phase needed)
    -   Final microstep returns `true` to signal completion
    -   Zero changes to pure functional opcode layer (252 opcodes preserved)
    -   All side effects isolated in `execution.zig`
-   **Reference:** `docs/implementation/sessions/2025-10-05-control-flow-implementation.md`

--- 

## P1: High-Priority Accuracy Fixes

### 1.1. Unstable Opcode Configuration

-   **Status:** 🔴 **TODO**
-   **Issue:** Unofficial opcodes (`XAA`, `LXA`, `SHA`, etc.) use hardcoded magic values. True hardware accuracy requires these to be configurable based on the CPU revision.
-   **Action:** Modify the implementation of unstable opcodes to use values from `CpuConfig` based on the selected `CpuVariant`.
-   **Rationale:** Essential for 100% AccuracyCoin test suite compliance.

### 1.2. Implement Cycle-Accurate PPU/CPU DMA

-   **Status:** 🔴 **TODO**
-   **Issue:** OAM DMA (`$4014`) is not yet implemented. This stalls the CPU for 513-514 cycles.
-   **Action:** Implement the OAM DMA transfer, including the CPU stall.
-   **Rationale:** Critical for correct sprite rendering in most games.

### 1.3. Replace `anytype` in Bus Logic

-   **Status:** 🔴 **TODO**
-   **Issue:** `src/bus/Logic.zig` uses `anytype` for the `ppu` parameter, reducing type safety.
-   **Action:** Change the `ppu: anytype` parameter in the bus logic functions to a concrete `*PpuState` pointer.
-   **Rationale:** Improves type safety and IDE support with no downside.

--- 

## P2: General Refactoring & Best Practices

### 2.1. Integrate Standard Test ROMs

-   **Status:** 🟡 **TODO**
-   **Issue:** The project does not yet automate running standard NES test ROMs (e.g., `nestest`).
-   **Action:** Create a test runner to execute ROMs and verify the output against known-good logs.
-   **Rationale:** Provides high-level, continuous validation of the entire emulator's accuracy.

### 2.2. Implement Granular PPU `tick` Function

-   **Status:** 🟡 **TODO**
-   **Issue:** The main `Ppu.tick()` function is monolithic.
-   **Action:** Break down the `tick` function into smaller, pipeline-stage-specific helpers (e.g., `fetchNametableByte`, `renderPixel`).
-   **Rationale:** Improves readability and makes the PPU pipeline easier to debug.

### 2.3. Reorganize Debug Tests

-   **Status:** 🟡 **TODO**
-   **Issue:** Debug-specific tests are mixed with core CPU tests.
-   **Action:** Move `cycle_trace_test.zig`, `dispatch_debug_test.zig`, etc., to a new `tests/debug/` directory and create a separate `zig build test-debug` step for them.
-   **Rationale:** Cleans up the main test suite.

--- 

## P3: Future-Facing & Accuracy Improvements

-   **Implement a More Accurate Open Bus Model:** Research and implement a model that accounts for which component last drove the bus.
-   **Implement Four-Screen Mirroring:** Update the PPU and Cartridge systems to handle cartridges that provide their own VRAM.
-   **Complete `libxev` Integration:** Implement the render thread, UI event handling, and async file I/O.
-   **Implement Real-Time Safe Allocator:** Create an `RtAllocator` that pre-allocates all necessary memory at startup to guarantee the RT-safety of the emulation thread.
-   **Add `build.zig` Options for Features:** Allow conditional compilation of logging, debugging, etc.
