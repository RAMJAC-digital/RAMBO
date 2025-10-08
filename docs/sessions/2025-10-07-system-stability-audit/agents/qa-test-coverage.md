# Comprehensive Test Coverage Analysis - RAMBO NES Emulator

**Date:** 2025-10-07
**Scope:** Full system test coverage audit against nesdev.org hardware specifications
**Test Count:** 778 test cases across 53 test files (~16,078 lines)
**ROM Library:** 185 commercial test ROMs available in tests/data/

---

## Executive Summary

### Overall Assessment: 🟡 GOOD with Critical Gaps

**Test Coverage Distribution:**
- ✅ **CPU:** Excellent (280+ tests, 100% opcode coverage, cycle-accurate timing)
- ✅ **PPU Sprites:** Excellent (73 tests, hardware-accurate rendering pipeline)
- 🟡 **PPU Background:** Good (6+ tests, missing timing edge cases)
- 🟡 **APU:** Good (135 tests, missing integration validation)
- ⚠️ **Bus/Memory:** Adequate (20 tests, missing hardware quirks)
- 🔴 **End-to-End:** Poor (3 integration tests, NO framebuffer validation)
- 🔴 **Hardware Compliance:** Poor (5 nesdev.org references, missing spec tests)
- 🔴 **Commercial ROMs:** Critical Gap (185 ROMs available, ZERO tested beyond load)

### Critical Findings

**CRITICAL PRIORITY (P0):**
1. ❌ **NO framebuffer validation tests** - PPU renders but output never verified
2. ❌ **NO commercial ROM visual regression tests** - Games load but rendering not validated
3. ❌ **NO PPU warm-up period tests** - Critical 29,658-cycle hardware behavior untested
4. ❌ **NO NMI timing race condition tests** - VBlank flag race window (241.0-241.1) untested
5. ❌ **NO rendering enable/disable transition tests** - PPUMASK state changes untested

**HIGH PRIORITY (P1):**
6. ⚠️ **Minimal nesdev.org spec compliance** - Only 5 references across entire test suite
7. ⚠️ **Missing PPU register timing tests** - $2002/$2007 read timing edge cases
8. ⚠️ **No PPUSTATUS read suppression tests** - Reading $2002 during VBlank set (241.1) untested
9. ⚠️ **Missing integration tests** - CPU-PPU-Bus-Cartridge pipeline never validated end-to-end
10. ⚠️ **22 TODO stubs in input_integration_test.zig** - Input system not integration tested

---

## 1. Test Coverage Gaps by Component

### 1.1 CPU (src/cpu/) - ✅ EXCELLENT

**Coverage:** ~280 tests across 10 test files

**Strengths:**
- ✅ All 256 opcodes tested (151 official + 105 unofficial)
- ✅ Cycle-accurate timing validation (page crossing, dummy reads)
- ✅ Read-Modify-Write (RMW) dummy write behavior verified
- ✅ NMI edge detection tested
- ✅ Power-on vs RESET behavior differentiated
- ✅ Zero-page wrapping verified
- ✅ Open bus behavior tested

**Test Files:**
```
tests/cpu/
├── instructions_test.zig          # Core instruction tests
├── rmw_test.zig                    # RMW dummy write verification
├── page_crossing_test.zig          # Timing edge cases
├── opcodes/arithmetic_test.zig     # ADC/SBC with all flags
├── opcodes/unofficial_test.zig     # All 105 unofficial opcodes
└── diagnostics/timing_trace_test.zig  # Cycle-by-cycle traces
```

**Gaps Identified:**
- ⚠️ **CPU timing deviation acknowledged but not regression-tested** (CLAUDE.md line 392)
  - Absolute,X/Y reads without page crossing: +1 cycle deviation from hardware
  - No test to prevent future timing regressions

**nesdev.org Compliance:**
- ✅ References nesdev.org/wiki/CPU in documentation
- ❌ No explicit "per nesdev.org spec" assertions in test code

---

### 1.2 PPU Background (src/ppu/) - 🟡 GOOD with Timing Gaps

**Coverage:** 6 tests in chr_integration_test.zig + integration tests

**Strengths:**
- ✅ CHR ROM/RAM access tested
- ✅ Nametable mirroring (horizontal/vertical) verified
- ✅ PPUDATA buffered reads tested
- ✅ Background tile fetching implemented
- ✅ Scroll management tested

**Test Files:**
```
tests/ppu/
└── chr_integration_test.zig        # 6 tests (CHR, mirroring, PPUDATA)

tests/integration/
├── cpu_ppu_integration_test.zig    # 20 tests (registers, NMI, DMA)
└── vblank_wait_test.zig            # 1 test (VBlank polling)
```

**Critical Gaps:**

#### 1.2.1 PPU Warm-Up Period (CRITICAL - P0)
**nesdev.org Reference:** https://www.nesdev.org/wiki/PPU_power_up_state

**Missing Tests:**
```zig
// ❌ NOT TESTED: PPU warm-up period (first 29,658 CPU cycles)
test "PPU Warm-up: PPUCTRL writes ignored during warm-up" {
    // Hardware: Writes to $2000 ignored for ~29,658 cycles after power-on
    // Implementation: src/ppu/Logic.zig:280-281 (warmup_complete check)
    // Risk: Games fail if warm-up not implemented (Mario 1, Burger Time)
}

test "PPU Warm-up: PPUMASK writes ignored during warm-up" {
    // Hardware: Writes to $2001 ignored during warm-up period
    // Implementation: src/ppu/Logic.zig:290-291
}

test "PPU Warm-up: PPUSCROLL writes ignored during warm-up" {
    // Hardware: Writes to $2005 ignored during warm-up period
    // Implementation: src/ppu/Logic.zig:311-312
}

test "PPU Warm-up: PPUADDR writes ignored during warm-up" {
    // Hardware: Writes to $2006 ignored during warm-up period
    // Implementation: src/ppu/Logic.zig:326-327
}

test "PPU Warm-up: Period completes after 29658 CPU cycles" {
    // Hardware: warmup_complete flag set after exact cycle count
    // Implementation: Needs verification in EmulationState
}

test "PPU Warm-up: RESET skips warm-up period" {
    // Hardware: RESET (not power-on) bypasses warm-up
    // Implementation: src/ppu/Logic.zig:30
}
```

**Impact:** CRITICAL - Documented fix (CLAUDE.md lines 53-94) but NO regression tests added

---

#### 1.2.2 Rendering Enable/Disable Transitions (CRITICAL - P0)
**nesdev.org Reference:** https://www.nesdev.org/wiki/PPU_rendering

**Missing Tests:**
```zig
// ❌ NOT TESTED: Rendering state transitions
test "PPU Rendering: Enable rendering mid-frame" {
    // Hardware: Setting PPUMASK bits 3/4 during rendering affects pipeline
    // Current Issue: Games stuck with PPUMASK=$00 (CLAUDE.md line 117)
}

test "PPU Rendering: Disable rendering mid-frame" {
    // Hardware: Clearing PPUMASK bits 3/4 stops fetching immediately
}

test "PPU Rendering: Enable BG only (sprites disabled)" {
    // Hardware: PPUMASK.3=1, PPUMASK.4=0
    // Framebuffer validation: Only background pixels rendered
}

test "PPU Rendering: Enable sprites only (BG disabled)" {
    // Hardware: PPUMASK.3=0, PPUMASK.4=1
    // Framebuffer validation: Only sprite pixels rendered
}

test "PPU Rendering: Leftmost 8 pixels clipping" {
    // Hardware: PPUMASK bits 1/2 control left column visibility
    // nesdev.org: https://www.nesdev.org/wiki/PPU_registers#PPUMASK
}
```

**Impact:** CRITICAL - Current issue blocking game playability (CLAUDE.md line 117)

---

#### 1.2.3 VBlank and NMI Timing Edge Cases (CRITICAL - P0)
**nesdev.org Reference:** https://www.nesdev.org/wiki/PPU_frame_timing#VBlank_Flag

**Missing Tests:**
```zig
// ❌ NOT TESTED: VBlank flag race conditions
test "PPU VBlank: Reading $2002 at scanline 241 dot 0" {
    // Hardware: VBlank not yet set (set at 241.1)
    // Expected: Returns VBlank=0, prevents NMI
    // nesdev.org: "VBlank is set at dot 1, not dot 0"
}

test "PPU VBlank: Reading $2002 at scanline 241 dot 1" {
    // Hardware: Reading during VBlank SET suppresses NMI
    // Expected: Returns VBlank=1, clears flag, NMI never fires
    // nesdev.org: "Reading one PPU clock before VBlank suppresses NMI"
}

test "PPU VBlank: Reading $2002 at scanline 241 dot 2" {
    // Hardware: VBlank already set and cleared by read
    // Expected: Returns VBlank=1, NMI already triggered
}

test "PPU VBlank: NMI suppression window (241.0 to 241.1)" {
    // Hardware: Reading $2002 in critical 1-dot window prevents NMI
    // Implementation: EmulationState needs to track read timing
}

test "PPU VBlank: Clear timing at scanline 261 dot 1" {
    // Hardware: VBlank flag cleared at pre-render scanline
    // Current Test: None (documented at PPU-HARDWARE-ACCURACY-AUDIT.md:101)
}
```

**Existing Partial Coverage:**
```zig
// tests/integration/cpu_ppu_integration_test.zig:118-138
test "CPU-PPU Integration: VBlank flag race condition (read during setting)" {
    // ⚠️ INSUFFICIENT: Sets VBlank manually, doesn't test cycle-accurate timing
    // Missing: Actual scanline 241 dot 0/1 transition testing
}
```

**Impact:** CRITICAL - VBlank timing bugs can cause NMI loss or spurious NMIs

---

#### 1.2.4 Frame Timing and Odd Frame Skip (HIGH - P1)
**nesdev.org Reference:** https://www.nesdev.org/wiki/PPU_frame_timing#Odd/Even_Frames

**Missing Tests:**
```zig
// ❌ NOT TESTED: Odd frame skip behavior
test "PPU Timing: Odd frame skips dot 0 of scanline 0" {
    // Hardware: When rendering enabled, odd frames skip 0.0 (jump 261.340→0.1)
    // Implementation: Documented at PPU-HARDWARE-ACCURACY-AUDIT.md:149
    // Result: Frame is 1 cycle shorter (89,341 vs 89,342)
}

test "PPU Timing: Even frame does not skip" {
    // Hardware: Even frames run full 89,342 cycles
}

test "PPU Timing: Odd frame skip only when rendering enabled" {
    // Hardware: Skip only occurs if PPUMASK bits 3 or 4 set
    // If rendering disabled, all frames are 89,342 cycles
}
```

**Impact:** HIGH - Affects timing accuracy for TAS playback and synchronization

---

#### 1.2.5 PPUSTATUS ($2002) Read Behavior (HIGH - P1)
**nesdev.org Reference:** https://www.nesdev.org/wiki/PPU_registers#PPUSTATUS

**Missing Tests:**
```zig
// ❌ NOT TESTED: PPUSTATUS read side effects
test "PPU Registers: PPUSTATUS clears w toggle on read" {
    // Hardware: Reading $2002 resets PPUADDR/PPUSCROLL write latch
    // Current Test: Partial coverage in cpu_ppu_integration_test.zig:180-200
    // Gap: No test for w toggle state during rendering
}

test "PPU Registers: PPUSTATUS open bus bits 0-4" {
    // Hardware: Bits 0-4 return PPU open bus value
    // Implementation: src/ppu/State.zig:98 (open_bus field)
}

test "PPU Registers: PPUSTATUS does not update CPU open bus" {
    // Hardware: Reading $2002 updates only PPU open bus, not CPU bus
    // Current: No test validates this distinction
}
```

---

### 1.3 PPU Sprites (src/ppu/) - ✅ EXCELLENT

**Coverage:** 73 tests across 3 test files

**Strengths:**
- ✅ Complete sprite evaluation pipeline (cycles 1-256)
- ✅ Sprite fetching logic (cycles 257-320)
- ✅ 8×8 and 8×16 sprite modes
- ✅ Sprite 0 hit detection
- ✅ Sprite overflow flag
- ✅ Priority system (BG vs sprite)
- ✅ Edge cases (256+ sprites, Y=0xFF, partial sprites)

**Test Files:**
```
tests/ppu/
├── sprite_evaluation_test.zig      # 15 tests (evaluation algorithm)
├── sprite_rendering_test.zig       # 23 tests (pattern fetching, rendering)
└── sprite_edge_cases_test.zig      # 35 tests (overflow, sprite 0, edge cases)
```

**Gaps Identified:**
- ⚠️ **No sprite DMA timing tests** (OAM DMA at $4014)
  - Current: OAM DMA tested separately (oam_dma_test.zig)
  - Gap: No integration with sprite rendering pipeline

**nesdev.org Compliance:**
- ✅ References nesdev.org in sprite_rendering_test.zig:3-4
- ✅ Hardware-accurate sprite evaluation per nesdev.org spec

---

### 1.4 APU (src/apu/) - 🟡 GOOD with Integration Gaps

**Coverage:** 135 tests across 8 test files

**Strengths:**
- ✅ Frame counter (4-step/5-step modes)
- ✅ DMC channel (DMA, IRQ, sample playback)
- ✅ Envelopes (volume control)
- ✅ Length counters (channel silencing)
- ✅ Sweep units (frequency modulation)
- ✅ Linear counter (triangle channel)
- ✅ Frame IRQ edge cases
- ✅ Open bus behavior

**Test Files:**
```
tests/apu/
├── apu_test.zig                    # 8 tests (frame counter)
├── dmc_test.zig                    # 25 tests (DMC channel)
├── envelope_test.zig               # 20 tests (envelopes)
├── length_counter_test.zig         # 25 tests (length counters)
├── linear_counter_test.zig         # 15 tests (linear counter)
├── sweep_test.zig                  # 25 tests (sweep units)
├── frame_irq_edge_test.zig         # 11 tests (IRQ edge cases)
└── open_bus_test.zig               # 8 tests (register reads)
```

**Critical Gaps:**

#### 1.4.1 APU-CPU Integration (HIGH - P1)
```zig
// ❌ NOT TESTED: APU IRQ integration with CPU
test "APU Integration: Frame IRQ triggers CPU IRQ line" {
    // Hardware: APU frame IRQ asserts CPU IRQ pin
    // Implementation: EmulationState.tick() needs validation
}

test "APU Integration: DMC IRQ triggers CPU IRQ line" {
    // Hardware: DMC IRQ asserts CPU IRQ pin when sample buffer empty
}

test "APU Integration: IRQ acknowledge via $4015 read" {
    // Hardware: Reading $4015 clears frame IRQ flag
}
```

#### 1.4.2 APU Waveform Generation (MISSING - P2)
```zig
// ❌ NOT IMPLEMENTED: Waveform generation (Milestone 7)
test "APU Waveform: Pulse channel square wave output" {
    // Hardware: Duty cycle 0-3 generates different waveforms
    // Status: Planned for Phase 9+ (CLAUDE.md line 306)
}

test "APU Waveform: Triangle channel linear output" {
    // Hardware: 32-step triangle wave
}

test "APU Waveform: Noise channel pseudo-random" {
    // Hardware: 15-bit LFSR generates white noise
}

test "APU Waveform: DMC channel delta modulation" {
    // Hardware: 7-bit counter with delta updates
}
```

**Impact:** MEDIUM - APU state machines complete, waveform output deferred to Phase 9+

---

### 1.5 Bus & Memory (src/emulation/State.zig) - ⚠️ ADEQUATE with Quirk Gaps

**Coverage:** ~20 tests (17 in tests/bus/ + 3 embedded)

**Strengths:**
- ✅ RAM mirroring ($0000-$1FFF mirrors 2KB)
- ✅ Open bus tracking
- ✅ ROM write protection
- ✅ PPU register routing ($2000-$2007)
- ✅ Controller I/O ($4016/$4017)

**Test Files:**
```
tests/bus/
└── bus_integration_test.zig        # 17 tests

tests/cpu/
└── bus_integration_test.zig        # CPU-specific bus tests
```

**Critical Gaps:**

#### 1.5.1 Open Bus Decay (MEDIUM - P1)
**nesdev.org Reference:** https://www.nesdev.org/wiki/Open_bus_behavior

**Missing Tests:**
```zig
// ❌ NOT TESTED: Open bus decay timing
test "Bus: Open bus decays over time" {
    // Hardware: Open bus value decays to 0 after ~600ms (variable)
    // Implementation: BusState has open_bus field but no decay timer
    // nesdev.org: "Open bus is not stable indefinitely"
}

test "Bus: Open bus updated on every bus access" {
    // Hardware: Each read/write updates the bus latch
    // Current: Partial coverage, no comprehensive test
}
```

#### 1.5.2 Special Read Behaviors (MEDIUM - P1)
```zig
// ❌ NOT TESTED: Bus read edge cases
test "Bus: Read from write-only register returns open bus" {
    // Hardware: PPUCTRL ($2000) read returns open bus
    // Current Test: cpu_ppu_integration_test.zig:192-194 (partial)
}

test "Bus: Simultaneous CPU and PPU bus access" {
    // Hardware: PPU has separate bus, no contention with CPU
    // Current: Architecturally separated, but not tested
}
```

---

### 1.6 Cartridge & Mappers (src/cartridge/) - 🟡 GOOD for Mapper 0

**Coverage:** 47 tests (2 loader + 45 registry)

**Strengths:**
- ✅ iNES format parsing
- ✅ Mapper 0 (NROM) fully tested
- ✅ AnyCartridge tagged union dispatch
- ✅ IRQ infrastructure (A12 edge detection)
- ✅ CHR ROM/RAM switching
- ✅ Mirroring mode parsing

**Test Files:**
```
tests/cartridge/
├── accuracycoin_test.zig           # 2 tests (ROM loading)
└── prg_ram_test.zig                # 3 tests (PRG RAM writes)

tests/comptime/
└── poc_mapper_generics.zig         # 45 tests (mapper dispatch)
```

**Critical Gaps:**

#### 1.6.1 Mapper Expansion (PLANNED - P2)
```zig
// ⬜ NOT IMPLEMENTED: Mappers 1-4 (CLAUDE.md line 268-279)
test "Mapper 1 (MMC1): Bank switching" {
    // Status: Planned for next phase (14-19 days estimated)
    // Coverage: Would add 28% of NES library
}

test "Mapper 2 (UxROM): Simple bank switching" {
    // Coverage: +11% of NES library
}

test "Mapper 3 (CNROM): CHR banking only" {
    // Coverage: +6% of NES library
}

test "Mapper 4 (MMC3): IRQ counter and banking" {
    // Coverage: +25% of NES library
    // Most complex mapper, requires scanline counter
}
```

**Impact:** MEDIUM - Mapper 0 covers ~5% of games, expansion needed for broader compatibility

---

### 1.7 Controller I/O (src/emulation/State.zig) - ✅ EXCELLENT

**Coverage:** 14 tests in controller_test.zig + 40 input system tests

**Strengths:**
- ✅ 4021 shift register emulation (hardware-accurate)
- ✅ Strobe protocol (latch on rising edge)
- ✅ Button order verification
- ✅ Shift register fill behavior (1s after 8 reads)
- ✅ Dual controller support
- ✅ Mailbox integration (thread-safe input)

**Test Files:**
```
tests/integration/
└── controller_test.zig             # 14 tests (hardware-accurate protocol)

tests/input/
├── button_state_test.zig           # 21 tests (unified button state)
└── keyboard_mapper_test.zig        # 20 tests (keyboard → button mapping)
```

**Gaps Identified:**
- ⚠️ **22 TODO stubs in input_integration_test.zig** (CLAUDE.md line 408)
  - All scaffolded but not implemented
  - End-to-end input path never tested

---

### 1.8 Debugger (src/debugger/) - ✅ EXCELLENT

**Coverage:** 62 tests in debugger_test.zig

**Strengths:**
- ✅ Breakpoints (execute, memory access)
- ✅ Watchpoints (read, write, change)
- ✅ Step execution (instruction, scanline, frame)
- ✅ User callbacks
- ✅ RT-safe (zero heap allocations)
- ✅ History buffer (snapshot-based)

**Test Files:**
```
tests/debugger/
└── debugger_test.zig               # 62 tests (100% coverage)
```

**Gaps:** None identified - comprehensive coverage

---

### 1.9 Threading & Mailboxes (src/threads/) - 🟡 GOOD with Timing Issues

**Coverage:** 14 tests in threading_test.zig + 57 mailbox tests

**Strengths:**
- ✅ EmulationThread timer-driven execution
- ✅ RenderThread 60 FPS rendering
- ✅ Mailbox pattern (SPSC ring buffers)
- ✅ Frame synchronization
- ✅ Atomic updates (thread-safe)

**Test Files:**
```
tests/threads/
└── threading_test.zig              # 14 tests

tests/mailboxes/ (inferred)
                                     # ~57 tests (all mailbox types)
```

**Known Issues:**
- ⚠️ **3 timing-sensitive tests fail** (CLAUDE.md line 14, line 401)
  - Race conditions in frame timing
  - Need deterministic mocking or tolerance adjustment

---

## 2. Hardware Spec Compliance (nesdev.org)

### 2.1 Current Compliance: 🔴 POOR

**Statistics:**
- **Test References:** 5 nesdev.org mentions in test code (grep results)
- **Source References:** 13 nesdev.org mentions in src/ code
- **Spec Assertions:** Minimal "per nesdev.org" test assertions

**Files with nesdev.org References:**
```
tests/ppu/sprite_rendering_test.zig:3-4
docs/implementation/PPU-HARDWARE-ACCURACY-AUDIT.md (comprehensive audit doc)
src/ppu/Logic.zig (inline comments)
```

### 2.2 Missing Spec Tests (CRITICAL - P0)

#### 2.2.1 PPU Power-Up State
**nesdev.org:** https://www.nesdev.org/wiki/PPU_power_up_state

**Required Tests:**
```zig
test "PPU Power-Up: Initial register values per nesdev.org" {
    // PPUCTRL: $00
    // PPUMASK: $00
    // PPUSTATUS: +0x+0 (VBlank clear, sprite 0 clear, bits 0-4 open bus)
    // OAMADDR: $00
    // Scroll: $0000
    // PPUDATA buffer: $00
}

test "PPU Power-Up: First frame is longer (29,658 CPU cycles warmup)" {
    // nesdev.org: "PPU ignores writes to registers for first ~29,658 cycles"
    // Implementation: src/ppu/Logic.zig:280 (warmup_complete check)
}
```

#### 2.2.2 CPU Power-Up State
**nesdev.org:** https://www.nesdev.org/wiki/CPU_power_up_state

**Existing Test:**
```zig
// tests/cpu/instructions_test.zig:25-35
test "CPU power-on state - AccuracyCoin requirements" {
    // ✅ GOOD: Tests power-on values per spec
    // P = $34 (IRQ disabled)
    // A, X, Y = $00
    // S = $FD
}
```

**Gap:** No test validates RESET vs power-on differences

#### 2.2.3 PPU Rendering
**nesdev.org:** https://www.nesdev.org/wiki/PPU_rendering

**Missing Tests:**
```zig
test "PPU Rendering: Pre-render scanline (261) behavior per nesdev.org" {
    // Copy vertical scroll bits at dots 280-304
    // Skip dot 0 on odd frames when rendering enabled
    // No visible output
}

test "PPU Rendering: Post-render scanline (240) idle per nesdev.org" {
    // No fetches, no rendering, no sprite evaluation
    // Just idle between visible scanlines and VBlank
}

test "PPU Rendering: Sprite 0 hit clear timing per nesdev.org" {
    // Clear at dot 1 of pre-render scanline (261.1)
    // Same timing as VBlank flag clear
}
```

#### 2.2.4 PPU Scrolling
**nesdev.org:** https://www.nesdev.org/wiki/PPU_scrolling

**Missing Tests:**
```zig
test "PPU Scrolling: Loopy v/t register behavior per nesdev.org" {
    // PPUADDR double write updates t, then copies to v
    // PPUSCROLL double write updates t only
    // Horizontal bits copied at dot 257 each scanline
    // Vertical bits copied at dots 280-304 of pre-render line
}

test "PPU Scrolling: Fine X separate from v register per nesdev.org" {
    // Fine X is 3-bit register separate from 15-bit v
    // Only updated by PPUSCROLL first write
}
```

### 2.3 Recommended Spec Compliance Strategy

**Action Items:**
1. **Add nesdev.org URL comments to all hardware behavior tests**
   - Example: `// nesdev.org/wiki/PPU_rendering#VBlank`
   - Enables spec traceability

2. **Create spec compliance test suite**
   ```
   tests/spec_compliance/
   ├── cpu_power_up_spec.zig
   ├── ppu_power_up_spec.zig
   ├── ppu_rendering_spec.zig
   ├── ppu_scrolling_spec.zig
   ├── ppu_registers_spec.zig
   └── timing_spec.zig
   ```

3. **Use explicit spec assertion pattern**
   ```zig
   // nesdev.org: "VBlank flag is set at scanline 241, dot 1"
   try testing.expectEqual(@as(u16, 241), state.scanline);
   try testing.expectEqual(@as(u16, 1), state.dot);
   try testing.expect(state.ppu.status.vblank);
   ```

---

## 3. Commercial ROM Testing (CRITICAL GAP)

### 3.1 Available Test Data

**ROM Library:** 185 .nes files in tests/data/
- Super Mario Bros. (World)
- BurgerTime (USA)
- Donkey Kong
- Castlevania (3 versions)
- Mega Man (6 games)
- Legend of Zelda (2 games)
- Contra, Tetris, Metroid, etc.

**Current Testing:** ❌ ZERO commercial ROMs tested beyond loading

### 3.2 Missing Commercial ROM Tests (CRITICAL - P0)

#### 3.2.1 Load and Render Tests
```zig
// ❌ NOT TESTED: Commercial ROM rendering validation
test "Commercial ROM: Mario 1 title screen renders correctly" {
    // 1. Load ROM: tests/data/Mario/Super Mario Bros. (World).nes
    // 2. Run to frame 120 (2 seconds, past warm-up)
    // 3. Validate framebuffer output:
    //    - Non-zero pixel count > 10,000 (not blank screen)
    //    - Title graphics visible (pattern matching or hash)
    //    - PPUMASK != $00 (rendering enabled)
}

test "Commercial ROM: BurgerTime title screen renders" {
    // Same pattern for BurgerTime (USA).nes
    // Documented as non-working in CLAUDE.md:117
}

test "Commercial ROM: Donkey Kong gameplay renders" {
    // Load Donkey Kong, run to gameplay
    // Validate platform and character sprites visible
}
```

#### 3.2.2 Input Response Tests
```zig
// ❌ NOT TESTED: Controller input affects commercial games
test "Commercial ROM: Mario responds to START button" {
    // 1. Load Mario 1
    // 2. Wait for title screen
    // 3. Inject START button press via ControllerInputMailbox
    // 4. Verify game state changes (PC advances past title loop)
    // Current Issue: Games stuck at title (CLAUDE.md:112)
}

test "Commercial ROM: Mario responds to D-pad input" {
    // Inject LEFT/RIGHT movement
    // Validate sprite X coordinate changes
}
```

#### 3.2.3 Visual Regression Tests
```zig
// ❌ NOT TESTED: Framebuffer visual regression
test "Visual Regression: Mario 1 title screen matches golden image" {
    // 1. Render Mario title screen
    // 2. Compare framebuffer to golden reference (256×240 RGBA)
    // 3. Allow <1% pixel difference (tolerance for timing)
    // Tools: Image diff library (PNG comparison)
}

test "Visual Regression: BurgerTime level 1 screen" {
    // Golden reference for BurgerTime gameplay
}
```

**Implementation Strategy:**
```zig
// tests/integration/commercial_rom_test.zig (NEW FILE)
const std = @import("std");
const testing = std.testing;
const RomTestRunner = @import("rom_test_runner.zig");

const CommercialRomTest = struct {
    name: []const u8,
    path: []const u8,
    expected_frames_to_title: usize,
    expected_non_zero_pixels: usize,
    golden_hash: ?u64, // CRC64 of framebuffer
};

const COMMERCIAL_ROMS = [_]CommercialRomTest{
    .{
        .name = "Super Mario Bros.",
        .path = "tests/data/Mario/Super Mario Bros. (World).nes",
        .expected_frames_to_title = 120,
        .expected_non_zero_pixels = 15000,
        .golden_hash = null, // Generate on first run
    },
    .{
        .name = "BurgerTime",
        .path = "tests/data/BurgerTime (USA).nes",
        .expected_frames_to_title = 90,
        .expected_non_zero_pixels = 12000,
        .golden_hash = null,
    },
    // Add 10-20 representative games
};

test "Commercial ROMs: All load and render" {
    for (COMMERCIAL_ROMS) |rom_test| {
        errdefer std.debug.print("Failed ROM: {s}\n", .{rom_test.name});

        var runner = try RomTestRunner.init(testing.allocator, rom_test.path, .{
            .max_frames = rom_test.expected_frames_to_title,
            .verbose = false,
        });
        defer runner.deinit();

        var result = try runner.run();
        defer result.deinit(testing.allocator);

        // Validate framebuffer is not blank
        const non_zero_pixels = countNonZeroPixels(runner.state.framebuffer);
        try testing.expect(non_zero_pixels > rom_test.expected_non_zero_pixels);

        // Validate rendering was enabled
        try testing.expect(runner.state.ppu.mask.renderingEnabled());
    }
}
```

### 3.3 Framebuffer Validation Framework (MISSING)

**Current State:** PPU renders to framebuffer but output never validated

**Required Infrastructure:**
```zig
// tests/visual/framebuffer_validation.zig (NEW FILE)

/// Count non-zero pixels in framebuffer (256×240 = 61,440 pixels)
pub fn countNonZeroPixels(framebuffer: []const u32) usize {
    var count: usize = 0;
    for (framebuffer) |pixel| {
        if (pixel != 0) count += 1;
    }
    return count;
}

/// Calculate CRC64 hash of framebuffer for regression testing
pub fn framebufferHash(framebuffer: []const u32) u64 {
    var hasher = std.hash.Crc64.init();
    const bytes = std.mem.sliceAsBytes(framebuffer);
    hasher.update(bytes);
    return hasher.final();
}

/// Compare two framebuffers with tolerance
pub fn framebuffersDiffer(fb1: []const u32, fb2: []const u32, tolerance: f32) bool {
    if (fb1.len != fb2.len) return true;

    var diff_count: usize = 0;
    for (fb1, fb2) |p1, p2| {
        if (p1 != p2) diff_count += 1;
    }

    const diff_ratio = @as(f32, @floatFromInt(diff_count)) / @as(f32, @floatFromInt(fb1.len));
    return diff_ratio > tolerance;
}

/// Save framebuffer as PNG for visual inspection
pub fn saveFramebufferPNG(framebuffer: []const u32, path: []const u8) !void {
    // Use stb_image_write or similar
    // Format: 256×240 RGBA
}
```

**Usage in Tests:**
```zig
test "Framebuffer: Mario title screen non-blank" {
    // Run Mario to frame 120
    const fb = runner.state.framebuffer;

    // Validate output
    try testing.expect(countNonZeroPixels(fb) > 10000);

    // Optional: Save for manual inspection
    if (std.os.getenv("SAVE_TEST_IMAGES")) |_| {
        try saveFramebufferPNG(fb, "/tmp/mario_title.png");
    }
}
```

---

## 4. Integration Test Gaps (CRITICAL)

### 4.1 Current Integration Coverage

**Existing Tests:**
- ✅ CPU ↔ PPU: 20 tests (cpu_ppu_integration_test.zig)
- ✅ OAM DMA: 14 tests (oam_dma_test.zig)
- ✅ Controller I/O: 14 tests (controller_test.zig)
- ⚠️ AccuracyCoin: 2 tests (informational, skipped)
- ⚠️ VBlank Wait: 1 test (integration)

**Total:** 51 integration tests

### 4.2 Missing Integration Tests (HIGH - P1)

#### 4.2.1 End-to-End Rendering Pipeline
```zig
// ❌ NOT TESTED: Complete rendering pipeline
test "E2E: CPU writes CHR data → PPU renders → Framebuffer output" {
    // 1. CPU writes pattern data to CHR RAM ($0000-$1FFF via PPU)
    // 2. CPU writes nametable data ($2000-$2FFF)
    // 3. CPU writes palette data ($3F00-$3F1F)
    // 4. CPU enables rendering (PPUMASK = $1E)
    // 5. Run one frame
    // 6. Validate framebuffer contains expected pattern
}

test "E2E: CPU writes sprite data → OAM DMA → PPU renders sprites" {
    // 1. CPU writes sprite data to RAM ($0200-$02FF)
    // 2. CPU triggers OAM DMA ($4014 = $02)
    // 3. CPU enables rendering
    // 4. Run one frame
    // 5. Validate sprites visible in framebuffer
}
```

#### 4.2.2 CPU-PPU-Bus-Cartridge Pipeline
```zig
// ❌ NOT TESTED: Full memory access chain
test "E2E: CPU reads PPU via bus from cartridge CHR ROM" {
    // 1. CPU reads $2007 (PPUDATA)
    // 2. PPU reads from VRAM address
    // 3. VRAM read triggers cartridge ppuRead()
    // 4. Cartridge returns CHR ROM data
    // 5. PPU buffers data
    // 6. CPU receives buffered value
    // Validate: Entire chain traced with expected values
}

test "E2E: CPU triggers APU IRQ → IRQ handler reads APU status → IRQ cleared" {
    // 1. APU frame counter triggers IRQ
    // 2. CPU IRQ line asserted
    // 3. CPU enters IRQ handler (PC → IRQ vector)
    // 4. IRQ handler reads $4015 (APU status)
    // 5. IRQ flag cleared
    // 6. CPU resumes
}
```

#### 4.2.3 Thread Synchronization
```zig
// ❌ NOT TESTED: Multi-thread integration
test "E2E: EmulationThread renders → FrameMailbox → RenderThread displays" {
    // 1. EmulationThread runs one frame
    // 2. Framebuffer written to FrameMailbox
    // 3. RenderThread polls mailbox
    // 4. RenderThread uploads to Vulkan texture
    // 5. Validate: Frame data identical at both ends
}

test "E2E: Input flow (Keyboard → Mailbox → Emulation → Game response)" {
    // 1. Main thread posts button press to ControllerInputMailbox
    // 2. EmulationThread polls mailbox
    // 3. Controller shift register updated
    // 4. Game reads $4016
    // 5. Game state changes
    // Current: 22 TODO stubs (input_integration_test.zig)
}
```

---

## 5. Test Quality Issues

### 5.1 Flaky / Timing-Sensitive Tests

**Known Issues:**
```
tests/threads/threading_test.zig: 3 tests fail intermittently
- Race conditions in frame timing
- Dependent on system clock precision
- CLAUDE.md line 14: "3 threading tests timing-sensitive"
```

**Root Cause Analysis:**
- Tests use real timers (libxev event loop)
- Frame timing expectations too strict (±1ms tolerance)
- CI environment has variable scheduling latency

**Recommended Fixes:**
```zig
// Current (flaky):
test "Threading: Frame timing maintains 60 FPS" {
    const expected_frame_time_ns = 16_666_666; // 60 FPS
    try testing.expectEqual(expected_frame_time_ns, actual_frame_time_ns);
    // ❌ Fails if actual is 16,666,500 or 16,667,000
}

// Fixed (tolerant):
test "Threading: Frame timing maintains 60 FPS (±5% tolerance)" {
    const expected_frame_time_ns = 16_666_666;
    const tolerance_ns = expected_frame_time_ns / 20; // 5% = 833,333ns
    const diff = if (actual_frame_time_ns > expected_frame_time_ns)
        actual_frame_time_ns - expected_frame_time_ns
    else
        expected_frame_time_ns - actual_frame_time_ns;
    try testing.expect(diff < tolerance_ns);
}

// Best (deterministic):
test "Threading: Frame timing with mocked timer" {
    // Mock FrameTimer.zig to return fixed timestamps
    // Eliminates system timer variability
}
```

### 5.2 Incomplete Test Stubs (TODO Markers)

**Found:** 22 TODO comments in tests/integration/input_integration_test.zig

**Examples:**
```zig
// TODO: Implement when ControllerInputMailbox is wired up
// TODO: Test holding button across multiple frames
// TODO: Test rapid A button presses
// TODO: Test multiple buttons pressed same frame
// TODO: Test two-player input
// TODO: Load simple TAS file
```

**Status:** Input system wired (CLAUDE.md line 112) but integration tests never completed

**Impact:** HIGH - Input path untested end-to-end despite being "ready for testing"

### 5.3 Tests with Known Bugs

**tests/cpu/opcodes/arithmetic_test.zig:23:**
```zig
false, // C (borrow occurred) ← BUG: Current code will set this to true!
```

**Status:** Bug documented in test, not fixed

**Impact:** MEDIUM - Carry flag behavior incorrect for SBC edge case

### 5.4 Skipped / Informational Tests

**AccuracyCoin tests marked as skip:**
```zig
// tests/integration/accuracycoin_execution_test.zig:96
if (!result.passed) {
    return error.SkipZigTest; // Skip instead of failing
}
```

**Reason:** APU waveform generation not implemented (Milestone 7)

**Impact:** LOW - Expected failure, documented in CLAUDE.md

---

## 6. Priority Recommendations

### 6.1 CRITICAL (P0) - Blocking Game Playability

**Must implement immediately:**

1. **PPU Warm-Up Period Tests** (2-3 hours)
   - Create tests/ppu/warmup_period_test.zig
   - Validate 29,658 cycle count
   - Verify register write blocking
   - Test RESET skips warm-up

2. **Rendering Enable/Disable Tests** (3-4 hours)
   - Create tests/ppu/rendering_state_test.zig
   - Test PPUMASK bit 3/4 transitions
   - Validate framebuffer output changes
   - Test leftmost 8-pixel clipping

3. **Commercial ROM Load Tests** (4-6 hours)
   - Create tests/integration/commercial_rom_test.zig
   - Test Mario 1, BurgerTime, Donkey Kong
   - Validate non-blank framebuffer
   - Check rendering enabled

4. **Framebuffer Validation Framework** (3-4 hours)
   - Create tests/visual/framebuffer_validation.zig
   - Implement pixel counting, hashing
   - Add PNG export for debugging

5. **VBlank NMI Race Condition Tests** (2-3 hours)
   - Test scanline 241 dot 0/1/2 behavior
   - Validate NMI suppression window
   - Test PPUSTATUS read timing

**Total Estimated Effort:** 14-20 hours

### 6.2 HIGH (P1) - Quality & Spec Compliance

**Implement soon:**

6. **nesdev.org Spec Compliance Suite** (6-8 hours)
   - Create tests/spec_compliance/ directory
   - Add URL references to all hardware tests
   - Document expected behavior per spec

7. **APU Integration Tests** (3-4 hours)
   - Test APU IRQ → CPU IRQ line
   - Validate IRQ acknowledge via $4015
   - Test DMC DMA integration

8. **Input Integration Tests** (4-6 hours)
   - Implement 22 TODO stubs
   - End-to-end keyboard → game response
   - TAS file playback validation

9. **Open Bus Edge Cases** (2-3 hours)
   - Test decay timing (if needed)
   - Validate all write-only registers
   - Test PPU vs CPU open bus separation

10. **PPU Register Timing Tests** (3-4 hours)
    - PPUSTATUS read at various scanline/dot positions
    - PPUDATA buffering edge cases
    - w toggle state during rendering

**Total Estimated Effort:** 18-25 hours

### 6.3 MEDIUM (P2) - Future Enhancements

**Defer to post-playability:**

11. **Visual Regression Test Suite** (8-12 hours)
    - Golden image generation for 10-20 games
    - Automated visual diff testing
    - CI integration

12. **Mapper Expansion Tests** (per mapper, 2-4 hours each)
    - Mapper 1 (MMC1): Bank switching, CHR switching
    - Mapper 2 (UxROM): PRG banking
    - Mapper 3 (CNROM): CHR banking
    - Mapper 4 (MMC3): IRQ counter, complex banking

13. **Performance Regression Tests** (4-6 hours)
    - Benchmark suite for CPU/PPU/APU
    - Automated performance tracking
    - Detect timing regressions

14. **Deterministic Threading Tests** (3-4 hours)
    - Mock FrameTimer for fixed timestamps
    - Eliminate flaky timing tests
    - 100% reliable CI

**Total Estimated Effort:** 17-26 hours

---

## 7. Test Organization Recommendations

### 7.1 Proposed Directory Structure

```
tests/
├── spec_compliance/              # NEW: nesdev.org spec validation
│   ├── cpu_spec.zig
│   ├── ppu_spec.zig
│   ├── apu_spec.zig
│   └── timing_spec.zig
├── visual/                       # NEW: Framebuffer validation
│   ├── framebuffer_validation.zig
│   └── golden_images/            # Reference screenshots
├── integration/                  # EXPAND: End-to-end tests
│   ├── commercial_rom_test.zig   # NEW
│   ├── rendering_pipeline_test.zig # NEW
│   └── input_integration_test.zig # FIX: Complete TODOs
├── ppu/                          # EXPAND: Missing PPU tests
│   ├── warmup_period_test.zig    # NEW
│   ├── rendering_state_test.zig  # NEW
│   └── vblank_timing_test.zig    # NEW
└── (existing directories)
```

### 7.2 Test Naming Convention

**Adopt consistent pattern:**
```zig
// Component: Feature: Specific behavior [nesdev.org reference]
test "PPU VBlank: Flag set at 241.1 per nesdev.org" { }
test "CPU RMW: Dummy write cycle per nesdev.org" { }
test "APU DMC: IRQ on buffer empty per nesdev.org" { }
```

### 7.3 Test Documentation Headers

**Add to all test files:**
```zig
//! Test File: ppu/vblank_timing_test.zig
//!
//! Hardware Reference: https://www.nesdev.org/wiki/PPU_frame_timing#VBlank_Flag
//!
//! Tests VBlank flag timing behavior:
//! - VBlank set at scanline 241, dot 1
//! - VBlank cleared at scanline 261, dot 1
//! - NMI suppression window (reading $2002 during set)
//!
//! All test cases validated against nesdev.org specification.
```

---

## 8. Specific Test Cases Needed (Implementation Ready)

### 8.1 PPU Warm-Up Period (tests/ppu/warmup_period_test.zig)

```zig
//! PPU Warm-Up Period Tests
//!
//! Hardware Reference: https://www.nesdev.org/wiki/PPU_power_up_state
//!
//! The NES PPU ignores writes to certain registers for approximately 29,658
//! CPU cycles after power-on. This "warm-up period" does not occur on RESET.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

test "PPU Warm-up: PPUCTRL writes ignored before 29658 cycles" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Initial state: warmup_complete = false (set by init)
    try testing.expect(!harness.state.ppu.warmup_complete);

    // Write to PPUCTRL should be ignored
    harness.state.busWrite(0x2000, 0x80); // Try to enable NMI
    try testing.expectEqual(@as(u8, 0x00), harness.state.ppu.ctrl.toByte());
}

test "PPU Warm-up: PPUMASK writes ignored during warm-up" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.busWrite(0x2001, 0x1E); // Try to enable rendering
    try testing.expectEqual(@as(u8, 0x00), harness.state.ppu.mask.toByte());
}

test "PPU Warm-up: PPUSCROLL writes ignored during warm-up" {
    var harness = try Harness.init();
    defer harness.deinit();

    // PPUSCROLL uses internal t register
    const initial_t = harness.state.ppu.internal.t;
    harness.state.busWrite(0x2005, 0x12); // Try to set X scroll
    harness.state.busWrite(0x2005, 0x34); // Try to set Y scroll

    // t register should be unchanged
    try testing.expectEqual(initial_t, harness.state.ppu.internal.t);
}

test "PPU Warm-up: PPUADDR writes ignored during warm-up" {
    var harness = try Harness.init();
    defer harness.deinit();

    const initial_v = harness.state.ppu.internal.v;
    harness.state.busWrite(0x2006, 0x20); // Try to set high byte
    harness.state.busWrite(0x2006, 0x00); // Try to set low byte

    // v register should be unchanged
    try testing.expectEqual(initial_v, harness.state.ppu.internal.v);
}

test "PPU Warm-up: Completes after 29658 CPU cycles" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Run emulation for 29,657 CPU cycles
    for (0..29657) |_| {
        harness.state.tick();
    }

    // Still in warm-up (29,658 cycles needed)
    try testing.expect(!harness.state.ppu.warmup_complete);

    // One more cycle completes warm-up
    harness.state.tick();
    try testing.expect(harness.state.ppu.warmup_complete);

    // Now writes should work
    harness.state.busWrite(0x2000, 0x80);
    try testing.expect(harness.state.ppu.ctrl.nmi_enable);
}

test "PPU Warm-up: RESET skips warm-up period" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Call reset (not power-on)
    harness.state.reset();

    // Warm-up should be skipped
    try testing.expect(harness.state.ppu.warmup_complete);

    // Writes should work immediately
    harness.state.busWrite(0x2000, 0x80);
    try testing.expect(harness.state.ppu.ctrl.nmi_enable);
}

test "PPU Warm-up: PPUDATA reads/writes allowed during warm-up" {
    // nesdev.org: "Only $2000, $2001, $2005, $2006 are affected"
    var harness = try Harness.init();
    defer harness.deinit();

    // PPUDATA ($2007) should work during warm-up
    harness.state.busWrite(0x2007, 0x42);
    // Cannot easily verify without setting PPUADDR first,
    // but write should not crash or be ignored

    // OAMDATA ($2004) should work
    harness.state.busWrite(0x2003, 0x10); // Set OAMADDR
    harness.state.busWrite(0x2004, 0x99); // Write to OAM
    try testing.expectEqual(@as(u8, 0x99), harness.state.ppu.oam[0x10]);
}
```

---

### 8.2 VBlank NMI Timing (tests/ppu/vblank_timing_test.zig)

```zig
//! VBlank NMI Timing Tests
//!
//! Hardware Reference: https://www.nesdev.org/wiki/PPU_frame_timing#VBlank_Flag
//!
//! Critical timing windows:
//! - VBlank flag set at scanline 241, dot 1 (not dot 0)
//! - Reading $2002 during the exact cycle VBlank is set suppresses NMI
//! - VBlank flag cleared at scanline 261, dot 1

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

test "PPU VBlank: Flag not set at scanline 241 dot 0" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Advance to scanline 241, dot 0
    // (Need to implement seekToScanlineDot helper in Harness)
    harness.seekToScanlineDot(241, 0);

    // VBlank should NOT be set yet
    try testing.expect(!harness.state.ppu.status.vblank);
}

test "PPU VBlank: Flag set at scanline 241 dot 1 per nesdev.org" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Advance to scanline 241, dot 1
    harness.seekToScanlineDot(241, 1);

    // VBlank should be set
    try testing.expect(harness.state.ppu.status.vblank);
}

test "PPU VBlank: Reading $2002 at 241.1 suppresses NMI" {
    // This is the critical race condition test
    var harness = try Harness.init();
    defer harness.deinit();

    // Enable NMI
    harness.state.ppu.ctrl.nmi_enable = true;

    // Advance to scanline 241, dot 0
    harness.seekToScanlineDot(241, 0);

    // Read PPUSTATUS (this happens BEFORE VBlank is set at dot 1)
    _ = harness.state.busRead(0x2002);

    // Tick to dot 1 (VBlank would normally be set here)
    harness.state.tick();

    // VBlank flag should be CLEARED by the read
    // NMI should NOT have been triggered
    try testing.expect(!harness.state.ppu.status.vblank);
    try testing.expect(!harness.state.cpu.nmi_line);
}

test "PPU VBlank: Reading $2002 at 241.2 does not suppress NMI" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.ppu.ctrl.nmi_enable = true;

    // Advance to scanline 241, dot 2 (AFTER VBlank set)
    harness.seekToScanlineDot(241, 2);

    // VBlank should already be set and NMI triggered
    try testing.expect(harness.state.ppu.status.vblank);
    try testing.expect(harness.state.cpu.nmi_line);

    // Reading now clears flag but NMI already fired
    _ = harness.state.busRead(0x2002);
    try testing.expect(!harness.state.ppu.status.vblank);
}

test "PPU VBlank: Flag cleared at scanline 261 dot 1 per nesdev.org" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Set VBlank flag manually
    harness.state.ppu.status.vblank = true;

    // Advance to scanline 261, dot 1
    harness.seekToScanlineDot(261, 1);

    // VBlank should be cleared
    try testing.expect(!harness.state.ppu.status.vblank);
}

// Helper implementation needed in TestHarness:
// pub fn seekToScanlineDot(self: *Harness, target_scanline: u16, target_dot: u16) void {
//     while (self.state.clock.scanline() != target_scanline or
//            self.state.clock.dot() != target_dot) {
//         self.state.tick();
//     }
// }
```

---

### 8.3 Commercial ROM Tests (tests/integration/commercial_rom_test.zig)

```zig
//! Commercial ROM Integration Tests
//!
//! Validates that commercial NES games load correctly and produce visible output.
//! These tests catch regressions in PPU rendering, controller input, and game logic.

const std = @import("std");
const testing = std.testing;
const RomTestRunner = @import("rom_test_runner.zig");

const CommercialRomTest = struct {
    name: []const u8,
    path: []const u8,
    frames_to_title: usize,      // Frames until title screen stable
    min_non_zero_pixels: usize,  // Minimum non-black pixels expected
    rendering_should_enable: bool, // PPUMASK should have bits 3/4 set
};

const TEST_ROMS = [_]CommercialRomTest{
    .{
        .name = "Super Mario Bros.",
        .path = "tests/data/Mario/Super Mario Bros. (World).nes",
        .frames_to_title = 120, // ~2 seconds (past warm-up)
        .min_non_zero_pixels = 10000,
        .rendering_should_enable = true,
    },
    .{
        .name = "BurgerTime",
        .path = "tests/data/BurgerTime (USA).nes",
        .frames_to_title = 90,
        .min_non_zero_pixels = 8000,
        .rendering_should_enable = true,
    },
    .{
        .name = "Donkey Kong",
        .path = "tests/data/Donkey Kong/Donkey Kong (World) (Rev 1).nes",
        .frames_to_title = 100,
        .min_non_zero_pixels = 12000,
        .rendering_should_enable = true,
    },
};

test "Commercial ROMs: All load without crash" {
    for (TEST_ROMS) |rom_test| {
        errdefer std.debug.print("FAILED: {s}\n", .{rom_test.name});

        var runner = RomTestRunner.init(
            testing.allocator,
            rom_test.path,
            .{ .max_frames = 10, .verbose = false },
        ) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("SKIP: {s} (ROM not found)\n", .{rom_test.name});
                continue;
            }
            return err;
        };
        defer runner.deinit();

        _ = try runner.run();
        // If we get here, ROM loaded successfully
    }
}

test "Commercial ROMs: Title screens render (non-blank output)" {
    for (TEST_ROMS) |rom_test| {
        errdefer std.debug.print("FAILED: {s}\n", .{rom_test.name});

        var runner = RomTestRunner.init(
            testing.allocator,
            rom_test.path,
            .{
                .max_frames = rom_test.frames_to_title,
                .verbose = false,
            },
        ) catch |err| {
            if (err == error.FileNotFound) continue; // Skip if ROM missing
            return err;
        };
        defer runner.deinit();

        var result = try runner.run();
        defer result.deinit(testing.allocator);

        // Validate framebuffer is not blank
        const framebuffer = runner.state.getFramebuffer();
        const non_zero_count = countNonZeroPixels(framebuffer);

        std.debug.print("{s}: {d} non-zero pixels (min {d})\n", .{
            rom_test.name,
            non_zero_count,
            rom_test.min_non_zero_pixels,
        });

        try testing.expect(non_zero_count >= rom_test.min_non_zero_pixels);
    }
}

test "Commercial ROMs: Rendering enabled (PPUMASK != $00)" {
    for (TEST_ROMS) |rom_test| {
        if (!rom_test.rendering_should_enable) continue;

        errdefer std.debug.print("FAILED: {s}\n", .{rom_test.name});

        var runner = RomTestRunner.init(
            testing.allocator,
            rom_test.path,
            .{
                .max_frames = rom_test.frames_to_title,
                .verbose = false,
            },
        ) catch |err| {
            if (err == error.FileNotFound) continue;
            return err;
        };
        defer runner.deinit();

        _ = try runner.run();

        // Check PPUMASK bits 3/4 (show BG / show sprites)
        const mask_byte = runner.state.ppu.mask.toByte();
        std.debug.print("{s}: PPUMASK = ${X:0>2}\n", .{ rom_test.name, mask_byte });

        try testing.expect(runner.state.ppu.mask.renderingEnabled());
    }
}

fn countNonZeroPixels(framebuffer: []const u32) usize {
    var count: usize = 0;
    for (framebuffer) |pixel| {
        if (pixel != 0) count += 1;
    }
    return count;
}
```

---

## 9. Summary & Action Plan

### 9.1 Test Coverage Score

**Component Scores (0-100):**
- CPU: 95/100 ✅
- PPU Sprites: 90/100 ✅
- PPU Background: 60/100 🟡
- APU: 75/100 🟡
- Bus/Memory: 65/100 🟡
- Controller I/O: 85/100 ✅
- Cartridge: 70/100 🟡
- Debugger: 100/100 ✅
- Integration: 30/100 🔴
- Commercial ROMs: 5/100 🔴

**Overall Score: 67.5/100 (GOOD with critical gaps)**

### 9.2 Critical Path to Playability

**Phase 1: Core Validation (14-20 hours)**
1. PPU warm-up period tests → Prevent regression
2. Rendering enable/disable tests → Fix current issue (PPUMASK=$00)
3. Commercial ROM load tests → Validate game compatibility
4. Framebuffer validation framework → Enable visual testing
5. VBlank NMI race tests → Prevent timing bugs

**Phase 2: Quality & Compliance (18-25 hours)**
6. nesdev.org spec compliance suite → Hardware accuracy
7. APU integration tests → Validate IRQ behavior
8. Input integration tests → Complete TODO stubs
9. PPU register timing tests → Edge case coverage
10. Open bus edge cases → Hardware quirk validation

**Phase 3: Long-Term (17-26 hours)**
11. Visual regression testing → Automated QA
12. Mapper expansion tests → Broader compatibility
13. Performance regression tests → Prevent slowdowns
14. Deterministic threading tests → Eliminate flakes

### 9.3 Immediate Next Steps

**This Week:**
1. ✅ Create this QA test coverage report
2. ⬜ Implement tests/ppu/warmup_period_test.zig (3 hours)
3. ⬜ Implement tests/ppu/rendering_state_test.zig (4 hours)
4. ⬜ Implement tests/integration/commercial_rom_test.zig (6 hours)
5. ⬜ Add framebuffer validation helpers (3 hours)

**Next Week:**
6. ⬜ Implement tests/ppu/vblank_timing_test.zig (3 hours)
7. ⬜ Complete input integration TODOs (6 hours)
8. ⬜ Add nesdev.org references to existing tests (4 hours)
9. ⬜ Fix 3 flaky threading tests (4 hours)

**Total:** ~33 hours to address all P0 and high-priority P1 gaps

---

## 10. Conclusion

The RAMBO NES emulator has **excellent test coverage for individual components** (778 tests, 16,078 lines), but suffers from **critical gaps in integration testing and hardware spec validation**.

**Key Strengths:**
- ✅ Comprehensive CPU testing (280+ tests, cycle-accurate)
- ✅ Excellent PPU sprite coverage (73 tests, hardware-accurate)
- ✅ Complete controller I/O validation (hardware-accurate 4021 emulation)
- ✅ Debugger fully tested (62 tests, production-ready)

**Critical Weaknesses:**
- ❌ NO framebuffer validation (PPU renders but output never checked)
- ❌ NO commercial ROM visual testing (185 ROMs available, 0 tested)
- ❌ NO PPU warm-up period tests (documented fix lacks regression tests)
- ❌ NO VBlank timing race tests (critical 1-cycle window untested)
- ❌ Minimal nesdev.org spec compliance (only 5 references in tests)

**Recommendation:** Prioritize the **Critical Path to Playability (Phase 1)** before expanding mapper support or adding audio output. Addressing these 5 gaps will:
1. Prevent regressions in recently-fixed bugs (warm-up period, rendering enable)
2. Validate the complete CPU-PPU-Bus-Cartridge pipeline end-to-end
3. Enable automated visual regression testing for future changes
4. Establish hardware spec compliance as a first-class testing concern

**Estimated Impact:** 14-20 hours of focused QA work will increase overall test coverage score from **67.5/100 → 85/100** and unlock commercial ROM playability validation.

---

**Report Generated:** 2025-10-07
**Agent:** qa-code-review-pro
**Review Scope:** Full system test coverage audit
**Test Count:** 778 test cases, 53 test files, ~16,078 lines
