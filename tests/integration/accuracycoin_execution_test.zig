//! AccuracyCoin Execution Test
//!
//! This test runs the full AccuracyCoin test suite and extracts results
//! to identify which specific tests pass/fail with our current implementation.
//!
//! AccuracyCoin Test Result Protocol:
//! - $6000-$6003: Test status bytes (0x00 = pass, 0x80 = running, other = fail)
//! - $6004+: Null-terminated error message if test failed
//!
//! The ROM cycles through tests continuously. We run for multiple frames
//! and sample test results to build a comprehensive pass/fail report.

const std = @import("std");
const testing = std.testing;
const RomTestRunner = @import("rom_test_runner.zig");
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

const RunConfig = RomTestRunner.RunConfig;
const TestResult = RomTestRunner.TestResult;

test "AccuracyCoin: Execute and extract test results" {
    const accuracycoin_path = "tests/data/AccuracyCoin.nes";

    // Configuration: Run for 10 seconds worth of frames (600 frames)
    // AccuracyCoin cycles through all tests continuously
    const config = RunConfig{
        .max_frames = 600,
        .max_instructions = 0, // No instruction limit
        .completion_address = null, // Run for full duration
        .verbose = true,
    };

    var runner = RomTestRunner.RomTestRunner.init(
        testing.allocator,
        accuracycoin_path,
        config,
    ) catch |err| {
        if (err == error.FileNotFound) {
            return error.SkipZigTest;
        }
        return err;
    };
    defer runner.deinit();

    // Run the ROM
    var result = try runner.run();
    defer result.deinit(testing.allocator);

    // Extract test results from $6000-$6003
    // Verify test passed
    try testing.expect(result.passed);

    // If test failed, print error message for debugging
    if (result.error_message) |msg| {
        std.debug.print("AccuracyCoin test failed: {s}\n", .{msg});
    }
}

// NOTE: Test removed - was diagnostic-only with no assertions
// The test sampled AccuracyCoin status bytes at intervals but had no expectations,
// making it useless for regression detection. The first test already validates pass/fail.

// ============================================================================
// ROM Rendering Diagnosis Tests
// ============================================================================
// Verify that all commercial ROMs enable rendering when using proper Harness
// infrastructure with framebuffer support

test "ROM Diagnosis: Compare PPU initialization sequences" {
    const roms = [_]struct {
        path: []const u8,
        name: []const u8,
        expected_working: bool,
    }{
        // All ROMs enable rendering when framebuffer is provided via Harness
        .{ .path = "tests/data/AccuracyCoin.nes", .name = "AccuracyCoin", .expected_working = true },
        .{ .path = "tests/data/Bomberman/Bomberman (USA).nes", .name = "Bomberman", .expected_working = true },
        .{ .path = "tests/data/Mario/Super Mario Bros. (World).nes", .name = "Mario Bros", .expected_working = true },
        .{ .path = "tests/data/BurgerTime (USA).nes", .name = "BurgerTime", .expected_working = true },
    };

    for (roms) |rom_info| {
        // Load ROM using proper test infrastructure
        const cart = RAMBO.CartridgeType.load(testing.allocator, rom_info.path) catch |err| {
            if (err == error.FileNotFound) {
                // Skip if ROM file not available
                continue;
            }
            return err;
        };

        var h = try Harness.init();
        defer h.deinit();

        h.loadNromCartridge(cart);
        h.state.reset();

        var rendering_enabled_frame: ?u64 = null;
        var framebuffer: [256 * 240]u32 = undefined;

        // Run for 300 frames (5 seconds) checking for rendering
        var frame: usize = 0;
        while (frame < 300) : (frame += 1) {
            // Provide framebuffer for PPU rendering
            h.state.framebuffer = &framebuffer;
            _ = h.state.emulateFrame();
            h.state.framebuffer = null;

            // Check if rendering enabled
            if (rendering_enabled_frame == null and h.state.rendering_enabled) {
                rendering_enabled_frame = h.state.clock.frame();
            }
        }

        // Verify rendering state matches expectations
        if (rom_info.expected_working) {
            try testing.expect(rendering_enabled_frame != null);
        } else {
            try testing.expect(rendering_enabled_frame == null);
        }
    }
}

test "ROM Diagnosis: Check for frame_complete signal" {
    const accuracycoin_path = "tests/data/AccuracyCoin.nes";

    var runner = RomTestRunner.RomTestRunner.init(
        testing.allocator,
        accuracycoin_path,
        .{ .max_frames = 10, .verbose = false },
    ) catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };
    defer runner.deinit();

    var frame_count: usize = 0;
    var frame_complete_count: usize = 0;

    while (frame_count < 10) {
        // Run one frame
        _ = try runner.runFrame();

        // Check if frame_complete was set
        if (runner.state.frame_complete) {
            frame_complete_count += 1;

            // Reset flag (emulator would do this)
            runner.state.frame_complete = false;
        }

        frame_count += 1;
    }

    // frame_complete should fire every frame during VBlank
    try testing.expect(frame_complete_count > 0);
}
