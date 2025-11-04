# RAMBO Architecture Reference

**Purpose:** Quick reference for core architectural patterns and design principles used throughout RAMBO.

**Target Audience:** Developers working on RAMBO codebase.

---

## Table of Contents

1. [Core Principles](#core-principles)
2. [State/Logic Separation Pattern](#statelogic-separation-pattern)
3. [Comptime Generics (Zero-Cost Polymorphism)](#comptime-generics-zero-cost-polymorphism)
4. [Bus Handler Architecture](#bus-handler-architecture)
5. [Thread Architecture](#thread-architecture)
6. [VBlank Pattern (Pure Data Ledgers)](#vblank-pattern-pure-data-ledgers)
7. [Master Clock and Phase Independence](#master-clock-and-phase-independence)
8. [DMA Interaction Model](#dma-interaction-model)
9. [RT-Safety Guidelines](#rt-safety-guidelines)
10. [Quick Pattern Reference](#quick-pattern-reference)

---

## Core Principles

### 1. Hardware Accuracy First
- Cycle-accurate execution over performance optimization
- All behavior verified against nesdev.org hardware documentation
- Timing precision validated with AccuracyCoin test suite

### 2. RT-Safety
- Zero heap allocations in emulation loop
- No blocking operations in critical paths
- Deterministic execution timing
- Lock-free inter-thread communication

### 3. Testability
- Pure functions enable isolated unit testing
- State/Logic separation allows component testing without full system
- Comprehensive test suite (990/995 tests passing)

### 4. Maintainability
- Clear separation of concerns
- Single responsibility per module
- Explicit side effects
- Zero hidden state

---

## State/Logic Separation Pattern

**Core Concept:** All components use hybrid State/Logic separation for modularity, testability, and RT-safety.

### State Modules (`State.zig`)

**Characteristics:**
- Pure data structures
- Optional non-owning pointers only
- Zero hidden state
- Fully serializable (save states)
- Convenience methods that delegate to Logic

**Example:**
```zig
// src/cpu/State.zig
pub const CpuState = struct {
    // Pure data fields
    a: u8,
    x: u8,
    y: u8,
    sp: u8,
    pc: u16,
    p: StatusRegister,

    // Execution state
    instruction_cycle: u8,
    opcode: u8,
    // ... more fields ...

    // Convenience delegation (optional)
    pub inline fn tick(self: *CpuState, bus: *BusState) void {
        Logic.tick(self, bus);
    }
};
```

### Logic Modules (`Logic.zig`)

**Characteristics:**
- Pure functions operating on State pointers
- No global state
- Deterministic execution
- All side effects explicit through parameters
- Easily testable in isolation

**Example:**
```zig
// src/cpu/Logic.zig
pub fn tick(cpu: *CpuState, bus: *BusState) void {
    // Pure function - all state passed explicitly
    // No hidden dependencies
    // All mutations explicit
}

pub fn reset(cpu: *CpuState, bus: *BusState) void {
    cpu.pc = bus.read16(0xFFFC);
    cpu.sp = 0xFD;
    cpu.p = StatusRegister.init(.{ .i = true });
}
```

### Benefits

1. **Testability:** Logic functions can be tested without full system
2. **Serialization:** State can be saved/loaded for save states
3. **Debugging:** State can be inspected without side effects
4. **Refactoring:** Logic changes don't affect State layout
5. **RT-Safety:** No hidden heap allocations or locks

---

## Comptime Generics (Zero-Cost Polymorphism)

**Core Concept:** All polymorphism uses comptime duck typing - zero runtime overhead.

### Pattern

```zig
pub fn Cartridge(comptime MapperType: type) type {
    return struct {
        mapper: MapperType,
        prg_rom: []const u8,
        chr_rom: []u8,

        const Self = @This();

        // Direct delegation - no VTable, fully inlined
        pub fn cpuRead(self: *const Self, address: u16) u8 {
            return self.mapper.cpuRead(self, address);
        }

        pub fn cpuWrite(self: *Self, address: u16, value: u8) void {
            self.mapper.cpuWrite(self, address, value);
        }
    };
}
```

### Usage

```zig
// Compile-time type instantiation
const NromCart = Cartridge(Mapper0);  // Zero runtime overhead
const Mmc1Cart = Cartridge(Mapper1);  // Different type, same pattern

// Type-erased registry (when needed)
pub const AnyCartridge = union(enum) {
    nrom: Cartridge(Mapper0),
    mmc1: Cartridge(Mapper1),
    // ... more mappers ...

    pub inline fn cpuRead(self: *const AnyCartridge, address: u16) u8 {
        return switch (self.*) {
            inline else => |*cart| cart.cpuRead(address),
        };
    }
};
```

### Benefits

1. **Zero Overhead:** No VTables, all calls inlined at compile time
2. **Type Safety:** Compile-time verification of interface compliance
3. **Performance:** Optimizer can inline and constant-fold entire call chains
4. **Flexibility:** Add new mappers without modifying base Cartridge code
5. **Duck Typing:** No explicit interface definitions needed

---

## Bus Handler Architecture

**Core Concept:** Stateless handler delegation pattern for CPU memory bus, mirroring the cartridge mapper pattern.

### Handler Interface Pattern

All bus handlers implement the same interface:

```zig
pub const HandlerName = struct {
    // NO fields - completely stateless!

    pub fn read(_: *const HandlerName, state: anytype, address: u16) u8 { }
    pub fn write(_: *HandlerName, state: anytype, address: u16, value: u8) void { }
    pub fn peek(_: *const HandlerName, state: anytype, address: u16) u8 { }
};
```

### Key Characteristics

1. **Zero-Size Handlers:** No internal state, all data accessed via `state` parameter
2. **Stateless Delegation:** Handlers delegate to Logic modules (PpuLogic, ApuLogic, etc.)
3. **Debugger Support:** `peek()` provides side-effect-free reads
4. **Mirrors Mapper Pattern:** Same delegation approach as cartridge mappers (comptime polymorphism)
5. **Hardware-Aligned Boundaries:** Handler address ranges match NES chip architecture

### Address Space Handlers

| Handler | Address Range | Complexity | Hardware Chip |
|---------|---------------|------------|---------------|
| `RamHandler` | $0000-$1FFF | ⭐ (1/5) | 6502 internal RAM (2KB, 4x mirrored) |
| `PpuHandler` | $2000-$3FFF | ⭐⭐⭐⭐⭐ (5/5) | 2C02 PPU registers (8 regs, mirrored) |
| `ApuHandler` | $4000-$4015 | ⭐⭐⭐ (3/5) | 2A03 APU channels |
| `OamDmaHandler` | $4014 | ⭐⭐ (2/5) | 2C02 OAM DMA trigger |
| `ControllerHandler` | $4016-$4017 | ⭐⭐ (2/5) | Controller ports + APU frame counter |
| `CartridgeHandler` | $4020-$FFFF | ⭐⭐ (2/5) | Cartridge mapper delegation |
| `OpenBusHandler` | unmapped | ⭐ (1/5) | Hardware open bus behavior |

### Integration in EmulationState

```zig
pub const EmulationState = struct {
    handlers: struct {
        open_bus: OpenBusHandler = .{},
        ram: RamHandler = .{},
        ppu: PpuHandler = .{},
        apu: ApuHandler = .{},
        controller: ControllerHandler = .{},
        oam_dma: OamDmaHandler = .{},
        cartridge: CartridgeHandler = .{},
    } = .{},

    pub fn busRead(self: *EmulationState, address: u16) u8 {
        const value = switch (address) {
            0x0000...0x1FFF => self.handlers.ram.read(self, address),
            0x2000...0x3FFF => self.handlers.ppu.read(self, address),
            // ... other ranges ...
            else => self.handlers.open_bus.read(self, address),
        };

        // Open bus capture (hardware behavior)
        if (address != 0x4015) {  // $4015 doesn't update open bus
            self.bus.open_bus = value;
        }

        return value;
    }
};
```

### Example: PpuHandler (Most Complex)

**Responsibilities:**
- PPU register reads/writes ($2000-$3FFF, 8 registers mirrored)
- VBlank race detection (scanline 241, dot 0-2)
- NMI line management (PPUCTRL bit 7 changes)
- $2002 read side effects (clear VBlank flag, clear NMI line)

**Implementation:**
```zig
// src/emulation/bus/handlers/PpuHandler.zig
pub const PpuHandler = struct {
    // NO fields - completely stateless!

    pub fn read(_: *const PpuHandler, state: anytype, address: u16) u8 {
        const reg = address & 0x07;  // Mirror to 8 registers

        // VBlank race detection (CRITICAL TIMING)
        if (reg == 0x02 and state.ppu.scanline == 241 and state.ppu.cycle <= 2) {
            // Prevent VBlank flag from being set this frame
            state.vblank_ledger.prevent_vbl_set_cycle = state.clock.master_cycles;
        }

        // Delegate to PPU logic for register read
        const result = PpuLogic.readRegister(&state.ppu, ...);

        // $2002 read side effects
        if (result.read_2002) {
            state.vblank_ledger.last_read_cycle = state.clock.master_cycles;
            state.cpu.nmi_line = false;  // Always clear NMI line
        }

        return result.value;
    }

    pub fn write(_: *PpuHandler, state: anytype, address: u16, value: u8) void {
        const reg = address & 0x07;

        // PPUCTRL write: Update NMI line IMMEDIATELY
        if (reg == 0x00) {
            const old_nmi_enable = state.ppu.ctrl.nmi_enable;
            const new_nmi_enable = (value & 0x80) != 0;
            const vblank_active = state.vblank_ledger.isFlagVisible();

            // 0→1 transition while VBlank active: trigger NMI
            if (!old_nmi_enable and new_nmi_enable and vblank_active) {
                state.cpu.nmi_line = true;
            }

            // 1→0 transition: clear NMI
            if (old_nmi_enable and !new_nmi_enable) {
                state.cpu.nmi_line = false;
            }
        }

        // Delegate to PPU logic for register write
        PpuLogic.writeRegister(&state.ppu, ...);
    }

    pub fn peek(_: *const PpuHandler, state: anytype, address: u16) u8 {
        // No side effects - safe for debugger
        const reg = address & 0x07;
        return state.ppu.registers[reg];
    }
};
```

### Design Principles

1. **No Internal State:** Handlers are zero-size (verified by unit tests)
2. **Pure Delegation:** Handlers delegate to Logic modules, don't implement logic themselves
3. **Explicit Side Effects:** All side effects visible in handler code (no hidden behavior)
4. **Hardware Mirroring:** Handler boundaries match NES hardware chip boundaries
5. **Testability:** Each handler has isolated unit tests

### Benefits

- **Clear Separation:** Each handler owns its address space (mirrors hardware)
- **Testable:** Handlers unit-tested independently from full EmulationState
- **Debugger-Safe:** `peek()` allows inspection without side effects
- **Zero Overhead:** Handlers are zero-size, all calls inlined by compiler
- **Maintainable:** Modular design easier to understand than monolithic bus routing

### Anti-Patterns to Avoid

**DON'T: Put state in handlers**
```zig
// WRONG - Handler has internal state!
pub const BadHandler = struct {
    last_value: u8 = 0,  // NO! Handlers must be stateless!
};
```

**DO: Access state via parameter**
```zig
// CORRECT - Handler is stateless
pub const GoodHandler = struct {
    // NO fields!

    pub fn read(_: *const GoodHandler, state: anytype, address: u16) u8 {
        return state.bus.open_bus;  // Access state via parameter
    }
};
```

### See Also

- `src/emulation/bus/handlers/` - All handler implementations
- `src/emulation/bus/inspection.zig` - Debugger-safe bus inspection (uses handler `peek()`)
- `src/cartridge/` - Cartridge mapper pattern (same delegation approach)
- `src/emulation/State.zig` - EmulationState bus routing integration

---

## Thread Architecture

**Core Concept:** 3-thread mailbox pattern with RT-safe emulation.

### Thread Roles

```
┌────────────────┐
│  Main Thread   │  Coordinator (minimal work)
│                │  - Event loop (libxev)
│                │  - Input handling
│                │  - Thread lifecycle
└───────┬────────┘
        │
        ├─────────────┐
        │             │
┌───────▼────────┐ ┌──▼─────────────┐
│ Emulation      │ │ Render Thread  │
│ Thread         │ │                │
│                │ │ - Wayland      │
│ - CPU cycles   │ │ - Vulkan       │
│ - PPU cycles   │ │ - 60 FPS       │
│ - APU cycles   │ │                │
│ - RT-safe      │ │                │
│ - Zero allocs  │ │                │
└────────────────┘ └────────────────┘
```

### Communication via Lock-Free Mailboxes

| Mailbox | Direction | Purpose | Implementation |
|---------|-----------|---------|----------------|
| `FrameMailbox` | Emulation → Render | Double-buffered RGBA frames | Triple-buffer atomic swap |
| `ControllerInputMailbox` | Main → Emulation | NES button state | Mutex-protected (not SPSC) |
| `DebugCommandMailbox` | Main → Emulation | Breakpoints, watchpoints | SpscRingBuffer |
| `DebugEventMailbox` | Emulation → Main | Debug events, snapshots | SpscRingBuffer |
| `XdgInputEventMailbox` | Render → Main | Keyboard/mouse events | SpscRingBuffer |
| `XdgWindowEventMailbox` | Render → Main | Window events | SpscRingBuffer |

### RT-Safety Guarantees

**Emulation Thread:**
- Zero heap allocations in hot path
- No blocking I/O operations
- No mutex waits
- Deterministic execution time
- Atomic mailbox operations only

**Example:**
```zig
// src/threads/EmulationThread.zig
pub fn run(self: *EmulationThread) void {
    while (self.running.load(.acquire)) {
        // RT-safe cycle execution (no allocations)
        self.state.tick();

        // Check for frame completion
        if (self.state.frame_complete) {
            // Atomic frame swap (lock-free)
            self.mailboxes.frame.swap(&self.state.ppu.frame_buffer);
            self.state.frame_complete = false;
        }
    }
}
```

---

## VBlank Pattern (Pure Data Ledgers)

**Core Concept:** Timestamp-based edge detection with external state management.

### Reference Implementation: VBlankLedger

```zig
pub const VBlankLedger = struct {
    // Pure data fields (timestamps only)
    last_set_cycle: u64 = 0,
    last_clear_cycle: u64 = 0,
    last_read_cycle: u64 = 0,
    race_hold: bool = false,

    // ONLY mutation method
    pub fn reset(self: *VBlankLedger) void {
        self.* = .{};
    }

    // NO business logic
    // NO decision-making
    // Just timestamps
};
```

### Key Principles

1. **Pure Data:** Ledger stores only timestamps and flags
2. **Single Mutation Method:** Only `reset()` method exists
3. **External State Management:** All mutations happen in EmulationState
4. **No Business Logic:** Ledger has no decision-making code
5. **Timestamp-Based Edges:** Detect events by comparing timestamps

### Usage Pattern

```zig
// In EmulationState.zig
pub fn setVBlankFlag(state: *EmulationState) void {
    const cycle = state.master_clock.ppu_cycle;

    // Direct field assignment (no ledger methods)
    state.vblank_ledger.last_set_cycle = cycle;
    state.ppu.status.vblank = true;

    // Check for NMI trigger
    if (state.ppu.ctrl.nmi_enable) {
        state.cpu.nmi_line = true;
    }
}

pub fn clearVBlankFlag(state: *EmulationState) void {
    const cycle = state.master_clock.ppu_cycle;

    // Direct field assignment (no ledger methods)
    state.vblank_ledger.last_clear_cycle = cycle;
    state.ppu.status.vblank = false;
}
```

### Sub-Cycle Execution Order (CRITICAL)

**LOCKED BEHAVIOR** - Do not modify without hardware justification.

VBlank flag updates must follow hardware-accurate sub-cycle execution order:

**Within a single PPU cycle:**
1. CPU read operations (if CPU active this cycle)
2. CPU write operations (if CPU active this cycle)
3. PPU flag updates (VBlank set, sprite evaluation, etc.)
4. End of cycle

**Implementation in EmulationState.tick():**
```zig
pub fn tick(self: *EmulationState) void {
    // Advance clocks
    PpuLogic.advanceClock(&self.ppu, self.rendering_enabled);
    self.clock.advance();
    const step = self.nextTimingStep();

    // 1. PPU rendering (pixel output)
    const ppu_result = self.stepPpuCycle(scanline, dot);

    // 2. APU processing (BEFORE CPU for IRQ state)
    if (step.apu_tick) {
        const apu_result = self.stepApuCycle();
    }

    // 3. CPU execution BEFORE VBlank timestamps
    //    (allows CPU to set prevention flag via $2002 reads)
    if (step.cpu_tick) {
        self.cpu.irq_line = ...;
        _ = self.stepCpuCycle();  // ← CPU reads $2002, sets prevention flag
    }

    // 4. VBlank timestamps applied AFTER CPU execution
    //    (respects prevention flag set by CPU)
    self.applyVBlankTimestamps(ppu_result);

    // 5. Interrupt sampling AFTER VBlank state is final
    //    (ensures NMI line reflects correct VBlank state including prevention)
    if (step.cpu_tick and self.cpu.state != .interrupt_sequence) {
        self.cpu.nmi_line = ...;  // Set from finalized VBlank state
        CpuLogic.checkInterrupts(&self.cpu);
        self.cpu.nmi_pending_prev = ...;
        self.cpu.irq_pending_prev = ...;
    }

    // 6. Other PPU state applied AFTER CPU execution
    //    (reflects CPU register writes from this cycle)
    self.applyPpuRenderingState(ppu_result);
}
```

**Critical Implementation Detail (2025-11-03):**
CPU execution BEFORE VBlank timestamps allows prevention mechanism to work:
- CPU reads $2002 at dot 1 → sets `prevent_vbl_set_cycle = master_cycles`
- `applyVBlankTimestamps()` checks if `master_cycles == prevent_vbl_set_cycle` → skips setting flag if true
- Interrupt sampling happens AFTER VBlank state is finalized (ensures correct NMI line state)
- Other PPU state (rendering_enabled, frame_complete) applied AFTER CPU to reflect register writes
- Reference: Mesen2 NesPpu.cpp:1340-1344 (prevention flag check before VBlank set)

**Critical Race Condition:**
When CPU reads $2002 at scanline 241, dot 1 (same cycle VBlank is set):
- CPU reads $2002 → sees VBlank bit = 0 (flag not set yet), sets prevention flag
- PPU checks prevention flag → skips setting VBlank (prevented)
- Result: VBlank flag never sets (correct hardware behavior)

**Hardware Citation:** https://www.nesdev.org/wiki/PPU_frame_timing

**Files:**
- `src/emulation/State.zig:tick()` lines 651-774
- `src/emulation/State.zig:applyVBlankTimestamps()` lines 776-804
- `src/emulation/State.zig:applyPpuRenderingState()` lines 806-814
- `src/emulation/VBlankLedger.zig` (pure data ledger)

**Test Coverage:**
- `tests/emulation/state/vblank_ledger_test.zig` (updated 2025-11-02)
- `tests/emulation/state_test.zig` (updated 2025-11-02)

### Anti-Pattern: Business Logic in Ledger

**WRONG:**
```zig
// DON'T DO THIS - Business logic in ledger
pub fn recordOamPause(self: *DmaLedger, state: OamState) void {
    self.oam_pause_cycle = cycle;
    self.interrupted_state = state;

    // Business logic decision in data structure! WRONG!
    if (state.was_reading) {
        self.duplication_pending = true;
    }
}
```

**CORRECT:**
```zig
// DO THIS - Business logic in EmulationState
pub fn handleOamPause(state: *EmulationState, oam_state: OamState) void {
    const cycle = state.master_clock.cpu_cycle;

    // Direct field assignment
    state.dma_ledger.oam_pause_cycle = cycle;
    state.dma_ledger.interrupted_state = oam_state;

    // Business logic stays in EmulationState
    if (oam_state.was_reading) {
        state.dma_ledger.duplication_pending = true;
    }
}
```

---

## Master Clock and Phase Independence

**Core Concept:** Separate monotonic master clock from PPU timing to enable CPU/PPU phase independence.

### Hardware Background

Real NES hardware has random CPU/PPU phase alignment at power-on (0, 1, or 2):
- **Phase 0:** CPU ticks when `master_cycles % 3 == 0` (dots 0, 3, 6, 9... at scanline 241)
- **Phase 1:** CPU ticks when `master_cycles % 3 == 0` (dots 1, 4, 7, 10... at scanline 241)
- **Phase 2:** CPU ticks when `master_cycles % 3 == 0` (dots 2, 5, 8, 11... at scanline 241)

Phase affects which PPU dots the CPU can execute during VBlank set (scanline 241, dot 1).

**Reference:** Mesen2 NesCpu.cpp lines 142-148 (randomizes `_ppuOffset` for hardware accuracy)

### Architecture (Post-Master-Clock-Refactor)

**MasterClock** (`src/emulation/MasterClock.zig`):
```zig
pub const MasterClock = struct {
    master_cycles: u64 = 0,        // Monotonic counter (never skips)
    initial_phase: u2 = 0,         // CPU/PPU phase offset (0, 1, or 2)

    pub fn advance(self: *MasterClock) void {
        self.master_cycles +%= 1;  // ALWAYS +1 (monotonic)
    }

    pub fn isCpuTick(self: MasterClock) bool {
        return (self.master_cycles % 3) == 0;
    }
};
```

**PpuState** (`src/ppu/State.zig`):
```zig
pub const PpuState = struct {
    cycle: u16 = 0,           // 0-340 (dot within scanline)
    scanline: i16 = -1,       // -1 (pre-render) to 260
    frame_count: u64 = 0,     // Frame counter

    // PPU owns its own timing (separate from master clock)
};
```

### Separation of Concerns

| Clock | Purpose | Characteristics |
|-------|---------|----------------|
| **Master Clock** | Event timestamps | Monotonic (0, 1, 2, 3...), never skips |
| **PPU Clock** | Hardware position | Can skip (odd frame skip), PPU owns it |

**Key Insight:** PPU clock (scanline/cycle) is NOT derived from master clock. PPU has its own state that advances via `PpuLogic.advanceClock()`.

### Phase-Independent Logic Example

**WRONG (phase-dependent):**
```zig
// Assumes CPU ticks at dot 1 (only works for phase 0)
if (dot == 1) {
    prevent_vbl_set_cycle = master_cycles;
}
```

**CORRECT (phase-independent):**
```zig
// Works for ALL phases by checking if CPU is ticking NOW
if (self.clock.isCpuTick() and scanline == 241 and dot <= 2) {
    prevent_vbl_set_cycle = master_cycles;
}
```

### Benefits

1. **Phase Independence:** VBlank/NMI timing works for all phases (0, 1, 2)
2. **Hardware Accuracy:** Mirrors Mesen2 separation of `_masterClock` and `_cycle`
3. **Monotonic Timestamps:** `master_cycles` never skips (safe for comparisons)
4. **PPU Ownership:** PPU handles odd frame skip in its own clock logic

### Testing Different Phases

```zig
// Phase 0 (default)
var clock = MasterClock.init();

// Phase 1 or 2 (for testing)
var clock = MasterClock.initWithPhase(1);
```

Tests should use `clock.isCpuTick()` instead of hardcoded dot values to be phase-independent.

**Reference:** `src/emulation/MasterClock.zig`, `src/ppu/Logic.zig:advanceClock()`

---

## DMA Interaction Model

**Core Concept:** Hardware-accurate DMC/OAM DMA time-sharing with functional pattern.

### Time-Sharing Behavior

**From nesdev.org specification:**

```
DMC DMA has absolute priority over OAM DMA.

When DMC triggers during OAM:
- OAM continues during DMC halt (cycle 4), dummy (cycle 3), and alignment (cycle 2)
- OAM pauses ONLY during DMC read (cycle 1)
- Total DMC: 4 cycles (halt, dummy, align, read)
- Net overhead: ~2 cycles (4 DMC - 3 OAM advancement + 1 post-DMC alignment)
- OAM resumes after DMC read completes with one alignment cycle
```

**Hardware Citations:**
- Primary: https://www.nesdev.org/wiki/DMA#DMC_DMA_during_OAM_DMA
- Reference Implementation: Mesen2 NesCpu.cpp:385 "Sprite DMA cycles count as halt/dummy cycles for the DMC"

### Implementation Pattern

```zig
// Functional edge detection (no state machine)
pub fn tickOamDma(state: *EmulationState) void {
    // Check if DMC is stalling OAM
    // Hardware time-sharing: OAM continues during halt/dummy/alignment,
    // only pauses during actual DMC read cycle
    const dmc_is_stalling_oam = state.dmc_dma.rdy_low and
        state.dmc_dma.stall_cycles_remaining == 1;  // Only DMC read cycle

    if (dmc_is_stalling_oam) {
        return;  // Pause OAM during DMC read cycle only
    }

    // Check if post-DMC alignment cycle needed
    if (state.dma_interaction_ledger.needs_alignment_after_dmc) {
        state.dma_interaction_ledger.needs_alignment_after_dmc = false;
        return;  // Consume alignment cycle
    }

    // Otherwise OAM executes normally (time-sharing on bus)
    // ... OAM execution logic ...
}
```

### DMA Ledger Pattern

```zig
pub const DmaInteractionLedger = struct {
    // Pure timestamps (VBlank pattern)
    dmc_active_cycle: u64 = 0,
    dmc_inactive_cycle: u64 = 0,
    oam_pause_cycle: u64 = 0,
    oam_resume_cycle: u64 = 0,

    // State preservation (no business logic)
    interrupted_state: OamInterruptedState = .{},
    duplication_pending: bool = false,

    // ONLY mutation method
    pub fn reset(self: *DmaInteractionLedger) void {
        self.* = .{};
    }
};
```

### Key Points

1. **No State Machine:** Use functional edge detection instead
2. **Time-Sharing:** OAM continues during DMC cycles 2 and 3
3. **Pure Ledger:** Timestamps only, no business logic
4. **External Mutations:** All state changes in EmulationState
5. **Hardware Accurate:** Matches nesdev.org specification exactly

---

## RT-Safety Guidelines

### Rules for Emulation Thread

1. **Zero Heap Allocations**
   - No `allocator.alloc()` calls
   - No `ArrayList`, `HashMap`, etc.
   - Stack-only allocations

2. **No Blocking Operations**
   - No `std.Thread.wait()`
   - No `std.Mutex.lock()` (except mailbox atomics)
   - No file I/O

3. **Deterministic Execution**
   - No random number generation (except power-on RAM init)
   - No system calls
   - Predictable timing

4. **Lock-Free Communication**
   - Atomic operations only
   - SPSC ring buffers
   - No mutex waits

### Verification Checklist

```zig
// GOOD - RT-safe
pub fn tick(cpu: *CpuState, bus: *BusState) void {
    const opcode = bus.read(cpu.pc);  // Stack variables only
    cpu.pc +%= 1;
    executeOpcode(cpu, bus, opcode);
}

// BAD - Not RT-safe
pub fn tick(cpu: *CpuState, bus: *BusState, allocator: Allocator) !void {
    const history = try allocator.alloc(u8, 100);  // Heap allocation!
    defer allocator.free(history);
    // ...
}
```

---

## Quick Pattern Reference

### State/Logic Separation

```zig
// State.zig - Pure data
pub const State = struct {
    field1: u8,
    field2: u16,

    pub inline fn method(self: *State) void {
        Logic.method(self);  // Delegate to Logic
    }
};

// Logic.zig - Pure functions
pub fn method(state: *State) void {
    // All state passed explicitly
}
```

### Comptime Generics

```zig
pub fn Generic(comptime T: type) type {
    return struct {
        data: T,

        pub fn method(self: *@This()) void {
            // Comptime instantiated, zero overhead
        }
    };
}
```

### Bus Handler Pattern

```zig
// Handler - Zero-size, stateless
pub const Handler = struct {
    // NO fields!

    pub fn read(_: *const Handler, state: anytype, address: u16) u8 {
        // Delegate to Logic modules
        return Logic.read(&state.component, address);
    }

    pub fn peek(_: *const Handler, state: anytype, address: u16) u8 {
        // No side effects - debugger safe
        return state.component.registers[address & 0x07];
    }
};

// Integration in EmulationState
pub const EmulationState = struct {
    handlers: struct {
        handler: Handler = .{},
    } = .{},

    pub fn busRead(self: *EmulationState, address: u16) u8 {
        return self.handlers.handler.read(self, address);
    }
};
```

### VBlank Ledger Pattern

```zig
pub const Ledger = struct {
    timestamp: u64 = 0,
    flag: bool = false,

    pub fn reset(self: *Ledger) void {
        self.* = .{};  // Only mutation method
    }
};
```

### Functional Edge Detection

```zig
// NO state machine
pub fn shouldTrigger(state: *State, cycle: u64) bool {
    return state.flag and
           cycle == state.trigger_cycle and
           state.other_condition;
}
```

### RT-Safe Mailbox

```zig
// Atomic swap (lock-free)
pub fn swap(self: *Mailbox, new_data: *Data) void {
    const old_index = self.write_index.swap(
        (old_index + 1) % 3,
        .acq_rel
    );
    self.buffers[old_index] = new_data.*;
}
```

---

## Related Documentation

- **Full Architecture:** `docs/dot/architecture.dot` (visual diagram)
- **Thread Details:** `docs/architecture/threading.md`
- **Component Structure:** `docs/architecture/codebase-inventory.md`
- **Development Guide:** `CLAUDE.md`

---

**Version:** 1.2
**Last Updated:** 2025-11-04
**Status:** Complete reference for Phase 2 patterns + Bus Handler Architecture
**Recent Update:** Bus handler architecture migration complete (2025-11-04) - Zero-size stateless handlers replacing monolithic routing
