# CPU Implementation Status - 2025-10-05

**Status:** 🟡 **Needs Urgent Attention**

## 1. Summary

The CPU has been refactored into a **pure functional architecture**, which is a significant improvement in design. Opcodes are implemented as pure functions that receive state and return a delta of changes (`OpcodeResult`), separating computation from state mutation. This architecture is clean, highly testable, and performant.

However, this major refactoring was incomplete and introduced critical issues:

1.  **`SBC` Bug (FIXED):** The `SBC` instruction had a flawed implementation that produced incorrect carry flag results. This has been corrected.
2.  **Missing Tests (CRITICAL):** 166 unit tests were not migrated, leaving the new implementation largely unverified.
3.  **Incomplete Instruction Set:** 4 essential opcodes (`JSR`, `RTS`, `RTI`, `BRK`) are not yet implemented, as they require multi-byte stack operations not yet supported by the `OpcodeResult` pattern.

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

### 3.2. Implement Missing Opcodes (CRITICAL)

-   **Status:** 🔴 **TODO**
-   **Issue:** `JSR`, `RTS`, `RTI`, and `BRK` are missing.
-   **Action:** The `OpcodeResult` struct and the execution logic in `Logic.zig` must be extended to handle multi-byte pushes and pulls from the stack. Once the architecture supports this, the 4 opcodes must be implemented and thoroughly tested.
-   **Justification:** Without these, the CPU cannot handle subroutines or interrupts, making it unable to run most NES games.

### 3.3. Unstable Opcode Configuration

-   **Status:** 🟡 **TODO**
-   **Issue:** Unofficial opcodes with hardware-variant behavior (e.g., `XAA`, `LXA`) use hardcoded magic constants.
-   **Action:** These opcodes should be made configurable via `CpuConfig` to allow for accurate emulation of different 6502 revisions, which is a requirement for full AccuracyCoin compliance.
-   **Code References:** `src/cpu/opcodes/unofficial.zig`, `src/config/Config.zig`
