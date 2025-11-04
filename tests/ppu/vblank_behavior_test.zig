//! VBlank Flag Behavior Tests
//!
//! Comprehensive tests for VBlank flag lifecycle and timing.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

// Helper to read the VBlank flag from the $2002 PPUSTATUS register
fn isVBlankSet(h: *Harness) bool {
    const status_byte = h.state.busRead(0x2002);
    return (status_byte & 0x80) != 0;
}

test "VBlank: Flag sets at scanline 241 dot 1" {
    var h = try Harness.init();
    defer h.deinit();
    h.state.ppu.warmup_complete = true; // Skip PPU warmup for VBlank timing tests

    // Seek to just before VBlank sets
    h.seekTo(241, 0);
    try testing.expect(!isVBlankSet(&h));

    // Tick to the exact cycle where VBlank sets
    h.tick(1);

    // CORRECTED: Reading AFTER tick() completes sees flag SET
    // Per nesdev.org: "Reading on the same PPU clock...reads it as set"
    // Note: This test calls tick() then reads, so the VBlank timestamp
    // has already been applied. True same-cycle reads (CPU reading during
    // the cycle via actual instruction execution) require integration tests.
    try testing.expect(isVBlankSet(&h));  // Sees SET after tick completes
    // NOTE: This read clears the flag!

    // One cycle later, flag has been cleared by the previous read
    h.tick(1);
    try testing.expect(!isVBlankSet(&h));  // CLEAR (was cleared by previous read)
}

test "VBlank: Flag clears at scanline -1 dot 1 (pre-render)" {
    var h = try Harness.init();
    defer h.deinit();
    h.state.ppu.warmup_complete = true; // Skip PPU warmup for VBlank timing tests

    // FIXED: Must advance through a full frame first to set VBlank
    // Starting from -1:0, seek to 0:0 (goes through 241:1 where VBlank sets)
    h.seekTo(0, 0);

    // Now seek to just before VBlank clears (scanline -1, dot 0)
    // Ensure we have not performed a prior $2002 read that clears the flag
    h.seekTo(-1, 0);
    try testing.expect(isVBlankSet(&h)); // Still set at -1,0

    // Tick to the exact clear cycle
    h.tick(1);

    // VBlank flag MUST be cleared by timing
    try testing.expect(!isVBlankSet(&h));
}

test "VBlank: Flag is not set during visible scanlines" {
    var h = try Harness.init();
    defer h.deinit();
    h.state.ppu.warmup_complete = true; // Skip PPU warmup for VBlank timing tests

    // Check a few points during the visible frame
    h.seekTo(100, 150);
    try testing.expect(!isVBlankSet(&h));

    h.seekTo(200, 50);
    try testing.expect(!isVBlankSet(&h));
}

test "VBlank: Multiple frame transitions" {
    var h = try Harness.init();
    defer h.deinit();
    h.state.ppu.warmup_complete = true; // Skip PPU warmup for VBlank timing tests

    var vblank_set_count: usize = 0;
    // FIXED: Check ledger state directly instead of reading $2002
    // Reading $2002 has side effect of clearing the flag, which prevents
    // detecting 0→1 transitions when reading every cycle
    var last_vblank = h.state.vblank_ledger.isFlagVisible();

    // Run for 3 frames
    const cycles_per_frame: usize = 89342;
    var cycles: usize = 0;
    while (cycles < cycles_per_frame * 3) : (cycles += 1) {
        h.tick(1);
        // FIXED: Check ledger directly (no side effects)
        const current_vblank = h.state.vblank_ledger.isFlagVisible();
        if (!last_vblank and current_vblank) {
            vblank_set_count += 1;
        }
        last_vblank = current_vblank;
    }

    // Should have seen VBlank set 3 times
    try testing.expectEqual(@as(usize, 3), vblank_set_count);
}
