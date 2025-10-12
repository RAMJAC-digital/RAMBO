# Testing Code Review

**Audit Date:** 2025-10-11
**Status:** Good, but needs consolidation and cleanup.

## 1. Overall Assessment

The project has a substantial and valuable suite of tests, covering unit tests for individual components, integration tests for component interactions, and full ROM execution tests. The presence of tests for unofficial opcodes, CPU timing, and PPU behavior demonstrates a strong commitment to accuracy.

The main issue is the fragmentation of test harnesses and the presence of tests for legacy components that are slated for removal. Consolidating the test infrastructure and migrating all tests to use a single, unified harness will significantly improve maintainability.

## 2. Issues and Inconsistencies

- **Multiple Test Harnesses:**
  - There are several different test harnesses in use across the `tests/` directory:
    1.  `src/test/Harness.zig`: A comprehensive harness that seems to be the most modern.
    2.  `tests/cpu/opcodes/helpers.zig`: A set of helpers specifically for testing pure CPU opcode functions.
    3.  `tests/integration/rom_test_runner.zig`: A framework for running full test ROMs like AccuracyCoin.
    4.  Various ad-hoc setups in individual test files.
  - This fragmentation leads to code duplication and makes it difficult to apply consistent testing patterns.

- **Tests for Legacy Code:**
  - `tests/ines/ines_test.zig` validates the old `src/cartridge/ines.zig` parser, which is obsolete.
  - Some tests in `tests/cartridge/` may still be using the old cartridge loading mechanisms.

- **Inconsistent Test Structure:**
  - Some tests are self-contained (`tests/apu/apu_test.zig`), while others rely on the complex `TestHarness` (`tests/ppu/vblank_behavior_test.zig`).
  - The `build.zig` file has a very long and manual list of every single test file. This is brittle and hard to maintain.

- **`poc_mapper_generics.zig`:**
  - The file `tests/comptime/poc_mapper_generics.zig` is a proof-of-concept that has served its purpose. Its findings should be integrated into the main cartridge system, and the file can then be removed or moved to an `archive` directory.

## 3. Dead Code and Legacy Artifacts

- **`tests/ines/ines_test.zig`:** This entire file is dead code once the legacy `ines.zig` parser is removed.
- **`tests/cpu/dispatch_debug_test.zig`:** This test appears to be a temporary diagnostic tool and may no longer be necessary. It should be reviewed and likely removed.
- **Redundant Helpers:** Many test files have their own local helper functions for creating test states, which could be consolidated into the main test harness.

## 4. Actionable Development Plan

1.  **Unify Test Harnesses:**
    - **Goal:** Have a single, primary test harness in `src/test/Harness.zig` that all integration tests can use.
    - **Action:**
        - Extend `src/test/Harness.zig` to include the functionality currently in `tests/integration/rom_test_runner.zig` (e.g., `runRomForFrames`, `extractResults`).
        - Move the pure opcode test helpers from `tests/cpu/opcodes/helpers.zig` into the main harness or a dedicated `src/test/CpuTestHelpers.zig` module that the harness can use.
        - Refactor all tests in `tests/integration/` and `tests/cpu/` to use the unified harness.

2.  **Automate Test Discovery in `build.zig`:**
    - **Goal:** Remove the manual list of test files from `build.zig`.
    - **Action:** Modify `build.zig` to use a glob pattern (e.g., `tests/**/*.zig`) to automatically discover and add all test files to the `test` step. This will make adding new tests much simpler.

3.  **Remove Legacy Tests:**
    - Delete `tests/ines/ines_test.zig` along with its corresponding legacy source file.
    - Review and delete `tests/cpu/dispatch_debug_test.zig` if it is confirmed to be a temporary diagnostic.

4.  **Migrate Cartridge Tests:**
    - Audit all tests in `tests/cartridge/` and `tests/integration/` to ensure they use the new `AnyCartridge` and generic `Cartridge(MapperType)` system for loading ROMs.
    - Remove any tests that are validating the old, obsolete cartridge loading logic.

5.  **Archive Proof-of-Concept:**
    - Move `tests/comptime/poc_mapper_generics.zig` to `docs/archive/` or a similar location, as it serves as valuable documentation for an architectural decision but is not a permanent test asset.
