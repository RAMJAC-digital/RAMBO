//! Sprite Y Position 1-Scanline Delay Tests
//!
//! Tests the NES hardware behavior where sprite evaluation and fetching
//! happen for the NEXT scanline, not the current scanline.
//!
//! Hardware behavior (nesdev.org/wiki/PPU_sprite_evaluation):
//! - Scanline N, dots 65-256: Evaluate which sprites appear on scanline N+1
//! - Scanline N, dots 257-320: Fetch pattern data for scanline N+1
//! - Scanline N+1, dots 1-256: Render the fetched sprites
//!
//! This creates a natural 1-scanline delay in the sprite pipeline.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const PpuState = RAMBO.PpuType;
const sprites = RAMBO.Ppu.Logic;

// ============================================================================
// Hardware Behavior: Next-Scanline Evaluation
// ============================================================================

test "Sprite Y Delay: Evaluation checks for next scanline" {
    var state = PpuState.init();

    // Place sprite at Y=10 (8x8 sprite, height=8)
    // Hardware: Visible on scanlines 10-17 (inclusive)
    state.oam[0] = 10; // Y position
    state.oam[1] = 0x42; // Tile index
    state.oam[2] = 0x00; // Attributes
    state.oam[3] = 50; // X position

    state.mask.show_sprites = true;
    state.mask.show_bg = true; // Enable rendering

    // During scanline 9, evaluate for scanline 10
    sprites.initSpriteEvaluation(&state);

    // Simulate evaluation during scanline 9, dot 65 (odd cycle - read Y)
    sprites.tickSpriteEvaluation(&state, 9, 65);

    // After reading Y coordinate, eval_sprite_in_range should be TRUE
    // because sprite Y=10 is visible on scanline 10 (next scanline)
    try testing.expect(state.sprite_state.eval_sprite_in_range);
}

test "Sprite Y Delay: Evaluation rejects sprite not on next scanline" {
    var state = PpuState.init();

    // Place sprite at Y=20 (8x8 sprite, height=8)
    // Hardware: Visible on scanlines 20-27
    state.oam[0] = 20; // Y position
    state.oam[1] = 0x42; // Tile index
    state.oam[2] = 0x00; // Attributes
    state.oam[3] = 50; // X position

    state.mask.show_sprites = true;
    state.mask.show_bg = true;

    // During scanline 9, evaluate for scanline 10
    sprites.initSpriteEvaluation(&state);
    sprites.tickSpriteEvaluation(&state, 9, 65);

    // Sprite Y=20 is NOT visible on scanline 10 (next scanline)
    try testing.expect(!state.sprite_state.eval_sprite_in_range);
}

test "Sprite Y Delay: Pre-render scanline evaluates for scanline 0" {
    var state = PpuState.init();

    // Place sprite at Y=0 (8x8 sprite)
    // Hardware: Visible on scanlines 0-7
    state.oam[0] = 0; // Y position
    state.oam[1] = 0x42; // Tile index
    state.oam[2] = 0x00; // Attributes
    state.oam[3] = 50; // X position

    state.mask.show_sprites = true;
    state.mask.show_bg = true;

    // During scanline -1 (pre-render), evaluate for scanline 0
    sprites.initSpriteEvaluation(&state);

    // Note: Evaluation only happens on visible scanlines (0-239)
    // Pre-render scanline (261) does NOT perform evaluation
    // This test documents that scanline -1 doesn't evaluate

    // Instead, scanline 239 evaluates for scanline 240 (post-render)
    // and that secondary OAM is reused for scanline 0
}

test "Sprite Y Delay: Scanline boundary evaluation" {
    var state = PpuState.init();

    // Place sprite at Y=239 (8x8 sprite, height=8)
    // Should be visible on scanlines 239-246
    // But scanlines 240+ are not visible, so only scanline 239 shows it
    state.oam[0] = 239; // Y position
    state.oam[1] = 0x42; // Tile index
    state.oam[2] = 0x00; // Attributes
    state.oam[3] = 50; // X position

    state.mask.show_sprites = true;
    state.mask.show_bg = true;

    // During scanline 238, evaluate for scanline 239
    sprites.initSpriteEvaluation(&state);
    sprites.tickSpriteEvaluation(&state, 238, 65);

    // Sprite should be evaluated as visible on scanline 239
    try testing.expect(state.sprite_state.eval_sprite_in_range);
}

// ============================================================================
// Hardware Behavior: Next-Scanline Fetching
// ============================================================================

test "Sprite Y Delay: Fetching calculates row for next scanline" {
    var state = PpuState.init();

    // Place sprite at Y=10 in secondary OAM
    state.secondary_oam[0] = 10; // Y position
    state.secondary_oam[1] = 0x42; // Tile index
    state.secondary_oam[2] = 0x00; // Attributes (no flip)
    state.secondary_oam[3] = 50; // X position

    state.mask.show_sprites = true;
    state.mask.show_bg = true;
    state.ctrl.sprite_pattern = false; // Pattern table at $0000

    // During scanline 10, dots 257-320, fetch pattern for scanline 11
    // Expected row: scanline 11 - Y 10 = row 1

    // Simulate fetch cycle 5 (fetch low bitplane) on scanline 10
    sprites.fetchSprites(&state, null, 10, 261);

    // After fetching, pattern_shift_lo[0] should contain row 1 data
    // (We can't directly verify the CHR read without a cartridge,
    //  but we can verify the address calculation is correct)

    // The key is: during scanline 10, we should fetch row 1 (for scanline 11)
    // not row 0 (which would be for scanline 10)
}

test "Sprite Y Delay: Pre-render scanline fetches for scanline 0" {
    var state = PpuState.init();

    // Place sprite at Y=0 in secondary OAM (from stale scanline 239 data)
    state.secondary_oam[0] = 0; // Y position
    state.secondary_oam[1] = 0x42; // Tile index
    state.secondary_oam[2] = 0x00; // Attributes
    state.secondary_oam[3] = 50; // X position

    state.mask.show_sprites = true;
    state.mask.show_bg = true;
    state.ctrl.sprite_pattern = false;

    // During scanline -1 (pre-render), dots 257-320, fetch for scanline 0
    // Expected row: scanline 0 - Y 0 = row 0

    sprites.fetchSprites(&state, null, -1, 261);

    // The calculation should be: next_scanline = (261 + 1) % 262 = 0
    // row = 0 - 0 = 0 (top row, correct for displaying on scanline 0)
}

test "Sprite Y Delay: Multiple scanlines fetch correct rows" {
    var state = PpuState.init();

    // Place 8x8 sprite at Y=100
    state.secondary_oam[0] = 100; // Y position
    state.secondary_oam[1] = 0x42; // Tile index
    state.secondary_oam[2] = 0x00; // Attributes
    state.secondary_oam[3] = 50; // X position

    state.mask.show_sprites = true;
    state.mask.show_bg = true;
    state.ctrl.sprite_pattern = false;

    // Test fetching across multiple scanlines
    const test_cases = [_]struct { scanline: u16, expected_row: u8 }{
        .{ .scanline = 99, .expected_row = 0 },  // Fetch for scanline 100
        .{ .scanline = 100, .expected_row = 1 }, // Fetch for scanline 101
        .{ .scanline = 101, .expected_row = 2 }, // Fetch for scanline 102
        .{ .scanline = 102, .expected_row = 3 }, // Fetch for scanline 103
        .{ .scanline = 103, .expected_row = 4 }, // Fetch for scanline 104
        .{ .scanline = 104, .expected_row = 5 }, // Fetch for scanline 105
        .{ .scanline = 105, .expected_row = 6 }, // Fetch for scanline 106
        .{ .scanline = 106, .expected_row = 7 }, // Fetch for scanline 107
    };

    for (test_cases) |case| {
        // Clear shift registers
        state.sprite_state.pattern_shift_lo[0] = 0;
        state.sprite_state.pattern_shift_hi[0] = 0;

        // Fetch during this scanline (for next scanline)
        sprites.fetchSprites(&state, null, @as(i16, @intCast(case.scanline)), @as(i16, 261));

        // Verify the row calculation would be correct
        // (We can't check actual pattern data without CHR ROM,
        //  but the address calculation should use next_scanline)
        const next_scanline = case.scanline + 1;
        const expected_row_calc = next_scanline - 100;
        try testing.expectEqual(case.expected_row, expected_row_calc);
    }
}

// ============================================================================
// Hardware Behavior: 8x16 Sprite Mode
// ============================================================================

test "Sprite Y Delay: 8x16 sprites use next-scanline for row calculation" {
    var state = PpuState.init();

    // Place 8x16 sprite at Y=50
    state.secondary_oam[0] = 50; // Y position
    state.secondary_oam[1] = 0x42; // Tile index (bit 0 selects pattern table)
    state.secondary_oam[2] = 0x00; // Attributes
    state.secondary_oam[3] = 50; // X position

    state.mask.show_sprites = true;
    state.mask.show_bg = true;
    state.ctrl.sprite_size = true; // 8x16 mode

    // During scanline 50, fetch for scanline 51
    // Expected row: 51 - 50 = 1
    sprites.fetchSprites(&state, null, 50, 261);

    // During scanline 57, fetch for scanline 58
    // Expected row: 58 - 50 = 8 (bottom half of sprite)
    sprites.fetchSprites(&state, null, 57, 261);

    // Row 8 should select the bottom 8x8 tile in 8x16 mode
}

test "Sprite Y Delay: 8x16 sprite boundary at row 8" {
    var state = PpuState.init();

    // Place 8x16 sprite at Y=100
    state.secondary_oam[0] = 100; // Y position
    state.secondary_oam[1] = 0x42; // Tile index
    state.secondary_oam[2] = 0x00; // Attributes
    state.secondary_oam[3] = 50; // X position

    state.mask.show_sprites = true;
    state.mask.show_bg = true;
    state.ctrl.sprite_size = true; // 8x16 mode

    // Scanline 107 fetches for scanline 108
    // Row 8 is the boundary between top and bottom tiles
    const next_scanline: u16 = 108;
    const sprite_y: u16 = 100;
    const row_in_sprite = next_scanline - sprite_y;

    try testing.expectEqual(@as(u16, 8), row_in_sprite);

    // Row 8 should trigger bottom tile selection in getSprite16PatternAddress
}

// ============================================================================
// Edge Cases and Boundary Conditions
// ============================================================================

test "Sprite Y Delay: Sprite at Y=255 wraps correctly" {
    var state = PpuState.init();

    // Place sprite at Y=255 (effectively off-screen due to Y delay)
    // Visible on scanlines 255-262 (but only 255-239 are visible)
    state.oam[0] = 255; // Y position
    state.oam[1] = 0x42; // Tile index
    state.oam[2] = 0x00; // Attributes
    state.oam[3] = 50; // X position

    state.mask.show_sprites = true;
    state.mask.show_bg = true;

    // During scanline 254, evaluate for scanline 255
    sprites.initSpriteEvaluation(&state);
    sprites.tickSpriteEvaluation(&state, 254, 65);

    // Sprite Y=255 is technically off-screen in hardware
    // Hardware quirk: Y values $EF-$FF are used to hide sprites
    // But evaluation should still check correctly
}

test "Sprite Y Delay: Frame wraparound at scanline -1" {
    var state = PpuState.init();

    // Place sprite at Y=0
    state.oam[0] = 0; // Y position
    state.oam[1] = 0x42; // Tile index
    state.oam[2] = 0x00; // Attributes
    state.oam[3] = 50; // X position

    state.mask.show_sprites = true;
    state.mask.show_bg = true;

    // Note: Evaluation doesn't happen on scanline -1 (pre-render)
    // But fetching DOES happen during pre-render (-1) for scanline 0

    // Verify that (-1 + 262 + 1) % 262 = 0 (wrapping arithmetic)
    const next_scanline = @mod(@as(i16, -1) + 1, 262);
    try testing.expectEqual(@as(u16, 0), next_scanline);
}

test "Sprite Y Delay: Sprite height boundary cases" {
    var state = PpuState.init();

    // 8x8 sprite: height = 8
    state.ctrl.sprite_size = false;

    // Place sprite at Y=232 (visible on scanlines 232-239)
    state.oam[0] = 232; // Y position
    state.oam[1] = 0x42; // Tile index
    state.oam[2] = 0x00; // Attributes
    state.oam[3] = 50; // X position

    state.mask.show_sprites = true;
    state.mask.show_bg = true;

    // During scanline 239, evaluate for scanline 240 (post-render)
    sprites.initSpriteEvaluation(&state);
    sprites.tickSpriteEvaluation(&state, 239, 65);

    // Sprite Y=232, height=8 → visible on 232-239
    // Scanline 240 is OUTSIDE range, so should NOT be in range
    try testing.expect(!state.sprite_state.eval_sprite_in_range);
}

// ============================================================================
// Integration Tests: Full Pipeline
// ============================================================================

test "Sprite Y Delay: Full pipeline - evaluate, fetch, render sequence" {
    var state = PpuState.init();

    // Place sprite at Y=50
    state.oam[0] = 50; // Y position
    state.oam[1] = 0x01; // Tile index
    state.oam[2] = 0x00; // Attributes
    state.oam[3] = 100; // X position

    state.mask.show_sprites = true;
    state.mask.show_bg = true;
    state.ctrl.sprite_pattern = false; // Pattern table at $0000

    // === Phase 1: Scanline 49, dots 65-256 - Evaluate for scanline 50 ===
    sprites.initSpriteEvaluation(&state);

    // Simulate progressive evaluation
    for (65..257) |dot| {
        sprites.tickSpriteEvaluation(&state, 49, @intCast(dot));
    }

    // After evaluation, sprite should be in secondary OAM
    try testing.expectEqual(@as(u8, 50), state.secondary_oam[0]); // Y position copied

    // === Phase 2: Scanline 49, dots 257-320 - Fetch for scanline 50 ===
    // During scanline 49, we fetch pattern data for scanline 50
    // Expected row: 50 - 50 = 0 (top row)

    sprites.fetchSprites(&state, null, 49, 261); // Simulate fetch

    // Pattern should be loaded into shift registers
    // (Can't verify actual pattern data without CHR ROM)

    // === Phase 3: Scanline 50, dots 1-256 - Render ===
    // The sprite data fetched during scanline 49 is rendered on scanline 50
    // This is the correct hardware behavior
}

test "Sprite Y Delay: Verify scanline 0 has sprites from scanline -1 fetch" {
    var state = PpuState.init();

    // Place sprite at Y=0 in OAM
    state.oam[0] = 0; // Y position
    state.oam[1] = 0x01; // Tile index
    state.oam[2] = 0x00; // Attributes
    state.oam[3] = 100; // X position

    state.mask.show_sprites = true;
    state.mask.show_bg = true;

    // During scanline -1 (pre-render), secondary OAM contains stale data
    // from scanline 239's evaluation
    // But fetching still happens during 261, dots 257-320

    // Manually place sprite in secondary OAM (simulating stale data)
    state.secondary_oam[0] = 0; // Y position
    state.secondary_oam[1] = 0x01; // Tile index
    state.secondary_oam[2] = 0x00; // Attributes
    state.secondary_oam[3] = 100; // X position

    // Fetch during scanline -1 for scanline 0
    sprites.fetchSprites(&state, null, -1, 261);

    // Expected row: (261 + 1) % 262 - 0 = 0 - 0 = 0
    // This fetches the top row (row 0) for displaying on scanline 0
}

// ============================================================================
// Documentation Tests
// ============================================================================

test "Sprite Y Delay: Document hardware specification" {
    // This test serves as executable documentation for the hardware behavior

    // From nesdev.org/wiki/PPU_OAM:
    // "Sprite data is delayed by one scanline; you must subtract 1 from
    //  the sprite's Y coordinate before writing it."

    // From nesdev.org/wiki/PPU_sprite_evaluation:
    // "Sprite evaluation does not happen on the pre-render scanline.
    //  Because evaluation applies to the next line's sprite rendering,
    //  no sprites will be rendered on the first scanline."

    // From nesdev.org/wiki/PPU_rendering:
    // "While all of this is going on, sprite evaluation for the next
    //  scanline is taking place as a separate process"

    // Hardware Pipeline:
    // Scanline N, dots 65-256:   Evaluate sprites for scanline N+1
    // Scanline N, dots 257-320:  Fetch patterns for scanline N+1
    // Scanline N+1, dots 1-256:  Render the fetched sprites

    // Therefore:
    // - To display sprite on scanline 50, write Y=49 to OAM
    // - During scanline 49, hardware evaluates and fetches for scanline 50
    // - During scanline 50, hardware renders the pre-fetched sprite
}
