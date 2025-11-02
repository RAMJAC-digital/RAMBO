---
name: h-fix-oam-nmi-accuracy
branch: fix/h-fix-oam-nmi-accuracy
status: pending
created: 2025-11-02
---

# Fix OAM and NMI Accuracy

## Problem/Goal
Improve the accuracy of OAM (Object Attribute Memory) and NMI (Non-Maskable Interrupt) interactions, particularly focusing on timing edge cases and DMA behavior that may be causing rendering issues in commercial ROMs.

## Success Criteria
- [ ] **Test audit against hardware spec** - Verify ALL OAM/NMI/VBlank tests match nesdev.org hardware behavior (assume existing tests are incorrect)
- [ ] **PPU VBlank timing corrected** - VBlank flag timing verified against hardware specification
- [ ] **AccuracyCoin OAM corruption test** - Minimum: no hang; Goal: passing
- [ ] **AccuracyCoin NMI CPU tests** - All NMI CPU tests passing (currently all failing)
- [ ] **AccuracyCoin OAM tests** - All OAM tests passing (currently all failing)
- [ ] **OAM DMA timing verified** - 513/514 cycle timing per nesdev.org hardware spec
- [ ] **DMC DMA conflicts verified** - Byte duplication behavior when DMC interrupts OAM DMA (hardware spec)
- [ ] **NMI edge detection verified** - NMI timing during OAM DMA matches hardware behavior
- [ ] **Test suite regression check** - All currently passing tests (1023/1041) still pass
- [ ] **Commercial ROM validation** - Test improvements against SMB3, Kirby's Adventure

## Context Manifest

### Hardware Specification: OAM DMA, NMI, and VBlank Timing

**CRITICAL: This task focuses on hardware timing accuracy for OAM DMA, NMI generation, and VBlank flag behavior. All implementations must match actual NES hardware behavior per nesdev.org specifications.**

According to NES hardware documentation, OAM DMA, NMI generation, and VBlank timing interact in complex ways that games depend on for correct operation. Getting these timing relationships wrong causes rendering glitches, missing animations, and hung execution (as seen in AccuracyCoin tests).

#### Hardware Timing Specifications

**OAM DMA Timing** (https://www.nesdev.org/wiki/PPU_OAM#DMA):
- Triggered by write to $4014 (OAMDMA register)
- Takes 513 CPU cycles on even-cycle start, 514 on odd-cycle start
- 1 alignment cycle (if odd start) + 256 read/write pairs (512 cycles)
- Transfers 256 bytes from $XX00-$XXFF to PPU OAM ($2004)
- **CRITICAL:** Can be interrupted by DMC DMA (time-sharing behavior)

**DMC DMA Timing** (https://www.nesdev.org/wiki/APU_DMC):
- DMC sample fetch stalls CPU via RDY line for 4 cycles
- Cycle 1 (stall=4): Halt/alignment - OAM PAUSES
- Cycle 2 (stall=3): Dummy read - OAM CONTINUES (time-sharing)
- Cycle 3 (stall=2): Alignment - OAM CONTINUES (time-sharing)
- Cycle 4 (stall=1): Actual DMC read - OAM PAUSES
- Post-DMC: OAM needs 1 additional alignment cycle
- **CRITICAL:** DMC and OAM time-share during dummy/alignment cycles

**VBlank Timing** (https://www.nesdev.org/wiki/PPU_frame_timing):
- VBlank flag set at scanline 241, dot 1 (start of VBlank period)
- VBlank flag cleared at scanline 261, dot 1 (pre-render scanline)
- VBlank flag also cleared by reading $2002 (PPUSTATUS)
- **CRITICAL:** Race condition - reading $2002 at exact cycle VBlank sets suppresses NMI but clears flag normally

**NMI Generation** (https://www.nesdev.org/wiki/NMI):
- NMI is edge-triggered (falling edge on /NMI line)
- NMI fires when: VBlank flag sets AND PPUCTRL.7 (NMI enable) is set
- NMI line stays asserted while VBlank active AND NMI enabled
- **CRITICAL:** Edge detection prevents double-triggering during same VBlank
- **CRITICAL:** Race suppression - $2002 read at VBlank set cycle suppresses NMI
- Games can cause multiple NMIs by toggling PPUCTRL.7 during VBlank
- NMI timing during OAM DMA follows standard interrupt latching

**Hardware Quirks & Edge Cases:**

1. **CPU/PPU Sub-Cycle Ordering** (https://www.nesdev.org/wiki/PPU_rendering):
   - Within a single PPU cycle, operations execute in order:
     1. CPU read operations
     2. CPU write operations
     3. PPU flag updates (VBlank set, sprite evaluation, etc.)
   - **Impact:** Reading $2002 at exact VBlank set cycle reads 0 (flag not set yet)

2. **DMC/OAM Time-Sharing** (https://www.nesdev.org/wiki/DMA#DMC_DMA_during_OAM_DMA):
   - OAM continues during DMC dummy/alignment cycles
   - No byte duplication - OAM reads sequential addresses even when interrupted
   - Post-DMC alignment cycle required to restore OAM get/put rhythm

3. **NTSC DMC Corruption** (NTSC 2A03 only):
   - CPU repeats last read during DMC idle cycles (stall=4,3,2)
   - If last read was MMIO ($2000-$5FFF), side effects repeat
   - Controllers ($4016-$4017): Shift register advances multiple times
   - PPU ($2002): VBlank flag could be cleared multiple times
   - PAL 2A07: Bug fixed, no repeat reads

### Current Implementation: Hardware-Accurate DMA Coordination

The codebase implements OAM/DMC DMA using a **functional pattern** following the VBlankLedger approach (timestamp-based, external state management). All timing critical logic is centralized in `src/emulation/cpu/execution.zig`.

**State Organization:**

**OAM DMA State** (`src/emulation/state/peripherals/OamDma.zig`):
```zig
pub const OamDma = struct {
    active: bool = false,         // Transfer in progress
    source_page: u8 = 0,          // Page $XX00-$XXFF
    current_offset: u8 = 0,       // Current byte (0-255)
    current_cycle: u16 = 0,       // Cycle counter (0-512)
    needs_alignment: bool = false, // Odd cycle start flag
    temp_value: u8 = 0,           // Read buffer (read→write)

    pub fn trigger(self: *OamDma, page: u8, on_odd_cycle: bool) void;
    pub fn reset(self: *OamDma) void;
};
```

**DMC DMA State** (`src/emulation/state/peripherals/DmcDma.zig`):
```zig
pub const DmcDma = struct {
    rdy_low: bool = false,             // RDY line active (CPU stalled)
    transfer_complete: bool = false,    // Completion signal for execution.zig
    stall_cycles_remaining: u8 = 0,    // Countdown (4→3→2→1→0)
    sample_address: u16 = 0,           // Address to fetch from
    sample_byte: u8 = 0,               // Fetched sample
    last_read_address: u16 = 0,        // For NTSC corruption

    pub fn triggerFetch(self: *DmcDma, address: u16) void;
    pub fn reset(self: *DmcDma) void;
};
```

**DMA Interaction Ledger** (`src/emulation/DmaInteractionLedger.zig`):
```zig
pub const DmaInteractionLedger = struct {
    // Edge detection timestamps (pattern: VBlankLedger)
    last_dmc_active_cycle: u64 = 0,      // DMC rising edge
    last_dmc_inactive_cycle: u64 = 0,    // DMC falling edge
    oam_pause_cycle: u64 = 0,            // OAM paused by DMC
    oam_resume_cycle: u64 = 0,           // OAM resumed after DMC

    // Post-DMC alignment flag
    needs_alignment_after_dmc: bool = false,

    pub fn reset(self: *DmaInteractionLedger) void;
};
```

**VBlank Ledger** (`src/emulation/VBlankLedger.zig`):
```zig
pub const VBlankLedger = struct {
    last_set_cycle: u64 = 0,     // VBlank set (scanline 241, dot 1)
    last_clear_cycle: u64 = 0,   // VBlank cleared by timing (scanline 261, dot 1)
    last_read_cycle: u64 = 0,    // $2002 read timestamp
    last_race_cycle: u64 = 0,    // Race read (same cycle as set)

    pub fn isActive(self: VBlankLedger) bool; // Hardware VBlank active
    pub fn isFlagVisible(self: VBlankLedger) bool; // Flag visible to CPU
    pub fn hasRaceSuppression(self: VBlankLedger) bool; // NMI suppressed
    pub fn reset(self: *VBlankLedger) void;
};
```

**CPU Interrupt State** (`src/cpu/State.zig` lines 159-167):
```zig
// In CpuState struct:
pending_interrupt: InterruptType = .none,   // .nmi, .irq, .reset, .brk
nmi_line: bool = false,                     // NMI input (level)
nmi_edge_detected: bool = false,            // Edge-triggered flag
nmi_enable_prev: bool = false,              // Previous PPUCTRL.7 for edge detection
nmi_vblank_set_cycle: u64 = 0,             // VBlank that triggered last NMI (double-trigger prevention)
irq_line: bool = false,                     // IRQ input (level-triggered)
```

**Logic Flow:**

**OAM DMA Execution** (`src/emulation/dma/logic.zig:tickOamDma`):
```zig
pub fn tickOamDma(state: anytype) void {
    // Pure function - all state passed explicitly

    // Check 1: DMC stalling OAM?
    const dmc_is_stalling_oam = state.dmc_dma.rdy_low and
        (state.dmc_dma.stall_cycles_remaining == 4 or  // Halt cycle
         state.dmc_dma.stall_cycles_remaining == 1);   // Read cycle
    if (dmc_is_stalling_oam) return; // Time-sharing: continue during stall==3,2

    // Check 2: Post-DMC alignment?
    if (state.dma_interaction_ledger.needs_alignment_after_dmc) {
        state.dma_interaction_ledger.needs_alignment_after_dmc = false;
        return; // Pure wait cycle
    }

    // Check 3: Pre-transfer alignment?
    const effective_cycle = if (dma.needs_alignment)
        @as(i32, @intCast(dma.current_cycle)) - 1
    else
        @as(i32, @intCast(dma.current_cycle));
    if (effective_cycle < 0) {
        dma.current_cycle += 1;
        return;
    }

    // Check 4: Completed?
    if (effective_cycle >= 512) {
        dma.reset();
        state.dma_interaction_ledger.reset();
        return;
    }

    // Check 5: Read or write? (cycle parity)
    const is_read_cycle = @rem(effective_cycle, 2) == 0;
    if (is_read_cycle) {
        // READ
        const addr = (@as(u16, dma.source_page) << 8) | dma.current_offset;
        dma.temp_value = state.busRead(addr);
    } else {
        // WRITE
        state.ppu.oam[state.ppu.oam_addr] = dma.temp_value;
        state.ppu.oam_addr +%= 1;
        dma.current_offset +%= 1;
    }
    dma.current_cycle += 1;
}
```

**DMC DMA Execution** (`src/emulation/dma/logic.zig:tickDmcDma`):
```zig
pub fn tickDmcDma(state: anytype) void {
    const cycle = state.dmc_dma.stall_cycles_remaining;
    if (cycle == 0) {
        state.dmc_dma.transfer_complete = true;
        return;
    }

    state.dmc_dma.stall_cycles_remaining -= 1;

    if (cycle == 1) {
        // Final cycle: Fetch sample
        const address = state.dmc_dma.sample_address;
        state.dmc_dma.sample_byte = state.busRead(address);
        ApuLogic.loadSampleByte(&state.apu, state.dmc_dma.sample_byte);

        // Complete: clear rdy_low, signal completion
        state.dmc_dma.rdy_low = false;
        state.dmc_dma.transfer_complete = true;
        return;
    }

    // Idle cycles (2-4): NTSC corruption (repeat last read)
    const has_dpcm_bug = switch (state.config.cpu.variant) {
        .rp2a03e, .rp2a03g, .rp2a03h => true, // NTSC
        .rp2a07 => false, // PAL
    };
    if (has_dpcm_bug) {
        _ = state.busRead(state.dmc_dma.last_read_address);
    }
}
```

**DMA Coordination** (`src/emulation/cpu/execution.zig:stepCycle` lines 126-180):

All DMA coordination and timestamp management happens in execution.zig (external state management pattern):

```zig
pub fn stepCycle(state: anytype) CpuCycleResult {
    // ... (warmup, NMI line management - lines 78-120) ...

    // DMC completion handling (external state management)
    if (state.dmc_dma.transfer_complete) {
        state.dmc_dma.transfer_complete = false;
        state.dma_interaction_ledger.last_dmc_inactive_cycle = state.clock.ppu_cycles;

        // Set OAM alignment flag if it was paused
        const was_paused = state.dma_interaction_ledger.oam_pause_cycle >
            state.dma_interaction_ledger.oam_resume_cycle;
        if (was_paused and state.dma.active) {
            state.dma_interaction_ledger.oam_resume_cycle = state.clock.ppu_cycles;
            state.dma_interaction_ledger.needs_alignment_after_dmc = true;
        }
    }

    // DMC rising edge detection
    const dmc_was_active = (state.dma_interaction_ledger.last_dmc_active_cycle >
        state.dma_interaction_ledger.last_dmc_inactive_cycle);
    const dmc_is_active = state.dmc_dma.rdy_low;

    if (dmc_is_active and !dmc_was_active) {
        state.dma_interaction_ledger.last_dmc_active_cycle = state.clock.ppu_cycles;
        if (state.dma.active) {
            state.dma_interaction_ledger.oam_pause_cycle = state.clock.ppu_cycles;
        }
    }

    // Execute DMAs (time-sharing: both can run same cycle)
    if (dmc_is_active) {
        state.tickDmcDma();
        // Don't return - OAM can continue
    }

    if (state.dma.active) {
        state.tickDma();
        return .{};
    }

    if (dmc_is_active) {
        return .{};
    }

    // Normal CPU execution
    executeCycle(state, current_vblank_set_cycle);
    return .{};
}
```

**NMI Line Management** (`src/emulation/cpu/execution.zig:stepCycle` lines 93-112):
```zig
// NMI line reflects VBlank flag state (when NMI enabled in PPUCTRL)
const vblank_flag_visible = state.vblank_ledger.isFlagVisible();
const race_suppression = state.vblank_ledger.hasRaceSuppression();
const nmi_line_should_assert = vblank_flag_visible and
    state.ppu.ctrl.nmi_enable and
    !race_suppression;

state.cpu.nmi_line = nmi_line_should_assert;

// Track current VBlank for double-trigger suppression
const vblank_active = state.vblank_ledger.isActive();
const current_vblank_set_cycle = if (vblank_active)
    state.vblank_ledger.last_set_cycle
else
    0;
```

**NMI Edge Detection** (`src/cpu/Logic.zig:checkInterrupts` lines 56-75):
```zig
pub fn checkInterrupts(state: *CpuState, vblank_set_cycle: u64) void {
    // NMI edge detection (falling edge)
    const nmi_prev = state.nmi_edge_detected;
    state.nmi_edge_detected = state.nmi_line;

    if (state.nmi_line and !nmi_prev) {
        // Double-trigger suppression
        const same_vblank = (vblank_set_cycle == state.nmi_vblank_set_cycle and
                             vblank_set_cycle != 0);

        if (!same_vblank) {
            state.pending_interrupt = .nmi;
            state.nmi_vblank_set_cycle = vblank_set_cycle;
        }
    }

    // IRQ level-triggered (if not masked)
    if (state.irq_line and !state.p.i) {
        state.pending_interrupt = .irq;
    }
}
```

**VBlank Timestamp Updates** (`src/emulation/State.zig:tick` via `applyPpuCycleResult`):
```zig
// VBlank flag set (scanline 241, dot 1)
if (ppu_result.set_vblank) {
    self.vblank_ledger.last_set_cycle = self.clock.ppu_cycles;
}

// VBlank flag cleared by timing (scanline 261, dot 1)
if (ppu_result.clear_vblank) {
    self.vblank_ledger.last_clear_cycle = self.clock.ppu_cycles;
}
```

**PPUSTATUS Read Handling** (`src/ppu/logic/registers.zig:readRegister` lines 80-106):
```zig
0x0002 => {
    // $2002 PPUSTATUS
    const vblank_active = vblank_ledger.isFlagVisible();

    const value = buildStatusByte(
        state.status.sprite_overflow,
        state.status.sprite_0_hit,
        vblank_active,
        state.open_bus.value,
    );

    // Signal that $2002 read occurred (EmulationState updates ledger)
    result.read_2002 = true;

    // Reset write toggle (local PPU state)
    state.internal.resetToggle();

    // Update open bus
    state.open_bus.write(value);

    result.value = value;
}
```

**CPU/PPU Sub-Cycle Ordering** (`src/emulation/State.zig:tick` lines 617-699):

**LOCKED BEHAVIOR** - CPU operations execute BEFORE PPU flag updates within same PPU cycle:

```zig
pub fn tick(self: *EmulationState) void {
    // ... (clock advancement, mapper IRQ poll) ...

    // Step 1: CPU execution (including DMA, $2002 reads)
    const cpu_result = self.stepCpuCycle();

    // Step 2: Handle $2002 read (before PPU flag updates)
    if (cpu_result.read_2002) {
        // Race detection: Is this read at exact VBlank set cycle?
        const is_race = (self.clock.ppu_cycles == self.vblank_ledger.last_set_cycle);

        if (is_race) {
            self.vblank_ledger.last_race_cycle = self.clock.ppu_cycles;
        }

        // Record read timestamp (clears flag)
        self.vblank_ledger.last_read_cycle = self.clock.ppu_cycles;
    }

    // Step 3: PPU tick (flag updates happen here)
    const ppu_result = self.stepPpuCycle();

    // Step 4: Apply PPU results (VBlank timestamps)
    self.applyPpuCycleResult(ppu_result);

    // ... (APU, frame completion) ...
}
```

This ordering ensures that $2002 reads at VBlank set cycle see flag=0 (not set yet), matching hardware behavior.

### State/Logic Abstraction Plan

**Current Architecture:**
- Pure functional DMA logic (`dma/logic.zig`) operates on state pointers
- External state management in `execution.zig` (timestamp updates, flag management)
- Timestamp-based edge detection (no boolean state machines)
- All mutations explicit through `state.*` parameters

**State Changes Required:**

No new state fields needed - current structures are hardware-complete.

**Potential Issues to Investigate:**

1. **OAM DMA timing accuracy:**
   - Verify 513/514 cycle timing with alignment
   - Check completion logic (cycle >= 512)
   - Verify time-sharing during DMC cycles

2. **DMC/OAM interaction accuracy:**
   - Verify OAM pauses only during stall==4 and stall==1
   - Verify OAM continues during stall==3 and stall==2
   - Verify post-DMC alignment cycle consumed
   - Check for byte duplication bugs (should NOT happen)

3. **NMI timing accuracy:**
   - Verify NMI edge detection during OAM DMA
   - Verify NMI fires on VBlank set when PPUCTRL.7=1
   - Verify double-trigger suppression works
   - Verify race suppression ($2002 read at VBlank set)

4. **VBlank flag timing:**
   - Verify flag set at scanline 241, dot 1
   - Verify flag cleared at scanline 261, dot 1
   - Verify flag cleared by $2002 read
   - Verify race condition handling (same-cycle read)

5. **Test expectations vs hardware:**
   - ⚠️ **CRITICAL:** Existing tests may have incorrect expectations
   - Verify ALL test expectations against nesdev.org specifications
   - Flag tests that contradict hardware documentation
   - Update test expectations to match hardware, NOT perpetuate bugs

### Readability Guidelines

**For This Investigation:**
- Prioritize obvious correctness over clever optimizations
- Add extensive comments explaining hardware behavior (cite nesdev.org)
- Use clear variable names that match hardware terminology
- Break complex timing checks into well-named helper functions
- Example: `isVBlankSetCycle()` more readable than inline timestamp comparison

**Code Structure:**
- Separate timing verification functions from correction logic
- Comment each check with hardware specification reference
- Explain WHY each timing relationship exists (hardware constraints)
- Document edge cases with nesdev.org citations

### Technical Reference

#### Hardware Citations

**Primary References:**
- OAM DMA: https://www.nesdev.org/wiki/PPU_OAM#DMA
- DMC DMA: https://www.nesdev.org/wiki/APU_DMC
- DMC/OAM Conflict: https://www.nesdev.org/wiki/DMA#DMC_DMA_during_OAM_DMA
- NMI: https://www.nesdev.org/wiki/NMI
- PPU Frame Timing: https://www.nesdev.org/wiki/PPU_frame_timing
- PPU Registers: https://www.nesdev.org/wiki/PPU_registers
- PPUSTATUS: https://www.nesdev.org/wiki/PPU_registers#PPUSTATUS
- PPUCTRL: https://www.nesdev.org/wiki/PPU_registers#PPUCTRL

**Forum Discussions:**
- CPU/PPU sub-cycle ordering: https://forums.nesdev.org/viewtopic.php?t=6186
- VBlank race condition: https://forums.nesdev.org/viewtopic.php?t=8216

#### Related State Structures

**OAM DMA State:**
```zig
// src/emulation/state/peripherals/OamDma.zig
pub const OamDma = struct {
    active: bool,
    source_page: u8,
    current_offset: u8,
    current_cycle: u16,
    needs_alignment: bool,
    temp_value: u8,
};
```

**DMC DMA State:**
```zig
// src/emulation/state/peripherals/DmcDma.zig
pub const DmcDma = struct {
    rdy_low: bool,
    transfer_complete: bool,
    stall_cycles_remaining: u8,
    sample_address: u16,
    sample_byte: u8,
    last_read_address: u16,
};
```

**DMA Interaction Ledger:**
```zig
// src/emulation/DmaInteractionLedger.zig
pub const DmaInteractionLedger = struct {
    last_dmc_active_cycle: u64,
    last_dmc_inactive_cycle: u64,
    oam_pause_cycle: u64,
    oam_resume_cycle: u64,
    needs_alignment_after_dmc: bool,

    pub fn reset(self: *DmaInteractionLedger) void;
};
```

**VBlank Ledger:**
```zig
// src/emulation/VBlankLedger.zig
pub const VBlankLedger = struct {
    last_set_cycle: u64,
    last_clear_cycle: u64,
    last_read_cycle: u64,
    last_race_cycle: u64,

    pub fn isActive(self: VBlankLedger) bool;
    pub fn isFlagVisible(self: VBlankLedger) bool;
    pub fn hasRaceSuppression(self: VBlankLedger) bool;
    pub fn reset(self: *VBlankLedger) void;
};
```

**CPU Interrupt State:**
```zig
// src/cpu/State.zig
pending_interrupt: InterruptType, // .none, .nmi, .irq, .reset, .brk
nmi_line: bool,                   // NMI input level
nmi_edge_detected: bool,          // Edge-triggered flag
nmi_enable_prev: bool,            // Previous PPUCTRL.7
nmi_vblank_set_cycle: u64,       // VBlank that triggered last NMI
irq_line: bool,                   // IRQ input level
```

#### Related Logic Functions

**DMA Execution:**
```zig
// src/emulation/dma/logic.zig
pub fn tickOamDma(state: anytype) void;  // Lines 21-84
pub fn tickDmcDma(state: anytype) void;  // Lines 97-134
```

**DMA Coordination:**
```zig
// src/emulation/cpu/execution.zig
pub fn stepCycle(state: anytype) CpuCycleResult; // Lines 77-188 (DMA coordination lines 126-180)
pub fn executeCycle(state: anytype, vblank_set_cycle: u64) void; // Lines 202-end
```

**NMI Management:**
```zig
// src/cpu/Logic.zig
pub fn checkInterrupts(state: *CpuState, vblank_set_cycle: u64) void; // Lines 56-81
```

**VBlank Management:**
```zig
// src/emulation/State.zig
pub fn tick(self: *EmulationState) void; // Lines 577-631 (sub-cycle ordering lines 617-699)
fn applyPpuCycleResult(self: *EmulationState, result: PpuCycleResult) void;
```

**PPU Register I/O:**
```zig
// src/ppu/logic/registers.zig
pub fn readRegister(
    state: *PpuState,
    cart: ?*AnyCartridge,
    address: u16,
    vblank_ledger: VBlankLedger,
) PpuReadResult; // Lines 60-175 ($2002 handling lines 80-106)

pub fn buildStatusByte(
    sprite_overflow: bool,
    sprite_0_hit: bool,
    vblank_flag: bool,
    data_bus_latch: u8,
) u8; // Lines 31-52
```

#### File Locations

**Core Implementation:**
- OAM DMA state: `src/emulation/state/peripherals/OamDma.zig`
- DMC DMA state: `src/emulation/state/peripherals/DmcDma.zig`
- DMA logic: `src/emulation/dma/logic.zig`
- DMA coordination: `src/emulation/cpu/execution.zig` (lines 126-180)
- DMA ledger: `src/emulation/DmaInteractionLedger.zig`
- VBlank ledger: `src/emulation/VBlankLedger.zig`
- CPU state: `src/cpu/State.zig` (interrupt fields lines 159-167)
- CPU interrupt logic: `src/cpu/Logic.zig` (checkInterrupts lines 56-81)
- PPU state: `src/ppu/State.zig`
- PPU registers: `src/ppu/logic/registers.zig`
- Sub-cycle ordering: `src/emulation/State.zig:tick` (lines 617-699)

**Test Files:**
- OAM DMA: `tests/integration/oam_dma_test.zig`
- DMC DMA: `tests/integration/dpcm_dma_test.zig`
- DMC/OAM conflict: `tests/integration/dmc_oam_conflict_test.zig`
- NMI tests: `tests/integration/nmi_*.zig` (7 files in tests/integration/accuracy/)
- VBlank tests: `tests/ppu/vblank_*.zig`, `tests/integration/accuracy/*vblank*.zig`
- AccuracyCoin: `tests/cartridge/accuracycoin_test.zig`
- AccuracyCoin ROM: `tests/data/AccuracyCoin/AccuracyCoin.nes`

**Documentation:**
- DMA implementation summary: `docs/quick-reference/dma-implementation-summary.md`
- OAM DMA review: `docs/testing/oam-dma-state-machine-review.md`
- DMC/OAM timing analysis: `docs/testing/dmc-oam-timing-analysis.md`
- NMI documentation: `docs/nesdev/nmi.md`
- VBlank documentation: `docs/VBLANK-*.md` (multiple files)
- VBlank implementation guide: `docs/VBLANK-IMPLEMENTATION-GUIDE.md`

**Hardware Documentation (Local Archives):**
- NES frame timing: `docs/nesdev/the-frame-and-nmis.md`
- NMI specification: `docs/nesdev/nmi.md`
- VBlank citations: `docs/VBLANK-CITATIONS.md`

#### Known Issues from Documentation

**From `docs/testing/oam-dma-state-machine-review.md`:**
- ⚠️ BUG #4: OAM resume logic never triggers due to exact cycle match requirement
  - Location: `src/emulation/dma/interaction.zig:198` (if still exists)
  - Problem: `last_dmc_inactive_cycle == cycle` check fails because timestamp recorded on cycle N but check happens on cycle N+1
  - Fix: Remove exact cycle match, rely on `oam_resume_cycle == 0` guard

**From `docs/testing/dmc-oam-timing-analysis.md`:**
- Test "Cycle count: OAM 513 + DMC 4 = 517 total" expects 517 cycles
- Actual result: 514 cycles
- Analysis: Test expectation may be wrong (should be 515-516 with time-sharing)
- Current implementation gives OAM 3 advance cycles during DMC (should be 2)

**From task success criteria:**
- AccuracyCoin OAM corruption test: Currently hangs or fails
- AccuracyCoin NMI CPU tests: All failing
- AccuracyCoin OAM tests: All failing
- These failures indicate timing accuracy bugs in OAM/NMI/VBlank interactions

#### Existing Pattern References

**VBlank Pattern (Reference Implementation):**
- Ledger: `src/emulation/VBlankLedger.zig` - Timestamp-based, external mutations
- Coordination: `src/emulation/State.zig:tick` - Sub-cycle ordering
- Edge detection: Timestamp comparison (last_set > last_clear)
- Race handling: `last_race_cycle` tracking

**NMI Pattern (Reference Implementation):**
- Edge detection: `src/cpu/Logic.zig:checkInterrupts`
- Line management: `src/emulation/cpu/execution.zig:stepCycle` (lines 93-112)
- Double-trigger prevention: `nmi_vblank_set_cycle` tracking
- Race suppression: Via VBlankLedger.hasRaceSuppression()

**DMA Pattern (Current Implementation):**
- Functional: Pure functions in `dma/logic.zig`
- External state management: Timestamps in `execution.zig`
- Time-sharing: Cycle-by-cycle checks
- Edge detection: Timestamp comparison

## User Notes
<!-- Any specific notes or requirements from the developer -->

## Work Log
<!-- Updated as work progresses -->
- [YYYY-MM-DD] Started task, initial research
