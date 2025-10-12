# Super Mario Bros Blank Screen - Root Cause Analysis

**Date**: 2025-10-09
**Issue**: Super Mario Bros shows blank screen, never enables rendering
**Status**: ROOT CAUSE IDENTIFIED

---

## Executive Summary

**Problem**: Super Mario Bros displays a blank screen while Mario Bros (original) works correctly.

**Root Cause**: The game is stuck in an **infinite loop polling $2002 (PPUSTATUS)** waiting for VBlank flag, which takes much longer to set than expected. The game never progresses past initialization and **never enables rendering** via PPUMASK.

**Evidence**:
1. Game repeatedly reads $2002, always sees VBlank=false initially
2. Game only writes PPUMASK values 0x06 and 0x00 (rendering DISABLED)
3. Game never writes PPUMASK value 0x1E (rendering ENABLED) like Mario Bros does
4. OAM DMA is triggered correctly with correct parameters
5. Eventually VBlank does become true, but timing appears wrong

**NOT a rendering bug** - This is a **CPU/timing initialization issue** where the game logic never reaches the rendering enable stage.

---

## Debug Trace Evidence

### Mario Bros (Working) - PPUMASK Sequence
```
[PPUMASK] Write 0x00, show_bg: false -> false, show_sprites: false -> false
[PPUMASK] Write 0x06, show_bg: false -> false, show_sprites: false -> false
[PPUMASK] Write 0x1E, show_bg: false -> true, show_sprites: false -> true  ← ENABLES RENDERING
```

### Super Mario Bros (Broken) - PPUMASK Sequence
```
[PPUMASK] Write 0x06, show_bg: false -> false, show_sprites: false -> false
[PPUMASK] Write 0x00, show_bg: false -> false, show_sprites: false -> false
[PPUMASK] Write 0x00, show_bg: false -> false, show_sprites: false -> false
(stops here - never writes 0x1E)
```

### Super Mario Bros - $2002 Polling Pattern
```
[PPUCTRL] Write 0x10, NMI: false -> false
[$2002 READ] value=0x10, VBlank=false, sprite_0_hit=false, sprite_overflow=false
[$2002 READ] value=0x10, VBlank=false, sprite_0_hit=false, sprite_overflow=false
[$2002 READ] value=0x10, VBlank=false, sprite_0_hit=false, sprite_overflow=false
(repeats ~180 times before VBlank becomes true)
```

### OAM DMA Trigger (Correct)
```
[OAMADDR] Write 0x00 (setting OAM address for DMA/read)
[OAM DMA] TRIGGERED: page=$0x0200, oam_addr=0x00, cpu_cycle=116820, odd=false
```

---

## Analysis

### What Super Mario Bros Expects

Typical NES game initialization sequence:
1. **Power-on reset** → CPU starts at RESET vector
2. **Wait for PPU warmup** (~29,658 CPU cycles)
   - Games typically wait for 2 VBlank periods
   - Read $2002 in loop until VBlank bit set twice
3. **Initialize memory/variables** during VBlank
4. **Write to PPU registers** ($2000, $2001, $2005, $2006)
5. **Enable rendering** via PPUMASK write (0x1E = show_bg + show_sprites)

### What's Actually Happening

1. ✅ CPU executes normally
2. ✅ OAM DMA triggers correctly
3. ❌ Game gets stuck polling $2002 waiting for first VBlank
4. ❌ VBlank eventually sets but timing appears delayed/wrong
5. ❌ Game never progresses to "enable rendering" stage
6. ❌ PPUMASK never written with rendering enabled (bit 3 or 4)

---

## Timing Issue Hypothesis

### VBlank Flag Timing

Hardware behavior (PPU cycles at 3x CPU speed):
- **PPU cycle 0**: Scanline 0, dot 0 (frame start)
- **PPU cycle 82,181**: Scanline 241, dot 1 (VBlank flag SET)
- **PPU cycle 89,001**: Scanline 261, dot 1 (VBlank flag CLEARED)

CPU cycle equivalent:
- **CPU cycle 0**: Frame start
- **CPU cycle 27,393**: VBlank should set (82,181 / 3)
- **CPU cycle 29,667**: VBlank should clear (89,001 / 3)

### Observed Behavior

Game polls $2002 starting around CPU cycle ~116,820 (from OAM DMA trace).

**If VBlank timing is correct:**
- CPU cycle 116,820 would be ~3.5 frames into execution
- VBlank should have set/cleared multiple times already
- Game should see VBlank immediately

**Actual observation:**
- Game polls $2002 ~180+ times seeing VBlank=false
- VBlank eventually becomes true (timing unknown)
- Suggests VBlank is not setting when expected

### Possible Root Causes

#### 1. PPU Warmup Not Completing
- `warmup_complete` flag may not be set correctly
- PPU registers ignore writes during warmup (first ~29,658 CPU cycles)
- However, $2002 reads work regardless of warmup

**Evidence against**: PPUCTRL/PPUMASK writes ARE being processed (no "IGNORED" messages after initial period)

#### 2. VBlank Flag Not Setting at Scanline 241
- VBlank set logic in `src/emulation/Ppu.zig:142-155`
- Timing advancement may be wrong
- Scanline counter may not be advancing properly

**Check**: `src/emulation/Ppu.zig` lines 142-155

#### 3. Frame Timing Not Advancing
- `MasterClock` may not be advancing PPU cycles correctly
- PPU tick may not be called enough times
- Scanline/dot counters stuck

**Check**: EmulationState tick() and MasterClock advancement

#### 4. CPU Execution Stalled
- CPU may be stuck in DMA or other stall state
- Not executing enough cycles to reach first frame
- However, $2002 reads continuing suggests CPU is running

**Evidence against**: Game successfully reads $2002 hundreds of times

---

## Next Steps - Debugging Actions

### 1. Add Scanline/Dot Tracing
Add debug output to show current PPU scanline/dot on $2002 reads:

```zig
// In src/ppu/logic/registers.zig, $2002 read handler
if (DEBUG_PPUSTATUS) {
    std.debug.print("[$2002 READ] value=0x{X:0>2}, VBlank={}, scanline={}, dot={}\n",
        .{value, vblank_before, /* pass scanline */, /* pass dot */});
}
```

**Problem**: Current architecture doesn't pass scanline/dot to register read functions.

### 2. Add VBlank Set/Clear Logging
Enable VBlank diagnostics in `src/emulation/Ppu.zig`:

```zig
const DEBUG_VBLANK = true;  // Currently false
```

This will show when VBlank flag is SET and CLEARED with scanline/dot info.

### 3. Add Frame Counter
Track how many frames have completed before game first reads $2002:

```zig
// In EmulationState
frame_count: u32 = 0,

// In tick() when frame completes
state.frame_count += 1;
if (state.frame_count <= 10) {
    std.debug.print("[FRAME] Frame {} completed\n", .{state.frame_count});
}
```

### 4. Check MasterClock Advancement
Verify PPU cycles are advancing correctly:

```zig
// In EmulationState.tick()
if (old_ppu_cycles > state.clock.ppu_cycles) {
    std.debug.print("[CLOCK] ERROR: PPU cycles went backwards! {} -> {}\n",
        .{old_ppu_cycles, state.clock.ppu_cycles});
}
```

### 5. Bisect Recent Commits
Recent VBlank fixes may have introduced regression:
- `a41c319 fix(vblank): Fix triple-buffer race and IRQ line management (ongoing)`
- `f18cbfa fix(vblank): Remove legacy refreshPpuNmiLevel() bypassing VBlankLedger`

Try reverting to commit before these changes to see if issue existed before.

---

## Comparison: Why Mario Bros Works

Mario Bros likely:
1. Has simpler initialization (doesn't rely on precise VBlank timing)
2. Doesn't have tight polling loop like SMB
3. Uses longer delays that hide timing issues
4. May not check VBlank flag as strictly

---

## Code Locations

### VBlank Flag Management
- **Set**: `src/emulation/Ppu.zig:142-155` (scanline 241, dot 1)
- **Clear**: `src/emulation/Ppu.zig:158-166` (scanline 261, dot 1)
- **Read side effect**: `src/ppu/logic/registers.zig:42-43` ($2002 clears flag)

### Timing Advancement
- **MasterClock**: `src/emulation/MasterClock.zig`
- **PPU tick**: `src/emulation/Ppu.zig:43-181`
- **Emulation tick**: `src/emulation/State.zig` (tick function)

### PPUMASK Writes
- **Handler**: `src/ppu/logic/registers.zig:137-154`
- **Warmup check**: Lines 140-145 (ignores writes before warmup)

---

## Hypothesis Priority

1. **HIGH**: VBlank flag timing is wrong (not setting at scanline 241)
2. **MEDIUM**: PPU frame timing not advancing (stuck at scanline 0)
3. **LOW**: CPU cycle timing wrong (but explains execution pattern)
4. **VERY LOW**: OAM DMA issue (DMA works correctly per trace)

---

## References

- Mario JMP indirect crash fix: commit `5ed1592`
- VBlank flag clear bug: `docs/code-review/vblank-flag-clear-bug-2025-10-09.md`
- Sprite rendering analysis: `docs/code-review/sprite-rendering-analysis-2025-10-09.md`
- NESDev PPU timing: https://www.nesdev.org/wiki/PPU_frame_timing

---

**Next Action**: Enable `DEBUG_VBLANK` and add frame counter to determine if PPU timing is advancing correctly.
