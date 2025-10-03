//! Unofficial/Undocumented 6502 Instructions
//!
//! These instructions are not officially documented but work reliably
//! on all 6502/2A03 hardware. They are tested by AccuracyCoin and used
//! by some NES games.
//!
//! Reference: https://www.nesdev.org/wiki/CPU_unofficial_opcodes

const std = @import("std");
const Cpu = @import("../Cpu.zig").Cpu;
const Bus = @import("../../bus/Bus.zig").Bus;
const helpers = @import("../helpers.zig");

// ============================================================================
// LAX - Load A and X (Combo: LDA + TAX)
// ============================================================================

/// LAX - Load Accumulator and X Register
/// A = X = M
/// Flags: N, Z
///
/// Combines LDA and TAX into a single instruction.
/// Loads a value from memory into both A and X simultaneously.
///
/// Addressing modes: zero page, zero page,Y, absolute, absolute,Y,
///                   indexed indirect, indirect indexed
pub fn lax(cpu: *Cpu, bus: *Bus) bool {
    const value = helpers.readOperand(cpu, bus);
    cpu.a = value;
    cpu.x = value;
    cpu.p.updateZN(value);
    return true;
}

// ============================================================================
// SAX - Store A AND X (Combo: A & X → Memory)
// ============================================================================

/// SAX - Store A AND X
/// M = A & X
/// Flags: None
///
/// Stores the bitwise AND of A and X to memory.
/// Does not affect any flags.
///
/// Addressing modes: zero page, zero page,Y, absolute, indexed indirect
pub fn sax(cpu: *Cpu, bus: *Bus) bool {
    const value = cpu.a & cpu.x;
    helpers.writeOperand(cpu, bus, value);
    return true;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "LAX: zero page" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.write(0x0042, 0x55);
    cpu.address_mode = .zero_page;
    cpu.operand_low = 0x42;

    _ = lax(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x55), cpu.a);
    try testing.expectEqual(@as(u8, 0x55), cpu.x);
    try testing.expect(!cpu.p.zero);
    try testing.expect(!cpu.p.negative);
}

test "LAX: sets both A and X" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x00;
    cpu.x = 0xFF;
    bus.write(0x1234, 0x42);
    cpu.address_mode = .absolute;
    cpu.operand_low = 0x34;
    cpu.operand_high = 0x12;

    _ = lax(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x42), cpu.a);
    try testing.expectEqual(@as(u8, 0x42), cpu.x);
}

test "LAX: zero flag" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.write(0x0010, 0x00);
    cpu.address_mode = .zero_page;
    cpu.operand_low = 0x10;

    _ = lax(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x00), cpu.a);
    try testing.expectEqual(@as(u8, 0x00), cpu.x);
    try testing.expect(cpu.p.zero);
}

test "LAX: negative flag" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.write(0x0020, 0x80);
    cpu.address_mode = .zero_page;
    cpu.operand_low = 0x20;

    _ = lax(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x80), cpu.a);
    try testing.expectEqual(@as(u8, 0x80), cpu.x);
    try testing.expect(cpu.p.negative);
}

test "LAX: absolute,Y page crossing" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.address_mode = .absolute_y;
    cpu.effective_address = 0x1100;
    cpu.page_crossed = true;
    bus.write(0x1100, 0xAA);

    _ = lax(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0xAA), cpu.a);
    try testing.expectEqual(@as(u8, 0xAA), cpu.x);
}

test "LAX: indirect indexed" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.address_mode = .indirect_indexed;
    cpu.effective_address = 0x2000;
    cpu.page_crossed = false;
    cpu.temp_value = 0x77;

    _ = lax(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x77), cpu.a);
    try testing.expectEqual(@as(u8, 0x77), cpu.x);
}

test "SAX: zero page" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0xFF;
    cpu.x = 0x0F;
    cpu.address_mode = .zero_page;
    cpu.operand_low = 0x50;

    _ = sax(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x0F), bus.read(0x0050));
}

test "SAX: AND operation" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0xF0;
    cpu.x = 0x0F;
    cpu.address_mode = .zero_page;
    cpu.operand_low = 0x60;

    _ = sax(&cpu, &bus);

    // 0xF0 AND 0x0F = 0x00
    try testing.expectEqual(@as(u8, 0x00), bus.read(0x0060));
}

test "SAX: does not affect flags" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x00;
    cpu.x = 0x00;
    cpu.p.zero = false;
    cpu.p.negative = true;
    cpu.address_mode = .zero_page;
    cpu.operand_low = 0x70;

    _ = sax(&cpu, &bus);

    // Flags should be unchanged
    try testing.expect(!cpu.p.zero);
    try testing.expect(cpu.p.negative);
}

test "SAX: absolute mode" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0xAA;
    cpu.x = 0x55;
    cpu.address_mode = .absolute;
    cpu.operand_low = 0x34;
    cpu.operand_high = 0x12;

    _ = sax(&cpu, &bus);

    // 0xAA AND 0x55 = 0x00
    try testing.expectEqual(@as(u8, 0x00), bus.read(0x1234));
}

test "SAX: zero page,Y" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0xFF;
    cpu.x = 0xF0;
    cpu.address_mode = .zero_page_y;
    cpu.effective_address = 0x0080;

    _ = sax(&cpu, &bus);

    // 0xFF AND 0xF0 = 0xF0
    try testing.expectEqual(@as(u8, 0xF0), bus.read(0x0080));
}

test "SAX: indexed indirect" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0b11110000;
    cpu.x = 0b10101010;
    cpu.address_mode = .indexed_indirect;
    cpu.effective_address = 0x1000;

    _ = sax(&cpu, &bus);

    // 0b11110000 AND 0b10101010 = 0b10100000 = 0xA0
    try testing.expectEqual(@as(u8, 0xA0), bus.read(0x1000));
}

// ============================================================================
// Immediate Logic/Math Operations
// ============================================================================

/// ANC - AND + Copy bit 7 to Carry (2 opcodes: $0B, $2B)
/// A = A & operand, C = bit 7 of result
/// Flags: C (equals N), N, Z
///
/// Immediate mode only (2 cycles)
pub fn anc(cpu: *Cpu, bus: *Bus) bool {
    const value = bus.read(cpu.pc);
    cpu.pc +%= 1;
    cpu.a &= value;
    cpu.p.carry = (cpu.a & 0x80) != 0; // Carry equals negative flag
    cpu.p.updateZN(cpu.a);
    return true;
}

/// ALR/ASR - AND + LSR (1 opcode: $4B)
/// A = (A & operand) >> 1
/// Flags: C (from LSR), N, Z
///
/// Immediate mode only (2 cycles)
pub fn alr(cpu: *Cpu, bus: *Bus) bool {
    const value = bus.read(cpu.pc);
    cpu.pc +%= 1;
    cpu.a &= value;
    cpu.p.carry = (cpu.a & 0x01) != 0; // Carry from LSR
    cpu.a >>= 1;
    cpu.p.updateZN(cpu.a);
    return true;
}

/// ARR - AND + ROR (1 opcode: $6B)
/// A = (A & operand) ROR 1
/// Flags: C, V (complex), N, Z
///
/// Immediate mode only (2 cycles)
/// Flag behavior is complex: C from bit 6, V from bit 6 XOR bit 5
pub fn arr(cpu: *Cpu, bus: *Bus) bool {
    const value = bus.read(cpu.pc);
    cpu.pc +%= 1;
    cpu.a &= value;

    // ROR with carry
    const old_carry = cpu.p.carry;
    cpu.a = (cpu.a >> 1) | (@as(u8, if (old_carry) 0x80 else 0));

    // Complex flag behavior
    cpu.p.carry = (cpu.a & 0x40) != 0; // Carry from bit 6
    cpu.p.overflow = ((cpu.a & 0x40) != 0) != ((cpu.a & 0x20) != 0); // V = bit 6 XOR bit 5
    cpu.p.updateZN(cpu.a);

    return true;
}

/// AXS/SBX - (A & X) - operand → X (1 opcode: $CB)
/// X = (A & X) - operand (without borrow)
/// Flags: C (from comparison), N, Z
///
/// Immediate mode only (2 cycles)
pub fn axs(cpu: *Cpu, bus: *Bus) bool {
    const value = bus.read(cpu.pc);
    cpu.pc +%= 1;
    const temp = cpu.a & cpu.x;
    cpu.x = temp -% value;
    cpu.p.carry = temp >= value; // Carry as if comparison
    cpu.p.updateZN(cpu.x);
    return true;
}

// ============================================================================
// Unstable Store Operations (Hardware-Dependent)
// ============================================================================
//
// WARNING: These opcodes have unstable behavior that varies between
// different 6502 chip revisions. This implementation uses the most
// common NMOS 6502 behavior.
//
// On some hardware, the high byte calculation may fail, especially when
// page boundaries are NOT crossed. Use with caution.

/// SHA/AHX - Store A & X & (H+1)
/// M = A & X & (high_byte + 1)
/// Flags: None
///
/// UNSTABLE: High byte calculation sometimes fails on some chip revisions
/// Addressing modes: absolute,Y ($9F), indirect,Y ($93)
pub fn sha(cpu: *Cpu, bus: *Bus) bool {
    const high_byte = @as(u8, @truncate(cpu.effective_address >> 8));
    const value = cpu.a & cpu.x & (high_byte +% 1);
    bus.write(cpu.effective_address, value);
    return true;
}

/// SHX - Store X & (H+1)
/// M = X & (high_byte + 1)
/// Flags: None
///
/// UNSTABLE: High byte calculation sometimes fails on some chip revisions
/// Addressing mode: absolute,Y ($9E)
pub fn shx(cpu: *Cpu, bus: *Bus) bool {
    const high_byte = @as(u8, @truncate(cpu.effective_address >> 8));
    const value = cpu.x & (high_byte +% 1);
    bus.write(cpu.effective_address, value);
    return true;
}

/// SHY - Store Y & (H+1)
/// M = Y & (high_byte + 1)
/// Flags: None
///
/// UNSTABLE: High byte calculation sometimes fails on some chip revisions
/// Addressing mode: absolute,X ($9C)
pub fn shy(cpu: *Cpu, bus: *Bus) bool {
    const high_byte = @as(u8, @truncate(cpu.effective_address >> 8));
    const value = cpu.y & (high_byte +% 1);
    bus.write(cpu.effective_address, value);
    return true;
}

/// TAS/SHS - Transfer A & X to SP, then store A & X & (H+1)
/// SP = A & X
/// M = A & X & (high_byte + 1)
/// Flags: None
///
/// HIGHLY UNSTABLE: Behavior varies significantly between chip revisions
/// Addressing mode: absolute,Y ($9B)
pub fn tas(cpu: *Cpu, bus: *Bus) bool {
    const temp = cpu.a & cpu.x;
    cpu.sp = temp;
    const high_byte = @as(u8, @truncate(cpu.effective_address >> 8));
    const value = temp & (high_byte +% 1);
    bus.write(cpu.effective_address, value);
    return true;
}

// ============================================================================
// Other Unstable Load/Transfer Operations
// ============================================================================

/// LAE/LAS - Load A, X, and SP with memory & SP
/// value = M & SP
/// A = X = SP = value
/// Flags: N, Z
///
/// Relatively stable compared to other unstable opcodes
/// Addressing mode: absolute,Y ($BB)
pub fn lae(cpu: *Cpu, bus: *Bus) bool {
    const value = helpers.readOperand(cpu, bus);
    const result = value & cpu.sp;
    cpu.a = result;
    cpu.x = result;
    cpu.sp = result;
    cpu.p.updateZN(result);
    return true;
}

/// XAA/ANE - Highly unstable AND operation
/// A = (A | MAGIC) & X & operand
/// Flags: N, Z
///
/// HIGHLY UNSTABLE: Magic constant varies by chip ($00, $EE, $FF, others)
/// This implementation uses $EE (most common NMOS behavior)
/// Addressing mode: immediate ($8B)
pub fn xaa(cpu: *Cpu, bus: *Bus) bool {
    const value = bus.read(cpu.pc);
    cpu.pc +%= 1;
    const magic: u8 = 0xEE; // Most common NMOS 6502 magic constant
    cpu.a = (cpu.a | magic) & cpu.x & value;
    cpu.p.updateZN(cpu.a);
    return true;
}

/// LXA - Highly unstable load A and X
/// A = X = (A | MAGIC) & operand
/// Flags: N, Z
///
/// HIGHLY UNSTABLE: Magic constant varies by chip ($00, $EE, $FF, others)
/// This implementation uses $EE (most common NMOS behavior)
/// Addressing mode: immediate ($AB)
pub fn lxa(cpu: *Cpu, bus: *Bus) bool {
    const value = bus.read(cpu.pc);
    cpu.pc +%= 1;
    const magic: u8 = 0xEE; // Most common NMOS 6502 magic constant
    const result = (cpu.a | magic) & value;
    cpu.a = result;
    cpu.x = result;
    cpu.p.updateZN(result);
    return true;
}

// ============================================================================
// JAM/KIL - CPU Halt Instructions
// ============================================================================
//
// These opcodes halt the CPU in an infinite internal loop.
// Only a RESET can recover from this state (NMI/IRQ are ignored).
// The PC does not increment and the bus shows the last read value.
//
// There are 12 JAM/KIL opcodes: $02, $12, $22, $32, $42, $52, $62, $72,
//                                 $92, $B2, $D2, $F2

/// JAM/KIL - Halt the CPU
/// CPU enters infinite loop, only RESET recovers
/// Flags: None affected
///
/// The CPU will remain halted until a hardware RESET occurs.
/// NMI and IRQ interrupts are ignored while halted.
pub fn jam(cpu: *Cpu, bus: *Bus) bool {
    _ = bus; // JAM doesn't access the bus after opcode fetch
    cpu.halted = true; // Set CPU halted state
    // PC does NOT increment - stays at JAM opcode address
    return true; // Instruction completes but CPU is now halted
}

// ============================================================================
// RMW Combo Instructions (Critical for AccuracyCoin)
// ============================================================================

/// SLO - Shift Left + OR (ASL + ORA)
/// M = M << 1, A |= M
/// Flags: C (from shift), N, Z
///
/// This is a Read-Modify-Write instruction that:
/// 1. Shifts memory left (ASL)
/// 2. ORs the result with accumulator (ORA)
///
/// The RMW addressing mode ALREADY handles the critical dummy write.
/// This function receives temp_value (the original read value) and
/// must write back the modified value.
pub fn slo(cpu: *Cpu, bus: *Bus) bool {
    // Read current value (addressing already handled RMW sequence)
    var value = cpu.temp_value;

    // ASL: Shift left
    const carry = (value & 0x80) != 0;
    value <<= 1;

    // Write modified value back (RMW addressing handles this)
    bus.write(cpu.effective_address, value);

    // ORA: OR with accumulator
    cpu.a |= value;

    // Update flags
    cpu.p.carry = carry;
    cpu.p.updateZN(cpu.a);

    return true;
}

/// RLA - Rotate Left + AND (ROL + AND)
/// M = (M << 1) | C, A &= M
/// Flags: C (from rotate), N, Z
///
/// This is a Read-Modify-Write instruction that:
/// 1. Rotates memory left through carry (ROL)
/// 2. ANDs the result with accumulator (AND)
pub fn rla(cpu: *Cpu, bus: *Bus) bool {
    var value = cpu.temp_value;

    // ROL: Rotate left through carry
    const old_carry = cpu.p.carry;
    const new_carry = (value & 0x80) != 0;
    value = (value << 1) | @as(u8, if (old_carry) 1 else 0);

    // Write modified value
    bus.write(cpu.effective_address, value);

    // AND: AND with accumulator
    cpu.a &= value;

    // Update flags
    cpu.p.carry = new_carry;
    cpu.p.updateZN(cpu.a);

    return true;
}

/// SRE - Shift Right + EOR (LSR + EOR)
/// M = M >> 1, A ^= M
/// Flags: C (from shift), N, Z
///
/// This is a Read-Modify-Write instruction that:
/// 1. Shifts memory right (LSR)
/// 2. XORs the result with accumulator (EOR)
pub fn sre(cpu: *Cpu, bus: *Bus) bool {
    var value = cpu.temp_value;

    // LSR: Shift right
    const carry = (value & 0x01) != 0;
    value >>= 1;

    // Write modified value
    bus.write(cpu.effective_address, value);

    // EOR: XOR with accumulator
    cpu.a ^= value;

    // Update flags
    cpu.p.carry = carry;
    cpu.p.updateZN(cpu.a);

    return true;
}

/// RRA - Rotate Right + ADC (ROR + ADC)
/// M = (M >> 1) | (C << 7), A = A + M + C
/// Flags: C, V, N, Z
///
/// This is a Read-Modify-Write instruction that:
/// 1. Rotates memory right through carry (ROR)
/// 2. Adds the result to accumulator with carry (ADC)
///
/// CRITICAL: The rotate sets a NEW carry, which is then used by ADC.
pub fn rra(cpu: *Cpu, bus: *Bus) bool {
    var value = cpu.temp_value;

    // ROR: Rotate right through carry
    const old_carry = cpu.p.carry;
    const new_carry_from_rotate = (value & 0x01) != 0;
    value = (value >> 1) | (@as(u8, if (old_carry) 0x80 else 0));

    // Write modified value
    bus.write(cpu.effective_address, value);

    // ADC: Add with carry (using the NEW carry from rotate)
    const a = cpu.a;
    const carry_in: u8 = if (new_carry_from_rotate) 1 else 0;
    const result16 = @as(u16, a) + @as(u16, value) + @as(u16, carry_in);
    const result = @as(u8, @truncate(result16));

    // Set carry from addition
    cpu.p.carry = (result16 > 0xFF);

    // Set overflow
    const overflow = ((a ^ result) & (value ^ result) & 0x80) != 0;
    cpu.p.overflow = overflow;

    // Update accumulator and flags
    cpu.a = result;
    cpu.p.updateZN(result);

    return true;
}

/// DCP - Decrement + Compare (DEC + CMP)
/// M = M - 1, compare A with M
/// Flags: C, N, Z
///
/// This is a Read-Modify-Write instruction that:
/// 1. Decrements memory (DEC)
/// 2. Compares accumulator with the result (CMP)
pub fn dcp(cpu: *Cpu, bus: *Bus) bool {
    var value = cpu.temp_value;

    // DEC: Decrement
    value -%= 1;

    // Write modified value
    bus.write(cpu.effective_address, value);

    // CMP: Compare A with M
    const result = cpu.a -% value;
    cpu.p.carry = cpu.a >= value;
    cpu.p.zero = cpu.a == value;
    cpu.p.negative = (result & 0x80) != 0;

    return true;
}

/// ISC/ISB - Increment + Subtract (INC + SBC)
/// M = M + 1, A = A - M - (1 - C)
/// Flags: C, V, N, Z
///
/// This is a Read-Modify-Write instruction that:
/// 1. Increments memory (INC)
/// 2. Subtracts the result from accumulator with borrow (SBC)
pub fn isc(cpu: *Cpu, bus: *Bus) bool {
    var value = cpu.temp_value;

    // INC: Increment
    value +%= 1;

    // Write modified value
    bus.write(cpu.effective_address, value);

    // SBC: Subtract with carry (A - M - (1 - C))
    // SBC is equivalent to ADC with inverted operand: A + (~M) + C
    const inverted = ~value;
    const a = cpu.a;
    const carry: u8 = if (cpu.p.carry) 1 else 0;
    const result16 = @as(u16, a) + @as(u16, inverted) + @as(u16, carry);
    const result = @as(u8, @truncate(result16));

    cpu.p.carry = (result16 > 0xFF);
    const overflow = ((a ^ result) & (inverted ^ result) & 0x80) != 0;
    cpu.p.overflow = overflow;

    cpu.a = result;
    cpu.p.updateZN(result);

    return true;
}

// ============================================================================
// RMW Combo Tests
// ============================================================================

test "SLO: shift left and OR with accumulator" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.write(0x0050, 0b01010101);
    cpu.temp_value = 0b01010101;
    cpu.effective_address = 0x0050;
    cpu.a = 0b00001111;
    cpu.p.carry = false;

    _ = slo(&cpu, &bus);

    // Memory: 0b01010101 << 1 = 0b10101010
    try testing.expectEqual(@as(u8, 0b10101010), bus.read(0x0050));
    // A: 0b00001111 | 0b10101010 = 0b10101111
    try testing.expectEqual(@as(u8, 0b10101111), cpu.a);
    try testing.expect(!cpu.p.carry); // Bit 7 was 0
    try testing.expect(cpu.p.negative); // Result bit 7 is 1
    try testing.expect(!cpu.p.zero);
}

test "SLO: sets carry flag" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.temp_value = 0b10000001;
    cpu.effective_address = 0x0100;
    cpu.a = 0x00;

    _ = slo(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0b00000010), bus.read(0x0100));
    try testing.expectEqual(@as(u8, 0b00000010), cpu.a);
    try testing.expect(cpu.p.carry); // Bit 7 was 1
}

test "RLA: rotate left and AND with accumulator" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.temp_value = 0b01010101;
    cpu.effective_address = 0x0060;
    cpu.a = 0b11110000;
    cpu.p.carry = true; // Will be rotated in

    _ = rla(&cpu, &bus);

    // Memory: (0b01010101 << 1) | 1 = 0b10101011
    try testing.expectEqual(@as(u8, 0b10101011), bus.read(0x0060));
    // A: 0b11110000 & 0b10101011 = 0b10100000
    try testing.expectEqual(@as(u8, 0b10100000), cpu.a);
    try testing.expect(!cpu.p.carry); // Original bit 7 was 0
    try testing.expect(cpu.p.negative);
}

test "RLA: sets carry from rotate" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.temp_value = 0b11000000;
    cpu.effective_address = 0x0070;
    cpu.a = 0xFF;
    cpu.p.carry = false;

    _ = rla(&cpu, &bus);

    // Memory: 0b11000000 << 1 = 0b10000000
    try testing.expectEqual(@as(u8, 0b10000000), bus.read(0x0070));
    try testing.expect(cpu.p.carry); // Original bit 7 was 1
}

test "SRE: shift right and XOR with accumulator" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.temp_value = 0b10101010;
    cpu.effective_address = 0x0080;
    cpu.a = 0b11110000;

    _ = sre(&cpu, &bus);

    // Memory: 0b10101010 >> 1 = 0b01010101
    try testing.expectEqual(@as(u8, 0b01010101), bus.read(0x0080));
    // A: 0b11110000 ^ 0b01010101 = 0b10100101
    try testing.expectEqual(@as(u8, 0b10100101), cpu.a);
    try testing.expect(!cpu.p.carry); // Bit 0 was 0
    try testing.expect(cpu.p.negative);
}

test "SRE: sets carry flag" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.temp_value = 0b00000011;
    cpu.effective_address = 0x0090;
    cpu.a = 0x00;

    _ = sre(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0b00000001), bus.read(0x0090));
    try testing.expect(cpu.p.carry); // Bit 0 was 1
}

test "RRA: rotate right and add with carry" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.temp_value = 0b00000010;
    cpu.effective_address = 0x00A0;
    cpu.a = 0x10;
    cpu.p.carry = true; // Will be rotated in

    _ = rra(&cpu, &bus);

    // Memory: (0b00000010 >> 1) | 0x80 = 0b10000001
    try testing.expectEqual(@as(u8, 0b10000001), bus.read(0x00A0));
    // A: 0x10 + 0b10000001 + 0 (new carry from rotate) = 0x91
    try testing.expectEqual(@as(u8, 0x91), cpu.a);
    try testing.expect(!cpu.p.carry); // No carry from addition
    try testing.expect(cpu.p.negative);
}

test "RRA: carry from rotate used in ADC" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.temp_value = 0b00000001; // Bit 0 = 1, will set carry
    cpu.effective_address = 0x00B0;
    cpu.a = 0x00;
    cpu.p.carry = false;

    _ = rra(&cpu, &bus);

    // Memory: 0b00000001 >> 1 = 0b00000000
    try testing.expectEqual(@as(u8, 0x00), bus.read(0x00B0));
    // A: 0x00 + 0x00 + 1 (carry from rotate) = 0x01
    try testing.expectEqual(@as(u8, 0x01), cpu.a);
}

test "DCP: decrement and compare" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.temp_value = 0x50;
    cpu.effective_address = 0x00C0;
    cpu.a = 0x4F;

    _ = dcp(&cpu, &bus);

    // Memory: 0x50 - 1 = 0x4F
    try testing.expectEqual(@as(u8, 0x4F), bus.read(0x00C0));
    // Compare: A (0x4F) == M (0x4F)
    try testing.expect(cpu.p.zero);
    try testing.expect(cpu.p.carry); // A >= M
    try testing.expect(!cpu.p.negative);
}

test "DCP: compare flags when A < M" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.temp_value = 0x60;
    cpu.effective_address = 0x00D0;
    cpu.a = 0x50;

    _ = dcp(&cpu, &bus);

    // Memory: 0x60 - 1 = 0x5F
    try testing.expectEqual(@as(u8, 0x5F), bus.read(0x00D0));
    // Compare: A (0x50) < M (0x5F)
    try testing.expect(!cpu.p.zero);
    try testing.expect(!cpu.p.carry); // A < M
    try testing.expect(cpu.p.negative); // Result is negative
}

test "ISC: increment and subtract with carry" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.temp_value = 0x0F;
    cpu.effective_address = 0x00E0;
    cpu.a = 0x20;
    cpu.p.carry = true; // No borrow

    _ = isc(&cpu, &bus);

    // Memory: 0x0F + 1 = 0x10
    try testing.expectEqual(@as(u8, 0x10), bus.read(0x00E0));
    // A: 0x20 - 0x10 = 0x10
    try testing.expectEqual(@as(u8, 0x10), cpu.a);
    try testing.expect(cpu.p.carry); // No borrow
    try testing.expect(!cpu.p.zero);
}

test "ISC: subtract with borrow" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.temp_value = 0x0F;
    cpu.effective_address = 0x00F0;
    cpu.a = 0x20;
    cpu.p.carry = false; // Borrow

    _ = isc(&cpu, &bus);

    // Memory: 0x0F + 1 = 0x10
    try testing.expectEqual(@as(u8, 0x10), bus.read(0x00F0));
    // A: 0x20 - 0x10 - 1 = 0x0F
    try testing.expectEqual(@as(u8, 0x0F), cpu.a);
}
