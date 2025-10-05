//! Pure Functional Tests for Transfer and Flag Instructions
//!
//! Tests TAX, TXA, TAY, TYA, TSX, TXS, CLC, SEC, CLI, SEI, CLV, CLD, SED opcodes.
//!
//! Migrated from: docs/archive/old-imperative-cpu/implementation/transfer.zig

const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");

const RAMBO = @import("RAMBO");
const Opcodes = RAMBO.Cpu.opcodes;

test "TAX: transfers A to X with flags (0x42)" {
    const state = helpers.makeState(0x42, 0, 0, helpers.clearFlags());
    const result = Opcodes.tax(state, 0);

    try helpers.expectRegister(result, "x", 0x42);
    try helpers.expectZN(result, false, false);
}

test "TXA: transfers X to A with flags (0x80)" {
    const state = helpers.makeState(0, 0x80, 0, helpers.clearFlags());
    const result = Opcodes.txa(state, 0);

    try helpers.expectRegister(result, "a", 0x80);
    try helpers.expectZN(result, false, true);
}

test "TAY: transfers A to Y with zero flag (0x00)" {
    const state = helpers.makeState(0x00, 0, 0xFF, helpers.clearFlags());
    const result = Opcodes.tay(state, 0);

    try helpers.expectRegister(result, "y", 0x00);
    try helpers.expectZN(result, true, false);
}

test "TYA: transfers Y to A (0x42)" {
    const state = helpers.makeState(0, 0, 0x42, helpers.clearFlags());
    const result = Opcodes.tya(state, 0);

    try helpers.expectRegister(result, "a", 0x42);
    try helpers.expectZN(result, false, false);
}

test "TSX: transfers SP to X (0xFD)" {
    var state = helpers.makeState(0, 0, 0, helpers.clearFlags());
    state.sp = 0xFD;
    const result = Opcodes.tsx(state, 0);

    try helpers.expectRegister(result, "x", 0xFD);
    try helpers.expectZN(result, false, true);
}

test "TXS: transfers X to SP, no flags affected" {
    const state = helpers.makeState(0, 0x42, 0, helpers.clearFlags());
    const result = Opcodes.txs(state, 0);

    try helpers.expectRegister(result, "sp", 0x42);
    try testing.expect(result.flags == null); // TXS doesn't affect flags
}

test "CLC: clears carry flag" {
    const state = helpers.makeState(0, 0, 0, helpers.flagsWithCarry());
    const result = Opcodes.clc(state, 0);

    const flags = result.flags.?;
    try testing.expect(!flags.carry);
}

test "SEC: sets carry flag" {
    const state = helpers.makeState(0, 0, 0, helpers.clearFlags());
    const result = Opcodes.sec(state, 0);

    const flags = result.flags.?;
    try testing.expect(flags.carry);
}

test "CLI: clears interrupt disable" {
    var state = helpers.makeState(0, 0, 0, helpers.clearFlags());
    state.p.interrupt = true;
    const result = Opcodes.cli(state, 0);

    const flags = result.flags.?;
    try testing.expect(!flags.interrupt);
}

test "SEI: sets interrupt disable" {
    const state = helpers.makeState(0, 0, 0, helpers.clearFlags());
    const result = Opcodes.sei(state, 0);

    const flags = result.flags.?;
    try testing.expect(flags.interrupt);
}

test "CLV: clears overflow flag" {
    const state = helpers.makeState(0, 0, 0, helpers.makeFlags(false, false, false, true));
    const result = Opcodes.clv(state, 0);

    const flags = result.flags.?;
    try testing.expect(!flags.overflow);
}

test "CLD: clears decimal flag" {
    var state = helpers.makeState(0, 0, 0, helpers.clearFlags());
    state.p.decimal = true;
    const result = Opcodes.cld(state, 0);

    const flags = result.flags.?;
    try testing.expect(!flags.decimal);
}

test "SED: sets decimal flag" {
    const state = helpers.makeState(0, 0, 0, helpers.clearFlags());
    const result = Opcodes.sed(state, 0);

    const flags = result.flags.?;
    try testing.expect(flags.decimal);
}

// ============================================================================
// Comprehensive Flag Preservation Tests
// ============================================================================

test "Transfer: all transfers preserve unaffected flags" {
    // TAX preserves C and V
    const state1 = helpers.makeState(0x42, 0, 0, helpers.makeFlags(false, false, true, true));
    const result1 = Opcodes.tax(state1, 0);
    const flags1 = result1.flags.?;
    try testing.expect(flags1.carry);
    try testing.expect(flags1.overflow);

    // TXA preserves C and V
    const state2 = helpers.makeState(0, 0x42, 0, helpers.makeFlags(false, false, true, true));
    const result2 = Opcodes.txa(state2, 0);
    const flags2 = result2.flags.?;
    try testing.expect(flags2.carry);
    try testing.expect(flags2.overflow);
}

test "Flag operations: each flag independent" {
    var state = helpers.makeState(0, 0, 0, helpers.clearFlags());

    // Set carry
    const result1 = Opcodes.sec(state, 0);
    state.p = result1.flags.?;
    try testing.expect(state.p.carry);
    try testing.expect(!state.p.interrupt);

    // Set interrupt
    const result2 = Opcodes.sei(state, 0);
    state.p = result2.flags.?;
    try testing.expect(state.p.carry); // Preserved
    try testing.expect(state.p.interrupt);

    // Clear carry
    const result3 = Opcodes.clc(state, 0);
    state.p = result3.flags.?;
    try testing.expect(!state.p.carry);
    try testing.expect(state.p.interrupt); // Preserved
}

test "TSX/TXS: boundary values (0x00, 0xFF)" {
    // TSX with SP=0x00
    var state1 = helpers.makeState(0, 0, 0, helpers.clearFlags());
    state1.sp = 0x00;
    const result1 = Opcodes.tsx(state1, 0);
    try helpers.expectRegister(result1, "x", 0x00);
    try helpers.expectZN(result1, true, false);

    // TSX with SP=0xFF
    var state2 = helpers.makeState(0, 0, 0, helpers.clearFlags());
    state2.sp = 0xFF;
    const result2 = Opcodes.tsx(state2, 0);
    try helpers.expectRegister(result2, "x", 0xFF);
    try helpers.expectZN(result2, false, true);

    // TXS with X=0x00
    const state3 = helpers.makeState(0, 0x00, 0, helpers.clearFlags());
    const result3 = Opcodes.txs(state3, 0);
    try helpers.expectRegister(result3, "sp", 0x00);

    // TXS with X=0xFF
    const state4 = helpers.makeState(0, 0xFF, 0, helpers.clearFlags());
    const result4 = Opcodes.txs(state4, 0);
    try helpers.expectRegister(result4, "sp", 0xFF);
}
