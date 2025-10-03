const std = @import("std");
const Cpu = @import("../Cpu.zig");
const Bus = @import("../../bus/Bus.zig").Bus;

const State = Cpu.State;

// ============================================================================
// ASL - Arithmetic Shift Left
// ============================================================================

/// ASL - Shift left one bit (memory or accumulator)
/// Flags: N Z C
pub fn asl(state: *State, bus: *Bus) bool {
    var value: u8 = undefined;

    if (state.address_mode == .accumulator) {
        // Accumulator mode - no memory access
        value = state.a;
        state.p.carry = (value & 0x80) != 0;
        value <<= 1;
        state.a = value;
        state.p.updateZN(value);
        return true;
    }

    // Memory mode - value already in temp_value from RMW read
    value = state.temp_value;
    state.p.carry = (value & 0x80) != 0;
    value <<= 1;
    state.p.updateZN(value);

    // Write modified value
    bus.write(state.effective_address, value);
    return true;
}

// ============================================================================
// LSR - Logical Shift Right
// ============================================================================

/// LSR - Shift right one bit (memory or accumulator)
/// Flags: N(0) Z C
pub fn lsr(state: *State, bus: *Bus) bool {
    var value: u8 = undefined;

    if (state.address_mode == .accumulator) {
        // Accumulator mode
        value = state.a;
        state.p.carry = (value & 0x01) != 0;
        value >>= 1;
        state.a = value;
        state.p.updateZN(value);
        return true;
    }

    // Memory mode
    value = state.temp_value;
    state.p.carry = (value & 0x01) != 0;
    value >>= 1;
    state.p.updateZN(value);

    bus.write(state.effective_address, value);
    return true;
}

// ============================================================================
// ROL - Rotate Left
// ============================================================================

/// ROL - Rotate left one bit (memory or accumulator)
/// Flags: N Z C
pub fn rol(state: *State, bus: *Bus) bool {
    var value: u8 = undefined;

    if (state.address_mode == .accumulator) {
        value = state.a;
        const old_carry: u8 = if (state.p.carry) 1 else 0;
        state.p.carry = (value & 0x80) != 0;
        value = (value << 1) | old_carry;
        state.a = value;
        state.p.updateZN(value);
        return true;
    }

    // Memory mode
    value = state.temp_value;
    const old_carry: u8 = if (state.p.carry) 1 else 0;
    state.p.carry = (value & 0x80) != 0;
    value = (value << 1) | old_carry;
    state.p.updateZN(value);

    bus.write(state.effective_address, value);
    return true;
}

// ============================================================================
// ROR - Rotate Right
// ============================================================================

/// ROR - Rotate right one bit (memory or accumulator)
/// Flags: N Z C
pub fn ror(state: *State, bus: *Bus) bool {
    var value: u8 = undefined;

    if (state.address_mode == .accumulator) {
        value = state.a;
        const old_carry: u8 = if (state.p.carry) 1 else 0;
        state.p.carry = (value & 0x01) != 0;
        value = (value >> 1) | (old_carry << 7);
        state.a = value;
        state.p.updateZN(value);
        return true;
    }

    // Memory mode
    value = state.temp_value;
    const old_carry: u8 = if (state.p.carry) 1 else 0;
    state.p.carry = (value & 0x01) != 0;
    value = (value >> 1) | (old_carry << 7);
    state.p.updateZN(value);

    bus.write(state.effective_address, value);
    return true;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "ASL accumulator - basic shift" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x42; // 01000010
    state.address_mode = .accumulator;

    const complete = asl(&state, &bus);
    try testing.expect(complete);
    try testing.expectEqual(@as(u8, 0x84), state.a); // 10000100
    try testing.expect(!state.p.carry); // No carry out
    try testing.expect(state.p.negative); // Bit 7 set
}

test "ASL accumulator - carry flag" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x81; // 10000001
    state.address_mode = .accumulator;

    _ = asl(&state, &bus);
    try testing.expectEqual(@as(u8, 0x02), state.a); // 00000010
    try testing.expect(state.p.carry); // Carry out from bit 7
}

test "LSR accumulator - basic shift" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x42; // 01000010
    state.address_mode = .accumulator;

    _ = lsr(&state, &bus);
    try testing.expectEqual(@as(u8, 0x21), state.a); // 00100001
    try testing.expect(!state.p.carry);
    try testing.expect(!state.p.negative); // Bit 7 always 0
}

test "ROL with carry" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x80; // 10000000
    state.p.carry = true;
    state.address_mode = .accumulator;

    _ = rol(&state, &bus);
    try testing.expectEqual(@as(u8, 0x01), state.a); // 00000001 (carry rotated in)
    try testing.expect(state.p.carry); // Bit 7 rotated out
}

test "ROR with carry" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x01; // 00000001
    state.p.carry = true;
    state.address_mode = .accumulator;

    _ = ror(&state, &bus);
    try testing.expectEqual(@as(u8, 0x80), state.a); // 10000000 (carry rotated in)
    try testing.expect(state.p.carry); // Bit 0 rotated out
}
