# Testing Status & Restoration Plan - 2025-10-05


_Historical snapshot: Captures the testing backlog as of 2025-10-05 (pre-configuration rename)._
**Status:** 🔴 **CRITICAL REGRESSION**

## 1. Summary

The project's overall testing strategy and infrastructure are strong. However, a critical regression occurred during the CPU refactoring where **166 opcode-specific unit tests were deleted** and not migrated to the new pure functional architecture.

The existing ~400 integration and system-level tests were insufficient to catch a critical bug in the `SBC` instruction, proving that the lack of unit-level coverage is a severe issue.

**The immediate priority is to restore these 166 tests.**

## 2. Test Coverage Analysis

-   **Current State:** 570/571 passing tests.
-   **Integration Tests (`tests/cpu/instructions_test.zig`):** These tests are valuable for verifying cycle-accurate execution of the *entire* instruction flow (fetch, address, execute). They test the *coordination* of the `Logic.zig` execution engine.
-   **Unit Tests (`tests/cpu/opcodes/*.zig`):** These tests are designed to verify the *computation* of the pure opcode functions. This is where the critical gap exists.

**Conclusion:** The integration tests provide a safety net for the overall system timing and flow, but they do not and cannot validate the logical correctness of each of the 252 implemented opcodes. Only a comprehensive suite of unit tests can do that.

## 3. Test Restoration Plan

The following plan, based on the analysis in `docs/code-review/archive/2025-10-05/TEST-REGRESSION-ANALYSIS-2025-10-05.md`, must be executed.

### 3.1. Migration Pattern

All restored tests must use the new pure functional pattern. This involves creating a `CpuCoreState`, calling the opcode function directly, and asserting against the returned `OpcodeResult` delta.

**Old Imperative Test (Example):**
```zig
// OLD (deleted):
test "ADC immediate - basic addition" {
    var state = CpuState.init();
    var bus = BusState.init();
    // ... setup state and bus ...
    _ = adc(&state, &bus); // Mutates state
    try testing.expectEqual(0x60, state.a);
}
```

**New Pure Functional Test (Required Pattern):**
```zig
// NEW (pure functional):
test "ADC immediate - basic addition" {
    const state = CpuCoreState{ .a = 0x50, .p = .{} };
    const result = Opcodes.adc(state, 0x10); // No mutation
    try testing.expectEqual(@as(?u8, 0x60), result.a);
    try testing.expect(!result.flags.?.carry);
}
```

### 3.2. Restoration Priority

The 166 tests must be restored in an order that prioritizes the most critical and complex instructions first.

1.  **Arithmetic (`ADC`, `SBC`):** Most complex flag logic. The `SBC` bug proved these are high-risk. (Tests already written in `arithmetic_test.zig`, now passing).
2.  **Branches (`BCC`, `BEQ`, etc.):** Critical for control flow.
3.  **Compares (`CMP`, `CPX`, `BIT`):** Critical for branch decisions.
4.  **Load/Store (`LDA`, `STA`, etc.):** Foundational to all operations.
5.  **Other Official Opcodes:** Transfers, stack operations, shifts, etc.
6.  **Unofficial Opcodes:** RMW combos, unstable opcodes, etc.

### 3.3. Test Organization

-   Create a new test file in `tests/cpu/opcodes/` for each corresponding source file in `src/cpu/opcodes/`.
    -   `src/cpu/opcodes/loadstore.zig` → `tests/cpu/opcodes/loadstore_test.zig`
    -   `src/cpu/opcodes/branch.zig` → `tests/cpu/opcodes/branch_test.zig`
    -   etc.
-   This work appears to have been started, but must be completed for all instruction categories.

## 4. Future Safeguards

To prevent this from happening again, the following should be implemented after the test restoration is complete:

1.  **Pre-commit Hook:** Add a script that runs `zig build --summary all test` and fails the commit if the test count decreases.
2.  **CI Check:** Implement a CI job that fails if the test count goes down in a pull request.
3.  **Mandatory Policy:** All future refactoring that involves deleting files containing tests must include a migration plan for those tests, to be verified in code review.
