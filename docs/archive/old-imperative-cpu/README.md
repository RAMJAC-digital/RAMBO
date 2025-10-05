# Old Imperative CPU Implementation (ARCHIVED)

**Date Archived:** 2025-10-05
**Status:** Reference material for test migration
**DO NOT USE:** This code is not part of the active codebase

---

## Purpose

This directory contains the **old imperative CPU instruction implementations** that were replaced by the pure functional architecture in `src/cpu/opcodes.zig`.

These files are preserved as **reference material** for migrating unit tests to the new pure functional API.

---

## Contents

### `implementation/` - Old Instruction Implementations

Contains 11 instruction category files with imperative (mutation-based) implementations:

| File | Tests Inside | Description |
|------|--------------|-------------|
| `arithmetic.zig` | 11 | ADC, SBC tests |
| `loadstore.zig` | 14 | LDA, LDX, LDY, STA, STX, STY tests |
| `logical.zig` | 9 | AND, ORA, EOR tests |
| `compare.zig` | 10 | CMP, CPX, CPY, BIT tests |
| `transfer.zig` | 13 | TAX, TXA, TAY, TYA, TSX, TXS tests |
| `incdec.zig` | 7 | INC, DEC, INX, INY, DEX, DEY tests |
| `stack.zig` | 7 | PHA, PHP, PLA, PLP tests |
| `shifts.zig` | 5 | ASL, LSR, ROL, ROR tests |
| `branch.zig` | 12 | BCC, BCS, BEQ, BNE, BMI, BPL, BVC, BVS tests |
| `jumps.zig` | 8 | JMP, JSR, RTS, RTI, BRK tests |
| `unofficial.zig` | 24 | Unofficial opcode tests |

**Total inline tests:** 120

### `tests/` - Old External Tests

- `unofficial_opcodes_test.zig` - 48 comprehensive unofficial opcode tests

**Total external tests:** 48

**TOTAL TESTS TO MIGRATE:** 168

---

## Old API (Imperative - DEPRECATED)

```zig
// Signature: Mutates state directly, accesses bus
pub fn lda(state: *CpuState, bus: *BusState) bool {
    const value = helpers.readOperand(state, bus);
    state.a = value;  // MUTATION
    state.p.updateZN(state.a);  // MUTATION
    return true;
}
```

**Problems:**
- Direct mutations make testing difficult
- Bus access requires mocking
- Side effects hidden in helpers
- Not thread-safe

---

## New API (Pure Functional - ACTIVE)

```zig
// Signature: Pure function returning delta
pub fn lda(state: CpuState, operand: u8) OpcodeResult {
    return .{
        .a = operand,  // Delta pattern
        .flags = state.p.setZN(operand),  // Pure function
    };
}
```

**Benefits:**
- No mutations, easy to test
- No bus access, no mocking needed
- All changes explicit in return value
- Thread-safe by design

---

## Migration Process

1. **Extract test case:** Understand what old test verified
2. **Convert to pure functional API:**
   - Old: Setup mutable state, call function, check mutations
   - New: Create pure state, call function, check OpcodeResult
3. **Write test using helpers** from `tests/cpu/opcodes/helpers.zig`
4. **Verify test passes** against new implementation

### Example Migration

**Old Test (Imperative):**
```zig
test "LDA: immediate mode" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.address_mode = .immediate;
    state.pc = 0;
    bus.ram[0] = 0x42;

    _ = lda(&state, &bus);  // Mutation happens here

    try testing.expectEqual(@as(u8, 0x42), state.a);
    try testing.expect(!state.p.zero);
    try testing.expect(!state.p.negative);
}
```

**New Test (Pure Functional):**
```zig
test "LDA: loads value and sets flags correctly" {
    const state = helpers.makeState(0, 0, 0, .{});
    const result = Opcodes.lda(state, 0x42);

    try helpers.expectRegister(result, "a", 0x42);
    try helpers.expectFlags(result, helpers.makeFlags(
        false,  // zero
        false,  // negative
        false,  // carry (unchanged)
        false   // overflow (unchanged)
    ));
}
```

---

## Status

- [x] Code archived (2025-10-05)
- [ ] Tests migrated to `tests/cpu/opcodes/`
- [ ] Archive can be deleted after migration complete

---

## References

- New implementation: `src/cpu/opcodes.zig`
- New tests: `tests/cpu/opcodes/*.zig`
- Architecture docs: `docs/code-review/PURE-FUNCTIONAL-ARCHITECTURE.md`
- Migration session: `docs/implementation/sessions/2025-10-05-test-migration-complete.md`
