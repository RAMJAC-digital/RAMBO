---
name: h-fix-ppu-nmi-remediation
branch: fix/h-fix-ppu-nmi-remediation
status: pending
created: 2025-11-06
---

# PPU NMI Remediation

## Problem/Goal
Fix critical CPU/PPU NMI coordination issues preventing games from working correctly. Current symptoms:
- SMB1: Input doesn't work (controller polling requires NMI)
- Tetris: Grey screen (no VBlank)
- TMNT3: Black screen and hang
- AccuracyCoin: 8 failures in "NMI control" tests, plus NMI timing/suppression failures

Root cause: CPU and PPU are not properly synchronized regarding NMI generation, VBlank flag timing, and interrupt coordination.

## Success Criteria
**Phase 1: Clock Synchronization**
- [ ] CPU and PPU master clock relationship verified (CPU = PPU/3 for NTSC 2A03)
- [ ] M2 clock timing correct (CPU cycles begin when M2 goes low)
- [ ] PPU cycles align with CPU cycles per hardware specification

**Phase 2: VBlank Flag Behavior**
- [ ] VBlank flag sets at correct PPU cycle (scanline 241, dot 1)
- [ ] VBlank flag clears at correct time (scanline 261)
- [ ] $2002 reads clear VBlank flag with correct timing
- [ ] Race condition handling: $2002 read during VBlank set prevents flag from being set

**Phase 3: NMI Line Management**
- [ ] NMI line = NAND(VBlank flag, NMI enable bit) per 2C02 specification
- [ ] NMI triggers on falling edge only (high → low transition)
- [ ] CPU samples NMI line at end of each cycle (second-to-last cycle rule)
- [ ] NMI sequences cannot be interrupted once started

**Phase 4: AccuracyCoin Test Validation**
- [ ] All "PPU VBLANK TIMING" tests pass (page 17/20)
- [ ] All "CPU INTERRUPTS" tests pass (page 12/20)
- [ ] Specifically: "NMI control" (currently 8 failures)
- [ ] Specifically: "NMI timing", "NMI suppression", "NMI at VBlank end"

**Phase 5: Commercial ROM Validation**
- [ ] SMB1: Controller input works correctly
- [ ] Tetris: Displays game screen (VBlank working)
- [ ] TMNT3: No longer hangs on black screen
- [ ] AccuracyCoin: Input tests pass (currently working)

## Context Manifest

### Hardware Specification: 2C02 PPU NMI Generation and CPU Interrupt Timing

**ALWAYS START WITH HARDWARE DOCUMENTATION**

According to the NES hardware documentation, the PPU and CPU coordinate VBlank and NMI signaling through precise timing and electrical relationships:

**2C02 PPU VBlank Flag Behavior:**
- VBlank flag (bit 7 of $2002 PPUSTATUS) sets at scanline 241, dot 1 (https://www.nesdev.org/wiki/PPU_frame_timing)
- VBlank flag clears at scanline 261 (pre-render), dot 1
- Reading $2002 clears the VBlank flag immediately (hardware side effect)
- Race condition: Reading $2002 at scanline 241, dot 0 (one cycle BEFORE flag sets) prevents the flag from ever being set that frame

**NMI Line Management (2C02 → 6502):**
- NMI line = NAND(VBlank flag, PPUCTRL.7 NMI enable bit) (https://www.nesdev.org/wiki/NMI)
- NMI line is edge-triggered: CPU detects falling edge (high → low transition) of NMI pin
- Writing to PPUCTRL ($2000) bit 7 updates NMI line immediately
  - 0→1 transition while VBlank flag is set: triggers NMI
  - 1→0 transition: clears NMI line
- Reading $2002 always clears NMI line (along with VBlank flag)

**CPU Interrupt Polling Timing (6502 "Second-to-Last Cycle" Rule):**
- CPU samples NMI/IRQ lines at END of each cycle (during φ2 clock phase) (https://www.nesdev.org/wiki/CPU_interrupts)
- Sampled values are checked at START of next cycle
- Gives instructions one cycle to complete after register writes (e.g., STA $2000 enabling NMI)
- Interrupt sequences cannot be interrupted once started (pending state preserved)
- NMI has priority over IRQ (NMI cannot be masked by IRQ during interrupt sequence)

**Example Timing (AccuracyCoin test case):**
```
Cycle N:   STA $2000 sets PPUCTRL.7 → nmi_line=true
           [END: sample nmi_line=true, store to nmi_pending_prev]

Cycle N+1: LDX #$10 executes normally
           [START: check nmi_pending_prev=false from cycle N-1]
           [END: sample nmi_line=true, store to nmi_pending_prev]

Cycle N+2: Next instruction
           [START: check nmi_pending_prev=true from cycle N] → NMI fires!
```

**Clock Synchronization:**
- NTSC NES master oscillator: 21.477272 MHz
- CPU clock: 21.477272 MHz ÷ 12 = 1.789773 MHz
- PPU clock: 21.477272 MHz ÷ 4 = 5.369318 MHz
- Ratio: 3 PPU cycles per 1 CPU cycle (https://www.nesdev.org/wiki/Clock_rate)
- M2 clock: CPU cycles begin when M2 goes low (φ2 is high during second half of M2)

**Cycle Timing and Frame Structure:**
- 341 dots per scanline
- 262 scanlines per frame (scanlines -1, 0-260)
- Even frames: 341 × 262 = 89,342 PPU cycles
- Odd frames with rendering enabled: 89,341 PPU cycles (skip dot 0 of scanline 0)

**Edge Cases & Boundary Conditions:**
- Reading $2002 at scanline 241, dot 0: Prevents VBlank flag from setting (prevention window)
- Reading $2002 at scanline 241, dot 1-2: Returns VBlank flag (if set), clears it, suppresses NMI
- Multiple NMIs allowed per VBlank if PPUCTRL.7 is toggled (no VBlank-based suppression)
- VBlank span (scanline 241 → pre-render) is separate from VBlank flag (flag can be cleared while span active)

**Hardware Citations:**
- Primary: https://www.nesdev.org/wiki/PPU_frame_timing
- NMI Generation: https://www.nesdev.org/wiki/NMI
- CPU Interrupts: https://www.nesdev.org/wiki/CPU_interrupts
- Clock Rate: https://www.nesdev.org/wiki/Clock_rate
- Reference Implementation: Mesen2 NesCpu.cpp:294-315 (EndCpuCycle), NesPpu.cpp:1340-1344 (VBlank flag set with prevention check)

### Current Implementation: RAMBO's VBlank/NMI Coordination System

**VERBOSE NARRATIVE explaining current codebase implementation:**

RAMBO implements CPU/PPU NMI coordination using a **VBlankLedger** system that separates VBlank FLAG (readable $2002 bit) from VBlank SPAN (hardware timing window). This separation is critical because the flag can be cleared by $2002 reads while the span remains active.

**Architecture Overview:**

The system uses three main components working together:

1. **VBlankLedger** (`src/emulation/VBlankLedger.zig`) - Timing ledger tracking VBlank flag state and timestamps
2. **PpuHandler** (`src/emulation/bus/handlers/PpuHandler.zig`) - Stateless bus handler managing $2000-$3FFF (PPU registers)
3. **EmulationState.tick()** (`src/emulation/State.zig:462`) - Master coordination function orchestrating CPU/PPU execution order

**VBlankLedger State Structure:**

```zig
pub const VBlankLedger = struct {
    vblank_flag: bool = false,              // Bit 7 of $2002 (readable state)
    vblank_span_active: bool = false,       // Hardware timing window (241 → pre-render)
    last_set_cycle: u64 = 0,                // Timestamp when VBlank set
    last_clear_cycle: u64 = 0,              // Timestamp when VBlank cleared by timing
    last_read_cycle: u64 = 0,               // Timestamp of last $2002 read
    prevent_vbl_set_cycle: u64 = 0,         // Prevention timestamp (0 = no prevention)
};
```

The ledger distinguishes between:
- **vblank_flag**: Readable state (bit 7 of $2002), cleared by reads or pre-render timing
- **vblank_span_active**: Hardware timing window (scanline 241 → pre-render), NOT affected by $2002 reads

This matches Mesen2's architecture: `_statusFlags.VerticalBlank` (flag) vs scanline range checks (span).

**Execution Flow (EmulationState.tick()):**

The tick() function implements hardware-accurate sub-cycle execution order within each PPU cycle:

```
1. Advance PPU clock (PpuLogic.advanceClock) - PPU owns timing state
2. Advance master clock (self.clock.advance) - Monotonic timestamp counter
3. Determine CPU/APU tick flags (1:3 ratio)
4. Execute PPU rendering (self.stepPpuCycle) - Returns event signals
5. Execute APU (if APU tick) - Updates IRQ flags
6. Execute CPU (if CPU tick) - CAN read $2002 and set prevention flag
7. Apply VBlank timestamps (self.applyVBlankTimestamps) - Respects prevention flag
8. Sample CPU interrupts (CpuLogic.checkInterrupts) - Second-to-last cycle rule
9. Apply PPU rendering state (self.applyPpuRenderingState)
```

**CRITICAL: CPU execution happens BEFORE VBlank timestamps are applied.** This allows the CPU to read $2002 during the race window and set `prevent_vbl_set_cycle`, which is then checked when applying VBlank timestamps.

**Race Condition Handling (Scanline 241, Dot 0):**

When CPU reads $2002 at scanline 241, dot 0 (one cycle before VBlank sets):

1. **PpuHandler.read()** detects race window (scanline 241, dot 0)
2. Sets `prevent_vbl_set_cycle = master_cycles + 1` (next cycle's timestamp)
3. Returns $2002 value with VBlank bit CLEAR (flag hasn't set yet)
4. Clears NMI line (always cleared on $2002 read)
5. Next cycle, `applyVBlankTimestamps()` checks prevention flag and skips setting VBlank flag

**PpuHandler Implementation ($2002 Read Side Effects):**

```zig
// src/emulation/bus/handlers/PpuHandler.zig:59-106
pub fn read(_: *const PpuHandler, state: anytype, address: u16) u8 {
    const reg = address & 0x07;

    // Race detection: scanline 241, dot 0 ONLY
    if (reg == 0x02) {
        if (state.ppu.scanline == 241 and state.ppu.cycle == 0) {
            // Prevent VBlank set next cycle
            state.vblank_ledger.prevent_vbl_set_cycle = state.clock.master_cycles + 1;
        }
    }

    // Delegate to PpuLogic for register read
    const result = PpuLogic.readRegister(...);

    // $2002 read side effects (CRITICAL)
    if (result.read_2002) {
        state.vblank_ledger.last_read_cycle = state.clock.master_cycles;
        state.vblank_ledger.vblank_flag = false;  // Always clear flag
        state.cpu.nmi_line = false;                // Always clear NMI line
    }

    return result.value;
}
```

**PpuHandler Implementation ($2000 Write - NMI Enable):**

```zig
// src/emulation/bus/handlers/PpuHandler.zig:121-148
pub fn write(_: *PpuHandler, state: anytype, address: u16, value: u8) void {
    const reg = address & 0x07;

    // CRITICAL: Update NMI line IMMEDIATELY on PPUCTRL write
    if (reg == 0x00) {
        const old_nmi_enable = state.ppu.ctrl.nmi_enable;
        const new_nmi_enable = (value & 0x80) != 0;
        const vblank_flag_set = state.vblank_ledger.isFlagSet();

        // Edge trigger: 0→1 transition while VBlank flag is set
        if (!old_nmi_enable and new_nmi_enable and vblank_flag_set) {
            state.cpu.nmi_line = true;
        }

        // Disable: 1→0 transition clears NMI
        if (old_nmi_enable and !new_nmi_enable) {
            state.cpu.nmi_line = false;
        }
    }

    // Delegate to PpuLogic for register write
    PpuLogic.writeRegister(...);
}
```

**VBlank Timestamp Application (After CPU Execution):**

```zig
// src/emulation/State.zig:585-635
fn applyVBlankTimestamps(self: *EmulationState, result: PpuCycleResult) void {
    if (result.nmi_signal) {  // Scanline 241, dot 1
        // Check prevention flag (set by $2002 read at dot 0)
        const prevent_cycle = self.vblank_ledger.prevent_vbl_set_cycle;
        const should_prevent = prevent_cycle != 0 and prevent_cycle == self.clock.master_cycles;

        // VBlank span always activates (hardware timing window)
        self.vblank_ledger.vblank_span_active = true;

        if (!should_prevent) {
            // Set VBlank flag (readable bit 7 of $2002)
            self.vblank_ledger.vblank_flag = true;
            self.vblank_ledger.last_set_cycle = self.clock.master_cycles;

            // Set NMI line if NMI enabled
            if (self.ppu.ctrl.nmi_enable) {
                self.cpu.nmi_line = true;
            }
        }

        // One-shot: ALWAYS clear prevention flag after checking
        self.vblank_ledger.prevent_vbl_set_cycle = 0;
    }

    if (result.vblank_clear) {  // Scanline 261, dot 1
        // Clear both span and flag (hardware timing)
        self.vblank_ledger.vblank_span_active = false;
        self.vblank_ledger.vblank_flag = false;
        self.vblank_ledger.last_clear_cycle = self.clock.master_cycles;

        // Clear NMI line when VBlank ends
        self.cpu.nmi_line = false;
    }
}
```

**CPU Interrupt Sampling (Second-to-Last Cycle Rule):**

```zig
// src/emulation/State.zig:561-575
if (step.cpu_tick and self.cpu.state != .interrupt_sequence) {
    // Sample interrupt lines for next cycle
    CpuLogic.checkInterrupts(&self.cpu);

    // Store interrupt states for next cycle
    self.cpu.nmi_pending_prev = (self.cpu.pending_interrupt == .nmi);
    self.cpu.irq_pending_prev = (self.cpu.pending_interrupt == .irq);

    // Clear pending for this cycle - will be restored from _prev next cycle
    self.cpu.pending_interrupt = .none;
}
```

```zig
// src/cpu/Logic.zig:59-76
pub fn checkInterrupts(state: *CpuState) void {
    // NMI edge detection: was low, now high
    const nmi_prev = state.nmi_edge_detected;
    state.nmi_edge_detected = state.nmi_line;

    if (state.nmi_line and !nmi_prev) {
        // Falling edge detected (0→1 transition)
        state.pending_interrupt = .nmi;
    }

    // IRQ level detection (can be masked by I flag)
    if (state.irq_line and !state.p.interrupt and state.pending_interrupt == .none) {
        state.pending_interrupt = .irq;
    }
}
```

**State Organization:**

VBlank/NMI state is distributed across components following the hybrid State/Logic pattern:

- **VBlankLedger** (`src/emulation/VBlankLedger.zig`) - Pure data structure tracking flag state and timestamps
- **CpuState** (`src/cpu/State.zig`) - Contains NMI/IRQ line state and interrupt pending flags
  - `nmi_line: bool` - Current NMI line state (high = NMI asserted)
  - `irq_line: bool` - Current IRQ line state
  - `nmi_edge_detected: bool` - Previous NMI line state for edge detection
  - `pending_interrupt: InterruptType` - Current interrupt pending (.none, .nmi, .irq)
  - `nmi_pending_prev: bool` - NMI pending from previous cycle (second-to-last cycle rule)
  - `irq_pending_prev: bool` - IRQ pending from previous cycle
- **PpuState** (`src/ppu/State.zig`) - Contains PPU timing (scanline, cycle) and control registers
  - `ctrl.nmi_enable: bool` - PPUCTRL bit 7 (NMI enable)
  - `scanline: i16` - Current scanline (-1 to 260)
  - `cycle: u16` - Current dot (0-340)
- **MasterClock** (`src/emulation/MasterClock.zig`) - Monotonic timestamp counter
  - `master_cycles: u64` - Always advances by 1 (used for timestamp comparisons)

**Logic Organization:**

All mutations happen through pure functions with explicit parameters:

- **CpuLogic.checkInterrupts()** (`src/cpu/Logic.zig:59`) - Edge/level detection for interrupts
- **PpuLogic.readRegister()** (`src/ppu/logic/registers.zig:158`) - PPU register reads (pure, returns result struct)
- **PpuLogic.writeRegister()** (`src/ppu/logic/registers.zig:293`) - PPU register writes (pure, mutates via parameter)
- **PpuHandler.read()** / **PpuHandler.write()** (`src/emulation/bus/handlers/PpuHandler.zig`) - Bus handler managing VBlank/NMI coordination
- **EmulationState.applyVBlankTimestamps()** (`src/emulation/State.zig:585`) - VBlank flag mutation with prevention check

**Maintaining Purity:**

- All state passed via explicit parameters (ppu: *PpuState, cpu: *CpuState, etc.)
- No global variables or hidden mutations
- Side effects limited to mutations of passed pointers
- Handlers are zero-size (no internal state), delegate to Logic functions
- VBlankLedger mutations ONLY in EmulationState.tick() and PpuHandler

**Similar Patterns:**

See APU frame IRQ handling (`src/apu/Logic.zig`) for similar edge-triggered interrupt pattern.
See OAM DMA coordination (`src/emulation/dma/logic.zig`) for similar timestamp-based coordination.

### Readability Guidelines

**For This Implementation:**

The VBlank/NMI coordination system prioritizes obviousness over optimization:

- **Extensive comments explaining hardware behavior** (cite nesdev.org)
  - Example: `// Race window: scanline 241, dot 0-2` with hardware reference
  - Example: `// Second-to-last cycle rule: CPU samples at END of cycle, checks at START of next`
- **Clear variable names matching hardware terminology**
  - `vblank_flag` vs `vblank_span_active` (distinguishes readable state from timing window)
  - `prevent_vbl_set_cycle` (explicit prevention mechanism)
  - `nmi_pending_prev` (second-to-last cycle rule implementation)
- **Breaking complex operations into well-named helper functions**
  - `applyVBlankTimestamps()` (separate from CPU execution)
  - `checkInterrupts()` (edge/level detection isolated)
  - Handler delegation (PpuHandler → PpuLogic, clean separation)
- **Explicit timing order with comments**
  - Numbered steps in tick() function (1-9) explaining execution order
  - CRITICAL comments marking race condition handling

**Code Structure:**

- **Separation of concerns:**
  - VBlankLedger: Pure timing data (no business logic)
  - PpuHandler: Bus-level side effects (NMI line management)
  - EmulationState.tick(): Orchestration (execution order)
  - CpuLogic.checkInterrupts(): Edge/level detection (pure function)
- **Comment each phase with hardware timing:**
  - "Scanline 241, dot 1 (VBlank sets)"
  - "Scanline 261, dot 1 (VBlank clears)"
  - "Race window: dot 0 prevents, dot 1-2 returns flag and clears"
- **Explain WHY each operation happens:**
  - "CPU execution BEFORE VBlank timestamps allows prevention mechanism to work"
  - "NMI line is edge-triggered: CPU detects falling edge (high → low transition)"
  - "Interrupt sampling happens AFTER VBlank state is finalized"

### Technical Reference

#### Hardware Citations
- Primary: https://www.nesdev.org/wiki/PPU_frame_timing
- VBlank Flag: https://www.nesdev.org/wiki/PPU_registers#PPUSTATUS
- NMI Generation: https://www.nesdev.org/wiki/NMI
- CPU Interrupts: https://www.nesdev.org/wiki/CPU_interrupts
- Clock Rate: https://www.nesdev.org/wiki/Clock_rate
- Reference Implementation: Mesen2 NesCpu.cpp:294-315, NesPpu.cpp:1340-1344

#### Related State Structures
```zig
// src/emulation/VBlankLedger.zig
pub const VBlankLedger = struct {
    vblank_flag: bool = false,              // Bit 7 of $2002
    vblank_span_active: bool = false,       // Timing window
    last_set_cycle: u64 = 0,                // Set timestamp
    last_clear_cycle: u64 = 0,              // Clear timestamp
    last_read_cycle: u64 = 0,               // $2002 read timestamp
    prevent_vbl_set_cycle: u64 = 0,         // Prevention timestamp
};

// src/cpu/State.zig
pub const CpuState = struct {
    nmi_line: bool = false,                 // NMI pin state (high = asserted)
    irq_line: bool = false,                 // IRQ pin state
    nmi_edge_detected: bool = false,        // Previous NMI line (for edge detection)
    pending_interrupt: InterruptType = .none, // Current pending interrupt
    nmi_pending_prev: bool = false,         // NMI pending from previous cycle
    irq_pending_prev: bool = false,         // IRQ pending from previous cycle
    // ... other CPU registers
};

// src/ppu/State.zig
pub const PpuState = struct {
    ctrl: PpuCtrl = .{},                    // PPUCTRL ($2000)
    scanline: i16 = -1,                     // Current scanline (-1 to 260)
    cycle: u16 = 0,                         // Current dot (0-340)
    frame_count: u64 = 0,                   // Frame counter
    // ... other PPU state
};

// src/emulation/MasterClock.zig
pub const MasterClock = struct {
    master_cycles: u64 = 0,                 // Monotonic timestamp counter
    initial_phase: u2 = 0,                  // CPU/PPU phase offset
};
```

#### Related Logic Functions
```zig
// src/cpu/Logic.zig
pub fn checkInterrupts(cpu: *CpuState) void

// src/ppu/logic/registers.zig
pub fn readRegister(
    ppu: *PpuState,
    cart: ?*AnyCartridge,
    address: u16,
    vblank_ledger: VBlankLedger,
    scanline: i16,
    dot: u16,
) PpuReadResult

pub fn writeRegister(
    ppu: *PpuState,
    cart: ?*AnyCartridge,
    address: u16,
    value: u8,
) void

// src/ppu/Logic.zig
pub fn advanceClock(ppu: *PpuState, rendering_enabled: bool) void
```

#### File Locations
- Master coordination: `src/emulation/State.zig:462` (tick function)
- VBlank timestamps: `src/emulation/State.zig:585` (applyVBlankTimestamps)
- CPU interrupt sampling: `src/emulation/State.zig:561` (second-to-last cycle rule)
- VBlank ledger: `src/emulation/VBlankLedger.zig`
- PPU handler: `src/emulation/bus/handlers/PpuHandler.zig`
- CPU interrupt logic: `src/cpu/Logic.zig:59` (checkInterrupts)
- PPU register I/O: `src/ppu/logic/registers.zig`
- Master clock: `src/emulation/MasterClock.zig`

#### Integration Points
- **EmulationState.tick()** calls handlers and coordinates execution order
- **PpuHandler.read()** sets prevention flag, clears VBlank flag/NMI line on $2002 read
- **PpuHandler.write()** updates NMI line immediately on PPUCTRL write
- **applyVBlankTimestamps()** checks prevention flag before setting VBlank flag
- **CpuLogic.checkInterrupts()** samples interrupt lines (called at cycle end for second-to-last cycle rule)

#### Related Tests
- VBlank behavior: `tests/ppu/vblank_behavior_test.zig` (comprehensive VBlank flag lifecycle)
- NMI edge trigger: `tests/integration/nmi_edge_trigger_test.zig` (immediate NMI on PPUCTRL write)
- Race conditions: `tests/ppu/ppustatus_polling_test.zig` (prevention window at 241:0)
- NMI timing: `tests/integration/accuracy/nmi_timing_test.zig` (AccuracyCoin NMI tests)
- CPU interrupts: `tests/cpu/interrupt_logic_test.zig` (edge/level detection)

**⚠️ Test Verification (CRITICAL WARNING):**
- Existing tests may have incorrect expectations (test code, not hardware docs, may be wrong)
- When test contradicts hardware documentation, **trust hardware documentation**
- Flag tests with discrepancies for investigation
- Example: Some tests may expect VBlank behavior that doesn't match nesdev.org specification

## User Notes
<!-- Any specific notes or requirements from the developer -->

## Work Log
<!-- Updated as work progresses -->
- [YYYY-MM-DD] Started task, initial research
