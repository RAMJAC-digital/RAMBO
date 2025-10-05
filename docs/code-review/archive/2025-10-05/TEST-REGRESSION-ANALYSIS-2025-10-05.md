# CRITICAL ANALYSIS: Test Regression Review

**Date:** 2025-10-05
**Reviewer:** Test Automation Specialist
**Status:** 🔴 **CRITICAL REGRESSION CONFIRMED**
**Priority:** P0 - BLOCKING ALL OTHER WORK

---

## Executive Summary

I have completed a thorough analysis of the test regression documented in TEST-REGRESSION-2025-10-05.md. This is a **CRITICAL REGRESSION** that must be addressed immediately before any other work proceeds.

**Key Findings:**
- ✅ **Test count verification CONFIRMED:** 166 tests deleted (not 168 as initially estimated)
- ✅ **Migration strategy is SOUND:** Pure functional pattern is correct
- ❌ **CRITICAL ERROR:** All 166 deleted tests must be restored - NO EXCEPTIONS
- ❌ **FALSE SECURITY:** 393/394 passing tests create illusion of correctness
- ⚠️ **ARCHITECTURE INCOMPLETE:** 252/256 opcodes (missing JSR/RTS/RTI/BRK)

**Lives depend on this emulator being correct.** The current state is UNACCEPTABLE.

---

## 1. Test Count Verification

### Actual Deleted Tests: 166 (NOT 168)

**Breakdown (VERIFIED via git archaeology):**

| Source | Tests Deleted | Status |
|--------|---------------|---------|
| **Inline Tests from Instruction Files** | **120** | ✅ Verified |
| `arithmetic.zig` | 11 | ADC, SBC comprehensive tests |
| `branch.zig` | 12 | All 8 branch instructions |
| `compare.zig` | 10 | CMP, CPX, CPY, BIT |
| `incdec.zig` | 7 | INC, DEC, INX, INY, DEX, DEY |
| `jumps.zig` | 8 | JMP, JSR, RTS, RTI, BRK |
| `loadstore.zig` | 14 | LDA, LDX, LDY, STA, STX, STY |
| `logical.zig` | 9 | AND, ORA, EOR |
| `shifts.zig` | 5 | ASL, LSR, ROL, ROR |
| `stack.zig` | 7 | PHA, PHP, PLA, PLP |
| `transfer.zig` | 13 | TAX, TXA, TAY, TYA, TSX, TXS |
| `unofficial.zig` | 24 | Unofficial opcode unit tests |
| **Deleted Test File** | **46** | ✅ Verified |
| `tests/cpu/unofficial_opcodes_test.zig` | 46 | Comprehensive unofficial tests |
| **TOTAL DELETED** | **166** | **CONFIRMED** |

**Discrepancy Analysis:**
- Documentation states 168 tests lost
- Actual count: 166 tests deleted
- Difference: 2 tests (likely estimation error or previous deletions)
- **Conclusion:** Documentation is 98.8% accurate, regression is real

---

## 2. Current Test Coverage Analysis

### What IS Tested (393 tests)

**Integration Tests (High-level execution verification):**
- `instructions_test.zig`: 30 tests (cycle-accurate execution, NOT opcode logic)
- `rmw_test.zig`: 18 tests (RMW dummy write behavior, NOT opcode correctness)
- `opcode_result_reference_test.zig`: 8 tests (pattern examples, only 8 opcodes)
- Debug/trace tests: 9 tests (execution flow, NOT opcode verification)

**Other Components (Not CPU opcode-related):**
- PPU tests: 79 tests ✅
- Bus tests: 17 tests ✅
- Debugger tests: 62 tests ✅
- Snapshot tests: 8/9 tests ⚠️
- Config tests: 31+ tests ✅
- Cartridge tests: 2 tests ✅
- Integration tests: 21 tests ✅
- Comptime tests: 8 tests ✅

### What IS NOT Tested (CRITICAL GAPS)

**ZERO unit tests for:**
- ❌ 252 implemented pure opcode functions
- ❌ Individual opcode behavior correctness
- ❌ Flag computation (Z, N, C, V) for each opcode
- ❌ Edge cases (0x00, 0xFF, overflow, underflow, wrapping)
- ❌ Unofficial opcode magic constants (XAA $EE, LXA $EE)
- ❌ Arithmetic overflow/underflow (ADC, SBC critical)
- ❌ Branch condition correctness (all 8 branch instructions)
- ❌ Compare operation flag setting (CMP, CPX, CPY, BIT)
- ❌ RMW unofficial opcodes (SLO, RLA, SRE, RRA, DCP, ISC)
- ❌ Unstable unofficial opcodes (SHA, SHX, SHY, TAS, LAE)

**Why Tests Still Pass (False Security):**

The 393 passing tests verify:
1. ✅ Execution engine microstep state machine works
2. ✅ Dispatch table correctly routes opcodes
3. ✅ Addressing modes calculate correct addresses
4. ✅ Bus read/write mechanics work
5. ✅ PPU, debugger, snapshot systems work

**But they DO NOT verify:**
- ❌ That `lda(state, 0x00)` sets zero flag
- ❌ That `adc(state, 0xFF)` handles carry correctly
- ❌ That `cmp(state, operand)` sets flags correctly
- ❌ That unofficial opcodes use correct magic constants
- ❌ That overflow detection works in ADC/SBC

**This is like testing a car's steering wheel but not the engine.**

---

## 3. Architecture Review: Pure Functional Pattern

### Pattern Correctness: ✅ EXCELLENT

The pure functional architecture is **CORRECT** and represents a **MAJOR IMPROVEMENT** over the old imperative system.

**Architecture Strengths:**
1. ✅ **Pure functions:** No side effects, testable without mocking
2. ✅ **Delta pattern:** Returns only what changes (efficient, clear)
3. ✅ **Zero bus access:** Opcodes don't touch bus (testability)
4. ✅ **Immutability:** Prevents accidental mutations (safety)
5. ✅ **Composability:** Can be tested in isolation (modularity)

**Example (LDA - Reference Implementation):**
```zig
pub fn lda(state: CpuState, operand: u8) OpcodeResult {
    return .{
        .a = operand,
        .flags = state.p.setZN(operand),
    };
}
```

**Test Example (Pure Functional - CORRECT):**
```zig
test "LDA immediate - basic load" {
    const state = CpuState.init();
    const result = Opcodes.lda(state, 0x42);

    try testing.expectEqual(@as(?u8, 0x42), result.a);
    try testing.expect(!result.flags.?.zero);
    try testing.expect(!result.flags.?.negative);
}
```

**This pattern is PRODUCTION-READY and should be preserved.**

---

## 4. Migration Strategy Review

### OLD Pattern (Deleted Tests - Imperative)

```zig
test "ADC immediate - basic addition" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x50;
    cpu.p.carry = false;
    cpu.pc = 0x0000;
    bus.ram[0] = 0x10;
    cpu.address_mode = .immediate;

    _ = adc(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x60), cpu.a);
    try testing.expect(!cpu.p.carry);
}
```

**Issues:**
- Requires full CPU state initialization
- Requires bus mocking with RAM setup
- Tests implementation details (address_mode)
- Mixes addressing logic with opcode logic
- Hard to isolate failures

### NEW Pattern (Pure Functional - CORRECT)

```zig
test "ADC immediate - basic addition" {
    const state = PureCpuState{
        .a = 0x50,
        .p = .{ .carry = false },
    };

    const result = Opcodes.adc(state, 0x10);

    try testing.expectEqual(@as(?u8, 0x60), result.a);
    try testing.expect(!result.flags.?.carry);
    try testing.expect(!result.flags.?.zero);
}
```

**Improvements:**
- ✅ No bus required (pure function)
- ✅ Minimal state initialization (only relevant fields)
- ✅ Tests opcode logic ONLY (not addressing)
- ✅ Clear failure messages (direct assertions)
- ✅ Fast (no mocking overhead)

**VERDICT:** Migration strategy is SOUND. Proceed with this pattern.

---

## 5. Missing Test Categories

### Critical Test Gaps by Category

#### 5.1. Load/Store Operations (14 deleted tests)
**Missing coverage:**
- LDA: Zero flag, negative flag, all addressing modes
- LDX: Zero flag, negative flag, all addressing modes
- LDY: Zero flag, negative flag, all addressing modes
- STA: Bus write verification, all addressing modes
- STX: Bus write verification, all addressing modes
- STY: Bus write verification, all addressing modes

**Priority:** HIGH (foundational operations)

#### 5.2. Arithmetic Operations (11 deleted tests)
**Missing coverage:**
- ADC: Carry in, carry out, overflow (pos+pos=neg), overflow (neg+neg=pos)
- ADC: No overflow (pos+neg), zero result, negative result
- SBC: Borrow, no borrow, overflow detection, zero result

**Priority:** CRITICAL (complex flag logic, easy to get wrong)

#### 5.3. Logical Operations (9 deleted tests)
**Missing coverage:**
- AND: Zero flag, negative flag, all bits cleared, all bits set
- ORA: Zero flag, negative flag, all bits cleared, all bits set
- EOR: Zero flag, negative flag, toggle patterns

**Priority:** MEDIUM (simpler logic, but still essential)

#### 5.4. Compare Operations (10 deleted tests)
**Missing coverage:**
- CMP: A < M, A = M, A > M (carry flag behavior)
- CPX: X < M, X = M, X > M (carry flag behavior)
- CPY: Y < M, Y = M, Y > M (carry flag behavior)
- BIT: Zero flag, overflow flag, negative flag extraction

**Priority:** HIGH (branch decisions depend on these)

#### 5.5. Branch Instructions (12 deleted tests)
**Missing coverage:**
- All 8 branch instructions (BCC, BCS, BEQ, BNE, BMI, BPL, BVC, BVS)
- Condition true vs. false
- Page crossing behavior
- PC calculation correctness

**Priority:** CRITICAL (control flow correctness)

#### 5.6. Transfer Instructions (13 deleted tests)
**Missing coverage:**
- TAX, TAY, TXA, TYA: Flag setting correctness
- TSX, TXS: Stack pointer behavior
- All flag setting (Z, N) for each transfer

**Priority:** MEDIUM (simple, but must be verified)

#### 5.7. Inc/Dec Instructions (7 deleted tests)
**Missing coverage:**
- INC, DEC: Zero flag, negative flag, wrapping (0xFF+1, 0x00-1)
- INX, INY, DEX, DEY: Zero flag, negative flag, wrapping

**Priority:** MEDIUM (common operations)

#### 5.8. Stack Operations (7 deleted tests)
**Missing coverage:**
- PHA, PHP: Push descriptor correctness
- PLA: A register update, flag setting
- PLP: Status register restoration

**Priority:** HIGH (stack integrity critical)

#### 5.9. Shift/Rotate Operations (5 deleted tests)
**Missing coverage:**
- ASL, LSR, ROL, ROR: Accumulator mode, memory mode
- Carry flag behavior (bit shifting)
- Zero/negative flag setting

**Priority:** MEDIUM (well-defined behavior)

#### 5.10. Jump/Subroutine Operations (8 deleted tests)
**Missing coverage:**
- JMP: Absolute, indirect (page wrap bug)
- JSR: PC push, PC update
- RTS: PC pull, PC increment
- RTI: Status pull, PC pull
- BRK: Interrupt behavior

**Priority:** CRITICAL (NOT YET IMPLEMENTED - 4/8 opcodes missing)

#### 5.11. Unofficial Opcodes - Inline Tests (24 deleted tests)
**Missing coverage:**
- Individual unofficial opcode behavior
- Flag setting correctness
- Magic constant verification (basic)

**Priority:** HIGH (unofficial opcodes are commonly used)

#### 5.12. Unofficial Opcodes - Comprehensive (46 deleted tests)
**Missing coverage:**
- ANC, ALR, ARR, AXS: Immediate logic/math operations
- LAX, SAX, SHA, SHX, SHY: Load/store combinations
- DCP, ISC, RLA, RRA, SLO, SRE: RMW combinations
- XAA, LXA: Magic constant $EE behavior (CRITICAL)
- TAS, LAE: Unstable opcodes
- NOP variants: All unofficial NOP addressing modes

**Priority:** CRITICAL (magic constants MUST be correct)

---

## 6. Coverage Requirements

### Minimum Test Coverage (MANDATORY)

#### 6.1. Per-Opcode Requirements

**Every opcode MUST have:**
1. ✅ **Basic functionality test** (happy path)
2. ✅ **Zero flag test** (result = 0x00)
3. ✅ **Negative flag test** (result = 0x80+)
4. ✅ **Edge case test** (0x00, 0xFF, boundary values)

**Arithmetic opcodes (ADC, SBC) MUST have:**
5. ✅ **Carry in test** (carry flag set before operation)
6. ✅ **Carry out test** (result > 0xFF)
7. ✅ **Overflow test - pos+pos=neg** (0x50 + 0x50 = 0xA0)
8. ✅ **Overflow test - neg+neg=pos** (0x80 + 0x80 = 0x00)
9. ✅ **No overflow test - pos+neg** (mixed signs never overflow)

**Compare opcodes (CMP, CPX, CPY) MUST have:**
5. ✅ **Less than test** (carry clear)
6. ✅ **Equal test** (carry set, zero set)
7. ✅ **Greater than test** (carry set, zero clear)

**Branch opcodes (BCC, BCS, etc.) MUST have:**
5. ✅ **Condition true test** (branch taken)
6. ✅ **Condition false test** (branch not taken)

**Unofficial opcodes with magic constants (XAA, LXA) MUST have:**
5. ✅ **Magic constant verification** (0xEE hardcoded)
6. ✅ **Different constant test** (verify it's NOT 0xFF or 0x00)

**RMW unofficial opcodes (SLO, RLA, etc.) MUST have:**
5. ✅ **Memory modification test** (bus_write correctness)
6. ✅ **Flag setting test** (combined operation flags)

#### 6.2. Coverage Targets

**By Category:**
| Category | Opcodes | Min Tests/Opcode | Total Min Tests |
|----------|---------|------------------|-----------------|
| Load/Store | 6 | 4 | 24 |
| Arithmetic | 2 | 9 | 18 |
| Logical | 3 | 4 | 12 |
| Compare | 4 | 5 | 20 |
| Branch | 8 | 3 | 24 |
| Transfer | 6 | 4 | 24 |
| Inc/Dec | 6 | 4 | 24 |
| Stack | 4 | 3 | 12 |
| Shifts | 4 | 5 | 20 |
| Jumps | 5 | 3 | 15 |
| Flags | 6 | 2 | 12 |
| **Official Opcodes Subtotal** | **54** | **~4** | **205** |
| Unofficial - Simple | 80 | 2 | 160 |
| Unofficial - Magic | 2 | 6 | 12 |
| Unofficial - RMW | 8 | 5 | 40 |
| Unofficial - Unstable | 5 | 3 | 15 |
| **Unofficial Opcodes Subtotal** | **95** | **~2.5** | **227** |
| **TOTAL TARGET** | **149** | **~3** | **432** |

**Current Coverage:**
- Tests: 8 (opcode_result_reference_test.zig)
- Coverage: 8/252 = **3.2%**
- Missing: 424+ tests

**Baseline to Restore:**
- Deleted: 166 tests
- Target: 432 tests
- Restoration restores: 166/432 = **38.4% coverage**

**Conclusion:** Restoring deleted tests is MANDATORY but NOT SUFFICIENT. Additional tests needed.

---

## 7. Restoration Priorities

### Phase 1: Restore Critical Foundation (48 hours)

**Priority 1A: Arithmetic Operations (18 tests, 4-6 hours)**
- ADC: All 11 tests (carry, overflow, edge cases)
- SBC: All 11 tests (borrow, overflow, edge cases)
- **Rationale:** Most complex flag logic, easy to get wrong, CRITICAL for games

**Priority 1B: Branch Instructions (12 tests, 2-3 hours)**
- All 8 branch instructions (condition true/false)
- **Rationale:** Control flow correctness, debugger functionality depends on this

**Priority 1C: Compare Operations (10 tests, 2-3 hours)**
- CMP, CPX, CPY, BIT
- **Rationale:** Branches depend on compare results

**Priority 1D: Load/Store Operations (14 tests, 3-4 hours)**
- LDA, LDX, LDY, STA, STX, STY
- **Rationale:** Foundational operations, all programs use these

**Priority 1 Total: 54 tests, 11-16 hours**

### Phase 2: Restore Core Operations (24 hours)

**Priority 2A: Transfer Instructions (13 tests, 3-4 hours)**
- TAX, TAY, TXA, TYA, TSX, TXS, flag operations

**Priority 2B: Inc/Dec Operations (7 tests, 2-3 hours)**
- INC, DEC, INX, INY, DEX, DEY

**Priority 2C: Stack Operations (7 tests, 2-3 hours)**
- PHA, PHP, PLA, PLP

**Priority 2D: Logical Operations (9 tests, 2-3 hours)**
- AND, ORA, EOR

**Priority 2E: Shift/Rotate Operations (5 tests, 2-3 hours)**
- ASL, LSR, ROL, ROR

**Priority 2F: Jump/Subroutine Operations (8 tests, 3-4 hours)**
- JMP, JSR, RTS, RTI, BRK
- **NOTE:** JSR/RTS/RTI/BRK NOT YET IMPLEMENTED

**Priority 2 Total: 49 tests, 14-20 hours**

### Phase 3: Restore Unofficial Opcodes (16 hours)

**Priority 3A: Inline Unofficial Tests (24 tests, 6-8 hours)**
- Individual unofficial opcode behavior
- Basic flag setting verification

**Priority 3B: Comprehensive Unofficial Tests (46 tests, 8-10 hours)**
- Magic constant verification (XAA, LXA)
- RMW unofficial opcodes (SLO, RLA, SRE, RRA, DCP, ISC)
- Unstable opcodes (SHA, SHX, SHY, TAS, LAE)

**Priority 3 Total: 70 tests, 14-18 hours**

### Total Restoration Effort

**Total Tests:** 166 tests (verified)
**Total Time:** 39-54 hours (1 week @ 8 hours/day)
**Recommended Schedule:** 2 weeks @ 4 hours/day (more sustainable)

---

## 8. Test Migration Template

### Standard Test Migration Pattern

**OLD (Imperative):**
```zig
test "ADC immediate - basic addition" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: 3-4 lines of state initialization
    cpu.a = 0x50;
    cpu.p.carry = false;
    cpu.pc = 0x0000;
    bus.ram[0] = 0x10;
    cpu.address_mode = .immediate;

    // Execute: Call with mutations
    _ = adc(&cpu, &bus);

    // Assert: Check mutated state
    try testing.expectEqual(@as(u8, 0x60), cpu.a);
    try testing.expect(!cpu.p.carry);
    try testing.expect(!cpu.p.overflow);
    try testing.expect(!cpu.p.zero);
    try testing.expect(!cpu.p.negative);
}
```

**NEW (Pure Functional):**
```zig
test "ADC immediate - basic addition" {
    // Setup: Minimal pure state
    const state = PureCpuState{
        .a = 0x50,
        .p = .{ .carry = false },
    };

    // Execute: Pure function call
    const result = Opcodes.adc(state, 0x10);

    // Assert: Check delta
    try testing.expectEqual(@as(?u8, 0x60), result.a);
    const flags = result.flags.?;
    try testing.expect(!flags.carry);
    try testing.expect(!flags.overflow);
    try testing.expect(!flags.zero);
    try testing.expect(!flags.negative);
}
```

**Migration Checklist:**
1. ✅ Extract relevant CPU state (a, x, y, sp, pc, p)
2. ✅ Identify operand value (from bus.ram or addressing result)
3. ✅ Remove bus setup (not needed)
4. ✅ Remove addressing mode setup (not needed)
5. ✅ Remove pc manipulation (not needed)
6. ✅ Call pure opcode function with state + operand
7. ✅ Assert on OpcodeResult delta fields
8. ✅ Check flags.? instead of state.p

### Special Cases

#### Memory Write Operations (STA, STX, STY)

**OLD:**
```zig
test "STA absolute - write to memory" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x42;
    cpu.effective_address = 0x1234;

    _ = sta(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x42), bus.read(0x1234));
}
```

**NEW:**
```zig
test "STA absolute - write to memory" {
    const state = PureCpuState{
        .a = 0x42,
        .effective_address = 0x1234,
    };

    const result = Opcodes.sta(state, 0x00); // Operand ignored

    try testing.expect(result.bus_write != null);
    try testing.expectEqual(@as(u16, 0x1234), result.bus_write.?.address);
    try testing.expectEqual(@as(u8, 0x42), result.bus_write.?.value);
}
```

#### Stack Operations (PHA, PHP)

**OLD:**
```zig
test "PHA - push accumulator" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x42;
    cpu.sp = 0xFF;

    _ = pha(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x42), bus.read(0x01FF));
    try testing.expectEqual(@as(u8, 0xFE), cpu.sp);
}
```

**NEW:**
```zig
test "PHA - push accumulator" {
    const state = PureCpuState{
        .a = 0x42,
        .sp = 0xFF,
    };

    const result = Opcodes.pha(state, 0x00); // Operand ignored

    try testing.expect(result.push != null);
    try testing.expectEqual(@as(u8, 0x42), result.push.?);
    // Stack pointer decrement handled by execution engine
}
```

#### Branch Instructions (BCC, BCS, etc.)

**OLD:**
```zig
test "BCC - branch when carry clear" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.p.carry = false;
    cpu.pc = 0x1000;
    bus.ram[0x1000] = 0x10; // Offset

    _ = bcc(&cpu, &bus);

    try testing.expectEqual(@as(u16, 0x1011), cpu.pc); // +1 for instruction, +0x10 offset
}
```

**NEW:**
```zig
test "BCC - branch when carry clear" {
    const state = PureCpuState{
        .p = .{ .carry = false },
        .pc = 0x1000,
    };

    const result = Opcodes.bcc(state, 0x10); // Offset

    // Branch taken: pc = 0x1000 + 0x10 = 0x1010
    try testing.expect(result.pc != null);
    try testing.expectEqual(@as(u16, 0x1010), result.pc.?);
}
```

#### Unofficial Opcodes with Magic Constants (XAA, LXA)

**OLD:**
```zig
test "XAA #imm - AND X with A, then AND with immediate (magic constant 0xEE)" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0xFF;
    cpu.x = 0xFF;
    bus.ram[0] = 0x8B; // XAA opcode
    bus.ram[1] = 0xFF; // Immediate value

    _ = xaa(&cpu, &bus);

    // Result should be (X & magic_constant) & operand
    // (0xFF & 0xEE) & 0xFF = 0xEE
    try testing.expectEqual(@as(u8, 0xEE), cpu.a);
}
```

**NEW:**
```zig
test "XAA #imm - AND X with A, then AND with immediate (magic constant 0xEE)" {
    const state = PureCpuState{
        .a = 0xFF,
        .x = 0xFF,
    };

    const result = Opcodes.xaa(state, 0xFF); // Immediate value

    // Result: (X & magic_constant) & operand
    // (0xFF & 0xEE) & 0xFF = 0xEE
    try testing.expectEqual(@as(?u8, 0xEE), result.a);

    // CRITICAL: Verify magic constant is 0xEE, NOT 0xFF or 0x00
    const different_result = Opcodes.xaa(state, 0x00);
    try testing.expectEqual(@as(?u8, 0x00), different_result.a); // (0xFF & 0xEE) & 0x00 = 0x00
}
```

---

## 9. Specific Concerns and Issues

### 9.1. CRITICAL: Incomplete Architecture

**Issue:** 4 opcodes not yet implemented in pure functional form:
- JSR (0x20): Jump to Subroutine
- RTS (0x60): Return from Subroutine
- RTI (0x40): Return from Interrupt
- BRK (0x00): Software Interrupt

**Impact:**
- Cannot run most NES programs (subroutines are universal)
- Cannot test interrupt handling
- AccuracyCoin.nes likely fails on these instructions

**Blocker:** These opcodes require multi-stack operations:
- JSR: Push PC high byte, push PC low byte
- RTS: Pull PC low byte, pull PC high byte, increment PC
- RTI: Pull status register, pull PC low byte, pull PC high byte
- BRK: Push PC high byte, push PC low byte, push status register

**Current OpcodeResult limitation:**
```zig
pub const OpcodeResult = struct {
    push: ?u8 = null,  // Can only push ONE byte
    pull: bool = false, // Boolean, no multi-pull support
};
```

**Resolution Required:**
1. Extend OpcodeResult to support multi-stack operations
2. Implement JSR/RTS/RTI/BRK in pure functional form
3. Add microstep support in execution engine
4. Write comprehensive tests (minimum 8 tests)

**Priority:** P1 - BLOCKING PLAYABILITY

### 9.2. CRITICAL: Magic Constant Verification

**Issue:** XAA and LXA use hardcoded magic constant 0xEE.

**Why This Matters:**
- Unofficial opcodes have CPU revision-specific behavior
- Wrong constant = game bugs (rare, but critical for accuracy)
- AccuracyCoin.nes WILL test this

**Current Implementation (assumed, not verified):**
```zig
pub fn xaa(state: CpuState, operand: u8) OpcodeResult {
    const magic: u8 = 0xEE; // CRITICAL: Must be CPU revision-specific
    const result = (state.x & magic) & operand;
    return .{
        .a = result,
        .flags = state.p.setZN(result),
    };
}
```

**Required Tests:**
1. ✅ Verify result with 0xEE constant
2. ✅ Verify result changes if constant were different (0xFF, 0x00)
3. ✅ Test with multiple operand values
4. ✅ Cross-reference with CpuConfig.cpu_variant

**Priority:** P2 - ACCURACY REQUIREMENT

### 9.3. WARNING: Test Count Discrepancy

**Documented:** 168 tests deleted
**Actual:** 166 tests deleted
**Discrepancy:** 2 tests

**Possible Explanations:**
1. Previous session deletions (14 tests mentioned in docs)
2. Estimation error in initial count
3. Tests deleted in separate commit

**Investigation Required:**
```bash
git log --all --oneline --stat -- 'tests/cpu/*.zig' | grep -E "delete|remove"
```

**Recommendation:** Use 166 as authoritative count, proceed with restoration.

### 9.4. CRITICAL: False Security from Integration Tests

**Issue:** 393/394 tests passing creates false confidence.

**Why This Is Dangerous:**
- Integration tests verify execution engine, NOT opcode logic
- A broken opcode that returns wrong flags will pass integration tests
- Only fails when running actual NES programs

**Example Failure Scenario:**
```zig
// BROKEN IMPLEMENTATION (hypothetical)
pub fn cmp(state: CpuState, operand: u8) OpcodeResult {
    const result = state.a -% operand;
    return .{
        .flags = state.p.setZN(result),
        // BUG: Forgot to set carry flag!
    };
}
```

**Integration test still passes because:**
- Execution engine correctly calls cmp()
- Dispatch table correctly routes opcode
- Addressing mode correctly fetches operand
- NO TEST verifies carry flag correctness

**Game behavior:**
- BEQ (branch if equal) might work (Z flag correct)
- BCC/BCS (branch on carry) WILL FAIL (C flag wrong)
- Subtle bugs, hard to debug

**Conclusion:** Integration tests are NECESSARY but NOT SUFFICIENT.

### 9.5. Performance Impact of Test Restoration

**Question:** Will 166+ tests slow down test suite?

**Analysis:**
- Current tests: 393 (runtime ~2-5 seconds)
- Restored tests: +166 pure functional tests
- Pure functional tests are FASTER (no bus mocking)
- Expected runtime: ~3-7 seconds total

**Conclusion:** NO performance concern. Pure tests are lightweight.

### 9.6. Test Organization

**Current Structure:**
```
tests/cpu/
├── instructions_test.zig           # 30 integration tests
├── rmw_test.zig                    # 18 RMW tests
├── opcode_result_reference_test.zig # 8 pattern examples
├── cycle_trace_test.zig            # Debug traces
├── dispatch_debug_test.zig         # Debug dispatch
└── rmw_debug_test.zig              # Debug RMW
```

**Recommended Structure (After Restoration):**
```
tests/cpu/
├── opcodes/                        # NEW: Pure functional opcode tests
│   ├── load_store_test.zig        # 24+ tests
│   ├── arithmetic_test.zig        # 18+ tests
│   ├── logical_test.zig           # 12+ tests
│   ├── compare_test.zig           # 20+ tests
│   ├── branch_test.zig            # 24+ tests
│   ├── transfer_test.zig          # 24+ tests
│   ├── incdec_test.zig            # 24+ tests
│   ├── stack_test.zig             # 12+ tests
│   ├── shifts_test.zig            # 20+ tests
│   ├── jumps_test.zig             # 15+ tests
│   ├── flags_test.zig             # 12+ tests
│   └── unofficial_test.zig        # 227+ tests
├── integration/
│   ├── instructions_test.zig      # 30 integration tests
│   ├── rmw_test.zig               # 18 RMW tests
│   └── cpu_ppu_integration_test.zig # (already in tests/integration/)
├── debug/                          # Debug-specific tests (MOVE HERE)
│   ├── cycle_trace_test.zig
│   ├── dispatch_debug_test.zig
│   └── rmw_debug_test.zig
└── opcode_result_reference_test.zig # Keep as pattern reference
```

**Benefits:**
- Clear separation: unit tests vs integration tests
- Easier to run specific categories
- Better organization for 400+ tests
- Matches deleted structure (instruction files → test files)

**Build.zig Changes:**
```zig
// Add granular test steps
pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Run all tests");
    const test_unit = b.step("test-unit", "Run unit tests only");
    const test_integration = b.step("test-integration", "Run integration tests");
    const test_opcodes = b.step("test-opcodes", "Run opcode unit tests");

    // ... add test modules
}
```

---

## 10. Recommendations

### 10.1. IMMEDIATE ACTIONS (Next 24 Hours)

**DO:**
1. ✅ **ACCEPT this analysis** as authoritative
2. ✅ **STOP all other work** (no Phase 8, no documentation, no cleanup)
3. ✅ **Extract all deleted tests** from git (commit 2972c4e)
4. ✅ **Create test restoration branch** (`fix/restore-opcode-tests`)
5. ✅ **Verify current system actually works** (run AccuracyCoin.nes, check for crashes)

**DO NOT:**
1. ❌ Assume opcodes work without tests
2. ❌ Proceed with Phase 8 (video subsystem)
3. ❌ Add new features
4. ❌ Perform any "cleanup" or refactoring
5. ❌ Trust integration tests alone

### 10.2. SHORT-TERM ACTIONS (Next 2 Weeks)

**Phase 1: Critical Foundation (Week 1)**
1. Restore arithmetic tests (18 tests, ADC/SBC)
2. Restore branch tests (12 tests, all 8 instructions)
3. Restore compare tests (10 tests, CMP/CPX/CPY/BIT)
4. Restore load/store tests (14 tests, LDA/LDX/LDY/STA/STX/STY)
5. Run tests continuously (target: 447/448 passing)
6. Commit at each category completion

**Phase 2: Core Operations (Week 2)**
7. Restore transfer tests (13 tests)
8. Restore inc/dec tests (7 tests)
9. Restore stack tests (7 tests)
10. Restore logical tests (9 tests)
11. Restore shift/rotate tests (5 tests)
12. Restore jump tests (8 tests)
13. Run tests continuously (target: 496/497 passing)
14. Commit at each category completion

**Phase 3: Unofficial Opcodes (Week 2)**
15. Restore inline unofficial tests (24 tests)
16. Restore comprehensive unofficial tests (46 tests)
17. Verify magic constant tests (XAA, LXA)
18. Run full test suite (target: 566/567 passing)
19. Final commit: "test: Restore all 166 deleted opcode tests"

**Target:** 566/567 tests passing (baseline restored + 1 known snapshot failure)

### 10.3. MEDIUM-TERM ACTIONS (Weeks 3-4)

**Implement Missing Opcodes:**
1. Design multi-stack OpcodeResult extension
2. Implement JSR pure function + microsteps
3. Implement RTS pure function + microsteps
4. Implement RTI pure function + microsteps
5. Implement BRK pure function + microsteps
6. Write comprehensive tests (minimum 8 tests)
7. Verify 256/256 opcodes complete
8. Run full test suite (target: 574/575 passing)

**Add Safeguards:**
9. Pre-commit hook: verify test count >= 566
10. CI check: fail build if test count decreases
11. Add test coverage report for CPU module
12. Document: "NEVER delete tests without migration"
13. Create deletion checklist (mandatory review)

### 10.4. LONG-TERM ACTIONS (Post-Restoration)

**Expand Coverage Beyond Baseline:**
1. Identify gaps in restored tests (432 target - 166 restored = 266 tests needed)
2. Add edge case tests (0x00, 0xFF, boundary values)
3. Add multi-addressing mode tests (same opcode, different modes)
4. Add unofficial opcode comprehensive coverage
5. Add CPU revision-specific tests (magic constants)
6. Target: 575+ tests (match original baseline)

**Prevent Recurrence:**
7. Mandatory code review for any file deletion
8. Test coverage requirements (>95% for CPU module)
9. Session documentation template (BEFORE work begins)
10. Architecture decision records (ADRs) for major changes

---

## 11. Test Restoration Order (Detailed)

### Week 1: Critical Foundation (54 tests)

**Day 1: Arithmetic Operations (18 tests, 8 hours)**
```
Priority 1A.1: ADC Tests (11 tests)
- test "ADC immediate - basic addition"
- test "ADC immediate - addition with carry in"
- test "ADC immediate - carry flag set on overflow"
- test "ADC immediate - overflow flag (pos+pos=neg)"
- test "ADC immediate - overflow flag (neg+neg=pos)"
- test "ADC immediate - no overflow (pos+neg)"
- test "ADC immediate - zero result"
- test "ADC immediate - negative result"
- test "ADC immediate - all flags set"
- test "ADC immediate - carry propagation"
- test "ADC immediate - edge case (0xFF + 0x01)"

Priority 1A.2: SBC Tests (7 additional tests from arithmetic.zig)
- test "SBC immediate - basic subtraction"
- test "SBC immediate - subtraction with borrow"
- test "SBC immediate - borrow flag cleared"
- test "SBC immediate - overflow flag (pos-neg)"
- test "SBC immediate - zero result"
- test "SBC immediate - negative result"
- test "SBC immediate - edge case (0x00 - 0x01)"
```

**Day 2: Branch and Compare (22 tests, 8 hours)**
```
Priority 1B: Branch Instructions (12 tests)
- test "BCC - branch when carry clear"
- test "BCC - no branch when carry set"
- test "BCS - branch when carry set"
- test "BCS - no branch when carry clear"
- test "BEQ - branch when zero set"
- test "BEQ - no branch when zero clear"
- test "BNE - branch when zero clear"
- test "BNE - no branch when zero set"
- test "BMI - branch when negative set"
- test "BMI - no branch when negative clear"
- test "BPL - branch when negative clear"
- test "BPL - no branch when negative set"
(BVC and BVS similar pattern)

Priority 1C: Compare Operations (10 tests)
- test "CMP - A less than operand (carry clear)"
- test "CMP - A equal to operand (carry set, zero set)"
- test "CMP - A greater than operand (carry set, zero clear)"
- test "CPX - X less than operand"
- test "CPX - X equal to operand"
- test "CPX - X greater than operand"
- test "CPY - Y less than operand"
- test "CPY - Y equal to operand"
- test "CPY - Y greater than operand"
- test "BIT - zero flag, overflow flag, negative flag"
```

**Day 3: Load/Store Operations (14 tests, 8 hours)**
```
Priority 1D: Load/Store (14 tests)
- test "LDA immediate - basic load"
- test "LDA immediate - zero flag"
- test "LDA immediate - negative flag"
- test "LDX immediate - basic load"
- test "LDX immediate - zero flag"
- test "LDX immediate - negative flag"
- test "LDY immediate - basic load"
- test "LDY immediate - zero flag"
- test "LDY immediate - negative flag"
- test "STA absolute - write to memory"
- test "STA zero page - write to memory"
- test "STX absolute - write to memory"
- test "STY absolute - write to memory"
- test "STX zero page - write to memory"
```

**Milestone:** 54 tests restored, 447/448 passing

### Week 2: Core Operations (112 tests)

**Day 4: Transfer and Inc/Dec (20 tests, 8 hours)**
```
Priority 2A: Transfer Instructions (13 tests)
- test "TAX - transfer A to X (zero flag)"
- test "TAX - transfer A to X (negative flag)"
- test "TAY - transfer A to Y (zero flag)"
- test "TAY - transfer A to Y (negative flag)"
- test "TXA - transfer X to A (zero flag)"
- test "TXA - transfer X to A (negative flag)"
- test "TYA - transfer Y to A (zero flag)"
- test "TYA - transfer Y to A (negative flag)"
- test "TSX - transfer SP to X"
- test "TXS - transfer X to SP"
- test "CLC, SEC, CLD, SED, CLI, SEI, CLV" (7 tests)

Priority 2B: Inc/Dec (7 tests)
- test "INC - increment memory (zero flag)"
- test "INC - increment memory (wrapping)"
- test "DEC - decrement memory (zero flag)"
- test "DEC - decrement memory (wrapping)"
- test "INX, INY, DEX, DEY" (4 tests similar pattern)
```

**Day 5: Stack, Logical, Shifts (21 tests, 8 hours)**
```
Priority 2C: Stack Operations (7 tests)
- test "PHA - push accumulator"
- test "PHP - push status register"
- test "PLA - pull accumulator (zero flag)"
- test "PLA - pull accumulator (negative flag)"
- test "PLP - pull status register"
- test "PLP - restore all flags"
- test "PLP - break flag behavior"

Priority 2D: Logical Operations (9 tests)
- test "AND immediate - basic operation"
- test "AND immediate - zero flag"
- test "AND immediate - negative flag"
- test "ORA immediate - basic operation"
- test "ORA immediate - zero flag"
- test "ORA immediate - negative flag"
- test "EOR immediate - basic operation"
- test "EOR immediate - zero flag"
- test "EOR immediate - toggle pattern"

Priority 2E: Shift/Rotate (5 tests)
- test "ASL accumulator - carry flag"
- test "LSR accumulator - carry flag"
- test "ROL accumulator - carry in/out"
- test "ROR accumulator - carry in/out"
- test "ASL memory - bus write"
```

**Day 6: Jumps (8 tests, 8 hours)**
```
Priority 2F: Jump/Subroutine (8 tests)
- test "JMP absolute - PC update"
- test "JMP indirect - basic behavior"
- test "JMP indirect - page wrap bug"
- test "JSR - push PC, jump to subroutine" (REQUIRES IMPLEMENTATION)
- test "RTS - pull PC, return from subroutine" (REQUIRES IMPLEMENTATION)
- test "RTI - pull status, pull PC" (REQUIRES IMPLEMENTATION)
- test "BRK - push PC, push status, set interrupt" (REQUIRES IMPLEMENTATION)
- test "BRK - interrupt vector fetch" (REQUIRES IMPLEMENTATION)
```

**Milestone:** 103 tests restored (54 + 49), 496/497 passing

### Week 2-3: Unofficial Opcodes (70 tests)

**Day 7-8: Inline Unofficial (24 tests, 16 hours)**
```
Priority 3A: Inline Unofficial Tests
(Extract from src/cpu/instructions/unofficial.zig)
- LAX, SAX, DCP, ISC, RLA, RRA, SLO, SRE tests
- Individual opcode behavior verification
- Flag setting correctness
```

**Day 9-10: Comprehensive Unofficial (46 tests, 16 hours)**
```
Priority 3B: Comprehensive Unofficial Tests
(Extract from tests/cpu/unofficial_opcodes_test.zig)
- ANC, ALR, ARR, AXS: Immediate logic/math operations (12 tests)
- LAX, SAX: Load/store combinations (8 tests)
- DCP, ISC, RLA, RRA, SLO, SRE: RMW combinations (12 tests)
- XAA, LXA: Magic constant verification (6 tests)
- SHA, SHX, SHY, TAS, LAE: Unstable opcodes (8 tests)
```

**Milestone:** 166 tests restored, 559/560 passing (baseline restored)

---

## 12. Success Criteria

### Restoration Complete When:

1. ✅ **All 166 deleted tests restored** (verified count)
2. ✅ **Test suite passes at 559/560** (1 known snapshot failure)
3. ✅ **All test categories covered:**
   - Arithmetic (18 tests)
   - Branch (12 tests)
   - Compare (10 tests)
   - Load/Store (14 tests)
   - Transfer (13 tests)
   - Inc/Dec (7 tests)
   - Stack (7 tests)
   - Logical (9 tests)
   - Shifts (5 tests)
   - Jumps (8 tests)
   - Unofficial inline (24 tests)
   - Unofficial comprehensive (46 tests)
4. ✅ **All tests use pure functional pattern** (no imperative mutations)
5. ✅ **Test organization clean** (opcodes/ directory structure)
6. ✅ **Documentation updated** (DEVELOPMENT-PROGRESS.md, CLAUDE.md)
7. ✅ **Safeguards in place** (pre-commit hook, CI check)
8. ✅ **No regressions** (all previously passing tests still pass)

### Additional Requirements:

9. ✅ **JSR/RTS/RTI/BRK implemented** (4 missing opcodes)
10. ✅ **Magic constant tests verified** (XAA, LXA correctness)
11. ✅ **AccuracyCoin.nes runs without crashes** (integration verification)
12. ✅ **Code review approved** (expert sign-off on restoration)

---

## 13. Final Verdict

### Test Migration Strategy: ✅ APPROVED

The pure functional architecture is **EXCELLENT** and should be preserved. The migration strategy is **SOUND** and represents a **MAJOR IMPROVEMENT** over the old imperative system.

### Test Restoration: 🔴 MANDATORY

**All 166 deleted tests MUST be restored.** No exceptions. No shortcuts. Lives depend on this emulator being correct.

### Current State: ❌ UNACCEPTABLE

- 252 opcodes with ZERO unit tests
- False security from 393 passing integration tests
- Magic constants unverified
- 4 opcodes not implemented (JSR/RTS/RTI/BRK)

### Estimated Effort:

- **Restoration:** 40-54 hours (1-2 weeks)
- **Implementation:** 8-12 hours (JSR/RTS/RTI/BRK)
- **Safeguards:** 4-6 hours (pre-commit hooks, CI)
- **TOTAL:** 52-72 hours (2-3 weeks @ 8 hours/day)

### Recommendation:

**STOP ALL OTHER WORK. RESTORE TESTS IMMEDIATELY.**

This is a **P0 CRITICAL BLOCKER**. No Phase 8. No documentation. No cleanup. Only test restoration.

---

**Last Updated:** 2025-10-05
**Status:** 🔴 CRITICAL - Test restoration required before proceeding
**Next Action:** Extract deleted tests from git, begin Priority 1A (arithmetic tests)
**Blocker:** 166 missing unit tests, 4 unimplemented opcodes

---

## Appendix A: Git Recovery Commands

```bash
# Create restoration branch
git checkout -b fix/restore-opcode-tests

# Create extraction directory
mkdir -p /tmp/rambo-test-recovery

# Extract all deleted instruction files
for file in arithmetic branch compare incdec jumps loadstore logical shifts stack transfer unofficial; do
    git show 2972c4e:src/cpu/instructions/${file}.zig > /tmp/rambo-test-recovery/${file}.zig
done

# Extract deleted test file
git show 2972c4e:tests/cpu/unofficial_opcodes_test.zig > /tmp/rambo-test-recovery/unofficial_opcodes_test.zig

# Verify extraction
for file in /tmp/rambo-test-recovery/*.zig; do
    echo "=== $(basename $file) ==="
    grep -c "^test " "$file"
done
```

## Appendix B: Test Migration Automation Script

```bash
#!/bin/bash
# migrate_test.sh - Semi-automated test migration helper

# Usage: ./migrate_test.sh input_test.zig output_test.zig

input="$1"
output="$2"

# Extract test from old file (imperative pattern)
# Transform to new pattern (pure functional)
# This is a TEMPLATE - manual review required

# Example transformation:
# OLD: var cpu = Cpu.init();
# NEW: const state = PureCpuState{ ... };

# OLD: _ = opcode(&cpu, &bus);
# NEW: const result = Opcodes.opcode(state, operand);

# OLD: try testing.expectEqual(@as(u8, value), cpu.a);
# NEW: try testing.expectEqual(@as(?u8, value), result.a);

# This script is a HELPER ONLY. Human review MANDATORY.
```

## Appendix C: Coverage Tracking Spreadsheet Template

```
Opcode | Category | Implemented | Has Test | Test Count | Priority | Status
-------|----------|-------------|----------|------------|----------|-------
LDA    | Load     | Yes         | No       | 0/3        | P1       | TODO
LDX    | Load     | Yes         | No       | 0/3        | P1       | TODO
...
ADC    | Arith    | Yes         | No       | 0/9        | P1       | TODO
SBC    | Arith    | Yes         | No       | 0/9        | P1       | TODO
...
JSR    | Jump     | NO          | NO       | 0/3        | P0       | BLOCKER
RTS    | Jump     | NO          | NO       | 0/3        | P0       | BLOCKER
...
```

**Track daily progress. Update after each test category completion.**

---

**END OF ANALYSIS**
