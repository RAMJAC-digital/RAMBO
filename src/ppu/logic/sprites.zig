//! PPU Sprite Rendering Logic
//!
//! Handles sprite evaluation, pattern fetching, and pixel rendering.
//! Supports both 8×8 and 8×16 sprite modes.

const StateModule = @import("../State.zig");
const PpuState = StateModule.PpuState;
const SpritePixel = StateModule.SpritePixel;
const AnyCartridge = @import("../../cartridge/mappers/registry.zig").AnyCartridge;
const memory = @import("memory.zig");

/// Get sprite pattern address for 8×8 sprites
/// Returns CHR ROM address for the specified sprite tile and row
pub fn getSpritePatternAddress(tile_index: u8, row: u8, bitplane: u1, pattern_table: bool, vertical_flip: bool) u16 {
    const flipped_row = if (vertical_flip) 7 - row else row;
    const pattern_table_base: u16 = if (pattern_table) 0x1000 else 0x0000;
    const tile_offset: u16 = @as(u16, tile_index) * 16;
    const row_offset: u16 = flipped_row;
    const bitplane_offset: u16 = @as(u16, bitplane) * 8;
    return pattern_table_base + tile_offset + row_offset + bitplane_offset;
}

/// Get sprite pattern address for 8×16 sprites
/// Returns CHR ROM address, handling top/bottom half and pattern table selection
pub fn getSprite16PatternAddress(tile_index: u8, row: u8, bitplane: u1, vertical_flip: bool) u16 {
    // In 8×16 mode, bit 0 of tile index selects pattern table (not PPUCTRL)
    const pattern_table_base: u16 = if ((tile_index & 0x01) != 0) 0x1000 else 0x0000;

    // Apply vertical flip (flip across all 16 rows)
    const flipped_row = if (vertical_flip) 15 - row else row;

    // Determine which 8×8 tile (top or bottom half)
    const half = flipped_row / 8; // 0 = top, 1 = bottom
    const row_in_tile = flipped_row % 8;

    // Top half uses tile_index & 0xFE, bottom half uses (tile_index & 0xFE) + 1
    const actual_tile = (tile_index & 0xFE) + half;

    const tile_offset: u16 = @as(u16, actual_tile) * 16;
    const row_offset: u16 = @intCast(row_in_tile);
    const bitplane_offset: u16 = @as(u16, bitplane) * 8;

    return pattern_table_base + tile_offset + row_offset + bitplane_offset;
}

/// Fetch sprite pattern data for visible scanline
/// Called during cycles 257-320 (8 sprites × 8 cycles each)
pub fn fetchSprites(state: *PpuState, cart: ?*AnyCartridge, scanline: u16, dot: u16) void {
    // Reset sprite state at start of fetch
    if (dot == 257) {
        state.sprite_state.sprite_count = 0;
        state.sprite_state.sprite_0_present = false;
        state.sprite_state.sprite_0_index = 0xFF;

        // Clear all sprite shift registers
        for (0..8) |i| {
            state.sprite_state.pattern_shift_lo[i] = 0;
            state.sprite_state.pattern_shift_hi[i] = 0;
            state.sprite_state.attributes[i] = 0;
            state.sprite_state.x_counters[i] = 0xFF;
        }
    }

    // Sprite fetching occurs during cycles 257-320
    if (dot >= 257 and dot <= 320) {
        const fetch_cycle = (dot - 257) % 8;
        const sprite_index = (dot - 257) / 8;

        // Only fetch if we have sprites in secondary OAM
        if (sprite_index < 8) {
            const oam_offset = sprite_index * 4;

            // Check if this sprite slot is valid (secondary OAM not $FF)
            if (state.secondary_oam[oam_offset] != 0xFF) {
                const sprite_y = state.secondary_oam[oam_offset];
                const tile_index = state.secondary_oam[oam_offset + 1];
                const attributes = state.secondary_oam[oam_offset + 2];
                const sprite_x = state.secondary_oam[oam_offset + 3];

                // Calculate row within sprite
                const row_in_sprite: u8 = @intCast(scanline -% sprite_y);

                // Fetch pattern data (cycles 5-6 and 7-8)
                if (fetch_cycle == 5 or fetch_cycle == 6) {
                    // Fetch low bitplane
                    const vertical_flip = (attributes & 0x80) != 0;
                    const sprite_height: u8 = if (state.ctrl.sprite_size) 16 else 8;

                    const addr = if (state.ctrl.sprite_size)
                        getSprite16PatternAddress(tile_index, row_in_sprite, 0, vertical_flip)
                    else
                        getSpritePatternAddress(tile_index, row_in_sprite, 0, state.ctrl.sprite_pattern, vertical_flip);

                    const pattern_lo = memory.readVram(state, cart, addr);

                    // Apply horizontal flip by reversing bits
                    const horizontal_flip = (attributes & 0x40) != 0;
                    state.sprite_state.pattern_shift_lo[sprite_index] = if (horizontal_flip)
                        reverseBits(pattern_lo)
                    else
                        pattern_lo;

                    _ = sprite_height;
                } else if (fetch_cycle == 7 or fetch_cycle == 0) {
                    // Fetch high bitplane
                    const vertical_flip = (attributes & 0x80) != 0;

                    const addr = if (state.ctrl.sprite_size)
                        getSprite16PatternAddress(tile_index, row_in_sprite, 1, vertical_flip)
                    else
                        getSpritePatternAddress(tile_index, row_in_sprite, 1, state.ctrl.sprite_pattern, vertical_flip);

                    const pattern_hi = memory.readVram(state, cart, addr);

                    // Apply horizontal flip
                    const horizontal_flip = (attributes & 0x40) != 0;
                    state.sprite_state.pattern_shift_hi[sprite_index] = if (horizontal_flip)
                        reverseBits(pattern_hi)
                    else
                        pattern_hi;

                    // Load other sprite data
                    state.sprite_state.attributes[sprite_index] = attributes;
                    state.sprite_state.x_counters[sprite_index] = sprite_x;
                    state.sprite_state.sprite_count = @intCast(sprite_index + 1);

                    // Check if sprite 0 is present (OAM index 0 copied to secondary OAM)
                    // This is a simplification - proper implementation would track OAM source index
                    if (sprite_index == 0) {
                        state.sprite_state.sprite_0_present = true;
                        state.sprite_state.sprite_0_index = 0;
                    }
                }
            }
        }
    }
}

/// Reverse bits in a byte (for horizontal sprite flip)
/// Example: 0b10110001 -> 0b10001101
pub fn reverseBits(byte: u8) u8 {
    var result: u8 = 0;
    var temp = byte;
    for (0..8) |_| {
        result = (result << 1) | (temp & 1);
        temp >>= 1;
    }
    return result;
}

/// Get sprite pixel for current position
/// Returns palette index (0 = transparent) and priority flag
pub fn getSpritePixel(state: *PpuState, pixel_x: u16) SpritePixel {
    if (!state.mask.show_sprites) {
        return .{ .pixel = 0, .priority = false, .sprite_0 = false };
    }

    // Check if we should hide sprites in leftmost 8 pixels
    if (pixel_x < 8 and !state.mask.show_sprites_left) {
        return .{ .pixel = 0, .priority = false, .sprite_0 = false };
    }

    // Find first opaque sprite pixel
    for (0..state.sprite_state.sprite_count) |i| {
        // Check if sprite is active (X counter reached 0)
        if (state.sprite_state.x_counters[i] == 0) {
            // Extract pixel from shift registers (MSB = leftmost pixel)
            const bit0 = (state.sprite_state.pattern_shift_lo[i] >> 7) & 1;
            const bit1 = (state.sprite_state.pattern_shift_hi[i] >> 7) & 1;
            const pattern: u8 = (bit1 << 1) | bit0;

            if (pattern != 0) {
                // Non-transparent sprite pixel found
                const palette_select = state.sprite_state.attributes[i] & 0x03;
                const priority_behind = (state.sprite_state.attributes[i] & 0x20) != 0;
                const is_sprite_0 = (i == state.sprite_state.sprite_0_index);

                // Sprite palette indices are $10-$1F
                const palette_index = 0x10 | (palette_select << 2) | pattern;

                return .{
                    .pixel = palette_index,
                    .priority = priority_behind,
                    .sprite_0 = is_sprite_0,
                };
            }

            // Shift this sprite's registers
            state.sprite_state.pattern_shift_lo[i] <<= 1;
            state.sprite_state.pattern_shift_hi[i] <<= 1;
        } else if (state.sprite_state.x_counters[i] < 0xFF) {
            // Decrement X counter
            state.sprite_state.x_counters[i] -= 1;
        }
    }

    return .{ .pixel = 0, .priority = false, .sprite_0 = false };
}

/// Evaluate sprites for the current scanline
/// Copies up to 8 sprites to secondary OAM
/// Sets sprite_overflow flag if more than 8 sprites found
pub fn evaluateSprites(state: *PpuState, scanline: u16) void {
    const sprite_height: u16 = if (state.ctrl.sprite_size) 16 else 8;
    var secondary_oam_index: usize = 0;
    var sprites_found: u8 = 0;

    // Clear sprite overflow flag at start of evaluation
    state.status.sprite_overflow = false;

    // Evaluate all 64 sprites in OAM
    for (0..64) |sprite_index| {
        const oam_offset = sprite_index * 4;
        const sprite_y = state.oam[oam_offset];

        // Check if sprite is in range for current scanline
        // Sprite Y position defines top of sprite
        // Sprite is visible if: scanline >= sprite_y AND scanline < sprite_y + height
        // Special case: Y=$FF means sprite at -1 (never visible due to overflow)
        const sprite_bottom = @as(u16, sprite_y) + sprite_height;
        if (scanline >= sprite_y and scanline < sprite_bottom) {
            // Sprite is in range
            if (sprites_found < 8) {
                // Copy sprite to secondary OAM
                state.secondary_oam[secondary_oam_index] = state.oam[oam_offset]; // Y
                state.secondary_oam[secondary_oam_index + 1] = state.oam[oam_offset + 1]; // Tile
                state.secondary_oam[secondary_oam_index + 2] = state.oam[oam_offset + 2]; // Attr
                state.secondary_oam[secondary_oam_index + 3] = state.oam[oam_offset + 3]; // X
                secondary_oam_index += 4;
                sprites_found += 1;
            } else {
                // More than 8 sprites found - set overflow flag
                state.status.sprite_overflow = true;
                // Hardware bug: Continue checking but with diagonal scan pattern
                // For now, just set flag and break
                break;
            }
        }
    }
}
