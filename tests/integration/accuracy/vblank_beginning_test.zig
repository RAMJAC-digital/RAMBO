//! AccuracyCoin Accuracy Test: VBLANK BEGINNING
//!
//! This test verifies the exact cycle timing of the VBlank flag in PPUSTATUS ($2002).
//! The VBlank flag is set on scanline 241, dot 1 - this is the start of vertical blanking.
//!
//! Test Entry Point: 0xB44A
//! Result Address: $0450 (result_VBlank_Beginning)
//! Expected: $00 = PASS (VBlank timing correct)
//! ROM Screenshot (2025-10-19): FAIL 1

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;
const helpers = @import("helpers.zig");

test "Accuracy: VBLANK BEGINNING (AccuracyCoin)" {
    const cart = RAMBO.CartridgeType.load(testing.allocator, "tests/data/AccuracyCoin.nes") catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    var h = try Harness.init();
    defer h.deinit();

    h.loadNromCartridge(cart);
    h.state.reset();
    h.state.ppu.warmup_complete = true;

    helpers.bootToMainMenu(&h);

    helpers.setupPpuTimingSuite(&h);

    // DEBUG: Check frame lengths with rendering disabled
    h.state.ppu.mask.show_bg = false;
    h.state.ppu.mask.show_sprites = false;
    h.state.rendering_enabled = false;
    h.state.clock.ppu_cycles = 0;
    h.state.frame_complete = false;
    h.state.odd_frame = false;

    const start0 = h.state.clock.ppu_cycles;
    while (!h.state.frame_complete) h.state.tick();
    const frame0_len = h.state.clock.ppu_cycles - start0;
    h.state.frame_complete = false;

    const start1 = h.state.clock.ppu_cycles;
    while (!h.state.frame_complete) h.state.tick();
    const frame1_len = h.state.clock.ppu_cycles - start1;

    std.debug.print("\nFrame lengths (rendering DISABLED):\n", .{});
    std.debug.print("  Frame 0: {} PPU cycles (expected 89342)\n", .{frame0_len});
    std.debug.print("  Frame 1: {} PPU cycles (expected 89342)\n", .{frame1_len});
    std.debug.print("  Drift per frame: {} % 3 = {}\n\n", .{frame0_len, frame0_len % 3});

    const result = helpers.runPpuTimingTest(&h, helpers.PpuTimingTest.vblank_beginning);
    const decoded = helpers.decodeResult(result);
    const expected_status = helpers.AccuracyStatus.pass;

    // Debug: Print individual iteration results
    std.debug.print("\nAccuracyCoin VBlank Beginning results:\n", .{});
    std.debug.print("Expected: $02, $02, $02, $02, $00, $01, $01\n", .{});
    std.debug.print("Actual:   ", .{});
    for (0..7) |i| {
        const byte = h.state.bus.ram[0x50 + i];
        std.debug.print("${X:0>2}", .{byte});
        if (i < 6) std.debug.print(", ", .{});
    }
    std.debug.print("\n", .{});
    std.debug.print("Result byte: ${X:0>2} (binary: {b:0>8})\n", .{result, result});

    if (decoded.status != expected_status) {
        helpers.reportAccuracyMismatch("VBlank beginning", result, expected_status, 0);
    }
    try testing.expectEqual(expected_status, decoded.status);
}
