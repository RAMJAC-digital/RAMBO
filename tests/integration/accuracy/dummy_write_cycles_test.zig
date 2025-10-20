//! AccuracyCoin Accuracy Test: DUMMY WRITE CYCLES
//!
//! This test verifies Read-Modify-Write instructions write the original value back
//! before writing the modified value (dummy write cycle).
//!
//! All RMW instructions (ASL, LSR, ROL, ROR, INC, DEC) must:
//! 1. Read value from address
//! 2. Write ORIGINAL value back (dummy write)
//! 3. Write MODIFIED value
//!
//! Test Entry Point: 0xA318
//! Result Address: $0407 (result_DummyWrites)
//! Expected: $00 = PASS (RMW dummy writes work correctly)
//! ROM Screenshot: PASS

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;
const helpers = @import("helpers.zig");

test "Accuracy: DUMMY WRITE CYCLES (AccuracyCoin)" {
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

    const result = helpers.runCpuBehaviorTest(&h, helpers.CpuBehaviorTest.dummy_write_cycles);
    const decoded = helpers.decodeResult(result);
    const expected_status = helpers.AccuracyStatus.pass;
    if (decoded.status != expected_status) {
        helpers.reportAccuracyMismatch("Dummy write cycles", result, expected_status, 0);
    }
    try testing.expectEqual(expected_status, decoded.status);
}
