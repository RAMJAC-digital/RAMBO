# NES PPU SPRITE RENDERING SPECIFICATION

**Source:** nesdev.org (https://www.nesdev.org/wiki/PPU_sprite_evaluation)
**Target:** RAMBO Phase 7 (Sprite Implementation)
**Estimated Effort:** 27-38 hours
**Prerequisites:** Phase 4 sprite tests complete

---

## OVERVIEW

The NES PPU sprite system handles up to 64 sprites (8×8 or 8×16 pixels) with a limit of 8 sprites per scanline. Sprite evaluation and rendering occur in parallel with background rendering.

**Key Components:**
1. **OAM (Object Attribute Memory):** 256 bytes, 64 sprites × 4 bytes each
2. **Secondary OAM:** 32 bytes, 8 sprites × 4 bytes each
3. **Sprite Evaluation:** Cycles 65-256 of each visible scanline
4. **Sprite Fetching:** Cycles 257-320 of each visible scanline
5. **Sprite Rendering:** Cycles 1-256 of each visible scanline (next scanline's sprites)

---

## OAM STRUCTURE

**Primary OAM (256 bytes at $2004):**
```
Sprite N (4 bytes):
  Byte 0: Y position (0-255)
  Byte 1: Tile index (0-255)
  Byte 2: Attributes
    Bit 7-6: Palette (0-3, selects $3F10-$3F1F range)
    Bit 5: Priority (0=front, 1=behind background)
    Bit 4-3: Unused (should be 0)
    Bit 2: Unused (should be 0)
    Bit 1: Horizontal flip
    Bit 0: Vertical flip
  Byte 3: X position (0-255)
```

**Secondary OAM (32 bytes, internal):**
- Same structure as primary OAM
- Holds up to 8 sprites for current scanline
- Cleared to $FF at start of sprite evaluation

---

## SPRITE EVALUATION ALGORITHM

**Timing:** Cycles 1-256 of visible scanlines (0-239)

### Phase 1: Clear Secondary OAM (Cycles 1-64)

**Action:** Write $FF to all 32 bytes of secondary OAM
**Hardware:** 2 cycles per byte (64 cycles total)

```zig
// Pseudocode
fn clearSecondaryOam(state: *PpuState) void {
    if (state.dot >= 1 and state.dot <= 64) {
        const idx = (state.dot - 1) >> 1;  // Divide by 2 (2 cycles per byte)
        if ((state.dot & 1) == 0) {  // Even cycles
            state.secondary_oam[idx] = 0xFF;
        }
    }
}
```

### Phase 2: Sprite Evaluation (Cycles 65-256)

**Action:** Scan primary OAM for sprites in range, copy to secondary OAM

**Algorithm:**
1. Read sprite Y coordinate from primary OAM (odd cycles)
2. Check if sprite is in range for NEXT scanline
3. If in range and <8 sprites found: Copy 4 bytes to secondary OAM
4. If 8 sprites found: Continue scanning for overflow detection
5. If >8 sprites on scanline: Set sprite overflow flag (with hardware bug)

**In-Range Check:**
```zig
fn isSpriteInRange(sprite_y: u8, scanline: u16, sprite_height: u8) bool {
    // Sprite is visible if:
    // scanline >= sprite_y AND scanline < sprite_y + sprite_height
    // Note: Rendered on NEXT scanline (1-line offset)
    const next_scanline = scanline + 1;

    if (next_scanline >= sprite_y and next_scanline < sprite_y + sprite_height) {
        return true;
    }
    return false;
}
```

**Sprite Height:**
- 8×8 mode (PPUCTRL bit 5 = 0): height = 8
- 8×16 mode (PPUCTRL bit 5 = 1): height = 16

### Phase 3: Sprite Overflow Detection (Cycles 65-256, after 8 sprites found)

**Hardware Bug:** After 8 sprites found, continues scanning with incorrect address increment

**Buggy Behavior:**
1. Read Y coordinate (odd cycle)
2. If in range: Set overflow flag, increment sprite index
3. If NOT in range: Increment m (attribute counter) instead of n (sprite index)
4. This causes "diagonal" OAM scan, missing sprites and setting false flags

**Result:** Sprite overflow flag is unreliable (sometimes set incorrectly, sometimes not set when should be)

**Implementation Note:** For accuracy, implement buggy behavior. For simplicity, can use correct behavior (always set overflow if >8 sprites).

---

## SPRITE FETCHING ALGORITHM

**Timing:** Cycles 257-320 of visible scanlines (0-239)

**Action:** Fetch pattern data for 8 sprites in secondary OAM

### Fetch Sequence (8 cycles per sprite)

**For each sprite (0-7):**
1. **Cycles 257, 265, 273, ... (Garbage NT):** Dummy nametable read
2. **Cycles 259, 267, 275, ... (Garbage NT):** Dummy nametable read
3. **Cycles 261, 269, 277, ... (PT low):** Fetch pattern table bitplane 0
4. **Cycles 263, 271, 279, ... (PT high):** Fetch pattern table bitplane 1

**If <8 sprites in secondary OAM:** Fetch from sprite 63 (or use $FF bytes)

### Pattern Address Calculation

**8×8 Mode (PPUCTRL bit 5 = 0):**
```zig
fn getSpritePatternAddress(
    tile_index: u8,
    row: u8,  // 0-7, which row of sprite to render
    bitplane: u1,  // 0 or 1
    pattern_table: u1,  // PPUCTRL bit 3
    vertical_flip: bool,
) u16 {
    var sprite_row = row;
    if (vertical_flip) {
        sprite_row = 7 - row;  // Flip vertically
    }

    const pattern_base: u16 = if (pattern_table == 1) 0x1000 else 0x0000;
    const tile_offset: u16 = @as(u16, tile_index) * 16;
    const bitplane_offset: u16 = if (bitplane == 1) 8 else 0;

    return pattern_base + tile_offset + sprite_row + bitplane_offset;
}
```

**8×16 Mode (PPUCTRL bit 5 = 1):**
```zig
fn getSprite16PatternAddress(
    tile_index: u8,  // Bit 0 selects pattern table
    row: u8,  // 0-15, which row of sprite to render
    bitplane: u1,
    vertical_flip: bool,
) u16 {
    var sprite_row = row;
    if (vertical_flip) {
        sprite_row = 15 - row;  // Flip vertically
    }

    // Pattern table from tile bit 0
    const pattern_base: u16 = if ((tile_index & 1) == 1) 0x1000 else 0x0000;

    // Top half (rows 0-7) uses tile_index & 0xFE
    // Bottom half (rows 8-15) uses (tile_index & 0xFE) + 1
    const tile = if (sprite_row < 8)
        (tile_index & 0xFE)
    else
        (tile_index & 0xFE) + 1;

    const tile_offset: u16 = @as(u16, tile) * 16;
    const row_offset: u16 = sprite_row & 7;  // Row within 8×8 tile
    const bitplane_offset: u16 = if (bitplane == 1) 8 else 0;

    return pattern_base + tile_offset + row_offset + bitplane_offset;
}
```

---

## SPRITE RENDERING ALGORITHM

**Timing:** Cycles 1-256 of visible scanlines (0-239)
**Note:** Renders sprites fetched on PREVIOUS scanline

### Sprite Shift Registers

**For each sprite (0-7):**
```zig
pub const SpriteState = struct {
    pattern_low: u8,   // Bitplane 0 (from previous scanline fetch)
    pattern_high: u8,  // Bitplane 1
    attributes: u8,    // Palette, priority, flip bits
    x_counter: u8,     // Counts down from X position to 0
    active: bool,      // True when x_counter == 0 (sprite is rendering)
};
```

### Rendering Loop (Each Pixel)

```zig
fn getSpritePixel(state: *PpuState, pixel_x: u8) ?SpritePixel {
    // Check each sprite in priority order (0 = highest priority)
    for (state.sprite_state, 0..) |*sprite, i| {
        // Sprite not active yet
        if (sprite.x_counter > 0) {
            sprite.x_counter -= 1;
            continue;
        }

        // Sprite finished rendering (8 pixels)
        if (sprite.x_counter == 0 and !sprite.active) {
            continue;
        }

        // Activate sprite at x_counter == 0
        if (sprite.x_counter == 0 and !sprite.active) {
            sprite.active = true;
        }

        // Get pixel from shift registers
        const horizontal_flip = (sprite.attributes & 0x01) != 0;
        const shift_amount: u3 = if (horizontal_flip)
            @truncate(pixel_x - sprite.x_position)  // Left to right
        else
            @truncate(7 - (pixel_x - sprite.x_position));  // Right to left

        const bit0 = (sprite.pattern_low >> shift_amount) & 1;
        const bit1 = (sprite.pattern_high >> shift_amount) & 1;
        const pattern: u8 = @intCast((bit1 << 1) | bit0);

        // Transparent pixel (color 0)
        if (pattern == 0) continue;

        // Found visible sprite pixel
        const palette = (sprite.attributes >> 6) & 0x03;
        const priority = (sprite.attributes >> 5) & 0x01;

        return SpritePixel{
            .palette_index = 0x10 | (palette << 2) | pattern,  // $10-$1F range
            .priority = priority,
            .sprite_0 = (i == 0),  // First sprite is sprite 0
        };
    }

    return null;  // No sprite pixel
}
```

---

## SPRITE PRIORITY SYSTEM

**Pixel Output (combines background + sprite):**

```zig
fn getPixelColor(state: *PpuState, pixel_x: u8, pixel_y: u8) u32 {
    const bg_pixel = getBackgroundPixel(state);
    const sprite_pixel = getSpritePixel(state, pixel_x);

    // Priority rules:
    // 1. If no sprite pixel → use background
    // 2. If no background pixel (transparent) → use sprite
    // 3. If both present → check sprite priority bit
    //    - Priority 0 (front): sprite wins
    //    - Priority 1 (back): background wins (unless BG is transparent)

    if (sprite_pixel == null) {
        // No sprite, use background
        return getPaletteColor(state, bg_pixel);
    }

    if (bg_pixel == 0) {
        // Background transparent, use sprite
        return getPaletteColor(state, sprite_pixel.?.palette_index);
    }

    // Both present, check priority
    if (sprite_pixel.?.priority == 0) {
        // Sprite in front
        return getPaletteColor(state, sprite_pixel.?.palette_index);
    } else {
        // Sprite behind, background wins
        return getPaletteColor(state, bg_pixel);
    }
}
```

---

## SPRITE 0 HIT DETECTION

**Condition:** Sprite 0 pixel (non-transparent) overlaps with background pixel (non-transparent)

**Timing:** Set flag during rendering (cycles 1-256)
**Clear:** Pre-render scanline (scanline 261, dot 1)

**Detection:**
```zig
fn checkSprite0Hit(state: *PpuState, bg_pixel: u8, sprite_pixel: ?SpritePixel) void {
    // Sprite 0 hit only if:
    // 1. Sprite pixel is from sprite 0
    // 2. Sprite pixel is not transparent (pattern != 0)
    // 3. Background pixel is not transparent (bg_pixel != 0)
    // 4. Not at X=255 (hardware limitation)
    // 5. Rendering is enabled (show_bg or show_sprites)

    if (sprite_pixel) |sp| {
        if (sp.sprite_0 and bg_pixel != 0 and state.dot < 255) {
            if (state.mask.show_bg or state.mask.show_sprites) {
                state.status.sprite_0_hit = true;
            }
        }
    }
}
```

**Important Notes:**
- Earliest detection: Cycle 2 (not cycle 1, hardware delay)
- Not set if left column clipping enabled and X < 8
- Flag persists until cleared at pre-render scanline

---

## OAM DMA ($4014 REGISTER)

**Purpose:** Fast copy of 256 bytes from CPU RAM to OAM

**CPU Write to $4014:**
```zig
pub fn oamDma(state: *BusState, page: u8) void {
    // Suspend CPU for 513-514 cycles
    // Odd CPU cycle: 514 cycles (1 dummy cycle + 513 DMA cycles)
    // Even CPU cycle: 513 cycles

    const base_addr: u16 = @as(u16, page) << 8;  // Page * 256

    // Copy 256 bytes from CPU memory to OAM
    for (0..256) |i| {
        const value = state.read(base_addr + @as(u16, @intCast(i)));
        state.ppu.oam[i] = value;
    }

    // CPU cycles consumed: 513 or 514 depending on alignment
    const cycles = if ((state.cycle & 1) == 1) 514 else 513;
    state.cpu_suspended_cycles = cycles;
}
```

**Timing:**
- 1 cycle: Dummy read (alignment)
- 512 cycles: 256 reads + 256 writes (2 cycles per byte)
- Total: 513-514 cycles

---

## IMPLEMENTATION CHECKLIST

### Phase 7.1: Sprite Evaluation (8-12 hours)
- [ ] Implement secondary OAM clearing (cycles 1-64)
- [ ] Implement sprite in-range check
- [ ] Implement sprite copying to secondary OAM (cycles 65-256)
- [ ] Implement sprite overflow detection (with or without bug)
- [ ] Add sprite evaluation tests (12-15 tests from Phase 4.1)

### Phase 7.2: Sprite Fetching (6-8 hours)
- [ ] Implement sprite fetch sequence (cycles 257-320)
- [ ] Implement 8×8 pattern address calculation
- [ ] Implement 8×16 pattern address calculation
- [ ] Implement vertical flip
- [ ] Add sprite fetching tests

### Phase 7.3: Sprite Rendering (8-12 hours)
- [ ] Implement sprite shift registers
- [ ] Implement sprite pixel extraction
- [ ] Implement horizontal flip
- [ ] Implement sprite priority system
- [ ] Add sprite rendering tests (15-20 tests from Phase 4.1)

### Phase 7.4: Sprite 0 Hit (4-6 hours)
- [ ] Implement sprite 0 hit detection
- [ ] Implement timing (earliest at cycle 2)
- [ ] Implement flag clear at pre-render
- [ ] Add sprite 0 hit tests (8-10 tests from Phase 4.1)

### Phase 7.5: OAM DMA (3-4 hours)
- [ ] Implement $4014 register write handler
- [ ] Implement CPU suspension (513-514 cycles)
- [ ] Implement 256-byte copy
- [ ] Add OAM DMA tests

**Total Estimate:** 29-42 hours

---

## TESTING STRATEGY

### Unit Tests (Isolated Components)
1. **Sprite Evaluation:**
   - Secondary OAM clearing
   - In-range detection
   - 8-sprite limit
   - Overflow flag

2. **Sprite Fetching:**
   - Pattern address calculation (8×8, 8×16)
   - Vertical flip
   - Bitplane reads

3. **Sprite Rendering:**
   - Pixel extraction
   - Horizontal flip
   - Priority system
   - Transparency

4. **Sprite 0 Hit:**
   - Hit detection logic
   - Timing constraints
   - Flag persistence

### Integration Tests (Real Scenarios)
1. **8 Sprites on Scanline:** Verify rendering and priority
2. **>8 Sprites:** Verify overflow flag and sprite dropout
3. **Sprite 0 Hit:** Verify hit detection in real rendering context
4. **OAM DMA:** Verify fast copy and CPU suspension
5. **8×16 Sprites:** Verify pattern selection and rendering
6. **Flipping:** Verify horizontal/vertical flip combinations
7. **Scrolling with Sprites:** Verify sprite-background interaction

---

## REFERENCE IMAGES (nesdev.org)

**Sprite Evaluation Timing:**
```
Scanline Y:
  Cycles 1-64:   Clear secondary OAM
  Cycles 65-256: Evaluate sprites (find up to 8 in range)
  Cycles 257-320: Fetch sprite data (for next scanline)
  Cycles 321-340: Background prefetch

Scanline Y+1:
  Cycles 1-256: Render sprites fetched above
  ... (repeat)
```

**Sprite Pixel Pipeline:**
```
X Counter → Active → Shift → Pattern → Palette → Priority → Output
   255        false    n/a      n/a      n/a       n/a      (skip)
   ...
     1        false    n/a      n/a      n/a       n/a      (skip)
     0        true     shift    2-bit    $10-$1F   0/1      (render)
   ...        true     shift    2-bit    $10-$1F   0/1      (render 8 pixels)
```

---

## HARDWARE QUIRKS SUMMARY

1. **1-Line Offset:** Sprites evaluated on scanline Y render on scanline Y+1
2. **Sprite Overflow Bug:** Diagonal OAM scan after 8 sprites (unreliable flag)
3. **Sprite 0 Hit Delay:** Earliest detection at cycle 2 (not cycle 1)
4. **OAM DMA Alignment:** 513 vs 514 cycles depending on CPU cycle parity
5. **8×16 Pattern Table:** Tile bit 0 selects pattern table (not PPUCTRL)

---

**Prepared by:** Claude (agent-docs-architect-pro)
**Source:** nesdev.org PPU documentation
**Target Implementation:** RAMBO Phase 7
**Verification:** Ready for implementation after Phase 4 tests complete
