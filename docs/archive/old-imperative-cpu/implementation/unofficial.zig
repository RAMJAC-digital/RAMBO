//! Unofficial/Undocumented 6502 Instructions
//!
//! These instructions are not officially documented but work reliably
//! on all 6502/2A03 hardware. They are tested by AccuracyCoin and used
//! by some NES games.
//!
//! Reference: https://www.nesdev.org/wiki/CPU_unofficial_opcodes

const std = @import("std");
const Cpu = @import("../Cpu.zig");
const BusState = @import("../../bus/Bus.zig").State.BusState;
const helpers = @import("../helpers.zig");

const CpuState = Cpu.State.CpuState;

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
pub fn lax(state: *CpuState, bus: *BusState) bool {
    const value = helpers.readOperand(state, bus);
    state.a = value;
    state.x = value;
    state.p.updateZN(value);
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
pub fn sax(state: *CpuState, bus: *BusState) bool {
    const value = state.a & state.x;
    helpers.writeOperand(state, bus, value);
    return true;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "LAX: zero page" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    bus.write(0x0042, 0x55);
    state.address_mode = .zero_page;
    state.operand_low = 0x42;

    _ = lax(&state, &bus);

    try testing.expectEqual(@as(u8, 0x55), state.a);
    try testing.expectEqual(@as(u8, 0x55), state.x);
    try testing.expect(!state.p.zero);
    try testing.expect(!state.p.negative);
}

test "LAX: sets both A and X" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.a = 0x00;
    state.x = 0xFF;
    bus.write(0x1234, 0x42);
    state.address_mode = .absolute;
    state.operand_low = 0x34;
    state.operand_high = 0x12;

    _ = lax(&state, &bus);

    try testing.expectEqual(@as(u8, 0x42), state.a);
    try testing.expectEqual(@as(u8, 0x42), state.x);
}

test "LAX: zero flag" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    bus.write(0x0010, 0x00);
    state.address_mode = .zero_page;
    state.operand_low = 0x10;

    _ = lax(&state, &bus);

    try testing.expectEqual(@as(u8, 0x00), state.a);
    try testing.expectEqual(@as(u8, 0x00), state.x);
    try testing.expect(state.p.zero);
}

test "LAX: negative flag" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    bus.write(0x0020, 0x80);
    state.address_mode = .zero_page;
    state.operand_low = 0x20;

    _ = lax(&state, &bus);

    try testing.expectEqual(@as(u8, 0x80), state.a);
    try testing.expectEqual(@as(u8, 0x80), state.x);
    try testing.expect(state.p.negative);
}

test "LAX: absolute,Y page crossing" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.address_mode = .absolute_y;
    state.effective_address = 0x1100;
    state.page_crossed = true;
    bus.write(0x1100, 0xAA);

    _ = lax(&state, &bus);

    try testing.expectEqual(@as(u8, 0xAA), state.a);
    try testing.expectEqual(@as(u8, 0xAA), state.x);
}

test "LAX: indirect indexed" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.address_mode = .indirect_indexed;
    state.effective_address = 0x2000;
    state.page_crossed = false;
    state.temp_value = 0x77;

    _ = lax(&state, &bus);

    try testing.expectEqual(@as(u8, 0x77), state.a);
    try testing.expectEqual(@as(u8, 0x77), state.x);
}

test "SAX: zero page" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.a = 0xFF;
    state.x = 0x0F;
    state.address_mode = .zero_page;
    state.operand_low = 0x50;

    _ = sax(&state, &bus);

    try testing.expectEqual(@as(u8, 0x0F), bus.read(0x0050));
}

test "SAX: AND operation" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.a = 0xF0;
    state.x = 0x0F;
    state.address_mode = .zero_page;
    state.operand_low = 0x60;

    _ = sax(&state, &bus);

    // 0xF0 AND 0x0F = 0x00
    try testing.expectEqual(@as(u8, 0x00), bus.read(0x0060));
}

test "SAX: does not affect flags" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.a = 0x00;
    state.x = 0x00;
    state.p.zero = false;
    state.p.negative = true;
    state.address_mode = .zero_page;
    state.operand_low = 0x70;

    _ = sax(&state, &bus);

    // Flags should be unchanged
    try testing.expect(!state.p.zero);
    try testing.expect(state.p.negative);
}

test "SAX: absolute mode" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.a = 0xAA;
    state.x = 0x55;
    state.address_mode = .absolute;
    state.operand_low = 0x34;
    state.operand_high = 0x12;

    _ = sax(&state, &bus);

    // 0xAA AND 0x55 = 0x00
    try testing.expectEqual(@as(u8, 0x00), bus.read(0x1234));
}

test "SAX: zero page,Y" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.a = 0xFF;
    state.x = 0xF0;
    state.address_mode = .zero_page_y;
    state.effective_address = 0x0080;

    _ = sax(&state, &bus);

    // 0xFF AND 0xF0 = 0xF0
    try testing.expectEqual(@as(u8, 0xF0), bus.read(0x0080));
}

test "SAX: indexed indirect" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.a = 0b11110000;
    state.x = 0b10101010;
    state.address_mode = .indexed_indirect;
    state.effective_address = 0x1000;

    _ = sax(&state, &bus);

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
pub fn anc(state: *CpuState, bus: *BusState) bool {
    const value = bus.read(state.pc);
    state.pc +%= 1;
    state.a &= value;
    state.p.carry = (state.a & 0x80) != 0; // Carry equals negative flag
    state.p.updateZN(state.a);
    return true;
}

/// ALR/ASR - AND + LSR (1 opcode: $4B)
/// A = (A & operand) >> 1
/// Flags: C (from LSR), N, Z
///
/// Immediate mode only (2 cycles)
pub fn alr(state: *CpuState, bus: *BusState) bool {
    const value = bus.read(state.pc);
    state.pc +%= 1;
    state.a &= value;
    state.p.carry = (state.a & 0x01) != 0; // Carry from LSR
    state.a >>= 1;
    state.p.updateZN(state.a);
    return true;
}

/// ARR - AND + ROR (1 opcode: $6B)
/// A = (A & operand) ROR 1
/// Flags: C, V (complex), N, Z
///
/// Immediate mode only (2 cycles)
/// Flag behavior is complex: C from bit 6, V from bit 6 XOR bit 5
pub fn arr(state: *CpuState, bus: *BusState) bool {
    const value = bus.read(state.pc);
    state.pc +%= 1;
    state.a &= value;

    // ROR with carry
    const old_carry = state.p.carry;
    state.a = (state.a >> 1) | (@as(u8, if (old_carry) 0x80 else 0));

    // Complex flag behavior
    state.p.carry = (state.a & 0x40) != 0; // Carry from bit 6
    state.p.overflow = ((state.a & 0x40) != 0) != ((state.a & 0x20) != 0); // V = bit 6 XOR bit 5
    state.p.updateZN(state.a);

    return true;
}

/// AXS/SBX - (A & X) - operand → X (1 opcode: $CB)
/// X = (A & X) - operand (without borrow)
/// Flags: C (from comparison), N, Z
///
/// Immediate mode only (2 cycles)
pub fn axs(state: *CpuState, bus: *BusState) bool {
    const value = bus.read(state.pc);
    state.pc +%= 1;
    const temp = state.a & state.x;
    state.x = temp -% value;
    state.p.carry = temp >= value; // Carry as if comparison
    state.p.updateZN(state.x);
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
pub fn sha(state: *CpuState, bus: *BusState) bool {
    const high_byte = @as(u8, @truncate(state.effective_address >> 8));
    const value = state.a & state.x & (high_byte +% 1);
    bus.write(state.effective_address, value);
    return true;
}

/// SHX - Store X & (H+1)
/// M = X & (high_byte + 1)
/// Flags: None
///
/// UNSTABLE: High byte calculation sometimes fails on some chip revisions
/// Addressing mode: absolute,Y ($9E)
pub fn shx(state: *CpuState, bus: *BusState) bool {
    const high_byte = @as(u8, @truncate(state.effective_address >> 8));
    const value = state.x & (high_byte +% 1);
    bus.write(state.effective_address, value);
    return true;
}

/// SHY - Store Y & (H+1)
/// M = Y & (high_byte + 1)
/// Flags: None
///
/// UNSTABLE: High byte calculation sometimes fails on some chip revisions
/// Addressing mode: absolute,X ($9C)
pub fn shy(state: *CpuState, bus: *BusState) bool {
    const high_byte = @as(u8, @truncate(state.effective_address >> 8));
    const value = state.y & (high_byte +% 1);
    bus.write(state.effective_address, value);
    return true;
}

/// TAS/SHS - Transfer A & X to SP, then store A & X & (H+1)
/// SP = A & X
/// M = A & X & (high_byte + 1)
/// Flags: None
///
/// HIGHLY UNSTABLE: Behavior varies significantly between chip revisions
/// Addressing mode: absolute,Y ($9B)
pub fn tas(state: *CpuState, bus: *BusState) bool {
    const temp = state.a & state.x;
    state.sp = temp;
    const high_byte = @as(u8, @truncate(state.effective_address >> 8));
    const value = temp & (high_byte +% 1);
    bus.write(state.effective_address, value);
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
pub fn lae(state: *CpuState, bus: *BusState) bool {
    const value = helpers.readOperand(state, bus);
    const result = value & state.sp;
    state.a = result;
    state.x = result;
    state.sp = result;
    state.p.updateZN(result);
    return true;
}

/// XAA/ANE - Highly unstable AND operation
/// A = (A | MAGIC) & X & operand
/// Flags: N, Z
///
/// HIGHLY UNSTABLE: Magic constant varies by chip ($00, $EE, $FF, others)
/// This implementation uses $EE (most common NMOS behavior)
/// Addressing mode: immediate ($8B)
pub fn xaa(state: *CpuState, bus: *BusState) bool {
    const value = bus.read(state.pc);
    state.pc +%= 1;
    const magic: u8 = 0xEE; // Most common NMOS 6502 magic constant
    state.a = (state.a | magic) & state.x & value;
    state.p.updateZN(state.a);
    return true;
}

/// LXA - Highly unstable load A and X
/// A = X = (A | MAGIC) & operand
/// Flags: N, Z
///
/// HIGHLY UNSTABLE: Magic constant varies by chip ($00, $EE, $FF, others)
/// This implementation uses $EE (most common NMOS behavior)
/// Addressing mode: immediate ($AB)
pub fn lxa(state: *CpuState, bus: *BusState) bool {
    const value = bus.read(state.pc);
    state.pc +%= 1;
    const magic: u8 = 0xEE; // Most common NMOS 6502 magic constant
    const result = (state.a | magic) & value;
    state.a = result;
    state.x = result;
    state.p.updateZN(result);
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
pub fn jam(state: *CpuState, bus: *BusState) bool {
    _ = bus; // JAM doesn't access the bus after opcode fetch
    state.halted = true; // Set CPU halted state
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
pub fn slo(state: *CpuState, bus: *BusState) bool {
    // Read current value (addressing already handled RMW sequence)
    var value = state.temp_value;

    // ASL: Shift left
    const carry = (value & 0x80) != 0;
    value <<= 1;

    // Write modified value back (RMW addressing handles this)
    bus.write(state.effective_address, value);

    // ORA: OR with accumulator
    state.a |= value;

    // Update flags
    state.p.carry = carry;
    state.p.updateZN(state.a);

    return true;
}

/// RLA - Rotate Left + AND (ROL + AND)
/// M = (M << 1) | C, A &= M
/// Flags: C (from rotate), N, Z
///
/// This is a Read-Modify-Write instruction that:
/// 1. Rotates memory left through carry (ROL)
/// 2. ANDs the result with accumulator (AND)
pub fn rla(state: *CpuState, bus: *BusState) bool {
    var value = state.temp_value;

    // ROL: Rotate left through carry
    const old_carry = state.p.carry;
    const new_carry = (value & 0x80) != 0;
    value = (value << 1) | @as(u8, if (old_carry) 1 else 0);

    // Write modified value
    bus.write(state.effective_address, value);

    // AND: AND with accumulator
    state.a &= value;

    // Update flags
    state.p.carry = new_carry;
    state.p.updateZN(state.a);

    return true;
}

/// SRE - Shift Right + EOR (LSR + EOR)
/// M = M >> 1, A ^= M
/// Flags: C (from shift), N, Z
///
/// This is a Read-Modify-Write instruction that:
/// 1. Shifts memory right (LSR)
/// 2. XORs the result with accumulator (EOR)
pub fn sre(state: *CpuState, bus: *BusState) bool {
    var value = state.temp_value;

    // LSR: Shift right
    const carry = (value & 0x01) != 0;
    value >>= 1;

    // Write modified value
    bus.write(state.effective_address, value);

    // EOR: XOR with accumulator
    state.a ^= value;

    // Update flags
    state.p.carry = carry;
    state.p.updateZN(state.a);

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
pub fn rra(state: *CpuState, bus: *BusState) bool {
    var value = state.temp_value;

    // ROR: Rotate right through carry
    const old_carry = state.p.carry;
    const new_carry_from_rotate = (value & 0x01) != 0;
    value = (value >> 1) | (@as(u8, if (old_carry) 0x80 else 0));

    // Write modified value
    bus.write(state.effective_address, value);

    // ADC: Add with carry (using the NEW carry from rotate)
    const a = state.a;
    const carry_in: u8 = if (new_carry_from_rotate) 1 else 0;
    const result16 = @as(u16, a) + @as(u16, value) + @as(u16, carry_in);
    const result = @as(u8, @truncate(result16));

    // Set carry from addition
    state.p.carry = (result16 > 0xFF);

    // Set overflow
    const overflow = ((a ^ result) & (value ^ result) & 0x80) != 0;
    state.p.overflow = overflow;

    // Update accumulator and flags
    state.a = result;
    state.p.updateZN(result);

    return true;
}

/// DCP - Decrement + Compare (DEC + CMP)
/// M = M - 1, compare A with M
/// Flags: C, N, Z
///
/// This is a Read-Modify-Write instruction that:
/// 1. Decrements memory (DEC)
/// 2. Compares accumulator with the result (CMP)
pub fn dcp(state: *CpuState, bus: *BusState) bool {
    var value = state.temp_value;

    // DEC: Decrement
    value -%= 1;

    // Write modified value
    bus.write(state.effective_address, value);

    // CMP: Compare A with M
    const result = state.a -% value;
    state.p.carry = state.a >= value;
    state.p.zero = state.a == value;
    state.p.negative = (result & 0x80) != 0;

    return true;
}

/// ISC/ISB - Increment + Subtract (INC + SBC)
/// M = M + 1, A = A - M - (1 - C)
/// Flags: C, V, N, Z
///
/// This is a Read-Modify-Write instruction that:
/// 1. Increments memory (INC)
/// 2. Subtracts the result from accumulator with borrow (SBC)
pub fn isc(state: *CpuState, bus: *BusState) bool {
    var value = state.temp_value;

    // INC: Increment
    value +%= 1;

    // Write modified value
    bus.write(state.effective_address, value);

    // SBC: Subtract with carry (A - M - (1 - C))
    // SBC is equivalent to ADC with inverted operand: A + (~M) + C
    const inverted = ~value;
    const a = state.a;
    const carry: u8 = if (state.p.carry) 1 else 0;
    const result16 = @as(u16, a) + @as(u16, inverted) + @as(u16, carry);
    const result = @as(u8, @truncate(result16));

    state.p.carry = (result16 > 0xFF);
    const overflow = ((a ^ result) & (inverted ^ result) & 0x80) != 0;
    state.p.overflow = overflow;

    state.a = result;
    state.p.updateZN(result);

    return true;
}

// ============================================================================
// RMW Combo Tests
// ============================================================================

test "SLO: shift left and OR with accumulator" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    bus.write(0x0050, 0b01010101);
    state.temp_value = 0b01010101;
    state.effective_address = 0x0050;
    state.a = 0b00001111;
    state.p.carry = false;

    _ = slo(&state, &bus);

    // Memory: 0b01010101 << 1 = 0b10101010
    try testing.expectEqual(@as(u8, 0b10101010), bus.read(0x0050));
    // A: 0b00001111 | 0b10101010 = 0b10101111
    try testing.expectEqual(@as(u8, 0b10101111), state.a);
    try testing.expect(!state.p.carry); // Bit 7 was 0
    try testing.expect(state.p.negative); // Result bit 7 is 1
    try testing.expect(!state.p.zero);
}

test "SLO: sets carry flag" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.temp_value = 0b10000001;
    state.effective_address = 0x0100;
    state.a = 0x00;

    _ = slo(&state, &bus);

    try testing.expectEqual(@as(u8, 0b00000010), bus.read(0x0100));
    try testing.expectEqual(@as(u8, 0b00000010), state.a);
    try testing.expect(state.p.carry); // Bit 7 was 1
}

test "RLA: rotate left and AND with accumulator" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.temp_value = 0b01010101;
    state.effective_address = 0x0060;
    state.a = 0b11110000;
    state.p.carry = true; // Will be rotated in

    _ = rla(&state, &bus);

    // Memory: (0b01010101 << 1) | 1 = 0b10101011
    try testing.expectEqual(@as(u8, 0b10101011), bus.read(0x0060));
    // A: 0b11110000 & 0b10101011 = 0b10100000
    try testing.expectEqual(@as(u8, 0b10100000), state.a);
    try testing.expect(!state.p.carry); // Original bit 7 was 0
    try testing.expect(state.p.negative);
}

test "RLA: sets carry from rotate" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.temp_value = 0b11000000;
    state.effective_address = 0x0070;
    state.a = 0xFF;
    state.p.carry = false;

    _ = rla(&state, &bus);

    // Memory: 0b11000000 << 1 = 0b10000000
    try testing.expectEqual(@as(u8, 0b10000000), bus.read(0x0070));
    try testing.expect(state.p.carry); // Original bit 7 was 1
}

test "SRE: shift right and XOR with accumulator" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.temp_value = 0b10101010;
    state.effective_address = 0x0080;
    state.a = 0b11110000;

    _ = sre(&state, &bus);

    // Memory: 0b10101010 >> 1 = 0b01010101
    try testing.expectEqual(@as(u8, 0b01010101), bus.read(0x0080));
    // A: 0b11110000 ^ 0b01010101 = 0b10100101
    try testing.expectEqual(@as(u8, 0b10100101), state.a);
    try testing.expect(!state.p.carry); // Bit 0 was 0
    try testing.expect(state.p.negative);
}

test "SRE: sets carry flag" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.temp_value = 0b00000011;
    state.effective_address = 0x0090;
    state.a = 0x00;

    _ = sre(&state, &bus);

    try testing.expectEqual(@as(u8, 0b00000001), bus.read(0x0090));
    try testing.expect(state.p.carry); // Bit 0 was 1
}

test "RRA: rotate right and add with carry" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.temp_value = 0b00000010;
    state.effective_address = 0x00A0;
    state.a = 0x10;
    state.p.carry = true; // Will be rotated in

    _ = rra(&state, &bus);

    // Memory: (0b00000010 >> 1) | 0x80 = 0b10000001
    try testing.expectEqual(@as(u8, 0b10000001), bus.read(0x00A0));
    // A: 0x10 + 0b10000001 + 0 (new carry from rotate) = 0x91
    try testing.expectEqual(@as(u8, 0x91), state.a);
    try testing.expect(!state.p.carry); // No carry from addition
    try testing.expect(state.p.negative);
}

test "RRA: carry from rotate used in ADC" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.temp_value = 0b00000001; // Bit 0 = 1, will set carry
    state.effective_address = 0x00B0;
    state.a = 0x00;
    state.p.carry = false;

    _ = rra(&state, &bus);

    // Memory: 0b00000001 >> 1 = 0b00000000
    try testing.expectEqual(@as(u8, 0x00), bus.read(0x00B0));
    // A: 0x00 + 0x00 + 1 (carry from rotate) = 0x01
    try testing.expectEqual(@as(u8, 0x01), state.a);
}

test "DCP: decrement and compare" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.temp_value = 0x50;
    state.effective_address = 0x00C0;
    state.a = 0x4F;

    _ = dcp(&state, &bus);

    // Memory: 0x50 - 1 = 0x4F
    try testing.expectEqual(@as(u8, 0x4F), bus.read(0x00C0));
    // Compare: A (0x4F) == M (0x4F)
    try testing.expect(state.p.zero);
    try testing.expect(state.p.carry); // A >= M
    try testing.expect(!state.p.negative);
}

test "DCP: compare flags when A < M" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.temp_value = 0x60;
    state.effective_address = 0x00D0;
    state.a = 0x50;

    _ = dcp(&state, &bus);

    // Memory: 0x60 - 1 = 0x5F
    try testing.expectEqual(@as(u8, 0x5F), bus.read(0x00D0));
    // Compare: A (0x50) < M (0x5F)
    try testing.expect(!state.p.zero);
    try testing.expect(!state.p.carry); // A < M
    try testing.expect(state.p.negative); // Result is negative
}

test "ISC: increment and subtract with carry" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.temp_value = 0x0F;
    state.effective_address = 0x00E0;
    state.a = 0x20;
    state.p.carry = true; // No borrow

    _ = isc(&state, &bus);

    // Memory: 0x0F + 1 = 0x10
    try testing.expectEqual(@as(u8, 0x10), bus.read(0x00E0));
    // A: 0x20 - 0x10 = 0x10
    try testing.expectEqual(@as(u8, 0x10), state.a);
    try testing.expect(state.p.carry); // No borrow
    try testing.expect(!state.p.zero);
}

test "ISC: subtract with borrow" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.temp_value = 0x0F;
    state.effective_address = 0x00F0;
    state.a = 0x20;
    state.p.carry = false; // Borrow

    _ = isc(&state, &bus);

    // Memory: 0x0F + 1 = 0x10
    try testing.expectEqual(@as(u8, 0x10), bus.read(0x00F0));
    // A: 0x20 - 0x10 - 1 = 0x0F
    try testing.expectEqual(@as(u8, 0x0F), state.a);
}
