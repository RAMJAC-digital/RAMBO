//! Pure Functional Tests for Load/Store Instructions
//!
//! Tests LDA, LDX, LDY, STA, STX, STY opcodes using the pure functional API.
//!
//! Migrated from: docs/archive/old-imperative-cpu/implementation/loadstore.zig

const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");

const RAMBO = @import("RAMBO");
const Opcodes = RAMBO.Cpu.opcodes;

// ============================================================================
// LDA Tests
// ============================================================================

test "LDA: loads value and sets Z/N flags correctly (0x42)" {
    const state = helpers.makeState(0, 0, 0, helpers.clearFlags());
    const result = Opcodes.lda(state, 0x42);

    try helpers.expectRegister(result, "a", 0x42);
    try helpers.expectZN(result, false, false);
}

test "LDA: zero flag set when loading 0x00" {
    const state = helpers.makeState(0xFF, 0, 0, helpers.clearFlags());
    const result = Opcodes.lda(state, 0x00);

    try helpers.expectRegister(result, "a", 0x00);
    try helpers.expectZN(result, true, false);
}

test "LDA: negative flag set when bit 7 is set (0x80)" {
    const state = helpers.makeState(0, 0, 0, helpers.clearFlags());
    const result = Opcodes.lda(state, 0x80);

    try helpers.expectRegister(result, "a", 0x80);
    try helpers.expectZN(result, false, true);
}

// ============================================================================
// LDX Tests
// ============================================================================

test "LDX: loads value into X register (0x42)" {
    const state = helpers.makeState(0, 0, 0, helpers.clearFlags());
    const result = Opcodes.ldx(state, 0x42);

    try helpers.expectRegister(result, "x", 0x42);
    try helpers.expectZN(result, false, false);
}

test "LDX: sets zero flag (0x00)" {
    const state = helpers.makeState(0, 0xFF, 0, helpers.clearFlags());
    const result = Opcodes.ldx(state, 0x00);

    try helpers.expectRegister(result, "x", 0x00);
    try helpers.expectZN(result, true, false);
}

// ============================================================================
// LDY Tests
// ============================================================================

test "LDY: loads value into Y register (0x42)" {
    const state = helpers.makeState(0, 0, 0, helpers.clearFlags());
    const result = Opcodes.ldy(state, 0x42);

    try helpers.expectRegister(result, "y", 0x42);
    try helpers.expectZN(result, false, false);
}

test "LDY: sets negative flag (0x80)" {
    const state = helpers.makeState(0, 0, 0, helpers.clearFlags());
    const result = Opcodes.ldy(state, 0x80);

    try helpers.expectRegister(result, "y", 0x80);
    try helpers.expectZN(result, false, true);
}

// ============================================================================
// STA Tests
// ============================================================================

test "STA: stores accumulator to memory" {
    const state = helpers.makeStateWithAddress(0x42, 0, 0, helpers.clearFlags(), 0x1234);
    const result = Opcodes.sta(state, 0); // Operand unused for stores

    try helpers.expectBusWrite(result, 0x1234, 0x42);
    // Store instructions don't change flags
    if (result.flags != null) {
        return error.TestUnexpectedValue;
    }
}

test "STA: does not affect flags even when storing 0x00" {
    const state = helpers.makeStateWithAddress(0x00, 0, 0, helpers.makeFlags(false, true, true, true), 0x0050);
    const result = Opcodes.sta(state, 0);

    try helpers.expectBusWrite(result, 0x0050, 0x00);
    // Flags should be unchanged (null)
    try testing.expect(result.flags == null);
}

// ============================================================================
// STX Tests
// ============================================================================

test "STX: stores X register to memory" {
    const state = helpers.makeStateWithAddress(0, 0x42, 0, helpers.clearFlags(), 0x0050);
    const result = Opcodes.stx(state, 0);

    try helpers.expectBusWrite(result, 0x0050, 0x42);
    try testing.expect(result.flags == null);
}

// ============================================================================
// STY Tests
// ============================================================================

test "STY: stores Y register to memory" {
    const state = helpers.makeStateWithAddress(0, 0, 0x42, helpers.clearFlags(), 0x0050);
    const result = Opcodes.sty(state, 0);

    try helpers.expectBusWrite(result, 0x0050, 0x42);
    try testing.expect(result.flags == null);
}

// ============================================================================
// Edge Cases
// ============================================================================

test "Load/Store: all three load instructions work independently" {
    const state = helpers.makeState(0x11, 0x22, 0x33, helpers.clearFlags());

    // Load different values into each register
    const lda_result = Opcodes.lda(state, 0xAA);
    const ldx_result = Opcodes.ldx(state, 0xBB);
    const ldy_result = Opcodes.ldy(state, 0xCC);

    try helpers.expectRegister(lda_result, "a", 0xAA);
    try helpers.expectRegister(ldx_result, "x", 0xBB);
    try helpers.expectRegister(ldy_result, "y", 0xCC);
}

test "Store: all three store instructions work independently" {
    const state_a = helpers.makeStateWithAddress(0xAA, 0xBB, 0xCC, helpers.clearFlags(), 0x1000);
    const state_x = helpers.makeStateWithAddress(0xAA, 0xBB, 0xCC, helpers.clearFlags(), 0x2000);
    const state_y = helpers.makeStateWithAddress(0xAA, 0xBB, 0xCC, helpers.clearFlags(), 0x3000);

    const sta_result = Opcodes.sta(state_a, 0);
    const stx_result = Opcodes.stx(state_x, 0);
    const sty_result = Opcodes.sty(state_y, 0);

    try helpers.expectBusWrite(sta_result, 0x1000, 0xAA);
    try helpers.expectBusWrite(stx_result, 0x2000, 0xBB);
    try helpers.expectBusWrite(sty_result, 0x3000, 0xCC);
}

// ============================================================================
// Comprehensive Boundary Value Tests
// ============================================================================

test "LDA: boundary values (0x00, 0xFF, 0x7F, 0x80)" {
    const tests = [_]struct { value: u8, expect_z: bool, expect_n: bool }{
        .{ .value = 0x00, .expect_z = true, .expect_n = false },
        .{ .value = 0xFF, .expect_z = false, .expect_n = true },
        .{ .value = 0x7F, .expect_z = false, .expect_n = false },
        .{ .value = 0x80, .expect_z = false, .expect_n = true },
        .{ .value = 0x01, .expect_z = false, .expect_n = false },
    };

    for (tests) |t| {
        const state = helpers.makeState(0, 0, 0, helpers.clearFlags());
        const result = Opcodes.lda(state, t.value);

        try helpers.expectRegister(result, "a", t.value);
        try helpers.expectZN(result, t.expect_z, t.expect_n);
    }
}

test "LDX: boundary values with all flag combinations" {
    const tests = [_]struct { value: u8, expect_z: bool, expect_n: bool }{
        .{ .value = 0x00, .expect_z = true, .expect_n = false },
        .{ .value = 0xFF, .expect_z = false, .expect_n = true },
        .{ .value = 0x7F, .expect_z = false, .expect_n = false },
        .{ .value = 0x80, .expect_z = false, .expect_n = true },
    };

    for (tests) |t| {
        const state = helpers.makeState(0, 0, 0, helpers.clearFlags());
        const result = Opcodes.ldx(state, t.value);

        try helpers.expectRegister(result, "x", t.value);
        try helpers.expectZN(result, t.expect_z, t.expect_n);
    }
}

test "LDY: boundary values with all flag combinations" {
    const tests = [_]struct { value: u8, expect_z: bool, expect_n: bool }{
        .{ .value = 0x00, .expect_z = true, .expect_n = false },
        .{ .value = 0xFF, .expect_z = false, .expect_n = true },
        .{ .value = 0x7F, .expect_z = false, .expect_n = false },
        .{ .value = 0x80, .expect_z = false, .expect_n = true },
    };

    for (tests) |t| {
        const state = helpers.makeState(0, 0, 0, helpers.clearFlags());
        const result = Opcodes.ldy(state, t.value);

        try helpers.expectRegister(result, "y", t.value);
        try helpers.expectZN(result, t.expect_z, t.expect_n);
    }
}

test "STA: stores boundary values correctly" {
    const values = [_]u8{ 0x00, 0xFF, 0x7F, 0x80, 0x01 };

    for (values) |val| {
        const state = helpers.makeStateWithAddress(val, 0, 0, helpers.clearFlags(), 0x1234);
        const result = Opcodes.sta(state, 0);
        try helpers.expectBusWrite(result, 0x1234, val);
    }
}

test "STX: stores boundary values correctly" {
    const values = [_]u8{ 0x00, 0xFF, 0x7F, 0x80 };

    for (values) |val| {
        const state = helpers.makeStateWithAddress(0, val, 0, helpers.clearFlags(), 0x2000);
        const result = Opcodes.stx(state, 0);
        try helpers.expectBusWrite(result, 0x2000, val);
    }
}

test "STY: stores boundary values correctly" {
    const values = [_]u8{ 0x00, 0xFF, 0x7F, 0x80 };

    for (values) |val| {
        const state = helpers.makeStateWithAddress(0, 0, val, helpers.clearFlags(), 0x3000);
        const result = Opcodes.sty(state, 0);
        try helpers.expectBusWrite(result, 0x3000, val);
    }
}

test "Load: preserves existing flag state (overflow, carry)" {
    // Load instructions only affect Z/N, not C/V
    const state = helpers.makeState(0, 0, 0, helpers.makeFlags(false, false, true, true));
    const result = Opcodes.lda(state, 0x42);

    const flags = result.flags.?;
    try testing.expect(flags.carry); // Preserved
    try testing.expect(flags.overflow); // Preserved
}

test "Store: preserves all existing flags" {
    // Store instructions don't affect ANY flags
    const state = helpers.makeStateWithAddress(0x42, 0, 0, helpers.makeFlags(true, true, true, true), 0x1234);
    const result = Opcodes.sta(state, 0);

    try testing.expect(result.flags == null); // No flag changes
}
