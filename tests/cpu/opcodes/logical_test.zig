//! Pure Functional Tests for Logical Instructions
//!
//! Tests AND, ORA, EOR opcodes using the pure functional API.
//!
//! Migrated from: docs/archive/old-imperative-cpu/implementation/logical.zig

const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");

const RAMBO = @import("RAMBO");
const Opcodes = RAMBO.Cpu.opcodes;

// ============================================================================
// AND Tests
// ============================================================================

test "AND: basic operation (0xFF & 0x0F = 0x0F)" {
    const state = helpers.makeState(0xFF, 0, 0, helpers.clearFlags());
    const result = Opcodes.logicalAnd(state, 0x0F);

    try helpers.expectRegister(result, "a", 0x0F);
    try helpers.expectZN(result, false, false);
}

test "AND: zero flag (0xFF & 0x00 = 0x00)" {
    const state = helpers.makeState(0xFF, 0, 0, helpers.clearFlags());
    const result = Opcodes.logicalAnd(state, 0x00);

    try helpers.expectRegister(result, "a", 0x00);
    try helpers.expectZN(result, true, false);
}

test "AND: negative flag (0xFF & 0x80 = 0x80)" {
    const state = helpers.makeState(0xFF, 0, 0, helpers.clearFlags());
    const result = Opcodes.logicalAnd(state, 0x80);

    try helpers.expectRegister(result, "a", 0x80);
    try helpers.expectZN(result, false, true);
}

// ============================================================================
// ORA Tests
// ============================================================================

test "ORA: basic operation (0x0F | 0xF0 = 0xFF)" {
    const state = helpers.makeState(0x0F, 0, 0, helpers.clearFlags());
    const result = Opcodes.logicalOr(state, 0xF0);

    try helpers.expectRegister(result, "a", 0xFF);
    try helpers.expectZN(result, false, true);
}

test "ORA: zero flag (0x00 | 0x00 = 0x00)" {
    const state = helpers.makeState(0x00, 0, 0, helpers.clearFlags());
    const result = Opcodes.logicalOr(state, 0x00);

    try helpers.expectRegister(result, "a", 0x00);
    try helpers.expectZN(result, true, false);
}

test "ORA: sets negative flag (0x00 | 0x80 = 0x80)" {
    const state = helpers.makeState(0x00, 0, 0, helpers.clearFlags());
    const result = Opcodes.logicalOr(state, 0x80);

    try helpers.expectRegister(result, "a", 0x80);
    try helpers.expectZN(result, false, true);
}

// ============================================================================
// EOR Tests
// ============================================================================

test "EOR: basic operation (0xFF ^ 0x0F = 0xF0)" {
    const state = helpers.makeState(0xFF, 0, 0, helpers.clearFlags());
    const result = Opcodes.logicalXor(state, 0x0F);

    try helpers.expectRegister(result, "a", 0xF0);
    try helpers.expectZN(result, false, true);
}

test "EOR: zero flag (0x55 ^ 0x55 = 0x00)" {
    const state = helpers.makeState(0x55, 0, 0, helpers.clearFlags());
    const result = Opcodes.logicalXor(state, 0x55);

    try helpers.expectRegister(result, "a", 0x00);
    try helpers.expectZN(result, true, false);
}

test "EOR: toggle bits (0xAA ^ 0xFF = 0x55)" {
    const state = helpers.makeState(0xAA, 0, 0, helpers.clearFlags());
    const result = Opcodes.logicalXor(state, 0xFF);

    try helpers.expectRegister(result, "a", 0x55);
    try helpers.expectZN(result, false, false);
}
