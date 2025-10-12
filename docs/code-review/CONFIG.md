# Configuration System Code Review

**Audit Date:** 2025-10-11
**Status:** Good, but Overly Complex

## 1. Overall Assessment

The configuration system is functional and provides a good foundation for hardware and emulator settings. The use of a KDL-style parser is a nice touch for human-readable config files. The system correctly separates hardware definitions (`hardware.zig`, `ppu.zig`) from runtime settings (`settings.zig`).

However, the current implementation is more complex than it needs to be. The type definitions are fragmented across multiple files, and the parser contains more logic than necessary for the current feature set. This creates a maintenance overhead and can make it harder for new contributors to understand the configuration flow.

## 2. Issues and Inconsistencies

- **File Fragmentation:**
  - Configuration types are spread across four different files: `types.zig`, `types/hardware.zig`, `types/ppu.zig`, and `types/settings.zig`. The top-level `types.zig` just re-exports everything, adding an unnecessary layer of indirection.
  - This fragmentation makes it difficult to get a holistic view of the `Config` struct and its components.

- **Parser Complexity:**
  - The `src/config/parser.zig` is well-written but is a fairly generic KDL parser. Given that `rambo.kdl` has a simple, well-defined structure, the parser could be made much more direct and less abstract, reducing its size and complexity.
  - The parser creates a temporary `Config` object and then copies the values over. It could instead be modified to take a `*Config` pointer and populate it directly.

- **Unused `Config.copyFrom`:**
  - The `Config.copyFrom` method is only used by the parser. If the parser is refactored to populate the `Config` struct directly, this method becomes redundant.

- **Redundant `Config.get`:**
  - The `Config.get()` method simply returns a copy of the `Config` struct. Since the config is intended to be immutable after loading, callers can just access the struct fields directly. The `get()` method adds little value and could be removed for a simpler API.

## 3. Dead Code and Legacy Artifacts

- **`src/config/types.zig`:** This file is pure boilerplate, re-exporting types from other files. It can be eliminated by consolidating the type definitions.
- **`Config.copyFrom` and `Config.get`:** These methods can be removed after a small refactoring of the parser, as noted above.

## 4. Actionable Development Plan

1.  **Consolidate All Type Definitions:**
    - Create a single, authoritative `src/config/types.zig` file.
    - Move all struct and enum definitions from `types/hardware.zig`, `types/ppu.zig`, and `types/settings.zig` into this new single file.
    - Delete the now-empty `types/` sub-directory and the old top-level `types.zig` re-export file.
    - Update `Config.zig` to import from the new consolidated `types.zig`.

2.  **Simplify the KDL Parser:**
    - Refactor `src/config/parser.zig` to be a more direct, less abstract parser.
    - Modify the `parseKdl` function to accept a `*Config` pointer and populate its fields directly, instead of creating and returning a new `Config` object.
    - This change will allow for the removal of the `Config.copyFrom` method.

3.  **Simplify the `Config` API:**
    - Remove the `get()` method from `Config.zig`. Callers should be instructed to access configuration fields directly (e.g., `config.ppu.variant`).
    - Remove the `copyFrom()` method after the parser is refactored.

4.  **Update `rambo.kdl`:**
    - The `rambo.kdl` file contains an `unstable_opcodes` section that is no longer reflected in the `Config` struct in `src/config/Config.zig`. The `sha_behavior` and `lxa_magic` fields were removed from `CpuModel`.
    - **Decision Needed:** Either remove this section from `rambo.kdl` to match the code, or re-add the `unstable_opcodes` struct to `CpuModel` if this level of configuration is still desired. Given the move to a `variants.zig` system for CPU behavior, removing it from the config seems more consistent.
