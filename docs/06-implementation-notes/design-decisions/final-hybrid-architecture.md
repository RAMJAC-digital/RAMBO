# RAMBO Final Hybrid Architecture Design

**Date:** 2025-10-03
**Status:** APPROVED - Ready for Implementation
**Architecture:** Hybrid Synchronous Emulation Core + Asynchronous I/O Layer

---

## Executive Summary

This document defines the final architecture for RAMBO after comprehensive research and multi-agent review. The design uses a **hybrid approach**:

1. **Synchronous RT Emulation Loop**: Single-threaded, cycle-accurate state machine for CPU/PPU/APU
2. **Asynchronous I/O Layer**: libxev-based event loop for input/video/audio/file operations
3. **Clean Separation**: Emulation core isolated from I/O, parameterized for hardware variants
4. **Independent Timing**: Each chip maintains its own clock while coordinated through master timing

**Key Principle:** The emulation core is a **pure, deterministic state machine** that advances by single PPU cycles, with all I/O happening asynchronously outside the emulation loop.

---

## Table of Contents

1. [Architecture Principles](#1-architecture-principles)
2. [System Overview](#2-system-overview)
3. [RT Emulation Loop Design](#3-rt-emulation-loop-design)
4. [Component State Machines](#4-component-state-machines)
5. [Timing Coordination System](#5-timing-coordination-system)
6. [PPU Visual Glitch Emulation](#6-ppu-visual-glitch-emulation)
7. [libxev Integration](#7-libxev-integration)
8. [Hardware Configuration](#8-hardware-configuration)
9. [Implementation Plan](#9-implementation-plan)
10. [Testing Strategy](#10-testing-strategy)
11. [Migration & Cleanup](#11-migration--cleanup)

---

## 1. Architecture Principles

### 1.1 Core Principles

**P1: Deterministic Emulation Core**
- Emulation core is a pure function: `state_n+1 = f(state_n)`
- No I/O, no allocations, no side effects on hot path
- Fully reproducible execution (same inputs → same outputs)

**P2: Hardware-Accurate Timing**
- Each component tracks its own clock cycles
- Timing relationships match real hardware (PPU = 3× CPU)
- Visual glitches and timing bugs are accurately emulated

**P3: Clean Separation of Concerns**
- Emulation core (RT loop) is isolated from I/O
- Components communicate through well-defined interfaces
- Configuration is immutable during emulation

**P4: Parameterized Hardware**
- All hardware variants (RP2A03G/H, RP2C02G, etc.) use same code
- Behavior differences controlled by configuration
- Easy to add new variants

**P5: Zero Coupling Between Components**
- CPU doesn't know about PPU implementation
- PPU doesn't know about CPU implementation
- Bus mediates all communication
- CIC is completely separate utility

---

## 2. System Overview

### 2.1 High-Level Architecture

```
┌────────────────────────────────────────────────────────┐
│                  Main Thread (libxev)                   │
│                                                         │
│  ┌──────────────────────────────────────────────────┐ │
│  │         RT Emulation Loop (State Machine)         │ │
│  │                                                   │ │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────┐│ │
│  │  │   CPU   │  │   PPU   │  │   APU   │  │ CIC ││ │
│  │  │  State  │  │  State  │  │  State  │  │State││ │
│  │  │ Machine │  │ Machine │  │ Machine │  │ M/C ││ │
│  │  └────┬────┘  └────┬────┘  └────┬────┘  └─────┘│ │
│  │       │            │            │               │ │
│  │       └────────┬───┴────────────┘               │ │
│  │                │                                 │ │
│  │           ┌────▼─────┐                          │ │
│  │           │   Bus    │                          │ │
│  │           │  (State) │                          │ │
│  │           └──────────┘                          │ │
│  │                                                  │ │
│  │  Pure State Machine: state_n+1 = tick(state_n) │ │
│  └──────────────────────────────────────────────────┘ │
│                          │                            │
│                          │ Events/Callbacks           │
│                          ▼                            │
│  ┌──────────────────────────────────────────────────┐ │
│  │            libxev Event Loop (Async I/O)         │ │
│  │                                                   │ │
│  │  ┌───────────┐  ┌──────────┐  ┌───────────────┐│ │
│  │  │  Input    │  │  Video   │  │  Audio/File   ││ │
│  │  │  Handler  │  │  Output  │  │  I/O Handler  ││ │
│  │  └───────────┘  └──────────┘  └───────────────┘│ │
│  └──────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────┘
```

### 2.2 Separation of Concerns

**Emulation Core (RT Loop):**
- Advances emulation state by PPU cycles
- All components run in lockstep (single thread)
- No I/O operations
- No memory allocations
- Deterministic and reproducible

**I/O Layer (libxev):**
- Input polling (controllers)
- Video frame submission
- Audio sample buffering
- File operations (ROM loading, save states)
- Debug/trace logging

**Interface Between Layers:**
- **Core → I/O**: Callback functions (frame ready, audio buffer full)
- **I/O → Core**: Input state updated asynchronously
- **No blocking**: I/O never blocks emulation core

---

## 3. RT Emulation Loop Design

### 3.1 Master Clock and Timing

The emulation advances by **single PPU cycles** (finest granularity):

```zig
/// Master timing state
pub const MasterClock = struct {
    /// Total PPU cycles elapsed since power-on
    ppu_cycles: u64 = 0,

    /// Derived CPU cycles (PPU ÷ 3)
    pub fn cpuCycles(self: MasterClock) u64 {
        return self.ppu_cycles / 3;
    }

    /// Current scanline (0-261 NTSC, 0-311 PAL)
    pub fn scanline(self: MasterClock, config: Config) u16 {
        const cycles_per_scanline = config.ppu.cyclesPerScanline();
        const scanlines_per_frame = config.ppu.scanlinesPerFrame();
        const frame_cycles = cycles_per_scanline * scanlines_per_frame;
        const cycle_in_frame = self.ppu_cycles % frame_cycles;
        return @intCast(cycle_in_frame / cycles_per_scanline);
    }

    /// Current dot/cycle within scanline (0-340)
    pub fn dot(self: MasterClock, config: Config) u16 {
        const cycles_per_scanline = config.ppu.cyclesPerScanline();
        return @intCast(self.ppu_cycles % cycles_per_scanline);
    }
};
```

### 3.2 Emulation State Structure

```zig
/// Complete emulation state (pure data, no logic)
pub const EmulationState = struct {
    /// Master clock (PPU cycles)
    clock: MasterClock,

    /// Component states (pure data)
    cpu: CpuState,
    ppu: PpuState,
    apu: ApuState,
    bus: BusState,
    cic: CicState,

    /// Hardware configuration (immutable during emulation)
    config: *const HardwareConfig,

    /// Frame completion flag
    frame_complete: bool = false,

    /// Audio buffer ready flag
    audio_ready: bool = false,
};

/// CPU state (all registers and execution state)
pub const CpuState = struct {
    // Registers
    a: u8 = 0,
    x: u8 = 0,
    y: u8 = 0,
    sp: u8 = 0xFD,
    pc: u16 = 0,
    p: StatusFlags = .{},

    // Execution state
    state: ExecutionState = .fetch_opcode,
    opcode: u8 = 0,
    operand_low: u8 = 0,
    operand_high: u8 = 0,
    temp_address: u16 = 0,
    temp_value: u8 = 0,

    // Interrupt state
    nmi_line: bool = false,
    nmi_pending: bool = false,
    irq_line: bool = false,

    // Cycle counter (local to CPU, for instruction timing)
    cycle: u64 = 0,
};

/// PPU state (all registers and rendering state)
pub const PpuState = struct {
    // Registers
    ctrl: u8 = 0,      // $2000
    mask: u8 = 0,      // $2001
    status: u8 = 0,    // $2002
    oam_addr: u8 = 0,  // $2003

    // Internal registers
    v: u16 = 0,  // Current VRAM address
    t: u16 = 0,  // Temporary VRAM address
    x: u8 = 0,   // Fine X scroll
    w: bool = false,  // Write latch

    // Rendering state
    scanline: u16 = 0,
    dot: u16 = 0,
    frame: u64 = 0,

    // VRAM/OAM
    vram: [2048]u8 = undefined,
    oam: [256]u8 = undefined,
    palette_ram: [32]u8 = undefined,

    // Rendering buffers
    frame_buffer: [256 * 240]u32 = undefined,

    // Cycle counter
    cycle: u64 = 0,
};

/// Bus state (memory and open bus)
pub const BusState = struct {
    ram: [2048]u8 = std.mem.zeroes([2048]u8),
    open_bus: u8 = 0,
    cartridge_state: ?CartridgeState = null,
};

/// CIC state (lockout chip state machine)
pub const CicState = struct {
    enabled: bool,
    variant: CicVariant,
    state: u8 = 0,  // State machine state
    authenticated: bool = false,
};
```

### 3.3 RT Loop Implementation

```zig
/// RT emulation loop - advances state by 1 PPU cycle
pub fn tick(state: *EmulationState) void {
    // Advance master clock
    state.clock.ppu_cycles += 1;

    // Determine which components need to tick this PPU cycle
    const cpu_tick = (state.clock.ppu_cycles % 3) == 0;  // CPU every 3 PPU cycles
    const ppu_tick = true;  // PPU every PPU cycle
    const apu_tick = cpu_tick;  // APU same as CPU

    // Tick components in hardware order (matters for same-cycle interactions)
    if (ppu_tick) {
        tickPpu(&state.ppu, &state.bus, state.config);
    }

    if (cpu_tick) {
        tickCpu(&state.cpu, &state.bus, state.config);
    }

    if (apu_tick) {
        tickApu(&state.apu, state.config);
    }

    // Check for frame completion (PPU scanline 241, dot 1 - VBlank start)
    if (state.ppu.scanline == 241 and state.ppu.dot == 1) {
        state.frame_complete = true;
    }

    // Check for audio buffer ready (every N samples)
    if (state.apu.buffer_full) {
        state.audio_ready = true;
    }
}

/// Tick CPU state machine
fn tickCpu(cpu: *CpuState, bus: *BusState, config: *const HardwareConfig) void {
    cpu.cycle += 1;

    // Execute current state
    switch (cpu.state) {
        .fetch_opcode => {
            cpu.opcode = busRead(bus, cpu.pc);
            cpu.pc +%= 1;
            // Decode and transition to next state based on opcode
            cpu.state = decodeNextState(cpu.opcode);
        },
        .fetch_operand_low => {
            cpu.operand_low = busRead(bus, cpu.pc);
            cpu.pc +%= 1;
            cpu.state = .fetch_operand_high;
        },
        // ... other states
        .execute => {
            // Execute instruction based on opcode
            executeInstruction(cpu, bus, config);
            cpu.state = .fetch_opcode;  // Next instruction
        },
    }

    // Check for interrupts (after instruction completes)
    if (cpu.state == .fetch_opcode) {
        if (cpu.nmi_pending) {
            cpu.state = .interrupt_nmi;
            cpu.nmi_pending = false;
        } else if (cpu.irq_line and !cpu.p.interrupt) {
            cpu.state = .interrupt_irq;
        }
    }
}

/// Tick PPU state machine
fn tickPpu(ppu: *PpuState, bus: *BusState, config: *const HardwareConfig) void {
    ppu.cycle += 1;

    // Advance dot and scanline
    ppu.dot += 1;
    if (ppu.dot > 340) {
        ppu.dot = 0;
        ppu.scanline += 1;

        const max_scanline = config.ppu.scanlinesPerFrame() - 1;
        if (ppu.scanline > max_scanline) {
            ppu.scanline = 0;
            ppu.frame += 1;
        }
    }

    // PPU rendering logic based on scanline and dot
    if (ppu.scanline <= 239 and ppu.dot >= 1 and ppu.dot <= 256) {
        // Visible scanline, visible dot - render pixel
        renderPixel(ppu, bus, config);
    } else if (ppu.scanline == 241 and ppu.dot == 1) {
        // VBlank start - set VBlank flag
        ppu.status |= 0x80;  // Set VBlank flag

        // Trigger NMI if enabled
        if ((ppu.ctrl & 0x80) != 0) {
            // Signal NMI to CPU (will be picked up next CPU tick)
            triggerNmi(ppu, bus);
        }
    } else if (ppu.scanline == 261 and ppu.dot == 1) {
        // Pre-render scanline - clear VBlank flag
        ppu.status &= ~0x80;
    }
}
```

### 3.4 Zero Coupling Design

Components communicate **only through the bus**, never directly:

```zig
/// CPU reads memory - doesn't know if it's RAM, PPU registers, or cartridge
fn cpuRead(cpu: *CpuState, bus: *BusState, address: u16) u8 {
    return busRead(bus, address);
}

/// Bus routing - mediates all access
fn busRead(bus: *BusState, address: u16) u8 {
    return switch (address) {
        0x0000...0x1FFF => bus.ram[address & 0x07FF],  // RAM + mirrors
        0x2000...0x3FFF => ppuRegisterRead(address),    // PPU registers
        0x4000...0x401F => apuRegisterRead(address),    // APU/IO registers
        0x4020...0xFFFF => cartridgeRead(bus.cartridge_state, address),
        else => bus.open_bus,
    };
}

/// PPU register read - doesn't know who's reading (CPU or DMA)
fn ppuRegisterRead(address: u16) u8 {
    const reg = address & 0x07;  // $2000-$2007 repeated
    return switch (reg) {
        0x02 => readPpuStatus(),  // $2002 - PPUSTATUS
        0x04 => readOamData(),     // $2004 - OAMDATA
        0x07 => readPpuData(),     // $2007 - PPUDATA
        else => open_bus,          // Write-only registers return open bus
    };
}
```

**Key Point:** CPU and PPU never call each other's functions. All communication is through the bus abstraction.

---

## 4. Component State Machines

### 4.1 CPU State Machine (6502)

Each instruction is a sequence of microsteps, one per cycle:

```zig
pub const ExecutionState = enum {
    fetch_opcode,
    fetch_operand_low,
    fetch_operand_high,
    calc_address_low,
    calc_address_high,
    dummy_read,
    dummy_write,
    execute,
    write_result,
    // Interrupt states
    interrupt_nmi,
    interrupt_irq,
    // ... stack, branch states
};

/// Example: LDA Absolute,X with page cross (5 cycles)
/// Cycle 1: Fetch opcode $BD
/// Cycle 2: Fetch address low byte
/// Cycle 3: Fetch address high byte
/// Cycle 4: Dummy read at wrong address (if page crossed)
/// Cycle 5: Read actual value, execute

fn executeLdaAbsoluteX(cpu: *CpuState, bus: *BusState) void {
    switch (cpu.state) {
        .fetch_operand_low => {
            cpu.operand_low = busRead(bus, cpu.pc);
            cpu.pc +%= 1;
            cpu.state = .fetch_operand_high;
        },
        .fetch_operand_high => {
            cpu.operand_high = busRead(bus, cpu.pc);
            cpu.pc +%= 1;

            // Calculate effective address
            const base = @as(u16, cpu.operand_high) << 8 | cpu.operand_low;
            const addr = base +% cpu.x;
            cpu.temp_address = addr;

            // Check page cross
            if ((base & 0xFF00) != (addr & 0xFF00)) {
                cpu.state = .dummy_read;  // Page crossed, dummy read
            } else {
                cpu.state = .execute;     // No page cross, read directly
            }
        },
        .dummy_read => {
            // Dummy read at wrong address (before high byte fixed)
            const wrong_addr = (@as(u16, cpu.operand_high) << 8) |
                               ((cpu.operand_low +% cpu.x) & 0xFF);
            _ = busRead(bus, wrong_addr);  // Dummy read updates open bus
            cpu.state = .execute;
        },
        .execute => {
            cpu.a = busRead(bus, cpu.temp_address);
            cpu.p.updateZN(cpu.a);
            cpu.state = .fetch_opcode;  // Done
        },
        else => unreachable,
    }
}
```

### 4.2 PPU State Machine

PPU state is driven by scanline and dot position:

```zig
fn tickPpu(ppu: *PpuState, bus: *BusState, config: *const HardwareConfig) void {
    // State is implicitly defined by (scanline, dot)
    const scanline = ppu.scanline;
    const dot = ppu.dot;

    if (scanline <= 239) {
        // Visible scanline
        if (dot >= 1 and dot <= 256) {
            renderPixel(ppu, bus, config);
        } else if (dot >= 257 and dot <= 320) {
            // Sprite evaluation for next scanline
            evaluateSprites(ppu);
        } else if (dot >= 321 and dot <= 336) {
            // Fetch tiles for next scanline
            fetchTiles(ppu, bus);
        }
    } else if (scanline == 240) {
        // Post-render scanline (idle)
    } else if (scanline >= 241 and scanline <= 260) {
        // VBlank
        if (scanline == 241 and dot == 1) {
            ppu.status |= 0x80;  // Set VBlank flag
            if ((ppu.ctrl & 0x80) != 0) {
                triggerNmi(ppu, bus);  // NMI if enabled
            }
        }
    } else if (scanline == 261) {
        // Pre-render scanline
        if (dot == 1) {
            ppu.status &= ~0xE0;  // Clear VBlank, sprite 0, overflow
        }
        // Pre-fetch tiles for scanline 0
    }

    // Advance dot and scanline
    advancePpuPosition(ppu, config);
}
```

### 4.3 Independent Timing, Coordinated Execution

Each component advances on its own schedule, but they run in a coordinated loop:

```zig
pub fn emulateFrame(state: *EmulationState) void {
    state.frame_complete = false;

    // Run until frame complete
    while (!state.frame_complete) {
        tick(state);  // Advance by 1 PPU cycle
    }

    // Frame complete - emulation state is now at start of VBlank
}

/// Alternative: Run for N PPU cycles
pub fn emulateCycles(state: *EmulationState, ppu_cycles: u32) void {
    for (0..ppu_cycles) |_| {
        tick(state);
    }
}
```

**Key Insight:** Even though components have independent clocks (CPU every 3 PPU cycles), they're coordinated by the master clock advancing one PPU cycle at a time.

---

## 5. Timing Coordination System

### 5.1 Clock Dividers and Ratios

```zig
/// Timing configuration per hardware variant
pub const TimingConfig = struct {
    /// PPU clock divider from master oscillator
    ppu_divider: u8,

    /// CPU clock divider from PPU clock
    cpu_from_ppu: u8 = 3,  // Always 3 for NES/Famicom

    /// APU clock divider from PPU clock
    apu_from_ppu: u8 = 3,  // Same as CPU

    /// Master oscillator frequency
    master_freq_hz: f64,

    /// Derived frequencies
    pub fn ppuFreqHz(self: TimingConfig) f64 {
        return self.master_freq_hz / @as(f64, @floatFromInt(self.ppu_divider));
    }

    pub fn cpuFreqHz(self: TimingConfig) f64 {
        return self.ppuFreqHz() / @as(f64, @floatFromInt(self.cpu_from_ppu));
    }
};

/// NTSC timing (RP2A03G + RP2C02G)
pub const NTSC_TIMING = TimingConfig{
    .ppu_divider = 4,
    .master_freq_hz = 21.477272e6,  // ~21.48 MHz
    // Derived: PPU = 5.37 MHz, CPU = 1.79 MHz
};

/// PAL timing (RP2A07 + RP2C07)
pub const PAL_TIMING = TimingConfig{
    .ppu_divider = 5,
    .master_freq_hz = 26.6017e6,   // ~26.60 MHz
    // Derived: PPU = 5.32 MHz, CPU = 1.77 MHz
};
```

### 5.2 Same-Cycle Interactions

Some interactions happen within the same PPU cycle and order matters:

```zig
fn tick(state: *EmulationState) void {
    // Order matters for same-cycle interactions!

    // 1. PPU first (can trigger NMI, set sprite 0 hit)
    if (needsPpuTick(state)) {
        tickPpu(&state.ppu, &state.bus, state.config);
    }

    // 2. CPU second (will see PPU changes from this cycle)
    if (needsCpuTick(state)) {
        tickCpu(&state.cpu, &state.bus, state.config);
    }

    // 3. APU last (audio generation)
    if (needsApuTick(state)) {
        tickApu(&state.apu, state.config);
    }

    // Advance master clock
    state.clock.ppu_cycles += 1;
}

/// Example: PPU triggers NMI on same cycle CPU is executing
/// Cycle N:
///   - PPU sets VBlank flag, triggers NMI line
///   - CPU sees NMI line (if between instructions)
///   - CPU begins NMI sequence
```

### 5.3 DMA and Bus Conflicts

OAM DMA halts CPU and steals bus cycles:

```zig
fn handleOamDma(state: *EmulationState, start_address: u16) void {
    // DMA takes 513 or 514 CPU cycles (1539 or 1542 PPU cycles)
    const alignment_cycle = if (state.cpu.cycle % 2 == 1) 1 else 0;
    const total_cycles = 512 + alignment_cycle + 1;

    // Suspend CPU
    const saved_cpu_state = state.cpu.state;
    state.cpu.state = .dma_suspended;

    // Transfer 256 bytes
    for (0..256) |i| {
        // Read cycle (CPU cycle N)
        const value = busRead(&state.bus, start_address + @as(u16, @intCast(i)));

        // Advance 1 CPU cycle = 3 PPU cycles
        for (0..3) |_| {
            tickPpu(&state.ppu, &state.bus, state.config);
            state.clock.ppu_cycles += 1;
        }

        // Write cycle (CPU cycle N+1)
        state.ppu.oam[i] = value;

        // Advance 1 CPU cycle = 3 PPU cycles
        for (0..3) |_| {
            tickPpu(&state.ppu, &state.bus, state.config);
            state.clock.ppu_cycles += 1;
        }
    }

    // Resume CPU
    state.cpu.state = saved_cpu_state;
    state.cpu.cycle += total_cycles;
}
```

---

## 6. PPU Visual Glitch Emulation

### 6.1 Timing-Dependent Visual Effects

Many visual glitches depend on precise cycle timing:

#### Sprite 0 Hit Timing
```zig
fn checkSprite0Hit(ppu: *PpuState) void {
    // Sprite 0 hit can only occur during specific conditions
    if (ppu.scanline > 239) return;  // Not in visible area
    if (ppu.dot < 1 or ppu.dot > 256) return;  // Not during rendering
    if ((ppu.mask & 0x18) == 0) return;  // Rendering disabled

    // Check if sprite 0 and background pixels are both opaque
    const sprite0_pixel = getSpritePixel(ppu, 0, ppu.dot - 1);
    const bg_pixel = getBackgroundPixel(ppu, ppu.dot - 1);

    if (sprite0_pixel.opaque and bg_pixel.opaque) {
        ppu.status |= 0x40;  // Set sprite 0 hit flag
    }
}
```

#### Mid-Scanline Register Writes
```zig
fn writePpuCtrl(ppu: *PpuState, value: u8, dot: u16) void {
    const old_ctrl = ppu.ctrl;
    ppu.ctrl = value;

    // Changing nametable mid-scanline causes visual glitch
    if ((old_ctrl & 0x03) != (value & 0x03)) {
        // Nametable changed - affects rendering immediately
        // Some games use this for split-screen effects
        updateNametableSelect(ppu, value & 0x03);
    }

    // NMI enable during VBlank can trigger immediate NMI
    if ((value & 0x80) != 0 and (old_ctrl & 0x80) == 0) {
        if ((ppu.status & 0x80) != 0) {
            // VBlank flag already set, enabling NMI triggers it
            triggerNmiImmediately(ppu);
        }
    }
}
```

#### Scroll Glitches
```zig
fn writePpuScroll(ppu: *PpuState, value: u8, dot: u16) void {
    if (!ppu.w) {
        // First write - X scroll
        ppu.t = (ppu.t & 0xFFE0) | (value >> 3);
        ppu.x = value & 0x07;
    } else {
        // Second write - Y scroll
        ppu.t = (ppu.t & 0x8C1F) | ((value & 0x07) << 12) | ((value & 0xF8) << 2);
    }
    ppu.w = !ppu.w;

    // Writing PPUSCROLL during rendering causes visual glitches
    if (dot >= 1 and dot <= 256 and ppu.scanline <= 239) {
        // Mid-render scroll change - creates split-screen or parallax effects
        // This is intentional in some games (e.g., Super Mario Bros 3)
    }
}
```

### 6.2 Accurate VBlank Timing

VBlank flag timing is critical for many games:

```zig
fn handleVBlankStart(ppu: *PpuState, bus: *BusState) void {
    // VBlank flag set on scanline 241, dot 1
    // This is BEFORE NMI can trigger
    ppu.status |= 0x80;

    // NMI occurs on dot 1 if enabled
    if ((ppu.ctrl & 0x80) != 0) {
        // But reading $2002 on dot 0 or 1 can suppress NMI
        if (!ppu.nmi_suppressed) {
            triggerNmi(bus);
        }
    }
}

fn readPpuStatus(ppu: *PpuState, dot: u16, scanline: u16) u8 {
    const status = ppu.status;

    // Reading $2002 clears VBlank flag
    ppu.status &= ~0x80;

    // Also resets write latch
    ppu.w = false;

    // Reading on dot 0 or 1 of scanline 241 suppresses NMI
    if (scanline == 241 and (dot == 0 or dot == 1)) {
        ppu.nmi_suppressed = true;
    }

    return status;
}
```

### 6.3 Rendering Glitches

Accurate rendering requires cycle-by-cycle pixel generation:

```zig
fn renderPixel(ppu: *PpuState, bus: *BusState, config: *const HardwareConfig) void {
    const x = ppu.dot - 1;  // Pixel X (0-255)
    const y = ppu.scanline;  // Pixel Y (0-239)

    // Fetch background pixel
    const bg_pixel = fetchBackgroundPixel(ppu, bus);

    // Fetch sprite pixels
    const sprite_pixel = fetchSpritePixel(ppu, x);

    // Priority and transparency logic
    const final_pixel = if (sprite_pixel.priority == .front and sprite_pixel.opaque) {
        sprite_pixel.color
    } else if (bg_pixel.opaque) {
        bg_pixel.color
    } else if (sprite_pixel.opaque) {
        sprite_pixel.color
    } else {
        getBackdropColor(ppu)
    };

    // Write to frame buffer
    ppu.frame_buffer[y * 256 + x] = final_pixel;

    // Check sprite 0 hit (timing-critical)
    if (sprite_pixel.sprite0 and bg_pixel.opaque and sprite_pixel.opaque) {
        if (x != 255) {  // Sprite 0 hit doesn't occur at X=255
            ppu.status |= 0x40;
        }
    }
}
```

---

## 7. libxev Integration

### 7.1 Event Loop Structure

```zig
const xev = @import("xev");
const std = @import("std");

pub const Emulator = struct {
    /// Emulation state (pure state machine)
    emu_state: EmulationState,

    /// libxev event loop
    loop: xev.Loop,

    /// Frame timer
    frame_timer: xev.Timer,

    /// Input state (updated asynchronously)
    input_state: InputState,

    /// Callbacks
    on_frame_complete: ?*const fn(*Emulator) void = null,
    on_audio_ready: ?*const fn(*Emulator, []const i16) void = null,

    pub fn init(allocator: std.mem.Allocator, config: HardwareConfig) !Emulator {
        return Emulator{
            .emu_state = try EmulationState.init(allocator, config),
            .loop = try xev.Loop.init(),
            .frame_timer = try xev.Timer.init(),
            .input_state = InputState.init(),
        };
    }

    pub fn run(self: *Emulator) !void {
        // Start frame timer
        try self.startFrameTimer();

        // Run event loop
        try self.loop.run(.until_done);
    }

    fn startFrameTimer(self: *Emulator) !void {
        const frame_duration_ns = self.emu_state.config.ppu.frameDurationUs() * 1000;
        const frame_duration_ms = frame_duration_ns / 1_000_000;

        var c: xev.Completion = undefined;
        self.frame_timer.run(
            &self.loop,
            &c,
            frame_duration_ms,
            Emulator,
            self,
            frameTimerCallback,
        );
    }

    fn frameTimerCallback(
        userdata: ?*Emulator,
        _: *xev.Loop,
        c: *xev.Completion,
        result: xev.Timer.RunError!void,
    ) xev.CallbackAction {
        _ = result catch return .disarm;

        const self = userdata.?;

        // Emulate one frame (pure state machine tick)
        emulateFrame(&self.emu_state);

        // Notify frame complete (async I/O can submit frame)
        if (self.on_frame_complete) |callback| {
            callback(self);
        }

        // Rearm timer for next frame
        const frame_duration_ns = self.emu_state.config.ppu.frameDurationUs() * 1000;
        const frame_duration_ms = frame_duration_ns / 1_000_000;

        self.frame_timer.run(
            &self.loop,
            c,
            frame_duration_ms,
            Emulator,
            self,
            frameTimerCallback,
        );

        return .rearm;
    }
};
```

### 7.2 Asynchronous I/O Integration

```zig
/// Input handler (async)
pub const InputHandler = struct {
    loop: *xev.Loop,
    emulator: *Emulator,
    poll_timer: xev.Timer,

    pub fn init(loop: *xev.Loop, emulator: *Emulator) !InputHandler {
        return InputHandler{
            .loop = loop,
            .emulator = emulator,
            .poll_timer = try xev.Timer.init(),
        };
    }

    pub fn start(self: *InputHandler) !void {
        // Poll input every 8ms (125 Hz - much faster than 60 Hz frame rate)
        var c: xev.Completion = undefined;
        self.poll_timer.run(
            self.loop,
            &c,
            8,  // 8ms
            InputHandler,
            self,
            pollCallback,
        );
    }

    fn pollCallback(
        userdata: ?*InputHandler,
        loop: *xev.Loop,
        c: *xev.Completion,
        result: xev.Timer.RunError!void,
    ) xev.CallbackAction {
        _ = result catch return .disarm;

        const self = userdata.?;

        // Read input state (platform-specific)
        const input = readInputState();

        // Update emulator input state (lock-free write)
        self.emulator.input_state.controller1 = input.controller1;
        self.emulator.input_state.controller2 = input.controller2;

        // Rearm
        self.poll_timer.run(loop, c, 8, InputHandler, self, pollCallback);
        return .rearm;
    }
};

/// Video output handler (async)
pub const VideoHandler = struct {
    loop: *xev.Loop,
    emulator: *Emulator,

    pub fn onFrameComplete(emulator: *Emulator) void {
        // Frame buffer is ready - submit to GPU (async)
        const frame_buffer = &emulator.emu_state.ppu.frame_buffer;

        // Platform-specific: Submit to GPU/window
        submitFrame(frame_buffer);
    }
};

/// Audio output handler (async)
pub const AudioHandler = struct {
    loop: *xev.Loop,
    emulator: *Emulator,
    buffer: [4096]i16,  // Audio sample buffer

    pub fn onAudioReady(emulator: *Emulator, samples: []const i16) void {
        // Audio samples ready - submit to audio device (async)
        submitAudioSamples(samples);
    }
};
```

### 7.3 File I/O (Async ROM Loading)

```zig
pub fn loadRomAsync(
    loop: *xev.Loop,
    path: []const u8,
    callback: *const fn(?Cartridge) void,
) !void {
    // Use libxev file operations
    var file_op: xev.File = undefined;
    try file_op.open(loop, path, .{}, FileOpenCallback, callback);
}

fn FileOpenCallback(
    userdata: ?*const fn(?Cartridge) void,
    _: *xev.Loop,
    _: *xev.Completion,
    result: xev.File.OpenError!xev.File,
) xev.CallbackAction {
    const file = result catch {
        userdata.?(null);  // Error - return null
        return .disarm;
    };

    // Read file contents asynchronously
    // Parse iNES format
    // Create cartridge
    // Invoke callback with cartridge

    return .disarm;
}
```

---

## 8. Hardware Configuration

### 8.1 Complete Configuration Structure

```zig
pub const HardwareConfig = struct {
    /// Console variant
    console: ConsoleVariant = .nes_ntsc_frontloader,

    /// CPU configuration
    cpu: CpuConfig = .{},

    /// PPU configuration
    ppu: PpuConfig = .{},

    /// APU configuration
    apu: ApuConfig = .{},

    /// CIC configuration
    cic: CicConfig = .{},

    /// Controller configuration
    controllers: ControllerConfig = .{},

    /// Timing configuration (derived from variants)
    timing: TimingConfig,

    pub fn initFromFile(allocator: std.mem.Allocator, path: []const u8) !HardwareConfig {
        // Load and parse KDL config file
        // ...
    }

    pub fn accuracyCoinTarget() HardwareConfig {
        return .{
            .console = .nes_ntsc_frontloader,
            .cpu = .{
                .variant = .rp2a03g,
                .unstable_opcodes = .{
                    .sha_behavior = .rp2a03g_standard,
                    .lxa_magic = 0xEE,
                },
            },
            .ppu = .{
                .variant = .rp2c02g,
                .region = .ntsc,
            },
            .cic = .{
                .variant = .cic_nes_3193,
                .enabled = true,
            },
            .controllers = .{
                .type = .nes,
            },
            .timing = NTSC_TIMING,
        };
    }
};

pub const CpuConfig = struct {
    variant: CpuVariant = .rp2a03g,
    region: VideoRegion = .ntsc,

    unstable_opcodes: struct {
        sha_behavior: SHABehavior = .rp2a03g_standard,
        lxa_magic: u8 = 0xEE,
    } = .{},
};

pub const CpuVariant = enum {
    rp2a03e,  // Early NTSC
    rp2a03g,  // Standard NTSC (AccuracyCoin target)
    rp2a03h,  // Later NTSC
    rp2a07,   // PAL
};

pub const SHABehavior = enum {
    rp2a03g_old,      // Older RP2A03G behavior
    rp2a03g_standard, // Standard RP2A03G behavior
    rp2a03h,          // RP2A03H behavior
};

pub const CicConfig = struct {
    variant: CicVariant = .cic_nes_3193,
    enabled: bool = true,
    emulation: CicEmulation = .state_machine,
};

pub const CicVariant = enum {
    cic_nes_3193,  // NTSC USA
    cic_nes_3195,  // PAL B
    cic_nes_3197,  // PAL A
    cic_6113,      // Die shrink
};

pub const CicEmulation = enum {
    state_machine,  // Full emulation
    bypass,         // Bypass (top-loader style)
    disabled,       // No CIC chip
};

pub const ControllerConfig = struct {
    type: ControllerType = .nes,
};

pub const ControllerType = enum {
    nes,      // Detachable controllers (specific clocking)
    famicom,  // Hardwired controllers (different clocking)
};
```

### 8.2 Configuration File (rambo.kdl)

```kdl
// RAMBO Hardware Configuration
// Target: AccuracyCoin test suite (RP2A03G + RP2C02G NTSC)

console "NES-NTSC-FrontLoader"

cpu {
    variant "RP2A03G"
    region "NTSC"

    unstable_opcodes {
        sha_behavior "standard"  // RP2A03G standard behavior
        lxa_magic 0xEE
    }
}

ppu {
    variant "RP2C02G"
    region "NTSC"
    accuracy "cycle"
}

apu {
    enabled true
    region "NTSC"
}

cic {
    variant "CIC-NES-3193"
    enabled true
    emulation "state_machine"
}

controllers {
    type "NES"
}
```

---

## 9. Implementation Plan

### Phase 1: Configuration System Expansion (Week 1)

**Goal:** Complete hardware variant configuration without touching emulation core.

**Tasks:**
1. ✅ Expand `Config.zig` with all hardware variants
2. ✅ Add CPU variant config (RP2A03G/H, RP2A07)
3. ✅ Add unstable opcode configuration (SHA, LXA behavior)
4. ✅ Add PPU variant config (RP2C02G, RP2C07)
5. ✅ Add CIC config (variant, emulation mode)
6. ✅ Add controller type config (NES vs Famicom)
7. ✅ Update `rambo.kdl` parser
8. ✅ Write 20+ tests for configuration
9. ✅ Document configuration options

**Deliverables:**
- `src/config/Config.zig` (expanded)
- `rambo.kdl` (complete hardware description)
- `docs/configuration-guide.md`
- 20+ passing tests

**Acceptance:**
- All 112 existing tests still pass
- Can load AccuracyCoin target config
- Can load PAL config

---

### Phase 2: Emulation State Refactoring (Week 2)

**Goal:** Refactor current code to pure state machine architecture.

**Tasks:**
1. ✅ Create `EmulationState` struct (all state in one place)
2. ✅ Create `MasterClock` for timing coordination
3. ✅ Refactor CPU to use `CpuState` (pure data)
4. ✅ Extract CPU logic to pure functions
5. ✅ Refactor Bus to use `BusState` (pure data)
6. ✅ Create `tick()` function (pure state transition)
7. ✅ Write tests for state machine

**Deliverables:**
- `src/emulation/State.zig` (EmulationState, MasterClock)
- `src/emulation/tick.zig` (RT loop)
- Refactored CPU/Bus
- 30+ tests

**Acceptance:**
- All 112 tests still pass (0 regressions)
- State can be serialized (save states possible)
- Emulation is deterministic (same input → same output)

---

### Phase 3: CIC State Machine (Week 3)

**Goal:** Implement CIC as synchronous state machine.

**Tasks:**
1. ✅ Implement `CicState` struct
2. ✅ Implement CIC authentication sequence
3. ✅ Implement CIC bypass mode (top-loader)
4. ✅ Implement CIC disabled mode
5. ✅ Integrate with console initialization
6. ✅ Write CIC tests

**Deliverables:**
- `src/cic/Cic.zig` (state machine)
- `src/cic/variants.zig` (CIC-NES-3193, 3195, 3197)
- 10+ tests

**Acceptance:**
- CIC authenticates correctly
- CIC bypass mode works
- All tests pass

---

### Phase 4: PPU State Machine Foundation (Week 4-6)

**Goal:** Implement PPU as cycle-accurate state machine.

**Tasks:**
1. ✅ Create `PpuState` struct (all PPU state)
2. ✅ Implement PPU register I/O ($2000-$2007)
3. ✅ Implement scanline/dot timing
4. ✅ Implement VBlank timing (flag set/clear)
5. ✅ Implement NMI triggering
6. ✅ Implement basic rendering (background only)
7. ✅ Implement sprite rendering
8. ✅ Implement sprite 0 hit
9. ✅ Write PPU tests

**Deliverables:**
- `src/ppu/Ppu.zig` (state machine)
- `src/ppu/rendering.zig` (pixel rendering)
- `src/ppu/registers.zig` (PPU I/O)
- 40+ tests

**Acceptance:**
- PPU renders basic graphics
- Sprite 0 hit timing correct
- VBlank timing matches hardware
- All tests pass

---

### Phase 5: libxev Integration (Week 7)

**Goal:** Integrate libxev event loop for async I/O.

**Tasks:**
1. ✅ Create `Emulator` struct with libxev loop
2. ✅ Implement frame timer callback
3. ✅ Implement input polling (async)
4. ✅ Implement video output (async frame submission)
5. ✅ Implement audio output (async sample buffering)
6. ✅ Implement async file loading
7. ✅ Wire up emulation core to I/O layer

**Deliverables:**
- `src/Emulator.zig` (main emulator with libxev)
- `src/io/Input.zig` (async input)
- `src/io/Video.zig` (async video)
- `src/io/Audio.zig` (async audio)
- Integration tests

**Acceptance:**
- Emulator runs at 60 FPS NTSC
- Input is responsive
- Video frames display correctly
- Audio plays correctly
- All tests pass

---

### Phase 6: Visual Glitch Emulation (Week 8)

**Goal:** Implement timing-dependent PPU effects.

**Tasks:**
1. ✅ Implement mid-scanline register writes (PPUCTRL, PPUSCROLL)
2. ✅ Implement accurate VBlank flag timing
3. ✅ Implement NMI suppression (reading $2002 on dot 0/1)
4. ✅ Implement accurate sprite 0 hit timing
5. ✅ Implement rendering glitches
6. ✅ Test with games that use these effects

**Deliverables:**
- Enhanced PPU rendering
- Timing-accurate register writes
- Tests for visual effects

**Acceptance:**
- Games with split-screen effects work (SMB3)
- Games with sprite 0 scrolling work (SMB1)
- VBlank timing accurate (no NMI bugs)

---

### Phase 7: APU State Machine (Week 9)

**Goal:** Implement APU for audio generation.

**Tasks:**
1. ✅ Create `ApuState` struct
2. ✅ Implement pulse channels
3. ✅ Implement triangle channel
4. ✅ Implement noise channel
5. ✅ Implement DMC channel
6. ✅ Implement frame counter
7. ✅ Implement audio output

**Deliverables:**
- `src/apu/Apu.zig` (state machine)
- `src/apu/channels.zig` (audio channels)
- 30+ tests

**Acceptance:**
- Audio plays correctly
- Frame counter timing accurate
- All tests pass

---

### Phase 8: Testing & Validation (Week 10)

**Goal:** Comprehensive testing against AccuracyCoin.

**Tasks:**
1. ✅ Run AccuracyCoin test suite
2. ✅ Fix any failing tests
3. ✅ Verify timing accuracy
4. ✅ Performance profiling
5. ✅ Optimize hot paths

**Deliverables:**
- AccuracyCoin results
- Performance report
- Optimization notes

**Acceptance:**
- AccuracyCoin CPU tests pass
- AccuracyCoin PPU tests pass
- 60 FPS achieved
- <10% CPU usage

---

### Phase 9: Documentation & Cleanup (Week 11)

**Goal:** Complete documentation and remove legacy code.

**Tasks:**
1. ✅ Update all documentation in `docs/`
2. ✅ Create architecture diagrams
3. ✅ Write developer guide
4. ✅ Remove legacy synchronous code (if any)
5. ✅ Remove dead code
6. ✅ Clean up comments

**Deliverables:**
- Updated documentation
- Architecture diagrams
- Developer guide
- Clean codebase

**Acceptance:**
- All docs up to date
- No dead code
- Code well-commented
- Ready for posterity

---

## 10. Testing Strategy

### 10.1 Unit Tests

**Per-Component Testing:**
- CPU: Test each instruction individually
- PPU: Test each register, timing behavior
- APU: Test each channel, frame counter
- Bus: Test memory access, mirroring
- CIC: Test authentication sequence

**Coverage Goal:** >95% for emulation core

### 10.2 Integration Tests

**Component Interaction:**
- CPU-PPU: NMI timing, sprite 0 hit
- CPU-APU: Audio generation
- PPU-Bus: Register access, DMA
- Full system: Frame execution

**AccuracyCoin Tests:**
- Run each test in isolation
- Verify exact behavior matches hardware
- Document any deviations

### 10.3 Regression Tests

**Critical Requirement:** ALL tests must pass after each phase.

**Current Tests (112):**
- Bus tests: 16
- CPU tests: 70
- Cartridge tests: 42
- Configuration tests: 20 (new)
- State machine tests: 30 (new)
- PPU tests: 40 (new)
- APU tests: 30 (new)
- **Total Target: 250+ tests**

### 10.4 Performance Tests

**Metrics:**
- Frame rate (target: 60 FPS NTSC)
- CPU usage (target: <10%)
- Memory usage (target: <100 MB)
- Latency (input to display: <16ms)

**Tools:**
- Zig built-in profiler
- perf (Linux)
- Valgrind (memory)
- Custom frame timing

---

## 11. Migration & Cleanup

### 11.1 Legacy Code Removal

**Identify and Remove:**
1. ✅ Old synchronous code that's been refactored
2. ✅ Unused helper functions
3. ✅ Dead test code
4. ✅ Commented-out experiments
5. ✅ Temporary debugging code

**Process:**
1. Run `git grep -n "TODO\|FIXME\|HACK"` - address all
2. Run `git grep -n "XXX\|DEPRECATED"` - remove all
3. Check for unused imports
4. Check for unreachable code paths
5. Verify all tests still pass after removal

### 11.2 Session Documentation

**Create Session Note:**
`docs/06-implementation-notes/sessions/2025-10-03-hybrid-architecture.md`

**Content:**
- Research findings (CPU variants, CIC chips, SPSC patterns)
- Architecture review (critical findings)
- Hybrid architecture decision (rationale)
- Implementation plan (11-week schedule)
- Testing strategy (250+ tests)
- Configuration expansion (hardware variants)

### 11.3 Preservation Documentation

**Create Preservation Document:**
`docs/01-architecture/hybrid-emulation-design.md`

**Content:**
- Architectural principles (deterministic state machine)
- RT loop design (PPU cycle granularity)
- Component decoupling (zero coupling principle)
- Timing coordination (independent clocks, coordinated execution)
- Visual glitch emulation (timing-dependent effects)
- libxev integration (async I/O layer)
- Hardware configuration (variant support)

**Purpose:** Future developers can understand the design decisions and rationale.

---

## 12. Critical Success Factors

### 12.1 Non-Negotiables

✅ **Zero Regressions:** All existing tests must pass at every phase
✅ **Cycle Accuracy:** Timing must match hardware exactly
✅ **Deterministic Execution:** Same inputs → same outputs
✅ **Clean Separation:** Emulation core isolated from I/O
✅ **Parameterized Hardware:** Configuration controls all variants

### 12.2 Validation Checkpoints

**After Each Phase:**
1. Run full test suite (`zig build test`)
2. Verify 0 regressions
3. Run specific phase tests
4. Update STATUS.md
5. Commit with descriptive message

**Before Final Release:**
1. Run AccuracyCoin full suite
2. Verify 60 FPS performance
3. Check memory usage
4. Validate save states work
5. Update all documentation

---

## Appendix A: Key Design Decisions

### A.1 Why Single-Threaded Emulation Core?

**Decision:** Keep CPU/PPU/APU in single thread, advance by PPU cycles.

**Rationale:**
1. **Hardware Accuracy:** Real NES is synchronous with shared clock
2. **Determinism:** Single thread = predictable execution order
3. **Simplicity:** No race conditions, no synchronization overhead
4. **Debugging:** Much easier to debug and trace
5. **Performance:** No context switching, better cache locality

**Trade-off:** Cannot leverage multi-core for emulation core (but I/O can be parallel).

### A.2 Why PPU Cycle Granularity?

**Decision:** Advance emulation by 1 PPU cycle (not CPU cycle or frame).

**Rationale:**
1. **Finest Granularity:** PPU runs 3× CPU, so PPU cycle is finest unit
2. **Visual Accuracy:** Mid-scanline effects require PPU-level timing
3. **Sprite 0 Hit:** Requires cycle-accurate pixel rendering
4. **DMA Timing:** OAM DMA must track PPU cycles

**Trade-off:** More ticks per frame (89,342 vs 29,780) but necessary for accuracy.

### A.3 Why libxev for I/O?

**Decision:** Use libxev event loop for all async I/O.

**Rationale:**
1. **Cross-Platform:** Works on Linux, macOS, Windows
2. **Efficient:** epoll/kqueue/IOCP under the hood
3. **Zig-Native:** Written in Zig, no C dependencies
4. **Future-Proof:** Can add network play, async ROM loading

**Trade-off:** Adds dependency, but it's already in build.zig.zon.

### A.4 Why Parameterized Hardware?

**Decision:** All hardware variants use same code, behavior controlled by config.

**Rationale:**
1. **Maintainability:** One codebase for all NES variants
2. **Testing:** Can test different configs without code changes
3. **AccuracyCoin:** Can match exact target hardware
4. **Future:** Easy to add new variants (Dendy, PlayChoice-10)

**Trade-off:** Slightly more complex code, but much better long-term.

---

## Appendix B: Resources

**Documentation:**
- AccuracyCoin CPU Requirements: `docs/05-testing/accuracycoin-cpu-requirements.md`
- 6502 Timing Quirks: `docs/06-implementation-notes/design-decisions/6502-hardware-timing-quirks.md`
- CPU Execution Architecture: `docs/06-implementation-notes/design-decisions/cpu-execution-architecture.md`
- Memory Bus Implementation: `docs/06-implementation-notes/design-decisions/memory-bus-implementation.md`

**Research:**
- CPU Variants: RP2A03G/H (NTSC), RP2A07 (PAL)
- PPU Variants: RP2C02G (NTSC), RP2C07 (PAL)
- CIC Chips: CIC-NES-3193/3195/3197
- SPSC Patterns: Lock-free ring buffers
- Board Revisions: NES vs Famicom differences

**External:**
- NESDev Wiki: https://www.nesdev.org/wiki/
- libxev: https://github.com/mitchellh/libxev
- AccuracyCoin: Local folder `AccuracyCoin/`

---

**End of Final Hybrid Architecture Design**

**Status:** APPROVED - Ready for Implementation
**Next Step:** Begin Phase 1 (Configuration System Expansion)
