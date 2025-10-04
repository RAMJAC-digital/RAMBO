# Phase 4.2: Sprite Rendering Test Status

**Date:** 2025-10-03
**Phase:** 4.2 - PPU Test Expansion (Sprite Rendering)
**Status:** Tests Created ✅ | Implementation Pending ⏳

---

## Overview

Phase 4.2 creates comprehensive sprite rendering tests following the TDD approach. Tests verify sprite fetching, pattern address calculation, shift registers, priority system, and rendering output.

**Total Tests Created:** 23
**Tests Passing:** 23/23 (100%) - All compile ✅
**Tests Failing:** 23/23 (100%) - **EXPECTED** (sprite rendering not implemented)

---

## Test Results Summary

### ✅ ALL TESTS COMPILE (23/23)

All tests compile successfully but fail at runtime (expected - sprite rendering logic not implemented yet).

### Test Categories

#### 1. Pattern Address Calculation (8×8 mode) - 3 tests
- `Sprite Rendering: 8×8 pattern address calculation`
- `Sprite Rendering: 8×8 pattern address with alternate pattern table`
- `Sprite Rendering: 8×8 vertical flip`

**Verification Points:**
- Pattern table base ($0000 or $1000 from PPUCTRL bit 3)
- Tile index × 16 bytes per tile
- Row offset (0-7)
- Bitplane offset (+8 for bitplane 1)
- Vertical flip (row = 7 - row)

**Expected Implementation:** `Logic.getSpritePatternAddress()`

#### 2. Pattern Address Calculation (8×16 mode) - 4 tests
- `Sprite Rendering: 8×16 pattern address calculation (top half)`
- `Sprite Rendering: 8×16 pattern address calculation (bottom half)`
- `Sprite Rendering: 8×16 pattern table from tile bit 0`
- `Sprite Rendering: 8×16 vertical flip`

**Verification Points:**
- Tile bit 0 selects pattern table (NOT PPUCTRL)
- Top half (rows 0-7) uses tile & 0xFE
- Bottom half (rows 8-15) uses (tile & 0xFE) + 1
- Vertical flip (row = 15 - row)

**Expected Implementation:** `Logic.getSprite16PatternAddress()`

#### 3. Sprite Shift Registers - 2 tests
- `Sprite Rendering: Shift register pixel extraction`
- `Sprite Rendering: Horizontal flip`

**Verification Points:**
- 2-bit pattern extraction from shift registers
- Horizontal flip reverses pixel order (left-to-right vs right-to-left)
- X counter activation (sprite becomes active when X counter reaches 0)

**Expected Implementation:** `SpriteState` struct with shift registers

#### 4. Sprite Priority System - 5 tests
- `Sprite Rendering: Priority 0 (sprite in front)`
- `Sprite Rendering: Priority 1 (sprite behind background)`
- `Sprite Rendering: Sprite wins when background transparent`
- `Sprite Rendering: Background wins when sprite transparent`
- `Sprite Rendering: Sprite 0-7 priority order`

**Verification Points:**
- Priority 0: Sprite renders in front of background
- Priority 1: Sprite renders behind background (unless BG transparent)
- Transparency: Color 0 is always transparent
- Sprite index priority: Lower index = higher priority (0 > 1 > 2 > ... > 7)

**Expected Implementation:** `getSpritePixel()` with priority logic

#### 5. Palette Selection - 2 tests
- `Sprite Rendering: Sprite palette selection`
- `Sprite Rendering: Sprite palette 1-3`

**Verification Points:**
- Palette bits 6-7 select 1 of 4 sprite palettes
- Palette 0: $3F10-$3F13
- Palette 1: $3F14-$3F17
- Palette 2: $3F18-$3F1B
- Palette 3: $3F1C-$3F1F

**Expected Implementation:** Palette index calculation in sprite rendering

#### 6. Sprite Fetching Timing - 3 tests
- `Sprite Rendering: Sprite fetch occurs cycles 257-320`
- `Sprite Rendering: 8 sprites fetched per scanline`
- `Sprite Rendering: Sprite fetch with <8 sprites`

**Verification Points:**
- Fetch occurs cycles 257-320 (64 cycles total)
- 8 cycles per sprite (2× garbage NT, pattern low, pattern high)
- All 8 slots fetched even if <8 sprites in secondary OAM

**Expected Implementation:** Sprite fetch logic in `tick()` function

#### 7. Sprite Rendering Output - 4 tests
- `Sprite Rendering: Sprite renders at correct X position`
- `Sprite Rendering: Sprite renders at correct Y position`
- `Sprite Rendering: Sprite X counter behavior`
- `Sprite Rendering: Left column clipping`

**Verification Points:**
- Sprites render at exact X/Y coordinates from OAM
- X counter counts down, sprite activates at 0, renders 8 pixels
- Left column clipping (PPUMASK bit 2)

**Expected Implementation:** Sprite rendering in pixel output logic

---

## Implementation Roadmap

### Phase 7.2: Sprite Fetching (6-8 hours)

**Required Implementation (src/ppu/State.zig):**

```zig
pub const SpriteState = struct {
    pattern_low: u8 = 0,   // Bitplane 0
    pattern_high: u8 = 0,  // Bitplane 1
    attributes: u8 = 0,    // Palette, priority, flip bits
    x_counter: u8 = 0,     // Counts down from X position to 0
    active: bool = false,  // True when sprite is rendering (x_counter reached 0)
};

// Add to PpuState
sprite_state: [8]SpriteState = [_]SpriteState{.{}} ** 8,
```

**Required Implementation (src/ppu/Logic.zig):**

```zig
/// Get sprite pattern address (8×8 mode)
fn getSpritePatternAddress(
    tile_index: u8,
    row: u8,
    bitplane: u1,
    pattern_table: u1,
    vertical_flip: bool,
) u16 {
    var sprite_row = row;
    if (vertical_flip) {
        sprite_row = 7 - row;
    }

    const pattern_base: u16 = if (pattern_table == 1) 0x1000 else 0x0000;
    const tile_offset: u16 = @as(u16, tile_index) * 16;
    const bitplane_offset: u16 = if (bitplane == 1) 8 else 0;

    return pattern_base + tile_offset + sprite_row + bitplane_offset;
}

/// Get sprite pattern address (8×16 mode)
fn getSprite16PatternAddress(
    tile_index: u8,
    row: u8,
    bitplane: u1,
    vertical_flip: bool,
) u16 {
    var sprite_row = row;
    if (vertical_flip) {
        sprite_row = 15 - row;
    }

    const pattern_base: u16 = if ((tile_index & 1) == 1) 0x1000 else 0x0000;
    const tile = if (sprite_row < 8)
        (tile_index & 0xFE)
    else
        (tile_index & 0xFE) + 1;

    const tile_offset: u16 = @as(u16, tile) * 16;
    const row_offset: u16 = sprite_row & 7;
    const bitplane_offset: u16 = if (bitplane == 1) 8 else 0;

    return pattern_base + tile_offset + row_offset + bitplane_offset;
}

/// Fetch sprite pattern data (cycles 257-320)
fn fetchSprites(state: *PpuState) void {
    // Implement 8-cycle fetch pattern per sprite
    // Load pattern data into sprite_state shift registers
}
```

### Phase 7.3: Sprite Rendering (8-12 hours)

**Required Implementation:**

```zig
/// Get sprite pixel from shift registers
fn getSpritePixel(state: *PpuState, pixel_x: u8) ?SpritePixel {
    // Check each sprite in priority order (0 = highest priority)
    for (state.sprite_state, 0..) |*sprite, i| {
        // Handle X counter and activation
        // Extract pixel from shift registers
        // Apply horizontal flip
        // Return sprite pixel with palette and priority
    }
    return null; // No sprite pixel
}

/// Combine background and sprite pixels
fn getPixelColor(state: *PpuState, pixel_x: u8, pixel_y: u8) u32 {
    const bg_pixel = getBackgroundPixel(state);
    const sprite_pixel = getSpritePixel(state, pixel_x);

    // Priority rules:
    // 1. If no sprite pixel → use background
    // 2. If no background pixel (transparent) → use sprite
    // 3. If both present → check sprite priority bit
}
```

**Files to Modify:**
- `src/ppu/State.zig` - Add sprite state structures
- `src/ppu/Logic.zig` - Implement sprite fetching and rendering

**Expected Outcome:**
All 23 sprite rendering tests should pass after Phase 7.2-7.3 implementation.

---

## Build Commands

```bash
# Run all tests (includes sprite tests)
zig build test

# Run only integration tests
zig build test-integration

# Run sprite rendering tests directly (faster)
zig test tests/ppu/sprite_rendering_test.zig --dep RAMBO -Mroot=src/root.zig
```

---

## Test Coverage Analysis

**Coverage by Category:**

| Category | Tests | Passing (Compile) | Failing (Runtime) | Coverage |
|----------|-------|-------------------|-------------------|----------|
| Pattern Address (8×8) | 3 | 3 | 3 | 0% |
| Pattern Address (8×16) | 4 | 4 | 4 | 0% |
| Shift Registers | 2 | 2 | 2 | 0% |
| Priority System | 5 | 5 | 5 | 0% |
| Palette Selection | 2 | 2 | 2 | 0% |
| Fetching Timing | 3 | 3 | 3 | 0% |
| Rendering Output | 4 | 4 | 4 | 0% |

**Overall Test Coverage:** 0% (0/23 implemented)

**Combined Phase 4.1 + 4.2:**
- Total Tests: 38 (15 evaluation + 23 rendering)
- Tests Passing: 6/38 (16%)
- Tests Failing: 32/38 (84%) - **EXPECTED**

**Next Steps:**
1. Phase 4.3: State Snapshot/Debugger Implementation (26-33 hours) ⏳
2. Phase 7.2: Implement sprite fetching to pass tests ⏳
3. Phase 7.3: Implement sprite rendering to pass tests ⏳

---

## References

- **Specification:** `docs/SPRITE-RENDERING-SPECIFICATION.md`
- **nesdev.org:** https://www.nesdev.org/wiki/PPU_sprite_evaluation
- **nesdev.org:** https://www.nesdev.org/wiki/PPU_OAM
- **Test File:** `tests/ppu/sprite_rendering_test.zig`
- **PPU Logic:** `src/ppu/Logic.zig`
- **PPU State:** `src/ppu/State.zig`

---

**Status:** ✅ Phase 4.2 Test Creation COMPLETE
**Next:** Phase 4.3 - State Snapshot/Debugger Implementation
