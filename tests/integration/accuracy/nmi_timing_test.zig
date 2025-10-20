//! AccuracyCoin Accuracy Test: NMI TIMING
//!
//! This test verifies the exact cycle timing of NMI execution.
//! The NMI handler is set up in RAM at $0700 with an INY instruction.
//! By enabling NMI at precise timings relative to VBlank and executing INY
//! instructions, the test determines exactly when the NMI fires.
//!
//! Expected Behavior:
//! - NMI fires 2 PPU cycles after VBlank begins
//! - The NMI occurs during the 2nd instruction after EnableNMI is written
//!
//! Test Entry Point: 0xB584
//! Result Address: $0453 (result_NMI_Timing)
//! Expected: $00 = PASS (NMI timing matches hardware)
//! ROM Screenshot (2025-10-19): FAIL 1

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;
const helpers = @import("helpers.zig");

test "Accuracy: NMI TIMING (AccuracyCoin)" {
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

    const result = helpers.runPpuTimingTest(&h, helpers.PpuTimingTest.nmi_timing);
    const decoded = helpers.decodeResult(result);
    const expected_status = helpers.AccuracyStatus.pass;
    if (decoded.status != expected_status) {
        helpers.reportAccuracyMismatch("NMI timing", result, expected_status, 0);
    }
    try testing.expectEqual(expected_status, decoded.status);
}
