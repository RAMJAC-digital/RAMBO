//! Branch Instructions
//!
//! All branch instructions use relative addressing mode and take 2-4 cycles:
//! - 2 cycles: Branch not taken
//! - 3 cycles: Branch taken, no page crossing
//! - 4 cycles: Branch taken, page crossing
//!
//! The execute function returns:
//! - true if branch not taken or taken without page crossing
//! - false if page crossing occurred (need page fix cycle)

const std = @import("std");
const Cpu = @import("../Cpu.zig");
const BusState = @import("../../bus/Bus.zig").State.BusState;

const CpuState = Cpu.State.CpuState;

/// BCC - Branch if Carry Clear
/// Branch if C = 0
pub fn bcc(state: *CpuState, bus: *BusState) bool {
    if (state.p.carry) {
        return true; // Not taken, 2 cycles total
    }
    return performBranch(state, bus);
}

/// BCS - Branch if Carry Set
/// Branch if C = 1
pub fn bcs(state: *CpuState, bus: *BusState) bool {
    if (!state.p.carry) {
        return true; // Not taken
    }
    return performBranch(state, bus);
}

/// BEQ - Branch if Equal
/// Branch if Z = 1
pub fn beq(state: *CpuState, bus: *BusState) bool {
    if (!state.p.zero) {
        return true; // Not taken
    }
    return performBranch(state, bus);
}

/// BNE - Branch if Not Equal
/// Branch if Z = 0
pub fn bne(state: *CpuState, bus: *BusState) bool {
    if (state.p.zero) {
        return true; // Not taken
    }
    return performBranch(state, bus);
}

/// BMI - Branch if Minus
/// Branch if N = 1
pub fn bmi(state: *CpuState, bus: *BusState) bool {
    if (!state.p.negative) {
        return true; // Not taken
    }
    return performBranch(state, bus);
}

/// BPL - Branch if Plus
/// Branch if N = 0
pub fn bpl(state: *CpuState, bus: *BusState) bool {
    if (state.p.negative) {
        return true; // Not taken
    }
    return performBranch(state, bus);
}

/// BVC - Branch if Overflow Clear
/// Branch if V = 0
pub fn bvc(state: *CpuState, bus: *BusState) bool {
    if (state.p.overflow) {
        return true; // Not taken
    }
    return performBranch(state, bus);
}

/// BVS - Branch if Overflow Set
/// Branch if V = 1
pub fn bvs(state: *CpuState, bus: *BusState) bool {
    if (!state.p.overflow) {
        return true; // Not taken
    }
    return performBranch(state, bus);
}

/// Perform the actual branch operation
/// Returns false if page crossing occurred
fn performBranch(state: *CpuState, bus: *BusState) bool {
    // Dummy read during offset calculation
    _ = bus.read(state.pc);

    // Calculate new PC with signed offset
    const offset = @as(i8, @bitCast(state.operand_low));
    const old_pc = state.pc;
    state.pc = @as(u16, @bitCast(@as(i16, @bitCast(old_pc)) +% offset));

    // Check for page crossing
    state.page_crossed = (old_pc & 0xFF00) != (state.pc & 0xFF00);

    if (!state.page_crossed) {
        return true; // 3 cycles total
    }

    return false; // Need page fix, 4 cycles total
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "BCC: branch not taken when carry set" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.p.carry = true;
    state.pc = 0x8000;
    state.operand_low = 0x10;

    _ = bcc(&state, &bus);

    try testing.expectEqual(@as(u16, 0x8000), state.pc); // PC unchanged
}

test "BCC: branch taken, no page cross" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.p.carry = false;
    state.pc = 0x8000;
    state.operand_low = 0x10; // +16

    const result = bcc(&state, &bus);

    try testing.expectEqual(@as(u16, 0x8010), state.pc);
    try testing.expect(!state.page_crossed);
    try testing.expect(result); // Completes
}

test "BCC: branch taken with page cross" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.p.carry = false;
    state.pc = 0x80F0;
    state.operand_low = 0x20; // +32, crosses to $8110

    const result = bcc(&state, &bus);

    try testing.expectEqual(@as(u16, 0x8110), state.pc);
    try testing.expect(state.page_crossed);
    try testing.expect(!result); // Needs page fix cycle
}

test "BCC: backward branch" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.p.carry = false;
    state.pc = 0x8010;
    state.operand_low = @as(u8, @bitCast(@as(i8, -16))); // -16

    _ = bcc(&state, &bus);

    try testing.expectEqual(@as(u16, 0x8000), state.pc);
}

test "BCS: branch taken when carry set" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.p.carry = true;
    state.pc = 0x8000;
    state.operand_low = 0x10;

    _ = bcs(&state, &bus);

    try testing.expectEqual(@as(u16, 0x8010), state.pc);
}

test "BEQ: branch taken when zero set" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.p.zero = true;
    state.pc = 0x8000;
    state.operand_low = 0x05;

    _ = beq(&state, &bus);

    try testing.expectEqual(@as(u16, 0x8005), state.pc);
}

test "BNE: branch taken when zero clear" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.p.zero = false;
    state.pc = 0x8000;
    state.operand_low = 0x08;

    _ = bne(&state, &bus);

    try testing.expectEqual(@as(u16, 0x8008), state.pc);
}

test "BMI: branch taken when negative set" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.p.negative = true;
    state.pc = 0x8000;
    state.operand_low = 0x0A;

    _ = bmi(&state, &bus);

    try testing.expectEqual(@as(u16, 0x800A), state.pc);
}

test "BPL: branch taken when negative clear" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.p.negative = false;
    state.pc = 0x8000;
    state.operand_low = 0x0C;

    _ = bpl(&state, &bus);

    try testing.expectEqual(@as(u16, 0x800C), state.pc);
}

test "BVC: branch taken when overflow clear" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.p.overflow = false;
    state.pc = 0x8000;
    state.operand_low = 0x15;

    _ = bvc(&state, &bus);

    try testing.expectEqual(@as(u16, 0x8015), state.pc);
}

test "BVS: branch taken when overflow set" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.p.overflow = true;
    state.pc = 0x8000;
    state.operand_low = 0x20;

    _ = bvs(&state, &bus);

    try testing.expectEqual(@as(u16, 0x8020), state.pc);
}

test "branch: page crossing backward" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.p.zero = true;
    state.pc = 0x8010;
    state.operand_low = @as(u8, @bitCast(@as(i8, -32))); // -32, crosses to $7FF0

    const result = beq(&state, &bus);

    try testing.expectEqual(@as(u16, 0x7FF0), state.pc);
    try testing.expect(state.page_crossed);
    try testing.expect(!result); // Needs page fix
}
