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
const Cpu = @import("../Cpu.zig").Cpu;
const Bus = @import("../../bus/Bus.zig").Bus;

/// BCC - Branch if Carry Clear
/// Branch if C = 0
pub fn bcc(cpu: *Cpu, bus: *Bus) bool {
    if (cpu.p.carry) {
        return true; // Not taken, 2 cycles total
    }
    return performBranch(cpu, bus);
}

/// BCS - Branch if Carry Set
/// Branch if C = 1
pub fn bcs(cpu: *Cpu, bus: *Bus) bool {
    if (!cpu.p.carry) {
        return true; // Not taken
    }
    return performBranch(cpu, bus);
}

/// BEQ - Branch if Equal
/// Branch if Z = 1
pub fn beq(cpu: *Cpu, bus: *Bus) bool {
    if (!cpu.p.zero) {
        return true; // Not taken
    }
    return performBranch(cpu, bus);
}

/// BNE - Branch if Not Equal
/// Branch if Z = 0
pub fn bne(cpu: *Cpu, bus: *Bus) bool {
    if (cpu.p.zero) {
        return true; // Not taken
    }
    return performBranch(cpu, bus);
}

/// BMI - Branch if Minus
/// Branch if N = 1
pub fn bmi(cpu: *Cpu, bus: *Bus) bool {
    if (!cpu.p.negative) {
        return true; // Not taken
    }
    return performBranch(cpu, bus);
}

/// BPL - Branch if Plus
/// Branch if N = 0
pub fn bpl(cpu: *Cpu, bus: *Bus) bool {
    if (cpu.p.negative) {
        return true; // Not taken
    }
    return performBranch(cpu, bus);
}

/// BVC - Branch if Overflow Clear
/// Branch if V = 0
pub fn bvc(cpu: *Cpu, bus: *Bus) bool {
    if (cpu.p.overflow) {
        return true; // Not taken
    }
    return performBranch(cpu, bus);
}

/// BVS - Branch if Overflow Set
/// Branch if V = 1
pub fn bvs(cpu: *Cpu, bus: *Bus) bool {
    if (!cpu.p.overflow) {
        return true; // Not taken
    }
    return performBranch(cpu, bus);
}

/// Perform the actual branch operation
/// Returns false if page crossing occurred
fn performBranch(cpu: *Cpu, bus: *Bus) bool {
    // Dummy read during offset calculation
    _ = bus.read(cpu.pc);

    // Calculate new PC with signed offset
    const offset = @as(i8, @bitCast(cpu.operand_low));
    const old_pc = cpu.pc;
    cpu.pc = @as(u16, @bitCast(@as(i16, @bitCast(old_pc)) +% offset));

    // Check for page crossing
    cpu.page_crossed = (old_pc & 0xFF00) != (cpu.pc & 0xFF00);

    if (!cpu.page_crossed) {
        return true; // 3 cycles total
    }

    return false; // Need page fix, 4 cycles total
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "BCC: branch not taken when carry set" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.p.carry = true;
    cpu.pc = 0x8000;
    cpu.operand_low = 0x10;

    _ = bcc(&cpu, &bus);

    try testing.expectEqual(@as(u16, 0x8000), cpu.pc); // PC unchanged
}

test "BCC: branch taken, no page cross" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.p.carry = false;
    cpu.pc = 0x8000;
    cpu.operand_low = 0x10; // +16

    const result = bcc(&cpu, &bus);

    try testing.expectEqual(@as(u16, 0x8010), cpu.pc);
    try testing.expect(!cpu.page_crossed);
    try testing.expect(result); // Completes
}

test "BCC: branch taken with page cross" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.p.carry = false;
    cpu.pc = 0x80F0;
    cpu.operand_low = 0x20; // +32, crosses to $8110

    const result = bcc(&cpu, &bus);

    try testing.expectEqual(@as(u16, 0x8110), cpu.pc);
    try testing.expect(cpu.page_crossed);
    try testing.expect(!result); // Needs page fix cycle
}

test "BCC: backward branch" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.p.carry = false;
    cpu.pc = 0x8010;
    cpu.operand_low = @as(u8, @bitCast(@as(i8, -16))); // -16

    _ = bcc(&cpu, &bus);

    try testing.expectEqual(@as(u16, 0x8000), cpu.pc);
}

test "BCS: branch taken when carry set" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.p.carry = true;
    cpu.pc = 0x8000;
    cpu.operand_low = 0x10;

    _ = bcs(&cpu, &bus);

    try testing.expectEqual(@as(u16, 0x8010), cpu.pc);
}

test "BEQ: branch taken when zero set" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.p.zero = true;
    cpu.pc = 0x8000;
    cpu.operand_low = 0x05;

    _ = beq(&cpu, &bus);

    try testing.expectEqual(@as(u16, 0x8005), cpu.pc);
}

test "BNE: branch taken when zero clear" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.p.zero = false;
    cpu.pc = 0x8000;
    cpu.operand_low = 0x08;

    _ = bne(&cpu, &bus);

    try testing.expectEqual(@as(u16, 0x8008), cpu.pc);
}

test "BMI: branch taken when negative set" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.p.negative = true;
    cpu.pc = 0x8000;
    cpu.operand_low = 0x0A;

    _ = bmi(&cpu, &bus);

    try testing.expectEqual(@as(u16, 0x800A), cpu.pc);
}

test "BPL: branch taken when negative clear" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.p.negative = false;
    cpu.pc = 0x8000;
    cpu.operand_low = 0x0C;

    _ = bpl(&cpu, &bus);

    try testing.expectEqual(@as(u16, 0x800C), cpu.pc);
}

test "BVC: branch taken when overflow clear" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.p.overflow = false;
    cpu.pc = 0x8000;
    cpu.operand_low = 0x15;

    _ = bvc(&cpu, &bus);

    try testing.expectEqual(@as(u16, 0x8015), cpu.pc);
}

test "BVS: branch taken when overflow set" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.p.overflow = true;
    cpu.pc = 0x8000;
    cpu.operand_low = 0x20;

    _ = bvs(&cpu, &bus);

    try testing.expectEqual(@as(u16, 0x8020), cpu.pc);
}

test "branch: page crossing backward" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.p.zero = true;
    cpu.pc = 0x8010;
    cpu.operand_low = @as(u8, @bitCast(@as(i8, -32))); // -32, crosses to $7FF0

    const result = beq(&cpu, &bus);

    try testing.expectEqual(@as(u16, 0x7FF0), cpu.pc);
    try testing.expect(cpu.page_crossed);
    try testing.expect(!result); // Needs page fix
}
