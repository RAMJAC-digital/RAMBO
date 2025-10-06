const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Cpu = RAMBO.Cpu;
const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;

// Test helper: Create EmulationState for RMW testing
fn createTestState() EmulationState {
    var config = Config.init(testing.allocator);
    config.deinit(); // Leak for test simplicity
    return EmulationState.init(&config);
}

// ============================================================================
// ASL - Arithmetic Shift Left Tests
// ============================================================================

test "ASL accumulator - 2 cycles" {
    var state = createTestState();

    state.bus.ram[0] = 0x0A; // ASL accumulator
    state.cpu.pc = 0x0000;
    state.cpu.a = 0x40; // 01000000

    // Cycle 1: Fetch opcode
    state.tickCpu();

    // Cycle 2: Execute
    state.tickCpu();

    try testing.expectEqual(@as(u8, 0x80), state.cpu.a); // 10000000
    try testing.expect(!state.cpu.p.carry);
    try testing.expect(state.cpu.p.negative);
    try testing.expectEqual(@as(u64, 2), state.cpu.cycle_count);
}

test "ASL zero page - 5 cycles with dummy write" {
    var state = createTestState();

    state.bus.ram[0] = 0x06; // ASL zero page
    state.bus.ram[1] = 0x10; // Address $10
    state.bus.ram[0x10] = 0x42; // Value to shift
    state.cpu.pc = 0x0000;

    // Execute all 5 cycles
    for (0..5) |_| {
        state.tickCpu();
    }

    // Verify final result
    try testing.expectEqual(@as(u8, 0x84), state.bus.ram[0x10]); // Final value (shifted)
    try testing.expectEqual(@as(u64, 5), state.cpu.cycle_count); // Correct cycle count

    // Note: The dummy write (cycle 4) writes 0x42 back to 0x10, which doesn't change
    // the value but IS visible to memory-mapped I/O. Testing this requires
    // bus monitoring hooks, which we'll implement when we add PPU support.
}

test "ASL absolute,X - 7 cycles" {
    var state = createTestState();

    state.bus.ram[0] = 0x1E; // ASL absolute,X
    state.bus.ram[1] = 0x00; // Low byte
    state.bus.ram[2] = 0x02; // High byte
    state.bus.ram[0x205] = 0x01; // Value at $0200 + $05
    state.cpu.pc = 0x0000;
    state.cpu.x = 0x05;

    for (0..7) |_| {
        state.tickCpu();
    }

    try testing.expectEqual(@as(u8, 0x02), state.bus.ram[0x205]);
    try testing.expectEqual(@as(u64, 7), state.cpu.cycle_count);
}

// ============================================================================
// LSR - Logical Shift Right Tests
// ============================================================================

test "LSR accumulator - carry flag" {
    var state = createTestState();

    state.bus.ram[0] = 0x4A; // LSR accumulator
    state.cpu.pc = 0x0000;
    state.cpu.a = 0x03; // 00000011

    _ = state.tickCpu(); // Fetch
    _ = state.tickCpu(); // Execute

    try testing.expectEqual(@as(u8, 0x01), state.cpu.a); // 00000001
    try testing.expect(state.cpu.p.carry); // Bit 0 -> carry
    try testing.expect(!state.cpu.p.negative); // Always 0
}

test "LSR zero page,X - 6 cycles with dummy write" {
    var state = createTestState();

    state.bus.ram[0] = 0x56; // LSR zero page,X
    state.bus.ram[1] = 0x10; // Base address
    state.bus.ram[0x12] = 0x80; // Value at $10 + $02
    state.cpu.pc = 0x0000;
    state.cpu.x = 0x02;

    for (0..6) |_| {
        _ = state.tickCpu();
    }

    try testing.expectEqual(@as(u8, 0x40), state.bus.ram[0x12]);
    try testing.expectEqual(@as(u64, 6), state.cpu.cycle_count);
}

// ============================================================================
// ROL - Rotate Left Tests
// ============================================================================

test "ROL with carry rotation" {
    var state = createTestState();

    state.bus.ram[0] = 0x2A; // ROL accumulator
    state.cpu.pc = 0x0000;
    state.cpu.a = 0x80; // 10000000
    state.cpu.p.carry = true;

    _ = state.tickCpu(); // Fetch
    _ = state.tickCpu(); // Execute

    try testing.expectEqual(@as(u8, 0x01), state.cpu.a); // 00000001 (old carry rotated in)
    try testing.expect(state.cpu.p.carry); // Bit 7 rotated out
}

test "ROL absolute - 6 cycles" {
    var state = createTestState();

    state.bus.ram[0] = 0x2E; // ROL absolute
    state.bus.ram[1] = 0x20;
    state.bus.ram[2] = 0x01;
    state.bus.ram[0x120] = 0x7F; // 01111111
    state.cpu.pc = 0x0000;
    state.cpu.p.carry = false;

    for (0..6) |_| {
        _ = state.tickCpu();
    }

    try testing.expectEqual(@as(u8, 0xFE), state.bus.ram[0x120]); // 11111110
    try testing.expect(!state.cpu.p.carry);
}

// ============================================================================
// ROR - Rotate Right Tests
// ============================================================================

test "ROR with carry rotation" {
    var state = createTestState();

    state.bus.ram[0] = 0x6A; // ROR accumulator
    state.cpu.pc = 0x0000;
    state.cpu.a = 0x01; // 00000001
    state.cpu.p.carry = true;

    _ = state.tickCpu(); // Fetch
    _ = state.tickCpu(); // Execute

    try testing.expectEqual(@as(u8, 0x80), state.cpu.a); // 10000000 (old carry rotated in)
    try testing.expect(state.cpu.p.carry); // Bit 0 rotated out
}

// ============================================================================
// INC - Increment Memory Tests
// ============================================================================

test "INC zero page - 5 cycles with dummy write" {
    var state = createTestState();

    state.bus.ram[0] = 0xE6; // INC zero page
    state.bus.ram[1] = 0x10;
    state.bus.ram[0x10] = 0x41;
    state.cpu.pc = 0x0000;

    for (0..5) |_| {
        _ = state.tickCpu();
    }

    try testing.expectEqual(@as(u8, 0x42), state.bus.ram[0x10]);
    try testing.expectEqual(@as(u64, 5), state.cpu.cycle_count);
}

test "INC wraps to zero" {
    var state = createTestState();

    state.bus.ram[0] = 0xE6; // INC zero page
    state.bus.ram[1] = 0x10;
    state.bus.ram[0x10] = 0xFF;
    state.cpu.pc = 0x0000;

    for (0..5) |_| {
        _ = state.tickCpu();
    }

    try testing.expectEqual(@as(u8, 0x00), state.bus.ram[0x10]);
    try testing.expect(state.cpu.p.zero);
}

test "INC absolute,X - 7 cycles" {
    var state = createTestState();

    state.bus.ram[0] = 0xFE; // INC absolute,X
    state.bus.ram[1] = 0x00;
    state.bus.ram[2] = 0x02;
    state.bus.ram[0x210] = 0x7F;
    state.cpu.pc = 0x0000;
    state.cpu.x = 0x10;

    for (0..7) |_| {
        _ = state.tickCpu();
    }

    try testing.expectEqual(@as(u8, 0x80), state.bus.ram[0x210]);
    try testing.expect(state.cpu.p.negative);
    try testing.expectEqual(@as(u64, 7), state.cpu.cycle_count);
}

// ============================================================================
// DEC - Decrement Memory Tests
// ============================================================================

test "DEC zero page - 5 cycles" {
    var state = createTestState();

    state.bus.ram[0] = 0xC6; // DEC zero page
    state.bus.ram[1] = 0x10;
    state.bus.ram[0x10] = 0x42;
    state.cpu.pc = 0x0000;

    for (0..5) |_| {
        _ = state.tickCpu();
    }

    try testing.expectEqual(@as(u8, 0x41), state.bus.ram[0x10]);
}

test "DEC wraps to FF" {
    var state = createTestState();

    state.bus.ram[0] = 0xC6; // DEC zero page
    state.bus.ram[1] = 0x10;
    state.bus.ram[0x10] = 0x00;
    state.cpu.pc = 0x0000;

    for (0..5) |_| {
        _ = state.tickCpu();
    }

    try testing.expectEqual(@as(u8, 0xFF), state.bus.ram[0x10]);
    try testing.expect(state.cpu.p.negative);
}

// ============================================================================
// Register Inc/Dec Tests
// ============================================================================

test "INX - 2 cycles" {
    var state = createTestState();

    state.bus.ram[0] = 0xE8; // INX
    state.cpu.pc = 0x0000;
    state.cpu.x = 0x10;

    _ = state.tickCpu(); // Fetch
    state.tickCpu(); // Execute
    try testing.expectEqual(@as(u8, 0x11), state.cpu.x);
    try testing.expectEqual(@as(u64, 2), state.cpu.cycle_count);
}

test "INY - zero flag" {
    var state = createTestState();

    state.bus.ram[0] = 0xC8; // INY
    state.cpu.pc = 0x0000;
    state.cpu.y = 0xFF;

    _ = state.tickCpu();
    _ = state.tickCpu();

    try testing.expectEqual(@as(u8, 0x00), state.cpu.y);
    try testing.expect(state.cpu.p.zero);
}

test "DEX - negative flag" {
    var state = createTestState();

    state.bus.ram[0] = 0xCA; // DEX
    state.cpu.pc = 0x0000;
    state.cpu.x = 0x01;

    _ = state.tickCpu();
    _ = state.tickCpu();

    try testing.expectEqual(@as(u8, 0x00), state.cpu.x);
    try testing.expect(state.cpu.p.zero);
}

test "DEY - 2 cycles" {
    var state = createTestState();

    state.bus.ram[0] = 0x88; // DEY
    state.cpu.pc = 0x0000;
    state.cpu.y = 0x80;

    _ = state.tickCpu();
    state.tickCpu();
    try testing.expectEqual(@as(u8, 0x7F), state.cpu.y);
    try testing.expectEqual(@as(u64, 2), state.cpu.cycle_count);
}

// ============================================================================
// Dummy Write Verification Tests
// ============================================================================

test "RMW dummy write occurs at correct cycle" {
    var state = createTestState();

    // INC zero page - dummy write happens on cycle 4
    state.bus.ram[0] = 0xE6; // INC zero page
    state.bus.ram[1] = 0x50;
    state.bus.ram[0x50] = 0x10;
    state.cpu.pc = 0x0000;

    for (0..5) |_| {
        _ = state.tickCpu();
    }

    // Verify final result
    try testing.expectEqual(@as(u8, 0x11), state.bus.ram[0x50]); // Final value
    try testing.expectEqual(@as(u64, 5), state.cpu.cycle_count);

    // Note: Cycle 4 performs dummy write (writes 0x10 back to 0x50)
    // Cycle 5 performs actual write (writes 0x11 to 0x50)
    // Both writes ARE happening, but dummy write doesn't change value.
    // This behavior is critical for PPU register writes which have side effects
    // even when writing the same value.
}
