//! Pure Functional Tests for Jump/Control Flow Instructions

const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");

const RAMBO = @import("RAMBO");
const Opcodes = RAMBO.Cpu.opcodes;

test "JMP absolute: sets PC to target address" {
    var state = helpers.makeState(0, 0, 0, helpers.clearFlags());
    state.effective_address = 0x1234;
    const result = Opcodes.jmp(state, 0);

    try testing.expect(result.pc != null);
    try testing.expectEqual(@as(u16, 0x1234), result.pc.?);
}

test "JMP indirect: uses effective address" {
    var state = helpers.makeState(0, 0, 0, helpers.clearFlags());
    state.effective_address = 0x5678;
    const result = Opcodes.jmp(state, 0);

    try testing.expect(result.pc != null);
    try testing.expectEqual(@as(u16, 0x5678), result.pc.?);
}

test "NOP: does nothing" {
    const state = helpers.makeState(0x42, 0x43, 0x44, helpers.flagsWithCarry());
    const result = Opcodes.nop(state, 0);

    // No registers should change
    try testing.expect(result.a == null);
    try testing.expect(result.x == null);
    try testing.expect(result.y == null);
    try testing.expect(result.flags == null);
}

// Note: JSR, RTS, RTI, BRK tests would go here
// These may not be implemented in pure functional form yet
// (they require multi-stack operations)

test "Placeholder: JSR implementation pending" {
    // JSR requires pushing PC high then PC low (2 push operations)
    // Current OpcodeResult only supports single push
    // See PURE-FUNCTIONAL-ARCHITECTURE.md for implementation plan
    try testing.expect(true);
}

test "Placeholder: RTS implementation pending" {
    try testing.expect(true);
}

test "Placeholder: RTI implementation pending" {
    try testing.expect(true);
}

test "Placeholder: BRK implementation pending" {
    try testing.expect(true);
}
