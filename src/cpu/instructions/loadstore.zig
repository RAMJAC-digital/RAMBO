//! Load and Store Instructions
//!
//! LDA - Load Accumulator
//! LDX - Load X Register
//! LDY - Load Y Register
//! STA - Store Accumulator
//! STX - Store X Register
//! STY - Store Y Register
//!
//! All load instructions update N and Z flags.
//! Store instructions do not affect any flags.

const Cpu = @import("../Cpu.zig").Cpu;
const Bus = @import("../../bus/Bus.zig").Bus;
const helpers = @import("../helpers.zig");

// ============================================================================
// Load Instructions
// ============================================================================

/// LDA - Load Accumulator
/// A = M
/// Flags: N, Z
///
/// Supports all 8 addressing modes:
/// - Immediate, Zero Page, Zero Page,X
/// - Absolute, Absolute,X, Absolute,Y
/// - Indexed Indirect, Indirect Indexed
pub fn lda(cpu: *Cpu, bus: *Bus) bool {
    const value = helpers.readOperand(cpu, bus);

    cpu.a = value;
    cpu.p.updateZN(cpu.a);
    return true;
}

/// LDX - Load X Register
/// X = M
/// Flags: N, Z
///
/// Supports 5 addressing modes:
/// - Immediate, Zero Page, Zero Page,Y
/// - Absolute, Absolute,Y
pub fn ldx(cpu: *Cpu, bus: *Bus) bool {
    const value = helpers.readOperand(cpu, bus);

    cpu.x = value;
    cpu.p.updateZN(cpu.x);
    return true;
}

/// LDY - Load Y Register
/// Y = M
/// Flags: N, Z
///
/// Supports 5 addressing modes:
/// - Immediate, Zero Page, Zero Page,X
/// - Absolute, Absolute,X
pub fn ldy(cpu: *Cpu, bus: *Bus) bool {
    const value = helpers.readOperand(cpu, bus);

    cpu.y = value;
    cpu.p.updateZN(cpu.y);
    return true;
}

// ============================================================================
// Store Instructions
// ============================================================================

/// STA - Store Accumulator
/// M = A
/// Flags: None
///
/// Supports 7 addressing modes (no immediate):
/// - Zero Page, Zero Page,X
/// - Absolute, Absolute,X, Absolute,Y
/// - Indexed Indirect, Indirect Indexed
pub fn sta(cpu: *Cpu, bus: *Bus) bool {
    helpers.writeOperand(cpu, bus, cpu.a);
    return true;
}

/// STX - Store X Register
/// M = X
/// Flags: None
///
/// Supports 3 addressing modes:
/// - Zero Page, Zero Page,Y
/// - Absolute
pub fn stx(cpu: *Cpu, bus: *Bus) bool {
    helpers.writeOperand(cpu, bus, cpu.x);
    return true;
}

/// STY - Store Y Register
/// M = Y
/// Flags: None
///
/// Supports 3 addressing modes:
/// - Zero Page, Zero Page,X
/// - Absolute
pub fn sty(cpu: *Cpu, bus: *Bus) bool {
    helpers.writeOperand(cpu, bus, cpu.y);
    return true;
}

// ============================================================================
// Tests
// ============================================================================

const std = @import("std");
const testing = std.testing;

test "LDA: immediate mode" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.address_mode = .immediate;
    cpu.pc = 0;
    bus.ram[0] = 0x42;

    _ = lda(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x42), cpu.a);
    try testing.expect(!cpu.p.zero);
    try testing.expect(!cpu.p.negative);
}

test "LDA: zero flag" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.address_mode = .immediate;
    cpu.pc = 0;
    bus.ram[0] = 0x00;

    _ = lda(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x00), cpu.a);
    try testing.expect(cpu.p.zero);
    try testing.expect(!cpu.p.negative);
}

test "LDA: negative flag" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.address_mode = .immediate;
    cpu.pc = 0;
    bus.ram[0] = 0x80;

    _ = lda(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x80), cpu.a);
    try testing.expect(!cpu.p.zero);
    try testing.expect(cpu.p.negative);
}

test "LDA: zero page" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.write(0x0042, 0x55);
    cpu.address_mode = .zero_page;
    cpu.operand_low = 0x42;

    _ = lda(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x55), cpu.a);
}

test "LDA: absolute" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.write(0x1234, 0xAA);
    cpu.address_mode = .absolute;
    cpu.operand_low = 0x34;
    cpu.operand_high = 0x12;

    _ = lda(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0xAA), cpu.a);
}

test "LDX: immediate mode" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.address_mode = .immediate;
    cpu.pc = 0;
    bus.ram[0] = 0x42;

    _ = ldx(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x42), cpu.x);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC increments
    try testing.expect(!cpu.p.zero);
    try testing.expect(!cpu.p.negative);
}

test "LDY: immediate mode" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.address_mode = .immediate;
    cpu.pc = 0;
    bus.ram[0] = 0x42;

    _ = ldy(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x42), cpu.y);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC increments
    try testing.expect(!cpu.p.zero);
    try testing.expect(!cpu.p.negative);
}

test "STA: zero page" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x42;
    cpu.address_mode = .zero_page;
    cpu.operand_low = 0x50;

    _ = sta(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x42), bus.read(0x0050));
}

test "STA: absolute" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x55;
    cpu.address_mode = .absolute;
    cpu.operand_low = 0x34;
    cpu.operand_high = 0x12;

    _ = sta(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x55), bus.read(0x1234));
}

test "STA: does not affect flags" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x00; // Would set zero flag if LDA
    cpu.p.zero = false;
    cpu.p.negative = true;
    cpu.address_mode = .zero_page;
    cpu.operand_low = 0x50;

    _ = sta(&cpu, &bus);

    // Flags should be unchanged
    try testing.expect(!cpu.p.zero);
    try testing.expect(cpu.p.negative);
}

test "STX: zero page" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.x = 0x42;
    cpu.address_mode = .zero_page;
    cpu.operand_low = 0x50;

    _ = stx(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x42), bus.read(0x0050));
}

test "STY: zero page" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.y = 0x42;
    cpu.address_mode = .zero_page;
    cpu.operand_low = 0x50;

    _ = sty(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x42), bus.read(0x0050));
}

test "load/store: page crossing with absolute,X" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: absolute,X with page crossing
    cpu.address_mode = .absolute_x;
    cpu.effective_address = 0x1100;
    cpu.page_crossed = true;
    bus.write(0x1100, 0x42);

    // Load
    _ = lda(&cpu, &bus);
    try testing.expectEqual(@as(u8, 0x42), cpu.a);

    // Store
    cpu.a = 0x55;
    _ = sta(&cpu, &bus);
    try testing.expectEqual(@as(u8, 0x55), bus.read(0x1100));
}

test "load/store: no page crossing uses temp_value" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.address_mode = .absolute_x;
    cpu.page_crossed = false;
    cpu.temp_value = 0x42;

    _ = lda(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x42), cpu.a);
}
