# AccuracyCoin Sprite/Animation Coverage Analysis
**Date:** 2025-10-14
**Purpose:** Identify hardware behaviors that AccuracyCoin tests vs. untested areas that could affect SMB animation
**Context:** SMB animation freeze despite AccuracyCoin passing - suggests untested edge case

---

## Executive Summary

**Key Finding:** AccuracyCoin has **excellent coverage** of sprite 0 hit and OAM corruption edge cases, but has **critical gaps** in testing **frame-to-frame sprite animation workflows** that commercial games like SMB rely on.

**Most Likely SMB Issue:** Animation logic not updating OAM between frames due to:
1. Missing frame counter increment in NMI handler
2. OAMDMA ($4014) not being called every frame
3. Timing issue with sprite evaluation across frames

**Recommendation:** Focus investigation on **frame persistence** behaviors, not sprite 0 hit (which is well-tested).

---

## Sprite-Related Tests in AccuracyCoin

### ✅ Well-Tested Behaviors

#### 1. Sprite 0 Hit Detection (Test "Sprite 0 Hit Behavior")
**15 comprehensive sub-tests covering:**
- ✅ Basic sprite 0 hit detection (test 1)
- ✅ Rendering enable requirements (tests 2-4)
  - Hit requires both background AND sprite rendering enabled
  - Hit requires sprite 0 to be non-transparent
- ✅ Position edge cases (tests 6-7, B-C)
  - X=254 CAN trigger hit (test 6)
  - X=255 CANNOT trigger hit (test 7) ⚠️ **SMB RELEVANT**
  - Y=238 CAN trigger hit (test B)
  - Y>=239 CANNOT trigger hit (test C)
- ✅ 8-pixel mask interaction (tests 8-9-A)
  - Sprite 0 at X=0 with mask enabled: no hit
  - Partial visibility (X=1-7): hit occurs on visible pixels
- ✅ Pixel-level collision (test D)
  - Verifies actual solid pixel overlap, not just bounding box
- ✅ Cycle-accurate timing (test E)
  - Hit flag sets on exact cycle sprite renders (2585 CPU cycles precision)
  - **This level of timing accuracy suggests emulator is cycle-perfect**

**Our Implementation Status:** ✅ PASSING (recently fixed - added rendering_enabled check)

---

#### 2. Arbitrary Sprite Zero (Test "Arbitrary Sprite Zero")
**3 tests covering:**
- ✅ Only sprite 0 (OAM slot 0) triggers hit
- ✅ First processed sprite on scanline treated as "sprite zero"
- ✅ Misaligned OAM can trigger sprite zero hit

**Implications:** SMB cannot rely on sprite zero hit for animation timing (rendering happens before animation updates).

---

#### 3. Sprite Overflow Behavior (Test "Sprite Overflow Behavior")
**3 tests covering:**
- ✅ 9+ sprites on scanline sets overflow flag
- ✅ Overflow flag distinct from CPU V flag
- ✅ 8 or fewer sprites: no overflow

**Our Status:** Not verified, but unlikely to affect animation (SMB title screen has <8 sprites).

---

#### 4. Misaligned OAM Behavior (Test "Misaligned OAM Behavior")
**7 tests covering:**
- ✅ Misaligned OAM sprite zero hit
- ✅ OAM address increment/wrap logic during sprite evaluation
- ✅ Secondary OAM full edge cases
- ✅ X/Y position out-of-range realignment

**Complexity:** Highly advanced PPU internal state machine testing
**SMB Relevance:** **LOW** - SMB uses standard OAMDMA, not manual OAM manipulation

---

#### 5. OAM Corruption (Test "OAM Corruption")
**4+ tests covering:**
- ✅ Disabling rendering mid-scanline corrupts OAM row
- ✅ Corruption timing (2-3 PPU cycle delay based on alignment)
- ✅ Secondary OAM address determines corruption seed
- ✅ Corruption occurs on next visible scanline after re-enabling

**SMB Relevance:** **LOW** - SMB doesn't disable rendering mid-frame

---

#### 6. $2004 (OAMDATA) Behavior (Test "Address $2004 Behavior")
**10 tests covering:**
- ✅ Write increments OAM address by 1
- ✅ Read doesn't increment OAM address
- ✅ Attribute byte reads missing bits 2-5
- ✅ Reads during cycles 1-64 return $FF (rendering enabled)
- ✅ Reads during cycles 65-256 return current OAM byte
- ✅ Reads during cycles 256-320 return $FF
- ✅ Writes during visible scanline increment by 4 and don't write

**Our Status:** Unknown, but unlikely issue (SMB uses OAMDMA, not $2004 writes)

---

#### 7. OAMDMA ($4014) Edge Cases
**Multiple tests covering:**
- ✅ DMC DMA + OAM DMA interaction ("DMC DMA + OAM DMA" test)
- ✅ INC $4014 edge case (double write within single DMA)
- ✅ DMA + open bus behavior
- ✅ DMA + $2007 read/write interaction

**Our Status:** Unknown, but DMA system likely works (other ROMs animate correctly).

---

### ❌ CRITICAL GAPS: Untested Behaviors

#### 1. ⚠️ **Frame-to-Frame OAM Persistence** (MOST LIKELY SMB ISSUE)
**What's NOT tested:**
- Verifying OAM contents persist across multiple frames
- Checking if OAMDMA transfers complete correctly every frame
- Testing animation workflows: NMI → update RAM → OAMDMA → render

**Why this matters for SMB:**
- SMB updates sprite positions in RAM during NMI
- Calls OAMDMA ($4014) to transfer to OAM
- If transfer incomplete or OAM clears between frames → frozen animation

**Test Gap:** AccuracyCoin does single-frame sprite tests, not multi-frame animation sequences.

**Recommendation:** Add test that:
```asm
; Pseudo-code test
Initialize sprite at (X=50, Y=50)
For frame 1-10:
    Update sprite X position += 5
    Call OAMDMA
    Wait for next frame
    Verify sprite rendered at new position
```

---

#### 2. ⚠️ **OAMADDR ($2003) Frame Boundary Behavior**
**What's NOT tested:**
- OAMADDR state during/after OAMDMA
- OAMADDR reset timing (when does it reset to 0?)
- OAMADDR interaction with rendering enable/disable across frames

**Why this matters for SMB:**
- If OAMADDR doesn't reset properly, OAMDMA might write to wrong offset
- SMB writes $00 to $2003 before OAMDMA - if this doesn't work, OAM misaligned

**NESDev Wiki:** "During rendering, OAMADDR should be set to 0 before sprite evaluation starts."

**Hypothesis:** OAMADDR not resetting at frame boundary → OAMDMA writing to wrong location

---

#### 3. ⚠️ **Sprite Evaluation Timing Across Frames**
**What's NOT tested:**
- Secondary OAM state at frame boundaries
- Sprite evaluation state machine reset between frames
- Pre-render scanline sprite evaluation behavior

**Why this matters:**
- If sprite evaluation state persists incorrectly between frames, sprites don't render
- Pre-render scanline (scanline 261) resets sprite evaluation - if broken, next frame fails

---

#### 4. ⚠️ **OAM Clear During VBlank**
**What's NOT tested:**
- Does OAM get cleared/corrupted during VBlank?
- Does Secondary OAM get cleared between frames?

**Hardware Behavior (from NESDev):**
- Primary OAM ($00-$FF) does NOT get cleared automatically
- Secondary OAM ($00-$1F internal) DOES get cleared during sprite evaluation

**Hypothesis:** If secondary OAM doesn't clear properly, sprites from previous frame might persist/corrupt next frame.

---

#### 5. ⚠️ **Rendering Enable Timing (Mid-Frame vs. VBlank)**
**What's tested:** Sprite 0 hit timing when rendering enabled
**What's NOT tested:** Sprite rendering behavior when PPUMASK changes during VBlank vs. mid-frame

**Why this matters for SMB:**
- SMB enables rendering during VBlank (frame 180)
- If there's a 1-frame delay before sprite evaluation starts, sprites won't appear until frame 181
- If sprites appear on frame 181 but don't UPDATE on frame 182+, animation frozen

---

#### 6. ⚠️ **Sprite X=255 Rendering** (Already Flagged)
**What's tested:** X=255 doesn't trigger sprite 0 hit
**What's NOT tested:** Does sprite at X=255 render at all?

**NESDev Wiki:** "Sprites at X=255 are not evaluated and don't render."

**SMB Relevance:** If SMB places sprites at X=255 expecting them to be hidden, but our emulator renders them, could affect state machine.

**More Likely:** If SMB uses X=255 as "disabled sprite" marker, and our OAM evaluation incorrectly processes it, sprite evaluation might stall.

---

#### 7. ⚠️ **Sprite Y-Coordinate Off-By-One** (Mentioned in Test D)
**AccuracyCoin Test D checks:** "Your sprites are being rendered one scanline higher than they should be"

**What this means:**
- Sprites render at Y+1 instead of Y
- If SMB expects sprite at Y=50 but emulator renders at Y=49, collision detection breaks

**Test Method:** Place sprite at Y=N with background tile at Y=N+1, verify sprite 0 hit DOESN'T occur.

**Our Status:** AccuracyCoin passing suggests this is correct, but worth double-checking in debugger.

---

### 🔍 Potential False Positives

#### 1. Sprite 0 Hit Timing Test (Test E) - **VERY SUSPICIOUS**
**What it tests:** Hit flag sets on exact cycle (2585 CPU cycles after VBlank)

**Potential False Positive:**
- Test uses `Clockslide_2032` to delay exactly 2032 CPU cycles
- If our cycle counting is off by ±1, test might still pass due to:
  - NOP padding (test uses 2 NOPs before reading $2002)
  - CPU/PPU alignment tolerance

**Risk:** We might be passing test while being off by 3-6 CPU cycles (1-2 PPU dots).

**Impact on SMB:** If sprite 0 hit timing is slightly wrong, SMB's scanline sync code might wait wrong number of frames.

**Verification:** Check our PPU cycle count against known-good emulator at sprite 0 hit moment.

---

#### 2. OAM Corruption Calibration Test (Test 2)
**What it does:** Detects CPU/PPU alignment by checking which OAM row gets corrupted

**Potential False Positive:**
- Test expects corruption at row 3, 4, or 5 depending on alignment
- If we're corrupting row 4 for wrong reasons, test still passes

**Our Status:** Unknown - OAM corruption not implemented? (Test 2 passing suggests it is)

---

#### 3. Misaligned OAM Tests - **VERY COMPLEX**
**What they test:** OAM address increment logic during sprite evaluation

**Potential False Positive:**
- Tests rely on exact PPU internal state machine behavior
- If our sprite evaluation is "close enough", tests might pass without being cycle-accurate

**Impact on SMB:** If misaligned OAM handling is wrong, and SMB inadvertently creates misaligned OAM (via $2003 writes?), sprite evaluation breaks.

---

## SMB Animation Freeze - Behavioral Hypotheses

### Hypothesis 1: OAMDMA Not Executing Every Frame (70% confidence)
**Theory:** SMB calls `STA $4014` every frame in NMI handler, but our DMA doesn't complete or writes to wrong page.

**Evidence For:**
- AccuracyCoin tests single OAMDMA operations, not repeated frame-by-frame DMA
- Other ROMs (Circus Charlie) might not rely on per-frame OAMDMA if sprites don't move

**Test Method:**
```zig
// In busWrite() for $4014
std.debug.print("OAMDMA: page=${X:02} frame={}\n", .{value, self.clock.frame()});
```
Expected: Print every frame after rendering enables
Actual: If prints stop after frame 180, OAMDMA not being called

**Fix:** Check DMC DMA interaction - if DMC DMA blocks OAMDMA, sprites freeze.

---

### Hypothesis 2: OAMADDR Not Resetting Between Frames (60% confidence)
**Theory:** $2003 (OAMADDR) doesn't reset to 0 during sprite evaluation, causing OAMDMA to write to wrong offset.

**Hardware Behavior (NESDev):**
> "OAMADDR is set to 0 during each of ticks 257-320 (the sprite tile loading interval) of the pre-render and visible scanlines."

**Our Implementation:** Check `PpuState.oam_addr` - does it reset during sprite evaluation?

**Test Method:**
```zig
// In PPU tick() around cycle 257-320
if (scanline < 240 or scanline == 261) {
    if (cycle >= 257 and cycle <= 320) {
        if (self.oam_addr != 0) {
            std.debug.print("BUG: OAMADDR not reset: {} at scanline {} cycle {}\n",
                .{self.oam_addr, scanline, cycle});
        }
    }
}
```

**Fix:** Add OAMADDR reset during sprite tile fetch phase.

---

### Hypothesis 3: Secondary OAM Not Clearing Between Frames (50% confidence)
**Theory:** Secondary OAM ($00-$1F internal buffer) retains stale data from previous frame, causing sprite evaluation to fail.

**Hardware Behavior:**
- Cycles 1-64 of visible scanline: Clear secondary OAM (write $FF to all 32 bytes)
- If this doesn't happen, sprite evaluation uses garbage data

**Our Implementation:** Check `PpuState.secondary_oam` - is it cleared during cycles 1-64?

**Test Method:** Log secondary OAM contents at start of scanline 0:
```zig
if (scanline == 0 and cycle == 1) {
    std.debug.print("Secondary OAM: {any}\n", .{self.secondary_oam});
}
```
Expected: All $FF
Actual: If contains sprite data from previous frame → BUG

---

### Hypothesis 4: Sprite Evaluation State Machine Stuck (40% confidence)
**Theory:** Sprite evaluation state machine doesn't reset properly between frames, causing no sprites to evaluate on subsequent frames.

**NESDev Wiki:** Sprite evaluation has 4 phases:
1. Cycles 1-64: Clear secondary OAM
2. Cycles 65-256: Evaluate sprites from primary OAM
3. Cycles 257-320: Fetch sprite tiles for next scanline
4. Cycles 321-340: Garbage nametable fetches

**Bug Scenario:** If state machine gets stuck in phase 3-4 and doesn't reset for next scanline, sprites never evaluate.

**Test Method:** Log sprite evaluation phase at cycle 1 of each scanline:
```zig
if (cycle == 1) {
    std.debug.print("Scanline {} sprite eval phase: {}\n", .{scanline, self.sprite_eval_phase});
}
```
Expected: Phase 0 (clear) at start of each visible scanline
Actual: If stuck in phase 2-3 → BUG

---

### Hypothesis 5: NMI Handler Frame Counter Not Incrementing (30% confidence)
**Theory:** SMB uses internal frame counter to pace animations (e.g., coin bounces every 8 frames). If counter doesn't increment, animations freeze.

**Not an Emulator Bug:** This would be SMB game logic issue, not hardware emulation.

**Test Method:** Use debugger to examine SMB zero-page RAM ($00-$FF) during NMI:
```bash
./zig-out/bin/RAMBO "tests/data/Mario/Super Mario Bros. (World).nes" --inspect --break-at 0x2001
```
Look for bytes that increment every frame - those are likely frame counters.

**Expected:** Some byte increments every NMI
**Actual:** If no bytes change → SMB's NMI handler not running, or stuck in infinite loop

---

## Recommended Testing Strategy

### Phase 1: Verify OAMDMA Execution (15 minutes)
```zig
// In src/emulation/State.zig busWrite() for $4014
std.debug.print("OAMDMA: page=${X:02} frame={} cycle={}\n",
    .{value, self.clock.frame(), self.clock.cpuCycles()});
```

**Expected:** Logs appear every frame starting at frame ~180
**If fails:** SMB not calling OAMDMA → game logic bug, not emulator bug

---

### Phase 2: Check OAMADDR Reset (15 minutes)
```zig
// In src/ppu/Logic.zig around sprite evaluation phase
if ((scanline < 240 or scanline == 261) and cycle == 257) {
    if (ppu.oam_addr != 0) {
        std.debug.print("ERROR: OAMADDR=${X:02} at scanline {} (should be 0)\n",
            .{ppu.oam_addr, scanline});
    }
    ppu.oam_addr = 0; // Force reset for testing
}
```

**Expected:** No errors, or errors but animation works after adding reset
**If fixes:** OAMADDR reset missing → add permanent fix

---

### Phase 3: Verify Secondary OAM Clearing (15 minutes)
```zig
// In src/ppu/Logic.zig during cycles 1-64
if (cycle >= 1 and cycle <= 64 and cycle % 2 == 1) {
    const oam_clear_index = (cycle - 1) / 2;
    ppu.secondary_oam[oam_clear_index] = 0xFF;
}

// At start of frame, verify all $FF
if (scanline == 0 and cycle == 0) {
    for (ppu.secondary_oam) |byte, i| {
        if (byte != 0xFF) {
            std.debug.print("ERROR: secondary_oam[{}]=${X:02} (expected $FF)\n", .{i, byte});
        }
    }
}
```

**Expected:** All $FF at frame start
**If fails:** Secondary OAM not clearing → implement clear logic

---

### Phase 4: Frame-to-Frame Comparison (30 minutes)
```zig
// Capture OAM contents at end of VBlank for 10 consecutive frames
var oam_snapshots: [10][256]u8 = undefined;

if (self.clock.frame() >= 180 and self.clock.frame() < 190) {
    const frame_index = self.clock.frame() - 180;
    if (scanline == 240 and cycle == 0) {
        @memcpy(&oam_snapshots[frame_index], &ppu.oam);
    }
}

if (self.clock.frame() == 190) {
    // Compare frames
    for (oam_snapshots[1..]) |frame_oam, i| {
        const prev_frame = oam_snapshots[i];
        var changed = false;
        for (frame_oam, 0..) |byte, j| {
            if (byte != prev_frame[j]) {
                changed = true;
                std.debug.print("OAM[{}] changed: ${X:02} -> ${X:02} (frame {}->{})\n",
                    .{j, prev_frame[j], byte, i+180, i+181});
            }
        }
        if (!changed) {
            std.debug.print("WARNING: OAM identical between frame {} and {}\n", .{i+180, i+181});
        }
    }
}
```

**Expected:** OAM changes every frame (sprite positions update)
**If fails:** OAM frozen → OAMDMA not working or game logic stuck

---

### Phase 5: Write Minimal Animation Test
```zig
// New test: tests/integration/sprite_animation_test.zig
test "Sprite position updates across multiple frames" {
    var emu = try setupEmulation();

    // Frame 1: Place sprite at (X=50, Y=50)
    emu.ppu.oam[0] = 50; // Y
    emu.ppu.oam[3] = 50; // X

    try emu.runFrame();
    const frame1_x = emu.ppu.oam[3];

    // Frame 2: Update sprite position in RAM, trigger OAMDMA
    emu.cpu.ram[0x203] = 60; // New X position
    emu.busWrite(0x4014, 0x02); // OAMDMA page 2

    try emu.runFrame();
    const frame2_x = emu.ppu.oam[3];

    try testing.expectEqual(@as(u8, 60), frame2_x); // Verify position updated
}
```

---

## Comparison: Working ROMs vs. SMB

### Circus Charlie (WORKS ✅)
**Observations from previous investigation:**
- Single $2002 read per frame
- PPUMASK=$1E at frame 4
- Animations work correctly

**Key Difference from SMB:**
- Simpler sprite management?
- Fewer sprites on screen?
- Different OAM update strategy?

**Action:** Compare Circus Charlie's OAMDMA frequency vs. SMB:
```bash
# Run both ROMs with OAMDMA logging
./zig-out/bin/RAMBO "tests/data/Circus Charlie.nes" 2>&1 | grep OAMDMA > circus_dma.log
./zig-out/bin/RAMBO "tests/data/Mario/Super Mario Bros. (World).nes" 2>&1 | grep OAMDMA > smb_dma.log
diff circus_dma.log smb_dma.log
```

---

## Conclusion

### AccuracyCoin Coverage Assessment
**Strengths:**
- ✅ Excellent sprite 0 hit edge case coverage (15 tests)
- ✅ Comprehensive OAM corruption testing (4+ tests)
- ✅ Thorough $2004 behavior validation (10 tests)
- ✅ Advanced misaligned OAM state machine tests (7 tests)

**Weaknesses:**
- ❌ No multi-frame sprite animation testing
- ❌ No OAMADDR frame boundary behavior tests
- ❌ No secondary OAM persistence tests
- ❌ No rendering enable/disable workflow tests

### SMB Investigation Priority
**High Priority (Test First):**
1. Verify OAMDMA called every frame (15 min)
2. Check OAMADDR reset at cycle 257 (15 min)
3. Verify secondary OAM clears cycles 1-64 (15 min)

**Medium Priority (If Above Pass):**
4. Frame-to-frame OAM comparison (30 min)
5. Sprite evaluation state machine logging (30 min)

**Low Priority (Unlikely):**
6. Sprite X=255 rendering behavior
7. Sprite Y off-by-one verification

### Expected Outcome
**Most Likely Fix:** OAMADDR not resetting, causing OAMDMA to write to wrong offset every frame.

**Fallback:** Secondary OAM not clearing, causing sprite evaluation to fail on frame 181+.

**Worst Case:** SMB game logic bug waiting for hardware condition we don't emulate (requires debugger deep-dive).

---

## Files to Investigate

**Emulator Files:**
1. `src/ppu/State.zig` - OAMADDR reset logic (lines around sprite evaluation)
2. `src/ppu/Logic.zig` - Secondary OAM clear (cycles 1-64 of visible scanlines)
3. `src/emulation/State.zig` - OAMDMA implementation (busWrite $4014 handler)
4. `src/ppu/Logic.zig` - Sprite evaluation state machine (cycles 65-256)

**Test Files:**
1. `tests/integration/commercial_rom_test.zig` - SMB tests
2. New: `tests/integration/sprite_animation_test.zig` (to be created)

**Reference:**
- NESDev Wiki: [PPU Sprite Evaluation](https://www.nesdev.org/wiki/PPU_sprite_evaluation)
- NESDev Wiki: [PPU Registers](https://www.nesdev.org/wiki/PPU_registers#OAMADDR)

---

**Report Author:** Zig Expert Agent
**Date:** 2025-10-14
**Status:** Ready for Phase 4 debugging session
