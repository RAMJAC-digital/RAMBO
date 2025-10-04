# 07 - Testing Review

**Date:** 2025-10-03
**Status:** In Progress

## 1. Summary

A robust test suite is critical for developing an accurate NES emulator. The existing tests provide a good foundation, particularly for the CPU. However, there are significant gaps in test coverage that need to be addressed. The `tests/bus` and `tests/integration` directories are empty, and the PPU tests are minimal.

This review provides actionable recommendations for improving the test suite, increasing coverage, and adopting best practices for testing in a Zig project.

## 2. Actionable Items

### 2.1. Implement Bus Tests

*   **Action:** The `tests/bus` directory is empty. Create a comprehensive suite of tests for the memory bus. These tests should cover all aspects of the bus's functionality, including RAM mirroring, PPU and APU register mapping, and cartridge communication.
*   **Rationale:** The bus is a critical component that connects all the major parts of the emulator. Its behavior must be thoroughly tested to ensure that the components can communicate correctly.
*   **Status:** **TODO**.

### 2.2. Implement Integration Tests

*   **Action:** The `tests/integration` directory is empty. Create a suite of integration tests that verify the interaction between different components. For example, tests that verify the CPU and PPU can communicate correctly through the bus to generate an NMI.
*   **Rationale:** Integration tests are essential for finding bugs that arise from the interaction between components. They are a crucial step in verifying the overall correctness of the emulator.
*   **Status:** **TODO**.

### 2.3. Expand PPU Test Coverage

*   **Action:** The PPU tests are currently minimal. Expand the PPU test suite to cover all aspects of the PPU's functionality, including rendering, sprite evaluation, scrolling, and timing.
*   **Rationale:** The PPU is one of the most complex components of the NES. A comprehensive test suite is essential for ensuring its correctness.
*   **Status:** **PARTIALLY COMPLETE** (Phase 4, 2025-10-03)
*   **Completed:**
    *   ✅ Sprite evaluation tests - 15 tests (`tests/ppu/sprite_evaluation_test.zig`)
    *   ✅ Sprite rendering tests - 23 tests (`tests/ppu/sprite_rendering_test.zig`)
    *   ✅ Background rendering tests - Already implemented in existing PPU tests
    *   ✅ VRAM/register tests - Already implemented
*   **Still Needed:**
    *   ❌ Scrolling tests (coarse/fine X/Y, nametable switching)
    *   ❌ Timing edge case tests (VBlank race conditions, odd frame skip)
    *   ❌ Sprite-background interaction tests
*   **Documentation:** `docs/PHASE-4-1-TEST-STATUS.md`, `docs/PHASE-4-2-TEST-STATUS.md`, `docs/PHASE-4-SUMMARY.md`

### 2.4. Use a Test Runner

*   **Action:** The project should use a test runner to automate the process of running tests and reporting results. `zig test` is the built-in test runner and should be used.
*   **Rationale:** A test runner makes it easy to run all the tests in the project with a single command. This is essential for maintaining a high level of quality and for implementing continuous integration.
*   **Status:** ✅ **COMPLETE**
*   **Implementation:**
    *   ✅ `zig build test` - Runs all tests (unit + integration)
    *   ✅ `zig build test-unit` - Runs only unit tests
    *   ✅ `zig build test-integration` - Runs only integration tests
    *   ✅ Separate test steps for debugging: `test-trace`, `test-rmw-debug`, `test-debug`
    *   ✅ All tests integrated into build system (`build.zig`)
    *   ✅ Total: 413 tests (381 passing, 32 expected failures documented)

### 2.5. Adopt a More Data-Driven Approach to Testing

*   **Action:** Many of the existing tests are very procedural. A more data-driven approach would make the tests more concise and easier to maintain. For example, instead of writing a separate test for each instruction, create a single test that is parameterized with a set of test cases.
*   **Rationale:** Data-driven tests are more scalable and make it easier to add new test cases. This is particularly important for testing the CPU, which has a large number of instructions and addressing modes.
*   **Code References:**
    *   `tests/cpu/instructions_test.zig`: This file could be refactored to use a data-driven approach.
*   **Status:** **SPECIFICATION COMPLETE** (Phase 4.3, 2025-10-03) | **IMPLEMENTATION TODO**
*   **Design:**
    *   Created comprehensive state snapshot + debugger specification
    *   Binary format (~5 KB core state, ~250 KB with framebuffer)
    *   JSON format (~8 KB core state, ~400 KB with framebuffer)
    *   Supports full system state save/load (CPU, PPU, Bus, RAM, cartridge, framebuffer)
    *   Enables data-driven testing via state snapshots
    *   Documentation: 5 specification documents, 119 KB total
*   **Documentation:** `docs/PHASE-4-3-*.md` (INDEX, SUMMARY, QUICKSTART, ARCHITECTURE, SNAPSHOT-DEBUGGER-SPEC)
*   **Implementation Estimate:** 26-33 hours

### 2.6. Use Existing Test ROMs

*   **Action:** There are many existing test ROMs for the NES that can be used to verify the emulator's accuracy. The project should integrate these test ROMs into its testing strategy.
*   **Rationale:** These test ROMs are a valuable resource for finding subtle bugs and for verifying the emulator's accuracy against real hardware.
*   **Status:** **TODO**.
