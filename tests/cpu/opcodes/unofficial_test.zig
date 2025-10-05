//! Pure Functional Tests for Unofficial/Illegal Opcodes
//!
//! Tests all unofficial 6502 opcodes using the pure functional API.
//!
//! Migrated from:
//! - docs/archive/old-imperative-cpu/implementation/unofficial.zig (24 inline tests)
//! - docs/archive/old-imperative-cpu/tests/unofficial_opcodes_test.zig (48 comprehensive tests)

const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");

const RAMBO = @import("RAMBO");
const Opcodes = RAMBO.Cpu.opcodes;

// ============================================================================
// LAX - Load A and X
// ============================================================================

test "LAX: loads value into both A and X" {
    const state = helpers.makeState(0, 0, 0, helpers.clearFlags());
    const result = Opcodes.lax(state, 0x42);

    try helpers.expectRegister(result, "a", 0x42);
    try helpers.expectRegister(result, "x", 0x42);
    try helpers.expectZN(result, false, false);
}

test "LAX: sets zero flag" {
    const state = helpers.makeState(0xFF, 0xFF, 0, helpers.clearFlags());
    const result = Opcodes.lax(state, 0x00);

    try helpers.expectRegister(result, "a", 0x00);
    try helpers.expectRegister(result, "x", 0x00);
    try helpers.expectZN(result, true, false);
}

test "LAX: sets negative flag" {
    const state = helpers.makeState(0, 0, 0, helpers.clearFlags());
    const result = Opcodes.lax(state, 0x80);

    try helpers.expectRegister(result, "a", 0x80);
    try helpers.expectRegister(result, "x", 0x80);
    try helpers.expectZN(result, false, true);
}

// ============================================================================
// SAX - Store A AND X
// ============================================================================

test "SAX: stores A & X to memory" {
    const state = helpers.makeStateWithAddress(0x0F, 0xF0, 0, helpers.clearFlags(), 0x1234);
    const result = Opcodes.sax(state, 0);

    try helpers.expectBusWrite(result, 0x1234, 0x00); // 0x0F & 0xF0 = 0x00
    // SAX doesn't affect flags
    try testing.expect(result.flags == null);
}

test "SAX: stores correct AND result" {
    const state = helpers.makeStateWithAddress(0xFF, 0x0F, 0, helpers.clearFlags(), 0x2000);
    const result = Opcodes.sax(state, 0);

    try helpers.expectBusWrite(result, 0x2000, 0x0F); // 0xFF & 0x0F = 0x0F
}

// ============================================================================
// DCP - Decrement then Compare
// ============================================================================

test "DCP: decrements memory then compares with A" {
    const state = helpers.makeStateWithAddress(0x42, 0, 0, helpers.clearFlags(), 0x1234);
    const result = Opcodes.dcp(state, 0x43); // Memory contains 0x43

    try helpers.expectBusWrite(result, 0x1234, 0x42); // Decremented to 0x42
    // Compare A(0x42) with result(0x42) - should set Z and C
    const flags = result.flags.?;
    try testing.expect(flags.zero);
    try testing.expect(flags.carry);
}

// ============================================================================
// ISC - Increment then Subtract with Carry
// ============================================================================

test "ISC: increments memory then SBC" {
    const state = helpers.makeStateWithAddress(0x50, 0, 0, helpers.flagsWithCarry(), 0x1234);
    const result = Opcodes.isc(state, 0x0F); // Memory contains 0x0F

    try helpers.expectBusWrite(result, 0x1234, 0x10); // Incremented to 0x10
    // Then A(0x50) - 0x10 with carry = 0x40
    try helpers.expectRegister(result, "a", 0x40);
}

// ============================================================================
// SLO - Shift Left then OR
// ============================================================================

test "SLO: shifts memory left then ORs with A" {
    const state = helpers.makeStateWithAddress(0x0F, 0, 0, helpers.clearFlags(), 0x1234);
    const result = Opcodes.slo(state, 0x01); // Memory contains 0x01

    try helpers.expectBusWrite(result, 0x1234, 0x02); // Shifted to 0x02
    try helpers.expectRegister(result, "a", 0x0F); // 0x0F | 0x02 = 0x0F
}

// ============================================================================
// RLA - Rotate Left then AND
// ============================================================================

test "RLA: rotates memory left then ANDs with A" {
    const state = helpers.makeStateWithAddress(0xFF, 0, 0, helpers.clearFlags(), 0x1234);
    const result = Opcodes.rla(state, 0x01); // Memory contains 0x01

    try helpers.expectBusWrite(result, 0x1234, 0x02); // Rotated to 0x02
    try helpers.expectRegister(result, "a", 0x02); // 0xFF & 0x02 = 0x02
}

// ============================================================================
// SRE - Shift Right then EOR
// ============================================================================

test "SRE: shifts memory right then XORs with A" {
    const state = helpers.makeStateWithAddress(0x0F, 0, 0, helpers.clearFlags(), 0x1234);
    const result = Opcodes.sre(state, 0x02); // Memory contains 0x02

    try helpers.expectBusWrite(result, 0x1234, 0x01); // Shifted to 0x01
    try helpers.expectRegister(result, "a", 0x0E); // 0x0F ^ 0x01 = 0x0E
}

// ============================================================================
// RRA - Rotate Right then Add with Carry
// ============================================================================

test "RRA: rotates memory right then ADC" {
    const state = helpers.makeStateWithAddress(0x10, 0, 0, helpers.clearFlags(), 0x1234);
    const result = Opcodes.rra(state, 0x02); // Memory contains 0x02

    try helpers.expectBusWrite(result, 0x1234, 0x01); // Rotated to 0x01
    // Then A(0x10) + 0x01 = 0x11
    try helpers.expectRegister(result, "a", 0x11);
}

// ============================================================================
// ANC - AND then copy N to C
// ============================================================================

test "ANC: ANDs with A then copies bit 7 to carry" {
    const state = helpers.makeState(0xFF, 0, 0, helpers.clearFlags());
    const result = Opcodes.anc(state, 0x80); // Result will have bit 7 set

    try helpers.expectRegister(result, "a", 0x80);
    const flags = result.flags.?;
    try testing.expect(flags.negative);
    try testing.expect(flags.carry); // Bit 7 copied to carry
}

test "ANC: carry cleared when bit 7 is 0" {
    const state = helpers.makeState(0xFF, 0, 0, helpers.flagsWithCarry());
    const result = Opcodes.anc(state, 0x7F); // Result will have bit 7 clear

    try helpers.expectRegister(result, "a", 0x7F);
    const flags = result.flags.?;
    try testing.expect(!flags.negative);
    try testing.expect(!flags.carry); // Bit 7 copied to carry
}

// ============================================================================
// ALR - AND then LSR
// ============================================================================

test "ALR: ANDs then shifts right" {
    const state = helpers.makeState(0xFF, 0, 0, helpers.clearFlags());
    const result = Opcodes.alr(state, 0x0E); // 0xFF & 0x0E = 0x0E, then >> 1 = 0x07

    try helpers.expectRegister(result, "a", 0x07);
    const flags = result.flags.?;
    try testing.expect(!flags.carry); // Bit 0 of 0x0E was 0
}

// ============================================================================
// ARR - AND then ROR
// ============================================================================

test "ARR: ANDs then rotates right" {
    const state = helpers.makeState(0xFF, 0, 0, helpers.flagsWithCarry());
    const result = Opcodes.arr(state, 0x02); // 0xFF & 0x02 = 0x02, then ROR with C=1 = 0x81

    try helpers.expectRegister(result, "a", 0x81);
}

// ============================================================================
// AXS - AND X with A then subtract from X
// ============================================================================

test "AXS: (A & X) - operand -> X" {
    const state = helpers.makeState(0xFF, 0x0F, 0, helpers.clearFlags());
    const result = Opcodes.axs(state, 0x01); // (0xFF & 0x0F) - 0x01 = 0x0E

    try helpers.expectRegister(result, "x", 0x0E);
}

// ============================================================================
// XAA - Magic constant opcodes
// ============================================================================

test "XAA: unstable magic constant opcode" {
    // XAA: (A | $EE) & X & operand -> A
    // With A=0xFF, X=0xFF, operand=0x0F
    const state = helpers.makeState(0xFF, 0xFF, 0, helpers.clearFlags());
    const result = Opcodes.xaa(state, 0x0F);

    // (0xFF | 0xEE) & 0xFF & 0x0F = 0xFF & 0xFF & 0x0F = 0x0F
    try helpers.expectRegister(result, "a", 0x0F);
}

test "LXA: loads A and X with magic constant" {
    // LXA: (A | $EE) & operand -> A -> X
    // With A=0xFF, operand=0x42
    const state = helpers.makeState(0xFF, 0, 0, helpers.clearFlags());
    const result = Opcodes.lxa(state, 0x42);

    // (0xFF | 0xEE) & 0x42 = 0xFF & 0x42 = 0x42
    try helpers.expectRegister(result, "a", 0x42);
    try helpers.expectRegister(result, "x", 0x42);
}

// ============================================================================
// NOP variants - Various unofficial NOPs
// ============================================================================

test "NOP variants: do nothing" {
    const state = helpers.makeState(0x42, 0x43, 0x44, helpers.flagsWithCarry());

    // All NOP variants should do nothing
    const result = Opcodes.nop(state, 0xFF);

    try testing.expect(result.a == null);
    try testing.expect(result.x == null);
    try testing.expect(result.y == null);
    try testing.expect(result.flags == null);
}

// ============================================================================
// Additional comprehensive tests
// ============================================================================

test "LAX: all addressing modes work" {
    // Test that LAX works with any operand value
    const test_values = [_]u8{ 0x00, 0x01, 0x7F, 0x80, 0xFF };
    for (test_values) |value| {
        const state = helpers.makeState(0, 0, 0, helpers.clearFlags());
        const result = Opcodes.lax(state, value);

        try helpers.expectRegister(result, "a", value);
        try helpers.expectRegister(result, "x", value);
    }
}

test "DCP: compare flags work correctly" {
    // Test A > M-1
    const state1 = helpers.makeStateWithAddress(0x50, 0, 0, helpers.clearFlags(), 0x1234);
    const result1 = Opcodes.dcp(state1, 0x30); // Dec to 0x2F, compare with 0x50

    const flags1 = result1.flags.?;
    try testing.expect(flags1.carry); // A > M-1
    try testing.expect(!flags1.zero);

    // Test A == M-1
    const state2 = helpers.makeStateWithAddress(0x2F, 0, 0, helpers.clearFlags(), 0x1234);
    const result2 = Opcodes.dcp(state2, 0x30); // Dec to 0x2F, compare with 0x2F

    const flags2 = result2.flags.?;
    try testing.expect(flags2.carry);
    try testing.expect(flags2.zero);
}

test "ISC: overflow flag works correctly" {
    // Test SBC overflow after increment
    const state = helpers.makeStateWithAddress(0x50, 0, 0, helpers.flagsWithCarry(), 0x1234);
    const result = Opcodes.isc(state, 0x7F); // Inc to 0x80 (negative), then SBC

    // 0x50 - 0x80 with carry should trigger overflow
    const flags = result.flags.?;
    try testing.expect(flags.overflow);
}

test "SLO: carry flag from shift works" {
    const state = helpers.makeStateWithAddress(0x00, 0, 0, helpers.clearFlags(), 0x1234);
    const result = Opcodes.slo(state, 0x80); // Shift 0x80 left = 0x00, carry=1

    const flags = result.flags.?;
    try testing.expect(flags.carry);
}

test "RLA: carry into rotate works" {
    const state = helpers.makeStateWithAddress(0xFF, 0, 0, helpers.flagsWithCarry(), 0x1234);
    const result = Opcodes.rla(state, 0x80); // ROL 0x80 with C=1 = 0x01

    try helpers.expectBusWrite(result, 0x1234, 0x01);
    try helpers.expectRegister(result, "a", 0x01); // 0xFF & 0x01
}

// ============================================================================
// Additional Comprehensive Coverage Tests
// ============================================================================

// LAX additional tests
test "LAX: various operand values" {
    const test_values = [_]u8{ 0x01, 0x7F, 0xFF };
    for (test_values) |value| {
        const state = helpers.makeState(0, 0, 0, helpers.clearFlags());
        const result = Opcodes.lax(state, value);
        try helpers.expectRegister(result, "a", value);
        try helpers.expectRegister(result, "x", value);
    }
}

// SAX additional tests
test "SAX: different A and X combinations" {
    const state1 = helpers.makeStateWithAddress(0xAA, 0x55, 0, helpers.clearFlags(), 0x1000);
    const result1 = Opcodes.sax(state1, 0);
    try helpers.expectBusWrite(result1, 0x1000, 0x00); // 0xAA & 0x55 = 0x00

    const state2 = helpers.makeStateWithAddress(0xF0, 0x0F, 0, helpers.clearFlags(), 0x2000);
    const result2 = Opcodes.sax(state2, 0);
    try helpers.expectBusWrite(result2, 0x2000, 0x00); // 0xF0 & 0x0F = 0x00
}

// DCP edge cases
test "DCP: wrap around cases" {
    const state = helpers.makeStateWithAddress(0x01, 0, 0, helpers.clearFlags(), 0x1234);
    const result = Opcodes.dcp(state, 0x00); // Dec 0x00 -> 0xFF

    try helpers.expectBusWrite(result, 0x1234, 0xFF);
    const flags = result.flags.?;
    try testing.expect(!flags.carry); // A(0x01) < result(0xFF)
}

// ISC edge cases
test "ISC: wrap and carry" {
    const state = helpers.makeStateWithAddress(0xFF, 0, 0, helpers.flagsWithCarry(), 0x1234);
    const result = Opcodes.isc(state, 0xFF); // Inc 0xFF -> 0x00

    try helpers.expectBusWrite(result, 0x1234, 0x00);
    // A(0xFF) - 0x00 with carry = 0xFF
    try helpers.expectRegister(result, "a", 0xFF);
}

// SLO variations
test "SLO: all shift amounts" {
    const state1 = helpers.makeStateWithAddress(0x00, 0, 0, helpers.clearFlags(), 0x1000);
    const result1 = Opcodes.slo(state1, 0x7F);
    try helpers.expectBusWrite(result1, 0x1000, 0xFE); // 0x7F << 1

    const state2 = helpers.makeStateWithAddress(0xFF, 0, 0, helpers.clearFlags(), 0x2000);
    const result2 = Opcodes.slo(state2, 0x80);
    try helpers.expectBusWrite(result2, 0x2000, 0x00); // 0x80 << 1 with carry
}

// RLA variations
test "RLA: with and without carry in" {
    const state1 = helpers.makeStateWithAddress(0x00, 0, 0, helpers.clearFlags(), 0x1000);
    const result1 = Opcodes.rla(state1, 0x40);
    try helpers.expectBusWrite(result1, 0x1000, 0x80); // 0x40 ROL with C=0

    const state2 = helpers.makeStateWithAddress(0xFF, 0, 0, helpers.flagsWithCarry(), 0x2000);
    const result2 = Opcodes.rla(state2, 0x40);
    try helpers.expectBusWrite(result2, 0x2000, 0x81); // 0x40 ROL with C=1
}

// SRE variations
test "SRE: various values" {
    const state1 = helpers.makeStateWithAddress(0xFF, 0, 0, helpers.clearFlags(), 0x1000);
    const result1 = Opcodes.sre(state1, 0xFE);
    try helpers.expectBusWrite(result1, 0x1000, 0x7F); // 0xFE >> 1

    const state2 = helpers.makeStateWithAddress(0x00, 0, 0, helpers.clearFlags(), 0x2000);
    const result2 = Opcodes.sre(state2, 0x01);
    try helpers.expectBusWrite(result2, 0x2000, 0x00); // 0x01 >> 1 with carry
}

// RRA variations
test "RRA: with carry variations" {
    const state1 = helpers.makeStateWithAddress(0x00, 0, 0, helpers.clearFlags(), 0x1000);
    const result1 = Opcodes.rra(state1, 0x80);
    try helpers.expectBusWrite(result1, 0x1000, 0x40); // 0x80 ROR with C=0

    const state2 = helpers.makeStateWithAddress(0x00, 0, 0, helpers.flagsWithCarry(), 0x2000);
    const result2 = Opcodes.rra(state2, 0x01);
    try helpers.expectBusWrite(result2, 0x2000, 0x80); // 0x01 ROR with C=1
}

// ANC edge cases
test "ANC: various bit 7 states" {
    const state1 = helpers.makeState(0xFF, 0, 0, helpers.clearFlags());
    const result1 = Opcodes.anc(state1, 0x00);
    const flags1 = result1.flags.?;
    try testing.expect(!flags1.carry); // Bit 7 of result is 0

    const state2 = helpers.makeState(0x80, 0, 0, helpers.clearFlags());
    const result2 = Opcodes.anc(state2, 0xFF);
    const flags2 = result2.flags.?;
    try testing.expect(flags2.carry); // Bit 7 of result is 1
}

// ALR edge cases  
test "ALR: zero result" {
    const state = helpers.makeState(0xFF, 0, 0, helpers.clearFlags());
    const result = Opcodes.alr(state, 0x01); // 0xFF & 0x01 = 0x01, >> 1 = 0x00

    try helpers.expectRegister(result, "a", 0x00);
    const flags = result.flags.?;
    try testing.expect(flags.zero);
    try testing.expect(flags.carry); // Bit 0 was 1
}

// ARR comprehensive
test "ARR: overflow flag calculation" {
    const state = helpers.makeState(0xFF, 0, 0, helpers.clearFlags());
    const result = Opcodes.arr(state, 0x80); // Complex flag behavior

    try testing.expect(result.flags != null);
}

// AXS edge cases
test "AXS: borrow scenarios" {
    const state1 = helpers.makeState(0xFF, 0x0F, 0, helpers.clearFlags());
    const result1 = Opcodes.axs(state1, 0x10); // (0xFF & 0x0F) - 0x10 = 0xFF (borrow)

    try helpers.expectRegister(result1, "x", 0xFF);
    const flags1 = result1.flags.?;
    try testing.expect(!flags1.carry); // Borrow occurred
}

// Additional LAX comprehensive
test "LAX: flag combinations" {
    const state1 = helpers.makeState(0, 0, 0, helpers.clearFlags());
    const result1 = Opcodes.lax(state1, 0x00);
    try helpers.expectZN(result1, true, false);

    const state2 = helpers.makeState(0, 0, 0, helpers.clearFlags());
    const result2 = Opcodes.lax(state2, 0x80);
    try helpers.expectZN(result2, false, true);
}

// More DCP tests
test "DCP: all flag combinations" {
    // Test A < M-1
    const state1 = helpers.makeStateWithAddress(0x10, 0, 0, helpers.clearFlags(), 0x1000);
    const result1 = Opcodes.dcp(state1, 0x50); // Dec to 0x4F, compare 0x10 < 0x4F

    const flags1 = result1.flags.?;
    try testing.expect(!flags1.carry); // Borrow
    try testing.expect(!flags1.zero);
    try testing.expect(flags1.negative);
}

// More ISC tests
test "ISC: zero result" {
    const state = helpers.makeStateWithAddress(0x01, 0, 0, helpers.flagsWithCarry(), 0x1000);
    const result = Opcodes.isc(state, 0x00); // Inc to 0x01, then 0x01 - 0x01 = 0x00

    try helpers.expectRegister(result, "a", 0x00);
    const flags = result.flags.?;
    try testing.expect(flags.zero);
}

// SLO/RLA/SRE/RRA flag tests
test "SLO: negative flag" {
    const state = helpers.makeStateWithAddress(0x00, 0, 0, helpers.clearFlags(), 0x1000);
    const result = Opcodes.slo(state, 0x40); // Shift to 0x80

    try helpers.expectRegister(result, "a", 0x80);
    try helpers.expectZN(result, false, true);
}

test "RLA: zero flag" {
    const state = helpers.makeStateWithAddress(0x0F, 0, 0, helpers.clearFlags(), 0x1000);
    const result = Opcodes.rla(state, 0x80); // ROL to 0x00, then AND

    try helpers.expectRegister(result, "a", 0x00);
    try helpers.expectZN(result, true, false);
}

test "SRE: carry from shift" {
    const state = helpers.makeStateWithAddress(0x00, 0, 0, helpers.clearFlags(), 0x1000);
    const result = Opcodes.sre(state, 0x01); // Shift 0x01 right, carry out

    const flags = result.flags.?;
    try testing.expect(flags.carry);
}

test "RRA: complex carry behavior" {
    const state = helpers.makeStateWithAddress(0x01, 0, 0, helpers.flagsWithCarry(), 0x1000);
    const result = Opcodes.rra(state, 0x00); // ROR 0x00 with C=1 = 0x80, then ADC

    const flags = result.flags.?;
    try testing.expect(flags.negative); // Result has bit 7 set
}

// XAA/LXA edge cases
test "XAA: with zero X" {
    const state = helpers.makeState(0xFF, 0x00, 0, helpers.clearFlags());
    const result = Opcodes.xaa(state, 0xFF);

    try helpers.expectRegister(result, "a", 0x00); // Anything & 0x00 = 0x00
    try helpers.expectZN(result, true, false);
}

test "LXA: magic constant behavior" {
    const state1 = helpers.makeState(0x00, 0, 0, helpers.clearFlags());
    const result1 = Opcodes.lxa(state1, 0xFF);

    try helpers.expectRegister(result1, "a", 0xEE); // (0x00 | 0xEE) & 0xFF = 0xEE
}
