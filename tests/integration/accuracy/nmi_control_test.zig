//! AccuracyCoin Accuracy Test: NMI CONTROL
//!
//! This test verifies NMI enable/disable logic via PPUCTRL bit 7.
//! Tests 8 different scenarios of NMI behavior.
//!
//! Test Entry Point: 0xB515
//! Result Address: $0452 (result_NMI_Control)
//! Expected: $00 = PASS (All NMI control tests pass)
//! ROM Screenshot (2025-10-19): FAIL 7 (Subtest 7 fails)

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;
const helpers = @import("helpers.zig");

test "Accuracy: NMI CONTROL (AccuracyCoin)" {
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

    const result = helpers.runPpuTimingTest(&h, helpers.PpuTimingTest.nmi_control);
    const decoded = helpers.decodeResult(result);
    const expected_status = helpers.AccuracyStatus.pass;
    if (decoded.status != expected_status) {
        helpers.reportAccuracyMismatch("NMI control", result, expected_status, 0);
    }
    try testing.expectEqual(expected_status, decoded.status);
}
