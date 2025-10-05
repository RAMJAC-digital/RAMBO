# CRITICAL: Test Regression - 168 Unit Tests Deleted

**Date:** 2025-10-05
**Status:** 🔴 **CRITICAL REGRESSION**
**Impact:** 168 opcode unit tests deleted without migration

---

## Executive Summary

During the "clean architecture" restructuring, **168 unit tests were deleted** from the CPU instruction files without being migrated to the new pure functional opcode implementations.

**Current State:**
- ✅ 252/256 opcodes implemented in `src/cpu/opcodes.zig`
- ❌ **ZERO unit tests** for those 252 opcodes
- ❌ 168 tests deleted from old implementation
- ⚠️ Tests passing: 393/394 (down from 575/576)
- ⚠️ **Test loss: 182 tests total**

**This is a CRITICAL regression.** The CPU opcodes are UNTESTED.

---

## Deleted Tests Breakdown

### Inline Tests from Deleted Instruction Files (120 tests)

| File | Tests Deleted | Tested Opcodes |
|------|---------------|----------------|
| `src/cpu/instructions/arithmetic.zig` | 11 | ADC, SBC |
| `src/cpu/instructions/branch.zig` | 12 | BCC, BCS, BEQ, BNE, BMI, BPL, BVC, BVS |
| `src/cpu/instructions/compare.zig` | 10 | CMP, CPX, CPY, BIT |
| `src/cpu/instructions/incdec.zig` | 7 | INC, DEC, INX, INY, DEX, DEY |
| `src/cpu/instructions/jumps.zig` | 8 | JMP, JSR, RTS, RTI, BRK |
| `src/cpu/instructions/loadstore.zig` | 14 | LDA, LDX, LDY, STA, STX, STY |
| `src/cpu/instructions/logical.zig` | 9 | AND, ORA, EOR |
| `src/cpu/instructions/shifts.zig` | 5 | ASL, LSR, ROL, ROR |
| `src/cpu/instructions/stack.zig` | 7 | PHA, PHP, PLA, PLP |
| `src/cpu/instructions/transfer.zig` | 13 | TAX, TXA, TAY, TYA, TSX, TXS |
| `src/cpu/instructions/unofficial.zig` | 24 | LAX, SAX, DCP, ISC, RLA, RRA, SLO, SRE, etc. |
| **TOTAL** | **120** | **~60 unique opcodes** |

### Deleted Test File (48 tests)

- `tests/cpu/unofficial_opcodes_test.zig` - **48 tests**
  - Comprehensive tests for all 105 unofficial opcodes
  - Magic constant verification (XAA, LXA)
  - RMW unofficial opcodes (SLO, RLA, SRE, RRA, DCP, ISC)
  - Unstable opcodes (SHA, SHX, SHY, TAS, LAE)

### Additional Tests Lost (14 tests)

- From previous session cleanup
- Pure equivalence tests

**TOTAL DELETED: 182 tests**

---

## Current Test Coverage

### What IS Tested (393 tests remaining)

**Integration Tests (still passing):**
- `tests/cpu/instructions_test.zig` - 30 tests (high-level cycle-accurate tests)
- `tests/cpu/rmw_test.zig` - 18 tests (RMW dummy write verification)
- `tests/cpu/opcode_result_reference_test.zig` - 8 tests (OpcodeResult pattern examples)
- Various debug/trace tests - 9 tests

**These test the EXECUTION ENGINE, not individual opcodes.**

### What IS NOT Tested (CRITICAL)

**Zero unit tests for:**
- ❌ Pure opcode functions in `src/cpu/opcodes.zig` (252 opcodes)
- ❌ Individual opcode behavior
- ❌ Flag setting correctness (Z, N, C, V)
- ❌ Edge cases (overflow, underflow, page crossing)
- ❌ Unofficial opcode magic constants (XAA $EE, LXA $EE)

---

## Why Tests Still Pass (False Security)

**393/394 tests pass because:**

1. **Integration tests** verify the execution engine works
2. **Dispatch table** correctly routes opcodes
3. **Addressing modes** work correctly
4. **NOT testing** individual opcode logic

**The opcodes MIGHT work (they're implemented), but we have ZERO proof.**

---

## Recovery Plan

### Phase 1: Document Test Requirements (1 hour)

- [x] Create this document
- [ ] List all 252 opcodes needing tests
- [ ] Categorize by complexity (simple, medium, complex)
- [ ] Identify critical opcodes (ADC, SBC, branches, unofficial)

### Phase 2: Restore Deleted Tests (8-12 hours)

**Option A: Git Recovery (RECOMMENDED)**
```bash
# Extract tests from deleted files
git show HEAD:src/cpu/instructions/arithmetic.zig > /tmp/arithmetic_tests.zig
# Port tests to new pure functional pattern
```

**Option B: Rewrite from Scratch**
- Use opcode_result_reference_test.zig as template
- Write comprehensive tests for each opcode

### Phase 3: Verify Coverage (2-4 hours)

- [ ] Run full test suite: target 575+ tests
- [ ] Verify all 252 opcodes have unit tests
- [ ] Test edge cases (0x00, 0xFF, overflow, etc.)
- [ ] Test magic constants for unstable opcodes

### Phase 4: Prevent Future Regressions

- [ ] Add pre-commit hook: verify test count doesn't decrease
- [ ] Require test coverage report for CPU module
- [ ] Document: "NEVER delete tests without migration"

---

## Immediate Actions Required

### 1. STOP Further Work
- ❌ Do NOT proceed with documentation cleanup
- ❌ Do NOT proceed with Phase 2 (JSR/RTS/RTI/BRK)
- ✅ Focus ONLY on restoring test coverage

### 2. Restore Tests (PRIORITY 1)

**Files to restore from git:**
```bash
git show HEAD:src/cpu/instructions/arithmetic.zig
git show HEAD:src/cpu/instructions/branch.zig
git show HEAD:src/cpu/instructions/compare.zig
git show HEAD:src/cpu/instructions/incdec.zig
git show HEAD:src/cpu/instructions/jumps.zig
git show HEAD:src/cpu/instructions/loadstore.zig
git show HEAD:src/cpu/instructions/logical.zig
git show HEAD:src/cpu/instructions/shifts.zig
git show HEAD:src/cpu/instructions/stack.zig
git show HEAD:src/cpu/instructions/transfer.zig
git show HEAD:src/cpu/instructions/unofficial.zig
git show HEAD:tests/cpu/unofficial_opcodes_test.zig
```

**Migration pattern:**
```zig
// OLD (deleted):
test "ADC immediate - basic addition" {
    var state = CpuState.init();
    var bus = BusState.init();
    // ... test with mutations
}

// NEW (pure functional):
test "ADC immediate - basic addition" {
    const state = PureCpuState{ .a = 0x50, .p = .{} };
    const result = Opcodes.adc(state, 0x30);
    try testing.expectEqual(@as(?u8, 0x80), result.a);
    try testing.expect(result.flags.?.negative);
}
```

### 3. Update Documentation

- [ ] Update PURE-FUNCTIONAL-ARCHITECTURE.md with regression
- [ ] Update DEVELOPMENT-PROGRESS.md with critical blocker
- [ ] Mark Phase 1 as INCOMPLETE (missing tests)

---

## Lessons Learned

### Critical Mistakes Made

1. **Deleted tests without verification**
   - Assumed integration tests were sufficient
   - Did not check test count before/after
   - Did not migrate unit tests to new pattern

2. **Failed to document test requirements**
   - No checklist for test migration
   - No verification step for coverage
   - No pre-commit validation

3. **Rushed "cleanup" without understanding impact**
   - Deleted "dead code" that contained critical tests
   - Did not analyze what was being removed
   - Did not verify functionality after deletion

### Prevention Measures

1. **NEVER delete files with tests without migration plan**
2. **ALWAYS verify test count remains stable**
3. **REQUIRE test coverage reports for critical modules**
4. **ADD pre-commit hooks to prevent test loss**

---

## Current State Summary

**Before Cleanup:**
- Tests: 575/576 passing ✅
- Coverage: All opcodes tested ✅

**After "Cleanup":**
- Tests: 393/394 passing ⚠️
- Coverage: **ZERO opcode unit tests** ❌
- Regression: **182 tests lost** 🔴

**Impact:**
- CPU opcodes are **UNTESTED**
- Pure functional pattern has **NO verification**
- Code works (probably) but **ZERO proof**

---

## Next Steps (MANDATORY)

1. **STOP all other work**
2. **Restore 168 deleted tests** from git history
3. **Migrate tests** to pure functional pattern
4. **Verify coverage**: 575+ tests passing
5. **Document recovery** in DEVELOPMENT-PROGRESS.md
6. **Add safeguards** to prevent future test loss

**Estimated Time:** 12-16 hours
**Priority:** CRITICAL - blocking all other work

---

**Last Updated:** 2025-10-05
**Status:** 🔴 CRITICAL REGRESSION - Test restoration required
