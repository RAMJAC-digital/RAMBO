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
    try testing.expectEqual(@as(i16, 241), h.state.ppu.scanline);
    try testing.expectEqual(@as(u16, 0), h.state.ppu.cycle);
    try testing.expect(!isVBlankSet(&h));

    // --- Test 2: Seek to past VBlank set cycle ---
    // VBlank sets at dot 1, so seek to dot 4 (past race window)
    h.seekTo(241, 4);
    try testing.expectEqual(@as(i16, 241), h.state.ppu.scanline);
    try testing.expectEqual(@as(u16, 4), h.state.ppu.cycle);
    // Past race window, flag should be visible
    try testing.expect(isVBlankSet(&h));

    // --- Test 3: Seek to after VBlank clear ---
    h.seekTo(-1, 2);
    try testing.expectEqual(@as(i16, -1), h.state.ppu.scanline);
    try testing.expectEqual(@as(u16, 2), h.state.ppu.cycle);
    // VBlank clears at scanline -1 dot 1, so at dot 2 it should be cleared
    try testing.expect(!isVBlankSet(&h));
}
