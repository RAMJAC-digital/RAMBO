//! Pure Functional Tests for Stack Instructions

const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");

const RAMBO = @import("RAMBO");
const Opcodes = RAMBO.Cpu.opcodes;

test "PHA: pushes accumulator" {
    const state = helpers.makeState(0x42, 0, 0, helpers.clearFlags());
    const result = Opcodes.pha(state, 0);

    try helpers.expectPush(result, 0x42);
}

test "PHP: pushes processor status" {
    const state = helpers.makeState(0, 0, 0, helpers.makeFlags(true, true, true, true));
    const result = Opcodes.php(state, 0);

    try testing.expect(result.push != null);
}

test "PLA: pulls to accumulator" {
    const state = helpers.makeState(0, 0, 0, helpers.clearFlags());
    const result = Opcodes.pla(state, 0x42); // Operand is value from stack

    try helpers.expectRegister(result, "a", 0x42);
    // Note: execution engine handles pull operation, not returned in OpcodeResult
}

test "PLA: sets zero flag" {
    const state = helpers.makeState(0xFF, 0, 0, helpers.clearFlags());
    const result = Opcodes.pla(state, 0x00);

    try helpers.expectRegister(result, "a", 0x00);
    try helpers.expectZN(result, true, false);
}

test "PLA: sets negative flag" {
    const state = helpers.makeState(0, 0, 0, helpers.clearFlags());
    const result = Opcodes.pla(state, 0x80);

    try helpers.expectRegister(result, "a", 0x80);
    try helpers.expectZN(result, false, true);
}

test "PLP: pulls processor status" {
    const state = helpers.makeState(0, 0, 0, helpers.clearFlags());
    const result = Opcodes.plp(state, 0xFF); // Pull all flags set

    // Execution engine handles pull, just verify flags were set
    try testing.expect(result.flags != null);
    const flags = result.flags.?;
    try testing.expect(flags.zero);
    try testing.expect(flags.negative);
    try testing.expect(flags.carry);
    try testing.expect(flags.overflow);
}
