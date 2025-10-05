//! Pure Functional Tests for Shift/Rotate Instructions

const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");

const RAMBO = @import("RAMBO");
const Opcodes = RAMBO.Cpu.opcodes;

test "ASL accumulator: shifts left (0x40 -> 0x80)" {
    const state = helpers.makeState(0x40, 0, 0, helpers.clearFlags());
    const result = Opcodes.aslAcc(state, 0);

    try helpers.expectRegister(result, "a", 0x80);
    try helpers.expectZN(result, false, true);
    const flags = result.flags.?;
    try testing.expect(!flags.carry); // Bit 7 was 0
}

test "ASL accumulator: carry out (0x80 -> 0x00)" {
    const state = helpers.makeState(0x80, 0, 0, helpers.clearFlags());
    const result = Opcodes.aslAcc(state, 0);

    try helpers.expectRegister(result, "a", 0x00);
    const flags = result.flags.?;
    try testing.expect(flags.zero);
    try testing.expect(flags.carry); // Bit 7 was 1
}

test "LSR accumulator: shifts right (0x02 -> 0x01)" {
    const state = helpers.makeState(0x02, 0, 0, helpers.clearFlags());
    const result = Opcodes.lsrAcc(state, 0);

    try helpers.expectRegister(result, "a", 0x01);
    try helpers.expectZN(result, false, false);
    const flags = result.flags.?;
    try testing.expect(!flags.carry); // Bit 0 was 0
}

test "LSR accumulator: carry out (0x01 -> 0x00)" {
    const state = helpers.makeState(0x01, 0, 0, helpers.clearFlags());
    const result = Opcodes.lsrAcc(state, 0);

    try helpers.expectRegister(result, "a", 0x00);
    const flags = result.flags.?;
    try testing.expect(flags.zero);
    try testing.expect(flags.carry); // Bit 0 was 1
}

test "ROL accumulator: rotate left with carry (0x40, C=1 -> 0x81)" {
    const state = helpers.makeState(0x40, 0, 0, helpers.flagsWithCarry());
    const result = Opcodes.rolAcc(state, 0);

    try helpers.expectRegister(result, "a", 0x81); // Carry rotated into bit 0
    const flags = result.flags.?;
    try testing.expect(!flags.carry); // Bit 7 was 0
}

test "ROR accumulator: rotate right with carry (0x01, C=1 -> 0x80)" {
    const state = helpers.makeState(0x01, 0, 0, helpers.flagsWithCarry());
    const result = Opcodes.rorAcc(state, 0);

    try helpers.expectRegister(result, "a", 0x80); // Carry rotated into bit 7
    const flags = result.flags.?;
    try testing.expect(flags.carry); // Bit 0 was 1
}

test "ASL memory: RMW operation (0x40 -> 0x80)" {
    const state = helpers.makeStateWithAddress(0, 0, 0, helpers.clearFlags(), 0x1234);
    const result = Opcodes.aslMem(state, 0x40); // Operand is current memory value

    try helpers.expectBusWrite(result, 0x1234, 0x80);
    try helpers.expectZN(result, false, true);
}

test "LSR memory: RMW operation (0x02 -> 0x01)" {
    const state = helpers.makeStateWithAddress(0, 0, 0, helpers.clearFlags(), 0x1234);
    const result = Opcodes.lsrMem(state, 0x02);

    try helpers.expectBusWrite(result, 0x1234, 0x01);
    try helpers.expectZN(result, false, false);
}

test "ROL memory: RMW operation (0x40, C=0 -> 0x80)" {
    const state = helpers.makeStateWithAddress(0, 0, 0, helpers.clearFlags(), 0x1234);
    const result = Opcodes.rolMem(state, 0x40);

    try helpers.expectBusWrite(result, 0x1234, 0x80);
    const flags = result.flags.?;
    try testing.expect(!flags.carry); // Bit 7 was 0
}

test "ROR memory: RMW operation (0x02, C=0 -> 0x01)" {
    const state = helpers.makeStateWithAddress(0, 0, 0, helpers.clearFlags(), 0x1234);
    const result = Opcodes.rorMem(state, 0x02);

    try helpers.expectBusWrite(result, 0x1234, 0x01);
    const flags = result.flags.?;
    try testing.expect(!flags.carry); // Bit 0 was 0
}

// ============================================================================
// Comprehensive Edge Cases
// ============================================================================

test "ASL: all boundary values" {
    const tests = [_]struct { value: u8, expect_result: u8, expect_z: bool, expect_n: bool, expect_c: bool }{
        .{ .value = 0x00, .expect_result = 0x00, .expect_z = true, .expect_n = false, .expect_c = false },
        .{ .value = 0x01, .expect_result = 0x02, .expect_z = false, .expect_n = false, .expect_c = false },
        .{ .value = 0x7F, .expect_result = 0xFE, .expect_z = false, .expect_n = true, .expect_c = false },
        .{ .value = 0x80, .expect_result = 0x00, .expect_z = true, .expect_n = false, .expect_c = true },
        .{ .value = 0xFF, .expect_result = 0xFE, .expect_z = false, .expect_n = true, .expect_c = true },
    };

    for (tests) |t| {
        const state = helpers.makeState(t.value, 0, 0, helpers.clearFlags());
        const result = Opcodes.aslAcc(state, 0);

        try helpers.expectRegister(result, "a", t.expect_result);
        const flags = result.flags.?;
        try testing.expectEqual(t.expect_z, flags.zero);
        try testing.expectEqual(t.expect_n, flags.negative);
        try testing.expectEqual(t.expect_c, flags.carry);
    }
}

test "LSR: all boundary values" {
    const tests = [_]struct { value: u8, expect_result: u8, expect_z: bool, expect_c: bool }{
        .{ .value = 0x00, .expect_result = 0x00, .expect_z = true, .expect_c = false },
        .{ .value = 0x01, .expect_result = 0x00, .expect_z = true, .expect_c = true },
        .{ .value = 0x80, .expect_result = 0x40, .expect_z = false, .expect_c = false },
        .{ .value = 0xFF, .expect_result = 0x7F, .expect_z = false, .expect_c = true },
    };

    for (tests) |t| {
        const state = helpers.makeState(t.value, 0, 0, helpers.clearFlags());
        const result = Opcodes.lsrAcc(state, 0);

        try helpers.expectRegister(result, "a", t.expect_result);
        const flags = result.flags.?;
        try testing.expectEqual(t.expect_z, flags.zero);
        try testing.expect(!flags.negative); // LSR always clears N
        try testing.expectEqual(t.expect_c, flags.carry);
    }
}

test "ROL: all carry flag combinations" {
    // ROL with C=0
    const state1 = helpers.makeState(0xAA, 0, 0, helpers.clearFlags());
    const result1 = Opcodes.rolAcc(state1, 0);
    try helpers.expectRegister(result1, "a", 0x54); // 10101010 << 1 = 01010100

    // ROL with C=1
    const state2 = helpers.makeState(0xAA, 0, 0, helpers.flagsWithCarry());
    const result2 = Opcodes.rolAcc(state2, 0);
    try helpers.expectRegister(result2, "a", 0x55); // 10101010 << 1 | 1 = 01010101
}

test "ROR: all carry flag combinations" {
    // ROR with C=0
    const state1 = helpers.makeState(0x55, 0, 0, helpers.clearFlags());
    const result1 = Opcodes.rorAcc(state1, 0);
    try helpers.expectRegister(result1, "a", 0x2A); // 01010101 >> 1 = 00101010

    // ROR with C=1
    const state2 = helpers.makeState(0x55, 0, 0, helpers.flagsWithCarry());
    const result2 = Opcodes.rorAcc(state2, 0);
    try helpers.expectRegister(result2, "a", 0xAA); // 01010101 >> 1 | 0x80 = 10101010
}

test "Shift memory: multiple operations on different addresses" {
    const state1 = helpers.makeStateWithAddress(0, 0, 0, helpers.clearFlags(), 0x1000);
    const result1 = Opcodes.aslMem(state1, 0x40);
    try helpers.expectBusWrite(result1, 0x1000, 0x80);

    const state2 = helpers.makeStateWithAddress(0, 0, 0, helpers.clearFlags(), 0x2000);
    const result2 = Opcodes.lsrMem(state2, 0x40);
    try helpers.expectBusWrite(result2, 0x2000, 0x20);
}

test "ROL/ROR memory: carry propagation" {
    // ROL memory with carry
    const state1 = helpers.makeStateWithAddress(0, 0, 0, helpers.flagsWithCarry(), 0x1234);
    const result1 = Opcodes.rolMem(state1, 0x00);
    try helpers.expectBusWrite(result1, 0x1234, 0x01); // Carry rotated in

    // ROR memory with carry
    const state2 = helpers.makeStateWithAddress(0, 0, 0, helpers.flagsWithCarry(), 0x5678);
    const result2 = Opcodes.rorMem(state2, 0x00);
    try helpers.expectBusWrite(result2, 0x5678, 0x80); // Carry rotated in
}
