# RAMBO Cleanup Plan - Post-Refactoring Review

**Date:** 2025-10-05
**Status:** Phase 0 Complete ✅ | In Progress (Phase 1 Next)
**Context:** Consolidated action plan from the comprehensive code review conducted after major architectural refactoring.
**Latest Update:** Phase 0 (Stateless KDL Parser) completed with zero regressions. Test baseline maintained at 575/576 passing.

## Executive Summary

A deep code review of the RAMBO codebase has been completed. The overall assessment is **excellent**. The project is well-structured, adheres to modern Zig practices, and has a strong architectural foundation. The core emulation loop is RT-safe, and the test suite is comprehensive.

This plan consolidates all outstanding minor cleanup tasks, refactoring opportunities, and remaining `TODO` items into a single, prioritized roadmap. These items are not critical blockers for new feature development but should be addressed to further improve code quality, maintainability, and hardware accuracy.

---

## Development Resources

**Essential documentation for implementing this cleanup plan:**

-   **[DEVELOPMENT-PROCEDURES.md](DEVELOPMENT-PROCEDURES.md)** - Step-by-step workflows for executing each phase (TDD, baseline capture, commit procedures, blocker protocol)
-   **[DEVELOPMENT-PROGRESS.md](DEVELOPMENT-PROGRESS.md)** - Real-time progress tracker with phase completion status, test baselines, and commit history
-   **[SUBAGENT-ANALYSIS.md](SUBAGENT-ANALYSIS.md)** - Detailed findings from 5 specialized agents including architecture recommendations and corrected approaches

**Key Principles:**
-   ✅ Test-Driven Development (write failing tests first)
-   ✅ Zero Regressions (test count never decreases, baselines must match)
-   ✅ Stateless Everything (State/Logic separation throughout)
-   ✅ Frequent Commits (every 2-4 hours, at milestones)
-   ✅ Baseline Capture (CPU traces, PPU framebuffers, dispatch tables)

**Test Baseline:** 575/576 passing (99.8%) - 1 expected failure (snapshot metadata cosmetic)

---

## Priority 1: Critical Fixes (Essential for Reliability & Accuracy)

### ✅ 1.1. **[PHASE 0 COMPLETE]** Stateless KDL Parser Implementation

-   **Status:** ✅ **COMPLETE** (Phase 0 - 2025-10-05)
-   **Implementation:** Created a robust, stateless KDL parser in `src/config/parser.zig` following the zzt-backup pattern. The parser is a pure function with zero global state, thread-safe, and includes comprehensive error handling with safety limits.
-   **Deliverables:**
    -   `src/config/parser.zig` (245 lines) - Stateless parser with enum-based section dispatch
    -   `tests/config/parser_test.zig` (308 lines) - 20+ comprehensive tests
    -   Refactored `Config.zig` to use stateless parser
    -   All 31+ config tests passing, baseline maintained (575/576)
-   **Commit:** `3cbf179` - feat(config): Implement stateless KDL parser (Phase 0 complete)
-   **Rationale:** Stateless design enables thread safety, testability, and follows established State/Logic pattern. Graceful error handling with defaults ensures reliability.
-   **Reference:** `docs/code-review/DEVELOPMENT-PROGRESS.md`, `docs/code-review/06-configuration.md`

### 1.2. Unstable Opcode Configuration

-   **Status:** 🔴 **High Priority TODO**
-   **Issue:** Unofficial opcodes in `unofficial.zig` use hardcoded magic values. True hardware accuracy requires these to be configurable based on the CPU revision.
-   **Action:** Modify the implementation of unstable opcodes (`XAA`, `LXA`, `SHA`, etc.) to use values from `CpuConfig` based on the selected `CpuVariant`.
-   **Rationale:** Essential for 100% AccuracyCoin test suite compliance.
-   **Reference:** `docs/code-review/02-cpu.md`

### 1.3. Replace `anytype` in Bus Logic

-   **Status:** 🔴 **High Priority TODO**
-   **Issue:** `src/bus/Logic.zig` uses `anytype` for the `ppu` parameter, reducing type safety.
-   **Action:** Change the `ppu: anytype` parameter in the bus logic functions to a concrete `*PpuState` pointer.
-   **Rationale:** Improves type safety and IDE support with no downside.
-   **Reference:** `docs/code-review/04-memory-and-bus.md`

---

## Priority 2: Code Organization & API Cleanup

### 2.1. Refactor Massive Dispatch Function

-   **Issue:** The `buildDispatchTable` function in `src/cpu/dispatch.zig` is over 1,200 lines long.
-   **Action:** Break the function into smaller, opcode-group-specific helper functions (e.g., `buildBranchOpcodes`).
-   **Rationale:** Improves readability and maintainability.
-   **Reference:** `docs/code-review/02-cpu.md`

### 2.2. Organize Opcodes into Functional Groups (Phase 1 - Planned)

-   **Status:** 🟡 **REVISED APPROACH** (Based on subagent analysis)
-   **Issue:** Original plan to merge `execution.zig` and `dispatch.zig` would violate State/Logic separation. The real issue is opcode organization, not file consolidation.
-   **Corrected Action:**
    -   Create `src/cpu/opcodes/` directory with functional groups (LoadStore.zig, Arithmetic.zig, Logical.zig, Shifts.zig, Branches.zig, Jumps.zig, Stack.zig, Transfer.zig, Unofficial.zig)
    -   Create `src/cpu/opcodes/state.zig` for pure opcode state (no system coupling)
    -   Extract pure microsteps to `src/cpu/execution/microsteps.zig`
    -   Refactor `dispatch.zig` with opcode-group builder functions
-   **Rationale:** Preserves State/Logic separation, improves organization by function (not location), maintains testability. Each opcode group is ~150-200 lines instead of 1370-line monolith.
-   **Reference:** `docs/code-review/SUBAGENT-ANALYSIS.md` (Agent 2 - architect-reviewer)

### 2.3. Remove Unused Type Aliases and `PpuLogic` from Public API

-   **Issue:** `src/root.zig` exports redundant `*Type` aliases and the internal `PpuLogic` module.
-   **Action:** Remove the aliases and the `PpuLogic` export from `root.zig`. Update tests to use direct paths.
-   **Rationale:** Cleans up the public API and improves encapsulation.
-   **Reference:** `docs/code-review/09-dead-code.md`

### 2.4. Reorganize Debug Tests

-   **Issue:** Debug-specific tests are mixed with core CPU tests.
-   **Action:** Move `cycle_trace_test.zig`, `dispatch_debug_test.zig`, etc., to a new `tests/debug/` directory and create a separate `zig build test-debug` step for them.
-   **Rationale:** Cleans up the main test suite.
-   **Reference:** `docs/code-review/07-testing.md`

---

## Priority 3: General Refactoring & Best Practices

### 3.1. Implement Granular PPU `tick` Function

-   **Issue:** The main `Ppu.tick()` function is monolithic.
-   **Action:** Break down the `tick` function into smaller, pipeline-stage-specific helpers (e.g., `fetchNametableByte`, `renderPixel`).
-   **Rationale:** Improves readability and makes the PPU pipeline easier to debug.
-   **Reference:** `docs/code-review/03-ppu.md`

### 3.2. Refactor Shift/Rotate Instructions

-   **Issue:** Duplicated logic in `src/cpu/instructions/shifts.zig` for accumulator vs. memory modes.
-   **Action:** Create `inline` helper functions to abstract the core shift/rotate logic.
-   **Rationale:** Reduces code duplication.
-   **Reference:** `docs/code-review/02-cpu.md`

### 3.3. Add READMEs to Placeholder Directories

-   **Issue:** Empty directories (`apu`, `io`, `mappers`) lack context.
-   **Action:** Add a `README.md` to each, explaining its purpose and future plans.
-   **Rationale:** Improves project clarity for new developers.
-   **Reference:** `docs/code-review/09-dead-code.md`

### 3.4. Skip TODO PPU Tests

-   **Issue:** `tests/ppu/sprite_rendering_test.zig` has empty, passing tests.
-   **Action:** Add `return error.SkipZigTest;` to each empty test body with a comment about their dependency on the video subsystem.
-   **Rationale:** Makes the test suite status more accurate.
-   **Reference:** `docs/code-review/03-ppu.md`

---

## Priority 4: Future-Facing & Accuracy Improvements

### 4.1. Integrate Existing Test ROMs

-   **Issue:** The project does not yet automate running standard NES test ROMs.
-   **Action:** Create a test runner to execute ROMs like `nestest` and verify the output against known-good logs.
-   **Rationale:** Provides high-level, continuous validation of the entire emulator's accuracy.
-   **Reference:** `docs/code-review/07-testing.md`

### 4.2. Implement More Accurate Open Bus Model

-   **Issue:** The current open bus model is a simplification.
-   **Action:** Research and implement a more accurate model that accounts for which component last drove the bus.
-   **Rationale:** Required for some edge-case game behaviors.
-   **Reference:** `docs/code-review/04-memory-and-bus.md`

### 4.3. Implement Cycle-Accurate PPU/CPU DMA

-   **Issue:** OAM DMA (`$4014`) is not yet implemented.
-   **Action:** Implement the OAM DMA transfer, which stalls the CPU for 513-514 cycles while copying data to PPU OAM.
-   **Rationale:** Critical for correct sprite rendering in most games.
-   **Reference:** `docs/code-review/03-ppu.md`

### 4.4. Implement Four-Screen Mirroring

-   **Issue:** Four-screen mirroring is not properly supported.
-   **Action:** Update the PPU and Cartridge systems to handle cartridges that provide their own VRAM for four-screen mirroring.
-   **Rationale:** Required for compatibility with a small number of games.
-   **Reference:** `docs/code-review/03-ppu.md`