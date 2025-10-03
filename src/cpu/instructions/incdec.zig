const std = @import("std");
const Cpu = @import("../Cpu.zig").Cpu;
const Bus = @import("../../bus/Bus.zig").Bus;

// ============================================================================
// INC - Increment Memory
// ============================================================================

/// INC - Increment memory by one
/// Flags: N Z
pub fn inc(cpu: *Cpu, bus: *Bus) bool {
    // Value already in temp_value from RMW read
    const value = cpu.temp_value +% 1;
    cpu.p.updateZN(value);

    // Write modified value
    bus.write(cpu.effective_address, value);
    return true;
}

// ============================================================================
// DEC - Decrement Memory
// ============================================================================

/// DEC - Decrement memory by one
/// Flags: N Z
pub fn dec(cpu: *Cpu, bus: *Bus) bool {
    // Value already in temp_value from RMW read
    const value = cpu.temp_value -% 1;
    cpu.p.updateZN(value);

    // Write modified value
    bus.write(cpu.effective_address, value);
    return true;
}

// ============================================================================
// INX - Increment X Register
// ============================================================================

/// INX - Increment X register by one
/// Flags: N Z
pub fn inx(cpu: *Cpu, bus: *Bus) bool {
    _ = bus;
    cpu.x +%= 1;
    cpu.p.updateZN(cpu.x);
    return true;
}

// ============================================================================
// INY - Increment Y Register
// ============================================================================

/// INY - Increment Y register by one
/// Flags: N Z
pub fn iny(cpu: *Cpu, bus: *Bus) bool {
    _ = bus;
    cpu.y +%= 1;
    cpu.p.updateZN(cpu.y);
    return true;
}

// ============================================================================
// DEX - Decrement X Register
// ============================================================================

/// DEX - Decrement X register by one
/// Flags: N Z
pub fn dex(cpu: *Cpu, bus: *Bus) bool {
    _ = bus;
    cpu.x -%= 1;
    cpu.p.updateZN(cpu.x);
    return true;
}

// ============================================================================
// DEY - Decrement Y Register
// ============================================================================

/// DEY - Decrement Y register by one
/// Flags: N Z
pub fn dey(cpu: *Cpu, bus: *Bus) bool {
    _ = bus;
    cpu.y -%= 1;
    cpu.p.updateZN(cpu.y);
    return true;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "INC - basic increment" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.temp_value = 0x42;
    cpu.effective_address = 0x0010;

    const complete = inc(&cpu, &bus);
    try testing.expect(complete);
    try testing.expectEqual(@as(u8, 0x43), bus.ram[0x10]);
    try testing.expect(!cpu.p.zero);
    try testing.expect(!cpu.p.negative);
}

test "INC - zero flag" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.temp_value = 0xFF;
    cpu.effective_address = 0x0010;

    _ = inc(&cpu, &bus);
    try testing.expectEqual(@as(u8, 0x00), bus.ram[0x10]);
    try testing.expect(cpu.p.zero);
}

test "DEC - basic decrement" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.temp_value = 0x42;
    cpu.effective_address = 0x0010;

    _ = dec(&cpu, &bus);
    try testing.expectEqual(@as(u8, 0x41), bus.ram[0x10]);
    try testing.expect(!cpu.p.zero);
}

test "INX - increment X" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.x = 0x10;
    _ = inx(&cpu, &bus);
    try testing.expectEqual(@as(u8, 0x11), cpu.x);
}

test "DEX - decrement X with wrap" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.x = 0x00;
    _ = dex(&cpu, &bus);
    try testing.expectEqual(@as(u8, 0xFF), cpu.x);
    try testing.expect(cpu.p.negative);
}

test "INY - increment Y" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.y = 0xFE;
    _ = iny(&cpu, &bus);
    try testing.expectEqual(@as(u8, 0xFF), cpu.y);
    try testing.expect(cpu.p.negative);
}

test "DEY - decrement Y with zero" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.y = 0x01;
    _ = dey(&cpu, &bus);
    try testing.expectEqual(@as(u8, 0x00), cpu.y);
    try testing.expect(cpu.p.zero);
}
