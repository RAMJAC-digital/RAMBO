//! AccuracyCoin Accuracy Test: ALL NOP INSTRUCTIONS
//!
//! This test verifies that all unofficial NOP instruction variants are implemented correctly.
//! Unofficial NOPs must:
//! - Have the correct number of operands (2 or 3 bytes total)
//! - NOT update CPU flags
//! - NOT update memory
//! - NOT update registers (A, X, Y, SP)
//! - Perform dummy reads (which can have side effects like clearing VBlank flag)
//!
//! Tested NOP Opcodes:
//! - $04, $44, $64 (Zero Page - 2 bytes)
//! - $0C (Absolute - 3 bytes)
//! - $14, $34, $54, $74, $D4, $F4 (Zero Page,X - 2 bytes)
//! - $1C, $3C, $5C, $7C, $DC, $FC (Absolute,X - 3 bytes)
//! - $1A, $3A, $5A, $7A, $DA, $FA (Implied - 1 byte)
//! - $80, $82, $89, $C2, $E2 (Immediate - 2 bytes)
//!
//! Test Entry Point: 0xE4E3
//! Result Address: $047D (result_AllNOPs)
//! Expected: $00 = PASS (all NOP variants correct)
//! ROM Screenshot (2025-10-19): FAIL 1 (NOP operand count or behavior incorrect)

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;
const helpers = @import("helpers.zig");

test "Accuracy: ALL NOP INSTRUCTIONS (AccuracyCoin)" {
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

    const result = helpers.runCpuBehaviorTest(&h, helpers.CpuBehaviorTest.all_nop_instructions);
    const decoded = helpers.decodeResult(result);
    const expected_status = helpers.AccuracyStatus.pass;
    if (decoded.status != expected_status) {
        helpers.reportAccuracyMismatch("All NOP instructions", result, expected_status, 0);
    }
    try testing.expectEqual(expected_status, decoded.status);
}
