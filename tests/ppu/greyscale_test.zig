//! PPU Greyscale Mode Tests
//!
//! Tests PPUMASK bit 0 (greyscale mode) implementation.
//! When enabled, color indices are masked with $30 to remove hue,
//! converting all colors to grayscale.
//!
//! Hardware reference: nesdev.org/wiki/PPU_palettes#Greyscale_mode

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const PpuState = RAMBO.PpuType;
const PpuLogic = RAMBO.Ppu.Logic;
const palette = RAMBO.PpuPalette;

// ============================================================================
// Basic Greyscale Mode Tests
// ============================================================================

test "Greyscale mode: disabled - colors pass through unchanged" {
    var state = PpuState.init();
    state.mask.greyscale = false;

    // Test a variety of color indices
    const test_colors = [_]u8{ 0x00, 0x0C, 0x1A, 0x2D, 0x30, 0x3F };

    for (test_colors) |color_index| {
        state.palette_ram[0] = color_index;
        const result = PpuLogic.getPaletteColor(&state, 0);
        const expected = palette.getNesColorRgba(color_index);

        try testing.expectEqual(expected, result);
    }
}

test "Greyscale mode: enabled - colors masked with $30" {
    var state = PpuState.init();
    state.mask.greyscale = true;

    // Populate delay buffer so getEffectiveMask() sees greyscale=true
    for (0..4) |i| {
        state.mask_delay_buffer[i] = state.mask;
    }

    // Test colors and their greyscale equivalents
    const test_cases = [_]struct { input: u8, expected: u8 }{
        // Colors in row 0 (value 0) → $00
        .{ .input = 0x00, .expected = 0x00 }, // Black → Black
        .{ .input = 0x01, .expected = 0x00 }, // Blue → Black
        .{ .input = 0x0C, .expected = 0x00 }, // Dark blue → Black
        .{ .input = 0x0D, .expected = 0x00 }, // Black → Black

        // Colors in row 1 (value 1) → $10
        .{ .input = 0x10, .expected = 0x10 }, // Light gray → Light gray
        .{ .input = 0x12, .expected = 0x10 }, // Light blue → Light gray
        .{ .input = 0x1A, .expected = 0x10 }, // Light green → Light gray

        // Colors in row 2 (value 2) → $20
        .{ .input = 0x20, .expected = 0x20 }, // White → White
        .{ .input = 0x22, .expected = 0x20 }, // Cyan → White
        .{ .input = 0x2D, .expected = 0x20 }, // Pink → White

        // Colors in row 3 (value 3) → $30
        .{ .input = 0x30, .expected = 0x30 }, // White → White
        .{ .input = 0x35, .expected = 0x30 }, // Light red → White
        .{ .input = 0x3F, .expected = 0x30 }, // White → White
    };

    for (test_cases) |case| {
        state.palette_ram[0] = case.input;
        const result = PpuLogic.getPaletteColor(&state, 0);
        const expected = palette.getNesColorRgba(case.expected);

        try testing.expectEqual(expected, result);
    }
}

test "Greyscale mode: hue bits removed, value bits preserved" {
    var state = PpuState.init();
    state.mask.greyscale = true;

    // Populate delay buffer so getEffectiveMask() sees greyscale=true
    for (0..4) |i| {
        state.mask_delay_buffer[i] = state.mask;
    }

    // All colors with same value (bits 4-5) should map to same greyscale
    // Value 0 (row 0): bits 4-5 = 00 → masked result = $00
    const row0_colors = [_]u8{ 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x0C, 0x0D };
    for (row0_colors) |color| {
        state.palette_ram[0] = color;
        const result = PpuLogic.getPaletteColor(&state, 0);
        const expected = palette.getNesColorRgba(0x00);
        try testing.expectEqual(expected, result);
    }

    // Value 1 (row 1): bits 4-5 = 01 → masked result = $10
    const row1_colors = [_]u8{ 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x1C, 0x1D };
    for (row1_colors) |color| {
        state.palette_ram[0] = color;
        const result = PpuLogic.getPaletteColor(&state, 0);
        const expected = palette.getNesColorRgba(0x10);
        try testing.expectEqual(expected, result);
    }

    // Value 2 (row 2): bits 4-5 = 10 → masked result = $20
    const row2_colors = [_]u8{ 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x2C, 0x2D };
    for (row2_colors) |color| {
        state.palette_ram[0] = color;
        const result = PpuLogic.getPaletteColor(&state, 0);
        const expected = palette.getNesColorRgba(0x20);
        try testing.expectEqual(expected, result);
    }

    // Value 3 (row 3): bits 4-5 = 11 → masked result = $30
    const row3_colors = [_]u8{ 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x3C, 0x3D };
    for (row3_colors) |color| {
        state.palette_ram[0] = color;
        const result = PpuLogic.getPaletteColor(&state, 0);
        const expected = palette.getNesColorRgba(0x30);
        try testing.expectEqual(expected, result);
    }
}

// ============================================================================
// Palette Index Boundary Tests
// ============================================================================

test "Greyscale mode: palette index masking with $1F" {
    var state = PpuState.init();
    state.mask.greyscale = true;

    // Populate delay buffer so getEffectiveMask() sees greyscale=true
    for (0..4) |i| {
        state.mask_delay_buffer[i] = state.mask;
    }

    // Palette indices are masked with $1F before accessing palette RAM
    // This test verifies greyscale works correctly with masked indices

    // Set up palette RAM with test pattern
    state.palette_ram[0x00] = 0x0C; // Blue
    state.palette_ram[0x10] = 0x2D; // Pink

    // Access background palette 0, color 0
    const result1 = PpuLogic.getPaletteColor(&state, 0x00);
    const expected1 = palette.getNesColorRgba(0x00); // 0x0C & 0x30 = 0x00
    try testing.expectEqual(expected1, result1);

    // Access sprite palette 0, color 0
    const result2 = PpuLogic.getPaletteColor(&state, 0x10);
    const expected2 = palette.getNesColorRgba(0x20); // 0x2D & 0x30 = 0x20
    try testing.expectEqual(expected2, result2);

    // Test with out-of-range index (should wrap via & 0x1F)
    state.palette_ram[0x1F] = 0x3A; // Light cyan
    const result3 = PpuLogic.getPaletteColor(&state, 0x1F);
    const expected3 = palette.getNesColorRgba(0x30); // 0x3A & 0x30 = 0x30
    try testing.expectEqual(expected3, result3);
}

test "Greyscale mode: all 64 NES colors map to 4 greyscale values" {
    var state = PpuState.init();
    state.mask.greyscale = true;

    // Populate delay buffer so getEffectiveMask() sees greyscale=true
    for (0..4) |i| {
        state.mask_delay_buffer[i] = state.mask;
    }

    // NES has 64 colors (6 bits: bits 0-5)
    // Greyscale mode maps them to 4 values based on bits 4-5 only
    const greyscale_values = [_]u8{ 0x00, 0x10, 0x20, 0x30 };

    for (0..64) |i| {
        const color_index: u8 = @intCast(i);
        state.palette_ram[0] = color_index;

        const result = PpuLogic.getPaletteColor(&state, 0);

        // Determine expected greyscale value
        const expected_index = color_index & 0x30;
        const expected = palette.getNesColorRgba(expected_index);

        try testing.expectEqual(expected, result);

        // Verify it's one of the 4 greyscale values
        const found = for (greyscale_values) |grey| {
            if (expected == palette.getNesColorRgba(grey)) break true;
        } else false;

        try testing.expect(found);
    }
}

// ============================================================================
// PPUMASK Register Integration Tests
// ============================================================================

test "Greyscale mode: PPUMASK bit 0 read/write" {
    var state = PpuState.init();

    // Initial state: greyscale disabled
    try testing.expectEqual(false, state.mask.greyscale);

    // Enable greyscale
    state.mask.greyscale = true;
    try testing.expectEqual(true, state.mask.greyscale);

    // Verify PPUMASK byte representation includes greyscale bit
    const mask_byte = state.mask.toByte();
    try testing.expectEqual(@as(u8, 0x01), mask_byte & 0x01);

    // Disable greyscale
    state.mask.greyscale = false;
    try testing.expectEqual(false, state.mask.greyscale);

    // Verify greyscale bit cleared
    const mask_byte2 = state.mask.toByte();
    try testing.expectEqual(@as(u8, 0x00), mask_byte2 & 0x01);
}

test "Greyscale mode: does not affect other PPUMASK bits" {
    var state = PpuState.init();

    // Set multiple PPUMASK bits
    state.mask.show_bg = true;
    state.mask.show_sprites = true;
    state.mask.show_bg_left = true;
    state.mask.emphasize_red = true;

    const mask_before = state.mask.toByte();

    // Enable greyscale
    state.mask.greyscale = true;

    const mask_after = state.mask.toByte();

    // Only bit 0 should change
    try testing.expectEqual(mask_before | 0x01, mask_after);

    // Verify other bits unchanged
    try testing.expectEqual(true, state.mask.show_bg);
    try testing.expectEqual(true, state.mask.show_sprites);
    try testing.expectEqual(true, state.mask.show_bg_left);
    try testing.expectEqual(true, state.mask.emphasize_red);
}

// ============================================================================
// Rendering Integration Tests
// ============================================================================

test "Greyscale mode: works with both background and sprite palettes" {
    var state = PpuState.init();
    state.mask.greyscale = true;

    // Populate delay buffer so getEffectiveMask() sees greyscale=true
    for (0..4) |i| {
        state.mask_delay_buffer[i] = state.mask;
    }

    // Background palette: $3F00-$3F0F
    state.palette_ram[0x00] = 0x0F; // Black
    state.palette_ram[0x05] = 0x1C; // Blue

    // Sprite palette: $3F10-$3F1F
    state.palette_ram[0x10] = 0x2D; // Pink
    state.palette_ram[0x15] = 0x38; // Yellow

    // Test background palette access
    const bg_result1 = PpuLogic.getPaletteColor(&state, 0x00);
    try testing.expectEqual(palette.getNesColorRgba(0x00), bg_result1);

    const bg_result2 = PpuLogic.getPaletteColor(&state, 0x05);
    try testing.expectEqual(palette.getNesColorRgba(0x10), bg_result2);

    // Test sprite palette access
    const sprite_result1 = PpuLogic.getPaletteColor(&state, 0x10);
    try testing.expectEqual(palette.getNesColorRgba(0x20), sprite_result1);

    const sprite_result2 = PpuLogic.getPaletteColor(&state, 0x15);
    try testing.expectEqual(palette.getNesColorRgba(0x30), sprite_result2);
}

test "Greyscale mode: runtime toggle affects rendering" {
    var state = PpuState.init();

    // Set up a colorful palette entry
    state.palette_ram[0] = 0x1C; // Blue (value 1, hue C)

    // Render without greyscale
    state.mask.greyscale = false;
    // Populate delay buffer for greyscale=false
    for (0..4) |i| {
        state.mask_delay_buffer[i] = state.mask;
    }
    const color_result = PpuLogic.getPaletteColor(&state, 0);
    const expected_color = palette.getNesColorRgba(0x1C);
    try testing.expectEqual(expected_color, color_result);

    // Enable greyscale and render again
    state.mask.greyscale = true;
    // Populate delay buffer for greyscale=true
    for (0..4) |i| {
        state.mask_delay_buffer[i] = state.mask;
    }
    const grey_result = PpuLogic.getPaletteColor(&state, 0);
    const expected_grey = palette.getNesColorRgba(0x10); // 0x1C & 0x30 = 0x10
    try testing.expectEqual(expected_grey, grey_result);

    // Verify results are different
    try testing.expect(color_result != grey_result);
}

// ============================================================================
// Edge Cases
// ============================================================================

test "Greyscale mode: already greyscale colors unchanged" {
    var state = PpuState.init();
    state.mask.greyscale = true;

    // Populate delay buffer for greyscale=true
    for (0..4) |i| {
        state.mask_delay_buffer[i] = state.mask;
    }

    // Colors that are already greyscale (hue = 0, bits 0-3 = 0)
    const greyscale_colors = [_]u8{ 0x00, 0x10, 0x20, 0x30 };

    for (greyscale_colors) |color| {
        state.palette_ram[0] = color;

        const result_enabled = PpuLogic.getPaletteColor(&state, 0);

        state.mask.greyscale = false;
        // Populate delay buffer for greyscale=false
        for (0..4) |i| {
            state.mask_delay_buffer[i] = state.mask;
        }
        const result_disabled = PpuLogic.getPaletteColor(&state, 0);

        // Greyscale colors should be identical with or without greyscale mode
        try testing.expectEqual(result_enabled, result_disabled);

        state.mask.greyscale = true; // Reset for next iteration
        // Populate delay buffer for greyscale=true
        for (0..4) |i| {
            state.mask_delay_buffer[i] = state.mask;
        }
    }
}

test "Greyscale mode: maximum color value" {
    var state = PpuState.init();
    state.mask.greyscale = true;

    // Populate delay buffer so getEffectiveMask() sees greyscale=true
    for (0..4) |i| {
        state.mask_delay_buffer[i] = state.mask;
    }

    // Color $3F is the maximum 6-bit value
    state.palette_ram[0] = 0x3F;

    const result = PpuLogic.getPaletteColor(&state, 0);
    const expected = palette.getNesColorRgba(0x30); // 0x3F & 0x30 = 0x30

    try testing.expectEqual(expected, result);
}

test "Greyscale mode: zero palette index special case" {
    var state = PpuState.init();
    state.mask.greyscale = true;

    // Populate delay buffer so getEffectiveMask() sees greyscale=true
    for (0..4) |i| {
        state.mask_delay_buffer[i] = state.mask;
    }

    // Palette index 0 is the universal backdrop color
    state.palette_ram[0] = 0x0D; // Black

    const result = PpuLogic.getPaletteColor(&state, 0);
    const expected = palette.getNesColorRgba(0x00); // 0x0D & 0x30 = 0x00

    try testing.expectEqual(expected, result);
}
