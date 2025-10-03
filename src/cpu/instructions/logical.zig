//! Logical Instructions: AND, ORA, EOR
//!
//! These instructions perform bitwise logical operations on the accumulator.
//! All update N and Z flags based on the result.

const std = @import("std");
const Cpu = @import("../Cpu.zig");
const Bus = @import("../../bus/Bus.zig").Bus;
const helpers = @import("../helpers.zig");

const State = Cpu.State.State;

/// AND - Logical AND
/// A = A & M
/// Flags: N, Z
///
/// Supports all addressing modes (8 total)
pub fn logicalAnd(state: *State, bus: *Bus) bool {
    const value = helpers.readOperand(state, bus);

    state.a &= value;
    state.p.updateZN(state.a);

    return true;
}

/// ORA - Logical OR
/// A = A | M
/// Flags: N, Z
///
/// Supports all addressing modes (8 total)
pub fn logicalOr(state: *State, bus: *Bus) bool {
    const value = helpers.readOperand(state, bus);

    state.a |= value;
    state.p.updateZN(state.a);

    return true;
}

/// EOR - Logical Exclusive OR
/// A = A ^ M
/// Flags: N, Z
///
/// Supports all addressing modes (8 total)
pub fn logicalXor(state: *State, bus: *Bus) bool {
    const value = helpers.readOperand(state, bus);

    state.a ^= value;
    state.p.updateZN(state.a);

    return true;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "AND: immediate mode - basic operation" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0xFF;
    state.pc = 0x0000;
    bus.ram[0] = 0x0F;
    state.address_mode = .immediate;

    _ = logicalAnd(&state, &bus);

    try testing.expectEqual(@as(u8, 0x0F), state.a);
    try testing.expect(!state.p.zero);
    try testing.expect(!state.p.negative);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "AND: zero flag" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x0F;
    state.pc = 0x0000;
    bus.ram[0] = 0xF0;
    state.address_mode = .immediate;

    _ = logicalAnd(&state, &bus);

    try testing.expectEqual(@as(u8, 0x00), state.a);
    try testing.expect(state.p.zero);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "AND: negative flag" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0xFF;
    state.pc = 0x0000;
    bus.ram[0] = 0x80;
    state.address_mode = .immediate;

    _ = logicalAnd(&state, &bus);

    try testing.expectEqual(@as(u8, 0x80), state.a);
    try testing.expect(state.p.negative);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "ORA: immediate mode - basic operation" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x0F;
    state.pc = 0x0000;
    bus.ram[0] = 0xF0;
    state.address_mode = .immediate;

    _ = logicalOr(&state, &bus);

    try testing.expectEqual(@as(u8, 0xFF), state.a);
    try testing.expect(!state.p.zero);
    try testing.expect(state.p.negative);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "ORA: zero to non-zero" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x00;
    state.pc = 0x0000;
    bus.ram[0] = 0x42;
    state.address_mode = .immediate;

    _ = logicalOr(&state, &bus);

    try testing.expectEqual(@as(u8, 0x42), state.a);
    try testing.expect(!state.p.zero);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "ORA: both zero" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x00;
    state.pc = 0x0000;
    bus.ram[0] = 0x00;
    state.address_mode = .immediate;

    _ = logicalOr(&state, &bus);

    try testing.expectEqual(@as(u8, 0x00), state.a);
    try testing.expect(state.p.zero);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "EOR: immediate mode - basic operation" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0xFF;
    state.pc = 0x0000;
    bus.ram[0] = 0x0F;
    state.address_mode = .immediate;

    _ = logicalXor(&state, &bus);

    try testing.expectEqual(@as(u8, 0xF0), state.a);
    try testing.expect(!state.p.zero);
    try testing.expect(state.p.negative);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "EOR: same values give zero" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x42;
    state.pc = 0x0000;
    bus.ram[0] = 0x42;
    state.address_mode = .immediate;

    _ = logicalXor(&state, &bus);

    try testing.expectEqual(@as(u8, 0x00), state.a);
    try testing.expect(state.p.zero);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "EOR: invert bits" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0xAA; // 10101010
    state.pc = 0x0000;
    bus.ram[0] = 0xFF;
    state.address_mode = .immediate;

    _ = logicalXor(&state, &bus);

    try testing.expectEqual(@as(u8, 0x55), state.a); // 01010101
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}
