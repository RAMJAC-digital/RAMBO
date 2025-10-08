# Timing Architecture Audit & Refactoring Plan (2025-10-07)

## Executive Summary

**Current State:** CRITICALLY BROKEN - Nested clocking violates hardware reality
**Impact:** PPU runs at 2× speed, frame timing wrong, commercial games fail
**Required Action:** Complete timing architecture refactoring

---

## Critical Architectural Problems

### Problem #1: Nested Clock Advancement

**Hardware Reality:**
- NES has ONE 21.477272 MHz crystal oscillator (NTSC)
- CPU divider ÷12 → 1.789773 MHz
- PPU divider ÷4 → 5.369318 MHz
- Components are **physically separate**, clocked externally

**Current Implementation (WRONG):**
```zig
// EmulationState.tick() - Line 653
self.clock.ppu_cycles += 1;  // ← Master clock advances

// Then calls:
self.tickPpu();
    → PpuRuntime.tick(&self.ppu, &self.ppu_timing, ...)
        → timing.dot += 1;  // ← PPU ALSO advances timing!
```

**Result:** PPU clock advances TWICE per tick → 2× speed → BROKEN

---

### Problem #2: Component-Owned Timing State

**Current State:**
```zig
CpuState {
    cycle_count: u64,  // ← CPU owns timing
}

PpuState {
    // No timing (correct)
}

EmulationState {
    clock: Clock { ppu_cycles: u64 },     // ← Master clock
    ppu_timing: Timing { scanline, dot, frame },  // ← Duplicate timing
}
```

**Issues:**
- CPU state contains timing (`cycle_count`)
- Two separate PPU timing structures (`clock` and `ppu_timing`)
- No single source of truth
- Components mutate their own timing

**Hardware Reality:**
- Components have NO clocks
- External oscillator drives everything
- State and timing are separate

---

### Problem #3: Tight Coupling via Nested Ticks

**Current Call Chain:**
```
EmulationState.tick()
  └→ tickPpu()
      └→ PpuRuntime.tick(timing)  // ← Mutates timing!
  └→ tickCpu()
      └→ Mutates cpu.cycle_count
  └→ tickDma()
      └→ Mutates cpu.cycle_count  // ← Correct (cycles pass during DMA)
  └→ tickApu()
```

**Problem:** Components reach into each other's timing state

---

## Timing Mutations Audit

### All Clock Advancement Points

**File: src/emulation/State.zig**

1. **Line 647:** `self.clock.ppu_cycles += 2` (odd frame skip)
2. **Line 653:** `self.clock.ppu_cycles += 1` (master clock)
3. **Line 1048:** `self.cpu.cycle_count += 1` (CPU tick)
4. **Line 1614:** `self.cpu.cycle_count += 1` (OAM DMA)
5. **Line 1664:** `self.cpu.cycle_count += 1` (DMC DMA)

**File: src/emulation/Ppu.zig**

6. **Line 50:** `timing.dot += 1` (PPU timing advance)
7. **Line 51-58:** Scanline/frame wrapping logic

**Total:** 7 separate timing mutation points → TOO MANY

---

## Hardware Research: nesdev.org Specifications

### Timing Specifications

**NTSC (RP2A03 + RP2C02):**
- Master clock: 21.477272 MHz
- CPU clock: 21.477272 MHz ÷ 12 = 1.789773 MHz
- PPU clock: 21.477272 MHz ÷ 4 = 5.369318 MHz
- **Ratio: 3 PPU cycles per 1 CPU cycle**

**Frame Timing:**
- 341 dots per scanline
- 262 scanlines per frame (0-261)
- 341 × 262 = 89,342 PPU cycles per frame (even frames)
- Odd frames with rendering: Skip dot 0 of scanline 0 → 89,341 cycles

**CPU Cycles per Frame:**
- 89,342 PPU cycles ÷ 3 = 29,780.67 CPU cycles
- (The 0.67 accumulates → every 3rd frame has 1 extra CPU cycle)

### Component Interaction Timing

**PPU → CPU (NMI):**
- PPU sets NMI flag at scanline 241, dot 1
- CPU checks NMI at start of next instruction
- No instant interrupt (instruction finishes first)

**CPU → PPU (Registers):**
- Writes to $2000-$2007 affect PPU immediately
- Some effects delayed to next scanline/frame

**OAM DMA:**
- CPU halted for 513-514 cycles
- PPU continues running
- DMA controller uses CPU bus (reads RAM, writes $2004)

**DMC DMA (2A03 only):**
- CPU stalled via RDY line for 4 cycles
- PPU continues running
- CPU repeats last read (corruption on NTSC)

### Tick Ordering (No Specified Hardware Order)

**From nesdev.org:**
- Components run **in parallel** on hardware
- No sequential tick order exists
- Synchronization via bus access only
- Our emulator must choose an order

**Safe Sequential Order:**
1. **PPU first:** Updates address (A12), sets flags (NMI, sprite 0)
2. **CPU second:** Sees updated PPU state, executes
3. **APU last:** Less critical, synchronized with CPU

**Rationale:**
- PPU state updates need to be visible before CPU reads $2002
- Mapper IRQ (MMC3) triggered by PPU A12 transitions
- CPU NMI check happens at instruction boundaries

---

## Proposed New Architecture

### Master Clock (External, Controllable)

**Single Source of Truth:**
```zig
pub const MasterClock = struct {
    /// Total PPU cycles elapsed since power-on
    /// This is the ONLY timing counter - all other timing is derived
    ppu_cycles: u64 = 0,

    /// Speed control multiplier (1.0 = normal, 2.0 = 2× speed, etc.)
    speed_multiplier: f64 = 1.0,

    /// Advance clock by N PPU cycles (externally controlled)
    pub fn advance(self: *MasterClock, cycles: u64) void {
        self.ppu_cycles += cycles;
    }

    /// Derive current scanline from master clock
    pub fn scanline(self: MasterClock) u16 {
        return @intCast((self.ppu_cycles / 341) % 262);
    }

    /// Derive current dot from master clock
    pub fn dot(self: MasterClock) u16 {
        return @intCast(self.ppu_cycles % 341);
    }

    /// Derive current frame number
    pub fn frame(self: MasterClock) u64 {
        return self.ppu_cycles / 89342;  // Approximate
    }

    /// Derive CPU cycles (1 CPU = 3 PPU)
    pub fn cpuCycles(self: MasterClock) u64 {
        return self.ppu_cycles / 3;
    }

    /// Check if current cycle is a CPU tick
    pub fn isCpuTick(self: MasterClock) bool {
        return (self.ppu_cycles % 3) == 0;
    }
};
```

### Pure Component Ticks (No Timing Mutation)

**PPU Tick (Pure):**
```zig
// src/ppu/Logic.zig
pub fn tick(
    state: *PpuState,
    scanline: u16,
    dot: u16,
    cart: ?*AnyCartridge,
    framebuffer: ?[]u32,
) TickFlags {
    // NO timing advancement - timing passed as read-only parameters
    // Pure state update based on current scanline/dot

    const is_visible = scanline < 240;
    const is_prerender = scanline == 261;

    // Background rendering
    if (is_visible or is_prerender) {
        if (dot >= 1 and dot <= 256) {
            state.bg_state.shift();
        }
        // ... rest of PPU logic
    }

    // VBlank flag
    if (scanline == 241 and dot == 1) {
        state.status.vblank = true;
        if (state.ctrl.nmi_enable) {
            state.nmi_occurred = true;
        }
    }

    return .{
        .frame_complete = (scanline == 261 and dot == 340),
        .rendering_enabled = state.mask.renderingEnabled(),
    };
}
```

**CPU Tick (Pure):**
```zig
// src/cpu/Logic.zig
pub fn tick(
    cpu: *CpuState,
    bus: *BusState,
    // NO cycle_count mutation
) void {
    // Pure instruction execution
    // Timing tracked externally
}
```

**Remove from CpuState:**
```zig
pub const CpuState = struct {
    // Remove: cycle_count: u64,  // ← TIMING REMOVED

    // Keep: Pure CPU state only
    a: u8,
    x: u8,
    y: u8,
    sp: u8,
    pc: u16,
    p: StatusRegister,
    // ... instruction state
};
```

### EmulationState (Externally Clocked)

```zig
pub const EmulationState = struct {
    /// Master clock (ONLY timing source)
    clock: MasterClock,

    /// Pure component states (NO timing)
    cpu: CpuState,
    ppu: PpuState,
    apu: ApuState,
    bus: BusState,
    controller: ControllerState,
    oam_dma: OamDmaState,  // ← Renamed from 'dma'
    dmc_dma: DmcDmaState,

    // Remove: ppu_timing (redundant)

    /// Advance emulation by 1 PPU cycle
    /// Called by external thread, fully controllable
    pub fn tick(self: *EmulationState) void {
        // 1. Advance master clock (SINGLE POINT)
        self.clock.advance(1);

        // 2. Derive timing
        const scanline = self.clock.scanline();
        const dot = self.clock.dot();
        const is_cpu_tick = self.clock.isCpuTick();

        // 3. Tick components (NO timing mutation)
        // PPU ticks every cycle
        const ppu_flags = PpuLogic.tick(
            &self.ppu,
            scanline,
            dot,
            self.cartPtr(),
            self.framebuffer,
        );

        self.frame_complete = ppu_flags.frame_complete;

        // CPU ticks every 3rd cycle
        if (is_cpu_tick) {
            if (self.oam_dma.active) {
                self.tickOamDma();  // ← Renamed
            } else if (self.dmc_dma.rdy_low) {
                self.tickDmcDma();
            } else {
                CpuLogic.tick(&self.cpu, &self.bus);
            }
        }

        // APU ticks with CPU
        if (is_cpu_tick) {
            ApuLogic.tick(&self.apu);
        }
    }

    /// Get current CPU cycle count (derived)
    pub fn cpuCycles(self: *EmulationState) u64 {
        return self.clock.cpuCycles();
    }
};
```

---

## Odd Frame Skip Handling

**Hardware Behavior:**
- On odd frames with rendering enabled
- Skip dot 0 of scanline 0
- Results in 89,341 PPU cycles instead of 89,342

**New Implementation (Master Clock Level):**
```zig
pub fn tick(self: *EmulationState) void {
    const current_scanline = self.clock.scanline();
    const current_dot = self.clock.dot();

    // Check for odd frame skip BEFORE advancing
    const is_odd_frame = (self.clock.frame() & 1) == 1;
    const should_skip = is_odd_frame and
                       self.ppu.mask.renderingEnabled() and
                       current_scanline == 261 and
                       current_dot == 340;

    if (should_skip) {
        // Advance by 2 cycles: normal advance + skip dot 0
        self.clock.advance(2);
    } else {
        // Normal advance
        self.clock.advance(1);
    }

    // Continue with component ticks...
}
```

---

## Refactoring Plan

### Phase 1: Create MasterClock (Non-Breaking)

**Tasks:**
1. Create `src/emulation/MasterClock.zig`
2. Implement timing derivation functions
3. Add unit tests for derivation correctness
4. Document hardware correspondence

**Tests:**
```zig
test "MasterClock: scanline/dot derivation" {
    var clock = MasterClock{};

    // Scanline 0, dot 0
    try testing.expectEqual(@as(u16, 0), clock.scanline());
    try testing.expectEqual(@as(u16, 0), clock.dot());

    // Advance to dot 340
    clock.advance(340);
    try testing.expectEqual(@as(u16, 0), clock.scanline());
    try testing.expectEqual(@as(u16, 340), clock.dot());

    // Advance to scanline 1, dot 0
    clock.advance(1);
    try testing.expectEqual(@as(u16, 1), clock.scanline());
    try testing.expectEqual(@as(u16, 0), clock.dot());
}

test "MasterClock: CPU cycle ratio" {
    var clock = MasterClock{};

    clock.advance(3);
    try testing.expectEqual(@as(u64, 1), clock.cpuCycles());

    clock.advance(3);
    try testing.expectEqual(@as(u64, 2), clock.cpuCycles());
}
```

**Deliverable:** Working MasterClock with tests, no emulator changes yet

---

### Phase 2: Decouple PPU Timing

**Tasks:**
1. Modify `PpuLogic.tick()` to accept scanline/dot as parameters
2. Remove `timing.dot += 1` from Ppu.zig
3. Remove `ppu_timing` from EmulationState
4. Update EmulationState.tick() to pass derived timing

**Changes:**
```zig
// OLD (src/emulation/Ppu.zig)
pub fn tick(
    state: *PpuState,
    timing: *Timing,  // ← Mutable timing
    ...
) {
    timing.dot += 1;  // ← REMOVE THIS
}

// NEW
pub fn tick(
    state: *PpuState,
    scanline: u16,     // ← Read-only
    dot: u16,          // ← Read-only
    ...
) {
    // No timing mutation
}
```

**Test Update:**
- PPU tests that relied on timing state need scanline/dot passed explicitly
- Frame boundary tests use master clock

**Deliverable:** PPU decoupled from timing, tests passing

---

### Phase 3: Decouple CPU Timing

**Tasks:**
1. Remove `cycle_count` from CpuState
2. Update `tickCpu()` to not mutate timing
3. Update warm-up check to use `clock.cpuCycles()` instead of `cpu.cycle_count`
4. Update tests

**Changes:**
```zig
// OLD
pub const CpuState = struct {
    cycle_count: u64,  // ← REMOVE
    ...
};

pub fn tickCpu(self: *EmulationState) void {
    self.cpu.cycle_count += 1;  // ← REMOVE

    // Warm-up check
    if (!self.ppu.warmup_complete and self.cpu.cycle_count >= 29658) {
        // ↑ WRONG - uses CPU state
    }
}

// NEW
pub fn tick(self: *EmulationState) void {
    // Warm-up check using master clock
    if (!self.ppu.warmup_complete and self.clock.cpuCycles() >= 29658) {
        self.ppu.warmup_complete = true;
    }
}
```

**Deliverable:** CPU decoupled from timing, tests passing

---

### Phase 4: Rename DMA for Clarity

**Tasks:**
1. Rename `dma` → `oam_dma` throughout codebase
2. Rename `tickDma()` → `tickOamDma()`
3. Update all references
4. Update tests
5. Update documentation

**Rationale:**
- Clarifies OAM DMA vs DMC DMA
- Prevents confusion
- More descriptive naming

**Deliverable:** Clear DMA naming, no functional changes

---

### Phase 5: Integrate MasterClock

**Tasks:**
1. Replace `EmulationState.clock` with `MasterClock`
2. Remove `ppu_cycles` counter (use MasterClock)
3. Update all tick functions to use master clock
4. Implement odd frame skip at master clock level
5. Update all tests

**Changes:**
```zig
pub const EmulationState = struct {
    clock: MasterClock,  // ← New
    // Remove: ppu_timing
    // Remove: old Clock struct

    pub fn tick(self: *EmulationState) void {
        // Handle odd frame skip
        // ... (see architecture above)

        // Advance master clock
        self.clock.advance(skip ? 2 : 1);

        // Tick components with derived timing
        // ...
    }
};
```

**Deliverable:** Unified timing architecture, single clock source

---

### Phase 6: Add Commercial ROM Tests

**Tasks:**
1. Create `test_roms/` directory (gitignored)
2. Add optional commercial ROM tests
3. Document ROM requirements (MD5 hashes)
4. Test Super Mario Bros frame timing
5. Test Burger Time frame timing

**Tests:**
```zig
test "Super Mario Bros: Frame timing accuracy" {
    const rom_path = "test_roms/smb.nes";

    const rom_data = std.fs.cwd().readFileAlloc(allocator, rom_path)
        catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("Skipping: SMB ROM not found\n", .{});
                return error.SkipZigTest;
            }
            return err;
        };
    defer allocator.free(rom_data);

    var state = try EmulationState.loadRom(allocator, rom_data);
    defer state.deinit();

    // Run first frame
    const start = state.clock.ppu_cycles;
    state.emulateFrame();
    const elapsed = state.clock.ppu_cycles - start;

    // First frame is even, should be exactly 89,342 cycles
    try testing.expectEqual(@as(u64, 89342), elapsed);
}
```

**Documentation:**
```markdown
# test_roms/README.md

## Commercial ROM Tests

These tests verify emulation accuracy against real NES games.
ROMs are NOT included (copyright). Obtain legally and place here.

### Required ROMs

**Super Mario Bros (USA)**
- File: `smb.nes`
- MD5: `811b027eaf99c2def7b933c5208636de`
- Mapper: 0 (NROM)
- Size: 40 KB (32 KB PRG + 8 KB CHR)

**Burger Time (USA)**
- File: `burgertime.nes`
- MD5: `...`
- Mapper: 0 (NROM)
- Size: 40 KB

Tests skip gracefully if ROMs not found.
```

**Deliverable:** Commercial ROM test framework, optional execution

---

### Phase 7: Open Bus Audit

**Tasks:**
1. Verify CPU open bus behavior (unmapped reads)
2. Verify PPU open bus behavior ($2007 reads)
3. Verify decay timing (if implemented)
4. Add open bus tests
5. Fix any issues found

**Questions to Answer:**
- Does CPU open bus update on ALL bus operations?
- Does PPU open bus update correctly on $2007?
- Are there any missing open bus behaviors?

**Deliverable:** Open bus behavior verified and tested

---

## Expected Test Impact

**Phase 1:** No test failures (additive only)
**Phase 2:** 10-20 PPU test failures (timing parameter changes)
**Phase 3:** 5-10 CPU test failures (cycle_count removal)
**Phase 4:** 0 test failures (rename only)
**Phase 5:** 50-100 test failures (major architecture change)
**Phase 6:** 0 failures (new optional tests)
**Phase 7:** 0-5 failures (audit findings)

**Total Expected Failures:** 65-135 tests temporarily broken
**Strategy:** Update tests incrementally, verify correctness at each phase

---

## Success Criteria

### Timing Accuracy
- ✅ Single master clock, externally controlled
- ✅ Frame length: 89,342 cycles (even), 89,341 (odd with rendering)
- ✅ CPU/PPU ratio: Exactly 1:3
- ✅ No nested clock advancement
- ✅ All timing derived from master clock

### Component Decoupling
- ✅ Component ticks are pure (no timing mutation)
- ✅ Timing passed as read-only parameters
- ✅ Components can be ticked independently
- ✅ No cross-component timing dependencies

### Commercial ROM Compatibility
- ✅ Super Mario Bros renders correctly
- ✅ Burger Time renders correctly
- ✅ Frame timing matches hardware
- ✅ VBlank timing correct

### Code Quality
- ✅ Clear, documented architecture
- ✅ Hardware correspondence explained
- ✅ No redundant timing structures
- ✅ Descriptive naming (oam_dma vs dma)

---

## Timeline Estimate

**Phase 1:** 2-3 hours (MasterClock creation + tests)
**Phase 2:** 3-4 hours (PPU decoupling + test updates)
**Phase 3:** 2-3 hours (CPU decoupling + test updates)
**Phase 4:** 1-2 hours (DMA rename)
**Phase 5:** 4-6 hours (Integration + major test updates)
**Phase 6:** 2-3 hours (Commercial ROM tests)
**Phase 7:** 2-3 hours (Open bus audit)

**Total:** 16-24 hours of systematic refactoring

---

## Risk Mitigation

**Risk:** Breaking AccuracyCoin
**Mitigation:** Run after each phase, halt if broken

**Risk:** Cascading test failures
**Mitigation:** Fix incrementally, document expected failures

**Risk:** Subtle timing bugs introduced
**Mitigation:** Frame cycle count tests, commercial ROM verification

**Risk:** Performance regression
**Mitigation:** Profile before/after, ensure no slowdown

---

## Ready to Proceed

**Phase 1: Create MasterClock** - Ready to implement
- Non-breaking, additive only
- Clear hardware mapping
- Well-defined tests

**Shall I proceed with Phase 1?**

---

**Date:** 2025-10-07
**Status:** 📋 PLAN COMPLETE - Awaiting approval
**Estimated Work:** 16-24 hours over 2-3 days
**Confidence:** HIGH - Clear path, well-researched

