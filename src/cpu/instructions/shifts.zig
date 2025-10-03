const std = @import("std");
const Cpu = @import("../Cpu.zig").Cpu;
const Bus = @import("../../bus/Bus.zig").Bus;

// ============================================================================
// ASL - Arithmetic Shift Left
// ============================================================================

/// ASL - Shift left one bit (memory or accumulator)
/// Flags: N Z C
pub fn asl(cpu: *Cpu, bus: *Bus) bool {
    var value: u8 = undefined;

    if (cpu.address_mode == .accumulator) {
        // Accumulator mode - no memory access
        value = cpu.a;
        cpu.p.carry = (value & 0x80) != 0;
        value <<= 1;
        cpu.a = value;
        cpu.p.updateZN(value);
        return true;
    }

    // Memory mode - value already in temp_value from RMW read
    value = cpu.temp_value;
    cpu.p.carry = (value & 0x80) != 0;
    value <<= 1;
    cpu.p.updateZN(value);

    // Write modified value
    bus.write(cpu.effective_address, value);
    return true;
}

// ============================================================================
// LSR - Logical Shift Right
// ============================================================================

/// LSR - Shift right one bit (memory or accumulator)
/// Flags: N(0) Z C
pub fn lsr(cpu: *Cpu, bus: *Bus) bool {
    var value: u8 = undefined;

    if (cpu.address_mode == .accumulator) {
        // Accumulator mode
        value = cpu.a;
        cpu.p.carry = (value & 0x01) != 0;
        value >>= 1;
        cpu.a = value;
        cpu.p.updateZN(value);
        return true;
    }

    // Memory mode
    value = cpu.temp_value;
    cpu.p.carry = (value & 0x01) != 0;
    value >>= 1;
    cpu.p.updateZN(value);

    bus.write(cpu.effective_address, value);
    return true;
}

// ============================================================================
// ROL - Rotate Left
// ============================================================================

/// ROL - Rotate left one bit (memory or accumulator)
/// Flags: N Z C
pub fn rol(cpu: *Cpu, bus: *Bus) bool {
    var value: u8 = undefined;

    if (cpu.address_mode == .accumulator) {
        value = cpu.a;
        const old_carry: u8 = if (cpu.p.carry) 1 else 0;
        cpu.p.carry = (value & 0x80) != 0;
        value = (value << 1) | old_carry;
        cpu.a = value;
        cpu.p.updateZN(value);
        return true;
    }

    // Memory mode
    value = cpu.temp_value;
    const old_carry: u8 = if (cpu.p.carry) 1 else 0;
    cpu.p.carry = (value & 0x80) != 0;
    value = (value << 1) | old_carry;
    cpu.p.updateZN(value);

    bus.write(cpu.effective_address, value);
    return true;
}

// ============================================================================
// ROR - Rotate Right
// ============================================================================

/// ROR - Rotate right one bit (memory or accumulator)
/// Flags: N Z C
pub fn ror(cpu: *Cpu, bus: *Bus) bool {
    var value: u8 = undefined;

    if (cpu.address_mode == .accumulator) {
        value = cpu.a;
        const old_carry: u8 = if (cpu.p.carry) 1 else 0;
        cpu.p.carry = (value & 0x01) != 0;
        value = (value >> 1) | (old_carry << 7);
        cpu.a = value;
        cpu.p.updateZN(value);
        return true;
    }

    // Memory mode
    value = cpu.temp_value;
    const old_carry: u8 = if (cpu.p.carry) 1 else 0;
    cpu.p.carry = (value & 0x01) != 0;
    value = (value >> 1) | (old_carry << 7);
    cpu.p.updateZN(value);

    bus.write(cpu.effective_address, value);
    return true;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "ASL accumulator - basic shift" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x42; // 01000010
    cpu.address_mode = .accumulator;

    const complete = asl(&cpu, &bus);
    try testing.expect(complete);
    try testing.expectEqual(@as(u8, 0x84), cpu.a); // 10000100
    try testing.expect(!cpu.p.carry); // No carry out
    try testing.expect(cpu.p.negative); // Bit 7 set
}

test "ASL accumulator - carry flag" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x81; // 10000001
    cpu.address_mode = .accumulator;

    _ = asl(&cpu, &bus);
    try testing.expectEqual(@as(u8, 0x02), cpu.a); // 00000010
    try testing.expect(cpu.p.carry); // Carry out from bit 7
}

test "LSR accumulator - basic shift" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x42; // 01000010
    cpu.address_mode = .accumulator;

    _ = lsr(&cpu, &bus);
    try testing.expectEqual(@as(u8, 0x21), cpu.a); // 00100001
    try testing.expect(!cpu.p.carry);
    try testing.expect(!cpu.p.negative); // Bit 7 always 0
}

test "ROL with carry" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x80; // 10000000
    cpu.p.carry = true;
    cpu.address_mode = .accumulator;

    _ = rol(&cpu, &bus);
    try testing.expectEqual(@as(u8, 0x01), cpu.a); // 00000001 (carry rotated in)
    try testing.expect(cpu.p.carry); // Bit 7 rotated out
}

test "ROR with carry" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x01; // 00000001
    cpu.p.carry = true;
    cpu.address_mode = .accumulator;

    _ = ror(&cpu, &bus);
    try testing.expectEqual(@as(u8, 0x80), cpu.a); // 10000000 (carry rotated in)
    try testing.expect(cpu.p.carry); // Bit 0 rotated out
}
