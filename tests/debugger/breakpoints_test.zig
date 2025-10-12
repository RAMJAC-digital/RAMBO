//! Debugger Breakpoint Tests
//!
//! Tests for breakpoint functionality:
//! - Execute breakpoints (at PC)
//! - Conditional breakpoints (with register conditions)
//! - Memory breakpoints (read, write, access)
//! - Breakpoint enable/disable
//! - Hit count tracking

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const test_fixtures = @import("test_fixtures.zig");

const Debugger = RAMBO.Debugger.Debugger;
const DebugMode = RAMBO.Debugger.DebugMode;
const Config = RAMBO.Config.Config;

test "Debugger: execute breakpoint triggers" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Add breakpoint at PC
    try debugger.addBreakpoint(0x8000, .execute);

    // Should break
    const should_break = try debugger.shouldBreak(&state);
    try testing.expect(should_break);
    try testing.expectEqual(DebugMode.paused, debugger.state.mode);
    try testing.expectEqual(@as(u64, 1), debugger.state.stats.breakpoints_hit);
}

test "Debugger: execute breakpoint with condition" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);
    state.cpu.a = 0x42;

    // Add conditional breakpoint
    try debugger.addBreakpoint(0x8000, .execute);
    // Find the breakpoint we just added and set condition
    for (debugger.state.breakpoints[0..256]) |*maybe_bp| {
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

    var state = test_fixtures.createTestState(&config);

    // Add read breakpoint
    try debugger.addBreakpoint(0x0100, .read);

    // Should break on read
    try testing.expect(try debugger.checkMemoryAccess(&state, 0x0100, 0x42, false));
    try testing.expectEqual(DebugMode.paused, debugger.state.mode);

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

    var state = test_fixtures.createTestState(&config);

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

    var state = test_fixtures.createTestState(&config);

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

    var state = test_fixtures.createTestState(&config);

    try debugger.addBreakpoint(0x8000, .execute);

    // Hit breakpoint multiple times
    _ = try debugger.shouldBreak(&state);
    // Find the breakpoint and check hit count
    var hit_count: u64 = 0;
    for (debugger.state.breakpoints[0..256]) |maybe_bp| {
        if (maybe_bp) |bp| {
            hit_count = bp.hit_count;
            break;
        }
    }
    try testing.expectEqual(@as(u64, 1), hit_count);

    debugger.continue_();
    _ = try debugger.shouldBreak(&state);
    for (debugger.state.breakpoints[0..256]) |maybe_bp| {
        if (maybe_bp) |bp| {
            hit_count = bp.hit_count;
            break;
        }
    }
    try testing.expectEqual(@as(u64, 2), hit_count);
}
