//! AccuracyCoin Accuracy Test: NMI AT VBLANK END
//!
//! This test verifies NMI behavior when VBlank ends (scanline 261 dot 1).
//! Tests edge cases around VBlank flag clearing by timing.
//!
//! Test Entry Point: 0xB63B
//! Result Address: $0455 (result_NMI_VBL_End)
//! Expected: $00 = PASS (VBlank end edge case correct)
//! ROM Screenshot (2025-10-19): FAIL 1

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;
const helpers = @import("helpers.zig");

test "Accuracy: NMI AT VBLANK END (AccuracyCoin)" {
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

    const result = helpers.runPpuTimingTest(&h, helpers.PpuTimingTest.nmi_vblank_end);
    const decoded = helpers.decodeResult(result);
    const expected_status = helpers.AccuracyStatus.pass;
    if (decoded.status != expected_status) {
        helpers.reportAccuracyMismatch("NMI at VBlank end", result, expected_status, 0);
    }
    try testing.expectEqual(expected_status, decoded.status);
}
