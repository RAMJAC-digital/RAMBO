//! Pure Functional Tests for Compare Instructions
//!
//! Tests CMP, CPX, CPY, BIT opcodes using the pure functional API.
//!
//! Migrated from: docs/archive/old-imperative-cpu/implementation/compare.zig

const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");

const RAMBO = @import("RAMBO");
const Opcodes = RAMBO.Cpu.opcodes;

test "CMP: A==M sets Z and C (0x42 - 0x42)" {
    const state = helpers.makeState(0x42, 0, 0, helpers.clearFlags());
    const result = Opcodes.cmp(state, 0x42);

    try helpers.expectFlags(result, helpers.makeFlags(true, false, true, false));
}

test "CMP: A>M sets C (0x50 - 0x30)" {
    const state = helpers.makeState(0x50, 0, 0, helpers.clearFlags());
    const result = Opcodes.cmp(state, 0x30);

    try helpers.expectFlags(result, helpers.makeFlags(false, false, true, false));
}

test "CMP: A<M clears C, sets N (0x30 - 0x50)" {
    const state = helpers.makeState(0x30, 0, 0, helpers.clearFlags());
    const result = Opcodes.cmp(state, 0x50);

    try helpers.expectFlags(result, helpers.makeFlags(false, true, false, false));
}

test "CPX: X==M (0x42)" {
    const state = helpers.makeState(0, 0x42, 0, helpers.clearFlags());
    const result = Opcodes.cpx(state, 0x42);

    try helpers.expectFlags(result, helpers.makeFlags(true, false, true, false));
}

test "CPX: X>M (0x50 > 0x30)" {
    const state = helpers.makeState(0, 0x50, 0, helpers.clearFlags());
    const result = Opcodes.cpx(state, 0x30);

    try helpers.expectFlags(result, helpers.makeFlags(false, false, true, false));
}

test "CPY: Y==M (0x42)" {
    const state = helpers.makeState(0, 0, 0x42, helpers.clearFlags());
    const result = Opcodes.cpy(state, 0x42);

    try helpers.expectFlags(result, helpers.makeFlags(true, false, true, false));
}

test "CPY: Y<M (0x30 < 0x50)" {
    const state = helpers.makeState(0, 0, 0x30, helpers.clearFlags());
    const result = Opcodes.cpy(state, 0x50);

    try helpers.expectFlags(result, helpers.makeFlags(false, true, false, false));
}

test "BIT: zero flag when A & M = 0" {
    const state = helpers.makeState(0x0F, 0, 0, helpers.clearFlags());
    const result = Opcodes.bit(state, 0xF0);

    const flags = result.flags.?;
    try testing.expect(flags.zero);
}

test "BIT: copies bit 6 to V flag" {
    const state = helpers.makeState(0xFF, 0, 0, helpers.clearFlags());
    const result = Opcodes.bit(state, 0x40); // bit 6 set

    const flags = result.flags.?;
    try testing.expect(flags.overflow);
}

test "BIT: copies bit 7 to N flag" {
    const state = helpers.makeState(0xFF, 0, 0, helpers.clearFlags());
    const result = Opcodes.bit(state, 0x80); // bit 7 set

    const flags = result.flags.?;
    try testing.expect(flags.negative);
}

// ============================================================================
// Comprehensive Boundary and Edge Cases
// ============================================================================

test "CMP: boundary values (0x00, 0xFF)" {
    // Compare 0x00 with 0x00 - equal
    const state1 = helpers.makeState(0x00, 0, 0, helpers.clearFlags());
    const result1 = Opcodes.cmp(state1, 0x00);
    try helpers.expectFlags(result1, helpers.makeFlags(true, false, true, false)); // Z=1, C=1

    // Compare 0xFF with 0xFF - equal
    const state2 = helpers.makeState(0xFF, 0, 0, helpers.clearFlags());
    const result2 = Opcodes.cmp(state2, 0xFF);
    try helpers.expectFlags(result2, helpers.makeFlags(true, false, true, false)); // Z=1, C=1

    // Compare 0x00 with 0xFF - less than (wrap)
    const state3 = helpers.makeState(0x00, 0, 0, helpers.clearFlags());
    const result3 = Opcodes.cmp(state3, 0xFF);
    try helpers.expectFlags(result3, helpers.makeFlags(false, false, false, false)); // C=0

    // Compare 0xFF with 0x00 - greater than
    const state4 = helpers.makeState(0xFF, 0, 0, helpers.clearFlags());
    const result4 = Opcodes.cmp(state4, 0x00);
    try helpers.expectFlags(result4, helpers.makeFlags(false, true, true, false)); // N=1, C=1
}

test "CPX: boundary values (0x00, 0xFF)" {
    // X=0x00, M=0x00 - equal
    const state1 = helpers.makeState(0, 0x00, 0, helpers.clearFlags());
    const result1 = Opcodes.cpx(state1, 0x00);
    try helpers.expectFlags(result1, helpers.makeFlags(true, false, true, false));

    // X=0xFF, M=0x00 - greater
    const state2 = helpers.makeState(0, 0xFF, 0, helpers.clearFlags());
    const result2 = Opcodes.cpx(state2, 0x00);
    try helpers.expectFlags(result2, helpers.makeFlags(false, true, true, false));

    // X=0x00, M=0xFF - less (wrap)
    const state3 = helpers.makeState(0, 0x00, 0, helpers.clearFlags());
    const result3 = Opcodes.cpx(state3, 0xFF);
    try helpers.expectFlags(result3, helpers.makeFlags(false, false, false, false));
}

test "CPY: boundary values (0x00, 0xFF)" {
    // Y=0x00, M=0x00 - equal
    const state1 = helpers.makeState(0, 0, 0x00, helpers.clearFlags());
    const result1 = Opcodes.cpy(state1, 0x00);
    try helpers.expectFlags(result1, helpers.makeFlags(true, false, true, false));

    // Y=0x7F, M=0x80 - less
    const state2 = helpers.makeState(0, 0, 0x7F, helpers.clearFlags());
    const result2 = Opcodes.cpy(state2, 0x80);
    try helpers.expectFlags(result2, helpers.makeFlags(false, true, false, false));
}

test "CMP: wrap-around edge cases" {
    // 0x01 - 0x02 = 0xFF (underflow)
    const state = helpers.makeState(0x01, 0, 0, helpers.clearFlags());
    const result = Opcodes.cmp(state, 0x02);
    try helpers.expectFlags(result, helpers.makeFlags(false, true, false, false)); // N=1, C=0
}

test "BIT: all combinations of bits 6 and 7" {
    const tests = [_]struct { mem: u8, expect_v: bool, expect_n: bool }{
        .{ .mem = 0x00, .expect_v = false, .expect_n = false }, // Neither set
        .{ .mem = 0x40, .expect_v = true, .expect_n = false }, // V set only
        .{ .mem = 0x80, .expect_v = false, .expect_n = true }, // N set only
        .{ .mem = 0xC0, .expect_v = true, .expect_n = true }, // Both set
    };

    for (tests) |t| {
        const state = helpers.makeState(0xFF, 0, 0, helpers.clearFlags());
        const result = Opcodes.bit(state, t.mem);

        const flags = result.flags.?;
        try testing.expectEqual(t.expect_v, flags.overflow);
        try testing.expectEqual(t.expect_n, flags.negative);
    }
}

test "BIT: zero flag independent of bits 6/7" {
    // Z flag set when (A & M) == 0
    const state1 = helpers.makeState(0x0F, 0, 0, helpers.clearFlags());
    const result1 = Opcodes.bit(state1, 0xF0); // No overlap
    const flags1 = result1.flags.?;
    try testing.expect(flags1.zero);

    // Z flag clear when (A & M) != 0
    const state2 = helpers.makeState(0xFF, 0, 0, helpers.clearFlags());
    const result2 = Opcodes.bit(state2, 0x01); // Bit 0 overlaps
    const flags2 = result2.flags.?;
    try testing.expect(!flags2.zero);
}

test "CMP/CPX/CPY: all three comparisons independent" {
    const state = helpers.makeState(0x50, 0x30, 0x70, helpers.clearFlags());

    const cmp_result = Opcodes.cmp(state, 0x40); // A=0x50 > 0x40
    const cpx_result = Opcodes.cpx(state, 0x40); // X=0x30 < 0x40
    const cpy_result = Opcodes.cpy(state, 0x40); // Y=0x70 > 0x40

    // CMP: A > M
    const cmp_flags = cmp_result.flags.?;
    try testing.expect(cmp_flags.carry);
    try testing.expect(!cmp_flags.zero);

    // CPX: X < M
    const cpx_flags = cpx_result.flags.?;
    try testing.expect(!cpx_flags.carry);

    // CPY: Y > M
    const cpy_flags = cpy_result.flags.?;
    try testing.expect(cpy_flags.carry);
}

test "BIT: preserves carry flag" {
    // BIT only affects Z, V, N - not carry
    const state = helpers.makeState(0xFF, 0, 0, helpers.flagsWithCarry());
    const result = Opcodes.bit(state, 0x00);

    const flags = result.flags.?;
    try testing.expect(flags.carry); // Preserved
}
