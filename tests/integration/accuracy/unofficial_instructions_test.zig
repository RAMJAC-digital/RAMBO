//! AccuracyCoin Accuracy Test: UNOFFICIAL INSTRUCTIONS
//!
//! This test verifies that unofficial/undocumented 6502 opcodes exist and
//! perform their expected operations. Tests ~20 different unofficial opcodes.
//!
//! Test Entry Point: 0xA557
//! Result Address: $0402 (result_UnofficialInstr)
//! Expected: $00 = PASS (all unofficial opcodes work)
//! ROM Screenshot: FAIL A (10 unofficial opcodes not implemented)

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;
const helpers = @import("helpers.zig");

test "Accuracy: UNOFFICIAL INSTRUCTIONS (AccuracyCoin)" {
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

    helpers.setupCpuBehaviorSuite(&h);

    const result = helpers.runCpuBehaviorTest(&h, helpers.CpuBehaviorTest.unofficial_instructions);

    // Expect PASS once all unofficial opcodes are implemented
    const decoded = helpers.decodeResult(result);
    const expected_status = helpers.AccuracyStatus.pass;
    if (decoded.status != expected_status) {
        helpers.reportAccuracyMismatch("Unofficial instructions", result, expected_status, 0);
    }
    try testing.expectEqual(expected_status, decoded.status);
}
