# Cartridge System Code Review

**Audit Date:** 2025-10-11
**Status:** Good, but contains significant legacy code that needs removal.

## 1. Overall Assessment

The cartridge system has recently undergone a significant and positive architectural refactoring. The new system, centered around the `Cartridge(MapperType)` generic in `src/cartridge/Cartridge.zig` and the `AnyCartridge` tagged union in `src/cartridge/mappers/registry.zig`, is excellent. It provides compile-time polymorphism for mappers, eliminating runtime overhead and improving type safety.

The primary issue is that the old cartridge system (`src/cartridge/ines.zig`, `src/cartridge/loader.zig`) and its associated tests still exist in the codebase. This creates confusion, code duplication, and a maintenance burden. The immediate priority is to fully migrate all remaining dependencies to the new system and decommission the old one.

## 2. Issues and Inconsistencies

- **Dual Cartridge Systems:**
  - The project currently has two parallel implementations for handling cartridges:
    1.  **Legacy System:** `src/cartridge/ines.zig` and `src/cartridge/loader.zig`. This system appears to be based on a more traditional, less type-safe approach.
    2.  **New Generic System:** `src/cartridge/Cartridge.zig` and `src/cartridge/mappers/registry.zig`. This is the superior, modern approach that should be used exclusively.

- **Test Inconsistency:**
  - Tests are split between the two systems. `tests/ines/ines_test.zig` tests the legacy parser. `tests/cartridge/` contains tests for both, with `accuracycoin_test.zig` and `prg_ram_test.zig` using the new system, but other tests potentially relying on old patterns.
  - The proof-of-concept file `tests/comptime/poc_mapper_generics.zig` successfully validates the new pattern, confirming it is ready for project-wide adoption.

- **Outdated `root.zig` Exports:**
  - `src/root.zig` exports `CartridgeType = Cartridge.NromCart`, which is an alias for the new generic system. However, it also exports `iNES = @import("cartridge/ines/mod.zig")`, which is the new, more robust iNES parser that seems to have replaced the even older `ines.zig`. This is confusing. The `ines.zig` file seems to be the oldest artifact.

- **Inconsistent Naming:**
  - The new iNES parser is located at `src/cartridge/ines/mod.zig`, while the old one is at `src/cartridge/ines.zig`. This is a source of confusion.

## 3. Dead Code and Legacy Artifacts

- **`src/cartridge/ines.zig`:** This appears to be the original, now-obsolete iNES header parser. It has been superseded by the more comprehensive parser in `src/cartridge/ines/`. It should be deleted.
- **`src/cartridge/loader.zig`:** This file contains the file loading logic for the new generic cartridge system, but it's designed to be part of the `Cartridge.zig` module. It should be integrated or its logic moved directly into `Cartridge.zig`.
- **`tests/ines/ines_test.zig`:** This test file validates the obsolete `ines.zig` parser and should be deleted along with it.

## 4. Actionable Development Plan

1.  **Consolidate iNES Parsing:**
    - Delete the legacy parser `src/cartridge/ines.zig`.
    - Delete the corresponding test file `tests/ines/ines_test.zig`.
    - Ensure all parts of the application that need to parse iNES headers use the new, superior parser from `src/cartridge/ines/mod.zig`.

2.  **Migrate All Cartridge Loading to the New System:**
    - Update `src/main.zig` to use `AnyCartridge` and `Cartridge(MapperType).load()` to load ROMs. The current implementation in `main.zig` seems to be manually loading the ROM data and creating the cartridge, which should be centralized.
    - Refactor all tests in `tests/cartridge/` and `tests/integration/` that load ROMs to use the new generic system. This includes `accuracycoin_execution_test.zig`, `commercial_rom_test.zig`, etc.

3.  **Decommission Legacy Loader:**
    - The logic in `src/cartridge/loader.zig` should be reviewed. It seems to be a helper for the new system. It should either be moved into the `Cartridge.zig` file as a static method or kept as a private module helper, but its public interface should be through `Cartridge.zig`.

4.  **Clean Up `root.zig`:**
    - Remove the export of the legacy `iNES` module. The only cartridge-related exports should be the `AnyCartridge` type and potentially the `Cartridge` generic factory itself if needed externally.

5.  **Expand Mapper Registry:**
    - The new system is designed for easy expansion. Plan the implementation of the next mappers (MMC1, UxROM, CNROM, MMC3) by creating new files in `src/cartridge/mappers/` and adding them to the `MapperId` enum and `AnyCartridge` union in `src/cartridge/mappers/registry.zig`.
