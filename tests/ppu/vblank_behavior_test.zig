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

    // Seek to just before VBlank sets
    h.seekTo(241, 0);
    try testing.expect(!isVBlankSet(&h));

    // Tick to the exact cycle
    h.tick(1);

    // VBlank flag MUST be set
    try testing.expect(isVBlankSet(&h));
}

test "VBlank: Flag clears at scanline 261 dot 1" {
    var h = try Harness.init();
    defer h.deinit();

    // Seek to just before VBlank clears
    // Ensure we have not performed a prior $2002 read that clears the flag
    h.seekTo(261, 0);
    try testing.expect(isVBlankSet(&h)); // Still set at 261,0

    // Tick to the exact clear cycle
    h.tick(1);

    // VBlank flag MUST be cleared by timing
    try testing.expect(!isVBlankSet(&h));
}

test "VBlank: Flag is not set during visible scanlines" {
    var h = try Harness.init();
    defer h.deinit();

    // Check a few points during the visible frame
    h.seekTo(100, 150);
    try testing.expect(!isVBlankSet(&h));

    h.seekTo(200, 50);
    try testing.expect(!isVBlankSet(&h));
}

test "VBlank: Multiple frame transitions" {
    var h = try Harness.init();
    defer h.deinit();

    var vblank_set_count: usize = 0;
    var last_vblank = isVBlankSet(&h);

    // Run for 3 frames
    const cycles_per_frame: usize = 89342;
    var cycles: usize = 0;
    while (cycles < cycles_per_frame * 3) : (cycles += 1) {
        h.tick(1);
        const current_vblank = isVBlankSet(&h);
        if (!last_vblank and current_vblank) {
            vblank_set_count += 1;
        }
        last_vblank = current_vblank;
    }

    // Should have seen VBlank set 3 times
    try testing.expectEqual(@as(usize, 3), vblank_set_count);
}
