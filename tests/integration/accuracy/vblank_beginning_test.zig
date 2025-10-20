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

    const result = helpers.runPpuTimingTest(&h, helpers.PpuTimingTest.vblank_beginning);
    const decoded = helpers.decodeResult(result);
    const expected_status = helpers.AccuracyStatus.pass;
    if (decoded.status != expected_status) {
        helpers.reportAccuracyMismatch("VBlank beginning", result, expected_status, 0);
    }
    try testing.expectEqual(expected_status, decoded.status);
}
