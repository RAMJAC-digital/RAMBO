# RAMBO Cleanup Plan - Post-Phase 7 Code Review

**Date:** 2025-10-04
**Status:** In Progress
**Context:** Comprehensive code review after Phase 7 (sprite system) completion

## Executive Summary

Three specialist agents (qa-code-review-pro, architect-reviewer, code-reviewer) conducted comprehensive reviews of the RAMBO codebase. Overall assessment: **Production-ready with minor cleanup needed**.

This plan consolidates all outstanding code review items and provides a prioritized roadmap for implementation.

**Key Findings:**
- ✅ **RT-Safety:** Excellent (98/100) - No critical violations found.
- ✅ **Architecture:** Strong State/Logic separation pattern is consistently applied.
- ⚠️ **API Consistency:** Naming inconsistencies in the public API in `root.zig`.
- ⚠️ **Code Organization:** Empty directories exist, and debug tests are mixed with regular tests.
- ⚠️ **Type Safety:** 55 instances of `anytype` reduce type safety and IDE support.

**Test Status:** 568/569 passing (99.8%)

---

## Priority 1: Immediate Fixes (< 2 hours total)

These are high-impact, low-effort changes that should be completed first.

### 1.1 API Naming Consistency (30 minutes)

**Issue:** Redundant and inconsistent `*Type` aliases are exported in `src/root.zig`.
**Action:** Remove the unnecessary aliases (`CpuType`, `BusType`, `PpuType`, `CartridgeType`) and update all test files to use the direct module paths (e.g., `rambo.cpu.State`).
**Rationale:** Improves API clarity and consistency.

### 1.2 Remove PpuLogic from Public API (5 minutes)

**Issue:** The internal `PpuLogic` module is exposed in the public API via `root.zig`.
**Action:** Remove the line `pub const PpuLogic = @import("ppu/Logic.zig");` from `src/root.zig`.
**Rationale:** `PpuLogic` is an internal implementation detail needed only for unit tests, not for public consumption.

### 1.3 RT-Safety Improvements (15 minutes)

**Issue:** The codebase contains non-RT-safe constructs (`@panic`, `std.debug.print`) in potential hot paths.
**Action:**
1.  Replace `@panic` in `src/cpu/execution.zig` with `unreachable`.
2.  Wrap the `std.debug.print` call in `src/emulation/State.zig` with `if (comptime std.debug.runtime_safety)` to ensure it's compiled out in release builds.
**Rationale:** Guarantees RT-safety in all build modes.

### 1.4 Remove Empty Directories (5 minutes)

**Issue:** The `src/sync/` and `src/nes/` directories are empty and have no documented purpose.
**Action:** Execute `rm -rf src/sync/ src/nes/`.
**Rationale:** Improves project clarity and removes clutter.

### 1.5 Add READMEs to Placeholder Directories (15 minutes)

**Issue:** The `src/apu/`, `src/io/`, and `src/mappers/` directories are empty placeholders.
**Action:** Add a `README.md` to each, briefly explaining its purpose and noting that implementation is pending a future phase.
**Rationale:** Provides clarity for new developers about the project's structure and future plans.

---

## Priority 2: Code Organization (2-4 hours)

### 2.1 Reorganize Debug Tests (1 hour)

**Issue:** Debug-specific tests are mixed with integration tests in `tests/cpu/`.
**Action:**
1.  Create a new `tests/cpu/debug/` directory.
2.  Move `cycle_trace_test.zig`, `dispatch_debug_test.zig`, `rmw_debug_test.zig`, and `simple_nop_test.zig` into it.
3.  Update `build.zig` to correctly locate and run these tests under a separate, optional step.
**Rationale:** Separates core validation tests from debugging helpers, resulting in a cleaner main test suite.

### 2.2 Fix Module Pattern Inconsistencies (30 minutes)

**Issue:** The snapshot module has an inconsistent file name capitalization (`state.zig` instead of `State.zig`).
**Action:** Rename `src/snapshot/state.zig` to `src/snapshot/State.zig` and update all imports.
**Rationale:** Enforces consistent naming conventions across all modules.

### 2.3 Document Non-Pattern Modules (30 minutes)

**Issue:** Several modules (`Config`, `FrameTimer`, `Debugger`, `Snapshot`) do not follow the State/Logic pattern, which could be confusing.
**Action:** Add doc comments to the top of these files explaining *why* they deviate from the pattern (e.g., they are pure data structures, I/O handlers, or not part of the RT loop).
**Rationale:** Improves architectural clarity and documents design decisions.

---

## Priority 3: Type Safety Improvements (4-6 hours)

### 3.1 Replace `anytype` with Explicit Types (HIGH EFFORT)

**Issue:** There are 55 instances of `anytype` in the codebase, primarily in the Bus, PPU, and CPU helper modules, which reduces type safety.
**Action:** Systematically replace `anytype` parameters with explicit types (e.g., `?*NromCart`, `*PpuState`). This is a significant refactoring task.
**Approach:** Start with `src/bus/Logic.zig`, update signatures, fix all call sites, and run tests. Repeat for other modules.
**Rationale:** Improves type safety, enables better static analysis, and enhances IDE support.

---

## Priority 4: Code Quality Improvements (6-8 hours)

### 4.1 Refactor Massive Dispatch Function (2-3 hours)

**Issue:** The `buildDispatchTable` function in `src/cpu/dispatch.zig` is over 1,200 lines long.
**Action:** Refactor this function by extracting opcode groups into smaller, focused helper functions (e.g., `buildArithmeticOpcodes`, `buildLoadStoreOpcodes`).
**Rationale:** Improves readability and maintainability of a critical piece of the CPU core.

### 4.2 Extract Shift Instruction Helpers (1 hour)

**Issue:** The shift and rotate instructions in `src/cpu/instructions/shifts.zig` contain duplicated logic.
**Action:** Create `inline` helper functions for accumulator and memory shift operations, parameterized by a `ShiftOp` enum, to reduce code duplication.
**Rationale:** Reduces code size and centralizes common logic.

### 4.3 Implement or Skip TODO Test Scaffolds (4-6 hours)

**Issue:** There are 12 empty test scaffolds in `tests/ppu/sprite_rendering_test.zig`.
**Action:** Since these are integration tests requiring a full video subsystem, they should be explicitly skipped for now. Add `return error.SkipZigTest;` to each empty test body with a comment explaining that they will be implemented with the video subsystem in Phase 8.
**Rationale:** Prevents running empty, passing tests and clearly documents the dependency on the video backend.

---

## Priority 5: Documentation Updates (2-3 hours)

### 5.1 Update Code Review Status (1 hour)

**Issue:** The `docs/code-review/` files are static and do not reflect the completion of Phase 7.
**Action:** Update the status of all relevant items in the code review documents to `COMPLETE` or `IN PROGRESS`.
**Rationale:** Keeps the project's main review hub accurate.

### 5.2 Add Function Documentation (1-2 hours)

**Issue:** Several public utility modules lack function-level documentation.
**Action:** Add doc comments to the public functions in `src/cpu/helpers.zig`, `src/ppu/palette.zig`, and `src/ppu/timing.zig`.
**Rationale:** Improves API usability and maintainability.
