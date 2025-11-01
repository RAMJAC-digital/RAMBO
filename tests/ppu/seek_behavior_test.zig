//! Test to verify Harness seekTo behavior

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

// Helper to read the VBlank flag from the $2002 PPUSTATUS register
fn isVBlankSet(h: *Harness) bool {
    const status_byte = h.state.busRead(0x2002);
    return (status_byte & 0x80) != 0;
}

test "Seek Behavior: seekTo correctly positions emulator" {
    var h = try Harness.init();
    defer h.deinit();

    // --- Test 1: Seek to before VBlank ---
    h.seekTo(241, 0);
    try testing.expectEqual(@as(u16, 241), h.state.clock.scanline());
    try testing.expectEqual(@as(u16, 0), h.state.clock.dot());
    try testing.expect(!isVBlankSet(&h));

    // --- Test 2: Seek to exact VBlank set cycle ---
    h.seekTo(241, 1);
    try testing.expectEqual(@as(u16, 241), h.state.clock.scanline());
    try testing.expectEqual(@as(u16, 1), h.state.clock.dot());
    // CORRECTED: Same-cycle read sees CLEAR (hardware sub-cycle timing)
    try testing.expect(!isVBlankSet(&h));  // CORRECTED

    // One cycle later, flag is visible
    h.tick(1);
    try testing.expect(isVBlankSet(&h));

    // --- Test 3: Seek to after VBlank clear ---
    h.seekTo(261, 2);
    try testing.expectEqual(@as(u16, 261), h.state.clock.scanline());
    try testing.expectEqual(@as(u16, 2), h.state.clock.dot());
    try testing.expect(!isVBlankSet(&h));
}
