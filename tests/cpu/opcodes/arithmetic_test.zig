//! Pure Functional Tests for Arithmetic Instructions
//!
//! Tests ADC (Add with Carry) and SBC (Subtract with Carry) opcodes
//! using the pure functional API.
//!
//! Migrated from: docs/archive/old-imperative-cpu/implementation/arithmetic.zig

const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");

const RAMBO = @import("RAMBO");
const Opcodes = RAMBO.Cpu.opcodes;
const PureCpuState = helpers.PureCpuState;

// ============================================================================
// ADC Tests (6 tests)
// ============================================================================

test "ADC: basic addition (0x50 + 0x10 = 0x60)" {
    const state = helpers.makeState(0x50, 0, 0, helpers.clearFlags());
    const result = Opcodes.adc(state, 0x10);

    try helpers.expectRegister(result, "a", 0x60);
    try helpers.expectFlags(result, helpers.makeFlags(
        false, // Z (result != 0)
        false, // N (bit 7 clear)
        false, // C (no carry out)
        false, // V (no overflow)
    ));
}

test "ADC: addition with carry in (0x50 + 0x10 + 1 = 0x61)" {
    const state = helpers.makeState(0x50, 0, 0, helpers.flagsWithCarry());
    const result = Opcodes.adc(state, 0x10);

    try helpers.expectRegister(result, "a", 0x61);
    try helpers.expectFlags(result, helpers.makeFlags(
        false, // Z
        false, // N
        false, // C (no carry out)
        false, // V
    ));
}

test "ADC: carry out (0xFF + 0x01 = 0x00, C=1)" {
    const state = helpers.makeState(0xFF, 0, 0, helpers.clearFlags());
    const result = Opcodes.adc(state, 0x01);

    try helpers.expectRegister(result, "a", 0x00);
    try helpers.expectFlags(result, helpers.makeFlags(
        true,  // Z (result = 0)
        false, // N (bit 7 clear)
        true,  // C (carry out)
        false, // V
    ));
}

test "ADC: overflow - positive + positive = negative (0x50 + 0x50 = 0xA0)" {
    const state = helpers.makeState(0x50, 0, 0, helpers.clearFlags());
    const result = Opcodes.adc(state, 0x50);

    try helpers.expectRegister(result, "a", 0xA0);
    try helpers.expectFlags(result, helpers.makeFlags(
        false, // Z
        true,  // N (bit 7 set)
        false, // C (no carry out)
        true,  // V (overflow: +80 + +80 = -96)
    ));
}

test "ADC: overflow - negative + negative = positive (0x80 + 0x80 = 0x00)" {
    const state = helpers.makeState(0x80, 0, 0, helpers.clearFlags());
    const result = Opcodes.adc(state, 0x80);

    try helpers.expectRegister(result, "a", 0x00);
    try helpers.expectFlags(result, helpers.makeFlags(
        true,  // Z (result = 0)
        false, // N (bit 7 clear)
        true,  // C (carry out)
        true,  // V (overflow: -128 + -128 = 0 with overflow)
    ));
}

test "ADC: no overflow - positive + negative (0x50 + 0xF0 = 0x40)" {
    const state = helpers.makeState(0x50, 0, 0, helpers.clearFlags());
    const result = Opcodes.adc(state, 0xF0);

    try helpers.expectRegister(result, "a", 0x40);
    try helpers.expectFlags(result, helpers.makeFlags(
        false, // Z
        false, // N
        true,  // C (carry out)
        false, // V (no overflow: different signs)
    ));
}

// ============================================================================
// SBC Tests (5 tests)
// These will reveal the carry flag bug in current implementation!
// ============================================================================

test "SBC: simple subtraction (0x50 - 0x10 with C=1 = 0x40)" {
    const state = helpers.makeState(0x50, 0, 0, helpers.flagsWithCarry());
    const result = Opcodes.sbc(state, 0x10);

    try helpers.expectRegister(result, "a", 0x40);
    try helpers.expectFlags(result, helpers.makeFlags(
        false, // Z
        false, // N
        true,  // C (no borrow occurred)
        false, // V
    ));
}

test "SBC: subtraction with borrow in (0x50 - 0x10 with C=0 = 0x3F)" {
    const state = helpers.makeState(0x50, 0, 0, helpers.clearFlags());
    const result = Opcodes.sbc(state, 0x10);

    try helpers.expectRegister(result, "a", 0x3F); // 0x50 - 0x10 - 1 = 0x3F
    try helpers.expectFlags(result, helpers.makeFlags(
        false, // Z
        false, // N
        true,  // C (no borrow in final result)
        false, // V
    ));
}

test "SBC: borrow flag cleared (0x10 - 0x20 with C=1 = 0xF0, C=0)" {
    // THIS TEST WILL FAIL with current bug!
    // Current code has backwards carry logic
    const state = helpers.makeState(0x10, 0, 0, helpers.flagsWithCarry());
    const result = Opcodes.sbc(state, 0x20);

    try helpers.expectRegister(result, "a", 0xF0); // Wrapped around
    try helpers.expectFlags(result, helpers.makeFlags(
        false, // Z
        true,  // N (bit 7 set)
        false, // C (borrow occurred) ← BUG: Current code will set this to true!
        false, // V
    ));
}

test "SBC: overflow flag (0x50 - 0x80 with C=1 = overflow)" {
    const state = helpers.makeState(0x50, 0, 0, helpers.flagsWithCarry());
    const result = Opcodes.sbc(state, 0x80);

    // +80 - (-128) = +80 + 128 = -48 (overflow)
    try helpers.expectFlags(result, helpers.makeFlags(
        false, // Z
        true,  // N
        false, // C
        true,  // V (overflow)
    ));
}

test "SBC: zero flag (0x50 - 0x50 with C=1 = 0x00)" {
    const state = helpers.makeState(0x50, 0, 0, helpers.flagsWithCarry());
    const result = Opcodes.sbc(state, 0x50);

    try helpers.expectRegister(result, "a", 0x00);
    try helpers.expectFlags(result, helpers.makeFlags(
        true,  // Z (result = 0)
        false, // N
        true,  // C (no borrow)
        false, // V
    ));
}

// ============================================================================
// Additional Comprehensive ADC Tests
// ============================================================================

test "ADC: all flag combinations" {
    // Test Z, N, C, V independently
    const tests = [_]struct { a: u8, op: u8, c: bool, expect_a: u8, expect_z: bool, expect_n: bool, expect_c: bool, expect_v: bool }{
        .{ .a = 0x00, .op = 0x00, .c = false, .expect_a = 0x00, .expect_z = true, .expect_n = false, .expect_c = false, .expect_v = false },
        .{ .a = 0x7F, .op = 0x01, .c = false, .expect_a = 0x80, .expect_z = false, .expect_n = true, .expect_c = false, .expect_v = true },
        .{ .a = 0xFF, .op = 0x01, .c = true, .expect_a = 0x01, .expect_z = false, .expect_n = false, .expect_c = true, .expect_v = false },
        .{ .a = 0x80, .op = 0x80, .c = true, .expect_a = 0x01, .expect_z = false, .expect_n = false, .expect_c = true, .expect_v = true },
    };

    for (tests) |t| {
        const flags = if (t.c) helpers.flagsWithCarry() else helpers.clearFlags();
        const state = helpers.makeState(t.a, 0, 0, flags);
        const result = Opcodes.adc(state, t.op);

        try helpers.expectRegister(result, "a", t.expect_a);
        try helpers.expectFlags(result, helpers.makeFlags(t.expect_z, t.expect_n, t.expect_c, t.expect_v));
    }
}

// ============================================================================
// Additional Comprehensive SBC Tests
// ============================================================================

test "SBC: all flag combinations" {
    const tests = [_]struct { a: u8, op: u8, c: bool, expect_a: u8, expect_z: bool, expect_n: bool, expect_c: bool, expect_v: bool }{
        .{ .a = 0x00, .op = 0x00, .c = true, .expect_a = 0x00, .expect_z = true, .expect_n = false, .expect_c = true, .expect_v = false },
        .{ .a = 0x80, .op = 0x01, .c = true, .expect_a = 0x7F, .expect_z = false, .expect_n = false, .expect_c = true, .expect_v = true },
        .{ .a = 0x00, .op = 0x01, .c = true, .expect_a = 0xFF, .expect_z = false, .expect_n = true, .expect_c = false, .expect_v = false },
        .{ .a = 0x01, .op = 0x01, .c = false, .expect_a = 0xFF, .expect_z = false, .expect_n = true, .expect_c = false, .expect_v = false },
    };

    for (tests) |t| {
        const flags = if (t.c) helpers.flagsWithCarry() else helpers.clearFlags();
        const state = helpers.makeState(t.a, 0, 0, flags);
        const result = Opcodes.sbc(state, t.op);

        try helpers.expectRegister(result, "a", t.expect_a);
        try helpers.expectFlags(result, helpers.makeFlags(t.expect_z, t.expect_n, t.expect_c, t.expect_v));
    }
}

test "ADC: boundary values" {
    const state1 = helpers.makeState(0x00, 0, 0, helpers.clearFlags());
    const result1 = Opcodes.adc(state1, 0xFF);
    try helpers.expectRegister(result1, "a", 0xFF);

    const state2 = helpers.makeState(0xFF, 0, 0, helpers.clearFlags());
    const result2 = Opcodes.adc(state2, 0xFF);
    try helpers.expectRegister(result2, "a", 0xFE);
}

test "SBC: boundary values" {
    const state1 = helpers.makeState(0xFF, 0, 0, helpers.flagsWithCarry());
    const result1 = Opcodes.sbc(state1, 0xFF);
    try helpers.expectRegister(result1, "a", 0x00);

    const state2 = helpers.makeState(0x00, 0, 0, helpers.flagsWithCarry());
    const result2 = Opcodes.sbc(state2, 0xFF);
    try helpers.expectRegister(result2, "a", 0x01);
}

test "ADC: decimal mode flag ignored (NES CPU)" {
    var state = helpers.makeState(0x09, 0, 0, helpers.clearFlags());
    state.p.decimal = true; // NES CPU ignores decimal mode
    const result = Opcodes.adc(state, 0x01);

    try helpers.expectRegister(result, "a", 0x0A); // Binary addition, not BCD
}

test "SBC: decimal mode flag ignored (NES CPU)" {
    var state = helpers.makeState(0x09, 0, 0, helpers.flagsWithCarry());
    state.p.decimal = true;
    const result = Opcodes.sbc(state, 0x01);

    try helpers.expectRegister(result, "a", 0x08); // Binary subtraction, not BCD
}
