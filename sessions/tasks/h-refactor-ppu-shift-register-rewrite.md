---
name: h-refactor-ppu-shift-register-rewrite
branch: feature/h-refactor-ppu-shift-register-rewrite
status: pending
created: 2025-11-02
parent-task: h-fix-vblank-subcycle-timing
---

# PPU Shift Register Cycle-Accurate Rewrite

## Problem/Goal

The current PPU implementation doesn't properly model the hardware's cycle-by-cycle shift register behavior. The PPU uses shift registers to progressively fetch and render tile data over multiple PPU cycles, but our implementation treats many operations as instantaneous. This causes several critical bugs:

1. **Scanline 0 sprite crash** - AccuracyCoin test crashes on scanline 0
2. **Mid-frame register updates broken** - SMB3 checkered floor disappears, Kirby dialog doesn't render
3. **Progressive tile fetching not modeled** - Hardware takes 2 PPU cycles per fetch (4 fetches per tile), we fetch instantly
4. **Shift register timing incorrect** - Hardware shifts data cycle-by-cycle, we don't model this

The goal is to rewrite the PPU to accurately model the hardware's shift register behavior, making it cycle-accurate rather than event-based.

## Success Criteria

**Test-Driven Development:**
- [ ] Audit all existing PPU tests for assumptions incompatible with shift register model
- [ ] Update existing tests to match hardware shift register behavior (document each change)
- [ ] Create new unit tests for shift register state transitions (background tile fetches)
- [ ] Create new unit tests for shift register state transitions (sprite fetches)
- [ ] Create new tests for progressive tile fetching timing (2 cycles per fetch, 4 fetches per tile)
- [ ] Create new tests for mid-frame register update propagation (PPUCTRL, PPUMASK)
- [ ] Create new tests for shift register advance timing (every rendering cycle)

**Core Shift Register Modeling:**
- [ ] PPU models background tile shift registers (2x 16-bit shift registers for pattern data)
- [ ] PPU models attribute shift registers (2x 8-bit shift registers for palette data)
- [ ] Progressive tile fetching implemented (2 PPU cycles per fetch, 4 fetches per 8-pixel tile)
- [ ] Shift registers advance every PPU cycle during rendering

**Bug Fixes (Validated by Tests):**
- [ ] Scanline 0 sprite crash in AccuracyCoin fixed
- [ ] SMB3 checkered floor renders correctly throughout entire game
- [ ] Kirby's Adventure dialog box renders correctly
- [ ] Mid-frame PPUCTRL register changes propagate correctly
- [ ] Mid-frame PPUMASK register changes propagate with 3-4 dot delay (per hardware spec)

**Regression Testing:**
- [ ] All existing PPU tests continue to pass (or updated with documented rationale)
- [ ] AccuracyCoin VBLANK BEGINNING test shows improvement or maintains current state
- [ ] Visual regression tests pass for commercial ROMs (SMB1, Castlevania, Mega Man, etc.)
- [ ] Document any test expectation changes in work log with hardware spec references

**Code Quality:**
- [ ] Mesen2 shift register implementation used as reference and documented
- [ ] Shift register state clearly separated in PpuState
- [ ] Cycle-by-cycle fetch logic documented with hardware timing references
- [ ] All test changes tracked in dedicated test audit document (similar to tests_updated.md)

## Context Manifest
<!-- Added by context-gathering agent -->

### Executive Summary: Why This Refactor Is Critical

The current PPU implementation treats tile fetching and rendering as **instantaneous operations** that complete within a single dot. Real NES hardware uses **progressive shift registers** that take **8 PPU dots per tile** (2 dots per fetch × 4 fetches). This architectural mismatch causes several critical bugs:

1. **Scanline 0 sprite crash** - AccuracyCoin crashes on first scanline
2. **Mid-frame register changes broken** - SMB3 checkered floor disappears, Kirby dialog missing
3. **No progressive tile fetching model** - We fetch instantly, hardware takes 2 cycles per fetch
4. **Shift register timing incorrect** - Hardware shifts every cycle, we don't model this properly

**The fix:** Rewrite PPU to model shift registers cycle-by-cycle, matching hardware behavior exactly.

---

## Hardware Specification: NES PPU Shift Register Architecture

### Primary References (MANDATORY READING)

**NESdev Wiki - PPU Rendering:**
- https://www.nesdev.org/wiki/PPU_rendering
- Complete frame timing (262 scanlines × 341 dots)
- Background tile fetch pipeline (8 dots per tile)
- Shift register behavior during rendering

**NESdev Wiki - PPU Scrolling:**
- https://www.nesdev.org/wiki/PPU_scrolling
- Internal register manipulation (v, t, x, w)
- Coarse X/Y increment timing

**NESdev Wiki - PPU Sprite Evaluation:**
- https://www.nesdev.org/wiki/PPU_sprite_evaluation
- Progressive sprite evaluation (dots 65-256)
- Sprite fetch cycles (dots 257-320)

**Mesen2 Reference Implementation:**
- Path: `/home/colin/Development/Mesen2/Core/NES/NesPpu.cpp`
- See `ShiftTileRegisters()` (line 811)
- See `LoadTileInfo()` (line 667)
- Key fields: `_lowBitShift`, `_highBitShift` (BaseNesPpu.h lines 26-27)

---

### Background Tile Shift Registers

**Hardware Structure (per nesdev.org):**

The PPU contains **two 16-bit shift registers** for background pattern data:
- `pattern_shift_lo`: Low bitplane (16 bits)
- `pattern_shift_hi`: High bitplane (16 bits)

**Hardware Structure - Attribute Shift Registers:**

The PPU contains **two 8-bit shift registers** with **attribute latch feeding**:
- `attribute_shift_lo`: Palette bit 0 (functionally 16-bit via latch feed)
- `attribute_shift_hi`: Palette bit 1 (functionally 16-bit via latch feed)

**Per NESDev:** "The palette attribute for the next tile is decoded during fetch and placed in a latch. This latch feeds the shift register during shifting, functionally acting like 16-bit registers where the low 8 bits are filled with the attribute bits."

**Current RAMBO Implementation (CORRECT):**
```zig
// src/ppu/State.zig:271-311
pub const BackgroundState = struct {
    pattern_shift_lo: u16 = 0,
    pattern_shift_hi: u16 = 0,
    attribute_shift_lo: u16 = 0,  // 16-bit for functional equivalence
    attribute_shift_hi: u16 = 0,
    // ... latches ...
};
```

**Shift Operation (every rendering cycle):**
```zig
// src/ppu/State.zig:307-312
pub fn shift(self: *BackgroundState) void {
    self.pattern_shift_lo <<= 1;
    self.pattern_shift_hi <<= 1;
    self.attribute_shift_lo <<= 1;
    self.attribute_shift_hi <<= 1;
}
```

**Mesen2 Implementation (for reference):**
```cpp
// /home/colin/Development/Mesen2/Core/NES/NesPpu.cpp:811-814
void NesPpu::ShiftTileRegisters() {
    _lowBitShift <<= 1;   // Pattern bitplane 0
    _highBitShift <<= 1;  // Pattern bitplane 1
}
```

---

### Progressive Tile Fetching (8-Dot Pipeline)

**Hardware Timing (per nesdev.org):**

Each background tile requires **8 PPU dots** to fetch:
- **Dots 1-2:** Nametable byte fetch (tile index)
- **Dots 3-4:** Attribute table byte fetch (palette select)
- **Dots 5-6:** Pattern table low bitplane fetch
- **Dots 7-8:** Pattern table high bitplane fetch

**Fetch completes at EVEN dots** (2, 4, 6, 8), data available on ODD dots (1, 3, 5, 7).

**Current RAMBO Implementation:**
```zig
// src/ppu/logic/background.zig:45-110
pub fn fetchBackgroundTile(state: *PpuState, cart: ?*AnyCartridge, dot: u16) void {
    const cycle_in_tile = (dot - 1) % 8;
    switch (cycle_in_tile) {
        1 => { /* Nametable fetch at dots 2, 10, 18, 26... */ },
        3 => { /* Attribute fetch at dots 4, 12, 20, 28... */ },
        5 => { /* Pattern low fetch at dots 6, 14, 22, 30... */ },
        7 => { /* Pattern high fetch at dots 8, 16, 24, 32... */ },
        0 => { /* Shift register reload at dots 9, 17, 25, 33... */ },
        else => { /* Idle cycles */ },
    }
}
```

**Mesen2 Implementation (for reference):**
```cpp
// /home/colin/Development/Mesen2/Core/NES/NesPpu.cpp:667-700
void NesPpu::LoadTileInfo() {
    if (IsRenderingEnabled()) {
        switch (_cycle & 0x07) {
            case 1: // Load fetched data into shift registers
                _lowBitShift |= _tile.LowByte;
                _highBitShift |= _tile.HighByte;
                // Fetch nametable for NEXT tile
                break;
            case 3: // Attribute fetch
                break;
            case 5: // Pattern low fetch
                break;
            case 7: // Pattern high fetch
                break;
        }
    }
}
```

**Key Difference:** Mesen2 uses `|=` to load into shift registers (ORs low 8 bits), while RAMBO explicitly manages high/low bytes. Both are functionally equivalent.

---

### Shift Register Advance Timing

**Hardware Behavior (per nesdev.org):**

Shift registers advance **every PPU cycle** during specific dot ranges:
- **Dots 2-257:** Visible rendering (shift during pixel output)
- **Dots 322-337:** Prefetch for next scanline (shift during tile 0/1 fetch)

**Current RAMBO Implementation (CORRECT):**
```zig
// src/ppu/Logic.zig:272-280
if (is_rendering_line and rendering_enabled) {
    // Per nesdev forums (ulfalizer): shift between dots 2-257 and 322-337
    if ((dot >= 2 and dot <= 257) or (dot >= 322 and dot <= 337)) {
        state.bg_state.shift();
    }
}
```

**Reference:** https://forums.nesdev.org/viewtopic.php?t=10348

**This timing is already CORRECT.** The refactor should NOT change this.

---

### Sprite Shift Registers

**Hardware Structure (per nesdev.org):**

Each of 8 sprites has:
- `pattern_shift_lo[8]`: Low bitplane (8 bytes, 1 per sprite)
- `pattern_shift_hi[8]`: High bitplane (8 bytes, 1 per sprite)
- `x_counters[8]`: X position countdown (sprite activates when counter reaches 0)
- `attributes[8]`: Palette, priority, flip flags

**Current RAMBO Implementation:**
```zig
// src/ppu/State.zig:211-262
pub const SpriteState = struct {
    pattern_shift_lo: [8]u8 = [_]u8{0} ** 8,
    pattern_shift_hi: [8]u8 = [_]u8{0} ** 8,
    attributes: [8]u8 = [_]u8{0} ** 8,
    x_counters: [8]u8 = [_]u8{0} ** 8,
    // ... evaluation state ...
};
```

**Sprite Shift Behavior:**
```zig
// src/ppu/logic/sprites.zig:208-215
// CRITICAL: Shift ALL active sprites every pixel
if (state.sprite_state.x_counters[i] == 0) {
    // Sprite is active, shift registers
    state.sprite_state.pattern_shift_lo[i] <<= 1;
    state.sprite_state.pattern_shift_hi[i] <<= 1;
}
```

**This is already CORRECT.** No changes needed for sprite shifting.

---

### Mid-Frame Register Update Propagation

**PPUCTRL ($2000) - Pattern Table Base:**

When PPUCTRL bit 4 (background pattern table) changes mid-scanline:
- Change takes effect on **next tile fetch** (next cycle 5-6 or 7-8)
- Does NOT retroactively affect tiles already in shift registers

**PPUMASK ($2001) - Rendering Enable/Disable:**

Hardware has **3-4 dot propagation delay** (already implemented in RAMBO):
```zig
// src/ppu/State.zig:326-335
mask_delay_buffer: [4]PpuMask = [_]PpuMask{.{}} ** 4,
mask_delay_index: u2 = 0,

pub fn getEffectiveMask(self: *const PpuState) PpuMask {
    return self.mask_delay_buffer[self.mask_delay_index];
}
```

**Reference:** https://www.nesdev.org/wiki/PPU_registers#PPUMASK

**Current Implementation:** Already correct. Refactor should preserve this.

---

## Current RAMBO PPU Implementation Analysis

### State/Logic Separation (Already Correct)

**State Module:** `src/ppu/State.zig`
- Pure data structures (no business logic)
- `BackgroundState` struct (lines 271-313)
- `SpriteState` struct (lines 211-262)
- Convenience methods delegate to Logic

**Logic Modules:**
- `src/ppu/Logic.zig` - Main orchestration (tick function)
- `src/ppu/logic/background.zig` - Background tile fetching
- `src/ppu/logic/sprites.zig` - Sprite evaluation and fetching
- `src/ppu/logic/memory.zig` - VRAM access
- `src/ppu/logic/scrolling.zig` - Scroll register manipulation
- `src/ppu/logic/registers.zig` - CPU register I/O

**Pure Function Pattern (Already Correct):**
```zig
// All state passed explicitly via parameters
pub fn fetchBackgroundTile(state: *PpuState, cart: ?*AnyCartridge, dot: u16) void
pub fn getSpritePixel(state: *PpuState, pixel_x: u16) SpritePixel
```

No global state, all side effects explicit. **This pattern should be preserved.**

---

### Background Tile Fetching (Current Implementation)

**File:** `src/ppu/logic/background.zig`

**Fetch Function (lines 45-110):**
```zig
pub fn fetchBackgroundTile(state: *PpuState, cart: ?*AnyCartridge, dot: u16) void {
    const cycle_in_tile = (dot - 1) % 8;
    switch (cycle_in_tile) {
        1 => { /* NT fetch at dots 2, 10, 18... */ },
        3 => { /* AT fetch at dots 4, 12, 20... */ },
        5 => { /* Pattern low at dots 6, 14, 22... */ },
        7 => { /* Pattern high at dots 8, 16, 24... */ },
        0 => { /* Reload shift registers at dots 9, 17, 25... */ },
        else => {},
    }
}
```

**Shift Register Reload (BackgroundState.loadShiftRegisters - lines 291-303):**
```zig
pub fn loadShiftRegisters(self: *BackgroundState) void {
    // Load pattern data into low 8 bits
    self.pattern_shift_lo = (self.pattern_shift_lo & 0xFF00) | self.pattern_latch_lo;
    self.pattern_shift_hi = (self.pattern_shift_hi & 0xFF00) | self.pattern_latch_hi;

    // Load attribute bits (duplicated across 8 bits)
    const attr_lo: u8 = if ((self.attribute_latch & 0x01) != 0) 0xFF else 0x00;
    const attr_hi: u8 = if ((self.attribute_latch & 0x02) != 0) 0xFF else 0x00;
    self.attribute_shift_lo = (self.attribute_shift_lo & 0xFF00) | attr_lo;
    self.attribute_shift_hi = (self.attribute_shift_hi & 0xFF00) | attr_hi;
}
```

**This implementation is ALREADY CYCLE-ACCURATE.** The refactor is NOT about rewriting this - it's about **ensuring ALL PPU operations follow the same cycle-by-cycle pattern.**

---

### Sprite Evaluation (Current Implementation)

**File:** `src/ppu/logic/sprites.zig`

**Progressive Evaluation (lines 237-329):**
```zig
pub fn tickSpriteEvaluation(state: *PpuState, scanline: u16, cycle: u16) void {
    // Cycle-by-cycle sprite evaluation during dots 65-256
    // Odd cycles: Read from OAM
    // Even cycles: Write to secondary OAM
}
```

**Already implements progressive, cycle-accurate evaluation.** This is CORRECT.

**Sprite Fetching (lines 46-146):**
```zig
pub fn fetchSprites(state: *PpuState, cart: ?*AnyCartridge, scanline: u16, dot: u16) void {
    // Cycles 257-320: Fetch 8 sprites × 8 cycles each
    const fetch_cycle = (dot - 257) % 8;
    const sprite_index = (dot - 257) / 8;

    if (fetch_cycle == 5 or fetch_cycle == 6) { /* Low bitplane */ }
    if (fetch_cycle == 7 or fetch_cycle == 0) { /* High bitplane */ }
}
```

**This is ALREADY PROGRESSIVE.** Sprites are fetched cycle-by-cycle.

---

## The Actual Problem: What Needs to Change

### Problem 1: Scanline 0 Sprite Crash

**Symptom:** AccuracyCoin crashes on scanline 0
**Root Cause:** Unknown - needs investigation
**Hypothesis:** Sprite fetch on scanline 0 may trigger invalid memory access or timing issue

**Investigation Steps:**
1. Run AccuracyCoin with debugger at scanline 0
2. Check sprite evaluation state at scanline transition
3. Verify sprite fetch doesn't access invalid memory
4. Check for off-by-one errors in scanline wrapping

**Related Code:**
- `src/ppu/logic/sprites.zig:46-146` (fetchSprites)
- `src/ppu/Logic.zig:305-332` (sprite evaluation orchestration)

---

### Problem 2: Mid-Frame Register Changes

**Symptom:** SMB3 checkered floor disappears, Kirby dialog doesn't render
**Root Cause:** PPUCTRL changes mid-scanline don't propagate correctly to ongoing fetches

**Current Behavior:**
- PPUCTRL.bg_pattern changes immediately affect `ctrl.bg_pattern` field
- Next tile fetch uses NEW pattern table base
- **This should be CORRECT** per hardware spec

**Hypothesis:** The bug is NOT in register propagation, but in **something else**:
- Incorrect scroll register handling during splits
- Background rendering state not properly reset on register change
- Fine X scroll edge cases

**Investigation Steps:**
1. Log PPUCTRL writes during SMB3 gameplay
2. Trace which pattern table is used for each tile fetch
3. Check if scroll registers are manipulated during split-screen
4. Verify fine X scroll doesn't cause tile fetch misalignment

**Related Code:**
- `src/ppu/logic/registers.zig` (PPUCTRL write handling)
- `src/ppu/logic/background.zig:14-29` (getPatternAddress)
- `src/ppu/Logic.zig:272-303` (background pipeline)

---

### Problem 3: Progressive Tile Fetching Not Modeled

**Wait... THIS IS WRONG.** Progressive tile fetching **IS** modeled:

```zig
// src/ppu/logic/background.zig:45-110
const cycle_in_tile = (dot - 1) % 8;
switch (cycle_in_tile) {
    1 => { /* NT fetch */ },
    3 => { /* AT fetch */ },
    5 => { /* Pattern low */ },
    7 => { /* Pattern high */ },
}
```

**This IS progressive fetching.** Each fetch happens at a specific dot, not instantly.

**Re-assessment:** This is NOT a problem. The task description is incorrect about this.

---

### Problem 4: Shift Register Timing Incorrect

**Current Shift Timing:**
```zig
// src/ppu/Logic.zig:272-280
if ((dot >= 2 and dot <= 257) or (dot >= 322 and dot <= 337)) {
    state.bg_state.shift();
}
```

**Hardware Specification (nesdev forums):**
- Shift during dots 2-257 (visible rendering)
- Shift during dots 322-337 (prefetch)

**This timing is CORRECT.** No changes needed.

---

## What Actually Needs to Be Fixed

After analyzing hardware specs and current code:

### Actual Issue 1: Scanline 0 Sprite Crash (Unknown Root Cause)

**Needs Investigation:** Run AccuracyCoin with debugger, identify crash point

### Actual Issue 2: Mid-Frame Register Changes (Hypothesis: NOT shift registers)

**Likely Culprits:**
1. **Fine X scroll edge case** - SMB1 has green line on left side (8 pixels = fine X range)
2. **Scroll register race conditions** - Mid-scanline PPUSCROLL writes
3. **First tile fetch issue** - Dot 1 behavior or dot 321 prefetch

**NOT shift register reloading** - that's already cycle-accurate.

### Actual Issue 3: Test Suite Incompatibility

From parent task (`timing_issues.md`):
- Many tests assume old execution order
- Tests need updating to match CPU-before-PPU-state-updates ordering
- AccuracyCoin shows progress (iterations 1-2 now pass)

---

## What This Refactor Should ACTUALLY Do

Based on evidence, the "shift register rewrite" should focus on:

### 1. Investigation Phase (CRITICAL)

**Run AccuracyCoin with instrumentation:**
- Log every PPU state change during scanline 0
- Log every sprite fetch during scanline 0
- Identify exact crash point

**Run SMB3 with PPUCTRL logging:**
- Log every PPUCTRL write (value, scanline, dot)
- Log pattern table address for each tile fetch
- Compare against expected behavior

### 2. Edge Case Fixes (Based on Investigation)

**Potential Fixes (TBD after investigation):**
- Scanline 0 sprite evaluation initialization
- Pre-render scanline sprite fetch behavior
- Fine X scroll edge case (dots 1-8 rendering)
- PPUCTRL mid-scanline change edge case

### 3. Test Suite Updates

**Update tests to match new execution order:**
- VBlankLedger tests (3 tests)
- Integration tests (3 tests)
- EmulationState timing tests (5 tests)

**Document test changes in dedicated audit file** (similar to `tests_updated.md`)

---

## Mesen2 Reference Implementation Summary

**Path:** `/home/colin/Development/Mesen2/Core/NES/`
- `NesPpu.h` - PPU class definition
- `NesPpu.cpp` - PPU implementation
- `BaseNesPpu.h` - Base state structure (shift registers at lines 26-27)

**Key Functions:**
- `ShiftTileRegisters()` - Shifts both shift registers left by 1 (line 811)
- `LoadTileInfo()` - Loads fetched tile data into shift registers (line 667)
- `GetPixelColor()` - Extracts pixel from shift registers using fine X (line 818)

**Key State Fields (BaseNesPpu.h):**
```cpp
uint16_t _highBitShift = 0;  // Pattern bitplane 1
uint16_t _lowBitShift = 0;   // Pattern bitplane 0
uint8_t _xScroll = 0;        // Fine X scroll (3 bits)
```

**Mesen2 Shift Register Reload (cycle & 0x07 == 1):**
```cpp
_lowBitShift |= _tile.LowByte;   // OR low 8 bits
_highBitShift |= _tile.HighByte; // OR low 8 bits
```

**RAMBO Equivalent (already implemented):**
```zig
self.pattern_shift_lo = (self.pattern_shift_lo & 0xFF00) | self.pattern_latch_lo;
self.pattern_shift_hi = (self.pattern_shift_hi & 0xFF00) | self.pattern_latch_hi;
```

**Functionally identical.** Mesen2 ORs because high byte is already 0 after shifting. RAMBO explicitly masks for clarity.

---

## Existing RAMBO Test Coverage

### PPU Unit Tests (tests/ppu/)

**Background Rendering:**
- `background_fetch_timing_test.zig` - Verifies 8-dot fetch cycle timing
- `chr_integration_test.zig` - CHR ROM pattern fetching

**Sprite Rendering:**
- `sprite_evaluation_test.zig` - Progressive evaluation (dots 65-256)
- `sprite_rendering_test.zig` - Sprite pixel output
- `sprite_y_delay_test.zig` - 1-scanline pipeline delay
- `sprite_edge_cases_test.zig` - Edge conditions
- `sprite0_hit_clipping_test.zig` - Sprite 0 hit detection

**Register Behavior:**
- `ppuctrl_mid_scanline_test.zig` - Mid-scanline PPUCTRL changes
- `ppumask_delay_test.zig` - 3-4 dot propagation delay
- `ppustatus_polling_test.zig` - VBlank flag race conditions
- `vblank_behavior_test.zig` - VBlank timing
- `vblank_nmi_timing_test.zig` - NMI edge detection

**Other:**
- `greyscale_test.zig` - Greyscale mode
- `a12_edge_detection_test.zig` - MMC3 IRQ timing
- `oamaddr_reset_test.zig` - OAMADDR behavior
- `status_bit_test.zig` - Status register bits
- `simple_vblank_test.zig` - Basic VBlank
- `seek_behavior_test.zig` - Test harness positioning

### PPU Integration Tests (tests/integration/)

- `cpu_ppu_integration_test.zig` - CPU/PPU coordination
- `ppu_register_absolute_test.zig` - Absolute addressing
- `ppu_write_toggle_test.zig` - Write toggle (w register)
- `bit_ppustatus_test.zig` - BIT instruction on PPUSTATUS

### Visual Regression Tests

Commercial ROMs tested:
- ✅ Super Mario Bros 1
- ✅ Castlevania
- ✅ Mega Man
- ✅ Kid Icarus
- ✅ Battletoads
- ⚠️ SMB3 (checkered floor bug)
- ⚠️ Kirby's Adventure (dialog box bug)
- ❌ TMNT (grey screen)

### AccuracyCoin Tests

From `tests_updated.md` (lines 145-187):
- ALL NOP INSTRUCTIONS - FAIL (err=1)
- UNOFFICIAL INSTRUCTIONS - FAIL (err=10)
- NMI CONTROL - FAIL (err=7)
- NMI AT VBLANK END - FAIL (err=1)
- NMI DISABLED AT VBLANK - FAIL (err=1)
- VBLANK END - FAIL (err=1)
- **VBLANK BEGINNING** - PARTIAL PASS (iterations 1-2 correct, 3-7 wrong)
- NMI SUPPRESSION - FAIL (err=1)
- NMI TIMING - FAIL (err=1)

**Progress:** After sub-cycle timing fix, VBLANK BEGINNING iterations 1-2 now pass (was all wrong before).

---

## Related Systems & Integration Points

### Emulation State Coordination

**File:** `src/emulation/State.zig` (EmulationState)

**PPU Integration:**
```zig
pub fn tick(self: *EmulationState) TickResult {
    // 1. PPU ticks (rendering, fetching, sprite evaluation)
    const ppu_result = PpuLogic.tick(&self.ppu, ...);

    // 2. APU processing
    // 3. CPU memory operations (reads can see PPU state BEFORE updates)
    // 4. Apply PPU state updates (VBlank flag, frame complete)
    self.applyPpuCycleResult(ppu_result);
}
```

**Critical Ordering (from parent task):**
- CPU reads $2002 BEFORE `applyPpuCycleResult()`
- This creates race condition: CPU can read $2002 same cycle VBlank sets
- CPU sees CLEAR (0x00), then PPU sets flag on same cycle
- Next CPU read sees SET (0x80)

**This ordering is CORRECT per hardware spec.**

### Frame Rendering Output

**File:** `src/threads/RenderThread.zig`

**Frame Data Flow:**
1. PPU writes pixels to `framebuffer` during visible scanlines
2. Frame complete signal sent via `FrameMailbox`
3. Render thread consumes frame data
4. Backend (Vulkan or Movy) displays frame

**PPU Pixel Output (Logic.zig lines 335-385):**
```zig
if (is_visible and dot >= 1 and dot <= 256) {
    const pixel_x = dot - 1;
    const pixel_y = scanline;

    const bg_pixel = getBackgroundPixel(state, pixel_x);
    const sprite_result = getSpritePixel(state, pixel_x);

    // Priority blending...
    const color = getPaletteColor(state, final_palette_index);

    if (framebuffer) |fb| {
        fb[pixel_y * 256 + pixel_x] = color;
    }
}
```

**No changes needed.** Framebuffer output is already cycle-accurate.

### PPUCTRL/PPUMASK Register Handling

**File:** `src/ppu/logic/registers.zig`

**PPUCTRL Write:**
```zig
pub fn writeRegister(state: *PpuState, cart: ?*AnyCartridge, address: u16, value: u8) void {
    switch (address & 0x07) {
        0x00 => { // PPUCTRL
            state.ctrl = PpuCtrl.fromByte(value);
            // Update t register bits 10-11 (nametable select)
            state.internal.t = (state.internal.t & 0xF3FF) | ...;
        },
        // ...
    }
}
```

**PPUCTRL changes take effect immediately.** Next tile fetch uses new values.

**PPUMASK Write:**
```zig
0x01 => { // PPUMASK
    state.mask = PpuMask.fromByte(value);
    // Delay buffer updated in tick() function
}
```

**Delay buffer advanced every tick (Logic.zig lines 209-214):**
```zig
state.mask_delay_buffer[state.mask_delay_index] = state.mask;
state.mask_delay_index = @truncate((state.mask_delay_index +% 1) & 3);
```

**This is CORRECT.** 3-4 dot delay is already implemented.

---

## Parent Task Context: VBlank Sub-Cycle Timing Fix

**Task:** `h-fix-vblank-subcycle-timing`
**Status:** Core fix implemented, tests being updated

### What Changed

**Before:** CPU reads $2002 AFTER PPU state updates (wrong order)
**After:** CPU reads $2002 BEFORE PPU state updates (correct order)

**Impact:**
- Race condition now matches hardware: CPU read at (241,1) sees CLEAR (0x00)
- Next CPU read sees SET (0x80)
- AccuracyCoin VBLANK BEGINNING iterations 1-2 now PASS (was all wrong)

### Test Failures Introduced

**12 new failures** (all timing-related, not logic bugs):
- 3 VBlankLedger tests - conceptual issue with "same-cycle" semantics
- 5 EmulationState tests - initial phase offset (ppu_cycles = 2 not 0)
- 3 integration tests - same conceptual issue as VBlankLedger
- 1 DMC/OAM test - needs investigation
- 8 AccuracyCoin tests - real emulation bugs (user will investigate)

### Key Insights from Parent Task

1. **Tests were written with incorrect execution order assumptions**
2. **Master clock initial phase (ppu_cycles = 2) needs investigation**
3. **AccuracyCoin shows PROGRESS** - iterations 1-2 pass (was 0/7 before)
4. **Sub-cycle fix is CORRECT** - tests need updating, not code

---

## Implementation Strategy

### Phase 1: Investigation (MANDATORY FIRST)

**DO NOT write code until investigation is complete.**

1. **Run AccuracyCoin with debugger**
   - Set breakpoint at scanline 0, dot 0
   - Log PPU state every cycle of scanline 0
   - Log sprite evaluation state
   - Log sprite fetch operations
   - **Identify exact crash point**

2. **Run SMB3 with PPUCTRL logging**
   - Log every PPUCTRL write (value, scanline, dot)
   - Log pattern table base for each tile fetch
   - Log scroll register state during split-screen
   - **Identify when checkered floor disappears**

3. **Run Kirby with rendering logging**
   - Log rendering state during dialog box
   - Log PPUCTRL/PPUMASK changes
   - Log background tile fetches
   - **Identify why dialog doesn't render**

4. **Document findings**
   - Create `investigation_results.md` in task directory
   - Include all logs, observations, hypotheses
   - Propose specific fixes based on evidence

### Phase 2: Targeted Fixes (Based on Investigation)

**Only fix problems IDENTIFIED in Phase 1.**

Potential fixes (TBD):
- Scanline 0 sprite evaluation edge case
- Pre-render scanline sprite fetch behavior
- Fine X scroll at screen edge (dots 1-8)
- PPUCTRL change propagation edge case
- Scroll register manipulation during splits

**DO NOT do a "big rewrite."** Make surgical, evidence-based fixes.

### Phase 3: Test Suite Updates

**Update tests to match new execution order:**

1. **Audit all PPU tests**
   - Document which tests assume old execution order
   - Document which tests are incompatible with shift register model
   - Create `test_audit.md` (similar to parent task's `tests_updated.md`)

2. **Update test expectations**
   - VBlankLedger tests (3 tests)
   - Integration tests (3 tests)
   - EmulationState timing tests (5 tests)
   - Document EVERY change with hardware spec reference

3. **Create new shift register tests**
   - Test shift register reload timing
   - Test mid-frame register update propagation
   - Test fine X scroll edge cases
   - Test scanline boundary behavior

### Phase 4: Regression Testing

**Verify NO regressions:**
- All existing PPU tests still pass (or updated with documented rationale)
- Visual regression tests pass (SMB1, Castlevania, Mega Man, etc.)
- AccuracyCoin shows improvement (not regression)

---

## Success Metrics

### Primary Metrics

- [ ] AccuracyCoin scanline 0 crash **FIXED**
- [ ] SMB3 checkered floor renders **correctly throughout game**
- [ ] Kirby's Adventure dialog box renders **correctly**
- [ ] AccuracyCoin VBLANK BEGINNING **all 7 iterations pass** (currently 2/7)

### Secondary Metrics

- [ ] All existing PPU tests pass (or updated with hardware spec justification)
- [ ] Visual regression tests pass (no new rendering bugs)
- [ ] Test audit document created (similar to `tests_updated.md`)
- [ ] Every test change documented with hardware reference

### Anti-Metrics (Things to AVOID)

- ❌ **Do NOT rewrite entire PPU** - make targeted fixes only
- ❌ **Do NOT change already-correct shift timing** (dots 2-257, 322-337)
- ❌ **Do NOT change State/Logic separation pattern**
- ❌ **Do NOT break existing working games** (SMB1, Castlevania, etc.)

---

## Code Quality Guidelines

### Readability Over Cleverness

**Prioritize:**
- Clear, obvious implementations
- Extensive comments explaining hardware behavior
- Well-named functions matching hardware terminology
- Breaking complex operations into understandable steps

**Example (GOOD):**
```zig
// Hardware behavior: Sprite evaluation on scanline N determines sprites
// for NEXT scanline (N+1). This creates 1-scanline pipeline delay.
// Reference: nesdev.org/wiki/PPU_sprite_evaluation
const next_scanline = (scanline + 1) % 262;
```

**Example (BAD):**
```zig
const sl = (s + 1) & 0x1FF; // Wrap scanline
```

### Hardware Citations Required

**Every non-obvious behavior MUST cite hardware documentation:**

```zig
// Per nesdev forums (ulfalizer): "The shifters seem to shift between
// dots 2...257 and dots 322...337"
// Reference: https://forums.nesdev.org/viewtopic.php?t=10348
if ((dot >= 2 and dot <= 257) or (dot >= 322 and dot <= 337)) {
    state.bg_state.shift();
}
```

### State/Logic Separation MUST Be Preserved

**All PPU logic functions take explicit state parameters:**

```zig
pub fn fetchBackgroundTile(state: *PpuState, cart: ?*AnyCartridge, dot: u16) void
```

**No global variables, no hidden mutations, all side effects explicit.**

---

## File Locations

### State Files
- `src/ppu/State.zig` - PPU state structures
  - `BackgroundState` (lines 271-313)
  - `SpriteState` (lines 211-262)
  - `PpuState` (lines 318-432)

### Logic Files
- `src/ppu/Logic.zig` - Main PPU tick orchestration
- `src/ppu/logic/background.zig` - Background tile fetching
- `src/ppu/logic/sprites.zig` - Sprite evaluation and fetching
- `src/ppu/logic/memory.zig` - VRAM access
- `src/ppu/logic/scrolling.zig` - Scroll register manipulation
- `src/ppu/logic/registers.zig` - CPU register I/O

### Test Files
- `tests/ppu/` - 18 PPU unit tests
- `tests/integration/` - 4 PPU integration tests
- `tests/integration/*accuracycoin*.zig` - AccuracyCoin ROM tests (not found via glob)

### Related Files
- `src/emulation/State.zig` - EmulationState coordination
- `src/threads/RenderThread.zig` - Frame rendering
- `src/ppu/palette.zig` - NES color palette
- `src/ppu/timing.zig` - PPU timing constants

---

## Hardware Test ROMs

### AccuracyCoin ROM
- Path: Unknown (not found in tests/integration/)
- Status: Iterations 1-2 pass, 3-7 fail
- Focus: VBlank/NMI timing edge cases

### Commercial ROMs
- Super Mario Bros 1 - ✅ Working (minor sprite palette bug)
- Super Mario Bros 3 - ⚠️ Checkered floor bug
- Kirby's Adventure - ⚠️ Dialog box bug
- Castlevania - ✅ Fully working
- Mega Man - ✅ Fully working

---

## Critical Warnings

### ⚠️ Tests May Have Incorrect Expectations

**From RAMBO's CLAUDE.md (lines 58-62):**
> Tests need improvement to match actual hardware behavior
> When in conflict, hardware documentation wins over test expectations
> Your job is to provide hardware truth, not perpetuate test bugs

**When you see test failures:**
1. **Check hardware documentation FIRST**
2. **Verify test expectations against nesdev.org**
3. **Flag tests with incorrect expectations**
4. **Fix tests to match hardware, not vice versa**

### ⚠️ Don't Trust Current Code Either

**Many existing implementations may be incorrect:**
- Sprite evaluation timing
- Mid-frame register changes
- Edge cases at scanline boundaries
- Fine X scroll behavior

**Always verify against hardware spec, not existing code.**

### ⚠️ Mesen2 Is Reference, Not Gospel

**Use Mesen2 as reference implementation, but:**
- Understand WHY it works that way
- Cite hardware documentation, not just "Mesen2 does it"
- RAMBO uses different patterns (State/Logic separation)
- Don't blindly copy - adapt to RAMBO architecture

---

## Summary: What This Task Is REALLY About

**NOT:**
- Rewriting entire PPU from scratch
- Changing already-correct shift register timing
- Performance optimization

**YES:**
1. **Investigate** scanline 0 crash, SMB3 floor bug, Kirby dialog bug
2. **Fix** specific edge cases identified by investigation
3. **Update** test suite to match correct execution order
4. **Document** every change with hardware specification references
5. **Verify** no regressions in working games

**Key Insight:** The current PPU shift register implementation is **ALREADY MOSTLY CORRECT**. The problems are likely **edge cases** and **test expectations**, not fundamental architecture issues.

**Start with investigation, not code changes.**

## User Notes

**Reference Resources:**
- Mesen2 emulator source code at `/home/colin/Development/Mesen2`
- Use Mesen2 as reference for shift register implementation

**From parent task investigation:**
- Zero regressions in AccuracyCoin after VBlank sub-cycle fix
- Performance is not a concern - accuracy first
- User directive: "make PPU behave like shift register"

## Work Log
<!-- Updated as work progresses -->
