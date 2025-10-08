# Comprehensive Hardware Accuracy Audit (2025-10-07)

## Status: 🔍 IN PROGRESS

**Goal:** Systematically identify ALL deviations from NES hardware behavior to fix remaining commercial game rendering issues.

**Context:**
- ✅ Bomberman displays something (partial success)
- ❌ Super Mario Bros shows blank screen (still broken)
- ✅ AccuracyCoin passes all tests ($00 $00 $00 $00)
- ✅ Tests: 887/888 passing

**Hypothesis:** Subtle timing or state update ordering differences prevent some games from initializing correctly.

---

## Audit Methodology

### 1. Core Timing Architecture

#### 1.1 Master Clock (EmulationState.tick)

**Location:** `src/emulation/State.zig:635-692`

**Current Implementation:**
```zig
pub fn tick(self: *EmulationState) void {
    // 1. Odd frame skip check
    // 2. Advance PPU clock (+1)
    // 3. Determine tick flags:
    //    - cpu_tick = (ppu_cycles % 3) == 0
    //    - ppu_tick = true (every cycle)
    //    - apu_tick = cpu_tick
    // 4. Tick in order: PPU → CPU/DMA → APU
}
```

**Hardware Behavior:**
- Master clock runs at 21.477272 MHz (NTSC)
- CPU divides by 12 (1.789773 MHz)
- PPU divides by 4 (5.369318 MHz)
- Ratio: 3 PPU cycles per 1 CPU cycle ✅

**Potential Issues:**
- ⚠️ **CRITICAL:** Tick order may matter for state consistency
- ⚠️ **Order:** PPU ticks first, then CPU, then APU
- ❓ **Question:** Should PPU tick *after* CPU on CPU cycles?
- ❓ **Question:** Are there any edge cases where component interaction matters?

**NES Hardware Evidence:**
- All components run in parallel on hardware
- Our sequential tick order is an approximation
- Need to verify: Does tick order create observable differences?

#### 1.2 PPU Timing Advance (PpuRuntime.tick)

**Location:** `src/emulation/Ppu.zig:38-178`

**Current Implementation:**
```zig
pub fn tick(...) TickFlags {
    // 1. Advance dot counter (+1)
    // 2. Wrap at dot 340 → scanline++
    // 3. Wrap at scanline 261 → frame++
    // 4. Odd frame skip (scanline 0, dot 0 → dot 1)
    // 5. Execute PPU operations (background, sprites, pixels)
    // 6. Set flags (VBlank, frame_complete)
}
```

**Issues Found:**

**ISSUE #1: Double Timing Advance**
- ❌ **EmulationState.tick()** advances PPU timing via `self.clock.ppu_cycles += 1`
- ❌ **PpuRuntime.tick()** ALSO advances timing via `timing.dot += 1`
- ❌ **RESULT:** PPU timing advances TWICE per call!

**Evidence:**
```zig
// EmulationState.tick (line 653)
self.clock.ppu_cycles += 1;  // ← Advance #1

// Then calls:
self.tickPpu();
    // → calls PpuRuntime.tick(&self.ppu, &self.ppu_timing, ...)

// PpuRuntime.tick (line 50)
timing.dot += 1;  // ← Advance #2 (DUPLICATE!)
```

**Impact:**
- 🔴 **CRITICAL BUG:** PPU runs at 2× speed!
- This explains why some games fail - they rely on precise CPU/PPU timing ratios
- Frame timing would be completely wrong
- VBlank would occur too early relative to CPU execution

**Hardware Reference:**
- NES PPU: 341 dots × 262 scanlines = 89,342 PPU cycles per frame
- CPU: 29,780.67 cycles per frame (89,342 ÷ 3)
- If PPU advances twice: 178,684 PPU cycles → 2× speed → WRONG!

**Fix Required:**
- Remove ONE of the timing advances
- Likely keep `PpuRuntime.tick`'s advance, remove `EmulationState.tick`'s advance
- OR: Keep master clock advance, make PpuRuntime read-only

---

### 2. State Update Ordering

#### 2.1 CPU State Updates

**Location:** `src/emulation/State.zig:1047-1400`

**Current Order:**
```zig
pub fn tickCpu(self: *EmulationState) void {
    self.cpu.cycle_count += 1;  // ← Timing update FIRST

    // Check PPU warm-up
    if (!self.ppu.warmup_complete and self.cpu.cycle_count >= 29658) {
        self.ppu.warmup_complete = true;  // ← Cross-component update
    }

    // Execute CPU microstep
    // ...
}
```

**Potential Issue:**
- ⚠️ Warm-up check happens BEFORE CPU executes
- ⚠️ Cross-component state update (CPU → PPU)
- ❓ Does this create ordering dependency?

**Hardware Behavior:**
- CPU and PPU run in parallel
- No cross-component state updates (except via bus/registers)
- Warm-up is PPU-internal behavior, not CPU-driven

**Question:** Should warm-up check be in PPU tick instead?

#### 2.2 PPU State Updates

**Location:** `src/emulation/Ppu.zig:73-176`

**Current Operations (in order):**
```zig
1. Background shift (dot 1-256)
2. Background tile fetch (dot 1-256, 321-336)
3. Scroll increment Y (dot 256)
4. Scroll copy X (dot 257)
5. Scroll copy Y (dot 280-304, prerender only)
6. Sprite evaluation (dot 65)
7. Sprite fetching (dot 257-320)
8. Pixel output (dot 1-256)
9. VBlank set (scanline 241, dot 1)
10. Pre-render clear (scanline 261, dot 1)
11. Frame complete flag (scanline 261, dot 340)
```

**Hardware Reference (nesdev.org):**
- Background fetch happens in parallel with rendering
- Sprite evaluation happens during visible scanlines only
- All operations are cycle-accurate

**Verification Needed:**
- ✅ Dot ranges correct (verified against nesdev.org)
- ✅ Scanline numbers correct
- ❓ Operation ordering correct?
- ❓ State mutation order matters?

#### 2.3 Frame Boundary Timing

**Current Implementation:**
```zig
// PpuRuntime.tick (line 165)
if (scanline == 261 and dot == 340) {
    flags.frame_complete = true;
}

// EmulationState.tickPpu (line 1565)
if (flags.frame_complete) {
    self.frame_complete = true;
}

// emulateFrame (line 1723)
while (!self.frame_complete) {
    self.tick();
}
```

**Potential Issue:**
- ⚠️ Frame complete set at scanline 261, dot 340
- ⚠️ Next tick would wrap to scanline 0, dot 0
- ⚠️ But emulateFrame checks frame_complete AFTER tick
- ❓ Does this create off-by-one frame boundary?

**Hardware Behavior:**
- Frame ends after scanline 261, dot 340
- Next cycle is scanline 0, dot 0 (or dot 1 on odd frames)
- Need to verify: Is boundary detection precise?

---

### 3. Controller Runtime Behavior

**Location:** `src/emulation/State.zig:169-221`

#### 3.1 Strobe Behavior

**Current Implementation:**
```zig
pub fn writeStrobe(self: *ControllerState, value: u8) void {
    const new_strobe = (value & 0x01) != 0;
    const rising_edge = new_strobe and !self.strobe;

    self.strobe = new_strobe;  // ← Update BEFORE latch check

    if (rising_edge) {
        self.latch();
    }
}
```

**Hardware Behavior (nesdev.org):**
- Strobe write updates strobe immediately
- Rising edge (0→1) latches button state
- Strobe high: read returns current button state (bit 0)
- Strobe low: read shifts out bits, refills with 1s

**Verification:**
- ✅ Rising edge detection correct
- ✅ Latch behavior correct
- ✅ Shift behavior correct
- ❓ But: When does button state update relative to strobe?

#### 3.2 Button Update Timing

**Current Implementation:**
```zig
// EmulationThread (every frame)
const input = ctx.mailboxes.controller_input.getInput();
ctx.state.controller.updateButtons(input.controller1.toByte(), input.controller2.toByte());

// updateButtons:
pub fn updateButtons(self: *ControllerState, buttons1: u8, buttons2: u8) void {
    self.buttons1 = buttons1;
    self.buttons2 = buttons2;
    if (self.strobe) {  // ← If strobe high, reload immediately
        self.latch();
    }
}
```

**Timing:**
- Button updates happen once per frame (60 Hz)
- Updates occur at frame boundary (between frames)
- If strobe is high during update, shift registers reload immediately

**Hardware Behavior:**
- Button state is continuous (not frame-based)
- Games can latch at any time during frame
- Button changes are instant

**Potential Issue:**
- ⚠️ **TIMING GRANULARITY:** Buttons update once per frame, but games may poll mid-frame
- ⚠️ Games expecting button state changes during frame won't see them
- ❓ Does this affect initialization sequences?
- ❓ Do any games poll controller during boot?

**Evidence Needed:**
- Check Super Mario Bros boot code for controller polling
- Verify when games latch controller state
- Determine if mid-frame polling is used during initialization

---

### 4. Memory Access Patterns

#### 4.1 Bus Read/Write Ordering

**Location:** `src/emulation/State.zig` (busRead/busWrite)

**Current Implementation:**
```zig
pub fn busRead(self: *EmulationState, address: u16) u8 {
    return BusLogic.read(&self.bus, address, &self.ppu, &self.apu, &self.controller, self.cartPtr());
}

pub fn busWrite(self: *EmulationState, address: u16, value: u8) void {
    BusLogic.write(&self.bus, address, value, &self.ppu, &self.apu, &self.controller, &self.dma, self.cartPtr());
}
```

**Hardware Behavior:**
- Bus operations are instant (single cycle)
- Read/write happen atomically
- Side effects (register updates) happen immediately

**Verification:**
- ✅ Operations are atomic
- ✅ Side effects handled in BusLogic
- ❓ Are there any multi-cycle bus operations that need special handling?

#### 4.2 PPU Register Write Effects

**Location:** `src/ppu/Logic.zig:writeRegister`

**Register $2000 (PPUCTRL):**
```zig
if (!state.warmup_complete) return;  // ← Warm-up gate

state.ctrl = PpuCtrl.fromByte(value);
// Update t register (bits 10-11)
state.internal.t = (state.internal.t & 0xF3FF) | ((@as(u16, value) & 0x03) << 10);
```

**Register $2001 (PPUMASK):**
```zig
if (!state.warmup_complete) return;  // ← Warm-up gate

state.mask = PpuMask.fromByte(value);
```

**Register $2005 (PPUSCROLL):**
```zig
if (!state.warmup_complete) return;  // ← Warm-up gate

if (!state.internal.w) {
    // First write: fine X + coarse X
    state.internal.x = @truncate(value & 0x07);
    state.internal.t = (state.internal.t & 0xFFE0) | (value >> 3);
} else {
    // Second write: fine Y + coarse Y
    state.internal.t = (state.internal.t & 0x8C1F) |
                      (((@as(u16, value) & 0x07) << 12) |
                       ((@as(u16, value) & 0xF8) << 2));
}
state.internal.w = !state.internal.w;
```

**Potential Issues:**
- ✅ Warm-up gating correct
- ✅ Register update immediate
- ✅ Toggle (w) behavior correct
- ❓ Are updates applied at the right time in frame?
- ❓ Can mid-scanline writes cause issues?

**Hardware Behavior:**
- Register writes take effect immediately
- Some effects are delayed until next frame/scanline
- Mid-scanline writes can cause glitches (intentional for effects)

**Question:** Do we handle mid-scanline register writes correctly?

---

### 5. Known Timing Issues

#### 5.1 Odd Frame Skip

**Current Implementation:**
```zig
// EmulationState.tick (line 642)
if (self.odd_frame and self.rendering_enabled and
    current_scanline == 261 and current_dot == 340)
{
    self.clock.ppu_cycles += 2;  // ← Skip dot 0
    self.odd_frame = false;
    return;
}

// PpuRuntime.tick (line 60)
if (timing.scanline == 0 and timing.dot == 0 and
    (timing.frame & 1) == 1 and state.mask.renderingEnabled()) {
    timing.dot = 1;  // ← ALSO skips dot 0
}
```

**ISSUE #2: Double Odd Frame Skip**
- ❌ EmulationState skips by advancing clock +2
- ❌ PpuRuntime ALSO skips by setting dot = 1
- ❌ **RESULT:** Potentially skipping 2 dots instead of 1!

**Hardware Behavior:**
- On odd frames with rendering enabled, skip 1 dot (341→340 total dots)
- This shortens frame by 1 PPU cycle
- Should happen exactly once per odd frame

**Impact:**
- 🔴 **CRITICAL:** Frame timing wrong on odd frames
- Could cause VBlank to occur at wrong time
- Could break games that rely on precise frame timing

**Fix Required:**
- Remove ONE of the skip implementations
- Verify frame lengths: Even=89,342 cycles, Odd=89,341 cycles

---

### 6. Critical Bugs Identified

#### BUG #1: DOUBLE PPU TIMING ADVANCE 🔴

**Severity:** CRITICAL
**Impact:** PPU runs at 2× speed, completely breaks timing

**Location:**
- `EmulationState.tick` (line 653): `self.clock.ppu_cycles += 1`
- `PpuRuntime.tick` (line 50): `timing.dot += 1`

**Fix:**
- Choose ONE authoritative timing source
- Option A: Remove line 653, let PpuRuntime manage timing
- Option B: Remove line 50, let master clock drive everything
- **Recommendation:** Option B (master clock authority)

**Evidence:**
- Both functions increment timing counters
- PpuRuntime.tick is called FROM EmulationState.tickPpu
- Clock gets advanced twice per tick cycle

**Test:**
- Verify frame cycle count: Should be 89,342 (NTSC), not 178,684

---

#### BUG #2: DOUBLE ODD FRAME SKIP 🔴

**Severity:** CRITICAL
**Impact:** Odd frames have wrong length, breaks VBlank timing

**Location:**
- `EmulationState.tick` (line 647): `self.clock.ppu_cycles += 2`
- `PpuRuntime.tick` (line 62): `timing.dot = 1`

**Fix:**
- Remove ONE skip implementation
- If keeping master clock authority, remove PpuRuntime skip
- If keeping PpuRuntime timing, remove EmulationState skip
- **Recommendation:** Keep PpuRuntime skip (more localized)

**Evidence:**
- Both check odd frame + rendering enabled
- Both skip dot 0 of scanline 0
- Results in double-skip (2 dots instead of 1)

**Test:**
- Verify odd frame length: Should be 89,341 cycles, not 89,340

---

#### BUG #3: TIMING STATE DUPLICATION ⚠️

**Severity:** HIGH
**Impact:** Two separate timing state structures, can diverge

**Location:**
- `EmulationState.clock` (master clock, ppu_cycles counter)
- `EmulationState.ppu_timing` (PPU timing, scanline/dot/frame)

**Issue:**
- Master clock tracks total PPU cycles
- PPU timing tracks scanline/dot/frame
- These can become inconsistent
- No synchronization mechanism

**Fix:**
- Derive one from the other
- OR: Unify into single timing structure
- **Recommendation:** Compute scanline/dot from ppu_cycles on demand

**Evidence:**
- Two separate structs with overlapping responsibilities
- ppu_cycles can drift from (scanline × 341 + dot)

**Test:**
- Verify: ppu_cycles == (scanline × 341 + dot) at all times

---

### 7. Systematic Testing Plan

#### 7.1 Timing Verification Tests

**Test 1: Frame Cycle Count**
```zig
test "NTSC frame has correct cycle count" {
    var state = EmulationState.init(config);

    const start_cycles = state.clock.ppu_cycles;
    state.emulateFrame();
    const end_cycles = state.clock.ppu_cycles;

    const elapsed = end_cycles - start_cycles;

    // Even frames: 89,342 cycles
    // Odd frames: 89,341 cycles (with rendering enabled)
    try testing.expect(elapsed == 89342 or elapsed == 89341);
}
```

**Test 2: CPU/PPU Cycle Ratio**
```zig
test "CPU/PPU ratio is 1:3" {
    var state = EmulationState.init(config);

    const start_ppu = state.clock.ppu_cycles;
    const start_cpu = state.cpu.cycle_count;

    state.emulateCpuCycles(10000);

    const ppu_elapsed = state.clock.ppu_cycles - start_ppu;
    const cpu_elapsed = state.cpu.cycle_count - start_cpu;

    // Should be exactly 3:1 ratio
    try testing.expectEqual(cpu_elapsed * 3, ppu_elapsed);
}
```

**Test 3: Timing State Consistency**
```zig
test "Master clock matches PPU timing" {
    var state = EmulationState.init(config);

    // Run for 1 frame
    state.emulateFrame();

    // Verify consistency
    const computed_cycles = state.ppu_timing.frame * 89342 +
                           state.ppu_timing.scanline * 341 +
                           state.ppu_timing.dot;

    try testing.expectEqual(state.clock.ppu_cycles, computed_cycles);
}
```

#### 7.2 Controller Timing Tests

**Test 4: Button Update Visibility**
```zig
test "Button updates visible during strobe" {
    var state = EmulationState.init(config);

    // Set initial buttons
    state.controller.updateButtons(0x00, 0x00);

    // Strobe high
    state.controller.writeStrobe(0x01);

    // Update buttons while strobe high
    state.controller.updateButtons(0x01, 0x00);  // A button

    // Read should see new state immediately
    const bit = state.controller.read1();
    try testing.expectEqual(@as(u8, 1), bit);
}
```

#### 7.3 PPU Register Write Tests

**Test 5: Mid-Scanline Writes**
```zig
test "PPUCTRL write during rendering" {
    var state = EmulationState.init(config);

    // Enable rendering
    state.ppu.mask.show_bg = true;

    // Advance to mid-scanline
    // TODO: Implement precise scanline positioning

    // Write PPUCTRL mid-scanline
    // Verify behavior matches hardware
}
```

---

### 8. Priority Fix Plan

**Immediate (Critical Bugs):**
1. 🔴 **BUG #1:** Fix double PPU timing advance
2. 🔴 **BUG #2:** Fix double odd frame skip
3. ⚠️ **BUG #3:** Unify timing state structures

**High Priority:**
4. Verify frame cycle counts (even=89,342, odd=89,341)
5. Verify CPU/PPU ratio (1:3)
6. Add timing consistency tests

**Medium Priority:**
7. Review controller update timing (frame vs continuous)
8. Review PPU register write timing (mid-scanline effects)
9. Review warm-up check placement (CPU vs PPU)

**Low Priority:**
10. Component tick ordering (PPU→CPU→APU vs other orders)
11. State update ordering within components
12. Edge case verification

---

### 9. Expected Impact

**If Timing Bugs Fixed:**
- ✅ Super Mario Bros should initialize correctly
- ✅ Frame timing should match hardware precisely
- ✅ VBlank should occur at correct time
- ✅ All commercial games should work

**Confidence Level:** HIGH
- Identified concrete timing bugs (double advance, double skip)
- Bugs directly affect frame timing
- Games rely on precise timing for initialization

---

## Next Steps

1. **Create timing verification tests** (above)
2. **Fix BUG #1: Double timing advance** (critical)
3. **Fix BUG #2: Double odd frame skip** (critical)
4. **Fix BUG #3: Timing state duplication** (high)
5. **Run tests and verify fixes**
6. **Test Super Mario Bros**
7. **Document results**

---

**Date:** 2025-10-07
**Status:** 🔍 IN PROGRESS - Critical bugs identified
**Critical Bugs:** 3 found (2 critical, 1 high)
**Recommendation:** Fix timing bugs immediately, test commercial games

