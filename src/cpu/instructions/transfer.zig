//! Transfer and Flag Instructions
//!
//! Transfer instructions: TAX, TXA, TAY, TYA, TSX, TXS
//! Flag instructions: SEC, CLC, SEI, CLI, SED, CLD, CLV
//! BIT instruction: Test bits in memory with accumulator
//!
//! All are 2-cycle implied mode instructions except BIT (3-4 cycles)

const std = @import("std");
const Cpu = @import("../Cpu.zig").Cpu;
const Bus = @import("../../bus/Bus.zig").Bus;

// ============================================================================
// Transfer Instructions (2 cycles, implied mode)
// ============================================================================

/// TAX - Transfer Accumulator to X
/// X = A
/// Flags: N, Z
pub fn tax(cpu: *Cpu, bus: *Bus) bool {
    _ = bus;
    cpu.x = cpu.a;
    cpu.p.updateZN(cpu.x);
    return true;
}

/// TXA - Transfer X to Accumulator
/// A = X
/// Flags: N, Z
pub fn txa(cpu: *Cpu, bus: *Bus) bool {
    _ = bus;
    cpu.a = cpu.x;
    cpu.p.updateZN(cpu.a);
    return true;
}

/// TAY - Transfer Accumulator to Y
/// Y = A
/// Flags: N, Z
pub fn tay(cpu: *Cpu, bus: *Bus) bool {
    _ = bus;
    cpu.y = cpu.a;
    cpu.p.updateZN(cpu.y);
    return true;
}

/// TYA - Transfer Y to Accumulator
/// A = Y
/// Flags: N, Z
pub fn tya(cpu: *Cpu, bus: *Bus) bool {
    _ = bus;
    cpu.a = cpu.y;
    cpu.p.updateZN(cpu.a);
    return true;
}

/// TSX - Transfer Stack Pointer to X
/// X = SP
/// Flags: N, Z
pub fn tsx(cpu: *Cpu, bus: *Bus) bool {
    _ = bus;
    cpu.x = cpu.sp;
    cpu.p.updateZN(cpu.x);
    return true;
}

/// TXS - Transfer X to Stack Pointer
/// SP = X
/// Flags: None
pub fn txs(cpu: *Cpu, bus: *Bus) bool {
    _ = bus;
    cpu.sp = cpu.x;
    return true;
}

// ============================================================================
// Flag Instructions (2 cycles, implied mode)
// ============================================================================

/// SEC - Set Carry Flag
/// C = 1
pub fn sec(cpu: *Cpu, bus: *Bus) bool {
    _ = bus;
    cpu.p.carry = true;
    return true;
}

/// CLC - Clear Carry Flag
/// C = 0
pub fn clc(cpu: *Cpu, bus: *Bus) bool {
    _ = bus;
    cpu.p.carry = false;
    return true;
}

/// SEI - Set Interrupt Disable
/// I = 1
pub fn sei(cpu: *Cpu, bus: *Bus) bool {
    _ = bus;
    cpu.p.interrupt = true;
    return true;
}

/// CLI - Clear Interrupt Disable
/// I = 0
pub fn cli(cpu: *Cpu, bus: *Bus) bool {
    _ = bus;
    cpu.p.interrupt = false;
    return true;
}

/// SED - Set Decimal Flag
/// D = 1
/// Note: NES CPU ignores decimal mode, but flag can still be set
pub fn sed(cpu: *Cpu, bus: *Bus) bool {
    _ = bus;
    cpu.p.decimal = true;
    return true;
}

/// CLD - Clear Decimal Flag
/// D = 0
pub fn cld(cpu: *Cpu, bus: *Bus) bool {
    _ = bus;
    cpu.p.decimal = false;
    return true;
}

/// CLV - Clear Overflow Flag
/// V = 0
pub fn clv(cpu: *Cpu, bus: *Bus) bool {
    _ = bus;
    cpu.p.overflow = false;
    return true;
}

// ============================================================================
// BIT Instruction (3-4 cycles depending on addressing mode)
// ============================================================================

/// BIT - Test Bits in Memory with Accumulator
/// A & M (result not stored)
/// Flags:
/// - N = M[7] (bit 7 of memory value)
/// - V = M[6] (bit 6 of memory value)
/// - Z = (A & M) == 0
///
/// Supports: Zero Page (3 cycles), Absolute (4 cycles)
pub fn bit(cpu: *Cpu, bus: *Bus) bool {
    _ = bus;
    var value: u8 = undefined;

    if (cpu.address_mode == .zero_page) {
        value = cpu.temp_value;
    } else if (cpu.address_mode == .absolute) {
        value = cpu.temp_value;
    } else {
        unreachable; // BIT only supports zero page and absolute
    }

    // Set N and V from memory value
    cpu.p.negative = (value & 0x80) != 0;
    cpu.p.overflow = (value & 0x40) != 0;

    // Set Z from AND result
    const result = cpu.a & value;
    cpu.p.zero = (result == 0);

    return true;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "TAX: transfer and update flags" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x42;
    _ = tax(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x42), cpu.x);
    try testing.expect(!cpu.p.zero);
    try testing.expect(!cpu.p.negative);
}

test "TAX: zero flag" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x00;
    _ = tax(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x00), cpu.x);
    try testing.expect(cpu.p.zero);
}

test "TXA: transfer and update flags" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.x = 0x80;
    _ = txa(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x80), cpu.a);
    try testing.expect(cpu.p.negative);
}

test "TAY and TYA: round trip" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x55;
    _ = tay(&cpu, &bus);
    try testing.expectEqual(@as(u8, 0x55), cpu.y);

    cpu.a = 0x00; // Clear A
    _ = tya(&cpu, &bus);
    try testing.expectEqual(@as(u8, 0x55), cpu.a);
}

test "TSX: transfer stack pointer" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.sp = 0xFD;
    _ = tsx(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0xFD), cpu.x);
    try testing.expect(cpu.p.negative); // 0xFD has bit 7 set
}

test "TXS: transfer to stack pointer, no flags" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.x = 0x80;
    const old_flags = cpu.p;

    _ = txs(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x80), cpu.sp);
    // Flags should be unchanged
    try testing.expectEqual(old_flags.toByte(), cpu.p.toByte());
}

test "SEC and CLC" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.p.carry = false;
    _ = sec(&cpu, &bus);
    try testing.expect(cpu.p.carry);

    _ = clc(&cpu, &bus);
    try testing.expect(!cpu.p.carry);
}

test "SEI and CLI" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.p.interrupt = false;
    _ = sei(&cpu, &bus);
    try testing.expect(cpu.p.interrupt);

    _ = cli(&cpu, &bus);
    try testing.expect(!cpu.p.interrupt);
}

test "SED and CLD" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.p.decimal = false;
    _ = sed(&cpu, &bus);
    try testing.expect(cpu.p.decimal);

    _ = cld(&cpu, &bus);
    try testing.expect(!cpu.p.decimal);
}

test "CLV: clear overflow" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.p.overflow = true;
    _ = clv(&cpu, &bus);
    try testing.expect(!cpu.p.overflow);
}

test "BIT: zero page mode" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0xFF;
    cpu.temp_value = 0xC0; // Bits 7 and 6 set
    cpu.address_mode = .zero_page;

    _ = bit(&cpu, &bus);

    try testing.expect(cpu.p.negative); // Bit 7 of memory
    try testing.expect(cpu.p.overflow); // Bit 6 of memory
    try testing.expect(!cpu.p.zero); // A & M != 0
}

test "BIT: zero flag set" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x0F;
    cpu.temp_value = 0xF0; // No overlap with A
    cpu.address_mode = .zero_page;

    _ = bit(&cpu, &bus);

    try testing.expect(cpu.p.negative); // Bit 7 of 0xF0
    try testing.expect(cpu.p.overflow); // Bit 6 of 0xF0
    try testing.expect(cpu.p.zero); // A & M == 0
}

test "BIT: flags from memory value" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0xFF;
    cpu.temp_value = 0x00; // All bits clear
    cpu.address_mode = .zero_page;

    _ = bit(&cpu, &bus);

    try testing.expect(!cpu.p.negative); // Bit 7 of 0x00
    try testing.expect(!cpu.p.overflow); // Bit 6 of 0x00
    try testing.expect(cpu.p.zero); // A & M == 0
}
