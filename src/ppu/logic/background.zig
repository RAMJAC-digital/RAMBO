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
/// Implements 4-cycle fetch pattern: nametable → attribute → pattern low → pattern high
pub fn fetchBackgroundTile(state: *PpuState, cart: ?*AnyCartridge, dot: u16) void {
    // Tile fetching occurs in 8-cycle chunks
    // Each chunk fetches: NT byte (2 cycles), AT byte (2 cycles),
    // pattern low (2 cycles), pattern high (2 cycles)
    const fetch_cycle = dot & 0x07;

    switch (fetch_cycle) {
        // Cycles 1, 3, 5, 7: Idle (hardware accesses nametable but doesn't use value)
        1, 3, 5, 7 => {},

        // Cycle 0: Fetch nametable byte (tile index)
        0 => {
            const nt_addr = 0x2000 | (state.internal.v & 0x0FFF);
            state.bg_state.nametable_latch = memory.readVram(state, cart, nt_addr);
        },

        // Cycle 2: Fetch attribute byte (palette select)
        2 => {
            const attr_addr = getAttributeAddress(state);
            const attr_byte = memory.readVram(state, cart, attr_addr);

            // Extract 2-bit palette for this 16×16 pixel quadrant
            // Attribute byte layout: BR BL TR TL (2 bits each)
            const coarse_x = state.internal.v & 0x1F;
            const coarse_y = (state.internal.v >> 5) & 0x1F;
            const shift = ((coarse_y & 0x02) << 1) | (coarse_x & 0x02);
            state.bg_state.attribute_latch = (attr_byte >> @intCast(shift)) & 0x03;
        },

        // Cycle 4: Fetch pattern table tile low byte (bitplane 0)
        4 => {
            const pattern_addr = getPatternAddress(state, false);
            state.bg_state.pattern_latch_lo = memory.readVram(state, cart, pattern_addr);
        },

        // Cycle 6: Fetch pattern table tile high byte (bitplane 1)
        6 => {
            const pattern_addr = getPatternAddress(state, true);
            state.bg_state.pattern_latch_hi = memory.readVram(state, cart, pattern_addr);

            // Load shift registers with fetched data
            state.bg_state.loadShiftRegisters();

            // Increment coarse X after loading tile
            scrolling.incrementScrollX(state);
        },

        else => unreachable,
    }
}

/// Get background pixel from shift registers
/// Returns palette index (0-31), or 0 for transparent
pub fn getBackgroundPixel(state: *PpuState) u8 {
    if (!state.mask.show_bg) return 0;

    // Apply fine X scroll (0-7)
    // Shift amount is 15 - fine_x (range: 8-15)
    const shift_amount = @as(u4, 15) - state.internal.x;

    // Extract bits from pattern shift registers
    const bit0 = (state.bg_state.pattern_shift_lo >> shift_amount) & 1;
    const bit1 = (state.bg_state.pattern_shift_hi >> shift_amount) & 1;
    const pattern: u8 = @intCast((bit1 << 1) | bit0);

    if (pattern == 0) return 0; // Transparent

    // Extract palette bits from attribute shift registers
    const attr_bit0 = (state.bg_state.attribute_shift_lo >> 7) & 1;
    const attr_bit1 = (state.bg_state.attribute_shift_hi >> 7) & 1;
    const palette_select: u8 = @intCast((attr_bit1 << 1) | attr_bit0);

    // Combine into palette RAM index ($00-$0F for background)
    return (palette_select << 2) | pattern;
}

/// Get final pixel color from palette
/// Converts palette index to RGBA8888 color
pub fn getPaletteColor(state: *PpuState, palette_index: u8) u32 {
    // Read NES color index from palette RAM
    const nes_color = state.palette_ram[palette_index & 0x1F];

    // Convert to RGBA using standard NES palette
    return palette.getNesColorRgba(nes_color);
}
