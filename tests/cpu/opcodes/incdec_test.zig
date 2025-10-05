//! Pure Functional Tests for Increment/Decrement Instructions
//!
//! Tests INC, DEC, INX, INY, DEX, DEY opcodes.

const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");

const RAMBO = @import("RAMBO");
const Opcodes = RAMBO.Cpu.opcodes;

test "INX: increments X (0x41 -> 0x42)" {
    const state = helpers.makeState(0, 0x41, 0, helpers.clearFlags());
    const result = Opcodes.inx(state, 0);

    try helpers.expectRegister(result, "x", 0x42);
    try helpers.expectZN(result, false, false);
}

test "INX: wraps at 0xFF (0xFF -> 0x00)" {
    const state = helpers.makeState(0, 0xFF, 0, helpers.clearFlags());
    const result = Opcodes.inx(state, 0);

    try helpers.expectRegister(result, "x", 0x00);
    try helpers.expectZN(result, true, false);
}

test "INY: increments Y (0x7F -> 0x80)" {
    const state = helpers.makeState(0, 0, 0x7F, helpers.clearFlags());
    const result = Opcodes.iny(state, 0);

    try helpers.expectRegister(result, "y", 0x80);
    try helpers.expectZN(result, false, true);
}

test "DEX: decrements X (0x42 -> 0x41)" {
    const state = helpers.makeState(0, 0x42, 0, helpers.clearFlags());
    const result = Opcodes.dex(state, 0);

    try helpers.expectRegister(result, "x", 0x41);
    try helpers.expectZN(result, false, false);
}

test "DEX: wraps at 0x00 (0x00 -> 0xFF)" {
    const state = helpers.makeState(0, 0x00, 0, helpers.clearFlags());
    const result = Opcodes.dex(state, 0);

    try helpers.expectRegister(result, "x", 0xFF);
    try helpers.expectZN(result, false, true);
}

test "DEY: decrements Y (0x01 -> 0x00)" {
    const state = helpers.makeState(0, 0, 0x01, helpers.clearFlags());
    const result = Opcodes.dey(state, 0);

    try helpers.expectRegister(result, "y", 0x00);
    try helpers.expectZN(result, true, false);
}

test "INC: increments memory value (RMW)" {
    const state = helpers.makeStateWithAddress(0, 0, 0, helpers.clearFlags(), 0x1234);
    const result = Opcodes.inc(state, 0x41); // Operand is current memory value

    try helpers.expectBusWrite(result, 0x1234, 0x42);
    try helpers.expectZN(result, false, false);
}

test "DEC: decrements memory value (RMW)" {
    const state = helpers.makeStateWithAddress(0, 0, 0, helpers.clearFlags(), 0x1234);
    const result = Opcodes.dec(state, 0x42); // Operand is current memory value

    try helpers.expectBusWrite(result, 0x1234, 0x41);
    try helpers.expectZN(result, false, false);
}

// ============================================================================
// Comprehensive Wrap-around and Boundary Tests
// ============================================================================

test "INC memory: wraps at 0xFF (0xFF -> 0x00)" {
    const state = helpers.makeStateWithAddress(0, 0, 0, helpers.clearFlags(), 0x1234);
    const result = Opcodes.inc(state, 0xFF);

    try helpers.expectBusWrite(result, 0x1234, 0x00);
    try helpers.expectZN(result, true, false); // Z=1, N=0
}

test "INC memory: sets negative flag (0x7F -> 0x80)" {
    const state = helpers.makeStateWithAddress(0, 0, 0, helpers.clearFlags(), 0x1234);
    const result = Opcodes.inc(state, 0x7F);

    try helpers.expectBusWrite(result, 0x1234, 0x80);
    try helpers.expectZN(result, false, true); // Z=0, N=1
}

test "DEC memory: wraps at 0x00 (0x00 -> 0xFF)" {
    const state = helpers.makeStateWithAddress(0, 0, 0, helpers.clearFlags(), 0x1234);
    const result = Opcodes.dec(state, 0x00);

    try helpers.expectBusWrite(result, 0x1234, 0xFF);
    try helpers.expectZN(result, false, true); // Z=0, N=1
}

test "DEC memory: sets zero flag (0x01 -> 0x00)" {
    const state = helpers.makeStateWithAddress(0, 0, 0, helpers.clearFlags(), 0x1234);
    const result = Opcodes.dec(state, 0x01);

    try helpers.expectBusWrite(result, 0x1234, 0x00);
    try helpers.expectZN(result, true, false); // Z=1, N=0
}

test "INY: wraps at 0xFF (0xFF -> 0x00)" {
    const state = helpers.makeState(0, 0, 0xFF, helpers.clearFlags());
    const result = Opcodes.iny(state, 0);

    try helpers.expectRegister(result, "y", 0x00);
    try helpers.expectZN(result, true, false);
}

test "DEY: wraps at 0x00 (0x00 -> 0xFF)" {
    const state = helpers.makeState(0, 0, 0x00, helpers.clearFlags());
    const result = Opcodes.dey(state, 0);

    try helpers.expectRegister(result, "y", 0xFF);
    try helpers.expectZN(result, false, true);
}

test "INC/DEC: all boundary values" {
    const tests = [_]struct { value: u8, inc_result: u8, dec_result: u8 }{
        .{ .value = 0x00, .inc_result = 0x01, .dec_result = 0xFF },
        .{ .value = 0x7F, .inc_result = 0x80, .dec_result = 0x7E },
        .{ .value = 0x80, .inc_result = 0x81, .dec_result = 0x7F },
        .{ .value = 0xFF, .inc_result = 0x00, .dec_result = 0xFE },
    };

    for (tests) |t| {
        // Test INC
        const state_inc = helpers.makeStateWithAddress(0, 0, 0, helpers.clearFlags(), 0x1000);
        const result_inc = Opcodes.inc(state_inc, t.value);
        try helpers.expectBusWrite(result_inc, 0x1000, t.inc_result);

        // Test DEC
        const state_dec = helpers.makeStateWithAddress(0, 0, 0, helpers.clearFlags(), 0x2000);
        const result_dec = Opcodes.dec(state_dec, t.value);
        try helpers.expectBusWrite(result_dec, 0x2000, t.dec_result);
    }
}
