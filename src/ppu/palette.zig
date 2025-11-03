//! NES PPU Palette System
//!
//! Standard NTSC NES color palette mapping.
//! Based on NESdev Wiki specifications.
//!
//! The NES palette contains 64 colors, each represented as a 6-bit value.
//! Color encoding: (emphasis << 6) | (hue << 4) | value
//!
//! References:
//! - https://www.nesdev.org/wiki/PPU_palettes

/// Standard NTSC NES palette (64 colors as RGB888)
///
/// Index format: 0bEEVVVVHH where:
/// - EE: Emphasis bits (color tint, not used in base palette)
/// - VVVV: Value/brightness (0-3)
/// - HH: Hue (0-15, where 0 is gray)
///
/// Colors are in 0xRRGGBB format
pub const NES_PALETTE_RGB = [64]u32{
    // Row 0: Value 0 (darkest)
    0x545454, 0x001E74, 0x081090, 0x300088,
    0x440064, 0x5C0030, 0x540400, 0x3C1800,
    0x202A00, 0x083A00, 0x004000, 0x003C00,
    0x00323C, 0x000000, 0x000000, 0x000000,

    // Row 1: Value 1
    0x989698, 0x084CC4, 0x3032EC, 0x5C1EE4,
    0x8814B0, 0xA01464, 0x982220, 0x783C00,
    0x545A00, 0x287200, 0x087C00, 0x007628,
    0x006678, 0x000000, 0x000000, 0x000000,

    // Row 2: Value 2
    0xECEEEC, 0x4C9AEC, 0x787CEC, 0xB062EC,
    0xE454EC, 0xEC58B4, 0xEC6A64, 0xD48820,
    0xA0AA00, 0x74C400, 0x4CD020, 0x38CC6C,
    0x38B4CC, 0x3C3C3C, 0x000000, 0x000000,

    // Row 3: Value 3 (brightest)
    0xECEEEC, 0xA8CCEC, 0xBCBCEC, 0xD4B2EC,
    0xECAEEC, 0xECAED4, 0xECB4B0, 0xE4C490,
    0xCCD278, 0xB4DE78, 0xA8E290, 0x98E2B4,
    0xA0D6E4, 0xA0A2A0, 0x000000, 0x000000,
};

/// Convert RGB888 to BGRA8888 (add alpha channel)
/// Vulkan expects VK_FORMAT_B8G8R8A8_UNORM format where alpha is in the high byte
/// Input:  0x00RRGGBB (NES palette RGB)
/// Output: 0xAABBGGRR (BGRA with alpha in high byte)
pub fn rgbToRgba(rgb: u32) u32 {
    return rgb | 0xFF000000; // Add alpha 0xFF in high byte for BGRA format
}

/// Get NES color as BGRA8888 for Vulkan rendering
pub inline fn getNesColorRgba(nes_color_index: u8) u32 {
    return rgbToRgba(NES_PALETTE_RGB[nes_color_index & 0x3F]);
}

/// Palette RAM addressing with backdrop mirroring
///
/// The NES has special mirroring for palette backdrop colors:
/// $3F10, $3F14, $3F18, $3F1C mirror $3F00, $3F04, $3F08, $3F0C
///
/// This is already implemented in PPU.zig mirrorPaletteAddress(),
/// but documented here for reference.
pub const PALETTE_SIZE = 32;
pub const BG_PALETTE_START = 0x00;
pub const SPRITE_PALETTE_START = 0x10;
pub const BACKDROP_INDICES = [4]u8{ 0x00, 0x04, 0x08, 0x0C };

// ============================================================================
// Tests
// ============================================================================

const std = @import("std");
const testing = std.testing;

test "NES palette: color count" {
    try testing.expectEqual(64, NES_PALETTE_RGB.len);
}

test "NES palette: black color" {
    // Index $0D, $0E, $0F are all black
    try testing.expectEqual(@as(u32, 0x000000), NES_PALETTE_RGB[0x0D]);
    try testing.expectEqual(@as(u32, 0x000000), NES_PALETTE_RGB[0x0E]);
    try testing.expectEqual(@as(u32, 0x000000), NES_PALETTE_RGB[0x0F]);
}

test "NES palette: white color" {
    // Index $20 and $30 are white/near-white
    try testing.expectEqual(@as(u32, 0xECEEEC), NES_PALETTE_RGB[0x20]);
    try testing.expectEqual(@as(u32, 0xECEEEC), NES_PALETTE_RGB[0x30]);
}

test "NES palette: BGRA conversion" {
    const rgb = 0x123456;
    const bgra = rgbToRgba(rgb);
    // BGRA format: alpha in high byte
    // Input:  0x00123456 (RGB)
    // Output: 0xFF123456 (BGRA with alpha=0xFF)
    try testing.expectEqual(@as(u32, 0xFF123456), bgra);
}

test "NES palette: color index masking" {
    // Index should be masked to 6 bits (0-63)
    // Index 0x40 should wrap to 0x00
    try testing.expectEqual(
        getNesColorRgba(0x00),
        getNesColorRgba(0x40)
    );

    // Index 0xFF should wrap to 0x3F
    try testing.expectEqual(
        getNesColorRgba(0x3F),
        getNesColorRgba(0xFF)
    );
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
