//! Stack Instructions
//!
//! PHA - Push Accumulator
//! PHP - Push Processor Status
//! PLA - Pull Accumulator
//! PLP - Pull Processor Status

const std = @import("std");
const Cpu = @import("../Cpu.zig").Cpu;
const Bus = @import("../../bus/Bus.zig").Bus;

/// PHA - Push Accumulator
/// Push A onto stack
/// No flags affected
///
/// 3 cycles total
pub fn pha(cpu: *Cpu, bus: *Bus) bool {
    cpu.push(bus, cpu.a);
    return true;
}

/// PHP - Push Processor Status
/// Push P onto stack with B flag set
/// No flags affected
///
/// 3 cycles total
pub fn php(cpu: *Cpu, bus: *Bus) bool {
    var status = cpu.p.toByte();
    status |= 0x10; // Set B flag (bit 4)
    cpu.push(bus, status);
    return true;
}

/// PLA - Pull Accumulator
/// Pull A from stack
/// Flags: N, Z
///
/// 4 cycles total
pub fn pla(cpu: *Cpu, bus: *Bus) bool {
    cpu.a = cpu.pull(bus);
    cpu.p.updateZN(cpu.a);
    return true;
}

/// PLP - Pull Processor Status
/// Pull P from stack
/// Flags: All (restored from stack)
///
/// 4 cycles total
pub fn plp(cpu: *Cpu, bus: *Bus) bool {
    const status = cpu.pull(bus);
    cpu.p = @TypeOf(cpu.p).fromByte(status);
    return true;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "PHA: push accumulator" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.sp = 0xFF;
    cpu.a = 0x42;

    _ = pha(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x42), bus.read(0x01FF));
    try testing.expectEqual(@as(u8, 0xFE), cpu.sp);
}

test "PHP: push status with B flag" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.sp = 0xFF;
    cpu.p.carry = true;
    cpu.p.zero = true;
    cpu.p.negative = true;

    _ = php(&cpu, &bus);

    const status = bus.read(0x01FF);
    try testing.expectEqual(@as(u8, 1), (status >> 0) & 1); // Carry
    try testing.expectEqual(@as(u8, 1), (status >> 1) & 1); // Zero
    try testing.expectEqual(@as(u8, 1), (status >> 4) & 1); // B flag set
    try testing.expectEqual(@as(u8, 1), (status >> 7) & 1); // Negative
    try testing.expectEqual(@as(u8, 0xFE), cpu.sp);
}

test "PLA: pull accumulator and update flags" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.sp = 0xFE;
    bus.write(0x01FF, 0x80);

    _ = pla(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x80), cpu.a);
    try testing.expect(cpu.p.negative); // 0x80 has bit 7 set
    try testing.expect(!cpu.p.zero);
    try testing.expectEqual(@as(u8, 0xFF), cpu.sp);
}

test "PLA: zero flag" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.sp = 0xFE;
    bus.write(0x01FF, 0x00);

    _ = pla(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0x00), cpu.a);
    try testing.expect(cpu.p.zero);
    try testing.expect(!cpu.p.negative);
}

test "PLP: pull status flags" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.sp = 0xFE;
    bus.write(0x01FF, 0b11000011); // N=1, V=1, Z=1, C=1

    _ = plp(&cpu, &bus);

    try testing.expect(cpu.p.carry);
    try testing.expect(cpu.p.zero);
    try testing.expect(cpu.p.overflow);
    try testing.expect(cpu.p.negative);
    try testing.expectEqual(@as(u8, 0xFF), cpu.sp);
}

test "PHA and PLA: round trip" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.sp = 0xFF;
    cpu.a = 0x55;

    // Push
    _ = pha(&cpu, &bus);
    try testing.expectEqual(@as(u8, 0xFE), cpu.sp);

    // Modify A
    cpu.a = 0x00;

    // Pull
    _ = pla(&cpu, &bus);
    try testing.expectEqual(@as(u8, 0x55), cpu.a);
    try testing.expectEqual(@as(u8, 0xFF), cpu.sp); // Stack balanced
}

test "PHP and PLP: round trip" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.sp = 0xFF;
    cpu.p.carry = true;
    cpu.p.overflow = true;

    // Push
    _ = php(&cpu, &bus);

    // Modify flags
    cpu.p.carry = false;
    cpu.p.overflow = false;
    cpu.p.zero = true;

    // Pull
    _ = plp(&cpu, &bus);
    try testing.expect(cpu.p.carry); // Restored
    try testing.expect(cpu.p.overflow); // Restored
    try testing.expect(!cpu.p.zero); // Was false when pushed
    try testing.expectEqual(@as(u8, 0xFF), cpu.sp); // Stack balanced
}
