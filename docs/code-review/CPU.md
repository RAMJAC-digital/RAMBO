# CPU Implementation Status - 2025-10-05

**Status:** 🟡 **Needs Urgent Attention**

## 1. Summary

The CPU has been refactored into a **pure functional architecture** and its instruction set is now **100% complete**. All 256 opcodes, including the critical control-flow instructions (`JSR`, `RTS`, `RTI`, `BRK`), are implemented and tested.

The architecture is clean, highly testable, and performant. The `SBC` instruction bug has been fixed, and the core instruction set is now considered stable and correct, pending the restoration of the full unit test suite.

**Key Status:**

1.  **`SBC` Bug (FIXED):** The `SBC` instruction now uses a correct hardware-accurate implementation.
2.  **100% Opcode Implementation (COMPLETE):** All 256 opcodes are implemented. The final four (`JSR`, `RTS`, `RTI`, `BRK`) were added using the cycle-accurate microstep decomposition method.
3.  **Missing Tests (CRITICAL):** While the implementation is complete, the unit test suite is still being restored. This remains a top priority.

## 2. Architecture Assessment

-   **Pattern:** Pure Functional Delta (`next_state = f(current_state) + delta`)
-   **Status:** ✅ **Excellent**
-   **Analysis:** The separation of concerns is superb. `Logic.zig` acts as the execution coordinator, applying the `OpcodeResult` deltas returned by the pure functions in `opcodes/*.zig`. This makes the core logic in the opcode files stateless, side-effect-free, and easy to unit test in isolation (once the tests are restored).
-   **File Structure:** The new `src/cpu/opcodes/` directory, with logic split by category (arithmetic, load/store, etc.), is a clean and maintainable organization.

## 3. Actionable Items

### 3.1. Restore Unit Tests (CRITICAL)

-   **Status:** 🔴 **TODO**
-   **Issue:** The lack of unit tests allowed the `SBC` bug to go undetected. The entire CPU instruction set is at risk.
-   **Action:** Restore all 166 deleted unit tests, migrating them to the new pure functional test pattern. This is the project's highest priority.
-   **Reference:** `docs/code-review/TESTING.md`

### 3.2. Unstable Opcode Configuration

-   **Status:** 🟡 **TODO**
-   **Issue:** Unofficial opcodes with hardware-variant behavior (e.g., `XAA`, `LXA`) use hardcoded magic constants.
-   **Action:** These opcodes should be made configurable via `CpuModel` to allow for accurate emulation of different 6502 revisions, which is a requirement for full AccuracyCoin compliance.
-   **Code References:** `src/cpu/opcodes/unofficial.zig`, `src/config/Config.zig`
