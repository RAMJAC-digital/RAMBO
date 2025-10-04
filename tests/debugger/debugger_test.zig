//! Debugger Integration Tests
//!
//! Comprehensive tests for debugger functionality including:
//! - Breakpoint system (execute, read, write, access)
//! - Watchpoint system (read, write, change)
//! - Step execution (instruction, over, out, scanline, frame)
//! - Execution history
//! - State inspection

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Debugger = RAMBO.Debugger.Debugger;
const DebugMode = RAMBO.Debugger.DebugMode;
const BreakpointType = RAMBO.Debugger.BreakpointType;

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;
const BusState = RAMBO.Bus.State.BusState;

// ============================================================================
// Test Fixtures
// ============================================================================

fn createTestState(config: *const Config) EmulationState {
    const bus = BusState.init();
    var state = EmulationState.init(config, bus);
    state.connectComponents();

    // Set distinctive state
    state.cpu.pc = 0x8000;
    state.cpu.sp = 0xFD;
    state.cpu.a = 0x42;
    state.ppu.scanline = 100;
    state.ppu.frame = 10;

    return state;
}

// ============================================================================
// Breakpoint Tests
// ============================================================================

test "Debugger: execute breakpoint triggers" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Add breakpoint at PC
    try debugger.addBreakpoint(0x8000, .execute);

    // Should break
    const should_break = try debugger.shouldBreak(&state);
    try testing.expect(should_break);
    try testing.expectEqual(DebugMode.paused, debugger.mode);
    try testing.expectEqual(@as(u64, 1), debugger.stats.breakpoints_hit);
}

test "Debugger: execute breakpoint with condition" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);
    state.cpu.a = 0x42;

    // Add conditional breakpoint
    try debugger.addBreakpoint(0x8000, .execute);
    debugger.breakpoints.items[0].condition = .{ .a_equals = 0x42 };

    // Should break (condition met)
    try testing.expect(try debugger.shouldBreak(&state));

    // Reset
    debugger.continue_();
    state.cpu.a = 0x00;

    // Should not break (condition not met)
    try testing.expect(!try debugger.shouldBreak(&state));
}

test "Debugger: read/write breakpoints" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Add read breakpoint
    try debugger.addBreakpoint(0x0100, .read);

    // Should break on read
    try testing.expect(try debugger.checkMemoryAccess(&state, 0x0100, 0x42, false));
    try testing.expectEqual(DebugMode.paused, debugger.mode);

    // Reset
    debugger.continue_();

    // Should not break on write
    try testing.expect(!try debugger.checkMemoryAccess(&state, 0x0100, 0x42, true));

    // Add write breakpoint
    try debugger.addBreakpoint(0x0200, .write);

    // Should break on write
    try testing.expect(try debugger.checkMemoryAccess(&state, 0x0200, 0x99, true));
}

test "Debugger: access breakpoint (read or write)" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Add access breakpoint
    try debugger.addBreakpoint(0x0300, .access);

    // Should break on read
    try testing.expect(try debugger.checkMemoryAccess(&state, 0x0300, 0x11, false));
    debugger.continue_();

    // Should break on write
    try testing.expect(try debugger.checkMemoryAccess(&state, 0x0300, 0x22, true));
}

test "Debugger: disabled breakpoint does not trigger" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Add and disable breakpoint
    try debugger.addBreakpoint(0x8000, .execute);
    try testing.expect(debugger.setBreakpointEnabled(0x8000, .execute, false));

    // Should not break
    try testing.expect(!try debugger.shouldBreak(&state));
}

test "Debugger: breakpoint hit count" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    try debugger.addBreakpoint(0x8000, .execute);

    // Hit breakpoint multiple times
    _ = try debugger.shouldBreak(&state);
    try testing.expectEqual(@as(u64, 1), debugger.breakpoints.items[0].hit_count);

    debugger.continue_();
    _ = try debugger.shouldBreak(&state);
    try testing.expectEqual(@as(u64, 2), debugger.breakpoints.items[0].hit_count);
}

// ============================================================================
// Watchpoint Tests
// ============================================================================

test "Debugger: write watchpoint" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Add write watchpoint
    try debugger.addWatchpoint(0x0000, 1, .write);

    // Should break on write
    try testing.expect(try debugger.checkMemoryAccess(&state, 0x0000, 0xFF, true));
    try testing.expectEqual(DebugMode.paused, debugger.mode);

    debugger.continue_();

    // Should not break on read
    try testing.expect(!try debugger.checkMemoryAccess(&state, 0x0000, 0xFF, false));
}

test "Debugger: read watchpoint" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Add read watchpoint
    try debugger.addWatchpoint(0x0000, 1, .read);

    // Should break on read
    try testing.expect(try debugger.checkMemoryAccess(&state, 0x0000, 0xFF, false));
}

test "Debugger: change watchpoint" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Add change watchpoint
    try debugger.addWatchpoint(0x0000, 1, .change);

    // First write sets old_value
    try testing.expect(try debugger.checkMemoryAccess(&state, 0x0000, 0x42, true));
    debugger.continue_();

    // Same value - should not break
    try testing.expect(!try debugger.checkMemoryAccess(&state, 0x0000, 0x42, true));

    // Different value - should break
    try testing.expect(try debugger.checkMemoryAccess(&state, 0x0000, 0x99, true));
}

test "Debugger: watchpoint range" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Add watchpoint covering 16 bytes
    try debugger.addWatchpoint(0x0100, 16, .write);

    // Should break within range
    try testing.expect(try debugger.checkMemoryAccess(&state, 0x0100, 0x00, true));
    debugger.continue_();
    try testing.expect(try debugger.checkMemoryAccess(&state, 0x010F, 0x00, true));
    debugger.continue_();

    // Should not break outside range
    try testing.expect(!try debugger.checkMemoryAccess(&state, 0x0110, 0x00, true));
}

// ============================================================================
// Step Execution Tests
// ============================================================================

test "Debugger: step instruction" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Enable step mode
    debugger.stepInstruction();
    try testing.expectEqual(DebugMode.step_instruction, debugger.mode);

    // Should break immediately
    try testing.expect(try debugger.shouldBreak(&state));
    try testing.expectEqual(DebugMode.paused, debugger.mode);
}

test "Debugger: step over (same stack level)" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);
    state.cpu.sp = 0xFD;

    debugger.stepOver(&state);
    try testing.expectEqual(DebugMode.step_over, debugger.mode);
    try testing.expectEqual(@as(u8, 0xFD), debugger.step_state.initial_sp);

    // Should not break yet
    try testing.expect(!try debugger.shouldBreak(&state));

    // Simulate JSR (decrement SP)
    state.cpu.sp = 0xFB;
    try testing.expect(!try debugger.shouldBreak(&state));

    // Simulate RTS (increment SP back)
    state.cpu.sp = 0xFD;
    try testing.expect(try debugger.shouldBreak(&state));
    try testing.expectEqual(DebugMode.paused, debugger.mode);
}

test "Debugger: step out (return from subroutine)" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);
    state.cpu.sp = 0xFB; // Inside subroutine

    debugger.stepOut(&state);
    try testing.expectEqual(DebugMode.step_out, debugger.mode);

    // Should not break at same level
    try testing.expect(!try debugger.shouldBreak(&state));

    // Should break when SP increases (RTS)
    state.cpu.sp = 0xFD;
    try testing.expect(try debugger.shouldBreak(&state));
}

test "Debugger: step scanline" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);
    state.ppu.scanline = 100;

    debugger.stepScanline(&state);
    try testing.expectEqual(DebugMode.step_scanline, debugger.mode);
    try testing.expectEqual(@as(u16, 101), debugger.step_state.target_scanline.?);

    // Should not break yet
    try testing.expect(!try debugger.shouldBreak(&state));

    // Should break on target scanline
    state.ppu.scanline = 101;
    try testing.expect(try debugger.shouldBreak(&state));
}

test "Debugger: step frame" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);
    state.ppu.frame = 10;

    debugger.stepFrame(&state);
    try testing.expectEqual(DebugMode.step_frame, debugger.mode);
    try testing.expectEqual(@as(u64, 11), debugger.step_state.target_frame.?);

    // Should not break yet
    try testing.expect(!try debugger.shouldBreak(&state));

    // Should break on target frame
    state.ppu.frame = 11;
    try testing.expect(try debugger.shouldBreak(&state));
}

// ============================================================================
// Execution History Tests
// ============================================================================

test "Debugger: capture and restore history" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);
    state.cpu.pc = 0x8000;
    state.cpu.a = 0x42;

    // Capture state
    try debugger.captureHistory(&state);
    try testing.expectEqual(@as(usize, 1), debugger.history.items.len);
    try testing.expectEqual(@as(u16, 0x8000), debugger.history.items[0].pc);

    // Modify state
    state.cpu.pc = 0x8100;
    state.cpu.a = 0x99;

    // Restore from history
    const restored = try debugger.restoreFromHistory(0, @as(?*RAMBO.Cartridge.NromCart, null));
    try testing.expectEqual(@as(u16, 0x8000), restored.cpu.pc);
    try testing.expectEqual(@as(u8, 0x42), restored.cpu.a);
}

test "Debugger: history circular buffer" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();
    debugger.history_max_size = 3;

    var state = createTestState(&config);

    // Capture 4 states (exceeds max)
    for (0..4) |i| {
        state.cpu.pc = @intCast(0x8000 + i);
        try debugger.captureHistory(&state);
    }

    // Should only have 3 entries
    try testing.expectEqual(@as(usize, 3), debugger.history.items.len);

    // First entry should be PC=0x8001 (oldest removed)
    try testing.expectEqual(@as(u16, 0x8001), debugger.history.items[0].pc);
}

test "Debugger: clear history" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    try debugger.captureHistory(&state);
    try testing.expectEqual(@as(usize, 1), debugger.history.items.len);

    debugger.clearHistory();
    try testing.expectEqual(@as(usize, 0), debugger.history.items.len);
}

// ============================================================================
// Statistics Tests
// ============================================================================

test "Debugger: statistics tracking" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Track instructions
    _ = try debugger.shouldBreak(&state);
    _ = try debugger.shouldBreak(&state);
    try testing.expectEqual(@as(u64, 2), debugger.stats.instructions_executed);

    // Track breakpoints
    try debugger.addBreakpoint(0x8000, .execute);
    _ = try debugger.shouldBreak(&state);
    try testing.expectEqual(@as(u64, 1), debugger.stats.breakpoints_hit);

    // Track watchpoints
    try debugger.addWatchpoint(0x0000, 1, .write);
    _ = try debugger.checkMemoryAccess(&state, 0x0000, 0xFF, true);
    try testing.expectEqual(@as(u64, 1), debugger.stats.watchpoints_hit);

    // Track snapshots
    try debugger.captureHistory(&state);
    try testing.expectEqual(@as(u64, 1), debugger.stats.snapshots_captured);
}

// ============================================================================
// Integration Tests
// ============================================================================

test "Debugger: combined breakpoints and watchpoints" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Add both types
    try debugger.addBreakpoint(0x8000, .execute);
    try debugger.addWatchpoint(0x0100, 1, .write);

    // Execute breakpoint should trigger
    try testing.expect(try debugger.shouldBreak(&state));
    debugger.continue_();

    // Watchpoint should trigger
    try testing.expect(try debugger.checkMemoryAccess(&state, 0x0100, 0x42, true));
}

test "Debugger: clear all breakpoints and watchpoints" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    // Add multiple
    try debugger.addBreakpoint(0x8000, .execute);
    try debugger.addBreakpoint(0x8100, .read);
    try debugger.addWatchpoint(0x0000, 1, .write);

    try testing.expectEqual(@as(usize, 2), debugger.breakpoints.items.len);
    try testing.expectEqual(@as(usize, 1), debugger.watchpoints.items.len);

    // Clear all
    debugger.clearBreakpoints();
    debugger.clearWatchpoints();

    try testing.expectEqual(@as(usize, 0), debugger.breakpoints.items.len);
    try testing.expectEqual(@as(usize, 0), debugger.watchpoints.items.len);
}

// ============================================================================
// State Manipulation Tests - CPU Registers
// ============================================================================

test "State Manipulation: set register A" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

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

    var state = createTestState(&config);

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

    var state = createTestState(&config);
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

    var state = createTestState(&config);

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

    var state = createTestState(&config);

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

    var state = createTestState(&config);

    // Set status register: C=1, Z=1, I=0, D=1, V=0, N=1
    // Binary: 10001011 = 0x8B
    debugger.setStatusRegister(&state, 0x8B);

    try testing.expect(state.cpu.p.carry);     // Bit 0
    try testing.expect(state.cpu.p.zero);      // Bit 1
    try testing.expect(!state.cpu.p.interrupt); // Bit 2
    try testing.expect(state.cpu.p.decimal);    // Bit 3
    try testing.expect(!state.cpu.p.overflow);  // Bit 6
    try testing.expect(state.cpu.p.negative);   // Bit 7
}

// ============================================================================
// State Manipulation Tests - Memory
// ============================================================================

test "State Manipulation: write single memory byte" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Write to zero page
    debugger.writeMemory(&state, 0x00, 0x42);
    try testing.expectEqual(@as(u8, 0x42), state.bus.read(0x00));

    // Write to RAM
    debugger.writeMemory(&state, 0x0200, 0x99);
    try testing.expectEqual(@as(u8, 0x99), state.bus.read(0x0200));

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

    var state = createTestState(&config);

    // Write range
    const data = [_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05 };
    debugger.writeMemoryRange(&state, 0x0100, &data);

    // Verify data written
    try testing.expectEqual(@as(u8, 0x01), state.bus.read(0x0100));
    try testing.expectEqual(@as(u8, 0x02), state.bus.read(0x0101));
    try testing.expectEqual(@as(u8, 0x03), state.bus.read(0x0102));
    try testing.expectEqual(@as(u8, 0x04), state.bus.read(0x0103));
    try testing.expectEqual(@as(u8, 0x05), state.bus.read(0x0104));

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

    var state = createTestState(&config);

    // Write some data first
    state.bus.write(0x0050, 0xAB);

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

    var state = createTestState(&config);

    // Write some data
    const write_data = [_]u8{ 0xAA, 0xBB, 0xCC, 0xDD };
    for (write_data, 0..) |byte, i| {
        state.bus.write(0x0200 + @as(u16, @intCast(i)), byte);
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

    var state = createTestState(&config);

    // Set scanline
    debugger.setPpuScanline(&state, 200);
    try testing.expectEqual(@as(u16, 200), state.ppu.scanline);

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

    var state = createTestState(&config);

    // Set frame counter
    debugger.setPpuFrame(&state, 1000);
    try testing.expectEqual(@as(u64, 1000), state.ppu.frame);

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

    var state = createTestState(&config);

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

    var state = createTestState(&config);

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

    var state = createTestState(&config);

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

// ============================================================================
// Phase 1.4: Side-Effect Isolation Tests
// ============================================================================

test "Memory Inspection: readMemory does not affect open bus" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Set open bus to known value
    state.bus.open_bus.update(0x42, 100);
    const original_value = state.bus.open_bus.value;
    const original_cycle = state.bus.open_bus.last_update_cycle;

    // Read memory via debugger (should NOT affect open bus)
    _ = debugger.readMemory(&state, 0x0200);

    // ✅ Verify open bus unchanged
    try testing.expectEqual(original_value, state.bus.open_bus.value);
    try testing.expectEqual(original_cycle, state.bus.open_bus.last_update_cycle);
}

test "Memory Inspection: readMemoryRange does not affect open bus" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Set open bus to known value
    state.bus.open_bus.update(0x99, 500);
    const original_value = state.bus.open_bus.value;
    const original_cycle = state.bus.open_bus.last_update_cycle;

    // Read memory range via debugger
    const buffer = try debugger.readMemoryRange(testing.allocator, &state, 0x0100, 16);
    defer testing.allocator.free(buffer);

    // ✅ Verify open bus unchanged after multiple reads
    try testing.expectEqual(original_value, state.bus.open_bus.value);
    try testing.expectEqual(original_cycle, state.bus.open_bus.last_update_cycle);
}

test "Memory Inspection: multiple reads preserve state" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Capture initial state
    state.bus.open_bus.update(0xAA, 1000);
    const initial_value = state.bus.open_bus.value;

    // Perform 1000 debugger reads
    for (0..1000) |i| {
        _ = debugger.readMemory(&state, @intCast(i % 256));
    }

    // ✅ Open bus should still be unchanged
    try testing.expectEqual(initial_value, state.bus.open_bus.value);
}

// ============================================================================
// Phase 2.5: RT-Safety Verification Tests
// ============================================================================

test "RT-Safety: shouldBreak() uses no heap allocation" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Add breakpoint
    try debugger.addBreakpoint(0x8000, .execute);
    state.cpu.pc = 0x8000;

    // Track allocations before shouldBreak()
    const allocations_before = testing.allocator_instance.total_requested_bytes;

    // Trigger breakpoint (should NOT allocate)
    _ = try debugger.shouldBreak(&state);

    const allocations_after = testing.allocator_instance.total_requested_bytes;

    // ✅ Verify zero allocations in hot path
    try testing.expectEqual(allocations_before, allocations_after);
}

test "RT-Safety: checkMemoryAccess() uses no heap allocation" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Add memory breakpoint and watchpoint
    try debugger.addBreakpoint(0x2000, .write);
    try debugger.addWatchpoint(0x2001, 1, .write);

    // Track allocations
    const allocations_before = testing.allocator_instance.total_requested_bytes;

    // Trigger memory breakpoint (should NOT allocate)
    _ = try debugger.checkMemoryAccess(&state, 0x2000, 0x42, true);

    const allocations_after = testing.allocator_instance.total_requested_bytes;

    // ✅ Verify zero allocations
    try testing.expectEqual(allocations_before, allocations_after);
}

test "RT-Safety: break reason accessible after trigger" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Initially no break reason
    try testing.expect(debugger.getBreakReason() == null);

    // Add and trigger breakpoint
    try debugger.addBreakpoint(0x8000, .execute);
    state.cpu.pc = 0x8000;
    _ = try debugger.shouldBreak(&state);

    // ✅ Verify break reason is set and accessible
    const reason = debugger.getBreakReason();
    try testing.expect(reason != null);
    try testing.expect(std.mem.containsAtLeast(u8, reason.?, 1, "Breakpoint"));

    // Verify it contains address
    try testing.expect(std.mem.containsAtLeast(u8, reason.?, 1, "8000"));
}
