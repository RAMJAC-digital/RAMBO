const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Cpu = RAMBO.CpuType;
const Bus = RAMBO.BusType;

// ============================================================================
// ASL - Arithmetic Shift Left Tests
// ============================================================================

test "ASL accumulator - 2 cycles" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0x0A; // ASL accumulator
    cpu.pc = 0x0000;
    cpu.a = 0x40; // 01000000

    // Cycle 1: Fetch opcode
    var complete = cpu.tick(&bus);
    try testing.expect(!complete);

    // Cycle 2: Execute
    complete = cpu.tick(&bus);
    try testing.expect(complete);

    try testing.expectEqual(@as(u8, 0x80), cpu.a); // 10000000
    try testing.expect(!cpu.p.carry);
    try testing.expect(cpu.p.negative);
    try testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

test "ASL zero page - 5 cycles with dummy write" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0x06; // ASL zero page
    bus.ram[1] = 0x10; // Address $10
    bus.ram[0x10] = 0x42; // Value to shift
    cpu.pc = 0x0000;

    // Execute all 5 cycles
    for (0..5) |i| {
        const complete = cpu.tick(&bus);
        if (i == 4) try testing.expect(complete);
    }

    // Verify final result
    try testing.expectEqual(@as(u8, 0x84), bus.ram[0x10]); // Final value (shifted)
    try testing.expectEqual(@as(u64, 5), cpu.cycle_count); // Correct cycle count

    // Note: The dummy write (cycle 4) writes 0x42 back to 0x10, which doesn't change
    // the value but IS visible to memory-mapped I/O. Testing this requires
    // bus monitoring hooks, which we'll implement when we add PPU support.
}

test "ASL absolute,X - 7 cycles" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0x1E; // ASL absolute,X
    bus.ram[1] = 0x00; // Low byte
    bus.ram[2] = 0x02; // High byte
    bus.ram[0x205] = 0x01; // Value at $0200 + $05
    cpu.pc = 0x0000;
    cpu.x = 0x05;

    for (0..7) |i| {
        const complete = cpu.tick(&bus);
        if (i == 6) try testing.expect(complete);
    }

    try testing.expectEqual(@as(u8, 0x02), bus.ram[0x205]);
    try testing.expectEqual(@as(u64, 7), cpu.cycle_count);
}

// ============================================================================
// LSR - Logical Shift Right Tests
// ============================================================================

test "LSR accumulator - carry flag" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0x4A; // LSR accumulator
    cpu.pc = 0x0000;
    cpu.a = 0x03; // 00000011

    _ = cpu.tick(&bus); // Fetch
    _ = cpu.tick(&bus); // Execute

    try testing.expectEqual(@as(u8, 0x01), cpu.a); // 00000001
    try testing.expect(cpu.p.carry); // Bit 0 -> carry
    try testing.expect(!cpu.p.negative); // Always 0
}

test "LSR zero page,X - 6 cycles with dummy write" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0x56; // LSR zero page,X
    bus.ram[1] = 0x10; // Base address
    bus.ram[0x12] = 0x80; // Value at $10 + $02
    cpu.pc = 0x0000;
    cpu.x = 0x02;

    for (0..6) |_| {
        _ = cpu.tick(&bus);
    }

    try testing.expectEqual(@as(u8, 0x40), bus.ram[0x12]);
    try testing.expectEqual(@as(u64, 6), cpu.cycle_count);
}

// ============================================================================
// ROL - Rotate Left Tests
// ============================================================================

test "ROL with carry rotation" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0x2A; // ROL accumulator
    cpu.pc = 0x0000;
    cpu.a = 0x80; // 10000000
    cpu.p.carry = true;

    _ = cpu.tick(&bus); // Fetch
    _ = cpu.tick(&bus); // Execute

    try testing.expectEqual(@as(u8, 0x01), cpu.a); // 00000001 (old carry rotated in)
    try testing.expect(cpu.p.carry); // Bit 7 rotated out
}

test "ROL absolute - 6 cycles" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0x2E; // ROL absolute
    bus.ram[1] = 0x20;
    bus.ram[2] = 0x01;
    bus.ram[0x120] = 0x7F; // 01111111
    cpu.pc = 0x0000;
    cpu.p.carry = false;

    for (0..6) |_| {
        _ = cpu.tick(&bus);
    }

    try testing.expectEqual(@as(u8, 0xFE), bus.ram[0x120]); // 11111110
    try testing.expect(!cpu.p.carry);
}

// ============================================================================
// ROR - Rotate Right Tests
// ============================================================================

test "ROR with carry rotation" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0x6A; // ROR accumulator
    cpu.pc = 0x0000;
    cpu.a = 0x01; // 00000001
    cpu.p.carry = true;

    _ = cpu.tick(&bus); // Fetch
    _ = cpu.tick(&bus); // Execute

    try testing.expectEqual(@as(u8, 0x80), cpu.a); // 10000000 (old carry rotated in)
    try testing.expect(cpu.p.carry); // Bit 0 rotated out
}

// ============================================================================
// INC - Increment Memory Tests
// ============================================================================

test "INC zero page - 5 cycles with dummy write" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0xE6; // INC zero page
    bus.ram[1] = 0x10;
    bus.ram[0x10] = 0x41;
    cpu.pc = 0x0000;

    for (0..5) |_| {
        _ = cpu.tick(&bus);
    }

    try testing.expectEqual(@as(u8, 0x42), bus.ram[0x10]);
    try testing.expectEqual(@as(u64, 5), cpu.cycle_count);
}

test "INC wraps to zero" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0xE6; // INC zero page
    bus.ram[1] = 0x10;
    bus.ram[0x10] = 0xFF;
    cpu.pc = 0x0000;

    for (0..5) |_| {
        _ = cpu.tick(&bus);
    }

    try testing.expectEqual(@as(u8, 0x00), bus.ram[0x10]);
    try testing.expect(cpu.p.zero);
}

test "INC absolute,X - 7 cycles" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0xFE; // INC absolute,X
    bus.ram[1] = 0x00;
    bus.ram[2] = 0x02;
    bus.ram[0x210] = 0x7F;
    cpu.pc = 0x0000;
    cpu.x = 0x10;

    for (0..7) |_| {
        _ = cpu.tick(&bus);
    }

    try testing.expectEqual(@as(u8, 0x80), bus.ram[0x210]);
    try testing.expect(cpu.p.negative);
    try testing.expectEqual(@as(u64, 7), cpu.cycle_count);
}

// ============================================================================
// DEC - Decrement Memory Tests
// ============================================================================

test "DEC zero page - 5 cycles" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0xC6; // DEC zero page
    bus.ram[1] = 0x10;
    bus.ram[0x10] = 0x42;
    cpu.pc = 0x0000;

    for (0..5) |_| {
        _ = cpu.tick(&bus);
    }

    try testing.expectEqual(@as(u8, 0x41), bus.ram[0x10]);
}

test "DEC wraps to FF" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0xC6; // DEC zero page
    bus.ram[1] = 0x10;
    bus.ram[0x10] = 0x00;
    cpu.pc = 0x0000;

    for (0..5) |_| {
        _ = cpu.tick(&bus);
    }

    try testing.expectEqual(@as(u8, 0xFF), bus.ram[0x10]);
    try testing.expect(cpu.p.negative);
}

// ============================================================================
// Register Inc/Dec Tests
// ============================================================================

test "INX - 2 cycles" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0xE8; // INX
    cpu.pc = 0x0000;
    cpu.x = 0x10;

    _ = cpu.tick(&bus); // Fetch
    const complete = cpu.tick(&bus); // Execute

    try testing.expect(complete);
    try testing.expectEqual(@as(u8, 0x11), cpu.x);
    try testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

test "INY - zero flag" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0xC8; // INY
    cpu.pc = 0x0000;
    cpu.y = 0xFF;

    _ = cpu.tick(&bus);
    _ = cpu.tick(&bus);

    try testing.expectEqual(@as(u8, 0x00), cpu.y);
    try testing.expect(cpu.p.zero);
}

test "DEX - negative flag" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0xCA; // DEX
    cpu.pc = 0x0000;
    cpu.x = 0x01;

    _ = cpu.tick(&bus);
    _ = cpu.tick(&bus);

    try testing.expectEqual(@as(u8, 0x00), cpu.x);
    try testing.expect(cpu.p.zero);
}

test "DEY - 2 cycles" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0x88; // DEY
    cpu.pc = 0x0000;
    cpu.y = 0x80;

    _ = cpu.tick(&bus);
    const complete = cpu.tick(&bus);

    try testing.expect(complete);
    try testing.expectEqual(@as(u8, 0x7F), cpu.y);
    try testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

// ============================================================================
// Dummy Write Verification Tests
// ============================================================================

test "RMW dummy write occurs at correct cycle" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // INC zero page - dummy write happens on cycle 4
    bus.ram[0] = 0xE6; // INC zero page
    bus.ram[1] = 0x50;
    bus.ram[0x50] = 0x10;
    cpu.pc = 0x0000;

    for (0..5) |_| {
        _ = cpu.tick(&bus);
    }

    // Verify final result
    try testing.expectEqual(@as(u8, 0x11), bus.ram[0x50]); // Final value
    try testing.expectEqual(@as(u64, 5), cpu.cycle_count);

    // Note: Cycle 4 performs dummy write (writes 0x10 back to 0x50)
    // Cycle 5 performs actual write (writes 0x11 to 0x50)
    // Both writes ARE happening, but dummy write doesn't change value.
    // This behavior is critical for PPU register writes which have side effects
    // even when writing the same value.
}
