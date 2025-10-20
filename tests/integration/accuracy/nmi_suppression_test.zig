//! AccuracyCoin Accuracy Test: NMI SUPPRESSION
//!
//! This test verifies that reading $2002 on the exact cycle VBlank is set
//! suppresses the NMI while still clearing the VBlank flag.
//!
//! Race condition: Reading $2002 at scanline 241 dot 1 (same cycle VBlank sets)
//! Expected: Flag clears BUT NMI doesn't fire
//!
//! Test Entry Point: 0xB5ED
//! Result Address: $0454 (result_NMI_Suppression)
//! Expected: $00 = PASS (NMI correctly suppressed)
//! ROM Screenshot (2025-10-19): FAIL 1

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;
const helpers = @import("helpers.zig");

test "Accuracy: NMI SUPPRESSION (AccuracyCoin)" {
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

    const result = helpers.runPpuTimingTest(&h, helpers.PpuTimingTest.nmi_suppression);
    const decoded = helpers.decodeResult(result);
    const expected_status = helpers.AccuracyStatus.pass;
    if (decoded.status != expected_status) {
        helpers.reportAccuracyMismatch("NMI suppression", result, expected_status, 0);
    }
    try testing.expectEqual(expected_status, decoded.status);
}
