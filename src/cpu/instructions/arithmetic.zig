//! Arithmetic Instructions: ADC, SBC
//!
//! These instructions perform addition and subtraction with carry flag handling
//! and overflow detection. The NES CPU does NOT support BCD mode (decimal flag
//! is ignored), unlike the original 6502.
//!
//! Reference: https://www.nesdev.org/wiki/Status_flags#Overflow_flag

const std = @import("std");
const Cpu = @import("../Cpu.zig");
const Bus = @import("../../bus/Bus.zig").Bus;
const helpers = @import("../helpers.zig");

const State = Cpu.State;

/// ADC - Add with Carry
/// A = A + M + C
/// Flags: N, V, Z, C
///
/// Supports all addressing modes (8 total):
/// - Immediate, Zero Page, Zero Page X
/// - Absolute, Absolute X, Absolute Y
/// - Indexed Indirect, Indirect Indexed
pub fn adc(state: *State, bus: *Bus) bool {
    const value = helpers.readOperand(state, bus);

    // Perform addition with carry
    const a = state.a;
    const carry: u8 = if (state.p.carry) 1 else 0;

    // 16-bit addition to detect carry
    const result16 = @as(u16, a) + @as(u16, value) + @as(u16, carry);
    const result = @as(u8, @truncate(result16));

    // Set carry flag if result > 255
    state.p.carry = (result16 > 0xFF);

    // Set overflow flag
    // V = (A^R) & (M^R) & 0x80
    // Overflow occurs when:
    // - Adding two positives gives negative (bit 7 set)
    // - Adding two negatives gives positive (bit 7 clear)
    const overflow = ((a ^ result) & (value ^ result) & 0x80) != 0;
    state.p.overflow = overflow;

    // Update accumulator and flags
    state.a = result;
    state.p.updateZN(result);

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
pub fn sbc(state: *State, bus: *Bus) bool {
    const value = helpers.readOperand(state, bus);

    // SBC is equivalent to ADC with inverted operand
    // A - M - (1-C) = A + (~M) + C
    const inverted = ~value;

    const a = state.a;
    const carry: u8 = if (state.p.carry) 1 else 0;

    // 16-bit addition to detect carry
    const result16 = @as(u16, a) + @as(u16, inverted) + @as(u16, carry);
    const result = @as(u8, @truncate(result16));

    // Set carry flag (inverted for subtraction)
    state.p.carry = (result16 > 0xFF);

    // Set overflow flag
    // Same logic as ADC, but with inverted operand
    const overflow = ((a ^ result) & (inverted ^ result) & 0x80) != 0;
    state.p.overflow = overflow;

    // Update accumulator and flags
    state.a = result;
    state.p.updateZN(result);

    return true;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "ADC: immediate mode - simple addition" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x50;
    state.p.carry = false;
    state.pc = 0x0000;
    bus.ram[0] = 0x10;
    state.address_mode = .immediate;

    _ = adc(&state, &bus);

    try testing.expectEqual(@as(u8, 0x60), state.a);
    try testing.expect(!state.p.carry);
    try testing.expect(!state.p.overflow);
    try testing.expect(!state.p.zero);
    try testing.expect(!state.p.negative);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "ADC: addition with carry in" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x50;
    state.p.carry = true; // Carry in
    state.pc = 0x0000;
    bus.ram[0] = 0x10;
    state.address_mode = .immediate;

    _ = adc(&state, &bus);

    try testing.expectEqual(@as(u8, 0x61), state.a);
    try testing.expect(!state.p.carry);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "ADC: carry flag set on overflow" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0xFF;
    state.p.carry = false;
    state.pc = 0x0000;
    bus.ram[0] = 0x01;
    state.address_mode = .immediate;

    _ = adc(&state, &bus);

    try testing.expectEqual(@as(u8, 0x00), state.a);
    try testing.expect(state.p.carry); // Carry out
    try testing.expect(state.p.zero);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "ADC: overflow flag - positive + positive = negative" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x50; // +80
    state.p.carry = false;
    state.pc = 0x0000;
    bus.ram[0] = 0x50; // +80
    state.address_mode = .immediate;

    _ = adc(&state, &bus);

    try testing.expectEqual(@as(u8, 0xA0), state.a); // -96 in signed
    try testing.expect(!state.p.carry);
    try testing.expect(state.p.overflow); // Overflow!
    try testing.expect(state.p.negative);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "ADC: overflow flag - negative + negative = positive" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x80; // -128
    state.p.carry = false;
    state.pc = 0x0000;
    bus.ram[0] = 0x80; // -128
    state.address_mode = .immediate;

    _ = adc(&state, &bus);

    try testing.expectEqual(@as(u8, 0x00), state.a); // 0
    try testing.expect(state.p.carry);
    try testing.expect(state.p.overflow); // Overflow!
    try testing.expect(state.p.zero);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "ADC: no overflow - positive + negative" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x50; // +80
    state.p.carry = false;
    state.pc = 0x0000;
    bus.ram[0] = 0xF0; // -16
    state.address_mode = .immediate;

    _ = adc(&state, &bus);

    try testing.expectEqual(@as(u8, 0x40), state.a);
    try testing.expect(state.p.carry);
    try testing.expect(!state.p.overflow); // No overflow
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "SBC: immediate mode - simple subtraction" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x50;
    state.p.carry = true; // No borrow
    state.pc = 0x0000;
    bus.ram[0] = 0x10;
    state.address_mode = .immediate;

    _ = sbc(&state, &bus);

    try testing.expectEqual(@as(u8, 0x40), state.a);
    try testing.expect(state.p.carry); // No borrow
    try testing.expect(!state.p.overflow);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "SBC: subtraction with borrow" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x50;
    state.p.carry = false; // Borrow
    state.pc = 0x0000;
    bus.ram[0] = 0x10;
    state.address_mode = .immediate;

    _ = sbc(&state, &bus);

    try testing.expectEqual(@as(u8, 0x3F), state.a);
    try testing.expect(state.p.carry);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "SBC: borrow flag cleared" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x10;
    state.p.carry = true; // No borrow
    state.pc = 0x0000;
    bus.ram[0] = 0x20;
    state.address_mode = .immediate;

    _ = sbc(&state, &bus);

    try testing.expectEqual(@as(u8, 0xF0), state.a); // Wrapped around
    try testing.expect(!state.p.carry); // Borrow occurred
    try testing.expect(state.p.negative);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "SBC: overflow flag - positive - negative = overflow" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x50; // +80
    state.p.carry = true;
    state.pc = 0x0000;
    bus.ram[0] = 0x80; // -128 (subtracting negative)
    state.address_mode = .immediate;

    _ = sbc(&state, &bus);

    try testing.expect(state.p.overflow); // Overflow
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}

test "SBC: zero flag" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x50;
    state.p.carry = true;
    state.pc = 0x0000;
    bus.ram[0] = 0x50;
    state.address_mode = .immediate;

    _ = sbc(&state, &bus);

    try testing.expectEqual(@as(u8, 0x00), state.a);
    try testing.expect(state.p.zero);
    try testing.expect(state.p.carry);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment after read
}
