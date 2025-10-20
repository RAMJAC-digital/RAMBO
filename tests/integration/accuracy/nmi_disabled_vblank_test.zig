//! AccuracyCoin Accuracy Test: NMI DISABLED AT VBLANK
//!
//! This test verifies that NMI doesn't fire when disabled (PPUCTRL bit 7 = 0)
//! even when VBlank begins.
//!
//! Test Entry Point: 0xB66D
//! Result Address: $0456 (result_NMI_Disabled_VBL_Start)
//! Expected: $00 = PASS (NMI correctly doesn't fire)
//! ROM Screenshot (2025-10-19): FAIL 1

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;
const helpers = @import("helpers.zig");

test "Accuracy: NMI DISABLED AT VBLANK (AccuracyCoin)" {
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

    const result = helpers.runPpuTimingTest(&h, helpers.PpuTimingTest.nmi_disabled_vblank);
    const decoded = helpers.decodeResult(result);
    const expected_status = helpers.AccuracyStatus.pass;
    if (decoded.status != expected_status) {
        helpers.reportAccuracyMismatch("NMI disabled at VBlank", result, expected_status, 0);
    }
    try testing.expectEqual(expected_status, decoded.status);
}
