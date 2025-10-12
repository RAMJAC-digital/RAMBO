//! Debugger State Manipulation Tests
//!
//! Tests for debugger state manipulation:
//! - CPU register manipulation (A, X, Y, SP, PC, P)
//! - Memory read/write (single byte and ranges)
//! - PPU state manipulation (scanline, frame counter)
//! - Modification history logging

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const test_fixtures = @import("test_fixtures.zig");

const Debugger = RAMBO.Debugger.Debugger;
const Config = RAMBO.Config.Config;

// ============================================================================
// State Manipulation Tests - CPU Registers
// ============================================================================

test "State Manipulation: set register A" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Set accumulator
    debugger.setRegisterA(&state, 0x42);
    try testing.expectEqual(@as(u8, 0x42), state.cpu.a);

    // Verify modification logged
    const mods = debugger.getModifications();
    try testing.expectEqual(@as(usize, 1), mods.len);
    try testing.expectEqual(@as(u8, 0x42), mods[0].register_a);
}

test "State Manipulation: set register X and Y" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Set X register
    debugger.setRegisterX(&state, 0x11);
    try testing.expectEqual(@as(u8, 0x11), state.cpu.x);

    // Set Y register
    debugger.setRegisterY(&state, 0x22);
    try testing.expectEqual(@as(u8, 0x22), state.cpu.y);

    // Verify modifications logged
    const mods = debugger.getModifications();
    try testing.expectEqual(@as(usize, 2), mods.len);
}

test "State Manipulation: set stack pointer" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);
    const original_sp = state.cpu.sp;

    // Set stack pointer
    debugger.setStackPointer(&state, 0xFF);
    try testing.expectEqual(@as(u8, 0xFF), state.cpu.sp);
    try testing.expect(state.cpu.sp != original_sp);
}

test "State Manipulation: set program counter" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Set program counter
    debugger.setProgramCounter(&state, 0xC000);
    try testing.expectEqual(@as(u16, 0xC000), state.cpu.pc);

    // Verify modification logged
    const mods = debugger.getModifications();
    try testing.expectEqual(@as(usize, 1), mods.len);
    try testing.expectEqual(@as(u16, 0xC000), mods[0].program_counter);
}

test "State Manipulation: set individual status flags" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Set carry flag
    debugger.setStatusFlag(&state, .carry, true);
    try testing.expect(state.cpu.p.carry);

    // Set zero flag
    debugger.setStatusFlag(&state, .zero, true);
    try testing.expect(state.cpu.p.zero);

    // Clear negative flag
    debugger.setStatusFlag(&state, .negative, false);
    try testing.expect(!state.cpu.p.negative);

    // Verify modifications logged
    const mods = debugger.getModifications();
    try testing.expectEqual(@as(usize, 3), mods.len);
}

test "State Manipulation: set complete status register" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Set status register: C=1, Z=1, I=0, D=1, V=0, N=1
    // Binary: 10001011 = 0x8B
    debugger.setStatusRegister(&state, 0x8B);

    try testing.expect(state.cpu.p.carry); // Bit 0
    try testing.expect(state.cpu.p.zero); // Bit 1
    try testing.expect(!state.cpu.p.interrupt); // Bit 2
    try testing.expect(state.cpu.p.decimal); // Bit 3
    try testing.expect(!state.cpu.p.overflow); // Bit 6
    try testing.expect(state.cpu.p.negative); // Bit 7
}

// ============================================================================
// State Manipulation Tests - Memory
// ============================================================================

test "State Manipulation: write single memory byte" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Write to zero page
    debugger.writeMemory(&state, 0x00, 0x42);
    try testing.expectEqual(@as(u8, 0x42), state.busRead(0x00));

    // Write to RAM
    debugger.writeMemory(&state, 0x0200, 0x99);
    try testing.expectEqual(@as(u8, 0x99), state.busRead(0x0200));

    // Verify modifications logged
    const mods = debugger.getModifications();
    try testing.expectEqual(@as(usize, 2), mods.len);
    try testing.expectEqual(@as(u16, 0x00), mods[0].memory_write.address);
    try testing.expectEqual(@as(u8, 0x42), mods[0].memory_write.value);
}

test "State Manipulation: write memory range" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Write range
    const data = [_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05 };
    debugger.writeMemoryRange(&state, 0x0100, &data);

    // Verify data written
    try testing.expectEqual(@as(u8, 0x01), state.busRead(0x0100));
    try testing.expectEqual(@as(u8, 0x02), state.busRead(0x0101));
    try testing.expectEqual(@as(u8, 0x03), state.busRead(0x0102));
    try testing.expectEqual(@as(u8, 0x04), state.busRead(0x0103));
    try testing.expectEqual(@as(u8, 0x05), state.busRead(0x0104));

    // Verify modification logged
    const mods = debugger.getModifications();
    try testing.expectEqual(@as(usize, 1), mods.len);
    try testing.expectEqual(@as(u16, 0x0100), mods[0].memory_range.start);
    try testing.expectEqual(@as(u16, 5), mods[0].memory_range.length);
}

test "State Manipulation: read memory for inspection" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Write some data first
    state.busWrite(0x0050, 0xAB);

    // Read it back via debugger
    const value = debugger.readMemory(&state, 0x0050);
    try testing.expectEqual(@as(u8, 0xAB), value);

    // Reading should NOT create modifications
    const mods = debugger.getModifications();
    try testing.expectEqual(@as(usize, 0), mods.len);
}

test "State Manipulation: read memory range" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Write some data
    const write_data = [_]u8{ 0xAA, 0xBB, 0xCC, 0xDD };
    for (write_data, 0..) |byte, i| {
        state.busWrite(0x0200 + @as(u16, @intCast(i)), byte);
    }

    // Read it back
    const read_data = try debugger.readMemoryRange(
        testing.allocator,
        &state,
        0x0200,
        4,
    );
    defer testing.allocator.free(read_data);

    try testing.expectEqualSlices(u8, &write_data, read_data);
}

// ============================================================================
// State Manipulation Tests - PPU
// ============================================================================

test "State Manipulation: set PPU scanline" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Set scanline
    debugger.setPpuScanline(&state, 200);
    try testing.expectEqual(@as(u16, 200), state.clock.scanline());

    // Verify modification logged
    const mods = debugger.getModifications();
    try testing.expectEqual(@as(usize, 1), mods.len);
    try testing.expectEqual(@as(u16, 200), mods[0].ppu_scanline);
}

test "State Manipulation: set PPU frame counter" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Set frame counter
    debugger.setPpuFrame(&state, 1000);
    try testing.expectEqual(@as(u64, 1000), state.clock.frame());

    // Verify modification logged
    const mods = debugger.getModifications();
    try testing.expectEqual(@as(usize, 1), mods.len);
    try testing.expectEqual(@as(u64, 1000), mods[0].ppu_frame);
}

// ============================================================================
// Modification Logging Tests
// ============================================================================

test "State Manipulation: track multiple modifications" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Make several modifications
    debugger.setRegisterA(&state, 0x11);
    debugger.setRegisterX(&state, 0x22);
    debugger.setProgramCounter(&state, 0x9000);
    debugger.writeMemory(&state, 0x0100, 0x33);
    debugger.setPpuScanline(&state, 150);

    // Verify all logged
    const mods = debugger.getModifications();
    try testing.expectEqual(@as(usize, 5), mods.len);

    // Verify order
    try testing.expectEqual(@as(u8, 0x11), mods[0].register_a);
    try testing.expectEqual(@as(u8, 0x22), mods[1].register_x);
    try testing.expectEqual(@as(u16, 0x9000), mods[2].program_counter);
    try testing.expectEqual(@as(u16, 0x0100), mods[3].memory_write.address);
    try testing.expectEqual(@as(u16, 150), mods[4].ppu_scanline);
}

test "State Manipulation: clear modification history" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Make modifications
    debugger.setRegisterA(&state, 0x42);
    debugger.setRegisterX(&state, 0x43);
    debugger.setRegisterY(&state, 0x44);

    // Verify logged
    try testing.expectEqual(@as(usize, 3), debugger.getModifications().len);

    // Clear history
    debugger.clearModifications();
    try testing.expectEqual(@as(usize, 0), debugger.getModifications().len);

    // New modifications should work
    debugger.setProgramCounter(&state, 0x8000);
    try testing.expectEqual(@as(usize, 1), debugger.getModifications().len);
}

test "State Manipulation: modification history persists across operations" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Make modification
    debugger.setRegisterA(&state, 0x11);
    try testing.expectEqual(@as(usize, 1), debugger.getModifications().len);

    // Add breakpoint (unrelated operation)
    try debugger.addBreakpoint(0x8000, .execute);

    // Modification history should persist
    try testing.expectEqual(@as(usize, 1), debugger.getModifications().len);

    // Add more modifications
    debugger.setRegisterX(&state, 0x22);
    try testing.expectEqual(@as(usize, 2), debugger.getModifications().len);
}
