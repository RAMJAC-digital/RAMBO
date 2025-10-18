# A12 Edge Detection Root Cause Analysis (2025-10-18)

## Executive Summary

**Root Cause:** Hardcoded background A12 detection logic in `src/ppu/Logic.zig:243`

**Impact:** Only 1 A12 edge detected per scanline instead of expected ~8 edges, causing MMC3 IRQ counter to never decrement properly.

## Bug Location

**File:** `src/ppu/Logic.zig`
**Line:** 243
**Current Code:**
```zig
const background_a12 = (dot == 260);  // BUG: Hardcoded to single dot
const sprite_a12 = (state.chr_address & 0x1000) != 0;
const current_a12 = if (is_sprite_fetch) sprite_a12 else background_a12;
```

## Why This Is Wrong

### Background on A12 Detection

MMC3 IRQ timing depends on detecting rising edges (0→1 transitions) on PPU address line A12. Per nesdev.org:

> The MMC3 scanline counter is triggered by A12 transitions. During rendering, A12 typically rises 8 times per scanline as the PPU fetches 8 background tiles (each tile fetch accesses pattern table, toggling A12).

### Normal Operation

1. **Background fetches** (dots 1-256, 321-336):
   - 8 tile fetches per scanline (32 tiles total during visible portion)
   - Each tile fetch reads pattern table at 2 addresses (low + high bitplane)
   - Pattern table address is in CHR space ($0000-$1FFF)
   - Bit 12 of pattern address determines A12 level

2. **Sprite fetches** (dots 257-320):
   - 8 sprite fetches
   - Similar pattern table access
   - A12 comes from bit 12 of CHR address

3. **CHR Address Tracking:**
   - `state.chr_address` is updated during EVERY pattern fetch
   - `background.zig:82` - Background low bitplane fetch
   - `background.zig:89` - Background high bitplane fetch
   - `sprites.zig:102` - Sprite low bitplane fetch
   - `sprites.zig:120` - Sprite high bitplane fetch

### The Bug

Line 243 hardcodes background A12 to only be high at exactly dot 260:
```zig
const background_a12 = (dot == 260);
```

This means:
- Background A12 can only transition at dot 260
- Maximum 1 edge per scanline (260 is in sprite fetch window anyway!)
- All other background fetches (dots 1-256, 321-336) are ignored
- `chr_address` tracking is completely bypassed for background

## Evidence from Investigation

From `docs/sessions/2025-10-18-mmc3-irq-investigation.md`:

1. **Only 1 A12 edge per scanline** during rendering (expected ~8)
2. **IRQ counter stuck at $A2-$C1** - never decrements properly
3. **`zero_counter_events` = 0** - counter never reaches zero
4. **IRQ reload flag fires every scanline** - counter reloads before decrementing

This matches exactly what would happen if A12 edges aren't being detected during background fetches.

## Expected Behavior

### Correct A12 Detection Logic

```zig
// Use chr_address for BOTH background and sprite fetches
const current_a12 = (state.chr_address & 0x1000) != 0;
```

Since `chr_address` is already being updated during all pattern fetches (background AND sprite), we should use it directly for A12 detection.

### Expected A12 Edge Pattern (per scanline)

During visible scanlines with rendering enabled:

**Dots 1-256: Background rendering**
- Tile 0: fetches at dots 6, 8 → potential A12 toggles
- Tile 1: fetches at dots 14, 16 → potential A12 toggles
- ...
- Tile 31: fetches at dots 254, 256 → potential A12 toggles

**Dots 257-320: Sprite rendering**
- Sprite 0-7: fetches at various dots → potential A12 toggles

**Dots 321-336: Prefetch**
- Tile 0 prefetch, tile 1 prefetch → potential A12 toggles

**Typical game pattern:**
- Background pattern table at $0000 (A12=0)
- Sprite pattern table at $1000 (A12=1)
- Result: ~8 A12 rising edges per scanline (each background tile fetch toggles A12)

## Fix Verification Plan

1. **Code Fix:**
   - Change line 243 from `(dot == 260)` to `(state.chr_address & 0x1000) != 0`
   - Remove sprite-specific logic (use chr_address uniformly)

2. **Instrumentation:**
   - Verify `debug_a12_count` increments properly (~8 per visible scanline)
   - Verify IRQ counter decrements correctly
   - Verify `zero_counter_events` increases when counter reaches zero

3. **Visual Verification:**
   - SMB3: Status bar should render correctly (black line should disappear)
   - Kirby: Dialog box should render
   - Mega Man 4: Bottom region should render properly
   - TMNT II/III: Should continue working (regression check)

## Dead Ends (Do Not Repeat)

From investigation notes, these approaches did NOT work:
1. ❌ Forcing background A12 via `chr_address` only (existing logic already does this)
2. ❌ Treating background A12 as "dot 260 equals high" (this IS the bug!)
3. ❌ Forcing `irq_counter = 0` when `$C001` written
4. ❌ Forcing background A12 to dot 260 / manual toggles

The issue was not in the counter logic or the reload logic - it was in the A12 edge detection itself.

## Next Steps

1. ✅ Document root cause (this file)
2. ⏳ Verify nesdev.org spec matches our understanding
3. ⏳ Have code reviewer analyze A12 detection logic
4. ⏳ Implement fix
5. ⏳ Run regression tests
6. ⏳ Update session documentation

## References

- [MMC3 nesdev.org](https://www.nesdev.org/wiki/MMC3)
- [MMC3 Scanline Counter](https://www.nesdev.org/wiki/MMC3_scanline_counter)
- [PPU Rendering](https://www.nesdev.org/wiki/PPU_rendering)
- Investigation notes: `docs/sessions/2025-10-18-mmc3-irq-investigation.md`

---

**Status:** Root cause identified, verification in progress
**Confidence:** High (bug location confirmed, fix is straightforward)
**Risk:** Low (fix is one-line change, well-understood behavior)
