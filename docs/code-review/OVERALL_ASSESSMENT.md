# RAMBO Codebase Audit: Overall Assessment & Action Plan

**Audit Date:** 2025-10-11
**Overall Status:** Good

The RAMBO codebase is in a solid state, demonstrating a strong commitment to modern Zig practices, performance, and a clean, modular architecture. The transition to a state/logic separation pattern is largely successful, and the use of comptime generics for the cartridge and mapper system is a significant architectural improvement.

However, the audit has identified several areas with legacy code, API inconsistencies, and opportunities for simplification and improved accuracy. The following action plan itemizes the necessary work to finalize the recent refactoring efforts, eliminate legacy code, and ensure a fully consistent and maintainable API.

---

## High-Priority Action Plan

This plan prioritizes cleaning up legacy code, finalizing API migrations, and improving architectural consistency.

### 1. **Finalize APU State/Logic Separation**
- **Issue:** The APU implementation is a mix of old and new patterns. `Dmc.zig`, `Envelope.zig`, and `Sweep.zig` still contain logic that directly mutates state, while `Logic.zig` acts as a partial facade.
- **Action:**
    - **Refactor `Dmc.zig`, `Envelope.zig`, and `Sweep.zig`** into pure-logic modules. All functions should take `*const ApuState` and return a result struct describing the state changes (similar to the CPU opcode pattern).
    - **Consolidate all APU logic** into the `src/apu/logic/` directory. The top-level `Apu.zig` should only re-export the final `State` and `Logic` modules.
    - **Update `EmulationState.tick()`** to call the new pure APU logic functions and apply the resulting state deltas.
- **Reference:** `docs/code-review/APU.md`

### 2. **Decommission Legacy Cartridge System**
- **Issue:** The old cartridge system (`ines.zig`, `loader.zig`) exists alongside the new comptime generic system (`Cartridge.zig`, `mappers/registry.zig`). Tests in `tests/cartridge/` and `tests/ines/` still use the old system.
- **Action:**
    - **Migrate all tests** in `tests/cartridge/` and `tests/ines/` to use `AnyCartridge` and the new `Cartridge(MapperType)` generic.
    - **Delete the legacy `src/cartridge/ines.zig` and `src/cartridge/loader.zig` files** once all dependencies are removed.
    - **Update `src/main.zig`** to use the new cartridge loading mechanism.
- **Reference:** `docs/code-review/CARTRIDGE.md`

### 3. **Refactor the Configuration System**
- **Issue:** The configuration system (`src/config/`) is overly complex. It uses a multi-file structure (`types.zig`, `hardware.zig`, `ppu.zig`, `settings.zig`) that can be simplified. The parser is also more complex than necessary for the current requirements.
- **Action:**
    - **Consolidate all `Config` related structs** into a single `src/config/types.zig` file.
    - **Simplify the KDL parser** in `src/config/parser.zig`. The current implementation is robust but could be more direct for the limited keys being parsed.
    - **Remove the `Config.copyFrom` method.** The parser should directly populate the final `Config` struct.
- **Reference:** `docs/code-review/CONFIG.md`

### 4. **Standardize CPU Logic and Dispatch**
- **Issue:** The CPU implementation is very strong but has minor inconsistencies. The `dispatch.zig` module is overly complex for its purpose, and some logic could be clarified.
- **Action:**
    - **Simplify `dispatch.zig`**. The dispatch table build process can be made more direct. The use of category-specific helper functions is good but can be streamlined.
    - **Clarify RMW (Read-Modify-Write) logic.** Ensure the dummy write cycle is consistently and clearly implemented for all RMW instructions, both official and unofficial.
    - **Review unofficial opcode implementations** against the latest hardware research to ensure accuracy, especially for unstable opcodes.
- **Reference:** `docs/code-review/CPU.md`

### 5. **Update and Consolidate Documentation**
- **Issue:** Several design documents in `docs/` (e.g., `INES-MODULE-PLAN.md`, `MAPPER-SYSTEM-PLAN.md`) refer to outdated architectural decisions. The main architecture diagram (`docs/dot/architecture.png`) is mostly accurate but needs minor updates to reflect the new cartridge system and the flattened `EmulationState`.
- **Action:**
    - **Archive outdated design documents** into a sub-folder like `docs/archive/pre-refactor-2025-10/`.
    - **Update `docs/dot/architecture.png`** to show the `AnyCartridge` union and the direct ownership of all state by `EmulationState`.
    - **Create a new `ARCHITECTURE.md`** that serves as the single source of truth for the current architecture, referencing the updated diagram.
- **Reference:** `docs/code-review/DOCUMENTATION.md`

---
