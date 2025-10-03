//! Logical Instructions: AND, ORA, EOR
//!
//! These instructions perform bitwise logical operations on the accumulator.
//! All update N and Z flags based on the result.

const std = @import("std");
const Cpu = @import("../Cpu.zig").Cpu;
const Bus = @import("../../bus/Bus.zig").Bus;
const helpers = @import("../helpers.zig");

/// AND - Logical AND
/// A = A & M
/// Flags: N, Z
///
/// Supports all addressing modes (8 total)
pub fn logicalAnd(cpu: *Cpu, bus: *Bus) bool {
    const value = helpers.readOperand(cpu, bus);

    cpu.a &= value;
    cpu.p.updateZN(cpu.a);

    return true;
}

/// ORA - Logical OR
/// A = A | M
/// Flags: N, Z
///
/// Supports all addressing modes (8 total)
pub fn logicalOr(cpu: *Cpu, bus: *Bus) bool {
    const value = helpers.readOperand(cpu, bus);

    cpu.a |= value;
    cpu.p.updateZN(cpu.a);

    return true;
}

/// EOR - Logical Exclusive OR
/// A = A ^ M
/// Flags: N, Z
///
/// Supports all addressing modes (8 total)
pub fn logicalXor(cpu: *Cpu, bus: *Bus) bool {
    const value = helpers.readOperand(cpu, bus);

    cpu.a ^= value;
    cpu.p.updateZN(cpu.a);

    return true;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "AND: immediate mode - basic operation" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0xFF;
    cpu.pc = 0x0000;
    bus.ram[0] = 0x0F;
    cpu.address_mode = .immediate;

    _ = logicalAnd(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x0F), cpu.a);
    try testing.expect(!cpu.p.zero);
    try testing.expect(!cpu.p.negative);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "AND: zero flag" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x0F;
    cpu.pc = 0x0000;
    bus.ram[0] = 0xF0;
    cpu.address_mode = .immediate;

    _ = logicalAnd(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x00), cpu.a);
    try testing.expect(cpu.p.zero);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "AND: negative flag" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0xFF;
    cpu.pc = 0x0000;
    bus.ram[0] = 0x80;
    cpu.address_mode = .immediate;

    _ = logicalAnd(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x80), cpu.a);
    try testing.expect(cpu.p.negative);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "ORA: immediate mode - basic operation" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x0F;
    cpu.pc = 0x0000;
    bus.ram[0] = 0xF0;
    cpu.address_mode = .immediate;

    _ = logicalOr(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0xFF), cpu.a);
    try testing.expect(!cpu.p.zero);
    try testing.expect(cpu.p.negative);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "ORA: zero to non-zero" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x00;
    cpu.pc = 0x0000;
    bus.ram[0] = 0x42;
    cpu.address_mode = .immediate;

    _ = logicalOr(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x42), cpu.a);
    try testing.expect(!cpu.p.zero);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "ORA: both zero" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x00;
    cpu.pc = 0x0000;
    bus.ram[0] = 0x00;
    cpu.address_mode = .immediate;

    _ = logicalOr(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x00), cpu.a);
    try testing.expect(cpu.p.zero);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "EOR: immediate mode - basic operation" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0xFF;
    cpu.pc = 0x0000;
    bus.ram[0] = 0x0F;
    cpu.address_mode = .immediate;

    _ = logicalXor(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0xF0), cpu.a);
    try testing.expect(!cpu.p.zero);
    try testing.expect(cpu.p.negative);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "EOR: same values give zero" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x42;
    cpu.pc = 0x0000;
    bus.ram[0] = 0x42;
    cpu.address_mode = .immediate;

    _ = logicalXor(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x00), cpu.a);
    try testing.expect(cpu.p.zero);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "EOR: invert bits" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0xAA; // 10101010
    cpu.pc = 0x0000;
    bus.ram[0] = 0xFF;
    cpu.address_mode = .immediate;

    _ = logicalXor(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x55), cpu.a); // 01010101
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}
