//! Sprite Rendering Tests
//!
//! Tests PPU sprite rendering pipeline per nesdev.org specification.
//! References: docs/SPRITE-RENDERING-SPECIFICATION.md
//!
//! Sprite rendering pipeline:
//! - Cycles 257-320: Fetch sprite pattern data (8 cycles per sprite)
//! - Cycles 1-256: Render sprites from shift registers
//! - Priority system: Background vs sprite, sprite 0 hit detection

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const PpuType = RAMBO.PpuType;

// ============================================================================
// PATTERN ADDRESS CALCULATION TESTS (8×8 mode)
// ============================================================================

test "Sprite Rendering: 8×8 pattern address calculation" {
    var ppu = PpuType.init();
    ppu.ctrl.sprite_size = false; // 8×8 mode
    ppu.ctrl.sprite_pattern = false; // Pattern table at $0000

    // Sprite tile index = 0x42
    // Row 0 (first row of sprite)
    // Expected address: $0000 + (0x42 × 16) + 0 = $0420
    const tile_index: u8 = 0x42;
    const row: u8 = 0;

    // Note: This test will fail until sprite pattern address calculation is implemented
    // Expected implementation in Logic.getSpritePatternAddress()
    _ = tile_index;
    _ = row;

    // TODO: Uncomment when getSpritePatternAddress() is implemented
    // const addr_low = Logic.getSpritePatternAddress(tile_index, row, 0, ppu.ctrl.sprite_pattern, false);
    // try testing.expectEqual(@as(u16, 0x0420), addr_low);

    // const addr_high = Logic.getSpritePatternAddress(tile_index, row, 1, ppu.ctrl.sprite_pattern, false);
    // try testing.expectEqual(@as(u16, 0x0428), addr_high); // +8 for bitplane 1
}

test "Sprite Rendering: 8×8 pattern address with alternate pattern table" {
    var ppu = PpuType.init();
    ppu.ctrl.sprite_size = false; // 8×8 mode
    ppu.ctrl.sprite_pattern = true; // Pattern table at $1000

    // Tile index = 0x10, Row 5
    // Expected address: $1000 + (0x10 × 16) + 5 = $1105
    const tile_index: u8 = 0x10;
    const row: u8 = 5;

    _ = tile_index;
    _ = row;

    // TODO: Uncomment when implemented
    // const addr = Logic.getSpritePatternAddress(tile_index, row, 0, ppu.ctrl.sprite_pattern, false);
    // try testing.expectEqual(@as(u16, 0x1105), addr);
}

test "Sprite Rendering: 8×8 vertical flip" {
    var ppu = PpuType.init();
    ppu.ctrl.sprite_size = false; // 8×8 mode
    ppu.ctrl.sprite_pattern = false;

    // Tile index = 0x42, Row 0, Vertical flip = true
    // Flipped row = 7 - 0 = 7
    // Expected address: $0000 + (0x42 × 16) + 7 = $0427
    const tile_index: u8 = 0x42;
    const row: u8 = 0;
    const vertical_flip: bool = true;

    _ = tile_index;
    _ = row;
    _ = vertical_flip;

    // TODO: Uncomment when implemented
    // const addr = Logic.getSpritePatternAddress(tile_index, row, 0, ppu.ctrl.sprite_pattern, vertical_flip);
    // try testing.expectEqual(@as(u16, 0x0427), addr);
}

// ============================================================================
// PATTERN ADDRESS CALCULATION TESTS (8×16 mode)
// ============================================================================

test "Sprite Rendering: 8×16 pattern address calculation (top half)" {
    var ppu = PpuType.init();
    ppu.ctrl.sprite_size = true; // 8×16 mode

    // Tile index = 0x42 (bit 0 = 0, so pattern table $0000)
    // Row 3 (top half: rows 0-7)
    // Expected: Pattern table $0000, tile 0x42 (even), row 3
    // Address: $0000 + (0x42 × 16) + 3 = $0423
    const tile_index: u8 = 0x42;
    const row: u8 = 3;

    _ = tile_index;
    _ = row;

    // TODO: Uncomment when implemented
    // const addr = Logic.getSprite16PatternAddress(tile_index, row, 0, false);
    // try testing.expectEqual(@as(u16, 0x0423), addr);
}

test "Sprite Rendering: 8×16 pattern address calculation (bottom half)" {
    var ppu = PpuType.init();
    ppu.ctrl.sprite_size = true; // 8×16 mode

    // Tile index = 0x42 (bit 0 = 0, so pattern table $0000)
    // Row 10 (bottom half: rows 8-15)
    // Expected: Pattern table $0000, tile 0x43 (0x42 + 1), row 2 (10 & 7)
    // Address: $0000 + (0x43 × 16) + 2 = $0432
    const tile_index: u8 = 0x42;
    const row: u8 = 10;

    _ = tile_index;
    _ = row;

    // TODO: Uncomment when implemented
    // const addr = Logic.getSprite16PatternAddress(tile_index, row, 0, false);
    // try testing.expectEqual(@as(u16, 0x0432), addr);
}

test "Sprite Rendering: 8×16 pattern table from tile bit 0" {
    var ppu = PpuType.init();
    ppu.ctrl.sprite_size = true; // 8×16 mode

    // Tile index = 0x43 (bit 0 = 1, so pattern table $1000)
    // Row 0 (top half)
    // Expected: Pattern table $1000, tile 0x42 (0x43 & 0xFE), row 0
    // Address: $1000 + (0x42 × 16) + 0 = $1420
    const tile_index: u8 = 0x43;
    const row: u8 = 0;

    _ = tile_index;
    _ = row;

    // TODO: Uncomment when implemented
    // const addr = Logic.getSprite16PatternAddress(tile_index, row, 0, false);
    // try testing.expectEqual(@as(u16, 0x1420), addr);
}

test "Sprite Rendering: 8×16 vertical flip" {
    var ppu = PpuType.init();
    ppu.ctrl.sprite_size = true; // 8×16 mode

    // Tile index = 0x42, Row 0, Vertical flip = true
    // Flipped row = 15 - 0 = 15
    // Row 15 is in bottom half, row 7 within tile
    // Expected: Pattern table $0000, tile 0x43, row 7
    // Address: $0000 + (0x43 × 16) + 7 = $0437
    const tile_index: u8 = 0x42;
    const row: u8 = 0;
    const vertical_flip: bool = true;

    _ = tile_index;
    _ = row;
    _ = vertical_flip;

    // TODO: Uncomment when implemented
    // const addr = Logic.getSprite16PatternAddress(tile_index, row, 0, vertical_flip);
    // try testing.expectEqual(@as(u16, 0x0437), addr);
}

// ============================================================================
// SPRITE SHIFT REGISTER TESTS
// ============================================================================

test "Sprite Rendering: Shift register pixel extraction" {
    var ppu = PpuType.init();
    ppu.mask.show_sprites = true;

    // Set up sprite 0 in secondary OAM
    // Y=50, Tile=0x00, Attr=0x00 (palette 0, no flip), X=100
    ppu.secondary_oam[0] = 50; // Y
    ppu.secondary_oam[1] = 0x00; // Tile
    ppu.secondary_oam[2] = 0x00; // Attributes (palette 0, priority 0, no flip)
    ppu.secondary_oam[3] = 100; // X

    // TODO: This test will fail until sprite shift registers are implemented
    // Expected: Extract 2-bit pattern from shift registers
    // Pattern 0b01 (color 1) → Palette index = (0 << 2) | 1 = 0x11

}

test "Sprite Rendering: Horizontal flip" {
    var ppu = PpuType.init();
    ppu.mask.show_sprites = true;

    // Set up sprite with horizontal flip
    ppu.secondary_oam[0] = 50; // Y
    ppu.secondary_oam[1] = 0x00; // Tile
    ppu.secondary_oam[2] = 0x01; // Attributes (horizontal flip = bit 0)
    ppu.secondary_oam[3] = 100; // X

    // TODO: Verify horizontal flip reverses pixel order
}

// ============================================================================
// SPRITE PRIORITY TESTS
// ============================================================================

test "Sprite Rendering: Priority 0 (sprite in front)" {
    var ppu = PpuType.init();
    ppu.mask.show_sprites = true;
    ppu.mask.show_bg = true;

    // Set up sprite with priority 0 (front)
    ppu.secondary_oam[0] = 50;
    ppu.secondary_oam[1] = 0x00;
    ppu.secondary_oam[2] = 0x00; // Priority 0 (bit 5 = 0)
    ppu.secondary_oam[3] = 100;

    // TODO: When both sprite and background are non-transparent,
    // sprite with priority 0 should be rendered (not background)
}

test "Sprite Rendering: Priority 1 (sprite behind background)" {
    var ppu = PpuType.init();
    ppu.mask.show_sprites = true;
    ppu.mask.show_bg = true;

    // Set up sprite with priority 1 (behind)
    ppu.secondary_oam[0] = 50;
    ppu.secondary_oam[1] = 0x00;
    ppu.secondary_oam[2] = 0x20; // Priority 1 (bit 5 = 1)
    ppu.secondary_oam[3] = 100;

    // TODO: When both sprite and background are non-transparent,
    // background should be rendered (sprite hidden behind)
}

test "Sprite Rendering: Sprite wins when background transparent" {
    var ppu = PpuType.init();
    ppu.mask.show_sprites = true;
    ppu.mask.show_bg = true;

    // Set up sprite with priority 1 (behind)
    ppu.secondary_oam[0] = 50;
    ppu.secondary_oam[1] = 0x00;
    ppu.secondary_oam[2] = 0x20; // Priority 1
    ppu.secondary_oam[3] = 100;

    // TODO: Even with priority 1, sprite should render when background is transparent (color 0)
}

test "Sprite Rendering: Background wins when sprite transparent" {
    var ppu = PpuType.init();
    ppu.mask.show_sprites = true;
    ppu.mask.show_bg = true;

    // Set up sprite
    ppu.secondary_oam[0] = 50;
    ppu.secondary_oam[1] = 0x00;
    ppu.secondary_oam[2] = 0x00; // Priority 0
    ppu.secondary_oam[3] = 100;

    // TODO: When sprite pixel is transparent (pattern 0), background should render
}

test "Sprite Rendering: Sprite 0-7 priority order" {
    var ppu = PpuType.init();
    ppu.mask.show_sprites = true;

    // Place 3 overlapping sprites at same position
    // Sprite 0 (highest priority)
    ppu.secondary_oam[0] = 50;
    ppu.secondary_oam[1] = 0x00;
    ppu.secondary_oam[2] = 0x00;
    ppu.secondary_oam[3] = 100;

    // Sprite 1 (medium priority)
    ppu.secondary_oam[4] = 50;
    ppu.secondary_oam[5] = 0x01;
    ppu.secondary_oam[6] = 0x00;
    ppu.secondary_oam[7] = 100;

    // Sprite 2 (lowest priority)
    ppu.secondary_oam[8] = 50;
    ppu.secondary_oam[9] = 0x02;
    ppu.secondary_oam[10] = 0x00;
    ppu.secondary_oam[11] = 100;

    // TODO: Sprite 0 should render (lowest index = highest priority)
}

// ============================================================================
// PALETTE TESTS
// ============================================================================

test "Sprite Rendering: Sprite palette selection" {
    var ppu = PpuType.init();
    ppu.mask.show_sprites = true;

    // Sprite with palette 0 (bits 6-7 = 0b00)
    ppu.secondary_oam[0] = 50;
    ppu.secondary_oam[1] = 0x00;
    ppu.secondary_oam[2] = 0x00; // Palette 0
    ppu.secondary_oam[3] = 100;

    // TODO: Sprite pixels should use palette $3F10-$3F13
}

test "Sprite Rendering: Sprite palette 1-3" {
    var ppu = PpuType.init();
    ppu.mask.show_sprites = true;

    // Sprite with palette 3 (bits 6-7 = 0b11)
    ppu.secondary_oam[0] = 50;
    ppu.secondary_oam[1] = 0x00;
    ppu.secondary_oam[2] = 0xC0; // Palette 3 (bits 6-7 = 0b11)
    ppu.secondary_oam[3] = 100;

    // TODO: Sprite pixels should use palette $3F1C-$3F1F
}

// ============================================================================
// SPRITE FETCHING TIMING TESTS
// ============================================================================

test "Sprite Rendering: Sprite fetch occurs cycles 257-320" {
    var ppu = PpuType.init();
    ppu.mask.show_sprites = true;

    // Place sprite in secondary OAM
    ppu.secondary_oam[0] = 50;
    ppu.secondary_oam[1] = 0x42;
    ppu.secondary_oam[2] = 0x00;
    ppu.secondary_oam[3] = 100;

    // Position at scanline 50, dot 256 (just before sprite fetch)
    ppu.scanline = 50;
    ppu.dot = 256;

    // TODO: Verify sprite pattern data is fetched during cycles 257-320
    // 8 cycles per sprite (garbage NT, garbage NT, pattern low, pattern high)
}

test "Sprite Rendering: 8 sprites fetched per scanline" {
    var ppu = PpuType.init();
    ppu.mask.show_sprites = true;

    // Fill secondary OAM with 8 sprites
    for (0..8) |i| {
        ppu.secondary_oam[i * 4 + 0] = 50; // Y
        ppu.secondary_oam[i * 4 + 1] = @intCast(i); // Tile (unique per sprite)
        ppu.secondary_oam[i * 4 + 2] = 0x00; // Attributes
        ppu.secondary_oam[i * 4 + 3] = @intCast(i * 8); // X (spread out)
    }

    // TODO: Verify all 8 sprites are fetched (64 cycles: 8 sprites × 8 cycles)
}

test "Sprite Rendering: Sprite fetch with <8 sprites" {
    var ppu = PpuType.init();
    ppu.mask.show_sprites = true;

    // Only 3 sprites in secondary OAM
    for (0..3) |i| {
        ppu.secondary_oam[i * 4 + 0] = 50;
        ppu.secondary_oam[i * 4 + 1] = @intCast(i);
        ppu.secondary_oam[i * 4 + 2] = 0x00;
        ppu.secondary_oam[i * 4 + 3] = @intCast(i * 8);
    }

    // Fill remaining with $FF (empty)
    for (3..8) |i| {
        ppu.secondary_oam[i * 4 + 0] = 0xFF;
        ppu.secondary_oam[i * 4 + 1] = 0xFF;
        ppu.secondary_oam[i * 4 + 2] = 0xFF;
        ppu.secondary_oam[i * 4 + 3] = 0xFF;
    }

    // TODO: Verify fetch still occurs for all 8 slots (using $FF bytes for empty sprites)
}

// ============================================================================
// SPRITE RENDERING OUTPUT TESTS
// ============================================================================

test "Sprite Rendering: Sprite renders at correct X position" {
    var ppu = PpuType.init();
    ppu.mask.show_sprites = true;

    // Sprite at X=100
    ppu.secondary_oam[0] = 50; // Y
    ppu.secondary_oam[1] = 0x00; // Tile
    ppu.secondary_oam[2] = 0x00; // Attributes
    ppu.secondary_oam[3] = 100; // X

    // TODO: Sprite should start rendering at pixel X=100 and continue for 8 pixels
}

test "Sprite Rendering: Sprite renders at correct Y position" {
    var ppu = PpuType.init();
    ppu.mask.show_sprites = true;

    // Sprite at Y=50
    ppu.secondary_oam[0] = 50; // Y
    ppu.secondary_oam[1] = 0x00; // Tile
    ppu.secondary_oam[2] = 0x00; // Attributes
    ppu.secondary_oam[3] = 100; // X

    // TODO: Sprite should render on scanlines 50-57 (8 scanlines for 8×8 sprite)
}

test "Sprite Rendering: Sprite X counter behavior" {
    var ppu = PpuType.init();
    ppu.mask.show_sprites = true;

    // Sprite at X=100
    ppu.secondary_oam[0] = 50;
    ppu.secondary_oam[1] = 0x00;
    ppu.secondary_oam[2] = 0x00;
    ppu.secondary_oam[3] = 100;

    // TODO: Verify X counter counts down from 100 to 0, then sprite becomes active
    // Active for 8 pixels (100-107), then sprite finishes
}

test "Sprite Rendering: Left column clipping" {
    var ppu = PpuType.init();
    ppu.mask.show_sprites = true;
    ppu.mask.show_sprites_left = false; // Hide sprites in leftmost 8 pixels

    // Sprite at X=4 (partially in left column)
    ppu.secondary_oam[0] = 50;
    ppu.secondary_oam[1] = 0x00;
    ppu.secondary_oam[2] = 0x00;
    ppu.secondary_oam[3] = 4;

    // TODO: Sprite pixels at X=4-7 should be hidden (left column clipping)
    // Sprite pixels at X=8-11 should render normally
}
