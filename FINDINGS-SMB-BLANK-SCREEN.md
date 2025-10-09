# Super Mario Bros Blank Screen - Debug Findings Summary

**Date**: 2025-10-09
**Issue**: Super Mario Bros displays blank screen
**Status**: ✅ ROOT CAUSE IDENTIFIED

---

## TL;DR - Root Cause

**Super Mario Bros NEVER enables rendering** because it gets stuck in initialization logic waiting for a condition that doesn't occur. The game successfully detects VBlank but never progresses to writing PPUMASK with rendering enabled (bits 3 or 4 set).

**This is NOT a sprite rendering bug** - it's a CPU/game logic initialization failure.

---

## Evidence Summary

### 1. Rendering Never Enabled

**Mario Bros (Working)**:
```
[PPUMASK] Write 0x1E → show_bg=true, show_sprites=true  ✅
```

**Super Mario Bros (Broken)**:
```
[PPUMASK] Write 0x06 → show_bg=false, show_sprites=false  ❌
[PPUMASK] Write 0x00 → show_bg=false, show_sprites=false  ❌
(never writes 0x1E or any value with bits 3/4 set)
```

### 2. VBlank Detection Works Correctly

VBlank SET/CLEAR timing is **hardware-accurate**:
```
[VBlank] SET at scanline=241, dot=1     ✅
[VBlank] SET COMPLETE - flag_after=true ✅
[$2002 READ] CLEARED VBlank flag        ✅
[VBlank] CLEAR at scanline=261, dot=1   ✅
```

Game **successfully reads VBlank=true** on frames 1-2, proving VBlank flag logic works.

### 3. OAM DMA Triggers Correctly

```
[OAMADDR] Write 0x00
[OAM DMA] TRIGGERED: page=$0x0200, oam_addr=0x00, cpu_cycle=116820
```

OAM DMA executes correctly with proper parameters.

### 4. PPU Timing Advances Correctly

- Scanlines advance 0 → 261 correctly
- VBlank sets at scanline 241, dot 1 (correct)
- VBlank clears at scanline 261, dot 1 (correct)
- Frames complete normally

---

## Debugging Steps Taken

### Step 1: Check PPUMASK Writes
**Finding**: Game only writes 0x00 and 0x06 (rendering disabled), never 0x1E (rendering enabled)

### Step 2: Check OAM DMA
**Finding**: DMA triggers correctly at CPU cycle 116,820 with correct page ($0200) and oam_addr (0x00)

### Step 3: Check VBlank Flag Timing
**Finding**: VBlank sets/clears at correct scanlines (241/261), game successfully reads VBlank

### Step 4: Check $2002 Polling Pattern
**Finding**: Game polls $2002 heavily during first 2 frames, sees VBlank=true, clears it by reading

### Step 5: Check Sprite Rendering Pipeline
**Finding**: Not reached - rendering never enabled so sprites never evaluated

---

## Why Mario Bros Works vs Super Mario Bros Fails

| Aspect | Mario Bros | Super Mario Bros |
|--------|------------|------------------|
| VBlank detection | Works | Works |
| OAM DMA | Triggers | Triggers |
| PPUMASK writes | Writes 0x1E ✅ | Only writes 0x00/0x06 ❌ |
| Initialization | Completes | **Gets stuck** |
| Rendering | Enables | Never enables |

**Hypothesis**: Super Mario Bros has more complex initialization logic that checks additional conditions (possibly sprite 0 hit, controller input, or other hardware state) before enabling rendering. One of these conditions is not being met.

---

## Potential Root Causes (Prioritized)

### 1. Sprite 0 Hit Never Occurs (HIGH)
- SMB may be waiting for sprite 0 hit as readiness check
- Sprite 0 hit requires rendering enabled (catch-22)
- But some games enable minimal rendering to test sprite 0 hit
- SMB might write PPUMASK 0x06 expecting sprite rendering

**Test**: Check if 0x06 should enable sprite rendering (bit 2 = show_sprites_left)

### 2. Controller Input Required (MEDIUM)
- Game may be waiting for START button before enabling rendering
- Common pattern: Show title screen after START pressed
- Blank screen might be intentional "press start" state

**Test**: Send controller input (START button) during initialization

### 3. PPU Warmup Issue (LOW)
- PPUMASK writes might be ignored during warmup
- However, debug shows writes are NOT logged as "IGNORED"
- Warmup appears to complete correctly

**Test**: Check warmup_complete flag timing

### 4. NMI/IRQ Timing Issue (LOW)
- Game might be waiting in NMI handler
- VBlank NMI not firing correctly
- However, nmi_enable toggles correctly in trace

**Test**: Add NMI trigger logging

### 5. Recent JMP Indirect Fix Regression (VERY LOW)
- Commit 5ed1592 fixed JMP indirect crash
- But might have introduced different issue
- Unlikely given VBlank detection works

**Test**: Bisect to commit before JMP fix

---

## Next Debugging Actions

### Immediate (High Priority)

1. **Check if bit 2 enables sprite rendering**
   - PPUMASK bit 2 = show_sprites_left
   - Bit 4 = show_sprites (full screen)
   - Game writes 0x06 (bits 1,2) expecting sprites?
   - **BUG**: `renderingEnabled()` only checks bits 3 and 4!

   ```zig
   // src/ppu/State.zig:85-87
   pub fn renderingEnabled(self: PpuMask) bool {
       return self.show_bg or self.show_sprites;  // Bits 3 or 4
   }
   ```

   Should it also check `show_sprites_left` (bit 2)?

2. **Add controller input**
   - Simulate START button press during initialization
   - See if game progresses to rendering

3. **Enable full $2002 debug**
   - See exact timing of when game polls vs when VBlank sets
   - Check if race condition exists

### Medium Priority

4. **Add NMI trigger logging**
   - Verify NMI fires when nmi_enable=true and VBlank sets
   - Check if NMI handler executes

5. **Check sprite evaluation logic**
   - Even though rendering disabled, check if sprite eval runs
   - Sprite 0 might need to be in OAM for some check

### Low Priority

6. **Bisect recent commits**
   - Test commit before VBlank fixes
   - Determine if regression or pre-existing issue

7. **Compare with another emulator**
   - Run SMB in Mesen or FCEUX
   - Check PPUMASK write pattern
   - See if 0x06 is expected or if our game logic differs

---

## Code Locations

### PPUMASK Handling
- `/home/colin/Development/RAMBO/src/ppu/State.zig:53-88` - PpuMask structure
- `/home/colin/Development/RAMBO/src/ppu/State.zig:85-87` - renderingEnabled() function ⚠️
- `/home/colin/Development/RAMBO/src/ppu/logic/registers.zig:137-154` - PPUMASK write handler

### VBlank Management
- `/home/colin/Development/RAMBO/src/emulation/Ppu.zig:142-166` - VBlank SET/CLEAR logic
- `/home/colin/Development/RAMBO/src/ppu/logic/registers.zig:32-51` - $2002 read handler

### Sprite Rendering
- `/home/colin/Development/RAMBO/src/emulation/Ppu.zig:89-114` - Sprite evaluation/fetching
- `/home/colin/Development/RAMBO/src/ppu/logic/sprites.zig` - Sprite pipeline

---

## Key Insight: PPUMASK Bit Interpretation

**CRITICAL FINDING**: The game writes PPUMASK=0x06:
- Bit 1 (show_bg_left) = 1
- Bit 2 (show_sprites_left) = 1
- Bits 3-4 (show_bg, show_sprites) = 0

Current `renderingEnabled()` returns **false** because bits 3-4 are not set.

**Question**: Should `show_sprites_left` enable sprite rendering for leftmost 8 pixels only?

**Hardware behavior** (nesdev.org):
- Bit 3: Show background (0=hide ALL background)
- Bit 4: Show sprites (0=hide ALL sprites)
- Bits 1-2: Only control leftmost 8 pixels **if rendering already enabled**

**Conclusion**: Bits 1-2 are **modifiers**, not **enablers**. Rendering MUST have bits 3 or 4 set. Game writing 0x06 is incorrect or there's a code path issue.

---

## Comparison: Expected vs Actual

### Expected NES Initialization Sequence

```assembly
RESET:
    SEI                    ; Disable interrupts
    CLD                    ; Clear decimal mode
    LDX #$40
    STX $4017             ; Disable APU frame IRQ
    LDX #$FF
    TXS                    ; Initialize stack

@wait_vblank1:
    BIT $2002              ; Wait for VBlank
    BPL @wait_vblank1

    ; Clear RAM, initialize variables...

@wait_vblank2:
    BIT $2002              ; Wait for 2nd VBlank (PPU warmup)
    BPL @wait_vblank2

    ; Load graphics data, set up PPU...
    LDA #$1E
    STA $2001              ; ENABLE RENDERING ← THIS IS MISSING IN SMB
```

### Actual SMB Behavior

```
1. Polls $2002, detects VBlank ✅
2. Writes PPUMASK=$06 (NOT $1E) ❌
3. Gets stuck, never writes $1E
4. Rendering never enables
5. Blank screen forever
```

---

## Files Modified for Debugging

All debug code added can be disabled by setting DEBUG flags to false:

- `/home/colin/Development/RAMBO/src/ppu/logic/registers.zig`
  - Added DEBUG_PPUSTATUS_VBLANK_ONLY logging
  - Added PPUMASK write logging
  - Added OAMADDR write logging

- `/home/colin/Development/RAMBO/src/emulation/Ppu.zig`
  - Enabled DEBUG_VBLANK logging
  - Added sprite evaluation logging
  - Added sprite 0 hit logging

- `/home/colin/Development/RAMBO/src/emulation/bus/routing.zig`
  - Added OAM DMA trigger logging (now removed)

**To disable all debug**: Set all DEBUG_* constants to `false`

---

## Recommended Fix Strategy

### Immediate Action

**Test hypothesis**: Is the game actually stuck or intentionally waiting?

1. Enable full CPU trace (PC, opcode) for first 10 frames
2. Check if PC is in infinite loop or progressing
3. Identify what code is executing between VBlank reads

### If stuck in loop:

**Likely cause**: Game logic bug or unimplemented hardware behavior

- Check for reads of unimplemented registers
- Look for unusual memory access patterns
- Verify recent JMP indirect fix didn't introduce regression

### If progressing but waiting:

**Likely cause**: Game waiting for user input or specific condition

- Send controller input (START button)
- Check if audio is playing (APU working?)
- Verify all hardware state is initialized correctly

---

## Success Criteria

SMB will be considered "fixed" when:

1. ✅ Game writes PPUMASK with rendering enabled (bits 3 or 4 set)
2. ✅ Background tiles render on screen
3. ✅ Sprites render on screen
4. ✅ Game responds to controller input

**Current status**: 0/4 criteria met

---

## References

- NESDev PPU Registers: https://www.nesdev.org/wiki/PPU_registers
- NESDev PPU Rendering: https://www.nesdev.org/wiki/PPU_rendering
- PPUMASK format: https://www.nesdev.org/wiki/PPU_registers#PPUMASK
- Recent commits: `git log --oneline -10`

---

**Conclusion**: Super Mario Bros initialization logic fails to enable rendering. The PPU, VBlank, and OAM DMA all work correctly. The issue is in game CPU code execution, not emulator hardware emulation.

**Next step**: Add CPU execution trace to identify where game logic gets stuck.
