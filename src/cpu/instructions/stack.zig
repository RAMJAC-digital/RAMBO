//! Stack Instructions
//!
//! PHA - Push Accumulator
//! PHP - Push Processor Status
//! PLA - Pull Accumulator
//! PLP - Pull Processor Status

const std = @import("std");
const Cpu = @import("../Cpu.zig");
const Bus = @import("../../bus/Bus.zig").Bus;
const Logic = @import("../Logic.zig");

const State = Cpu.State.State;

/// PHA - Push Accumulator
/// Push A onto stack
/// No flags affected
///
/// 3 cycles total
pub fn pha(state: *State, bus: *Bus) bool {
    Logic.push(state, bus, state.a);
    return true;
}

/// PHP - Push Processor Status
/// Push P onto stack with B flag set
/// No flags affected
///
/// 3 cycles total
pub fn php(state: *State, bus: *Bus) bool {
    var status = state.p.toByte();
    status |= 0x10; // Set B flag (bit 4)
    Logic.push(state, bus, status);
    return true;
}

/// PLA - Pull Accumulator
/// Pull A from stack
/// Flags: N, Z
///
/// 4 cycles total
pub fn pla(state: *State, bus: *Bus) bool {
    state.a = Logic.pull(state, bus);
    state.p.updateZN(state.a);
    return true;
}

/// PLP - Pull Processor Status
/// Pull P from stack
/// Flags: All (restored from stack)
///
/// 4 cycles total
pub fn plp(state: *State, bus: *Bus) bool {
    const status = Logic.pull(state, bus);
    state.p = @TypeOf(state.p).fromByte(status);
    return true;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "PHA: push accumulator" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.sp = 0xFF;
    state.a = 0x42;

    _ = pha(&state, &bus);

    try testing.expectEqual(@as(u8, 0x42), bus.read(0x01FF));
    try testing.expectEqual(@as(u8, 0xFE), state.sp);
}

test "PHP: push status with B flag" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.sp = 0xFF;
    state.p.carry = true;
    state.p.zero = true;
    state.p.negative = true;

    _ = php(&state, &bus);

    const status = bus.read(0x01FF);
    try testing.expectEqual(@as(u8, 1), (status >> 0) & 1); // Carry
    try testing.expectEqual(@as(u8, 1), (status >> 1) & 1); // Zero
    try testing.expectEqual(@as(u8, 1), (status >> 4) & 1); // B flag set
    try testing.expectEqual(@as(u8, 1), (status >> 7) & 1); // Negative
    try testing.expectEqual(@as(u8, 0xFE), state.sp);
}

test "PLA: pull accumulator and update flags" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.sp = 0xFE;
    bus.write(0x01FF, 0x80);

    _ = pla(&state, &bus);

    try testing.expectEqual(@as(u8, 0x80), state.a);
    try testing.expect(state.p.negative); // 0x80 has bit 7 set
    try testing.expect(!state.p.zero);
    try testing.expectEqual(@as(u8, 0xFF), state.sp);
}

test "PLA: zero flag" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.sp = 0xFE;
    bus.write(0x01FF, 0x00);

    _ = pla(&state, &bus);

    try testing.expectEqual(@as(u8, 0x00), state.a);
    try testing.expect(state.p.zero);
    try testing.expect(!state.p.negative);
}

test "PLP: pull status flags" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.sp = 0xFE;
    bus.write(0x01FF, 0b11000011); // N=1, V=1, Z=1, C=1

    _ = plp(&state, &bus);

    try testing.expect(state.p.carry);
    try testing.expect(state.p.zero);
    try testing.expect(state.p.overflow);
    try testing.expect(state.p.negative);
    try testing.expectEqual(@as(u8, 0xFF), state.sp);
}

test "PHA and PLA: round trip" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.sp = 0xFF;
    state.a = 0x55;

    // Push
    _ = pha(&state, &bus);
    try testing.expectEqual(@as(u8, 0xFE), state.sp);

    // Modify A
    state.a = 0x00;

    // Pull
    _ = pla(&state, &bus);
    try testing.expectEqual(@as(u8, 0x55), state.a);
    try testing.expectEqual(@as(u8, 0xFF), state.sp); // Stack balanced
}

test "PHP and PLP: round trip" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.sp = 0xFF;
    state.p.carry = true;
    state.p.overflow = true;

    // Push
    _ = php(&state, &bus);

    // Modify flags
    state.p.carry = false;
    state.p.overflow = false;
    state.p.zero = true;

    // Pull
    _ = plp(&state, &bus);
    try testing.expect(state.p.carry); // Restored
    try testing.expect(state.p.overflow); // Restored
    try testing.expect(!state.p.zero); // Was false when pushed
    try testing.expectEqual(@as(u8, 0xFF), state.sp); // Stack balanced
}
