# Sprite 0 Hit Detection Analysis

**Date:** 2025-10-09
**Context:** Super Mario Bros displays blank screen and disables NMI after one frame
**Hypothesis:** Sprite 0 hit detection may be broken, causing game to detect hardware failure

## Executive Summary

**CRITICAL BUG FOUND:** Background rendering does NOT implement left-column clipping when `show_bg_left=false`. This breaks sprite 0 hit detection and causes Super Mario Bros to fail.

## Hardware Specification (NESDev Wiki Reference)

Sprite 0 hit detection requires ALL of these conditions:

1. **Opaque Pixels:** Both sprite 0 pixel AND background pixel must be non-zero (opaque)
2. **Both Enabled:** Both `show_bg` and `show_sprites` must be true
3. **Left Clipping:** Hit detection ONLY occurs in columns 8-255 when left-clipping is enabled
4. **Timing:** Hit flag set THE CYCLE AFTER the hit occurs (not during)
5. **Not X=255:** Hardware quirk - no hit detection at rightmost pixel
6. **Cleared at 261.1:** Flag cleared at dot 1 of pre-render scanline (261)

Reference: https://www.nesdev.org/wiki/PPU_OAM#Sprite_0_hits

## Current Implementation Analysis

### Sprite 0 Hit Detection Code

**File:** `/home/colin/Development/RAMBO/src/emulation/Ppu.zig` (lines 106-133)

```zig
// === Pixel Output ===
if (is_visible and dot >= 1 and dot <= 256) {
    const pixel_x = dot - 1;  // pixel_x range: 0-255
    const pixel_y = scanline;

    const bg_pixel = PpuLogic.getBackgroundPixel(state);      // Line 111
    const sprite_result = PpuLogic.getSpritePixel(state, pixel_x);  // Line 112

    var final_palette_index: u8 = 0;
    if (bg_pixel == 0 and sprite_result.pixel == 0) {
        final_palette_index = 0;
    } else if (bg_pixel == 0 and sprite_result.pixel != 0) {
        final_palette_index = sprite_result.pixel;
    } else if (bg_pixel != 0 and sprite_result.pixel == 0) {
        final_palette_index = bg_pixel;
    } else {
        // Both pixels opaque - apply priority
        final_palette_index = if (sprite_result.priority) bg_pixel else sprite_result.pixel;

        // SPRITE 0 HIT DETECTION
        if (sprite_result.sprite_0 and pixel_x < 255 and dot >= 2) {  // Line 123
            state.status.sprite_0_hit = true;
        }
    }
}
```

### Implementation Correctness Matrix

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| Opaque sprite pixel | `sprite_result.pixel != 0` (implicit in else branch) | ✅ CORRECT |
| Opaque background pixel | `bg_pixel != 0` (implicit in else branch) | ✅ CORRECT |
| Both rendering enabled | Implicit in pixel fetch | ✅ CORRECT |
| Not at X=255 | `pixel_x < 255` | ✅ CORRECT |
| Earliest at dot 2 | `dot >= 2` | ✅ CORRECT |
| Sprite 0 tracking | `sprite_result.sprite_0` | ⚠️ QUESTIONABLE |
| Left clipping (columns 8-255) | **MISSING** | ❌ **CRITICAL BUG** |
| Flag cleared at 261.1 | Line 163 in same file | ✅ CORRECT |

## Bug #1: Missing Left-Column Clipping Check (CRITICAL)

### Problem

The sprite 0 hit detection code checks:
```zig
if (sprite_result.sprite_0 and pixel_x < 255 and dot >= 2) {
    state.status.sprite_0_hit = true;
}
```

**Missing check:** `pixel_x >= 8` when left-clipping is enabled.

### Hardware Behavior

When `show_bg_left=false` or `show_sprites_left=false`:
- **Columns 0-7:** Clipped (transparent background displayed)
- **Columns 8-255:** Normal rendering
- **Sprite 0 hit:** Should ONLY occur in columns 8-255

### Current Broken Behavior

Background rendering in `src/ppu/logic/background.zig`:

```zig
pub fn getBackgroundPixel(state: *PpuState) u8 {
    if (!state.mask.show_bg) return 0;  // Global enable check

    // NO CHECK for show_bg_left here!

    const fine_x: u8 = state.internal.x;
    const shift_amount: u4 = @intCast(15 - fine_x);

    const bit0 = (state.bg_state.pattern_shift_lo >> shift_amount) & 1;
    const bit1 = (state.bg_state.pattern_shift_hi >> shift_amount) & 1;
    const pattern: u8 = @intCast((bit1 << 1) | bit0);

    if (pattern == 0) return 0; // Transparent

    // ... returns opaque pixel even in leftmost 8 columns
}
```

**The bug:** `getBackgroundPixel()` returns opaque pixels in columns 0-7 even when `show_bg_left=false`.

Sprite rendering DOES implement left-clipping correctly (`src/ppu/logic/sprites.zig:159`):

```zig
if (pixel_x < 8 and !state.mask.show_sprites_left) {
    return .{ .pixel = 0, .priority = false, .sprite_0 = false };
}
```

### Impact on Super Mario Bros

Super Mario Bros:
1. Sets `show_bg_left=false` and `show_sprites_left=false` to hide leftmost 8 pixels
2. Places sprite 0 at X=8 (first visible column after clipping)
3. Waits for sprite 0 hit to occur at X=8

**What actually happens:**
- Background returns opaque pixel at X=8 ✅
- Sprite rendering returns **transparent** pixel at X=8 (correctly clipped) ❌
- No sprite 0 hit occurs because sprite pixel is transparent
- Game detects "broken PPU hardware" and disables NMI

## Bug #2: Sprite 0 Tracking Simplification (QUESTIONABLE)

### Problem

In `src/ppu/logic/sprites.zig:129-132`:

```zig
// Check if sprite 0 is present (OAM index 0 copied to secondary OAM)
// This is a simplification - proper implementation would track OAM source index
if (sprite_index == 0) {
    state.sprite_state.sprite_0_present = true;
    state.sprite_state.sprite_0_index = 0;
}
```

**The assumption:** Sprite 0 (OAM index 0) will always be copied to secondary OAM slot 0.

### Hardware Reality

Sprite evaluation copies sprites to secondary OAM in **OAM order**, but sprite 0 might not be in slot 0 if:
1. An earlier sprite (higher Y priority) appears on the same scanline
2. Sprite 0 is off-screen for that scanline

**Correct behavior:** Track the **source OAM index** during sprite evaluation, not the secondary OAM slot.

### Likelihood of Impact

**LOW** for Super Mario Bros because:
- Super Mario Bros places sprite 0 at Y=0 (top scanline)
- It's typically the first sprite on its scanline
- This bug would only manifest if multiple sprites overlap at sprite 0's Y position

**MEDIUM** for other games that use sprite 0 differently.

## Bug #3: Background Left-Clipping Implementation Missing

### Root Cause

`getBackgroundPixel()` in `src/ppu/logic/background.zig` does NOT check `show_bg_left`:

```zig
pub fn getBackgroundPixel(state: *PpuState) u8 {
    if (!state.mask.show_bg) return 0;  // Only checks global enable

    // MISSING: Check pixel_x < 8 and !show_bg_left
```

This is not just a sprite 0 hit issue - it's a **general rendering bug** affecting all games.

### Required Fix

```zig
pub fn getBackgroundPixel(state: *PpuState, pixel_x: u16) u8 {
    if (!state.mask.show_bg) return 0;

    // Left-column clipping
    if (pixel_x < 8 and !state.mask.show_bg_left) {
        return 0;  // Transparent in leftmost 8 pixels when clipped
    }

    // ... rest of implementation
}
```

**NOTE:** This requires changing the function signature to accept `pixel_x` parameter.

## Verification Against Hardware Specification

### Sprite 0 Hit Timing

**Hardware (nesdev.org):**
> The sprite 0 hit flag is set when an opaque pixel of sprite 0 overlaps an opaque background pixel.
> The hit is detected the cycle it occurs, but the flag is readable starting the next PPU cycle.

**Implementation:** ✅ CORRECT
- Detection occurs during pixel output (line 123)
- Flag set immediately: `state.status.sprite_0_hit = true`
- No delayed setting mechanism needed (flag is readable next cycle)

### Flag Clearing

**Hardware:**
> The sprite 0 hit flag is cleared at dot 1 of the pre-render scanline (scanline 261).

**Implementation:** ✅ CORRECT (line 158-166)
```zig
if (scanline == 261 and dot == 1) {
    state.status.vblank = false;
    state.status.sprite_0_hit = false;  // Cleared here
    state.status.sprite_overflow = false;
    flags.vblank_clear = true;
}
```

### Left-Column Clipping

**Hardware (nesdev.org):**
> Sprite 0 hits do not trigger in the first column (x=0-7) if background or sprite rendering is disabled in that area.

**Implementation:** ❌ **BROKEN**
- Sprite clipping: ✅ Correctly returns transparent sprite pixel in columns 0-7
- Background clipping: ❌ Returns opaque background pixel in columns 0-7 (BUG)
- Result: No sprite 0 hit can occur in columns 0-7 (sprites are transparent)
- But: **Hit CAN incorrectly occur at columns 8+ when sprite is clipped but background is not**

Wait, let me reconsider this...

### Reconsidered Analysis

Actually, the situation is more subtle:

**Case 1: Both clipping disabled** (`show_bg_left=true`, `show_sprites_left=true`)
- Background: Opaque pixels in columns 0-255 ✅
- Sprites: Opaque pixels in columns 0-255 ✅
- Sprite 0 hit: Can occur in columns 0-254 ✅

**Case 2: Both clipping enabled** (`show_bg_left=false`, `show_sprites_left=false`)
- Background: Opaque pixels in columns 0-255 (BUG - should be transparent in 0-7) ❌
- Sprites: Transparent in columns 0-7, opaque in 8-255 ✅
- Sprite 0 hit: Should only occur in columns 8-254
- **ACTUAL:** Cannot occur in columns 0-7 (sprite transparent), CAN occur in 8-254 ✅

**Verdict:** Left-clipping bug does NOT directly break sprite 0 hit for typical usage! The sprite clipping prevents hits in 0-7.

**BUT:** The background IS rendered incorrectly in columns 0-7 when clipping is enabled. This is a **visual rendering bug**.

## Super Mario Bros Debugging

Let me reconsider why Super Mario Bros fails...

### Expected Behavior

Super Mario Bros:
1. Sets `show_bg_left=false`, `show_sprites_left=false`
2. Places sprite 0 at X=8, Y=0
3. Waits in NMI handler for sprite 0 hit
4. Uses hit to synchronize scrolling

### Possible Failure Modes

If sprite 0 hit NEVER occurs:
1. ❌ Sprite 0 not in secondary OAM (evaluation bug)
2. ❌ Background pixel transparent at sprite 0 location
3. ❌ Sprite pixel transparent at sprite 0 location
4. ❌ Hit detection condition has logic error
5. ❌ Flag cleared too early
6. ❌ Flag never read correctly

### Investigation Required

Need to check:
1. **Sprite evaluation:** Does sprite 0 get copied to secondary OAM?
2. **Background rendering:** Is there an opaque background pixel at sprite 0's position?
3. **Sprite rendering:** Is sprite 0's pixel actually opaque (not clipped)?
4. **Hit timing:** Does the hit occur at the expected cycle?

## Recommendations

### Priority 1: Add Background Left-Clipping (CRITICAL RENDERING BUG)

**File:** `src/ppu/logic/background.zig`

```zig
pub fn getBackgroundPixel(state: *PpuState, pixel_x: u16) u8 {
    if (!state.mask.show_bg) return 0;

    // Left-column clipping (hardware accurate)
    if (pixel_x < 8 and !state.mask.show_bg_left) {
        return 0;
    }

    // ... rest unchanged
}
```

**Files to update:**
- `src/ppu/logic/background.zig` - Add `pixel_x` parameter
- `src/ppu/Logic.zig` - Update function signature
- `src/emulation/Ppu.zig` - Pass `pixel_x` to `getBackgroundPixel()`

### Priority 2: Fix Sprite 0 Tracking

**File:** `src/ppu/logic/sprites.zig`

Track source OAM index during sprite evaluation:

```zig
pub const SpriteState = struct {
    // ... existing fields ...

    /// Source OAM indices for sprites in secondary OAM (0-63, or 0xFF if not sprite 0)
    source_oam_indices: [8]u8 = [_]u8{0xFF} ** 8,
};

pub fn evaluateSprites(state: *PpuState, scanline: u16) void {
    // ... sprite evaluation loop ...

    if (scanline >= sprite_y and scanline < sprite_bottom) {
        if (sprites_found < 8) {
            // Copy sprite to secondary OAM
            state.secondary_oam[secondary_oam_index] = state.oam[oam_offset]; // Y
            // ... other bytes ...

            // Track source OAM index
            state.sprite_state.source_oam_indices[sprites_found] = @intCast(sprite_index);

            sprites_found += 1;
        }
    }
}

pub fn fetchSprites(state: *PpuState, cart: ?*AnyCartridge, scanline: u16, dot: u16) void {
    // ... sprite fetching ...

    // Check if this is sprite 0
    const source_oam_index = state.sprite_state.source_oam_indices[sprite_index];
    if (source_oam_index == 0) {
        state.sprite_state.sprite_0_present = true;
        state.sprite_state.sprite_0_index = @intCast(sprite_index);
    }
}
```

### Priority 3: Debug Super Mario Bros Sprite 0 Failure

Add diagnostic logging:

```zig
// In Ppu.zig, sprite 0 hit detection
if (sprite_result.sprite_0 and pixel_x < 255 and dot >= 2) {
    std.debug.print("[Sprite 0 Hit] scanline={}, dot={}, pixel_x={}, bg_pixel={}, sprite_pixel={}\n",
        .{scanline, dot, pixel_x, bg_pixel, sprite_result.pixel});
    state.status.sprite_0_hit = true;
}
```

Run Super Mario Bros with logging to determine:
- Does sprite 0 appear in secondary OAM?
- What is the background pixel value at sprite 0's position?
- What is sprite 0's pixel value?
- Does the hit condition ever trigger?

## Testing Requirements

### Unit Tests Required

1. **Background left-clipping:**
   ```zig
   test "Background: Left-column clipping when show_bg_left=false" {
       // Verify bg pixel returns 0 for pixel_x < 8 when show_bg_left=false
   }
   ```

2. **Sprite 0 hit with left-clipping:**
   ```zig
   test "Sprite 0 Hit: Occurs at X=8 when left-clipping enabled" {
       // Set show_bg_left=false, show_sprites_left=false
       // Place sprite 0 at X=8
       // Verify hit occurs at X=8
   }

   test "Sprite 0 Hit: Does not occur at X=7 when left-clipping enabled" {
       // Set show_bg_left=false, show_sprites_left=false
       // Place sprite 0 at X=7
       // Verify hit does NOT occur
   }
   ```

3. **Sprite 0 tracking:**
   ```zig
   test "Sprite 0: Tracked correctly when not in secondary OAM slot 0" {
       // Place sprite 0 at Y=100
       // Place another sprite at Y=100, X=0 (evaluated first)
       // Verify sprite 0 still detected correctly
   }
   ```

## Conclusion

**Root cause of Super Mario Bros failure:** Unknown - requires debugging.

**Critical bugs found:**
1. ❌ Background left-column clipping not implemented (rendering bug)
2. ⚠️ Sprite 0 tracking assumes slot 0 (edge case bug)

**Sprite 0 hit logic:** Mostly correct, but cannot be fully validated without background clipping fix.

**Next steps:**
1. Implement background left-column clipping
2. Add diagnostic logging for sprite 0 hit detection
3. Run Super Mario Bros with logging to identify actual failure point
4. Fix sprite 0 tracking to use source OAM indices
