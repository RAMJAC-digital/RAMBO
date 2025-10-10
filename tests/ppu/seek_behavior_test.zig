//! Test to verify Harness seekToScanlineDot behavior
//!
//! Validates that seekToScanlineDot correctly positions at exact scanline.dot
//! and that VBlank flag behavior is correct at boundary conditions.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Harness = RAMBO.TestHarness.Harness;

test "Seek Behavior: Harness seekToScanlineDot(241,1) sets VBlank correctly" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;

    // Seek to scanline 241, dot 0 (just before VBlank)
    harness.seekToScanlineDot(241, 0);

    // Verify position
    try testing.expectEqual(@as(u16, 241), harness.getScanline());
    try testing.expectEqual(@as(u16, 0), harness.getDot());

    // VBlank should NOT be set (we're at dot 0, VBlank sets at dot 1)
    try testing.expect(!harness.state.vblank_ledger.isReadableFlagSet(harness.state.clock.ppu_cycles));

    // Now tick ONCE to advance to 241.1
    harness.state.tick();

    // Verify position advanced
    try testing.expectEqual(@as(u16, 241), harness.getScanline());
    try testing.expectEqual(@as(u16, 1), harness.getDot());

    // VBlank MUST be set at 241.1
    try testing.expect(harness.state.vblank_ledger.isReadableFlagSet(harness.state.clock.ppu_cycles));
}

test "Seek Behavior: Harness seekToScanlineDot(241,1) direct positioning" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;

    // Seek directly to 241.1 (where VBlank sets)
    harness.seekToScanlineDot(241, 1);

    // Verify exact position
    try testing.expectEqual(@as(u16, 241), harness.getScanline());
    try testing.expectEqual(@as(u16, 1), harness.getDot());

    // VBlank MUST be set
    try testing.expect(harness.state.vblank_ledger.isReadableFlagSet(harness.state.clock.ppu_cycles));
}