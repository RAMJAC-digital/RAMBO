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

const Cpu = @import("../Cpu.zig");
const Bus = @import("../../bus/Bus.zig").Bus;
const helpers = @import("../helpers.zig");

const State = Cpu.State.State;

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
pub fn lda(state: *State, bus: *Bus) bool {
    const value = helpers.readOperand(state, bus);

    state.a = value;
    state.p.updateZN(state.a);
    return true;
}

/// LDX - Load X Register
/// X = M
/// Flags: N, Z
///
/// Supports 5 addressing modes:
/// - Immediate, Zero Page, Zero Page,Y
/// - Absolute, Absolute,Y
pub fn ldx(state: *State, bus: *Bus) bool {
    const value = helpers.readOperand(state, bus);

    state.x = value;
    state.p.updateZN(state.x);
    return true;
}

/// LDY - Load Y Register
/// Y = M
/// Flags: N, Z
///
/// Supports 5 addressing modes:
/// - Immediate, Zero Page, Zero Page,X
/// - Absolute, Absolute,X
pub fn ldy(state: *State, bus: *Bus) bool {
    const value = helpers.readOperand(state, bus);

    state.y = value;
    state.p.updateZN(state.y);
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
pub fn sta(state: *State, bus: *Bus) bool {
    helpers.writeOperand(state, bus, state.a);
    return true;
}

/// STX - Store X Register
/// M = X
/// Flags: None
///
/// Supports 3 addressing modes:
/// - Zero Page, Zero Page,Y
/// - Absolute
pub fn stx(state: *State, bus: *Bus) bool {
    helpers.writeOperand(state, bus, state.x);
    return true;
}

/// STY - Store Y Register
/// M = Y
/// Flags: None
///
/// Supports 3 addressing modes:
/// - Zero Page, Zero Page,X
/// - Absolute
pub fn sty(state: *State, bus: *Bus) bool {
    helpers.writeOperand(state, bus, state.y);
    return true;
}

// ============================================================================
// Tests
// ============================================================================

const std = @import("std");
const testing = std.testing;

test "LDA: immediate mode" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.address_mode = .immediate;
    state.pc = 0;
    bus.ram[0] = 0x42;

    _ = lda(&state, &bus);

    try testing.expectEqual(@as(u8, 0x42), state.a);
    try testing.expect(!state.p.zero);
    try testing.expect(!state.p.negative);
}

test "LDA: zero flag" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.address_mode = .immediate;
    state.pc = 0;
    bus.ram[0] = 0x00;

    _ = lda(&state, &bus);

    try testing.expectEqual(@as(u8, 0x00), state.a);
    try testing.expect(state.p.zero);
    try testing.expect(!state.p.negative);
}

test "LDA: negative flag" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.address_mode = .immediate;
    state.pc = 0;
    bus.ram[0] = 0x80;

    _ = lda(&state, &bus);

    try testing.expectEqual(@as(u8, 0x80), state.a);
    try testing.expect(!state.p.zero);
    try testing.expect(state.p.negative);
}

test "LDA: zero page" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    bus.write(0x0042, 0x55);
    state.address_mode = .zero_page;
    state.operand_low = 0x42;

    _ = lda(&state, &bus);

    try testing.expectEqual(@as(u8, 0x55), state.a);
}

test "LDA: absolute" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    bus.write(0x1234, 0xAA);
    state.address_mode = .absolute;
    state.operand_low = 0x34;
    state.operand_high = 0x12;

    _ = lda(&state, &bus);

    try testing.expectEqual(@as(u8, 0xAA), state.a);
}

test "LDX: immediate mode" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.address_mode = .immediate;
    state.pc = 0;
    bus.ram[0] = 0x42;

    _ = ldx(&state, &bus);

    try testing.expectEqual(@as(u8, 0x42), state.x);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC increments
    try testing.expect(!state.p.zero);
    try testing.expect(!state.p.negative);
}

test "LDY: immediate mode" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.address_mode = .immediate;
    state.pc = 0;
    bus.ram[0] = 0x42;

    _ = ldy(&state, &bus);

    try testing.expectEqual(@as(u8, 0x42), state.y);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC increments
    try testing.expect(!state.p.zero);
    try testing.expect(!state.p.negative);
}

test "STA: zero page" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x42;
    state.address_mode = .zero_page;
    state.operand_low = 0x50;

    _ = sta(&state, &bus);

    try testing.expectEqual(@as(u8, 0x42), bus.read(0x0050));
}

test "STA: absolute" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x55;
    state.address_mode = .absolute;
    state.operand_low = 0x34;
    state.operand_high = 0x12;

    _ = sta(&state, &bus);

    try testing.expectEqual(@as(u8, 0x55), bus.read(0x1234));
}

test "STA: does not affect flags" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.a = 0x00; // Would set zero flag if LDA
    state.p.zero = false;
    state.p.negative = true;
    state.address_mode = .zero_page;
    state.operand_low = 0x50;

    _ = sta(&state, &bus);

    // Flags should be unchanged
    try testing.expect(!state.p.zero);
    try testing.expect(state.p.negative);
}

test "STX: zero page" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.x = 0x42;
    state.address_mode = .zero_page;
    state.operand_low = 0x50;

    _ = stx(&state, &bus);

    try testing.expectEqual(@as(u8, 0x42), bus.read(0x0050));
}

test "STY: zero page" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.y = 0x42;
    state.address_mode = .zero_page;
    state.operand_low = 0x50;

    _ = sty(&state, &bus);

    try testing.expectEqual(@as(u8, 0x42), bus.read(0x0050));
}

test "load/store: page crossing with absolute,X" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    // Setup: absolute,X with page crossing
    state.address_mode = .absolute_x;
    state.effective_address = 0x1100;
    state.page_crossed = true;
    bus.write(0x1100, 0x42);

    // Load
    _ = lda(&state, &bus);
    try testing.expectEqual(@as(u8, 0x42), state.a);

    // Store
    state.a = 0x55;
    _ = sta(&state, &bus);
    try testing.expectEqual(@as(u8, 0x55), bus.read(0x1100));
}

test "load/store: no page crossing uses temp_value" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.address_mode = .absolute_x;
    state.page_crossed = false;
    state.temp_value = 0x42;

    _ = lda(&state, &bus);

    try testing.expectEqual(@as(u8, 0x42), state.a);
}
