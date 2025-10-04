# 06 - Configuration System Review

**Date:** 2025-10-03
**Status:** In Progress

## 1. Summary

The configuration system, based on the `rambo.kdl` file and parsed by `src/config/Config.zig`, is a strong point of the project. It provides a clear and flexible way to define the hardware configuration, which is essential for an accurate, multi-system emulator.

However, the current implementation relies on a manual, line-by-line parsing of the KDL file. This approach is brittle and can be difficult to maintain. The system can be made more robust and easier to use by adopting a proper KDL parsing library and improving the overall design.

## 2. Actionable Items

### 2.1. Use a KDL Parsing Library

*   **Action:** Instead of parsing the KDL file manually, use a dedicated KDL parsing library. There are several available for Zig. This will simplify the code, make it more robust, and reduce the maintenance burden.
*   **Rationale:** A dedicated library will handle all the complexities of KDL parsing, including comments, different data types, and error handling. This will make the configuration loading process more reliable and easier to extend.
*   **Code References:**
    *   `src/config/Config.zig`: The `parseKdl` function.
*   **Status:** **TODO**.

### 2.2. Consolidate Hardware Configuration

*   **Action:** The `final-hybrid-architecture.md` document proposes a `HardwareConfig` struct that consolidates all hardware-related configuration into a single place. This is an excellent idea and should be implemented. The `Config` struct should then hold this `HardwareConfig` struct.
*   **Rationale:** This will create a clear separation between hardware configuration and other settings (e.g., video, audio). It will also make it easier to pass the hardware configuration to the emulation core.
*   **Code References:**
    *   `src/config/Config.zig`: The `Config` struct.
*   **Status:** **TODO**.

### 2.3. Implement Hot-Reloading

*   **Action:** The design documents mention the possibility of hot-reloading the configuration file. This would be a powerful feature for development and debugging. Implement this using `libxev`'s file watching capabilities.
*   **Rationale:** Hot-reloading would allow developers to change the hardware configuration on the fly, without having to restart the emulator. This would be a huge time-saver.
*   **Code References:**
    *   `src/config/Config.zig`: The `Config` struct could have a `reload` method.
    *   `src/io/Runtime.zig`: The I/O thread could watch the configuration file for changes.
*   **Status:** **TODO**.
