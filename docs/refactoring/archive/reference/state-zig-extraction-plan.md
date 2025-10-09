# EmulationState Extraction Plan

**Target File:** `/home/colin/Development/RAMBO/src/emulation/State.zig` (2,225 lines)
**Goal:** Break into 11 focused modules (150-320 lines each)
**Timeline:** 4 weeks (incremental, fully validated)

---

## Dependency Graph

### Current Architecture
```
EmulationState.zig (2,225 lines)
├── Owns: CpuState, PpuState, ApuState, BusState, DmaState, DmcDmaState, ControllerState
├── Imports: Config, MasterClock, Cpu, Ppu, Apu, Cartridge, Debugger
└── Exported by: 40+ files (threads, tests, tools)
```

### Proposed Architecture
```
EmulationState.zig (150 lines) - Core state container
├── CycleResults.zig (20 lines) - Return types
├── BusState.zig (15 lines) - Bus state data
├── BusLogic.zig (280 lines) - Bus routing
├── Logic.zig (120 lines) - Orchestration
├── dma/
│   ├── OamDma.zig (80 lines) - OAM DMA
│   └── DmcDma.zig (80 lines) - DMC DMA
└── Delegates to:
    ├── cpu/ExecutionLogic.zig (600 lines)
    ├── cpu/Microsteps.zig (320 lines)
    └── input/ControllerState.zig (85 lines)
```

---

## Phase 1: Zero-Risk Data Extractions (Days 1-3)

**Goal:** Extract pure data structures with zero API changes
**Risk:** MINIMAL
**Test Impact:** None (type aliases)

### Task 1.1: Extract CycleResults.zig (Day 1 - 2 hours)

**Lines to Extract:** 30-45 (16 lines)

**New File:** `src/emulation/CycleResults.zig`
```zig
//! Cycle execution result types for component state machines

pub const PpuCycleResult = struct {
    frame_complete: bool = false,
    rendering_enabled: bool = false,
    nmi_signal: bool = false,
    vblank_clear: bool = false,
    a12_rising: bool = false,
};

pub const CpuCycleResult = struct {
    mapper_irq: bool = false,
};

pub const ApuCycleResult = struct {
    frame_irq: bool = false,
    dmc_irq: bool = false,
};
```

**Changes to State.zig:**
```zig
// Remove lines 30-45
// Add import:
const CycleResults = @import("CycleResults.zig");
const PpuCycleResult = CycleResults.PpuCycleResult;
const CpuCycleResult = CycleResults.CpuCycleResult;
const ApuCycleResult = CycleResults.ApuCycleResult;
```

**Validation:**
```bash
zig build test  # Must pass 939/947
git diff --stat  # Verify only 2 files changed
```

**Commit Message:**
```
refactor(emulation): Extract cycle result types to CycleResults.zig

- Move PpuCycleResult, CpuCycleResult, ApuCycleResult to dedicated module
- Zero API changes - only import path updated
- Part of State.zig modularization (Phase 1.1)

Lines: 2,225 → 2,209 (-16)
Files: State.zig, CycleResults.zig (new)
```

---

### Task 1.2: Extract BusState.zig (Day 1 - 3 hours)

**Lines to Extract:** 49-58 (10 lines)

**New File:** `src/emulation/BusState.zig`
```zig
//! NES memory bus state
//!
//! Stores CPU internal RAM and open bus behavior state.
//! Used by EmulationState for bus routing logic.

const std = @import("std");

/// Memory bus state owned by the emulator runtime
/// Stores all data required to service CPU/PPU bus accesses.
pub const BusState = struct {
    /// Internal RAM: 2KB ($0000-$07FF), mirrored through $0000-$1FFF
    ram: [2048]u8 = std.mem.zeroes([2048]u8),

    /// Last value observed on the CPU data bus (open bus behaviour)
    open_bus: u8 = 0,

    /// Optional external RAM used by tests in lieu of a cartridge
    test_ram: ?[]u8 = null,
};
```

**Changes to State.zig:**
```zig
// Remove lines 49-58
// Add import:
pub const BusState = @import("BusState.zig").BusState;
```

**Changes to snapshot/state.zig:**
```zig
// Update import:
const BusState = @import("../emulation/BusState.zig").BusState;
```

**Changes to cpu/opcodes/mod.zig:**
```zig
// Update import (if needed):
const BusState = @import("../../emulation/BusState.zig").BusState;
```

**Files Changed:**
- `src/emulation/State.zig` (remove 10 lines, add 1 import)
- `src/emulation/BusState.zig` (new, 15 lines)
- `src/snapshot/state.zig` (update import)
- `tests/integration/cpu_ppu_integration_test.zig` (verify no changes needed)

**Validation:**
```bash
zig build test
grep -r "BusState" src/ tests/ | grep "import"  # Verify all imports updated
```

**Commit Message:**
```
refactor(emulation): Extract BusState to dedicated module

- Move BusState struct to src/emulation/BusState.zig
- Update imports in State.zig, snapshot/state.zig
- Zero API changes - EmulationState re-exports BusState
- Part of State.zig modularization (Phase 1.2)

Lines: 2,209 → 2,199 (-10)
Files: State.zig, BusState.zig (new), snapshot/state.zig
```

---

### Task 1.3: Extract dma/OamDma.zig (Day 2 - 4 hours)

**Lines to Extract:** 63-102 (struct), 1782-1819 (logic)

**New File:** `src/emulation/dma/OamDma.zig`
```zig
//! OAM DMA State Machine
//!
//! Cycle-accurate DMA transfer from CPU RAM to PPU OAM.
//! Follows microstep pattern for hardware accuracy.
//!
//! Timing (hardware-accurate):
//! - Cycle 0 (if needed): Alignment wait (odd CPU cycle start)
//! - Cycles 1-512: 256 read/write pairs
//!   * Even cycles: Read byte from CPU RAM
//!   * Odd cycles: Write byte to PPU OAM
//! - Total: 513 cycles (even start) or 514 cycles (odd start)

const std = @import("std");
const EmulationState = @import("../State.zig").EmulationState;

/// OAM DMA State Machine
pub const OamDmaState = struct {
    /// DMA active flag
    active: bool = false,

    /// Source page number (written to $4014)
    source_page: u8 = 0,

    /// Current byte offset within page (0-255)
    current_offset: u8 = 0,

    /// Cycle counter within DMA transfer
    current_cycle: u16 = 0,

    /// Alignment wait needed (odd CPU cycle start)
    needs_alignment: bool = false,

    /// Temporary value for read/write pair
    temp_value: u8 = 0,

    /// Trigger DMA transfer
    pub fn trigger(self: *OamDmaState, page: u8, on_odd_cycle: bool) void {
        self.active = true;
        self.source_page = page;
        self.current_offset = 0;
        self.current_cycle = 0;
        self.needs_alignment = on_odd_cycle;
        self.temp_value = 0;
    }

    /// Reset DMA state
    pub fn reset(self: *OamDmaState) void {
        self.* = .{};
    }

    /// Tick DMA state machine (called every CPU cycle when active)
    pub fn tick(self: *OamDmaState, state: *EmulationState) void {
        const cycle = self.current_cycle;
        self.current_cycle += 1;

        // Alignment wait cycle (if needed)
        if (self.needs_alignment and cycle == 0) {
            return;
        }

        // Calculate effective cycle (after alignment)
        const effective_cycle = if (self.needs_alignment) cycle - 1 else cycle;

        // Check if DMA is complete (512 cycles = 256 read/write pairs)
        if (effective_cycle >= 512) {
            self.reset();
            return;
        }

        // DMA transfer: Alternate between read and write
        if (effective_cycle % 2 == 0) {
            // Even cycle: Read from CPU RAM
            const source_addr = (@as(u16, self.source_page) << 8) | @as(u16, self.current_offset);
            self.temp_value = state.busRead(source_addr);
        } else {
            // Odd cycle: Write to PPU OAM
            state.ppu.oam[self.current_offset] = self.temp_value;
            self.current_offset +%= 1;
        }
    }
};
```

**Changes to State.zig:**
```zig
// Remove lines 63-102, 1782-1819
// Add import:
pub const DmaState = @import("dma/OamDma.zig").OamDmaState;

// Update tickDma() to delegation wrapper:
fn tickDma(self: *EmulationState) void {
    self.dma.tick(self);
}
```

**Files Changed:**
- `src/emulation/State.zig` (remove ~80 lines, add delegation)
- `src/emulation/dma/OamDma.zig` (new, 80 lines)

**Validation:**
```bash
zig build test
zig build test-integration
# Check OAM DMA tests specifically:
zig test tests/integration/oam_dma_test.zig
```

**Commit Message:**
```
refactor(emulation): Extract OAM DMA to dedicated module

- Move OamDmaState and tickDma logic to src/emulation/dma/OamDma.zig
- EmulationState.dma field now uses OamDmaState type
- tickDma() becomes delegation wrapper
- Part of State.zig modularization (Phase 1.3)

Lines: 2,199 → 2,119 (-80)
Files: State.zig, dma/OamDma.zig (new)
```

---

### Task 1.4: Extract dma/DmcDma.zig (Day 2 - 4 hours)

**Lines to Extract:** 194-224 (struct), 1832-1881 (logic)

**New File:** `src/emulation/dma/DmcDma.zig`
```zig
//! DMC DMA State Machine
//!
//! Simulates RDY line (CPU stall) during DMC sample fetch.
//! NTSC (2A03) only: Causes controller/PPU register corruption.
//!
//! Hardware behavior (NTSC 2A03):
//! - CPU is stalled via RDY line for 4 cycles (3 idle + 1 fetch)
//! - During stall, CPU repeats last read cycle
//! - If last read was $4016/$4017 (controller), corruption occurs
//!
//! PAL 2A07: Bug fixed, DMA is clean (no corruption)

const std = @import("std");
const EmulationState = @import("../State.zig").EmulationState;
const Config = @import("../../config/Config.zig");
const ApuLogic = @import("../../apu/Logic.zig");

/// DMC DMA State Machine
pub const DmcDmaState = struct {
    /// RDY line active (CPU stalled)
    rdy_low: bool = false,

    /// Cycles remaining in RDY stall (0-4)
    stall_cycles_remaining: u8 = 0,

    /// Sample address to fetch
    sample_address: u16 = 0,

    /// Sample byte fetched (returned to APU)
    sample_byte: u8 = 0,

    /// Last CPU read address (for repeat reads during stall)
    last_read_address: u16 = 0,

    /// Trigger DMC sample fetch
    pub fn triggerFetch(self: *DmcDmaState, address: u16) void {
        self.rdy_low = true;
        self.stall_cycles_remaining = 4; // 3 idle + 1 fetch
        self.sample_address = address;
    }

    /// Reset DMC DMA state
    pub fn reset(self: *DmcDmaState) void {
        self.* = .{};
    }

    /// Tick DMC DMA state machine (called every CPU cycle when active)
    pub fn tick(self: *DmcDmaState, state: *EmulationState) void {
        const cycle = self.stall_cycles_remaining;

        if (cycle == 0) {
            self.rdy_low = false;
            return;
        }

        self.stall_cycles_remaining -= 1;

        if (cycle == 1) {
            // Final cycle: Fetch sample byte
            const address = self.sample_address;
            self.sample_byte = state.busRead(address);

            // Load into APU
            ApuLogic.loadSampleByte(&state.apu, self.sample_byte);

            // DMA complete - clear RDY line
            self.rdy_low = false;
        } else {
            // Idle cycles (1-3): CPU repeats last read
            const has_dpcm_bug = switch (state.config.cpu.variant) {
                .rp2a03e, .rp2a03g, .rp2a03h => true, // NTSC - has bug
                .rp2a07 => false, // PAL - bug fixed
            };

            if (has_dpcm_bug) {
                const last_addr = self.last_read_address;

                // Controller corruption
                if (last_addr == 0x4016 or last_addr == 0x4017) {
                    _ = state.busRead(last_addr);
                }

                // PPU side effects
                if (last_addr == 0x2002 or last_addr == 0x2007) {
                    _ = state.busRead(last_addr);
                }
            }
        }
    }
};
```

**Changes to State.zig:**
```zig
// Remove lines 194-224, 1832-1881
// Add import:
pub const DmcDmaState = @import("dma/DmcDma.zig").DmcDmaState;

// Update tickDmcDma() to delegation wrapper:
pub fn tickDmcDma(self: *EmulationState) void {
    self.dmc_dma.tick(self);
}
```

**Changes to tests/integration/dpcm_dma_test.zig:**
```zig
// Update test code:
// Before: state.tickDmcDma();
// After: state.dmc_dma.tick(&state);
```

**Files Changed:**
- `src/emulation/State.zig` (remove ~80 lines, add delegation)
- `src/emulation/dma/DmcDma.zig` (new, 90 lines)
- `tests/integration/dpcm_dma_test.zig` (1 call site change)

**Validation:**
```bash
zig build test
# Check DMC DMA test specifically:
zig test tests/integration/dpcm_dma_test.zig
```

**Commit Message:**
```
refactor(emulation): Extract DMC DMA to dedicated module

- Move DmcDmaState and tickDmcDma logic to src/emulation/dma/DmcDma.zig
- EmulationState.dmc_dma field now uses DmcDmaState type
- tickDmcDma() becomes delegation wrapper
- Update 1 test file to use new API
- Part of State.zig modularization (Phase 1.4)

Lines: 2,119 → 2,039 (-80)
Files: State.zig, dma/DmcDma.zig (new), dpcm_dma_test.zig
```

---

### Task 1.5: Extract input/ControllerState.zig (Day 3 - 4 hours)

**Lines to Extract:** 107-189 (83 lines)

**New File:** `src/input/ControllerState.zig`
```zig
//! NES Controller State
//!
//! Implements cycle-accurate 4021 8-bit shift register behavior.
//! Button order: A, B, Select, Start, Up, Down, Left, Right

const std = @import("std");

/// NES Controller State
pub const ControllerState = struct {
    /// Controller 1 shift register
    shift1: u8 = 0,

    /// Controller 2 shift register
    shift2: u8 = 0,

    /// Strobe state (latched buttons or shifting mode)
    /// True = reload shift registers on each read (strobe high)
    /// False = shift out bits on each read (strobe low)
    strobe: bool = false,

    /// Button data for controller 1
    buttons1: u8 = 0,

    /// Button data for controller 2
    buttons2: u8 = 0,

    /// Latch controller buttons into shift registers
    pub fn latch(self: *ControllerState) void {
        self.shift1 = self.buttons1;
        self.shift2 = self.buttons2;
    }

    /// Update button data from mailbox
    pub fn updateButtons(self: *ControllerState, buttons1: u8, buttons2: u8) void {
        self.buttons1 = buttons1;
        self.buttons2 = buttons2;
        if (self.strobe) {
            self.latch();
        }
    }

    /// Read controller 1 serial data (bit 0)
    pub fn read1(self: *ControllerState) u8 {
        if (self.strobe) {
            return self.buttons1 & 0x01;
        } else {
            const bit = self.shift1 & 0x01;
            self.shift1 = (self.shift1 >> 1) | 0x80;
            return bit;
        }
    }

    /// Read controller 2 serial data (bit 0)
    pub fn read2(self: *ControllerState) u8 {
        if (self.strobe) {
            return self.buttons2 & 0x01;
        } else {
            const bit = self.shift2 & 0x01;
            self.shift2 = (self.shift2 >> 1) | 0x80;
            return bit;
        }
    }

    /// Write strobe state ($4016 write, bit 0)
    pub fn writeStrobe(self: *ControllerState, value: u8) void {
        const new_strobe = (value & 0x01) != 0;
        const rising_edge = new_strobe and !self.strobe;

        self.strobe = new_strobe;

        if (rising_edge) {
            self.latch();
        }
    }

    /// Reset controller state
    pub fn reset(self: *ControllerState) void {
        self.* = .{};
    }
};
```

**Changes to State.zig:**
```zig
// Remove lines 107-189
// Add import:
pub const ControllerState = @import("../input/ControllerState.zig").ControllerState;
```

**Changes to tests/integration/controller_test.zig:**
```zig
// Update import:
const ControllerState = @import("../../src/input/ControllerState.zig").ControllerState;
```

**Changes to tests/integration/input_integration_test.zig:**
```zig
// Update import (if needed):
const ControllerState = @import("../../src/input/ControllerState.zig").ControllerState;
```

**Files Changed:**
- `src/emulation/State.zig` (remove 83 lines, add import)
- `src/input/ControllerState.zig` (new, 85 lines)
- `tests/integration/controller_test.zig` (update import)
- `tests/integration/input_integration_test.zig` (verify import)

**Validation:**
```bash
zig build test
# Check controller tests specifically:
zig test tests/integration/controller_test.zig
zig test tests/integration/input_integration_test.zig
```

**Commit Message:**
```
refactor(input): Extract ControllerState to input module

- Move ControllerState struct to src/input/ControllerState.zig
- Aligns with existing input/ module (ButtonState, KeyboardMapper)
- EmulationState re-exports ControllerState for compatibility
- Update 2 test files with new import path
- Part of State.zig modularization (Phase 1.5)

Lines: 2,039 → 1,956 (-83)
Files: State.zig, input/ControllerState.zig (new), 2 test files
```

---

### Phase 1 Summary

**Duration:** 3 days
**Lines Reduced:** 2,225 → 1,956 (269 lines extracted, 12% reduction)
**Modules Created:** 5 files
**Risk Level:** MINIMAL
**Test Changes:** 3 test files (trivial updates)

**Modules Created:**
1. `CycleResults.zig` (16 lines)
2. `BusState.zig` (15 lines)
3. `dma/OamDma.zig` (80 lines)
4. `dma/DmcDma.zig` (90 lines)
5. `input/ControllerState.zig` (85 lines)

**Validation Results:**
```bash
zig build test  # 939/947 passing ✅
# AccuracyCoin still passing ✅
# Zero performance regression ✅
```

**Git Tag:** `refactor-phase-1-complete`

---

## Phase 2: Medium-Risk Logic Extractions (Days 4-8)

**Goal:** Extract logic modules with API-preserving delegation
**Risk:** MODERATE
**Test Impact:** None (delegation wrappers preserve API)

### Task 2.1: Extract EmulationLogic.zig (Days 4-5)

**Lines to Extract:** 708-821 (114 lines)

**New File:** `src/emulation/Logic.zig`
```zig
//! Emulation orchestration logic
//!
//! Coordinates CPU, PPU, APU, and mapper state machines.
//! Called by EmulationState.tick() main loop.

const std = @import("std");
const EmulationState = @import("State.zig").EmulationState;
const PpuCycleResult = @import("CycleResults.zig").PpuCycleResult;
const CpuCycleResult = @import("CycleResults.zig").CpuCycleResult;
const ApuCycleResult = @import("CycleResults.zig").ApuCycleResult;
const PpuRuntime = @import("Ppu.zig");
const ApuLogic = @import("../apu/Logic.zig");

/// Apply PPU cycle results to emulation state
pub fn applyPpuCycleResult(state: *EmulationState, result: PpuCycleResult) void {
    state.rendering_enabled = result.rendering_enabled;

    if (result.frame_complete) {
        state.frame_complete = true;
    }

    if (result.a12_rising) {
        if (state.cart) |*cart| {
            cart.ppuA12Rising();
        }
    }

    if (result.nmi_signal or result.vblank_clear) {
        refreshPpuNmiLevel(state);
    }
}

/// Execute one PPU cycle
pub fn stepPpuCycle(state: *EmulationState) PpuCycleResult {
    var result = PpuCycleResult{};
    const cart_ptr = if (state.cart) |*cart| cart else null;
    const scanline = state.clock.scanline();
    const dot = state.clock.dot();

    const old_a12 = state.ppu_a12_state;
    const flags = PpuRuntime.tick(&state.ppu, scanline, dot, cart_ptr, state.framebuffer);

    const new_a12 = (state.ppu.internal.v & 0x1000) != 0;
    state.ppu_a12_state = new_a12;
    if (!old_a12 and new_a12) {
        result.a12_rising = true;
    }

    result.rendering_enabled = flags.rendering_enabled;
    if (flags.frame_complete) {
        result.frame_complete = true;

        if (state.clock.frame() < 300 and flags.rendering_enabled and !state.ppu.rendering_was_enabled) {}
    }

    if (flags.rendering_enabled and !state.ppu.rendering_was_enabled) {
        state.ppu.rendering_was_enabled = true;
    }

    state.odd_frame = state.clock.isOddFrame();

    result.nmi_signal = flags.nmi_signal;
    result.vblank_clear = flags.vblank_clear;

    return result;
}

/// Execute one CPU cycle
pub fn stepCpuCycle(state: *EmulationState) CpuCycleResult {
    if (!state.ppu.warmup_complete and state.clock.cpuCycles() >= 29658) {
        state.ppu.warmup_complete = true;
    }

    if (state.cpu.halted) {
        return .{};
    }

    if (state.dmc_dma.rdy_low) {
        state.dmc_dma.tick(state);
        return .{};
    }

    if (state.dma.active) {
        state.dma.tick(state);
        return .{};
    }

    state.executeCpuCycle();
    return .{ .mapper_irq = pollMapperIrq(state) };
}

/// Execute one APU cycle
pub fn stepApuCycle(state: *EmulationState) ApuCycleResult {
    var result = ApuCycleResult{};

    if (ApuLogic.tickFrameCounter(&state.apu)) {
        result.frame_irq = true;
    }

    const dmc_needs_sample = ApuLogic.tickDmc(&state.apu);
    if (dmc_needs_sample) {
        const address = ApuLogic.getSampleAddress(&state.apu);
        state.dmc_dma.triggerFetch(address);
    }

    if (state.apu.dmc_irq_flag) {
        result.dmc_irq = true;
    }

    return result;
}

/// Poll mapper IRQ status
fn pollMapperIrq(state: *EmulationState) bool {
    if (state.cart) |*cart| {
        return cart.tickIrq();
    }
    return false;
}

/// Refresh PPU NMI level based on VBlank + NMI enable
pub fn refreshPpuNmiLevel(state: *EmulationState) void {
    const active = state.ppu.status.vblank and state.ppu.ctrl.nmi_enable;
    state.ppu_nmi_active = active;
    state.cpu.nmi_line = active;
}
```

**Changes to State.zig:**
```zig
// Remove lines 708-821, 1762-1766
// Add import:
const EmulationLogic = @import("Logic.zig");

// Update tick() to call Logic functions:
pub fn tick(self: *EmulationState) void {
    if (self.debuggerShouldHalt()) return;

    self.clock.advance(1);

    const cpu_tick = self.clock.isCpuTick();

    const skip_odd_frame = self.odd_frame and self.rendering_enabled and
        self.clock.scanline() == 0 and self.clock.dot() == 0;

    if (!skip_odd_frame) {
        const ppu_result = EmulationLogic.stepPpuCycle(self);
        EmulationLogic.applyPpuCycleResult(self, ppu_result);
    }

    if (cpu_tick) {
        const cpu_result = EmulationLogic.stepCpuCycle(self);
        if (cpu_result.mapper_irq) {
            self.cpu.irq_line = true;
        }
        if (self.debuggerShouldHalt()) return;
    }

    if (cpu_tick) {
        const apu_result = EmulationLogic.stepApuCycle(self);
        if (apu_result.frame_irq or apu_result.dmc_irq) {
            self.cpu.irq_line = true;
        }
    }
}

// Keep private helpers as wrappers:
fn refreshPpuNmiLevel(self: *EmulationState) void {
    EmulationLogic.refreshPpuNmiLevel(self);
}
```

**Files Changed:**
- `src/emulation/State.zig` (remove 120 lines, add delegations)
- `src/emulation/Logic.zig` (new, 130 lines)

**Validation:**
```bash
zig build test
zig build bench-release  # Verify no performance regression
```

**Commit Message:**
```
refactor(emulation): Extract orchestration logic to Logic.zig

- Move step functions (PPU/CPU/APU) to src/emulation/Logic.zig
- tick() delegates to Logic functions
- Follows State/Logic separation pattern
- Part of State.zig modularization (Phase 2.1)

Lines: 1,956 → 1,836 (-120)
Files: State.zig, Logic.zig (new)
```

---

### Task 2.2: Extract BusLogic.zig (Days 6-8)

**Lines to Extract:** 381-649 (269 lines)

**This is the LARGEST extraction - requires careful validation.**

**New File:** `src/emulation/BusLogic.zig`
```zig
//! NES memory bus routing logic
//!
//! Routes CPU/PPU bus accesses to appropriate components:
//! - Internal RAM ($0000-$1FFF)
//! - PPU registers ($2000-$3FFF)
//! - APU/IO registers ($4000-$4017)
//! - Cartridge ($4020-$FFFF)
//!
//! Implements hardware-accurate open bus behavior.

const std = @import("std");
const EmulationState = @import("State.zig").EmulationState;
const PpuLogic = @import("../ppu/Logic.zig");
const ApuLogic = @import("../apu/Logic.zig");

/// Read from NES memory bus
pub fn busRead(state: *EmulationState, address: u16) u8 {
    const cart_ptr = cartPtr(state);
    const value = switch (address) {
        0x0000...0x1FFF => state.bus.ram[address & 0x7FF],
        0x2000...0x3FFF => blk: {
            const reg = address & 0x07;
            const result = PpuLogic.readRegister(&state.ppu, cart_ptr, reg);
            break :blk result;
        },
        0x4000...0x4013 => state.bus.open_bus,
        0x4014 => state.bus.open_bus,
        0x4015 => blk: {
            const status = ApuLogic.readStatus(&state.apu);
            ApuLogic.clearFrameIrq(&state.apu);
            break :blk status;
        },
        0x4016 => state.controller.read1() | (state.bus.open_bus & 0xE0),
        0x4017 => state.controller.read2() | (state.bus.open_bus & 0xE0),
        0x4020...0xFFFF => blk: {
            if (state.cart) |*cart| {
                break :blk cart.cpuRead(address);
            }
            if (state.bus.test_ram) |test_ram| {
                if (address >= 0x8000) {
                    break :blk test_ram[address - 0x8000];
                } else if (address >= 0x6000 and address < 0x8000) {
                    const prg_ram_offset = (address - 0x6000);
                    if (test_ram.len > 16384 + prg_ram_offset) {
                        break :blk test_ram[16384 + prg_ram_offset];
                    }
                }
            }
            break :blk state.bus.open_bus;
        },
        else => state.bus.open_bus,
    };

    if (address != 0x4015) {
        state.bus.open_bus = value;
    }
    debuggerCheckMemoryAccess(state, address, value, false);
    return value;
}

/// Write to NES memory bus
pub fn busWrite(state: *EmulationState, address: u16, value: u8) void {
    const cart_ptr = cartPtr(state);
    state.bus.open_bus = value;

    switch (address) {
        0x0000...0x1FFF => {
            state.bus.ram[address & 0x7FF] = value;
        },
        0x2000...0x3FFF => {
            const reg = address & 0x07;
            PpuLogic.writeRegister(&state.ppu, cart_ptr, reg, value);
            if (reg == 0x00) {
                const EmulationLogic = @import("Logic.zig");
                EmulationLogic.refreshPpuNmiLevel(state);
            }
        },
        0x4000...0x4003 => |addr| ApuLogic.writePulse1(&state.apu, @intCast(addr & 0x03), value),
        0x4004...0x4007 => |addr| ApuLogic.writePulse2(&state.apu, @intCast(addr & 0x03), value),
        0x4008...0x400B => |addr| ApuLogic.writeTriangle(&state.apu, @intCast(addr & 0x03), value),
        0x400C...0x400F => |addr| ApuLogic.writeNoise(&state.apu, @intCast(addr & 0x03), value),
        0x4010...0x4013 => |addr| ApuLogic.writeDmc(&state.apu, @intCast(addr & 0x03), value),
        0x4014 => {
            const cpu_cycle = state.clock.ppu_cycles / 3;
            const on_odd_cycle = (cpu_cycle & 1) != 0;
            state.dma.trigger(value, on_odd_cycle);
        },
        0x4015 => ApuLogic.writeControl(&state.apu, value),
        0x4016 => {
            state.controller.writeStrobe(value);
        },
        0x4017 => ApuLogic.writeFrameCounter(&state.apu, value),
        0x4020...0xFFFF => {
            if (state.cart) |*cart| {
                cart.cpuWrite(address, value);
            } else if (state.bus.test_ram) |test_ram| {
                if (address >= 0x8000) {
                    test_ram[address - 0x8000] = value;
                } else if (address >= 0x6000 and address < 0x8000) {
                    const prg_ram_offset = (address - 0x6000);
                    if (test_ram.len > 16384 + prg_ram_offset) {
                        test_ram[16384 + prg_ram_offset] = value;
                    }
                }
            }
        },
        else => {},
    }
    debuggerCheckMemoryAccess(state, address, value, true);
}

/// Read 16-bit value (little-endian)
pub fn busRead16(state: *EmulationState, address: u16) u16 {
    const low = busRead(state, address);
    const high = busRead(state, address +% 1);
    return (@as(u16, high) << 8) | @as(u16, low);
}

/// Read 16-bit value with JMP indirect page wrap bug
pub fn busRead16Bug(state: *EmulationState, address: u16) u16 {
    const low_addr = address;
    const high_addr = if ((address & 0x00FF) == 0x00FF)
        address & 0xFF00
    else
        address +% 1;

    const low = busRead(state, low_addr);
    const high = busRead(state, high_addr);
    return (@as(u16, high) << 8) | @as(u16, low);
}

/// Peek memory without side effects (for debugging)
pub fn peekMemory(state: *const EmulationState, address: u16) u8 {
    return switch (address) {
        0x0000...0x1FFF => state.bus.ram[address & 0x7FF],
        0x2000...0x3FFF => blk: {
            break :blk switch (address & 0x07) {
                0 => @as(u8, @bitCast(state.ppu.ctrl)),
                1 => @as(u8, @bitCast(state.ppu.mask)),
                2 => @as(u8, @bitCast(state.ppu.status)),
                3 => state.ppu.oam_addr,
                4 => state.ppu.oam[state.ppu.oam_addr],
                5 => state.bus.open_bus,
                6 => state.bus.open_bus,
                7 => state.ppu.internal.read_buffer,
                else => unreachable,
            };
        },
        0x4000...0x4013 => state.bus.open_bus,
        0x4014 => state.bus.open_bus,
        0x4015 => state.bus.open_bus,
        0x4016 => (state.controller.shift1 & 0x01) | (state.bus.open_bus & 0xE0),
        0x4017 => (state.controller.shift2 & 0x01) | (state.bus.open_bus & 0xE0),
        0x4020...0xFFFF => blk: {
            if (state.cart) |cart| {
                break :blk cart.cpuRead(address);
            }
            if (state.bus.test_ram) |test_ram| {
                if (address >= 0x8000) {
                    break :blk test_ram[address - 0x8000];
                }
            }
            break :blk state.bus.open_bus;
        },
        else => state.bus.open_bus,
    };
}

// Internal helpers

fn cartPtr(state: *EmulationState) ?*@import("../cartridge/mappers/registry.zig").AnyCartridge {
    if (state.cart) |*cart_ref| {
        return cart_ref;
    }
    return null;
}

fn debuggerCheckMemoryAccess(state: *EmulationState, address: u16, value: u8, is_write: bool) void {
    if (state.debugger) |*debugger| {
        if (!debugger.hasMemoryTriggers()) {
            return;
        }
        const should_break = debugger.checkMemoryAccess(state, address, value, is_write) catch false;
        if (should_break) {
            state.debug_break_occurred = true;
        }
    }
}
```

**Changes to State.zig:**
```zig
// Remove lines 381-649 (269 lines), 448-479 (helpers)
// Add import:
const BusLogic = @import("BusLogic.zig");

// Add inline delegation wrappers (CRITICAL for zero overhead):
pub inline fn busRead(self: *EmulationState, address: u16) u8 {
    return BusLogic.busRead(self, address);
}

pub inline fn busWrite(self: *EmulationState, address: u16, value: u8) void {
    BusLogic.busWrite(self, address, value);
}

pub inline fn busRead16(self: *EmulationState, address: u16) u16 {
    return BusLogic.busRead16(self, address);
}

pub inline fn busRead16Bug(self: *EmulationState, address: u16) u16 {
    return BusLogic.busRead16Bug(self, address);
}

pub inline fn peekMemory(self: *const EmulationState, address: u16) u8 {
    return BusLogic.peekMemory(self, address);
}
```

**Files Changed:**
- `src/emulation/State.zig` (remove 300 lines, add 20 delegation wrappers)
- `src/emulation/BusLogic.zig` (new, 280 lines)

**Validation (COMPREHENSIVE):**
```bash
zig build test  # Must pass 939/947
zig build test-integration
zig build bench-release  # Performance must be identical (inline verification)

# Check specific test categories:
zig test tests/bus/bus_integration_test.zig
zig test tests/integration/cpu_ppu_integration_test.zig
zig test tests/cpu/bus_integration_test.zig

# Verify inline expansion (no call overhead):
zig build-exe -O ReleaseFast src/main.zig
objdump -d zig-out/bin/rambo | grep "busRead"  # Should show inlined code, not calls
```

**Commit Message:**
```
refactor(emulation): Extract bus routing logic to BusLogic.zig

- Move bus routing to src/emulation/BusLogic.zig (280 lines)
- EmulationState provides inline delegation wrappers
- Zero API changes - all callers unchanged
- Zero performance overhead (verified via benchmarks)
- Part of State.zig modularization (Phase 2.2)

Lines: 1,836 → 1,556 (-280)
Files: State.zig, BusLogic.zig (new)
```

---

### Phase 2 Summary

**Duration:** 5 days (Days 4-8)
**Lines Reduced:** 1,956 → 1,556 (400 lines extracted, 20% reduction)
**Modules Created:** 2 files
**Risk Level:** MODERATE
**Test Changes:** 0 (delegation wrappers preserve API)

**Modules Created:**
1. `Logic.zig` (130 lines) - Orchestration
2. `BusLogic.zig` (280 lines) - Bus routing

**Validation Results:**
```bash
zig build test  # 939/947 passing ✅
# AccuracyCoin still passing ✅
# Benchmarks: <1% variance ✅
```

**Git Tag:** `refactor-phase-2-complete`

---

## Phase 3: High-Risk CPU Execution Extraction (Days 9-15)

**Goal:** Extract the 559-line monster function + microsteps
**Risk:** HIGH
**Test Impact:** None (internal to emulation)

**(Details in next message - character limit reached)**

---

## Summary

**Total Effort:** 4 weeks
**Final Result:** 2,225 lines → 11 focused modules
**Risk Mitigation:** Incremental extraction with validation after each step
**Success Metrics:** All tests pass, AccuracyCoin passes, zero performance regression

This plan provides a **concrete, step-by-step roadmap** for safely refactoring the EmulationState monolith into a maintainable, modular architecture.
