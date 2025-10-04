# 06 - Configuration System Review

**Date:** 2025-10-05
**Status:** 🟡 Needs Improvement

## 1. Summary

The configuration system in `src/config/Config.zig` is extensive and provides a good foundation for defining hardware variations, which is crucial for an accurate, multi-system emulator. The use of enums for variants like `CpuVariant` and `PpuVariant` is a strong point.

However, the system's primary weakness is its manual, line-by-line KDL parsing. This approach is brittle, error-prone, and difficult to maintain or extend. Adopting a proper KDL parsing library is a high-priority task.

## 2. Actionable Items

### 2.1. Use a KDL Parsing Library

-   **Status:** 🔴 **High Priority TODO**
-   **Issue:** The `parseKdl` function in `src/config/Config.zig` manually parses the KDL file by splitting lines and trimming whitespace. This is not robust and will fail with slightly different formatting, comments, or more complex KDL structures.
-   **Action:** Replace the manual parsing logic with a dedicated KDL parsing library for Zig. Several are available (e.g., searching on GitHub for "zig kdl"). This will simplify the code, make it more robust, and handle all the complexities of the KDL format automatically.
-   **Rationale:** A dedicated library will make the configuration loading process more reliable, easier to extend, and less prone to bugs. It will also significantly reduce the amount of code in `Config.zig`.
-   **Code Reference:** `src/config/Config.zig` (the `parseKdl` function).

### 2.2. Consolidate Hardware Configuration

-   **Status:** 🟡 **TODO**
-   **Issue:** The `Config` struct contains a mix of hardware-specific settings (like `cpu`, `ppu`, `cic`) and application-level settings (like `video`, `audio`). While the `console` enum provides a good top-level switch, a clearer separation would be beneficial.
-   **Action:** Create a `HardwareConfig` struct that consolidates all the hardware-related configurations (`cpu`, `ppu`, `cic`, `controllers`). The main `Config` struct would then hold this `HardwareConfig` struct alongside other settings. This would make it easier to pass the complete hardware configuration to the `EmulationState`.
-   **Rationale:** Creates a clear separation between the emulated hardware and the emulator's application settings, improving architectural clarity.
-   **Code Reference:** `src/config/Config.zig`

### 2.3. Implement Hot-Reloading

-   **Status:** 🟡 **TODO**
-   **Issue:** The design documents mention the possibility of hot-reloading the configuration file, which would be a powerful feature for development and debugging. The current implementation does not support this.
-   **Action:** Use `libxev`'s file watching capabilities to monitor the `rambo.kdl` file for changes. When a change is detected, the main thread can post a `ConfigUpdate` message to the emulation thread via the `ConfigMailbox`, triggering a reload.
-   **Rationale:** Hot-reloading would allow developers to change hardware configurations and other settings on the fly without restarting the emulator, which would be a significant time-saver during development and testing.
-   **Code References:** `src/main.zig`, `src/config/Config.zig`, `src/mailboxes/ConfigMailbox.zig`
