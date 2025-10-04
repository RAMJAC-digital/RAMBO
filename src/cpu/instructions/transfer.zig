//! Transfer and Flag Instructions
//!
//! Transfer instructions: TAX, TXA, TAY, TYA, TSX, TXS
//! Flag instructions: SEC, CLC, SEI, CLI, SED, CLD, CLV
//! BIT instruction: Test bits in memory with accumulator
//!
//! All are 2-cycle implied mode instructions except BIT (3-4 cycles)

const std = @import("std");
const Cpu = @import("../Cpu.zig");
const BusState = @import("../../bus/Bus.zig").State.BusState;

const CpuState = Cpu.State.CpuState;

// ============================================================================
// Transfer Instructions (2 cycles, implied mode)
// ============================================================================

/// TAX - Transfer Accumulator to X
/// X = A
/// Flags: N, Z
pub fn tax(state: *CpuState, bus: *BusState) bool {
    _ = bus;
    state.x = state.a;
    state.p.updateZN(state.x);
    return true;
}

/// TXA - Transfer X to Accumulator
/// A = X
/// Flags: N, Z
pub fn txa(state: *CpuState, bus: *BusState) bool {
    _ = bus;
    state.a = state.x;
    state.p.updateZN(state.a);
    return true;
}

/// TAY - Transfer Accumulator to Y
/// Y = A
/// Flags: N, Z
pub fn tay(state: *CpuState, bus: *BusState) bool {
    _ = bus;
    state.y = state.a;
    state.p.updateZN(state.y);
    return true;
}

/// TYA - Transfer Y to Accumulator
/// A = Y
/// Flags: N, Z
pub fn tya(state: *CpuState, bus: *BusState) bool {
    _ = bus;
    state.a = state.y;
    state.p.updateZN(state.a);
    return true;
}

/// TSX - Transfer Stack Pointer to X
/// X = SP
/// Flags: N, Z
pub fn tsx(state: *CpuState, bus: *BusState) bool {
    _ = bus;
    state.x = state.sp;
    state.p.updateZN(state.x);
    return true;
}

/// TXS - Transfer X to Stack Pointer
/// SP = X
/// Flags: None
pub fn txs(state: *CpuState, bus: *BusState) bool {
    _ = bus;
    state.sp = state.x;
    return true;
}

// ============================================================================
// Flag Instructions (2 cycles, implied mode)
// ============================================================================

/// SEC - Set Carry Flag
/// C = 1
pub fn sec(state: *CpuState, bus: *BusState) bool {
    _ = bus;
    state.p.carry = true;
    return true;
}

/// CLC - Clear Carry Flag
/// C = 0
pub fn clc(state: *CpuState, bus: *BusState) bool {
    _ = bus;
    state.p.carry = false;
    return true;
}

/// SEI - Set Interrupt Disable
/// I = 1
pub fn sei(state: *CpuState, bus: *BusState) bool {
    _ = bus;
    state.p.interrupt = true;
    return true;
}

/// CLI - Clear Interrupt Disable
/// I = 0
pub fn cli(state: *CpuState, bus: *BusState) bool {
    _ = bus;
    state.p.interrupt = false;
    return true;
}

/// SED - Set Decimal Flag
/// D = 1
/// Note: NES CPU ignores decimal mode, but flag can still be set
pub fn sed(state: *CpuState, bus: *BusState) bool {
    _ = bus;
    state.p.decimal = true;
    return true;
}

/// CLD - Clear Decimal Flag
/// D = 0
pub fn cld(state: *CpuState, bus: *BusState) bool {
    _ = bus;
    state.p.decimal = false;
    return true;
}

/// CLV - Clear Overflow Flag
/// V = 0
pub fn clv(state: *CpuState, bus: *BusState) bool {
    _ = bus;
    state.p.overflow = false;
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
pub fn bit(state: *CpuState, bus: *BusState) bool {
    _ = bus;
    var value: u8 = undefined;

    if (state.address_mode == .zero_page) {
        value = state.temp_value;
    } else if (state.address_mode == .absolute) {
        value = state.temp_value;
    } else {
        unreachable; // BIT only supports zero page and absolute
    }

    // Set N and V from memory value
    state.p.negative = (value & 0x80) != 0;
    state.p.overflow = (value & 0x40) != 0;

    // Set Z from AND result
    const result = state.a & value;
    state.p.zero = (result == 0);

    return true;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "TAX: transfer and update flags" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.a = 0x42;
    _ = tax(&state, &bus);

    try testing.expectEqual(@as(u8, 0x42), state.x);
    try testing.expect(!state.p.zero);
    try testing.expect(!state.p.negative);
}

test "TAX: zero flag" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.a = 0x00;
    _ = tax(&state, &bus);

    try testing.expectEqual(@as(u8, 0x00), state.x);
    try testing.expect(state.p.zero);
}

test "TXA: transfer and update flags" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.x = 0x80;
    _ = txa(&state, &bus);

    try testing.expectEqual(@as(u8, 0x80), state.a);
    try testing.expect(state.p.negative);
}

test "TAY and TYA: round trip" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.a = 0x55;
    _ = tay(&state, &bus);
    try testing.expectEqual(@as(u8, 0x55), state.y);

    state.a = 0x00; // Clear A
    _ = tya(&state, &bus);
    try testing.expectEqual(@as(u8, 0x55), state.a);
}

test "TSX: transfer stack pointer" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.sp = 0xFD;
    _ = tsx(&state, &bus);

    try testing.expectEqual(@as(u8, 0xFD), state.x);
    try testing.expect(state.p.negative); // 0xFD has bit 7 set
}

test "TXS: transfer to stack pointer, no flags" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.x = 0x80;
    const old_flags = state.p;

    _ = txs(&state, &bus);

    try testing.expectEqual(@as(u8, 0x80), state.sp);
    // Flags should be unchanged
    try testing.expectEqual(old_flags.toByte(), state.p.toByte());
}

test "SEC and CLC" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.p.carry = false;
    _ = sec(&state, &bus);
    try testing.expect(state.p.carry);

    _ = clc(&state, &bus);
    try testing.expect(!state.p.carry);
}

test "SEI and CLI" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.p.interrupt = false;
    _ = sei(&state, &bus);
    try testing.expect(state.p.interrupt);

    _ = cli(&state, &bus);
    try testing.expect(!state.p.interrupt);
}

test "SED and CLD" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.p.decimal = false;
    _ = sed(&state, &bus);
    try testing.expect(state.p.decimal);

    _ = cld(&state, &bus);
    try testing.expect(!state.p.decimal);
}

test "CLV: clear overflow" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.p.overflow = true;
    _ = clv(&state, &bus);
    try testing.expect(!state.p.overflow);
}

test "BIT: zero page mode" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.a = 0xFF;
    state.temp_value = 0xC0; // Bits 7 and 6 set
    state.address_mode = .zero_page;

    _ = bit(&state, &bus);

    try testing.expect(state.p.negative); // Bit 7 of memory
    try testing.expect(state.p.overflow); // Bit 6 of memory
    try testing.expect(!state.p.zero); // A & M != 0
}

test "BIT: zero flag set" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.a = 0x0F;
    state.temp_value = 0xF0; // No overlap with A
    state.address_mode = .zero_page;

    _ = bit(&state, &bus);

    try testing.expect(state.p.negative); // Bit 7 of 0xF0
    try testing.expect(state.p.overflow); // Bit 6 of 0xF0
    try testing.expect(state.p.zero); // A & M == 0
}

test "BIT: flags from memory value" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.a = 0xFF;
    state.temp_value = 0x00; // All bits clear
    state.address_mode = .zero_page;

    _ = bit(&state, &bus);

    try testing.expect(!state.p.negative); // Bit 7 of 0x00
    try testing.expect(!state.p.overflow); // Bit 6 of 0x00
    try testing.expect(state.p.zero); // A & M == 0
}
