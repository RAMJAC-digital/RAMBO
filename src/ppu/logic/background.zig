//! PPU Background Rendering Logic
//!
//! Handles background tile fetching and pixel rendering.
//! Implements the 8-cycle tile fetch pattern and shift register output.

const PpuState = @import("../State.zig").PpuState;
const AnyCartridge = @import("../../cartridge/mappers/registry.zig").AnyCartridge;
const memory = @import("memory.zig");
const scrolling = @import("scrolling.zig");
const palette = @import("../palette.zig");

/// Get pattern table address for current tile
/// high_bitplane: false = bitplane 0, true = bitplane 1
fn getPatternAddress(state: *PpuState, high_bitplane: bool) u16 {
    // Pattern table base from PPUCTRL ($0000 or $1000)
    const pattern_base: u16 = if (state.ctrl.bg_pattern) 0x1000 else 0x0000;

    // Tile index from nametable latch
    const tile_index: u16 = state.bg_state.nametable_latch;

    // Fine Y from v register (bits 12-14)
    const fine_y: u16 = (state.internal.v >> 12) & 0x07;

    // Bitplane offset (bitplane 1 is +8 bytes from bitplane 0)
    const bitplane_offset: u16 = if (high_bitplane) 8 else 0;

    // Each tile is 16 bytes (8 bytes per bitplane)
    return pattern_base + (tile_index * 16) + fine_y + bitplane_offset;
}

/// Get attribute table address for current tile
fn getAttributeAddress(state: *PpuState) u16 {
    // Attribute table is at +$03C0 from nametable base
    // Each attribute byte controls a 4×4 tile area (32×32 pixels)
    const v = state.internal.v;
    return 0x23C0 |
        (v & 0x0C00) | // Nametable select (bits 10-11)
        ((v >> 4) & 0x38) | // High 3 bits of coarse Y
        ((v >> 2) & 0x07); // High 3 bits of coarse X
}

/// Fetch background tile data for current cycle
/// Implements hardware-accurate 8-cycle tile fetch pattern
/// Reference: https://www.nesdev.org/wiki/PPU_rendering
pub fn fetchBackgroundTile(state: *PpuState, cart: ?*AnyCartridge, dot: u16) void {
    // Hardware-accurate tile fetch timing:
    // Each tile fetch takes 8 dots, with fetches completing at dots 2, 4, 6, 8
    // Shift registers reload at dots 9, 17, 25, 33... (every 8 dots, offset by 1)
    //
    // Dots 1-2:   Nametable byte fetch
    // Dots 3-4:   Attribute table byte fetch
    // Dots 5-6:   Pattern table low byte fetch
    // Dots 7-8:   Pattern table high byte fetch
    // Dot 9:      Load shift registers, increment scroll X, start next tile
    //
    // Map dots to cycles within tile (0-7)
    const cycle_in_tile = (dot - 1) % 8;

    switch (cycle_in_tile) {
        // Cycle 1: Nametable fetch completes (dots 2, 10, 18, 26...)
        1 => {
            const nt_addr = 0x2000 | (state.internal.v & 0x0FFF);
            state.bg_state.nametable_latch = memory.readVram(state, cart, nt_addr);
        },

        // Cycle 3: Attribute fetch completes (dots 4, 12, 20, 28...)
        3 => {
            const attr_addr = getAttributeAddress(state);
            const attr_byte = memory.readVram(state, cart, attr_addr);

            // Extract 2-bit palette for this 16×16 pixel quadrant
            // Attribute byte layout: BR BL TR TL (2 bits each)
            const coarse_x = state.internal.v & 0x1F;
            const coarse_y = (state.internal.v >> 5) & 0x1F;
            const shift = ((coarse_y & 0x02) << 1) | (coarse_x & 0x02);
            state.bg_state.attribute_latch = (attr_byte >> @intCast(shift)) & 0x03;
        },

        // Cycle 5: Pattern low fetch completes (dots 6, 14, 22, 30...)
        5 => {
            const pattern_addr = getPatternAddress(state, false);
            state.bg_state.pattern_latch_lo = memory.readVram(state, cart, pattern_addr);
        },

        // Cycle 7: Pattern high fetch completes (dots 8, 16, 24, 32...)
        7 => {
            const pattern_addr = getPatternAddress(state, true);
            state.bg_state.pattern_latch_hi = memory.readVram(state, cart, pattern_addr);
        },

        // Cycle 0: Shift register reload (dots 9, 17, 25, 33, 329, 337...)
        // Special cases:
        // - Skip dot 1: First dot of scanline, no data fetched yet
        // - Skip dot 321: First prefetch dot, spurious reload with garbage data
        0 => {
            if (dot > 1 and dot != 321) {
                // Load shift registers with fetched tile data
                state.bg_state.loadShiftRegisters();

                // Increment coarse X after loading tile
                scrolling.incrementScrollX(state);
            }
        },

        // Cycles 2, 4, 6: Idle (hardware is setting up addresses)
        else => {},
    }
}

/// Get background pixel from shift registers
/// Returns palette index (0-31), or 0 for transparent
pub fn getBackgroundPixel(state: *PpuState, pixel_x: u16) u8 {
    if (!state.mask.show_bg) return 0;

    // Left-column clipping (hardware accurate)
    // When show_bg_left is false, background is transparent in columns 0-7
    if (pixel_x < 8 and !state.mask.show_bg_left) {
        return 0;
    }

    // Apply fine X scroll (0-7)
    // Hardware: fine X is a 3-bit register (nesdev.org/wiki/PPU_scrolling)
    // Mask to ensure valid range before arithmetic
    const fine_x: u8 = state.internal.x & 0x07;
    const shift_amount: u4 = @intCast(15 - fine_x); // Range: 8-15

    // Extract bits from pattern shift registers
    const bit0 = (state.bg_state.pattern_shift_lo >> shift_amount) & 1;
    const bit1 = (state.bg_state.pattern_shift_hi >> shift_amount) & 1;
    const pattern: u8 = @intCast((bit1 << 1) | bit0);

    if (pattern == 0) return 0; // Transparent

    // Extract palette bits from attribute shift registers
    // Hardware: Attribute shift registers are now 16-bit (like pattern registers)
    // They shift LEFT each cycle, with next tile's attribute in low 8 bits
    // CRITICAL: Must use same shift_amount as pattern registers to keep them synchronized!
    // Bug fix: Previously sampled bit 15 only, causing palette desync with fine_x scroll
    // After 8 shifts, bits 8-15 contain previous tile, bits 0-7 contain next tile
    // Reference: NESDev - "next tile's attribute bits connected to shift register inputs"
    const attr_bit0 = (state.bg_state.attribute_shift_lo >> shift_amount) & 1;
    const attr_bit1 = (state.bg_state.attribute_shift_hi >> shift_amount) & 1;
    const palette_select: u8 = @intCast((attr_bit1 << 1) | attr_bit0);

    // Combine into palette RAM index ($00-$0F for background)
    return (palette_select << 2) | pattern;
}

/// Get final pixel color from palette
/// Converts palette index to RGBA8888 color with greyscale mode support
pub fn getPaletteColor(state: *PpuState, palette_index: u8) u32 {
    // Read NES color index from palette RAM
    var nes_color = state.palette_ram[palette_index & 0x1F];

    // Apply greyscale mode (PPUMASK bit 0)
    // Hardware: AND with $30 to strip hue (bits 0-3), keeping only value (bits 4-5)
    // This converts all colors to grayscale by removing color information
    // Reference: nesdev.org/wiki/PPU_palettes#Greyscale_mode
    if (state.mask.greyscale) {
        nes_color &= 0x30;
    }

    // Convert to RGBA using standard NES palette
    return palette.getNesColorRgba(nes_color);
}
