//! Debugger Watchpoint Tests
//!
//! Tests for watchpoint functionality:
//! - Write watchpoints (break on memory write)
//! - Read watchpoints (break on memory read)
//! - Change watchpoints (break only when value changes)
//! - Watchpoint address ranges

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const test_fixtures = @import("test_fixtures.zig");

const Debugger = RAMBO.Debugger.Debugger;
const DebugMode = RAMBO.Debugger.DebugMode;
const Config = RAMBO.Config.Config;

test "Debugger: write watchpoint" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Add write watchpoint
    try debugger.addWatchpoint(0x0000, 1, .write);

    // Should break on write
    try testing.expect(try debugger.checkMemoryAccess(&state, 0x0000, 0xFF, true));
    try testing.expectEqual(DebugMode.paused, debugger.state.mode);

    debugger.continue_();

    // Should not break on read
    try testing.expect(!try debugger.checkMemoryAccess(&state, 0x0000, 0xFF, false));
}

test "Debugger: read watchpoint" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

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

    var state = test_fixtures.createTestState(&config);

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

    var state = test_fixtures.createTestState(&config);

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
