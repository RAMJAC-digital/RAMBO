//! PPU Logic
//!
//! This module contains pure functions that operate on PPU state.
//! All functions receive PpuState as the first parameter.

const std = @import("std");
const StateModule = @import("State.zig");
const PpuState = StateModule.PpuState;
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
pub fn reset(state: *PpuState) void {
    state.ctrl = .{};
    state.mask = .{};
    // Status VBlank bit is random at reset
    state.internal.resetToggle();
    state.nmi_occurred = false;
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
pub fn readVram(state: *PpuState, address: u16) u8 {
    const addr = address & 0x3FFF; // Mirror at $4000

    return switch (addr) {
        // CHR ROM/RAM ($0000-$1FFF) - Pattern tables
        // Accessed via cartridge ppuRead() method
        0x0000...0x1FFF => blk: {
            if (state.cartridge) |cart| {
                break :blk cart.ppuRead(addr);
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
            break :blk readVram(state, addr - 0x1000);
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
            break :blk readVram(state, 0x3F00 | (addr & 0x1F));
        },

        else => unreachable, // addr is masked to $0000-$3FFF
    };
}

/// Write to PPU VRAM address space ($0000-$3FFF)
/// Handles CHR RAM, nametables, and palette RAM (CHR ROM is read-only)
pub fn writeVram(state: *PpuState, address: u16, value: u8) void {
    const addr = address & 0x3FFF; // Mirror at $4000

    switch (addr) {
        // CHR ROM/RAM ($0000-$1FFF)
        // CHR ROM is read-only, CHR RAM is writable via cartridge
        0x0000...0x1FFF => {
            if (state.cartridge) |cart| {
                // Cartridge handles write (ignores if CHR ROM)
                cart.ppuWrite(addr, value);
            }
        },

        // Nametables ($2000-$2FFF)
        0x2000...0x2FFF => {
            const mirrored_addr = mirrorNametableAddress(addr, state.mirroring);
            state.vram[mirrored_addr] = value;
        },

        // Nametable mirrors ($3000-$3EFF)
        0x3000...0x3EFF => {
            writeVram(state, addr - 0x1000, value);
        },

        // Palette RAM ($3F00-$3F1F)
        0x3F00...0x3F1F => {
            const palette_addr = mirrorPaletteAddress(@truncate(addr & 0x1F));
            state.palette_ram[palette_addr] = value;
        },

        // Palette RAM mirrors ($3F20-$3FFF)
        0x3F20...0x3FFF => {
            writeVram(state, 0x3F00 | (addr & 0x1F), value);
        },

        else => unreachable, // addr is masked to $0000-$3FFF
    }
}
    pub fn readRegister(state: *PpuState, address: u16) u8 {
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
                state.internal.read_buffer = state.readVram(addr);

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
    pub fn writeRegister(state: *PpuState, address: u16, value: u8) void {
        // Registers are mirrored every 8 bytes through $3FFF
        const reg = address & 0x0007;

        // All writes update the open bus
        state.open_bus.write(value);

        switch (reg) {
            0x0000 => {
                // $2000 PPUCTRL
                state.ctrl = PpuCtrl.fromByte(value);

                // Update t register bits 10-11 (nametable select)
                state.internal.t = (state.internal.t & 0xF3FF) |
                    (@as(u16, value & 0x03) << 10);
            },
            0x0001 => {
                // $2001 PPUMASK
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
                state.writeVram(addr, value);

                // Increment VRAM address after write
                state.internal.v +%= state.ctrl.vramIncrementAmount();
            },
            else => unreachable, // reg is masked to 0-7
        }
    }

    /// Increment coarse X scroll (every 8 pixels)
    /// Handles horizontal nametable wrapping
    fn incrementScrollX(state: *PpuState) void {
        if (!state.mask.renderingEnabled()) return;

        // Coarse X is bits 0-4 of v register
        if ((state.internal.v & 0x001F) == 31) {
            // Coarse X = 31, wrap to 0 and switch horizontal nametable
            state.internal.v &= ~@as(u16, 0x001F);  // Clear coarse X
            state.internal.v ^= 0x0400;              // Switch horizontal nametable
        } else {
            // Increment coarse X
            state.internal.v += 1;
        }
    }

    /// Increment Y scroll (end of scanline)
    /// Handles vertical nametable wrapping
    fn incrementScrollY(state: *PpuState) void {
        if (!state.mask.renderingEnabled()) return;

        // Fine Y is bits 12-14 of v register
        if ((state.internal.v & 0x7000) != 0x7000) {
            // Increment fine Y
            state.internal.v += 0x1000;
        } else {
            // Fine Y = 7, reset to 0 and increment coarse Y
            state.internal.v &= ~@as(u16, 0x7000);  // Clear fine Y

            // Coarse Y is bits 5-9
            var coarse_y = (state.internal.v >> 5) & 0x1F;
            if (coarse_y == 29) {
                // Coarse Y = 29, wrap to 0 and switch vertical nametable
                coarse_y = 0;
                state.internal.v ^= 0x0800;  // Switch vertical nametable
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
    fn copyScrollX(state: *PpuState) void {
        if (!state.mask.renderingEnabled()) return;

        // Copy bits 0-4 (coarse X) and bit 10 (horizontal nametable)
        state.internal.v = (state.internal.v & 0xFBE0) | (state.internal.t & 0x041F);
    }

    /// Copy vertical scroll bits from t to v
    /// Called at dot 280-304 of pre-render scanline
    fn copyScrollY(state: *PpuState) void {
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
            (v & 0x0C00) |                    // Nametable select (bits 10-11)
            ((v >> 4) & 0x38) |               // High 3 bits of coarse Y
            ((v >> 2) & 0x07);                // High 3 bits of coarse X
    }

    /// Fetch background tile data for current cycle
    /// Implements 4-cycle fetch pattern: nametable → attribute → pattern low → pattern high
    fn fetchBackgroundTile(state: *PpuState) void {
        // Tile fetching occurs in 8-cycle chunks
        // Each chunk fetches: NT byte (2 cycles), AT byte (2 cycles),
        // pattern low (2 cycles), pattern high (2 cycles)
        const fetch_cycle = state.dot & 0x07;

        switch (fetch_cycle) {
            // Cycles 1, 3, 5, 7: Idle (hardware accesses nametable but doesn't use value)
            1, 3, 5, 7 => {},

            // Cycle 0: Fetch nametable byte (tile index)
            0 => {
                const nt_addr = 0x2000 | (state.internal.v & 0x0FFF);
                state.bg_state.nametable_latch = state.readVram(nt_addr);
            },

            // Cycle 2: Fetch attribute byte (palette select)
            2 => {
                const attr_addr = getAttributeAddress(state);
                const attr_byte = state.readVram(attr_addr);

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
                state.bg_state.pattern_latch_lo = state.readVram(pattern_addr);
            },

            // Cycle 6: Fetch pattern table tile high byte (bitplane 1)
            6 => {
                const pattern_addr = getPatternAddress(state, true);
                state.bg_state.pattern_latch_hi = state.readVram(pattern_addr);

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
    fn getBackgroundPixel(state: *PpuState) u8 {
        if (!state.mask.show_bg) return 0;

        // Apply fine X scroll (0-7)
        // Shift amount is 15 - fine_x (range: 8-15)
        const shift_amount = @as(u4, 15) - state.internal.x;

        // Extract bits from pattern shift registers
        const bit0 = (state.bg_state.pattern_shift_lo >> shift_amount) & 1;
        const bit1 = (state.bg_state.pattern_shift_hi >> shift_amount) & 1;
        const pattern: u8 = @intCast((bit1 << 1) | bit0);

        if (pattern == 0) return 0;  // Transparent

        // Extract palette bits from attribute shift registers
        const attr_bit0 = (state.bg_state.attribute_shift_lo >> 7) & 1;
        const attr_bit1 = (state.bg_state.attribute_shift_hi >> 7) & 1;
        const palette_select: u8 = @intCast((attr_bit1 << 1) | attr_bit0);

        // Combine into palette RAM index ($00-$0F for background)
        return (palette_select << 2) | pattern;
    }

    /// Get final pixel color from palette
    /// Converts palette index to RGBA8888 color
    fn getPaletteColor(state: *PpuState, palette_index: u8) u32 {
        // Read NES color index from palette RAM
        const nes_color = state.palette_ram[palette_index & 0x1F];

        // Convert to RGBA using standard NES palette
        return palette.getNesColorRgba(nes_color);
    }

    /// Evaluate sprites for the current scanline
    /// Copies up to 8 sprites to secondary OAM
    /// Sets sprite_overflow flag if more than 8 sprites found
    fn evaluateSprites(state: *PpuState) void {
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
            if (state.scanline >= sprite_y and state.scanline < sprite_bottom) {
                // Sprite is in range
                if (sprites_found < 8) {
                    // Copy sprite to secondary OAM
                    state.secondary_oam[secondary_oam_index] = state.oam[oam_offset];         // Y
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

    /// Tick PPU by one PPU cycle
    /// Optional framebuffer for pixel output (RGBA8888, 256×240 pixels)
    pub fn tick(state: *PpuState, framebuffer: ?[]u32) void {
        // === Cycle Advance (happens FIRST) ===
        state.dot += 1;

        // End of scanline
        if (state.dot > 340) {
            state.dot = 0;
            state.scanline += 1;

            // End of frame
            if (state.scanline > 261) {
                state.scanline = 0;
                state.frame += 1;
            }
        }

        // Odd frame skip: Skip dot 0 of scanline 0 on odd frames when rendering
        if (state.scanline == 0 and state.dot == 0 and (state.frame & 1) == 1 and state.mask.renderingEnabled()) {
            state.dot = 1;
        }

        // Capture current position AFTER advancing
        const scanline = state.scanline;
        const dot = state.dot;

        // Visible scanlines (0-239) + pre-render line (261)
        const is_visible = scanline < 240;
        const is_prerender = scanline == 261;
        const is_rendering_line = is_visible or is_prerender;

        // === Background Tile Fetching ===
        // Occurs during visible scanlines and pre-render line
        if (is_rendering_line and state.mask.renderingEnabled()) {
            // Shift registers every cycle (except dot 0)
            if (dot >= 1 and dot <= 256) {
                state.bg_state.shift();
            }

            // Tile fetching (dots 1-256 and 321-336)
            if ((dot >= 1 and dot <= 256) or (dot >= 321 and dot <= 336)) {
                fetchBackgroundTile(state);
            }

            // Dummy nametable fetches (dots 337-340)
            // Hardware fetches first two tiles of next scanline
            if (dot == 338 or dot == 340) {
                const nt_addr = 0x2000 | (state.internal.v & 0x0FFF);
                _ = state.readVram(nt_addr);
            }

            // Y increment at dot 256
            if (dot == 256) {
                incrementScrollY(state);
            }

            // Copy horizontal scroll at dot 257
            if (dot == 257) {
                copyScrollX(state);
            }

            // Copy vertical scroll during pre-render scanline
            if (is_prerender and dot >= 280 and dot <= 304) {
                copyScrollY(state);
            }
        }

        // === Sprite Evaluation ===
        // Secondary OAM clearing happens on ALL scanlines (visible + VBlank + pre-render)
        // Cycles 1-64: Clear secondary OAM to $FF
        if (dot >= 1 and dot <= 64) {
            // Clear bytes 0-31 during cycles 1-32
            // Cycles 33-64 are used for sprite evaluation setup
            const clear_index = dot - 1;
            if (clear_index < 32) {
                state.secondary_oam[clear_index] = 0xFF;
            }
        }

        // Sprite evaluation only occurs on visible scanlines (0-239) when rendering enabled
        if (is_visible) {
            // Cycles 65-256: Sprite evaluation
            // Evaluate sprites and copy up to 8 to secondary OAM
            // Only occurs when rendering is enabled
            if (dot == 65 and state.mask.renderingEnabled()) {
                evaluateSprites(state);
            }
        }

        // === Pixel Output ===
        // Render pixels to framebuffer during visible scanlines
        if (is_visible and dot >= 1 and dot <= 256) {
            const pixel_x = dot - 1;
            const pixel_y = scanline;

            // Get background pixel
            const bg_pixel = getBackgroundPixel(state);

            // Determine final color
            const palette_index = if (bg_pixel != 0)
                bg_pixel
            else
                state.palette_ram[0];  // Use backdrop color for transparent

            const color = getPaletteColor(state, palette_index);

            // Write to framebuffer
            if (framebuffer) |fb| {
                const fb_index = pixel_y * 256 + pixel_x;
                fb[fb_index] = color;
            }
        }

        // === VBlank Timing ===
        // VBlank start: Scanline 241, dot 1
        if (scanline == 241 and dot == 1) {
            state.status.vblank = true;

            // Trigger NMI if enabled
            if (state.ctrl.nmi_enable) {
                state.nmi_occurred = true;
            }
        }

        // === Pre-render Scanline ===
        // Pre-render scanline: Scanline 261, dot 1
        // Clear VBlank and sprite flags
        if (scanline == 261 and dot == 1) {
            state.status.vblank = false;
            state.status.sprite_0_hit = false;
            state.status.sprite_overflow = false;
            state.nmi_occurred = false;
        }
    }

    /// Check if NMI should be triggered
    /// Called by CPU to check NMI line
    pub fn pollNmi(state: *PpuState) bool {
        const nmi = state.nmi_occurred;
        state.nmi_occurred = false; // Clear on poll
        return nmi;
    }

    /// Decay open bus value (called once per frame)
    pub fn tickFrame(state: *PpuState) void {
        state.open_bus.decay();
    }

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "PpuCtrl: byte conversion" {
    const TestCtrl = StateModule.PpuCtrl;
    var ctrl = TestCtrl{};
    try testing.expectEqual(@as(u8, 0x00), ctrl.toByte());

    ctrl.nmi_enable = true;
    try testing.expectEqual(@as(u8, 0x80), ctrl.toByte());

    ctrl = TestCtrl.fromByte(0xFF);
    try testing.expect(ctrl.nmi_enable);
    try testing.expect(ctrl.sprite_size);
    try testing.expect(ctrl.vram_increment);
}

test "PpuMask: rendering enabled" {
    var mask = PpuMask{};
    try testing.expect(!mask.renderingEnabled());

    mask.show_bg = true;
    try testing.expect(mask.renderingEnabled());

    mask.show_bg = false;
    mask.show_sprites = true;
    try testing.expect(mask.renderingEnabled());
}

test "PpuStatus: open bus behavior" {
    var status = PpuStatus{};
    status.vblank = true;

    // With data bus = 0x1F (all open bus bits set)
    const value1 = status.toByte(0x1F);
    try testing.expectEqual(@as(u8, 0x9F), value1); // VBlank + open bus

    // With data bus = 0x00
    const value2 = status.toByte(0x00);
    try testing.expectEqual(@as(u8, 0x80), value2); // VBlank only
}

test "State: initialization" {
    const ppu = PpuState.init();
    try testing.expect(!ppu.ctrl.nmi_enable);
    try testing.expect(!ppu.mask.renderingEnabled());
    try testing.expect(!ppu.status.vblank);
}

test "State: PPUCTRL write" {
    var ppu = PpuState.init();

    ppu.writeRegister(0x2000, 0x80); // Enable NMI
    try testing.expect(ppu.ctrl.nmi_enable);
    try testing.expectEqual(@as(u8, 0x80), ppu.open_bus.value);
}

test "State: PPUSTATUS read clears VBlank" {
    var ppu = PpuState.init();
    ppu.status.vblank = true;

    const value = ppu.readRegister(0x2002);
    try testing.expectEqual(@as(u8, 0x80), value); // VBlank bit set
    try testing.expect(!ppu.status.vblank); // Cleared after read
}

test "State: write-only register reads return open bus" {
    var ppu = PpuState.init();
    ppu.open_bus.write(0x42);

    try testing.expectEqual(@as(u8, 0x42), ppu.readRegister(0x2000)); // PPUCTRL
    try testing.expectEqual(@as(u8, 0x42), ppu.readRegister(0x2001)); // PPUMASK
    try testing.expectEqual(@as(u8, 0x42), ppu.readRegister(0x2005)); // PPUSCROLL
}

test "State: register mirroring" {
    var ppu = PpuState.init();

    // Write to $2000
    ppu.writeRegister(0x2000, 0x80);
    try testing.expect(ppu.ctrl.nmi_enable);

    // Write to $2008 (mirror of $2000)
    ppu.writeRegister(0x2008, 0x00);
    try testing.expect(!ppu.ctrl.nmi_enable);

    // Write to $3456 (mirror of $2006)
    ppu.writeRegister(0x3456, 0x20);
    try testing.expect(ppu.internal.w); // First write to PPUADDR sets w flag
}

test "State: VBlank NMI generation" {
    var ppu = PpuState.init();
    ppu.ctrl.nmi_enable = true;

    // Advance to scanline 240, dot 340
    ppu.scanline = 240;
    ppu.dot = 340;
    ppu.tick(null);
    try testing.expect(!ppu.nmi_occurred);

    // Advance to scanline 241, dot 1 (VBlank start)
    ppu.scanline = 241;
    ppu.dot = 0;
    ppu.tick(null);  // This advances to dot 1
    try testing.expect(ppu.status.vblank);
    try testing.expect(ppu.nmi_occurred);
}

test "State: pre-render scanline clears flags" {
    var ppu = PpuState.init();
    ppu.status.vblank = true;
    ppu.status.sprite_0_hit = true;
    ppu.status.sprite_overflow = true;

    // Advance to scanline 261, dot 1 (pre-render)
    ppu.scanline = 261;
    ppu.dot = 0;
    ppu.tick(null);

    try testing.expect(!ppu.status.vblank);
    try testing.expect(!ppu.status.sprite_0_hit);
    try testing.expect(!ppu.status.sprite_overflow);
}

// ============================================================================
// VRAM Tests
// ============================================================================

test "VRAM: nametable read/write with horizontal mirroring" {
    var ppu = PpuState.init();
    ppu.mirroring = .horizontal;

    // NT0 ($2000-$23FF) and NT1 ($2400-$27FF) map to first 1KB
    ppu.writeVram(0x2000, 0xAA);
    try testing.expectEqual(@as(u8, 0xAA), ppu.readVram(0x2000));
    try testing.expectEqual(@as(u8, 0xAA), ppu.vram[0x0000]);

    ppu.writeVram(0x2400, 0xBB);
    try testing.expectEqual(@as(u8, 0xBB), ppu.readVram(0x2400));
    try testing.expectEqual(@as(u8, 0xBB), ppu.vram[0x0000]); // Same as NT0

    // NT2 ($2800-$2BFF) and NT3 ($2C00-$2FFF) map to second 1KB
    ppu.writeVram(0x2800, 0xCC);
    try testing.expectEqual(@as(u8, 0xCC), ppu.readVram(0x2800));
    try testing.expectEqual(@as(u8, 0xCC), ppu.vram[0x0400]);

    ppu.writeVram(0x2C00, 0xDD);
    try testing.expectEqual(@as(u8, 0xDD), ppu.readVram(0x2C00));
    try testing.expectEqual(@as(u8, 0xDD), ppu.vram[0x0400]); // Same as NT2
}

test "VRAM: nametable read/write with vertical mirroring" {
    var ppu = PpuState.init();
    ppu.mirroring = .vertical;

    // NT0 ($2000-$23FF) and NT2 ($2800-$2BFF) map to first 1KB
    ppu.writeVram(0x2000, 0xAA);
    try testing.expectEqual(@as(u8, 0xAA), ppu.readVram(0x2000));

    ppu.writeVram(0x2800, 0xBB);
    try testing.expectEqual(@as(u8, 0xBB), ppu.readVram(0x2800));
    try testing.expectEqual(@as(u8, 0xBB), ppu.vram[0x0000]); // Same as NT0

    // NT1 ($2400-$27FF) and NT3 ($2C00-$2FFF) map to second 1KB
    ppu.writeVram(0x2400, 0xCC);
    try testing.expectEqual(@as(u8, 0xCC), ppu.readVram(0x2400));

    ppu.writeVram(0x2C00, 0xDD);
    try testing.expectEqual(@as(u8, 0xDD), ppu.readVram(0x2C00));
    try testing.expectEqual(@as(u8, 0xDD), ppu.vram[0x0400]); // Same as NT1
}

test "VRAM: nametable mirrors ($3000-$3EFF)" {
    var ppu = PpuState.init();
    ppu.mirroring = .horizontal;

    // Write to nametable
    ppu.writeVram(0x2123, 0x42);

    // Read from mirror
    try testing.expectEqual(@as(u8, 0x42), ppu.readVram(0x3123));

    // Write to mirror
    ppu.writeVram(0x3456, 0x99);

    // Read from nametable
    try testing.expectEqual(@as(u8, 0x99), ppu.readVram(0x2456));
}

test "VRAM: palette RAM read/write" {
    var ppu = PpuState.init();

    // Background palette 0
    ppu.writeVram(0x3F00, 0x0F); // Backdrop
    ppu.writeVram(0x3F01, 0x30);
    ppu.writeVram(0x3F02, 0x10);
    ppu.writeVram(0x3F03, 0x00);

    try testing.expectEqual(@as(u8, 0x0F), ppu.readVram(0x3F00));
    try testing.expectEqual(@as(u8, 0x30), ppu.readVram(0x3F01));

    // Sprite palette 0
    ppu.writeVram(0x3F11, 0x38);
    try testing.expectEqual(@as(u8, 0x38), ppu.readVram(0x3F11));
}

test "VRAM: palette backdrop mirroring" {
    var ppu = PpuState.init();

    // Write to background backdrop
    ppu.writeVram(0x3F00, 0x0F);

    // Sprite palette 0 backdrop should mirror BG backdrop
    try testing.expectEqual(@as(u8, 0x0F), ppu.readVram(0x3F10));

    // Same for other sprite palettes
    ppu.writeVram(0x3F04, 0x30);
    try testing.expectEqual(@as(u8, 0x30), ppu.readVram(0x3F14));

    ppu.writeVram(0x3F08, 0x10);
    try testing.expectEqual(@as(u8, 0x10), ppu.readVram(0x3F18));

    ppu.writeVram(0x3F0C, 0x00);
    try testing.expectEqual(@as(u8, 0x00), ppu.readVram(0x3F1C));
}

test "VRAM: palette RAM mirrors ($3F20-$3FFF)" {
    var ppu = PpuState.init();

    // Write to palette RAM
    ppu.writeVram(0x3F05, 0x42);

    // Read from mirrors
    try testing.expectEqual(@as(u8, 0x42), ppu.readVram(0x3F25));
    try testing.expectEqual(@as(u8, 0x42), ppu.readVram(0x3F45));
    try testing.expectEqual(@as(u8, 0x42), ppu.readVram(0x3FE5));

    // Write to mirror
    ppu.writeVram(0x3F67, 0x99);

    // Read from base
    try testing.expectEqual(@as(u8, 0x99), ppu.readVram(0x3F07));
}

test "PPUDATA: read with buffering" {
    var ppu = PpuState.init();
    ppu.mirroring = .horizontal;

    // Write test data to VRAM
    ppu.writeVram(0x2000, 0xAA);
    ppu.writeVram(0x2001, 0xBB);
    ppu.writeVram(0x2002, 0xCC);

    // Set PPUADDR to $2000
    ppu.writeRegister(0x2006, 0x20);
    ppu.writeRegister(0x2006, 0x00);

    // First read returns buffer (0), buffer fills with $AA
    const read1 = ppu.readRegister(0x2007);
    try testing.expectEqual(@as(u8, 0x00), read1);

    // Second read returns $AA, buffer fills with $BB
    const read2 = ppu.readRegister(0x2007);
    try testing.expectEqual(@as(u8, 0xAA), read2);

    // Third read returns $BB
    const read3 = ppu.readRegister(0x2007);
    try testing.expectEqual(@as(u8, 0xBB), read3);
}

test "PPUDATA: palette reads not buffered" {
    var ppu = PpuState.init();

    // Write test data to palette
    ppu.writeVram(0x3F00, 0x0F);
    ppu.writeVram(0x3F01, 0x30);

    // Set PPUADDR to $3F00 (palette)
    ppu.writeRegister(0x2006, 0x3F);
    ppu.writeRegister(0x2006, 0x00);

    // Palette reads are NOT buffered - return immediately
    const read1 = ppu.readRegister(0x2007);
    try testing.expectEqual(@as(u8, 0x0F), read1);

    const read2 = ppu.readRegister(0x2007);
    try testing.expectEqual(@as(u8, 0x30), read2);
}

test "PPUDATA: write to VRAM" {
    var ppu = PpuState.init();
    ppu.mirroring = .horizontal;

    // Set PPUADDR to $2000
    ppu.writeRegister(0x2006, 0x20);
    ppu.writeRegister(0x2006, 0x00);

    // Write via PPUDATA
    ppu.writeRegister(0x2007, 0xAA);
    ppu.writeRegister(0x2007, 0xBB);
    ppu.writeRegister(0x2007, 0xCC);

    // Verify data written
    try testing.expectEqual(@as(u8, 0xAA), ppu.readVram(0x2000));
    try testing.expectEqual(@as(u8, 0xBB), ppu.readVram(0x2001));
    try testing.expectEqual(@as(u8, 0xCC), ppu.readVram(0x2002));
}

test "PPUDATA: VRAM increment +1" {
    var ppu = PpuState.init();

    // Set VRAM increment to +1 (PPUCTRL bit 2 = 0)
    ppu.writeRegister(0x2000, 0x00);

    // Set PPUADDR to $2000
    ppu.writeRegister(0x2006, 0x20);
    ppu.writeRegister(0x2006, 0x00);

    // Write 3 bytes
    ppu.writeRegister(0x2007, 0xAA);
    ppu.writeRegister(0x2007, 0xBB);
    ppu.writeRegister(0x2007, 0xCC);

    // VRAM address should now be $2003
    try testing.expectEqual(@as(u16, 0x2003), ppu.internal.v);
}

test "PPUDATA: VRAM increment +32" {
    var ppu = PpuState.init();

    // Set VRAM increment to +32 (PPUCTRL bit 2 = 1)
    ppu.writeRegister(0x2000, 0x04);

    // Set PPUADDR to $2000
    ppu.writeRegister(0x2006, 0x20);
    ppu.writeRegister(0x2006, 0x00);

    // Write 2 bytes
    ppu.writeRegister(0x2007, 0xAA);
    ppu.writeRegister(0x2007, 0xBB);

    // VRAM address should now be $2040 (2000 + 32 + 32)
    try testing.expectEqual(@as(u16, 0x2040), ppu.internal.v);
}

test "mirrorNametableAddress: horizontal mirroring" {
    // NT0 ($2000) -> VRAM $0000
    try testing.expectEqual(@as(u16, 0x0000), mirrorNametableAddress(0x2000, .horizontal));

    // NT1 ($2400) -> VRAM $0000 (same as NT0)
    try testing.expectEqual(@as(u16, 0x0000), mirrorNametableAddress(0x2400, .horizontal));

    // NT2 ($2800) -> VRAM $0400
    try testing.expectEqual(@as(u16, 0x0400), mirrorNametableAddress(0x2800, .horizontal));

    // NT3 ($2C00) -> VRAM $0400 (same as NT2)
    try testing.expectEqual(@as(u16, 0x0400), mirrorNametableAddress(0x2C00, .horizontal));

    // Test with offset
    try testing.expectEqual(@as(u16, 0x0123), mirrorNametableAddress(0x2123, .horizontal));
    try testing.expectEqual(@as(u16, 0x0123), mirrorNametableAddress(0x2523, .horizontal));
}

test "mirrorNametableAddress: vertical mirroring" {
    // NT0 ($2000) -> VRAM $0000
    try testing.expectEqual(@as(u16, 0x0000), mirrorNametableAddress(0x2000, .vertical));

    // NT1 ($2400) -> VRAM $0400
    try testing.expectEqual(@as(u16, 0x0400), mirrorNametableAddress(0x2400, .vertical));

    // NT2 ($2800) -> VRAM $0000 (same as NT0)
    try testing.expectEqual(@as(u16, 0x0000), mirrorNametableAddress(0x2800, .vertical));

    // NT3 ($2C00) -> VRAM $0400 (same as NT1)
    try testing.expectEqual(@as(u16, 0x0400), mirrorNametableAddress(0x2C00, .vertical));
}

test "mirrorPaletteAddress: backdrop mirroring" {
    // Background backdrops map to themselves
    try testing.expectEqual(@as(u8, 0x00), mirrorPaletteAddress(0x00));
    try testing.expectEqual(@as(u8, 0x04), mirrorPaletteAddress(0x04));
    try testing.expectEqual(@as(u8, 0x08), mirrorPaletteAddress(0x08));
    try testing.expectEqual(@as(u8, 0x0C), mirrorPaletteAddress(0x0C));

    // Sprite backdrops mirror to background backdrops
    try testing.expectEqual(@as(u8, 0x00), mirrorPaletteAddress(0x10));
    try testing.expectEqual(@as(u8, 0x04), mirrorPaletteAddress(0x14));
    try testing.expectEqual(@as(u8, 0x08), mirrorPaletteAddress(0x18));
    try testing.expectEqual(@as(u8, 0x0C), mirrorPaletteAddress(0x1C));

    // Non-backdrop colors map to themselves
    try testing.expectEqual(@as(u8, 0x01), mirrorPaletteAddress(0x01));
    try testing.expectEqual(@as(u8, 0x11), mirrorPaletteAddress(0x11));
    try testing.expectEqual(@as(u8, 0x1F), mirrorPaletteAddress(0x1F));
}
