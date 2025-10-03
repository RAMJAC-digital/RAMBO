//! Arithmetic Instructions: ADC, SBC
//!
//! These instructions perform addition and subtraction with carry flag handling
//! and overflow detection. The NES CPU does NOT support BCD mode (decimal flag
//! is ignored), unlike the original 6502.
//!
//! Reference: https://www.nesdev.org/wiki/Status_flags#Overflow_flag

const std = @import("std");
const Cpu = @import("../Cpu.zig").Cpu;
const Bus = @import("../../bus/Bus.zig").Bus;
const helpers = @import("../helpers.zig");

/// ADC - Add with Carry
/// A = A + M + C
/// Flags: N, V, Z, C
///
/// Supports all addressing modes (8 total):
/// - Immediate, Zero Page, Zero Page X
/// - Absolute, Absolute X, Absolute Y
/// - Indexed Indirect, Indirect Indexed
pub fn adc(cpu: *Cpu, bus: *Bus) bool {
    const value = helpers.readOperand(cpu, bus);

    // Perform addition with carry
    const a = cpu.a;
    const carry: u8 = if (cpu.p.carry) 1 else 0;

    // 16-bit addition to detect carry
    const result16 = @as(u16, a) + @as(u16, value) + @as(u16, carry);
    const result = @as(u8, @truncate(result16));

    // Set carry flag if result > 255
    cpu.p.carry = (result16 > 0xFF);

    // Set overflow flag
    // V = (A^R) & (M^R) & 0x80
    // Overflow occurs when:
    // - Adding two positives gives negative (bit 7 set)
    // - Adding two negatives gives positive (bit 7 clear)
    const overflow = ((a ^ result) & (value ^ result) & 0x80) != 0;
    cpu.p.overflow = overflow;

    // Update accumulator and flags
    cpu.a = result;
    cpu.p.updateZN(result);

    return true;
}

/// SBC - Subtract with Carry (borrow)
/// A = A - M - (1 - C)
/// Flags: N, V, Z, C
///
/// Note: Carry flag is inverted for borrow (C=1 means no borrow)
///
/// Supports all addressing modes (8 total):
/// - Immediate, Zero Page, Zero Page X
/// - Absolute, Absolute X, Absolute Y
/// - Indexed Indirect, Indirect Indexed
pub fn sbc(cpu: *Cpu, bus: *Bus) bool {
    const value = helpers.readOperand(cpu, bus);

    // SBC is equivalent to ADC with inverted operand
    // A - M - (1-C) = A + (~M) + C
    const inverted = ~value;

    const a = cpu.a;
    const carry: u8 = if (cpu.p.carry) 1 else 0;

    // 16-bit addition to detect carry
    const result16 = @as(u16, a) + @as(u16, inverted) + @as(u16, carry);
    const result = @as(u8, @truncate(result16));

    // Set carry flag (inverted for subtraction)
    cpu.p.carry = (result16 > 0xFF);

    // Set overflow flag
    // Same logic as ADC, but with inverted operand
    const overflow = ((a ^ result) & (inverted ^ result) & 0x80) != 0;
    cpu.p.overflow = overflow;

    // Update accumulator and flags
    cpu.a = result;
    cpu.p.updateZN(result);

    return true;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "ADC: immediate mode - simple addition" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x50;
    cpu.p.carry = false;
    cpu.pc = 0x0000;
    bus.ram[0] = 0x10;
    cpu.address_mode = .immediate;

    _ = adc(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x60), cpu.a);
    try testing.expect(!cpu.p.carry);
    try testing.expect(!cpu.p.overflow);
    try testing.expect(!cpu.p.zero);
    try testing.expect(!cpu.p.negative);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "ADC: addition with carry in" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x50;
    cpu.p.carry = true; // Carry in
    cpu.pc = 0x0000;
    bus.ram[0] = 0x10;
    cpu.address_mode = .immediate;

    _ = adc(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x61), cpu.a);
    try testing.expect(!cpu.p.carry);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "ADC: carry flag set on overflow" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0xFF;
    cpu.p.carry = false;
    cpu.pc = 0x0000;
    bus.ram[0] = 0x01;
    cpu.address_mode = .immediate;

    _ = adc(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x00), cpu.a);
    try testing.expect(cpu.p.carry); // Carry out
    try testing.expect(cpu.p.zero);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "ADC: overflow flag - positive + positive = negative" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x50; // +80
    cpu.p.carry = false;
    cpu.pc = 0x0000;
    bus.ram[0] = 0x50; // +80
    cpu.address_mode = .immediate;

    _ = adc(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0xA0), cpu.a); // -96 in signed
    try testing.expect(!cpu.p.carry);
    try testing.expect(cpu.p.overflow); // Overflow!
    try testing.expect(cpu.p.negative);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "ADC: overflow flag - negative + negative = positive" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x80; // -128
    cpu.p.carry = false;
    cpu.pc = 0x0000;
    bus.ram[0] = 0x80; // -128
    cpu.address_mode = .immediate;

    _ = adc(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x00), cpu.a); // 0
    try testing.expect(cpu.p.carry);
    try testing.expect(cpu.p.overflow); // Overflow!
    try testing.expect(cpu.p.zero);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "ADC: no overflow - positive + negative" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x50; // +80
    cpu.p.carry = false;
    cpu.pc = 0x0000;
    bus.ram[0] = 0xF0; // -16
    cpu.address_mode = .immediate;

    _ = adc(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x40), cpu.a);
    try testing.expect(cpu.p.carry);
    try testing.expect(!cpu.p.overflow); // No overflow
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "SBC: immediate mode - simple subtraction" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x50;
    cpu.p.carry = true; // No borrow
    cpu.pc = 0x0000;
    bus.ram[0] = 0x10;
    cpu.address_mode = .immediate;

    _ = sbc(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x40), cpu.a);
    try testing.expect(cpu.p.carry); // No borrow
    try testing.expect(!cpu.p.overflow);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "SBC: subtraction with borrow" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x50;
    cpu.p.carry = false; // Borrow
    cpu.pc = 0x0000;
    bus.ram[0] = 0x10;
    cpu.address_mode = .immediate;

    _ = sbc(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x3F), cpu.a);
    try testing.expect(cpu.p.carry);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "SBC: borrow flag cleared" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x10;
    cpu.p.carry = true; // No borrow
    cpu.pc = 0x0000;
    bus.ram[0] = 0x20;
    cpu.address_mode = .immediate;

    _ = sbc(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0xF0), cpu.a); // Wrapped around
    try testing.expect(!cpu.p.carry); // Borrow occurred
    try testing.expect(cpu.p.negative);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "SBC: overflow flag - positive - negative = overflow" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x50; // +80
    cpu.p.carry = true;
    cpu.pc = 0x0000;
    bus.ram[0] = 0x80; // -128 (subtracting negative)
    cpu.address_mode = .immediate;

    _ = sbc(&cpu, &bus);

    try testing.expect(cpu.p.overflow); // Overflow
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}

test "SBC: zero flag" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x50;
    cpu.p.carry = true;
    cpu.pc = 0x0000;
    bus.ram[0] = 0x50;
    cpu.address_mode = .immediate;

    _ = sbc(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x00), cpu.a);
    try testing.expect(cpu.p.zero);
    try testing.expect(cpu.p.carry);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment after read
}
