// Pre-render Scanline Sprite Fetch Test
//
// Tests that sprite fetching on the pre-render scanline (261) correctly handles
// stale secondary OAM data from the previous frame's scanline 239 evaluation.
//
// Hardware behavior (per nesdev.org/wiki/PPU_rendering):
// - Pre-render scanline (261) performs sprite fetches using stale secondary OAM
// - Secondary OAM contains sprite Y positions from scanline 239
// - When next_scanline = 0 (261 + 1) % 262, row calculation can wrap
// - Example: sprite_y=200, next_scanline=0 → row = 0 -% 200 = 56 (wraps)
// - Hardware doesn't crash - it uses wrapped row value to fetch pattern data

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

test "Pre-render scanline: Sprite fetch with wrapped row calculation" {
    var h = try Harness.init();
    defer h.deinit();

    // Enable rendering so pre-render scanline performs sprite fetches
    h.state.ppu.mask.show_bg = true;
    h.state.ppu.mask.show_sprites = true;

    // Set up sprite 0 in OAM with Y position that will cause wrapping
    // When fetched on pre-render scanline (261), next_scanline will be 0
    // row = 0 -% 200 = 56 for 8x8 sprite (out of valid range 0-7)
    h.state.ppu.oam[0] = 200; // Y position
    h.state.ppu.oam[1] = 0x42; // Tile index
    h.state.ppu.oam[2] = 0x80; // Attributes (vertical flip to trigger wrapping subtraction)
    h.state.ppu.oam[3] = 100; // X position

    // Populate secondary OAM as if sprite evaluation on scanline 239 found this sprite
    h.state.ppu.secondary_oam[0] = 200; // Y
    h.state.ppu.secondary_oam[1] = 0x42; // Tile
    h.state.ppu.secondary_oam[2] = 0x80; // Attr (vertical flip)
    h.state.ppu.secondary_oam[3] = 100; // X
    h.state.ppu.sprite_state.oam_source_index[0] = 0; // Sprite 0

    // Fill remaining secondary OAM with $FF (no sprite)
    for (4..32) |i| {
        h.state.ppu.secondary_oam[i] = 0xFF;
    }

    // Position at pre-render scanline (261), just before sprite fetch begins
    h.seekTo(261, 256);
    try testing.expectEqual(@as(u16, 261), h.state.ppu.scanline);

    // Advance through sprite fetch cycles (257-320)
    // This should NOT crash - hardware wraps row calculation naturally
    for (257..321) |_| {
        h.tick(1);
        try testing.expectEqual(@as(u16, 261), h.state.ppu.scanline);
    }

    // Verify we completed sprite fetch without crashing
    // The wrapped row value (56 for 8x8, or 241 for 8x16 with vflip) is used to
    // calculate pattern address, which may access arbitrary CHR data but shouldn't crash
    try testing.expect(true); // If we got here, no crash occurred
}

test "Pre-render scanline: 8x16 sprite with wrapped row calculation" {
    var h = try Harness.init();
    defer h.deinit();

    // Enable rendering and 8x16 sprite mode
    h.state.ppu.mask.show_bg = true;
    h.state.ppu.mask.show_sprites = true;
    h.state.ppu.ctrl.sprite_size = true; // 8x16 mode

    // Set up 8x16 sprite with Y position that causes wrapping
    // row = 0 -% 200 = 56, with vflip: 15 -% 56 = 215 (wraps)
    h.state.ppu.oam[0] = 200; // Y position
    h.state.ppu.oam[1] = 0x42; // Tile index
    h.state.ppu.oam[2] = 0x80; // Vertical flip
    h.state.ppu.oam[3] = 100; // X position

    // Populate secondary OAM
    h.state.ppu.secondary_oam[0] = 200;
    h.state.ppu.secondary_oam[1] = 0x42;
    h.state.ppu.secondary_oam[2] = 0x80;
    h.state.ppu.secondary_oam[3] = 100;
    h.state.ppu.sprite_state.oam_source_index[0] = 0;

    for (4..32) |i| {
        h.state.ppu.secondary_oam[i] = 0xFF;
    }

    // Position at pre-render scanline
    h.seekTo(261, 256);

    // Advance through sprite fetch - should not crash with 8x16 sprites
    for (257..321) |_| {
        h.tick(1);
    }

    try testing.expect(true); // No crash
}

test "Pre-render scanline: Multiple sprites with various Y positions" {
    var h = try Harness.init();
    defer h.deinit();

    h.state.ppu.mask.show_bg = true;
    h.state.ppu.mask.show_sprites = true;

    // Set up 8 sprites in secondary OAM with Y positions that might cause issues
    const test_y_positions = [8]u8{ 0, 50, 100, 150, 200, 220, 239, 255 };

    for (0..8) |i| {
        const oam_offset = i * 4;
        h.state.ppu.secondary_oam[oam_offset] = test_y_positions[i];
        h.state.ppu.secondary_oam[oam_offset + 1] = @intCast(i); // Tile index
        h.state.ppu.secondary_oam[oam_offset + 2] = if (i % 2 == 0) 0x80 else 0x00; // Alternate vflip
        h.state.ppu.secondary_oam[oam_offset + 3] = @intCast(i * 16); // X position
        h.state.ppu.sprite_state.oam_source_index[i] = @intCast(i);
    }

    // Position at pre-render scanline
    h.seekTo(261, 256);

    // Fetch all 8 sprites - none should crash regardless of Y position
    for (257..321) |_| {
        h.tick(1);
    }

    try testing.expect(true); // All sprites fetched successfully
}
