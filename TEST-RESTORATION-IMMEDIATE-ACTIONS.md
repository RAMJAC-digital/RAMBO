# IMMEDIATE ACTIONS: Test Restoration

**Date:** 2025-10-05
**Status:** 🔴 **CRITICAL - READ THIS FIRST**
**Time Sensitivity:** Blocking all other work

---

## TL;DR - What You Need to Know

**CRITICAL REGRESSION CONFIRMED:**
- ✅ 166 unit tests were deleted (verified count)
- ❌ CPU opcodes have ZERO unit test coverage
- ❌ 393/394 passing tests create false security
- ❌ Pure functional architecture is CORRECT but UNTESTED
- ⚠️ 4 opcodes not yet implemented (JSR/RTS/RTI/BRK)

**IMMEDIATE ACTIONS:**
1. STOP all other work (no Phase 8, no documentation)
2. Extract deleted tests from git (commit 2972c4e)
3. Begin test restoration (Priority 1A: Arithmetic)
4. Target: 559/560 tests passing (166 tests restored)

**ESTIMATED EFFORT:**
- Restoration: 40-54 hours (1-2 weeks)
- Implementation (missing opcodes): 8-12 hours
- TOTAL: 52-72 hours (2-3 weeks)

---

## Quick Start - Next 30 Minutes

### Step 1: Verify Current State (5 minutes)

```bash
cd /home/colin/Development/RAMBO

# Run test suite - should show 393/394 passing
zig build test 2>&1 | grep -E "passed|failed"

# Count current opcode tests
grep -c "^test " tests/cpu/opcode_result_reference_test.zig
# Expected: 8 tests (only 8 opcodes tested)

# Verify opcodes.zig exists
wc -l src/cpu/opcodes.zig
# Expected: 1250 lines, 65 opcode functions
```

### Step 2: Create Recovery Environment (10 minutes)

```bash
# Create restoration branch
git checkout -b fix/restore-opcode-tests

# Create extraction directory
mkdir -p /tmp/rambo-test-recovery

# Extract all deleted instruction files
for file in arithmetic branch compare incdec jumps loadstore logical shifts stack transfer unofficial; do
    git show 2972c4e:src/cpu/instructions/${file}.zig > /tmp/rambo-test-recovery/${file}.zig
    echo "Extracted: ${file}.zig"
done

# Extract deleted test file
git show 2972c4e:tests/cpu/unofficial_opcodes_test.zig > /tmp/rambo-test-recovery/unofficial_opcodes_test.zig

# Verify extraction
echo ""
echo "=== EXTRACTION VERIFICATION ==="
for file in /tmp/rambo-test-recovery/*.zig; do
    count=$(grep -c "^test " "$file")
    echo "$(basename $file): ${count} tests"
done
```

**Expected Output:**
```
arithmetic.zig: 11 tests
branch.zig: 12 tests
compare.zig: 10 tests
incdec.zig: 7 tests
jumps.zig: 8 tests
loadstore.zig: 14 tests
logical.zig: 9 tests
shifts.zig: 5 tests
stack.zig: 7 tests
transfer.zig: 13 tests
unofficial.zig: 24 tests
unofficial_opcodes_test.zig: 46 tests
TOTAL: 166 tests
```

### Step 3: Review Analysis Document (15 minutes)

```bash
# Read comprehensive analysis
cat docs/code-review/TEST-REGRESSION-ANALYSIS-2025-10-05.md | less

# Key sections to read:
# - Section 1: Test Count Verification (page 1)
# - Section 3: Architecture Review (page 3)
# - Section 8: Test Migration Template (page 8)
# - Section 11: Test Restoration Order (page 11)
```

---

## Next 2 Hours - Priority 1A: Arithmetic Tests

### Task: Restore ADC and SBC Tests (18 tests)

**File to Create:** `tests/cpu/opcodes/arithmetic_test.zig`

**Step 1: Setup Test File (15 minutes)**

```bash
# Create opcodes test directory
mkdir -p tests/cpu/opcodes

# Create arithmetic test file
cat > tests/cpu/opcodes/arithmetic_test.zig << 'EOF'
//! Pure Functional Arithmetic Opcode Tests
//! ADC (Add with Carry) - 11 tests
//! SBC (Subtract with Carry) - 7 tests

const std = @import("std");
const testing = std.testing;

const Opcodes = @import("../../src/cpu/opcodes.zig");
const StateModule = @import("../../src/cpu/State.zig");

const PureCpuState = StateModule.PureCpuState;
const OpcodeResult = StateModule.OpcodeResult;
const StatusFlags = StateModule.StatusFlags;

// ============================================================================
// ADC Tests (11 tests)
// ============================================================================

test "ADC immediate - basic addition" {
    const state = PureCpuState{
        .a = 0x50,
        .p = .{ .carry = false },
    };

    const result = Opcodes.adc(state, 0x10);

    try testing.expectEqual(@as(?u8, 0x60), result.a);
    const flags = result.flags.?;
    try testing.expect(!flags.carry);
    try testing.expect(!flags.overflow);
    try testing.expect(!flags.zero);
    try testing.expect(!flags.negative);
}

// TODO: Add remaining 10 ADC tests
// TODO: Add 7 SBC tests

EOF

# Verify file created
cat tests/cpu/opcodes/arithmetic_test.zig
```

**Step 2: Migrate First ADC Test (30 minutes)**

Open `/tmp/rambo-test-recovery/arithmetic.zig` and manually migrate each test following the pattern:

**OLD (Imperative):**
```zig
test "ADC: addition with carry in" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x50;
    cpu.p.carry = true; // Carry in
    cpu.pc = 0x0000;
    bus.ram[0] = 0x10;
    cpu.address_mode = .immediate;

    _ = adc(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x61), cpu.a);
    try testing.expect(!cpu.p.carry);
}
```

**NEW (Pure Functional):**
```zig
test "ADC immediate - addition with carry in" {
    const state = PureCpuState{
        .a = 0x50,
        .p = .{ .carry = true }, // Carry in
    };

    const result = Opcodes.adc(state, 0x10);

    try testing.expectEqual(@as(?u8, 0x61), result.a);
    const flags = result.flags.?;
    try testing.expect(!flags.carry);
}
```

**Step 3: Migrate All ADC Tests (45 minutes)**

Continue migrating remaining ADC tests from `/tmp/rambo-test-recovery/arithmetic.zig`:
- ADC: carry flag set on overflow
- ADC: overflow flag (pos+pos=neg)
- ADC: overflow flag (neg+neg=pos)
- ADC: no overflow (pos+neg)
- ADC: zero result
- ADC: negative result
- ADC: all flags set
- ADC: carry propagation
- ADC: edge case (0xFF + 0x01)

**Step 4: Migrate SBC Tests (30 minutes)**

Migrate 7 SBC tests from `/tmp/rambo-test-recovery/arithmetic.zig`:
- SBC: basic subtraction
- SBC: subtraction with borrow
- SBC: borrow flag cleared
- SBC: overflow flag (pos-neg)
- SBC: zero result
- SBC: negative result
- SBC: edge case (0x00 - 0x01)

**Step 5: Add to Build System (10 minutes)**

```bash
# Edit build.zig to include new test file
# Add to test step

# Run tests
zig build test 2>&1 | grep -E "passed|failed"

# Expected: 411/412 passing (393 + 18 new tests)
```

**Step 6: Commit (10 minutes)**

```bash
git add tests/cpu/opcodes/arithmetic_test.zig
git add build.zig  # If modified

git commit -m "$(cat <<'EOF'
test(cpu): Restore arithmetic opcode tests (18 tests)

Restored ADC and SBC unit tests from commit 2972c4e.
Migrated from imperative to pure functional pattern.

Tests:
- ADC: 11 tests (carry, overflow, edge cases)
- SBC: 7 tests (borrow, overflow, edge cases)

Pattern: Pure CpuState → opcode function → OpcodeResult delta
No bus mocking required (pure functions).

Progress: 18/166 tests restored (10.8%)
Test count: 411/412 passing

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"

git push origin fix/restore-opcode-tests
```

---

## Daily Schedule (Next 2 Weeks)

### Week 1: Critical Foundation (54 tests)

**Day 1 (Today): Arithmetic (18 tests, 6-8 hours)**
- ✅ Setup recovery environment (30 min)
- ✅ Create opcodes/ test directory
- ✅ Migrate ADC tests (11 tests, 3 hours)
- ✅ Migrate SBC tests (7 tests, 2 hours)
- ✅ Commit + push (30 min)
- **Milestone: 411/412 tests passing**

**Day 2: Branch + Compare Part 1 (22 tests, 6-8 hours)**
- Create `tests/cpu/opcodes/branch_test.zig`
- Migrate all 12 branch tests
- Create `tests/cpu/opcodes/compare_test.zig`
- Migrate 10 compare tests
- Commit + push
- **Milestone: 433/434 tests passing**

**Day 3: Load/Store (14 tests, 6-8 hours)**
- Create `tests/cpu/opcodes/load_store_test.zig`
- Migrate all 14 load/store tests
- Commit + push
- **Milestone: 447/448 tests passing**

### Week 2: Core Operations + Unofficial (112 tests)

**Days 4-6: Core Operations (49 tests)**
- Transfer (13 tests)
- Inc/Dec (7 tests)
- Stack (7 tests)
- Logical (9 tests)
- Shifts (5 tests)
- Jumps (8 tests)
- **Milestone: 496/497 tests passing**

**Days 7-10: Unofficial Opcodes (70 tests)**
- Inline unofficial (24 tests)
- Comprehensive unofficial (46 tests)
- **Milestone: 559/560 tests passing (BASELINE RESTORED)**

---

## Success Metrics

### After 2 Hours (Today):
- ✅ 18 arithmetic tests migrated
- ✅ 411/412 tests passing
- ✅ Pure functional pattern verified working
- ✅ Commit pushed to branch

### After 1 Week:
- ✅ 103 critical tests restored
- ✅ 496/497 tests passing
- ✅ All core opcodes tested

### After 2 Weeks:
- ✅ 166 tests restored (100%)
- ✅ 559/560 tests passing
- ✅ Baseline coverage restored
- ✅ Safeguards in place (pre-commit hook)

---

## Getting Help

### If You Get Stuck:

**Pattern Questions:**
- Read Section 8 of TEST-REGRESSION-ANALYSIS-2025-10-05.md
- See tests/cpu/opcode_result_reference_test.zig for examples
- Follow OLD → NEW transformation template

**Build Issues:**
- Verify import paths: `@import("../../src/cpu/opcodes.zig")`
- Check build.zig includes new test files
- Run `zig build test` to see specific errors

**Test Failures:**
- Compare OLD test expectations with NEW OpcodeResult fields
- Verify flag checks use `result.flags.?` (optional unwrap)
- Check operand value is correct (extracted from bus in OLD tests)

### Red Flags (STOP AND ASK):

- ❌ If tests fail after migration (pattern might be wrong)
- ❌ If test count decreases (regression detector)
- ❌ If unsure about flag computation (arithmetic is tricky)
- ❌ If tempted to skip tests (NO SHORTCUTS)

---

## Critical Reminders

### DO:
1. ✅ Follow the pure functional pattern EXACTLY
2. ✅ Test each migrated file before committing
3. ✅ Commit frequently (every category completion)
4. ✅ Verify test count increases with each commit
5. ✅ Read analysis document for context

### DO NOT:
1. ❌ Skip any tests (ALL 166 must be restored)
2. ❌ Modify opcode implementations (only test migration)
3. ❌ Assume tests are redundant (each tests different behavior)
4. ❌ Work on other features (this is P0 blocker)
5. ❌ Trust integration tests alone (they don't verify opcode logic)

---

## Quick Reference - Migration Pattern

```zig
// BEFORE (Imperative - from deleted files)
test "OpcodeName: description" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x??;
    cpu.p.carry = true/false;
    cpu.pc = 0x0000;
    bus.ram[0] = 0x??;

    _ = opcode(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x??), cpu.a);
    try testing.expect(cpu.p.carry);
}

// AFTER (Pure Functional - new pattern)
test "OpcodeName: description" {
    const state = PureCpuState{
        .a = 0x??,
        .p = .{ .carry = true/false },
    };

    const result = Opcodes.opcode(state, 0x??);

    try testing.expectEqual(@as(?u8, 0x??), result.a);
    const flags = result.flags.?;
    try testing.expect(flags.carry);
}
```

**Key Changes:**
1. `var cpu` → `const state` (immutable)
2. `Cpu.init()` → `PureCpuState{ ... }` (minimal state)
3. No `bus` needed (pure functions)
4. `opcode(&cpu, &bus)` → `Opcodes.opcode(state, operand)`
5. `cpu.a` → `result.a` (optional field)
6. `cpu.p.carry` → `result.flags.?.carry` (unwrap optional)

---

## Resources

- **Comprehensive Analysis:** `docs/code-review/TEST-REGRESSION-ANALYSIS-2025-10-05.md`
- **Original Regression Doc:** `docs/code-review/TEST-REGRESSION-2025-10-05.md`
- **Failed Session Notes:** `docs/implementation/sessions/2025-10-05-architecture-cleanup-FAILED.md`
- **Extracted Tests:** `/tmp/rambo-test-recovery/*.zig`
- **Pattern Reference:** `tests/cpu/opcode_result_reference_test.zig`

---

**START NOW. EVERY HOUR COUNTS.**

Lives depend on this emulator being correct.

---

**Last Updated:** 2025-10-05
**Status:** 🔴 CRITICAL - Begin immediately
**Next Action:** Run extraction script (Step 2 above)
