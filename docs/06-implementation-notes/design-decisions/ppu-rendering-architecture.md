# PPU Rendering Architecture Design

**Date:** 2025-10-03
**Status:** Design Phase
**References:** NESdev Wiki - PPU rendering, PPU scrolling, PPU palettes, Pattern tables

## Hardware Specifications (From NESdev Wiki)

### Timing Constants
- **Frame Structure:** 262 scanlines (NTSC)
- **Scanline Length:** 341 PPU cycles
- **Visible Scanlines:** 0-239 (240 lines)
- **Visible Pixels:** 256 pixels wide
- **VBlank:** Scanlines 240-260
- **Pre-render:** Scanline 261 (-1)

### Rendering Pipeline Per Scanline

#### Background Rendering (Every 8 Pixels)
**4 Memory Fetches per Tile:**
1. **Nametable Byte** (Cycle 0-1): Which tile to display
2. **Attribute Byte** (Cycle 2-3): Palette selection (2 bits)
3. **Pattern Low Byte** (Cycle 4-5): Bitplane 0 of tile graphics
4. **Pattern High Byte** (Cycle 6-7): Bitplane 1 of tile graphics

**Shift Registers:**
- Two 16-bit shift registers for pattern data
- Two 8-bit shift registers for palette data
- Shift every pixel, reload every 8 pixels

#### Sprite Rendering
**Evaluation (Cycles 65-256):**
- Scan OAM for sprites on next scanline
- Select first 8 sprites (hardware limitation)
- Copy to secondary OAM

**Fetching (Cycles 257-320):**
- 8 cycles per sprite (8 sprites × 8 = 64 cycles)
- Fetch pattern data for selected sprites
- Load sprite shift registers

### Internal Registers (Scrolling)

```
v register (15 bits): yyy NN YYYYY XXXXX
- yyy: Fine Y scroll (0-7)
- NN: Nametable select (0-3)
- YYYYY: Coarse Y scroll (0-29)
- XXXXX: Coarse X scroll (0-31)

t register (15 bits): Temporary VRAM address
x register (3 bits): Fine X scroll (0-7)
w register (1 bit): Write toggle (first/second write)
```

### Pattern Table Encoding

**Each 8×8 Tile = 16 Bytes:**
```
Bitplane 0 (bytes 0-7): Low bit of color index
Bitplane 1 (bytes 8-15): High bit of color index

Color Index = (bitplane1_bit << 1) | bitplane0_bit
- 0: Transparent (use backdrop)
- 1-3: Palette color
```

### Palette System

**Palette RAM ($3F00-$3F1F):**
```
$3F00-$3F0F: Background palettes (4 palettes × 4 colors)
$3F10-$3F1F: Sprite palettes (4 palettes × 4 colors)

Palette Entry = 2-bit attribute + 2-bit pattern → 4-bit index
Final Color = palette_ram[palette_base + palette_entry]
```

## Implementation Design

### Phase 1: Background Rendering (Minimal)

#### Data Structures

```zig
/// Background rendering state
pub const BackgroundState = struct {
    /// Shift registers for pattern data
    pattern_shift_lo: u16 = 0,
    pattern_shift_hi: u16 = 0,

    /// Shift registers for attribute/palette data
    attribute_shift_lo: u8 = 0,
    attribute_shift_hi: u8 = 0,

    /// Latches for next tile data
    nametable_latch: u8 = 0,
    attribute_latch: u8 = 0,
    pattern_latch_lo: u8 = 0,
    pattern_latch_hi: u8 = 0,

    /// Tile fetch cycle (0-7)
    fetch_cycle: u3 = 0,
};
```

#### Rendering State Machine

```zig
pub fn renderPixel(
    self: *Ppu,
    scanline: u16,
    dot: u16,
    framebuffer: []u32
) void {
    // Only render on visible scanlines and dots
    if (scanline >= 240 or dot >= 256) return;

    // Skip if rendering disabled
    if (!self.mask.show_bg and !self.mask.show_sprites) return;

    // Background pixel
    const bg_pixel = if (self.mask.show_bg)
        self.getBackgroundPixel()
    else
        0;

    // Sprite pixel (Phase 2)
    const sprite_pixel = if (self.mask.show_sprites)
        self.getSpritePixel()
    else
        0;

    // Priority and transparency
    const final_pixel = self.compositePixel(bg_pixel, sprite_pixel);

    // Lookup in palette and write to framebuffer
    const color = self.getPaletteColor(final_pixel);
    const fb_index = scanline * 256 + dot;
    framebuffer[fb_index] = color;
}
```

#### Background Tile Fetching

```zig
fn fetchBackgroundTile(self: *Ppu, cycle: u16) void {
    const fetch_phase = cycle & 0x07;

    switch (fetch_phase) {
        0, 1 => {
            // Fetch nametable byte
            const nt_addr = 0x2000 | (self.internal.v & 0x0FFF);
            self.bg_state.nametable_latch = self.readVram(nt_addr);
        },
        2, 3 => {
            // Fetch attribute byte
            const attr_addr = 0x23C0 |
                (self.internal.v & 0x0C00) |
                ((self.internal.v >> 4) & 0x38) |
                ((self.internal.v >> 2) & 0x07);
            self.bg_state.attribute_latch = self.readVram(attr_addr);
        },
        4, 5 => {
            // Fetch pattern low byte
            const pattern_addr = self.getPatternAddress(false);
            self.bg_state.pattern_latch_lo = self.readVram(pattern_addr);
        },
        6, 7 => {
            // Fetch pattern high byte
            const pattern_addr = self.getPatternAddress(true);
            self.bg_state.pattern_latch_hi = self.readVram(pattern_addr);

            // Load shift registers
            self.loadShiftRegisters();

            // Increment coarse X
            self.incrementScrollX();
        },
        else => unreachable,
    }
}
```

#### Pattern Address Calculation

```zig
fn getPatternAddress(self: *Ppu, high_bitplane: bool) u16 {
    // Pattern table base from PPUCTRL
    const pattern_base: u16 = if (self.ctrl.bg_pattern) 0x1000 else 0x0000;

    // Tile index from nametable
    const tile_index: u16 = self.bg_state.nametable_latch;

    // Fine Y from v register
    const fine_y: u16 = (self.internal.v >> 12) & 0x07;

    // Bitplane offset
    const bitplane_offset: u16 = if (high_bitplane) 8 else 0;

    return pattern_base + (tile_index * 16) + fine_y + bitplane_offset;
}
```

#### Scroll Increment Logic

```zig
fn incrementScrollX(self: *Ppu) void {
    if ((self.internal.v & 0x001F) == 31) {
        // Coarse X = 0, switch horizontal nametable
        self.internal.v &= ~@as(u16, 0x001F);
        self.internal.v ^= 0x0400;
    } else {
        // Increment coarse X
        self.internal.v += 1;
    }
}

fn incrementScrollY(self: *Ppu) void {
    if ((self.internal.v & 0x7000) != 0x7000) {
        // Increment fine Y
        self.internal.v += 0x1000;
    } else {
        // Fine Y = 0
        self.internal.v &= ~@as(u16, 0x7000);

        var coarse_y = (self.internal.v >> 5) & 0x1F;
        if (coarse_y == 29) {
            // Coarse Y = 0, switch vertical nametable
            coarse_y = 0;
            self.internal.v ^= 0x0800;
        } else if (coarse_y == 31) {
            // Out of bounds, wrap without nametable switch
            coarse_y = 0;
        } else {
            coarse_y += 1;
        }

        self.internal.v = (self.internal.v & ~@as(u16, 0x03E0)) | (coarse_y << 5);
    }
}
```

#### Pixel Output

```zig
fn getBackgroundPixel(self: *Ppu) u8 {
    if (!self.mask.show_bg) return 0;

    // Apply fine X scroll
    const shift_amount = 15 - self.internal.x;

    // Get bits from shift registers
    const bit0 = (self.bg_state.pattern_shift_lo >> shift_amount) & 1;
    const bit1 = (self.bg_state.pattern_shift_hi >> shift_amount) & 1;

    // 2-bit pattern value
    const pattern = @as(u8, @intCast((bit1 << 1) | bit0));

    if (pattern == 0) return 0; // Transparent

    // Get attribute bits
    const attr_bit0 = (self.bg_state.attribute_shift_lo >> 7) & 1;
    const attr_bit1 = (self.bg_state.attribute_shift_hi >> 7) & 1;
    const palette = @as(u8, @intCast((attr_bit1 << 1) | attr_bit0));

    // Combine into palette index
    return (palette << 2) | pattern;
}

fn getPaletteColor(self: *Ppu, palette_index: u8) u32 {
    // Read from palette RAM
    const nes_color = self.palette_ram[palette_index & 0x1F];

    // Convert NES color to RGB (using standard palette)
    return NES_PALETTE[nes_color & 0x3F];
}
```

### Phase 2: Sprite Rendering

#### Sprite Evaluation State Machine

```zig
pub const SpriteState = struct {
    /// Secondary OAM (8 sprites)
    secondary_oam: [32]u8 = [_]u8{0xFF} ** 32,

    /// Sprite pattern shift registers (8 sprites)
    pattern_shift_lo: [8]u8 = [_]u8{0} ** 8,
    pattern_shift_hi: [8]u8 = [_]u8{0} ** 8,

    /// Sprite attributes (8 sprites)
    attributes: [8]u8 = [_]u8{0} ** 8,

    /// Sprite X counters (8 sprites)
    x_counters: [8]u8 = [_]u8{0} ** 8,

    /// Sprite 0 present on this scanline
    sprite_0_present: bool = false,

    /// Number of sprites found
    sprite_count: u8 = 0,
};
```

#### Sprite Evaluation (Cycles 65-256)

```zig
fn evaluateSprites(self: *Ppu, scanline: u16) void {
    self.sprite_state.sprite_count = 0;
    self.sprite_state.sprite_0_present = false;

    const sprite_height: u8 = if (self.ctrl.sprite_size) 16 else 8;

    for (0..64) |i| {
        if (self.sprite_state.sprite_count >= 8) {
            // Sprite overflow
            self.status.sprite_overflow = true;
            break;
        }

        const y = self.oam[i * 4];
        const diff = scanline -% y;

        if (diff < sprite_height) {
            // Sprite is on this scanline
            const sprite_idx = self.sprite_state.sprite_count;

            // Copy to secondary OAM
            const oam_offset = i * 4;
            const sec_oam_offset = sprite_idx * 4;
            @memcpy(
                self.sprite_state.secondary_oam[sec_oam_offset..][0..4],
                self.oam[oam_offset..][0..4]
            );

            if (i == 0) {
                self.sprite_state.sprite_0_present = true;
            }

            self.sprite_state.sprite_count += 1;
        }
    }
}
```

### NES Palette Lookup Table

```zig
/// Standard NTSC NES palette (64 colors as RGB)
pub const NES_PALETTE = [64]u32{
    0x545454, 0x001E74, 0x081090, 0x300088, 0x440064, 0x5C0030, 0x540400, 0x3C1800,
    0x202A00, 0x083A00, 0x004000, 0x003C00, 0x00323C, 0x000000, 0x000000, 0x000000,
    0x989698, 0x084CC4, 0x3032EC, 0x5C1EE4, 0x8814B0, 0xA01464, 0x982220, 0x783C00,
    0x545A00, 0x287200, 0x087C00, 0x007628, 0x006678, 0x000000, 0x000000, 0x000000,
    0xECEEEC, 0x4C9AEC, 0x787CEC, 0xB062EC, 0xE454EC, 0xEC58B4, 0xEC6A64, 0xD48820,
    0xA0AA00, 0x74C400, 0x4CD020, 0x38CC6C, 0x38B4CC, 0x3C3C3C, 0x000000, 0x000000,
    0xECEEEC, 0xA8CCEC, 0xBCBCEC, 0xD4B2EC, 0xECAEEC, 0xECAED4, 0xECB4B0, 0xE4C490,
    0xCCD278, 0xB4DE78, 0xA8E290, 0x98E2B4, 0xA0D6E4, 0xA0A2A0, 0x000000, 0x000000,
};
```

## Testing Strategy

### Unit Tests
1. **Pattern Decoding** - Verify bitplane → color index conversion
2. **Palette Lookup** - Test palette RAM addressing and mirroring
3. **Scroll Increment** - Validate coarse X/Y increment logic
4. **Attribute Calculation** - Test 2×2 tile attribute addressing

### Integration Tests
1. **Single Tile Render** - Render one 8×8 tile, verify pixels
2. **Nametable Render** - Full 32×30 tile screen
3. **Palette Test** - Different palettes on same pattern
4. **Scroll Test** - Render with various scroll positions

### Reference ROMs
- Use known test patterns from AccuracyCoin
- Compare framebuffer output with reference images
- Verify cycle-accurate timing with known sequences

## Implementation Phases

### Phase 1: Minimal Background Rendering ✅ (This Session)
- Background tile fetching state machine
- Pattern table decoding
- Palette lookup
- Shift register implementation
- No scrolling (fixed position)
- **Output:** Static background rendering

### Phase 2: Sprite Rendering (Next Session)
- Sprite evaluation algorithm
- Sprite pattern fetching
- Priority and transparency
- Sprite 0 hit detection
- **Output:** Background + sprites

### Phase 3: Scrolling (Future)
- Coarse scroll (nametable switching)
- Fine scroll (sub-pixel)
- Mid-screen scroll changes
- **Output:** Scrolling games functional

### Phase 4: Advanced Features (Future)
- 8×16 sprite mode
- Sprite overflow bug emulation
- Emphasis bits (color tinting)
- **Output:** Full compatibility

## Hardware Quirks to Implement

1. **Sprite 0 Hit:** Set when non-transparent pixels overlap
2. **Sprite Overflow:** Hardware bug with inconsistent behavior
3. **Odd Frame Skip:** Scanline 261, dot 0 skipped on odd frames (already implemented)
4. **VRAM Access Timing:** Cannot read VRAM during active rendering
5. **Palette Backdrop:** $3F10/$3F14/$3F18/$3F1C mirror $3F00/$3F04/$3F08/$3F0C

## References

All implementation based on NESdev Wiki:
- https://www.nesdev.org/wiki/PPU_rendering
- https://www.nesdev.org/wiki/PPU_scrolling
- https://www.nesdev.org/wiki/PPU_palettes
- https://www.nesdev.org/wiki/PPU_pattern_tables
- https://www.nesdev.org/wiki/PPU_sprite_evaluation
