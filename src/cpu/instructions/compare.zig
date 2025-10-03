//! Compare Instructions: CMP, CPX, CPY
//!
//! These instructions perform subtraction without storing the result,
//! only updating flags to indicate the relationship between values.
//!
//! Flags set:
//! - Carry: Set if Register >= Memory (no borrow needed)
//! - Zero: Set if Register == Memory
//! - Negative: Set if bit 7 of (Register - Memory) is set

const std = @import("std");
const Cpu = @import("../Cpu.zig");
const Bus = @import("../../bus/Bus.zig").Bus;
const helpers = @import("../helpers.zig");

const State = Cpu.State;

/// CMP - Compare Accumulator
/// Compare A with M (A - M)
/// Flags: N, Z, C
///
/// Supports all addressing modes (8 total)
pub fn cmp(state: *State, bus: *Bus) bool {
    const value = helpers.readOperand(state, bus);

    // Perform comparison (subtraction without storing)
    const result = state.a -% value;

    // Set flags
    state.p.carry = state.a >= value; // No borrow if A >= M
    state.p.zero = state.a == value;
    state.p.negative = (result & 0x80) != 0;

    return true;
}

/// CPX - Compare X Register
/// Compare X with M (X - M)
/// Flags: N, Z, C
///
/// Supports: Immediate, Zero Page, Absolute
pub fn cpx(state: *State, bus: *Bus) bool {
    const value = helpers.readOperand(state, bus);

    // Perform comparison
    const result = state.x -% value;

    // Set flags
    state.p.carry = state.x >= value;
    state.p.zero = state.x == value;
    state.p.negative = (result & 0x80) != 0;

    return true;
}

/// CPY - Compare Y Register
/// Compare Y with M (Y - M)
/// Flags: N, Z, C
///
/// Supports: Immediate, Zero Page, Absolute
pub fn cpy(state: *State, bus: *Bus) bool {
    const value = helpers.readOperand(state, bus);

    // Perform comparison
    const result = state.y -% value;

    // Set flags
    state.p.carry = state.y >= value;
    state.p.zero = state.y == value;
    state.p.negative = (result & 0x80) != 0;

    return true;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "CMP: equal values" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x42;
    state.pc = 0x0000;
    bus.ram[0] = 0x42;
    state.address_mode = .immediate;

    _ = cmp(&state, &bus);

    try testing.expect(state.p.carry); // A >= M
    try testing.expect(state.p.zero); // A == M
    try testing.expect(!state.p.negative);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "CMP: A greater than M" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x50;
    state.pc = 0x0000;
    bus.ram[0] = 0x30;
    state.address_mode = .immediate;

    _ = cmp(&state, &bus);

    try testing.expect(state.p.carry); // A >= M
    try testing.expect(!state.p.zero); // A != M
    try testing.expect(!state.p.negative); // Result is positive
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "CMP: A less than M" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x30;
    state.pc = 0x0000;
    bus.ram[0] = 0x50;
    state.address_mode = .immediate;

    _ = cmp(&state, &bus);

    try testing.expect(!state.p.carry); // A < M (borrow needed)
    try testing.expect(!state.p.zero);
    try testing.expect(state.p.negative); // Result is negative (0x30 - 0x50 = 0xE0)
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "CMP: negative flag behavior" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x00;
    state.pc = 0x0000;
    bus.ram[0] = 0x01;
    state.address_mode = .immediate;

    _ = cmp(&state, &bus);

    try testing.expect(!state.p.carry);
    try testing.expect(!state.p.zero);
    try testing.expect(state.p.negative); // 0x00 - 0x01 = 0xFF (negative)
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "CPX: equal values" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.x = 0x42;
    state.pc = 0x0000;
    bus.ram[0] = 0x42;
    state.address_mode = .immediate;

    _ = cpx(&state, &bus);

    try testing.expect(state.p.carry);
    try testing.expect(state.p.zero);
    try testing.expect(!state.p.negative);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "CPX: X greater than M" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.x = 0x80;
    state.pc = 0x0000;
    bus.ram[0] = 0x40;
    state.address_mode = .immediate;

    _ = cpx(&state, &bus);

    try testing.expect(state.p.carry);
    try testing.expect(!state.p.zero);
    try testing.expect(!state.p.negative);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "CPX: X less than M" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.x = 0x40;
    state.pc = 0x0000;
    bus.ram[0] = 0x80;
    state.address_mode = .immediate;

    _ = cpx(&state, &bus);

    try testing.expect(!state.p.carry);
    try testing.expect(!state.p.zero);
    try testing.expect(state.p.negative);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "CPY: equal values" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.y = 0x42;
    state.pc = 0x0000;
    bus.ram[0] = 0x42;
    state.address_mode = .immediate;

    _ = cpy(&state, &bus);

    try testing.expect(state.p.carry);
    try testing.expect(state.p.zero);
    try testing.expect(!state.p.negative);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "CPY: Y greater than M" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.y = 0xFF;
    state.pc = 0x0000;
    bus.ram[0] = 0x01;
    state.address_mode = .immediate;

    _ = cpy(&state, &bus);

    try testing.expect(state.p.carry);
    try testing.expect(!state.p.zero);
    try testing.expect(state.p.negative); // 0xFF - 0x01 = 0xFE (negative)
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "CPY: Y less than M" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.y = 0x01;
    state.pc = 0x0000;
    bus.ram[0] = 0xFF;
    state.address_mode = .immediate;

    _ = cpy(&state, &bus);

    try testing.expect(!state.p.carry);
    try testing.expect(!state.p.zero);
    try testing.expect(!state.p.negative); // 0x01 - 0xFF = 0x02 (wraps, positive)
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}
