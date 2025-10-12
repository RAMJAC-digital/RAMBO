//! Debugger Integration Tests
//!
//! Tests verify end-to-end debugger functionality including:
//! - Execution history capture and restore
//! - Statistics tracking
//! - Combined breakpoint/watchpoint operations
//! - Fixed array capacity limits
//! - Memory trigger tracking
//! - Integration with bus operations

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Debugger = RAMBO.Debugger.Debugger;
const DebugMode = RAMBO.Debugger.DebugMode;
const BreakpointType = RAMBO.Debugger.BreakpointType;

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;

const test_fixtures = @import("test_fixtures.zig");

// ============================================================================
// Execution History Tests
// ============================================================================

test "Debugger: capture and restore history" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);
    state.cpu.pc = 0x8000;
    state.cpu.a = 0x42;

    // Capture state
    try debugger.captureHistory(&state);
    try testing.expectEqual(@as(usize, 1), debugger.state.history.items.len);
    try testing.expectEqual(@as(u16, 0x8000), debugger.state.history.items[0].pc);

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
    debugger.state.history_max_size = 3;

    var state = test_fixtures.createTestState(&config);

    // Capture 4 states (exceeds max)
    for (0..4) |i| {
        state.cpu.pc = @intCast(0x8000 + i);
        try debugger.captureHistory(&state);
    }

    // Should only have 3 entries
    try testing.expectEqual(@as(usize, 3), debugger.state.history.items.len);

    // First entry should be PC=0x8001 (oldest removed)
    try testing.expectEqual(@as(u16, 0x8001), debugger.state.history.items[0].pc);
}

test "Debugger: clear history" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    try debugger.captureHistory(&state);
    try testing.expectEqual(@as(usize, 1), debugger.state.history.items.len);

    debugger.clearHistory();
    try testing.expectEqual(@as(usize, 0), debugger.state.history.items.len);
}

// ============================================================================
// Statistics Tests
// ============================================================================

test "Debugger: statistics tracking" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Track instructions
    _ = try debugger.shouldBreak(&state);
    _ = try debugger.shouldBreak(&state);
    try testing.expectEqual(@as(u64, 2), debugger.state.stats.instructions_executed);

    // Track breakpoints
    try debugger.addBreakpoint(0x8000, .execute);
    _ = try debugger.shouldBreak(&state);
    try testing.expectEqual(@as(u64, 1), debugger.state.stats.breakpoints_hit);

    // Track watchpoints
    try debugger.addWatchpoint(0x0000, 1, .write);
    _ = try debugger.checkMemoryAccess(&state, 0x0000, 0xFF, true);
    try testing.expectEqual(@as(u64, 1), debugger.state.stats.watchpoints_hit);

    // Track snapshots
    try debugger.captureHistory(&state);
    try testing.expectEqual(@as(u64, 1), debugger.state.stats.snapshots_captured);
}

// ============================================================================
// Integration Tests
// ============================================================================

test "Debugger: combined breakpoints and watchpoints" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

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

    try testing.expectEqual(@as(usize, 2), debugger.state.breakpoint_count);
    try testing.expectEqual(@as(usize, 1), debugger.state.watchpoint_count);

    // Clear all
    debugger.clearBreakpoints();
    debugger.clearWatchpoints();

    try testing.expectEqual(@as(usize, 0), debugger.state.breakpoint_count);
    try testing.expectEqual(@as(usize, 0), debugger.state.watchpoint_count);
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
    try testing.expectEqual(@as(usize, 256), debugger.state.breakpoint_count);

    // 257th breakpoint should fail
    try testing.expectError(error.BreakpointLimitReached, debugger.addBreakpoint(256, .execute));
    try testing.expectEqual(@as(usize, 256), debugger.state.breakpoint_count); // Count unchanged
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
    try testing.expectEqual(@as(usize, 256), debugger.state.watchpoint_count);

    // 257th watchpoint should fail
    try testing.expectError(error.WatchpointLimitReached, debugger.addWatchpoint(256, 1, .write));
    try testing.expectEqual(@as(usize, 256), debugger.state.watchpoint_count); // Count unchanged
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
