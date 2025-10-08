//! PPU Logic
//!
//! This module contains pure functions that operate on PPU state.
//! All functions receive PpuState as the first parameter.

const std = @import("std");
const StateModule = @import("State.zig");
const PpuState = StateModule.PpuState;
const AnyCartridge = @import("../cartridge/mappers/registry.zig").AnyCartridge;
const PpuCtrl = StateModule.PpuCtrl;
const PpuMask = StateModule.PpuMask;
const PpuStatus = StateModule.PpuStatus;
const Mirroring = @import("../cartridge/ines.zig").Mirroring;
const palette = @import("palette.zig");

/// Initialize PPU state to power-on values
pub fn init() PpuState {
    return PpuState.init();
}

/// Reset PPU (RESET button pressed)
/// Some registers are not affected by RESET
/// Note: RESET does NOT trigger the warm-up period (only power-on does)
pub fn reset(state: *PpuState) void {
    state.ctrl = .{};
    state.mask = .{};
    // Status VBlank bit is random at reset
    state.internal.resetToggle();
    // RESET skips the warm-up period (PPU already initialized)
    state.warmup_complete = true;
}

/// Mirror nametable address based on mirroring mode
/// Returns address in 0-2047 range (2KB VRAM)
///
/// Nametable layout:
/// $2000-$23FF: Nametable 0 (1KB)
/// $2400-$27FF: Nametable 1 (1KB)
/// $2800-$2BFF: Nametable 2 (1KB)
/// $2C00-$2FFF: Nametable 3 (1KB)
///
/// Physical VRAM is only 2KB, so nametables are mirrored:
/// - Horizontal: NT0=NT1 (top), NT2=NT3 (bottom)
/// - Vertical: NT0=NT2 (left), NT1=NT3 (right)
/// - Single screen: All map to same 1KB
/// - Four screen: 4KB external VRAM (no mirroring)
fn mirrorNametableAddress(address: u16, mirroring: Mirroring) u16 {
    const addr = address & 0x0FFF; // Mask to $0000-$0FFF (4KB logical space)
    const nametable = (addr >> 10) & 0x03; // Extract nametable index (0-3)

    return switch (mirroring) {
        .horizontal => blk: {
            // Horizontal mirroring (top/bottom)
            // NT0, NT1 -> VRAM $0000-$03FF
            // NT2, NT3 -> VRAM $0400-$07FF
            if (nametable < 2) {
                break :blk addr & 0x03FF; // First 1KB
            } else {
                break :blk 0x0400 | (addr & 0x03FF); // Second 1KB
            }
        },
        .vertical => blk: {
            // Vertical mirroring (left/right)
            // NT0, NT2 -> VRAM $0000-$03FF
            // NT1, NT3 -> VRAM $0400-$07FF
            if (nametable == 0 or nametable == 2) {
                break :blk addr & 0x03FF; // First 1KB
            } else {
                break :blk 0x0400 | (addr & 0x03FF); // Second 1KB
            }
        },
        .four_screen => blk: {
            // Four-screen VRAM (no mirroring)
            // Requires 4KB external VRAM on cartridge
            // For now, mirror to 2KB (will need cartridge support later)
            break :blk addr & 0x07FF;
        },
    };
}

/// Mirror palette RAM address (handles backdrop mirroring)
/// Palette RAM is 32 bytes at $3F00-$3F1F
/// Special case: $3F10/$3F14/$3F18/$3F1C mirror $3F00/$3F04/$3F08/$3F0C
///
/// Palette layout:
/// $3F00-$3F0F: Background palettes (4 palettes, 4 colors each)
/// $3F10-$3F1F: Sprite palettes (4 palettes, 4 colors each)
/// But sprite palette backdrop colors ($3F10/$14/$18/$1C) mirror BG backdrop
fn mirrorPaletteAddress(address: u8) u8 {
    const addr = address & 0x1F; // Mask to 32-byte range

    // Mirror sprite backdrop colors to background backdrop colors
    // $3F10, $3F14, $3F18, $3F1C -> $3F00, $3F04, $3F08, $3F0C
    if (addr >= 0x10 and (addr & 0x03) == 0) {
        return addr & 0x0F; // Clear bit 4 to mirror to background
    }

    return addr;
}

/// Read from PPU VRAM address space ($0000-$3FFF)
/// Handles CHR ROM/RAM, nametables, and palette RAM with proper mirroring
pub fn readVram(state: *PpuState, cart: ?*AnyCartridge, address: u16) u8 {
    const addr = address & 0x3FFF; // Mirror at $4000

    return switch (addr) {
        // CHR ROM/RAM ($0000-$1FFF) - Pattern tables
        // Accessed via cartridge ppuRead() method
        0x0000...0x1FFF => blk: {
            if (cart) |c| {
                break :blk c.ppuRead(addr);
            }
            // No cartridge - return PPU open bus (data bus latch)
            break :blk state.open_bus.read();
        },

        // Nametables ($2000-$2FFF)
        // 4KB logical space mapped to 2KB physical VRAM via mirroring
        0x2000...0x2FFF => blk: {
            const mirrored_addr = mirrorNametableAddress(addr, state.mirroring);
            break :blk state.vram[mirrored_addr];
        },

        // Nametable mirrors ($3000-$3EFF)
        // $3000-$3EFF mirrors $2000-$2EFF
        0x3000...0x3EFF => blk: {
            break :blk readVram(state, cart, addr - 0x1000);
        },

        // Palette RAM ($3F00-$3F1F)
        // 32 bytes with special backdrop mirroring
        0x3F00...0x3F1F => blk: {
            const palette_addr = mirrorPaletteAddress(@truncate(addr & 0x1F));
            break :blk state.palette_ram[palette_addr];
        },

        // Palette RAM mirrors ($3F20-$3FFF)
        // Mirrors $3F00-$3F1F throughout $3F20-$3FFF
        0x3F20...0x3FFF => blk: {
            break :blk readVram(state, cart, 0x3F00 | (addr & 0x1F));
        },

        else => unreachable, // addr is masked to $0000-$3FFF
    };
}

/// Write to PPU VRAM address space ($0000-$3FFF)
/// Handles CHR RAM, nametables, and palette RAM (CHR ROM is read-only)
pub fn writeVram(state: *PpuState, cart: ?*AnyCartridge, address: u16, value: u8) void {
    const addr = address & 0x3FFF; // Mirror at $4000

    switch (addr) {
        // CHR ROM/RAM ($0000-$1FFF)
        // CHR ROM is read-only, CHR RAM is writable via cartridge
        0x0000...0x1FFF => {
            if (cart) |c| {
                // Cartridge handles write (ignores if CHR ROM)
                c.ppuWrite(addr, value);
            }
        },

        // Nametables ($2000-$2FFF)
        0x2000...0x2FFF => {
            const mirrored_addr = mirrorNametableAddress(addr, state.mirroring);
            state.vram[mirrored_addr] = value;
        },

        // Nametable mirrors ($3000-$3EFF)
        0x3000...0x3EFF => {
            writeVram(state, cart, addr - 0x1000, value);
        },

        // Palette RAM ($3F00-$3F1F)
        0x3F00...0x3F1F => {
            const palette_addr = mirrorPaletteAddress(@truncate(addr & 0x1F));
            state.palette_ram[palette_addr] = value;
        },

        // Palette RAM mirrors ($3F20-$3FFF)
        0x3F20...0x3FFF => {
            writeVram(state, cart, 0x3F00 | (addr & 0x1F), value);
        },

        else => unreachable, // addr is masked to $0000-$3FFF
    }
}
pub fn readRegister(state: *PpuState, cart: ?*AnyCartridge, address: u16) u8 {
    // Registers are mirrored every 8 bytes through $3FFF
    const reg = address & 0x0007;

    return switch (reg) {
        0x0000 => blk: {
            // $2000 PPUCTRL - Write-only, return open bus
            break :blk state.open_bus.read();
        },
        0x0001 => blk: {
            // $2001 PPUMASK - Write-only, return open bus
            break :blk state.open_bus.read();
        },
        0x0002 => blk: {
            // $2002 PPUSTATUS - Read-only
            const value = state.status.toByte(state.open_bus.value);

            // Side effects:
            // 1. Clear VBlank flag
            state.status.vblank = false;

            // 2. Reset write toggle
            state.internal.resetToggle();

            // 3. Update open bus with status (top 3 bits)
            state.open_bus.write(value);

            break :blk value;
        },
        0x0003 => blk: {
            // $2003 OAMADDR - Write-only, return open bus
            break :blk state.open_bus.read();
        },
        0x0004 => blk: {
            // $2004 OAMDATA - Read/write
            const value = state.oam[state.oam_addr];

            // Attribute bytes have bits 2-4 as open bus
            const is_attribute_byte = (state.oam_addr & 0x03) == 0x02;
            const result = if (is_attribute_byte)
                (value & 0xE3) | (state.open_bus.value & 0x1C)
            else
                value;

            // Update open bus
            state.open_bus.write(result);

            break :blk result;
        },
        0x0005 => blk: {
            // $2005 PPUSCROLL - Write-only, return open bus
            break :blk state.open_bus.read();
        },
        0x0006 => blk: {
            // $2006 PPUADDR - Write-only, return open bus
            break :blk state.open_bus.read();
        },
        0x0007 => blk: {
            // $2007 PPUDATA - Buffered read from VRAM
            const addr = state.internal.v;
            const buffered_value = state.internal.read_buffer;

            // Update buffer with current VRAM value
            state.internal.read_buffer = readVram(state, cart, addr);

            // Increment VRAM address after read
            state.internal.v +%= state.ctrl.vramIncrementAmount();

            // Palette reads are NOT buffered (return current, not buffered)
            // All other reads return the buffered value
            const value = if (addr >= 0x3F00) state.internal.read_buffer else buffered_value;

            // Update open bus
            state.open_bus.write(value);

            break :blk value;
        },
        else => unreachable,
    };
}

/// Write to PPU register (via CPU memory bus)
/// Handles register mirroring and open bus updates
pub fn writeRegister(state: *PpuState, cart: ?*AnyCartridge, address: u16, value: u8) void {
    // Registers are mirrored every 8 bytes through $3FFF
    const reg = address & 0x0007;

    // All writes update the open bus
    state.open_bus.write(value);

    switch (reg) {
        0x0000 => {
            // $2000 PPUCTRL
            // Ignored during warm-up period (first ~29,658 CPU cycles)
            if (!state.warmup_complete) return;

            state.ctrl = PpuCtrl.fromByte(value);

            // Update t register bits 10-11 (nametable select)
            state.internal.t = (state.internal.t & 0xF3FF) |
                (@as(u16, value & 0x03) << 10);
        },
        0x0001 => {
            // $2001 PPUMASK
            // Ignored during warm-up period (first ~29,658 CPU cycles)
            if (!state.warmup_complete) return;

            state.mask = PpuMask.fromByte(value);
        },
        0x0002 => {
            // $2002 PPUSTATUS - Read-only, write has no effect
        },
        0x0003 => {
            // $2003 OAMADDR
            state.oam_addr = value;
        },
        0x0004 => {
            // $2004 OAMDATA
            state.oam[state.oam_addr] = value;
            state.oam_addr +%= 1; // Wraps at 256
        },
        0x0005 => {
            // $2005 PPUSCROLL
            // Ignored during warm-up period (first ~29,658 CPU cycles)
            if (!state.warmup_complete) return;

            if (!state.internal.w) {
                // First write: X scroll
                state.internal.t = (state.internal.t & 0xFFE0) |
                    (@as(u16, value) >> 3);
                state.internal.x = @truncate(value & 0x07);
                state.internal.w = true;
            } else {
                // Second write: Y scroll
                state.internal.t = (state.internal.t & 0x8FFF) |
                    ((@as(u16, value) & 0x07) << 12);
                state.internal.t = (state.internal.t & 0xFC1F) |
                    ((@as(u16, value) & 0xF8) << 2);
                state.internal.w = false;
            }
        },
        0x0006 => {
            // $2006 PPUADDR
            // Ignored during warm-up period (first ~29,658 CPU cycles)
            if (!state.warmup_complete) return;

            if (!state.internal.w) {
                // First write: High byte
                state.internal.t = (state.internal.t & 0x80FF) |
                    ((@as(u16, value) & 0x3F) << 8);
                state.internal.w = true;
            } else {
                // Second write: Low byte
                state.internal.t = (state.internal.t & 0xFF00) |
                    @as(u16, value);
                state.internal.v = state.internal.t;
                state.internal.w = false;
            }
        },
        0x0007 => {
            // $2007 PPUDATA - Write to VRAM
            const addr = state.internal.v;

            // Write to VRAM
            writeVram(state, cart, addr, value);

            // Increment VRAM address after write
            state.internal.v +%= state.ctrl.vramIncrementAmount();
        },
        else => unreachable, // reg is masked to 0-7
    }
}

/// Increment coarse X scroll (every 8 pixels)
/// Handles horizontal nametable wrapping
pub fn incrementScrollX(state: *PpuState) void {
    if (!state.mask.renderingEnabled()) return;

    // Coarse X is bits 0-4 of v register
    if ((state.internal.v & 0x001F) == 31) {
        // Coarse X = 31, wrap to 0 and switch horizontal nametable
        state.internal.v &= ~@as(u16, 0x001F); // Clear coarse X
        state.internal.v ^= 0x0400; // Switch horizontal nametable
    } else {
        // Increment coarse X
        state.internal.v += 1;
    }
}

/// Increment Y scroll (end of scanline)
/// Handles vertical nametable wrapping
pub fn incrementScrollY(state: *PpuState) void {
    if (!state.mask.renderingEnabled()) return;

    // Fine Y is bits 12-14 of v register
    if ((state.internal.v & 0x7000) != 0x7000) {
        // Increment fine Y
        state.internal.v += 0x1000;
    } else {
        // Fine Y = 7, reset to 0 and increment coarse Y
        state.internal.v &= ~@as(u16, 0x7000); // Clear fine Y

        // Coarse Y is bits 5-9
        var coarse_y = (state.internal.v >> 5) & 0x1F;
        if (coarse_y == 29) {
            // Coarse Y = 29, wrap to 0 and switch vertical nametable
            coarse_y = 0;
            state.internal.v ^= 0x0800; // Switch vertical nametable
        } else if (coarse_y == 31) {
            // Out of bounds, wrap without nametable switch
            coarse_y = 0;
        } else {
            coarse_y += 1;
        }

        // Write coarse Y back to v register
        state.internal.v = (state.internal.v & ~@as(u16, 0x03E0)) | (coarse_y << 5);
    }
}

/// Copy horizontal scroll bits from t to v
/// Called at dot 257 of each visible scanline
pub fn copyScrollX(state: *PpuState) void {
    if (!state.mask.renderingEnabled()) return;

    // Copy bits 0-4 (coarse X) and bit 10 (horizontal nametable)
    state.internal.v = (state.internal.v & 0xFBE0) | (state.internal.t & 0x041F);
}

/// Copy vertical scroll bits from t to v
/// Called at dot 280-304 of pre-render scanline
pub fn copyScrollY(state: *PpuState) void {
    if (!state.mask.renderingEnabled()) return;

    // Copy bits 5-9 (coarse Y), bits 12-14 (fine Y), bit 11 (vertical nametable)
    state.internal.v = (state.internal.v & 0x841F) | (state.internal.t & 0x7BE0);
}

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
            state.bg_state.nametable_latch = readVram(state, cart, nt_addr);
        },

        // Cycle 2: Fetch attribute byte (palette select)
        2 => {
            const attr_addr = getAttributeAddress(state);
            const attr_byte = readVram(state, cart, attr_addr);

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
            state.bg_state.pattern_latch_lo = readVram(state, cart, pattern_addr);
        },

        // Cycle 6: Fetch pattern table tile high byte (bitplane 1)
        6 => {
            const pattern_addr = getPatternAddress(state, true);
            state.bg_state.pattern_latch_hi = readVram(state, cart, pattern_addr);

            // Load shift registers with fetched data
            state.bg_state.loadShiftRegisters();

            // Increment coarse X after loading tile
            incrementScrollX(state);
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

                    const pattern_lo = readVram(state, cart, addr);

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

                    const pattern_hi = readVram(state, cart, addr);

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
pub fn getSpritePixel(state: *PpuState, pixel_x: u16) struct { pixel: u8, priority: bool, sprite_0: bool } {
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

/// Decay open bus value (called once per frame)
pub fn tickFrame(state: *PpuState) void {
    state.open_bus.decay();
}
