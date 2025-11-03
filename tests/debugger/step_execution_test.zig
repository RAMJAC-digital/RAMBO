//! Debugger Step Execution Tests
//!
//! Tests for step execution modes:
//! - Step instruction (single-step)
//! - Step over (skip subroutines)
//! - Step out (return from subroutine)
//! - Step scanline (PPU timing)
//! - Step frame (frame-by-frame)

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const test_fixtures = @import("test_fixtures.zig");

const Debugger = RAMBO.Debugger.Debugger;
const DebugMode = RAMBO.Debugger.DebugMode;
const Config = RAMBO.Config.Config;

test "Debugger: step instruction" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);

    // Enable step mode
    debugger.stepInstruction();
    try testing.expectEqual(DebugMode.step_instruction, debugger.state.mode);

    // Should break immediately
    try testing.expect(try debugger.shouldBreak(&state));
    try testing.expectEqual(DebugMode.paused, debugger.state.mode);
}

test "Debugger: step over (same stack level)" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);
    state.cpu.sp = 0xFD;

    debugger.stepOver(&state);
    try testing.expectEqual(DebugMode.step_over, debugger.state.mode);
    try testing.expectEqual(@as(u8, 0xFD), debugger.state.step_state.initial_sp);

    // Should not break yet
    try testing.expect(!try debugger.shouldBreak(&state));

    // Simulate JSR (decrement SP)
    state.cpu.sp = 0xFB;
    try testing.expect(!try debugger.shouldBreak(&state));

    // Simulate RTS (increment SP back)
    state.cpu.sp = 0xFD;
    try testing.expect(try debugger.shouldBreak(&state));
    try testing.expectEqual(DebugMode.paused, debugger.state.mode);
}

test "Debugger: step out (return from subroutine)" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);
    state.cpu.sp = 0xFB; // Inside subroutine

    debugger.stepOut(&state);
    try testing.expectEqual(DebugMode.step_out, debugger.state.mode);

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

    var state = test_fixtures.createTestState(&config);
    state.ppu.scanline = 100; // Scanline 100

    debugger.stepScanline(&state);
    try testing.expectEqual(DebugMode.step_scanline, debugger.state.mode);
    try testing.expectEqual(@as(u16, 101), debugger.state.step_state.target_scanline.?);

    // Should not break yet
    try testing.expect(!try debugger.shouldBreak(&state));

    // Should break on target scanline
    state.ppu.scanline = 101; // Scanline 101
    try testing.expect(try debugger.shouldBreak(&state));
}

test "Debugger: step frame" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    var state = test_fixtures.createTestState(&config);
    state.ppu.frame_count = 10; // Frame 10

    debugger.stepFrame(&state);
    try testing.expectEqual(DebugMode.step_frame, debugger.state.mode);
    try testing.expectEqual(@as(u64, 11), debugger.state.step_state.target_frame.?);

    // Should not break yet
    try testing.expect(!try debugger.shouldBreak(&state));

    // Should break on target frame
    state.ppu.frame_count = 11; // Frame 11
    try testing.expect(try debugger.shouldBreak(&state));
}
