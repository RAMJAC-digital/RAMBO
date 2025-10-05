//! Pure Functional Tests for Branch Instructions

const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");

const RAMBO = @import("RAMBO");
const Opcodes = RAMBO.Cpu.opcodes;

test "BCC: branch when carry clear" {
    const state = helpers.makeState(0, 0, 0, helpers.clearFlags());
    const result = Opcodes.bcc(state, 0x10); // offset

    try testing.expect(result.pc != null); // Branch taken
}

test "BCC: no branch when carry set" {
    const state = helpers.makeState(0, 0, 0, helpers.flagsWithCarry());
    const result = Opcodes.bcc(state, 0x10);

    try testing.expect(result.pc == null); // Branch not taken
}

test "BCS: branch when carry set" {
    const state = helpers.makeState(0, 0, 0, helpers.flagsWithCarry());
    const result = Opcodes.bcs(state, 0x10);

    try testing.expect(result.pc != null);
}

test "BCS: no branch when carry clear" {
    const state = helpers.makeState(0, 0, 0, helpers.clearFlags());
    const result = Opcodes.bcs(state, 0x10);

    try testing.expect(result.pc == null);
}

test "BEQ: branch when zero set" {
    const state = helpers.makeState(0, 0, 0, helpers.makeFlags(true, false, false, false));
    const result = Opcodes.beq(state, 0x10);

    try testing.expect(result.pc != null);
}

test "BEQ: no branch when zero clear" {
    const state = helpers.makeState(0, 0, 0, helpers.clearFlags());
    const result = Opcodes.beq(state, 0x10);

    try testing.expect(result.pc == null);
}

test "BNE: branch when zero clear" {
    const state = helpers.makeState(0, 0, 0, helpers.clearFlags());
    const result = Opcodes.bne(state, 0x10);

    try testing.expect(result.pc != null);
}

test "BNE: no branch when zero set" {
    const state = helpers.makeState(0, 0, 0, helpers.makeFlags(true, false, false, false));
    const result = Opcodes.bne(state, 0x10);

    try testing.expect(result.pc == null);
}

test "BMI: branch when negative set" {
    const state = helpers.makeState(0, 0, 0, helpers.makeFlags(false, true, false, false));
    const result = Opcodes.bmi(state, 0x10);

    try testing.expect(result.pc != null);
}

test "BPL: branch when negative clear" {
    const state = helpers.makeState(0, 0, 0, helpers.clearFlags());
    const result = Opcodes.bpl(state, 0x10);

    try testing.expect(result.pc != null);
}

test "BVC: branch when overflow clear" {
    const state = helpers.makeState(0, 0, 0, helpers.clearFlags());
    const result = Opcodes.bvc(state, 0x10);

    try testing.expect(result.pc != null);
}

test "BVS: branch when overflow set" {
    const state = helpers.makeState(0, 0, 0, helpers.makeFlags(false, false, false, true));
    const result = Opcodes.bvs(state, 0x10);

    try testing.expect(result.pc != null);
}
