//! Sprite Rendering Tests
//!
//! Tests PPU sprite rendering pipeline per nesdev.org specification.
//! References: docs/architecture/ppu-sprites.md
//!
//! Sprite rendering pipeline:
//! - Cycles 257-320: Fetch sprite pattern data (8 cycles per sprite)
//! - Cycles 1-256: Render sprites from shift registers
//! - Priority system: Background vs sprite, sprite 0 hit detection

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const PpuType = RAMBO.PpuType;
const Logic = RAMBO.PpuLogic;

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

    // Test low bitplane
    const addr_low = Logic.getSpritePatternAddress(tile_index, row, 0, ppu.ctrl.sprite_pattern, false);
    try testing.expectEqual(@as(u16, 0x0420), addr_low);

    // Test high bitplane (+8 offset)
    const addr_high = Logic.getSpritePatternAddress(tile_index, row, 1, ppu.ctrl.sprite_pattern, false);
    try testing.expectEqual(@as(u16, 0x0428), addr_high); // +8 for bitplane 1
}

test "Sprite Rendering: 8×8 pattern address with alternate pattern table" {
    var ppu = PpuType.init();
    ppu.ctrl.sprite_size = false; // 8×8 mode
    ppu.ctrl.sprite_pattern = true; // Pattern table at $1000

    // Tile index = 0x10, Row 5
    // Expected address: $1000 + (0x10 × 16) + 5 = $1105
    const tile_index: u8 = 0x10;
    const row: u8 = 5;

    const addr = Logic.getSpritePatternAddress(tile_index, row, 0, ppu.ctrl.sprite_pattern, false);
    try testing.expectEqual(@as(u16, 0x1105), addr);
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

    const addr = Logic.getSpritePatternAddress(tile_index, row, 0, ppu.ctrl.sprite_pattern, vertical_flip);
    try testing.expectEqual(@as(u16, 0x0427), addr);
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

    const addr = Logic.getSprite16PatternAddress(tile_index, row, 0, false);
    try testing.expectEqual(@as(u16, 0x0423), addr);
}

test "Sprite Rendering: 8×16 pattern address calculation (bottom half)" {
    var ppu = PpuType.init();
    ppu.ctrl.sprite_size = true; // 8×16 mode

    // Tile index = 0x42 (bit 0 = 0, so pattern table $0000)
    // Row 10 (bottom half: rows 8-15)
    // Expected: Pattern table $0000, tile 0x43 (0x42 + 1), row 2 (10 % 8)
    // Address: $0000 + (0x43 × 16) + 2 = $0432
    const tile_index: u8 = 0x42;
    const row: u8 = 10;

    const addr = Logic.getSprite16PatternAddress(tile_index, row, 0, false);
    try testing.expectEqual(@as(u16, 0x0432), addr);
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

    const addr = Logic.getSprite16PatternAddress(tile_index, row, 0, false);
    try testing.expectEqual(@as(u16, 0x1420), addr);
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

    const addr = Logic.getSprite16PatternAddress(tile_index, row, 0, vertical_flip);
    try testing.expectEqual(@as(u16, 0x0437), addr);
}

// ============================================================================
// SPRITE SHIFT REGISTER TESTS
// ============================================================================

test "Sprite Rendering: Sprite state initialization" {
    const ppu = PpuType.init();

    // Verify sprite state is properly initialized
    try testing.expectEqual(@as(u8, 0), ppu.sprite_state.sprite_count);
    try testing.expect(!ppu.sprite_state.sprite_0_present);
    try testing.expectEqual(@as(u8, 0xFF), ppu.sprite_state.sprite_0_index);

    // Verify all shift registers start at 0
    for (ppu.sprite_state.pattern_shift_lo) |byte| {
        try testing.expectEqual(@as(u8, 0), byte);
    }
    for (ppu.sprite_state.pattern_shift_hi) |byte| {
        try testing.expectEqual(@as(u8, 0), byte);
    }

    // Verify all X counters start at 0
    for (ppu.sprite_state.x_counters) |counter| {
        try testing.expectEqual(@as(u8, 0), counter);
    }

    // Verify all attributes start at 0
    for (ppu.sprite_state.attributes) |attr| {
        try testing.expectEqual(@as(u8, 0), attr);
    }
}

test "Sprite Rendering: Horizontal flip bit reversal" {
    // Test reverseBits function used for horizontal flip

    // Test 1: All zeros
    try testing.expectEqual(@as(u8, 0x00), Logic.reverseBits(0x00));

    // Test 2: All ones
    try testing.expectEqual(@as(u8, 0xFF), Logic.reverseBits(0xFF));

    // Test 3: 0b10000000 -> 0b00000001
    try testing.expectEqual(@as(u8, 0x01), Logic.reverseBits(0x80));

    // Test 4: 0b00000001 -> 0b10000000
    try testing.expectEqual(@as(u8, 0x80), Logic.reverseBits(0x01));

    // Test 5: 0b10110001 -> 0b10001101
    try testing.expectEqual(@as(u8, 0b10001101), Logic.reverseBits(0b10110001));

    // Test 6: 0b11110000 -> 0b00001111
    try testing.expectEqual(@as(u8, 0x0F), Logic.reverseBits(0xF0));

    // Test 7: Pattern data reversal
    // Original: 0b11000011 -> Reversed: 0b11000011 (palindrome)
    try testing.expectEqual(@as(u8, 0b11000011), Logic.reverseBits(0b11000011));
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

test "Sprite Rendering: Sprite attribute byte interpretation" {
    // Test attribute byte structure (PPH..SPP)
    // Bits 0-1: Palette (0-3)
    // Bit 5: Priority (0=front, 1=behind)
    // Bit 6: Horizontal flip
    // Bit 7: Vertical flip

    // Palette 0
    const attr0: u8 = 0x00;
    const palette0 = attr0 & 0x03;
    try testing.expectEqual(@as(u8, 0), palette0);

    // Palette 3
    const attr3: u8 = 0x03;
    const palette3 = attr3 & 0x03;
    try testing.expectEqual(@as(u8, 3), palette3);

    // Priority front (bit 5 = 0)
    const priority_front: u8 = 0x00;
    const is_behind_front = (priority_front & 0x20) != 0;
    try testing.expect(!is_behind_front);

    // Priority behind (bit 5 = 1)
    const priority_behind: u8 = 0x20;
    const is_behind_back = (priority_behind & 0x20) != 0;
    try testing.expect(is_behind_back);

    // Horizontal flip (bit 6)
    const h_flip: u8 = 0x40;
    const has_h_flip = (h_flip & 0x40) != 0;
    try testing.expect(has_h_flip);

    // Vertical flip (bit 7)
    const v_flip: u8 = 0x80;
    const has_v_flip = (v_flip & 0x80) != 0;
    try testing.expect(has_v_flip);

    // Combined: Palette 2, priority behind, h-flip, v-flip
    const combined: u8 = 0xE2; // 0b11100010
    const combined_palette = combined & 0x03;
    const combined_priority = (combined & 0x20) != 0;
    const combined_h_flip = (combined & 0x40) != 0;
    const combined_v_flip = (combined & 0x80) != 0;
    try testing.expectEqual(@as(u8, 2), combined_palette);
    try testing.expect(combined_priority);
    try testing.expect(combined_h_flip);
    try testing.expect(combined_v_flip);
}

test "Sprite Rendering: Sprite palette RAM address calculation" {
    // Sprite palettes are at $3F10-$3F1F (16 bytes, 4 palettes × 4 colors)
    // Formula: $3F10 + (palette_num × 4) + color_index
    // Note: Color 0 of each palette ($3F10, $3F14, $3F18, $3F1C) is transparent

    // Palette 0, Color 0 (transparent)
    const addr_p0_c0: u16 = 0x3F10 + (0 * 4) + 0;
    try testing.expectEqual(@as(u16, 0x3F10), addr_p0_c0);

    // Palette 0, Color 3
    const addr_p0_c3: u16 = 0x3F10 + (0 * 4) + 3;
    try testing.expectEqual(@as(u16, 0x3F13), addr_p0_c3);

    // Palette 1, Color 2
    const addr_p1_c2: u16 = 0x3F10 + (1 * 4) + 2;
    try testing.expectEqual(@as(u16, 0x3F16), addr_p1_c2);

    // Palette 2, Color 1
    const addr_p2_c1: u16 = 0x3F10 + (2 * 4) + 1;
    try testing.expectEqual(@as(u16, 0x3F19), addr_p2_c1);

    // Palette 3, Color 3 (last sprite palette entry)
    const addr_p3_c3: u16 = 0x3F10 + (3 * 4) + 3;
    try testing.expectEqual(@as(u16, 0x3F1F), addr_p3_c3);

    // Verify palette index extraction from palette RAM address
    const test_addr: u16 = 0x3F1A; // Palette 2, Color 2
    const palette_offset = test_addr - 0x3F10; // 10
    const palette_num = palette_offset / 4; // 2
    const color_index = palette_offset % 4; // 2
    try testing.expectEqual(@as(u16, 2), palette_num);
    try testing.expectEqual(@as(u16, 2), color_index);
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
