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
const Cpu = @import("../Cpu.zig").Cpu;
const Bus = @import("../../bus/Bus.zig").Bus;
const helpers = @import("../helpers.zig");

/// CMP - Compare Accumulator
/// Compare A with M (A - M)
/// Flags: N, Z, C
///
/// Supports all addressing modes (8 total)
pub fn cmp(cpu: *Cpu, bus: *Bus) bool {
    const value = helpers.readOperand(cpu, bus);

    // Perform comparison (subtraction without storing)
    const result = cpu.a -% value;

    // Set flags
    cpu.p.carry = cpu.a >= value; // No borrow if A >= M
    cpu.p.zero = cpu.a == value;
    cpu.p.negative = (result & 0x80) != 0;

    return true;
}

/// CPX - Compare X Register
/// Compare X with M (X - M)
/// Flags: N, Z, C
///
/// Supports: Immediate, Zero Page, Absolute
pub fn cpx(cpu: *Cpu, bus: *Bus) bool {
    const value = helpers.readOperand(cpu, bus);

    // Perform comparison
    const result = cpu.x -% value;

    // Set flags
    cpu.p.carry = cpu.x >= value;
    cpu.p.zero = cpu.x == value;
    cpu.p.negative = (result & 0x80) != 0;

    return true;
}

/// CPY - Compare Y Register
/// Compare Y with M (Y - M)
/// Flags: N, Z, C
///
/// Supports: Immediate, Zero Page, Absolute
pub fn cpy(cpu: *Cpu, bus: *Bus) bool {
    const value = helpers.readOperand(cpu, bus);

    // Perform comparison
    const result = cpu.y -% value;

    // Set flags
    cpu.p.carry = cpu.y >= value;
    cpu.p.zero = cpu.y == value;
    cpu.p.negative = (result & 0x80) != 0;

    return true;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "CMP: equal values" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x42;
    cpu.pc = 0x0000;
    bus.ram[0] = 0x42;
    cpu.address_mode = .immediate;

    _ = cmp(&cpu, &bus);

    try testing.expect(cpu.p.carry); // A >= M
    try testing.expect(cpu.p.zero); // A == M
    try testing.expect(!cpu.p.negative);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "CMP: A greater than M" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x50;
    cpu.pc = 0x0000;
    bus.ram[0] = 0x30;
    cpu.address_mode = .immediate;

    _ = cmp(&cpu, &bus);

    try testing.expect(cpu.p.carry); // A >= M
    try testing.expect(!cpu.p.zero); // A != M
    try testing.expect(!cpu.p.negative); // Result is positive
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "CMP: A less than M" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x30;
    cpu.pc = 0x0000;
    bus.ram[0] = 0x50;
    cpu.address_mode = .immediate;

    _ = cmp(&cpu, &bus);

    try testing.expect(!cpu.p.carry); // A < M (borrow needed)
    try testing.expect(!cpu.p.zero);
    try testing.expect(cpu.p.negative); // Result is negative (0x30 - 0x50 = 0xE0)
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "CMP: negative flag behavior" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x00;
    cpu.pc = 0x0000;
    bus.ram[0] = 0x01;
    cpu.address_mode = .immediate;

    _ = cmp(&cpu, &bus);

    try testing.expect(!cpu.p.carry);
    try testing.expect(!cpu.p.zero);
    try testing.expect(cpu.p.negative); // 0x00 - 0x01 = 0xFF (negative)
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "CPX: equal values" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.x = 0x42;
    cpu.pc = 0x0000;
    bus.ram[0] = 0x42;
    cpu.address_mode = .immediate;

    _ = cpx(&cpu, &bus);

    try testing.expect(cpu.p.carry);
    try testing.expect(cpu.p.zero);
    try testing.expect(!cpu.p.negative);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "CPX: X greater than M" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.x = 0x80;
    cpu.pc = 0x0000;
    bus.ram[0] = 0x40;
    cpu.address_mode = .immediate;

    _ = cpx(&cpu, &bus);

    try testing.expect(cpu.p.carry);
    try testing.expect(!cpu.p.zero);
    try testing.expect(!cpu.p.negative);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "CPX: X less than M" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.x = 0x40;
    cpu.pc = 0x0000;
    bus.ram[0] = 0x80;
    cpu.address_mode = .immediate;

    _ = cpx(&cpu, &bus);

    try testing.expect(!cpu.p.carry);
    try testing.expect(!cpu.p.zero);
    try testing.expect(cpu.p.negative);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "CPY: equal values" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.y = 0x42;
    cpu.pc = 0x0000;
    bus.ram[0] = 0x42;
    cpu.address_mode = .immediate;

    _ = cpy(&cpu, &bus);

    try testing.expect(cpu.p.carry);
    try testing.expect(cpu.p.zero);
    try testing.expect(!cpu.p.negative);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "CPY: Y greater than M" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.y = 0xFF;
    cpu.pc = 0x0000;
    bus.ram[0] = 0x01;
    cpu.address_mode = .immediate;

    _ = cpy(&cpu, &bus);

    try testing.expect(cpu.p.carry);
    try testing.expect(!cpu.p.zero);
    try testing.expect(cpu.p.negative); // 0xFF - 0x01 = 0xFE (negative)
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "CPY: Y less than M" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.y = 0x01;
    cpu.pc = 0x0000;
    bus.ram[0] = 0xFF;
    cpu.address_mode = .immediate;

    _ = cpy(&cpu, &bus);

    try testing.expect(!cpu.p.carry);
    try testing.expect(!cpu.p.zero);
    try testing.expect(!cpu.p.negative); // 0x01 - 0xFF = 0x02 (wraps, positive)
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}
