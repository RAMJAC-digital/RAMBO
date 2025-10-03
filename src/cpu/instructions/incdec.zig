const std = @import("std");
const Cpu = @import("../Cpu.zig");
const Bus = @import("../../bus/Bus.zig").Bus;

const State = Cpu.State;

// ============================================================================
// INC - Increment Memory
// ============================================================================

/// INC - Increment memory by one
/// Flags: N Z
pub fn inc(state: *State, bus: *Bus) bool {
    // Value already in temp_value from RMW read
    const value = state.temp_value +% 1;
    state.p.updateZN(value);

    // Write modified value
    bus.write(state.effective_address, value);
    return true;
}

// ============================================================================
// DEC - Decrement Memory
// ============================================================================

/// DEC - Decrement memory by one
/// Flags: N Z
pub fn dec(state: *State, bus: *Bus) bool {
    // Value already in temp_value from RMW read
    const value = state.temp_value -% 1;
    state.p.updateZN(value);

    // Write modified value
    bus.write(state.effective_address, value);
    return true;
}

// ============================================================================
// INX - Increment X Register
// ============================================================================

/// INX - Increment X register by one
/// Flags: N Z
pub fn inx(state: *State, bus: *Bus) bool {
    _ = bus;
    state.x +%= 1;
    state.p.updateZN(state.x);
    return true;
}

// ============================================================================
// INY - Increment Y Register
// ============================================================================

/// INY - Increment Y register by one
/// Flags: N Z
pub fn iny(state: *State, bus: *Bus) bool {
    _ = bus;
    state.y +%= 1;
    state.p.updateZN(state.y);
    return true;
}

// ============================================================================
// DEX - Decrement X Register
// ============================================================================

/// DEX - Decrement X register by one
/// Flags: N Z
pub fn dex(state: *State, bus: *Bus) bool {
    _ = bus;
    state.x -%= 1;
    state.p.updateZN(state.x);
    return true;
}

// ============================================================================
// DEY - Decrement Y Register
// ============================================================================

/// DEY - Decrement Y register by one
/// Flags: N Z
pub fn dey(state: *State, bus: *Bus) bool {
    _ = bus;
    state.y -%= 1;
    state.p.updateZN(state.y);
    return true;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "INC - basic increment" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.temp_value = 0x42;
    state.effective_address = 0x0010;

    const complete = inc(&state, &bus);
    try testing.expect(complete);
    try testing.expectEqual(@as(u8, 0x43), bus.ram[0x10]);
    try testing.expect(!state.p.zero);
    try testing.expect(!state.p.negative);
}

test "INC - zero flag" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.temp_value = 0xFF;
    state.effective_address = 0x0010;

    _ = inc(&state, &bus);
    try testing.expectEqual(@as(u8, 0x00), bus.ram[0x10]);
    try testing.expect(state.p.zero);
}

test "DEC - basic decrement" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.temp_value = 0x42;
    state.effective_address = 0x0010;

    _ = dec(&state, &bus);
    try testing.expectEqual(@as(u8, 0x41), bus.ram[0x10]);
    try testing.expect(!state.p.zero);
}

test "INX - increment X" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.x = 0x10;
    _ = inx(&state, &bus);
    try testing.expectEqual(@as(u8, 0x11), state.x);
}

test "DEX - decrement X with wrap" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.x = 0x00;
    _ = dex(&state, &bus);
    try testing.expectEqual(@as(u8, 0xFF), state.x);
    try testing.expect(state.p.negative);
}

test "INY - increment Y" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.y = 0xFE;
    _ = iny(&state, &bus);
    try testing.expectEqual(@as(u8, 0xFF), state.y);
    try testing.expect(state.p.negative);
}

test "DEY - decrement Y with zero" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.y = 0x01;
    _ = dey(&state, &bus);
    try testing.expectEqual(@as(u8, 0x00), state.y);
    try testing.expect(state.p.zero);
}
