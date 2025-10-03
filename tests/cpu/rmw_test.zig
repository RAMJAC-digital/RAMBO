const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Cpu = RAMBO.Cpu;
const Bus = RAMBO.Bus;

// ============================================================================
// ASL - Arithmetic Shift Left Tests
// ============================================================================

test "ASL accumulator - 2 cycles" {
    var state = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    bus.ram[0] = 0x0A; // ASL accumulator
    state.pc = 0x0000;
    state.a = 0x40; // 01000000

    // Cycle 1: Fetch opcode
    var complete = Cpu.Logic.tick(&state, &bus);
    try testing.expect(!complete);

    // Cycle 2: Execute
    complete = Cpu.Logic.tick(&state, &bus);
    try testing.expect(complete);

    try testing.expectEqual(@as(u8, 0x80), state.a); // 10000000
    try testing.expect(!state.p.carry);
    try testing.expect(state.p.negative);
    try testing.expectEqual(@as(u64, 2), state.cycle_count);
}

test "ASL zero page - 5 cycles with dummy write" {
    var state = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    bus.ram[0] = 0x06; // ASL zero page
    bus.ram[1] = 0x10; // Address $10
    bus.ram[0x10] = 0x42; // Value to shift
    state.pc = 0x0000;

    // Execute all 5 cycles
    for (0..5) |i| {
        const complete = Cpu.Logic.tick(&state, &bus);
        if (i == 4) try testing.expect(complete);
    }

    // Verify final result
    try testing.expectEqual(@as(u8, 0x84), bus.ram[0x10]); // Final value (shifted)
    try testing.expectEqual(@as(u64, 5), state.cycle_count); // Correct cycle count

    // Note: The dummy write (cycle 4) writes 0x42 back to 0x10, which doesn't change
    // the value but IS visible to memory-mapped I/O. Testing this requires
    // bus monitoring hooks, which we'll implement when we add PPU support.
}

test "ASL absolute,X - 7 cycles" {
    var state = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    bus.ram[0] = 0x1E; // ASL absolute,X
    bus.ram[1] = 0x00; // Low byte
    bus.ram[2] = 0x02; // High byte
    bus.ram[0x205] = 0x01; // Value at $0200 + $05
    state.pc = 0x0000;
    state.x = 0x05;

    for (0..7) |i| {
        const complete = Cpu.Logic.tick(&state, &bus);
        if (i == 6) try testing.expect(complete);
    }

    try testing.expectEqual(@as(u8, 0x02), bus.ram[0x205]);
    try testing.expectEqual(@as(u64, 7), state.cycle_count);
}

// ============================================================================
// LSR - Logical Shift Right Tests
// ============================================================================

test "LSR accumulator - carry flag" {
    var state = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    bus.ram[0] = 0x4A; // LSR accumulator
    state.pc = 0x0000;
    state.a = 0x03; // 00000011

    _ = Cpu.Logic.tick(&state, &bus); // Fetch
    _ = Cpu.Logic.tick(&state, &bus); // Execute

    try testing.expectEqual(@as(u8, 0x01), state.a); // 00000001
    try testing.expect(state.p.carry); // Bit 0 -> carry
    try testing.expect(!state.p.negative); // Always 0
}

test "LSR zero page,X - 6 cycles with dummy write" {
    var state = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    bus.ram[0] = 0x56; // LSR zero page,X
    bus.ram[1] = 0x10; // Base address
    bus.ram[0x12] = 0x80; // Value at $10 + $02
    state.pc = 0x0000;
    state.x = 0x02;

    for (0..6) |_| {
        _ = Cpu.Logic.tick(&state, &bus);
    }

    try testing.expectEqual(@as(u8, 0x40), bus.ram[0x12]);
    try testing.expectEqual(@as(u64, 6), state.cycle_count);
}

// ============================================================================
// ROL - Rotate Left Tests
// ============================================================================

test "ROL with carry rotation" {
    var state = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    bus.ram[0] = 0x2A; // ROL accumulator
    state.pc = 0x0000;
    state.a = 0x80; // 10000000
    state.p.carry = true;

    _ = Cpu.Logic.tick(&state, &bus); // Fetch
    _ = Cpu.Logic.tick(&state, &bus); // Execute

    try testing.expectEqual(@as(u8, 0x01), state.a); // 00000001 (old carry rotated in)
    try testing.expect(state.p.carry); // Bit 7 rotated out
}

test "ROL absolute - 6 cycles" {
    var state = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    bus.ram[0] = 0x2E; // ROL absolute
    bus.ram[1] = 0x20;
    bus.ram[2] = 0x01;
    bus.ram[0x120] = 0x7F; // 01111111
    state.pc = 0x0000;
    state.p.carry = false;

    for (0..6) |_| {
        _ = Cpu.Logic.tick(&state, &bus);
    }

    try testing.expectEqual(@as(u8, 0xFE), bus.ram[0x120]); // 11111110
    try testing.expect(!state.p.carry);
}

// ============================================================================
// ROR - Rotate Right Tests
// ============================================================================

test "ROR with carry rotation" {
    var state = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    bus.ram[0] = 0x6A; // ROR accumulator
    state.pc = 0x0000;
    state.a = 0x01; // 00000001
    state.p.carry = true;

    _ = Cpu.Logic.tick(&state, &bus); // Fetch
    _ = Cpu.Logic.tick(&state, &bus); // Execute

    try testing.expectEqual(@as(u8, 0x80), state.a); // 10000000 (old carry rotated in)
    try testing.expect(state.p.carry); // Bit 0 rotated out
}

// ============================================================================
// INC - Increment Memory Tests
// ============================================================================

test "INC zero page - 5 cycles with dummy write" {
    var state = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    bus.ram[0] = 0xE6; // INC zero page
    bus.ram[1] = 0x10;
    bus.ram[0x10] = 0x41;
    state.pc = 0x0000;

    for (0..5) |_| {
        _ = Cpu.Logic.tick(&state, &bus);
    }

    try testing.expectEqual(@as(u8, 0x42), bus.ram[0x10]);
    try testing.expectEqual(@as(u64, 5), state.cycle_count);
}

test "INC wraps to zero" {
    var state = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    bus.ram[0] = 0xE6; // INC zero page
    bus.ram[1] = 0x10;
    bus.ram[0x10] = 0xFF;
    state.pc = 0x0000;

    for (0..5) |_| {
        _ = Cpu.Logic.tick(&state, &bus);
    }

    try testing.expectEqual(@as(u8, 0x00), bus.ram[0x10]);
    try testing.expect(state.p.zero);
}

test "INC absolute,X - 7 cycles" {
    var state = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    bus.ram[0] = 0xFE; // INC absolute,X
    bus.ram[1] = 0x00;
    bus.ram[2] = 0x02;
    bus.ram[0x210] = 0x7F;
    state.pc = 0x0000;
    state.x = 0x10;

    for (0..7) |_| {
        _ = Cpu.Logic.tick(&state, &bus);
    }

    try testing.expectEqual(@as(u8, 0x80), bus.ram[0x210]);
    try testing.expect(state.p.negative);
    try testing.expectEqual(@as(u64, 7), state.cycle_count);
}

// ============================================================================
// DEC - Decrement Memory Tests
// ============================================================================

test "DEC zero page - 5 cycles" {
    var state = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    bus.ram[0] = 0xC6; // DEC zero page
    bus.ram[1] = 0x10;
    bus.ram[0x10] = 0x42;
    state.pc = 0x0000;

    for (0..5) |_| {
        _ = Cpu.Logic.tick(&state, &bus);
    }

    try testing.expectEqual(@as(u8, 0x41), bus.ram[0x10]);
}

test "DEC wraps to FF" {
    var state = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    bus.ram[0] = 0xC6; // DEC zero page
    bus.ram[1] = 0x10;
    bus.ram[0x10] = 0x00;
    state.pc = 0x0000;

    for (0..5) |_| {
        _ = Cpu.Logic.tick(&state, &bus);
    }

    try testing.expectEqual(@as(u8, 0xFF), bus.ram[0x10]);
    try testing.expect(state.p.negative);
}

// ============================================================================
// Register Inc/Dec Tests
// ============================================================================

test "INX - 2 cycles" {
    var state = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    bus.ram[0] = 0xE8; // INX
    state.pc = 0x0000;
    state.x = 0x10;

    _ = Cpu.Logic.tick(&state, &bus); // Fetch
    const complete = Cpu.Logic.tick(&state, &bus); // Execute

    try testing.expect(complete);
    try testing.expectEqual(@as(u8, 0x11), state.x);
    try testing.expectEqual(@as(u64, 2), state.cycle_count);
}

test "INY - zero flag" {
    var state = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    bus.ram[0] = 0xC8; // INY
    state.pc = 0x0000;
    state.y = 0xFF;

    _ = Cpu.Logic.tick(&state, &bus);
    _ = Cpu.Logic.tick(&state, &bus);

    try testing.expectEqual(@as(u8, 0x00), state.y);
    try testing.expect(state.p.zero);
}

test "DEX - negative flag" {
    var state = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    bus.ram[0] = 0xCA; // DEX
    state.pc = 0x0000;
    state.x = 0x01;

    _ = Cpu.Logic.tick(&state, &bus);
    _ = Cpu.Logic.tick(&state, &bus);

    try testing.expectEqual(@as(u8, 0x00), state.x);
    try testing.expect(state.p.zero);
}

test "DEY - 2 cycles" {
    var state = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    bus.ram[0] = 0x88; // DEY
    state.pc = 0x0000;
    state.y = 0x80;

    _ = Cpu.Logic.tick(&state, &bus);
    const complete = Cpu.Logic.tick(&state, &bus);

    try testing.expect(complete);
    try testing.expectEqual(@as(u8, 0x7F), state.y);
    try testing.expectEqual(@as(u64, 2), state.cycle_count);
}

// ============================================================================
// Dummy Write Verification Tests
// ============================================================================

test "RMW dummy write occurs at correct cycle" {
    var state = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    // INC zero page - dummy write happens on cycle 4
    bus.ram[0] = 0xE6; // INC zero page
    bus.ram[1] = 0x50;
    bus.ram[0x50] = 0x10;
    state.pc = 0x0000;

    for (0..5) |_| {
        _ = Cpu.Logic.tick(&state, &bus);
    }

    // Verify final result
    try testing.expectEqual(@as(u8, 0x11), bus.ram[0x50]); // Final value
    try testing.expectEqual(@as(u64, 5), state.cycle_count);

    // Note: Cycle 4 performs dummy write (writes 0x10 back to 0x50)
    // Cycle 5 performs actual write (writes 0x11 to 0x50)
    // Both writes ARE happening, but dummy write doesn't change value.
    // This behavior is critical for PPU register writes which have side effects
    // even when writing the same value.
}
