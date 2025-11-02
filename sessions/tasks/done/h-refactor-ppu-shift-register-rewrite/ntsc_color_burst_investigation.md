# NTSC Color Burst Behavior Investigation

**Date:** 2025-11-02
**Status:** Investigation complete - NTSC emulation not needed for accuracy

## Hardware Behavior

Based on https://www.nesdev.org/wiki/NTSC_video:

### Color Burst Signal
- Operates at ~3.58 MHz as phase reference for color demodulation
- NTSC colorburst is phase 8 in NES's 12-phase color system
- Color generator clocks at ~42.95 MHz effective rate (rising/falling edges of 21.48 MHz clock)

### NTSC Timing
- NES generates **227⅓ color cycles per scanline** (not standard 227½)
- Non-standard timing causes TV to draw fields on top of each other
- Results in "progressive" or "double struck" video mode (low-definition)

### Color Phase Alignment
- Color phase shifts by 4 clock cycles per scanline
- Pattern repeats every 3 scanlines
- Creates rainbow artifact pattern on vertical lines (characteristic NES rainbow effect)

### Frame Timing
- Odd frames: 59560⅔ color cycles
- Even frames: 59561⅓ color cycles
- Difference due to odd frame dot skip (scanline 261, dot 339→0)

## Current RAMBO Implementation

**File:** `src/ppu/palette.zig`

We use a **static RGB lookup table** (64 colors):
```zig
pub const NES_PALETTE_RGB = [64]u32{
    // Pre-computed RGB values for all 64 NES colors
    0x545454, 0x001E74, 0x081090, ...
};
```

**We do NOT emulate:**
- ❌ Color burst signal generation
- ❌ NTSC color phase timing
- ❌ Color phase shifts per scanline
- ❌ Rainbow artifacts on vertical lines
- ❌ Emphasis bit color distortion
- ❌ Progressive vs interlaced field handling

## Impact Assessment

### Gameplay/Logic Accuracy
✅ **ZERO IMPACT** - Color generation is purely cosmetic
✅ **Game logic unaffected** - ROM code doesn't depend on NTSC signal timing
✅ **PPU timing correct** - We emulate cycle-accurate PPU behavior (scanlines, dots)
✅ **Register behavior correct** - PPUCTRL/PPUMASK/PPUSTATUS work properly

### Visual Accuracy
⚠️ **Minor cosmetic differences:**
- No rainbow artifacts on vertical lines (games don't rely on this)
- Emphasis bits might not match exact hardware color shift
- No scanline-to-scanline phase variation (not visible in most content)

### Commercial ROM Compatibility
✅ **NO ISSUES EXPECTED** - All tested ROMs work with static palette:
- Super Mario Bros 1, 3
- Castlevania
- Mega Man
- Kid Icarus
- Battletoads
- Kirby's Adventure

## Conclusion

**NTSC color burst emulation is NOT NEEDED for:**
- ✅ Cycle-accurate emulation
- ✅ Commercial ROM compatibility
- ✅ Game logic correctness
- ✅ PPU timing accuracy

**NTSC emulation WOULD BE NEEDED for:**
- ❌ Pixel-perfect visual reproduction (rainbow artifacts)
- ❌ CRT filter effects
- ❌ Hardware clone reproduction
- ❌ Composite video signal generation

## Recommendation

**Do NOT implement NTSC color burst emulation** unless:
1. User specifically requests CRT filter effects
2. We're building a hardware clone
3. We need composite video output

The static RGB palette is **sufficient and correct** for cycle-accurate emulation.

## References

- https://www.nesdev.org/wiki/NTSC_video (NTSC timing and color generation)
- https://www.nesdev.org/wiki/PPU_palettes (NES color encoding)
- https://www.nesdev.org/wiki/PPU_rendering (PPU timing - separate from NTSC signal)
