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

// ============================================================================
// Test Fixtures
// ============================================================================

fn createTestState(config: *const Config) EmulationState {
    var state = EmulationState.init(config);

    // Set distinctive state
    state.cpu.pc = 0x8000;
    state.cpu.sp = 0xFD;
    state.cpu.a = 0x42;
    state.clock.ppu_cycles = (10 * 89342) + (100 * 341); // Frame 10, scanline 100

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
    // Find the breakpoint we just added and set condition
    for (debugger.breakpoints[0..256]) |*maybe_bp| {
        if (maybe_bp.*) |*bp| {
            bp.condition = .{ .a_equals = 0x42 };
            break;
        }
    }

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
    // Find the breakpoint and check hit count
    var hit_count: u64 = 0;
    for (debugger.breakpoints[0..256]) |maybe_bp| {
        if (maybe_bp) |bp| {
            hit_count = bp.hit_count;
            break;
        }
    }
    try testing.expectEqual(@as(u64, 1), hit_count);

    debugger.continue_();
    _ = try debugger.shouldBreak(&state);
    for (debugger.breakpoints[0..256]) |maybe_bp| {
        if (maybe_bp) |bp| {
            hit_count = bp.hit_count;
            break;
        }
    }
    try testing.expectEqual(@as(u64, 2), hit_count);
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
    state.clock.ppu_cycles = 100 * 341; // Scanline 100

    debugger.stepScanline(&state);
    try testing.expectEqual(DebugMode.step_scanline, debugger.mode);
    try testing.expectEqual(@as(u16, 101), debugger.step_state.target_scanline.?);

    // Should not break yet
    try testing.expect(!try debugger.shouldBreak(&state));

    // Should break on target scanline
    state.clock.ppu_cycles = 101 * 341; // Scanline 101
    try testing.expect(try debugger.shouldBreak(&state));
}

test "Debugger: step frame" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);
    state.clock.ppu_cycles = 10 * 89342; // Frame 10

    debugger.stepFrame(&state);
    try testing.expectEqual(DebugMode.step_frame, debugger.mode);
    try testing.expectEqual(@as(u64, 11), debugger.step_state.target_frame.?);

    // Should not break yet
    try testing.expect(!try debugger.shouldBreak(&state));

    // Should break on target frame
    state.clock.ppu_cycles = 11 * 89342; // Frame 11
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
    const restored = try debugger.restoreFromHistory(0, null);
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

    try testing.expectEqual(@as(usize, 2), debugger.breakpoint_count);
    try testing.expectEqual(@as(usize, 1), debugger.watchpoint_count);

    // Clear all
    debugger.clearBreakpoints();
    debugger.clearWatchpoints();

    try testing.expectEqual(@as(usize, 0), debugger.breakpoint_count);
    try testing.expectEqual(@as(usize, 0), debugger.watchpoint_count);
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

    var state = createTestState(&config);

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

    var state = createTestState(&config);

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

    var state = createTestState(&config);

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

    var state = createTestState(&config);

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

    var state = createTestState(&config);

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

    var state = createTestState(&config);

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
    state.bus.open_bus = 0x42;
    const original_value = state.bus.open_bus;
    // Cycle tracking removed: open_bus is now just u8

    // Read memory via debugger (should NOT affect open bus)
    _ = debugger.readMemory(&state, 0x0200);

    // ✅ Verify open bus unchanged
    try testing.expectEqual(original_value, state.bus.open_bus);
}

test "Memory Inspection: readMemoryRange does not affect open bus" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Set open bus to known value
    state.bus.open_bus = 0x99;
    const original_value = state.bus.open_bus;
    // Cycle tracking removed: open_bus is now just u8

    // Read memory range via debugger
    const buffer = try debugger.readMemoryRange(testing.allocator, &state, 0x0100, 16);
    defer testing.allocator.free(buffer);

    // ✅ Verify open bus unchanged after multiple reads
    try testing.expectEqual(original_value, state.bus.open_bus);
}

test "Memory Inspection: multiple reads preserve state" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Capture initial state
    state.bus.open_bus = 0xAA;
    const initial_value = state.bus.open_bus;

    // Perform 1000 debugger reads
    for (0..1000) |i| {
        _ = debugger.readMemory(&state, @intCast(i % 256));
    }

    // ✅ Open bus should still be unchanged
    try testing.expectEqual(initial_value, state.bus.open_bus);
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

// ============================================================================
// Phase 3: Bounded Modifications History Tests
// ============================================================================

test "Modification History: bounded to max size" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    // Set small max size for testing
    debugger.modifications_max_size = 10;

    var state = createTestState(&config);

    // Add 20 modifications (2x max size)
    for (0..20) |i| {
        debugger.setRegisterA(&state, @intCast(i));
    }

    // ✅ Should be bounded to 10
    const mods = debugger.getModifications();
    try testing.expectEqual(@as(usize, 10), mods.len);

    // ✅ Should contain most recent 10 (values 10-19)
    try testing.expectEqual(@as(u8, 10), mods[0].register_a);
    try testing.expectEqual(@as(u8, 19), mods[9].register_a);
}

test "Modification History: circular buffer behavior" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    debugger.modifications_max_size = 5;

    var state = createTestState(&config);

    // Add 3 modifications
    debugger.setRegisterA(&state, 0x11);
    debugger.setRegisterX(&state, 0x22);
    debugger.setRegisterY(&state, 0x33);

    try testing.expectEqual(@as(usize, 3), debugger.getModifications().len);

    // Add 5 more (total 8, should wrap to 5)
    for (0..5) |i| {
        debugger.setProgramCounter(&state, @intCast(0x8000 + i));
    }

    // ✅ Should have exactly 5 entries
    try testing.expectEqual(@as(usize, 5), debugger.getModifications().len);

    // ✅ First 3 should be removed, remaining are last 5 PC changes
    const mods = debugger.getModifications();
    try testing.expect(mods[0] == .program_counter);
    try testing.expectEqual(@as(u16, 0x8000), mods[0].program_counter);
    try testing.expectEqual(@as(u16, 0x8004), mods[4].program_counter);
}

// ============================================================================
// TAS (Tool-Assisted Speedrun) Support Tests
// ============================================================================
// These tests verify that the debugger supports TAS workflows including
// intentional undefined behaviors, corruption, and edge cases.

test "TAS Support: PC in RAM for ACE (Arbitrary Code Execution)" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Write crafted "code" to RAM (actually data)
    // Example: LDA #$42 (0xA9 0x42), RTS (0x60)
    debugger.writeMemory(&state, 0x0200, 0xA9); // LDA immediate
    debugger.writeMemory(&state, 0x0201, 0x42); // Value
    debugger.writeMemory(&state, 0x0202, 0x60); // RTS

    // ✅ Set PC to RAM address (ACE technique)
    debugger.setProgramCounter(&state, 0x0200);
    try testing.expectEqual(@as(u16, 0x0200), state.cpu.pc);

    // ✅ Verify modification logged
    const mods = debugger.getModifications();
    try testing.expect(mods.len >= 1);

    // CPU will now execute RAM as code (ACE exploit)
    // This is INTENTIONAL for TAS - debugger does NOT prevent this
}

test "TAS Support: ROM write intent tracking" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Clear modifications history
    debugger.clearHistory();

    // ✅ Write to ROM region (hardware-protected, write won't succeed)
    debugger.writeMemory(&state, 0x8000, 0xFF);
    debugger.writeMemory(&state, 0xFFFC, 0x00); // NMI vector (ROM)

    // ✅ Verify writes are LOGGED even though they don't modify ROM
    // This is intentional - debugger tracks INTENT for TAS documentation
    const mods = debugger.getModifications();
    try testing.expectEqual(@as(usize, 2), mods.len);
    try testing.expect(mods[0] == .memory_write);
    try testing.expectEqual(@as(u16, 0x8000), mods[0].memory_write.address);
    try testing.expectEqual(@as(u8, 0xFF), mods[0].memory_write.value);

    // ✅ Data bus is updated even though ROM isn't modified
    try testing.expectEqual(@as(u8, 0x00), state.bus.open_bus);
}

test "TAS Support: Stack overflow and underflow edge cases" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // ✅ Test stack overflow (SP = 0x00)
    debugger.setStackPointer(&state, 0x00);
    try testing.expectEqual(@as(u8, 0x00), state.cpu.sp);
    // Stack now at $0100 - pushes will wrap to $01FF

    // ✅ Test stack underflow (SP = 0xFF)
    debugger.setStackPointer(&state, 0xFF);
    try testing.expectEqual(@as(u8, 0xFF), state.cpu.sp);
    // Stack now at $01FF - pops will wrap to $0100

    // ✅ Verify modifications logged
    const mods = debugger.getModifications();
    try testing.expect(mods.len >= 2);

    // This is INTENTIONAL - TAS uses stack manipulation for wrong warps
    // The emulator allows these edge cases without protection
}

test "TAS Support: Unusual status flag combinations" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // ✅ Set decimal flag (normally ignored on NES)
    debugger.setStatusRegister(&state, 0b00001000); // D flag only
    try testing.expect(state.cpu.p.decimal);
    try testing.expect(!state.cpu.p.carry);
    try testing.expect(!state.cpu.p.zero);

    // ✅ Set all flags simultaneously (unusual but valid)
    debugger.setStatusRegister(&state, 0xFF);
    try testing.expect(state.cpu.p.carry);
    try testing.expect(state.cpu.p.zero);
    try testing.expect(state.cpu.p.interrupt);
    try testing.expect(state.cpu.p.decimal);
    try testing.expect(state.cpu.p.overflow);
    try testing.expect(state.cpu.p.negative);

    // ✅ Clear all flags (also unusual)
    debugger.setStatusRegister(&state, 0x00);
    try testing.expect(!state.cpu.p.carry);
    try testing.expect(!state.cpu.p.zero);
    try testing.expect(!state.cpu.p.interrupt);
    try testing.expect(!state.cpu.p.decimal);
    try testing.expect(!state.cpu.p.overflow);
    try testing.expect(!state.cpu.p.negative);

    // All combinations are INTENTIONAL - TAS may use unusual states
}

test "TAS Support: PC in I/O region (undefined behavior)" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // ✅ Set PC to PPU register region (undefined behavior)
    debugger.setProgramCounter(&state, 0x2000); // PPUCTRL
    try testing.expectEqual(@as(u16, 0x2000), state.cpu.pc);

    // ✅ Set PC to APU register region
    debugger.setProgramCounter(&state, 0x4000); // APU
    try testing.expectEqual(@as(u16, 0x4000), state.cpu.pc);

    // ✅ Set PC to controller I/O region
    debugger.setProgramCounter(&state, 0x4016); // Controller 1
    try testing.expectEqual(@as(u16, 0x4016), state.cpu.pc);

    // ✅ Verify modifications logged
    const mods = debugger.getModifications();
    try testing.expect(mods.len >= 3);

    // This is INTENTIONAL - debugger does NOT prevent undefined behaviors
    // CPU will attempt to execute I/O reads as opcodes (may crash/glitch)
    // TAS users may intentionally create these states for exploits
}

// ============================================================================
// Isolation Verification Tests
// ============================================================================
// These tests verify complete isolation between debugger and runtime:
// - Zero shared mutable state
// - Debugger operations don't affect runtime
// - Runtime execution doesn't corrupt debugger state

test "Isolation: Debugger state changes don't affect runtime" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    const state = createTestState(&config);

    // Capture original runtime state
    const orig_pc = state.cpu.pc;
    const orig_a = state.cpu.a;
    const orig_sp = state.cpu.sp;
    const orig_bus = state.bus.open_bus;

    // Perform debugger operations (should NOT affect runtime)
    try debugger.addBreakpoint(0x8100, .execute);
    try debugger.addWatchpoint(0x0200, 1, .write);
    debugger.mode = .paused;
    debugger.clearHistory();

    // ✅ Verify runtime state UNCHANGED
    try testing.expectEqual(orig_pc, state.cpu.pc);
    try testing.expectEqual(orig_a, state.cpu.a);
    try testing.expectEqual(orig_sp, state.cpu.sp);
    try testing.expectEqual(orig_bus, state.bus.open_bus);

    // Debugger and runtime are COMPLETELY ISOLATED
}

test "Isolation: Runtime execution doesn't corrupt debugger state" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Set up debugger state
    try debugger.addBreakpoint(0x8000, .execute);
    try debugger.addWatchpoint(0x0200, 1, .write);
    debugger.setRegisterA(&state, 0x42);
    debugger.setProgramCounter(&state, 0x8000);

    const mod_count_before = debugger.getModifications().len;

    // Simulate runtime operations (direct state manipulation)
    state.cpu.a = 0x99; // Direct write (NOT via debugger)
    state.cpu.pc = 0x8050;
    state.busWrite(0x0200, 0xFF);
    state.clock.ppu_cycles = 200 * 341; // Scanline 200

    // ✅ Verify debugger state UNCHANGED
    try testing.expectEqual(@as(usize, 1), debugger.breakpoint_count);
    try testing.expectEqual(@as(usize, 1), debugger.watchpoint_count);
    // Find and verify breakpoint address
    var found_bp_addr: u16 = 0;
    for (debugger.breakpoints[0..256]) |maybe_bp| {
        if (maybe_bp) |bp| {
            found_bp_addr = bp.address;
            break;
        }
    }
    try testing.expectEqual(@as(u16, 0x8000), found_bp_addr);
    // Find and verify watchpoint address
    var found_wp_addr: u16 = 0;
    for (debugger.watchpoints[0..256]) |maybe_wp| {
        if (maybe_wp) |wp| {
            found_wp_addr = wp.address;
            break;
        }
    }
    try testing.expectEqual(@as(u16, 0x0200), found_wp_addr);

    // ✅ Modification history UNCHANGED (runtime ops don't log to debugger)
    try testing.expectEqual(mod_count_before, debugger.getModifications().len);

    // Runtime and debugger are COMPLETELY ISOLATED
}

test "Isolation: Breakpoint state isolation from runtime" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Add breakpoints via debugger
    try debugger.addBreakpoint(0x8000, .execute);
    try debugger.addBreakpoint(0x8010, .write);
    try debugger.addBreakpoint(0x8020, .read);

    // Capture breakpoint count
    const bp_count = debugger.breakpoint_count;

    // Simulate runtime operations that MIGHT affect breakpoints (if shared)
    state.cpu.pc = 0x8000; // PC at breakpoint address
    state.busWrite(0x8010, 0xFF); // Write to breakpoint address
    _ = state.busRead(0x8020); // Read from breakpoint address

    // Execute CPU cycles
    for (0..100) |_| {
        state.tickCpu();
    }

    // ✅ Breakpoint count UNCHANGED (runtime doesn't modify breakpoints)
    try testing.expectEqual(bp_count, debugger.breakpoint_count);

    // ✅ Breakpoints still at correct addresses
    var found_addresses = [_]u16{ 0, 0, 0 };
    var found_count: usize = 0;
    for (debugger.breakpoints[0..256]) |maybe_bp| {
        if (maybe_bp) |bp| {
            found_addresses[found_count] = bp.address;
            found_count += 1;
        }
    }
    try testing.expectEqual(@as(usize, 3), found_count);
    // Check addresses (may be in any order due to fixed array slots)
    const has_8000 = (found_addresses[0] == 0x8000 or found_addresses[1] == 0x8000 or found_addresses[2] == 0x8000);
    const has_8010 = (found_addresses[0] == 0x8010 or found_addresses[1] == 0x8010 or found_addresses[2] == 0x8010);
    const has_8020 = (found_addresses[0] == 0x8020 or found_addresses[1] == 0x8020 or found_addresses[2] == 0x8020);
    try testing.expect(has_8000);
    try testing.expect(has_8010);
    try testing.expect(has_8020);

    // Breakpoint storage is ISOLATED from runtime
}

test "Isolation: Modification history isolation from runtime" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Log modifications via debugger
    debugger.setRegisterA(&state, 0x11);
    debugger.setRegisterX(&state, 0x22);
    debugger.setRegisterY(&state, 0x33);

    const mod_count = debugger.getModifications().len;
    try testing.expectEqual(@as(usize, 3), mod_count);

    // Simulate runtime operations (NOT via debugger)
    state.cpu.a = 0x99; // Direct write
    state.cpu.x = 0x88;
    state.cpu.y = 0x77;
    state.cpu.pc = 0x9000;
    state.cpu.sp = 0x00;
    state.busWrite(0x0300, 0xFF);
    state.clock.ppu_cycles += 89342; // Advance one frame

    // ✅ Modification history UNCHANGED (runtime ops don't auto-log)
    try testing.expectEqual(mod_count, debugger.getModifications().len);

    // ✅ Original modifications preserved
    const mods = debugger.getModifications();
    try testing.expectEqual(@as(u8, 0x11), mods[0].register_a);
    try testing.expectEqual(@as(u8, 0x22), mods[1].register_x);
    try testing.expectEqual(@as(u8, 0x33), mods[2].register_y);

    // Modification history is ISOLATED from runtime
}

test "Isolation: readMemory() const parameter enforces isolation" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Set known RAM value
    state.busWrite(0x0200, 0x42);

    // Set known open bus value
    state.bus.open_bus = 0x99;
    const orig_bus_value = state.bus.open_bus;
    // Cycle tracking removed: open_bus is now just u8

    // ✅ readMemory accepts CONST state (compile-time isolation guarantee)
    const const_state: *const EmulationState = &state;
    const value = debugger.readMemory(const_state, 0x0200);

    // ✅ Correct value read
    try testing.expectEqual(@as(u8, 0x42), value);

    // ✅ Open bus UNCHANGED (const parameter prevents mutation)
    try testing.expectEqual(orig_bus_value, state.bus.open_bus);

    // COMPILE-TIME ISOLATION: const parameter prevents mutation
    // If readMemory tried to modify state, it would be a compile error
}

test "Isolation: shouldBreak() doesn't mutate state" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    // Add breakpoint at current PC
    try debugger.addBreakpoint(0x8000, .execute);
    state.cpu.pc = 0x8000;

    // Capture state before shouldBreak
    const orig_a = state.cpu.a;
    const orig_pc = state.cpu.pc;
    const orig_sp = state.cpu.sp;
    const orig_bus = state.bus.open_bus;

    // ✅ shouldBreak() checks breakpoints without mutating state
    const should_break = try debugger.shouldBreak(&state);
    try testing.expect(should_break);

    // ✅ State UNCHANGED after breakpoint check
    try testing.expectEqual(orig_a, state.cpu.a);
    try testing.expectEqual(orig_pc, state.cpu.pc);
    try testing.expectEqual(orig_sp, state.cpu.sp);
    try testing.expectEqual(orig_bus, state.bus.open_bus);

    // Hook functions operate on READ-ONLY state
    // Future user-defined hooks will receive *const EmulationState
    // This provides COMPILE-TIME isolation guarantee
}

// ============================================================================
// Callback System Tests
// ============================================================================
// These tests verify user-defined callbacks work correctly and maintain
// isolation, RT-safety, and const-correctness guarantees.

const TestCallback = struct {
    break_count: u32 = 0,
    last_pc: u16 = 0,
    last_address: u16 = 0,

    fn onBeforeInstruction(userdata: *anyopaque, state: *const EmulationState) bool {
        const self: *TestCallback = @ptrCast(@alignCast(userdata));
        self.last_pc = state.cpu.pc;
        self.break_count += 1;
        return state.cpu.pc == 0x8100; // Break at specific PC
    }

    fn onMemoryAccess(userdata: *anyopaque, address: u16, value: u8, is_write: bool) bool {
        const self: *TestCallback = @ptrCast(@alignCast(userdata));
        self.last_address = address;
        _ = value;
        _ = is_write;
        return address == 0x2000; // Break on PPU access
    }
};

test "Callback: onBeforeInstruction called and can break" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    var callback = TestCallback{};
    try debugger.registerCallback(.{
        .onBeforeInstruction = TestCallback.onBeforeInstruction,
        .userdata = &callback,
    });

    // Callback should NOT break at 0x8000
    state.cpu.pc = 0x8000;
    const should_break1 = try debugger.shouldBreak(&state);
    try testing.expect(!should_break1);
    try testing.expectEqual(@as(u32, 1), callback.break_count);
    try testing.expectEqual(@as(u16, 0x8000), callback.last_pc);

    // Callback SHOULD break at 0x8100
    state.cpu.pc = 0x8100;
    const should_break2 = try debugger.shouldBreak(&state);
    try testing.expect(should_break2);
    try testing.expectEqual(@as(u32, 2), callback.break_count);
    try testing.expectEqual(@as(u16, 0x8100), callback.last_pc);

    // Verify break reason
    const reason = debugger.getBreakReason();
    try testing.expect(reason != null);
    try testing.expect(std.mem.eql(u8, reason.?, "User callback break"));
}

test "Callback: onMemoryAccess called and can break" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    const state = createTestState(&config);

    var callback = TestCallback{};
    try debugger.registerCallback(.{
        .onMemoryAccess = TestCallback.onMemoryAccess,
        .userdata = &callback,
    });

    // Callback should NOT break at 0x0200
    const should_break1 = try debugger.checkMemoryAccess(&state, 0x0200, 0x42, false);
    try testing.expect(!should_break1);
    try testing.expectEqual(@as(u16, 0x0200), callback.last_address);

    // Callback SHOULD break at 0x2000 (PPU)
    const should_break2 = try debugger.checkMemoryAccess(&state, 0x2000, 0x80, true);
    try testing.expect(should_break2);
    try testing.expectEqual(@as(u16, 0x2000), callback.last_address);

    // Verify break reason contains "Memory callback"
    const reason = debugger.getBreakReason();
    try testing.expect(reason != null);
    try testing.expect(std.mem.indexOf(u8, reason.?, "Memory callback") != null);
}

test "Callback: Multiple callbacks supported" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    var callback1 = TestCallback{};
    var callback2 = TestCallback{};

    // Register two callbacks
    try debugger.registerCallback(.{
        .onBeforeInstruction = TestCallback.onBeforeInstruction,
        .userdata = &callback1,
    });
    try debugger.registerCallback(.{
        .onBeforeInstruction = TestCallback.onBeforeInstruction,
        .userdata = &callback2,
    });

    // Both callbacks should be called
    state.cpu.pc = 0x8000;
    _ = try debugger.shouldBreak(&state);

    try testing.expectEqual(@as(u32, 1), callback1.break_count);
    try testing.expectEqual(@as(u32, 1), callback2.break_count);
    try testing.expectEqual(@as(u16, 0x8000), callback1.last_pc);
    try testing.expectEqual(@as(u16, 0x8000), callback2.last_pc);
}

test "Callback: Unregister works correctly" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    var callback = TestCallback{};
    try debugger.registerCallback(.{
        .onBeforeInstruction = TestCallback.onBeforeInstruction,
        .userdata = &callback,
    });

    // Callback is registered
    state.cpu.pc = 0x8000;
    _ = try debugger.shouldBreak(&state);
    try testing.expectEqual(@as(u32, 1), callback.break_count);

    // Unregister callback
    const removed = debugger.unregisterCallback(&callback);
    try testing.expect(removed);

    // Callback should NOT be called anymore
    state.cpu.pc = 0x8000;
    _ = try debugger.shouldBreak(&state);
    try testing.expectEqual(@as(u32, 1), callback.break_count); // Still 1, not incremented
}

test "Callback: Clear all callbacks" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    var callback1 = TestCallback{};
    var callback2 = TestCallback{};

    try debugger.registerCallback(.{
        .onBeforeInstruction = TestCallback.onBeforeInstruction,
        .userdata = &callback1,
    });
    try debugger.registerCallback(.{
        .onBeforeInstruction = TestCallback.onBeforeInstruction,
        .userdata = &callback2,
    });

    // Clear all callbacks
    debugger.clearCallbacks();

    // No callbacks should be called
    state.cpu.pc = 0x8000;
    _ = try debugger.shouldBreak(&state);

    try testing.expectEqual(@as(u32, 0), callback1.break_count);
    try testing.expectEqual(@as(u32, 0), callback2.break_count);
}

test "Callback: RT-safety - no heap allocations in callback path" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    var callback = TestCallback{};
    try debugger.registerCallback(.{
        .onBeforeInstruction = TestCallback.onBeforeInstruction,
        .userdata = &callback,
    });

    // Capture allocation count
    const allocations_before = testing.allocator_instance.total_requested_bytes;

    // Call shouldBreak (which calls callback)
    state.cpu.pc = 0x8000;
    _ = try debugger.shouldBreak(&state);

    const allocations_after = testing.allocator_instance.total_requested_bytes;

    // ✅ Verify zero heap allocations in callback path
    try testing.expectEqual(allocations_before, allocations_after);
}

test "Callback: Const state enforcement - callback receives read-only state" {
    // This is a compile-time test - if it compiles, const is enforced
    // The callback signature requires *const EmulationState

    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = createTestState(&config);

    const ReadOnlyCallback = struct {
        fn onBefore(userdata: *anyopaque, const_state: *const EmulationState) bool {
            _ = userdata;
            // ✅ Can read state
            _ = const_state.cpu.pc;
            _ = const_state.cpu.a;

            // ❌ Cannot write state (would be compile error)
            // const_state.cpu.pc = 0x9000;  // Compile error: const_state is const

            return false;
        }
    };

    var callback_data: u32 = 0;
    try debugger.registerCallback(.{
        .onBeforeInstruction = ReadOnlyCallback.onBefore,
        .userdata = &callback_data,
    });

    // If this compiles, const enforcement works
    _ = try debugger.shouldBreak(&state);
}

// ============================================================================
// Fixed Array Capacity Tests
// ============================================================================

test "Debugger: Breakpoint limit enforcement (256 max)" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    // Add 256 breakpoints (should succeed)
    for (0..256) |i| {
        try debugger.addBreakpoint(@intCast(i), .execute);
    }
    try testing.expectEqual(@as(usize, 256), debugger.breakpoint_count);

    // 257th breakpoint should fail
    try testing.expectError(error.BreakpointLimitReached, debugger.addBreakpoint(256, .execute));
    try testing.expectEqual(@as(usize, 256), debugger.breakpoint_count); // Count unchanged
}

test "Debugger: Watchpoint limit enforcement (256 max)" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    // Add 256 watchpoints (should succeed)
    for (0..256) |i| {
        try debugger.addWatchpoint(@intCast(i), 1, .write);
    }
    try testing.expectEqual(@as(usize, 256), debugger.watchpoint_count);

    // 257th watchpoint should fail
    try testing.expectError(error.WatchpointLimitReached, debugger.addWatchpoint(256, 1, .write));
    try testing.expectEqual(@as(usize, 256), debugger.watchpoint_count); // Count unchanged
}

test "Debugger: memory trigger tracking" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    try testing.expect(!debugger.hasMemoryTriggers());

    try debugger.addBreakpoint(0x8000, .execute);
    try testing.expect(!debugger.hasMemoryTriggers());

    try debugger.addBreakpoint(0x8000, .write);
    try testing.expect(debugger.hasMemoryTriggers());

    try testing.expect(debugger.setBreakpointEnabled(0x8000, .write, false));
    try testing.expect(!debugger.hasMemoryTriggers());
    try testing.expect(debugger.setBreakpointEnabled(0x8000, .write, true));
    try testing.expect(debugger.hasMemoryTriggers());

    try testing.expect(debugger.removeBreakpoint(0x8000, .write));
    try testing.expect(!debugger.hasMemoryTriggers());

    try debugger.addWatchpoint(0x2000, 1, .write);
    try testing.expect(debugger.hasMemoryTriggers());
    try testing.expect(debugger.removeWatchpoint(0x2000, .write));
    try testing.expect(!debugger.hasMemoryTriggers());

    debugger.clearBreakpoints();
    debugger.clearWatchpoints();
    try testing.expect(!debugger.hasMemoryTriggers());
}

test "Debugger: bus memory access halts execution" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);

    state.debugger = Debugger.init(testing.allocator, &config);
    defer if (state.debugger) |*d| d.deinit();

    var debugger = &state.debugger.?;
    try debugger.addWatchpoint(0x0000, 1, .write);
    try testing.expect(debugger.hasMemoryTriggers());

    state.busWrite(0x0000, 0x42);

    try testing.expect(state.debuggerIsPaused());
    try testing.expect(state.debug_break_occurred);

    const reason = debugger.getBreakReason() orelse "";
    try testing.expectEqualStrings("Watchpoint: write $0000 = $42", reason);
}
