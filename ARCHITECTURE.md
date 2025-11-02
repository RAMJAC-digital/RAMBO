# RAMBO Architecture Reference

**Purpose:** Quick reference for core architectural patterns and design principles used throughout RAMBO.

**Target Audience:** Developers working on RAMBO codebase.

---

## Table of Contents

1. [Core Principles](#core-principles)
2. [State/Logic Separation Pattern](#statelogic-separation-pattern)
3. [Comptime Generics (Zero-Cost Polymorphism)](#comptime-generics-zero-cost-polymorphism)
4. [Thread Architecture](#thread-architecture)
5. [VBlank Pattern (Pure Data Ledgers)](#vblank-pattern-pure-data-ledgers)
6. [DMA Interaction Model](#dma-interaction-model)
7. [RT-Safety Guidelines](#rt-safety-guidelines)
8. [Quick Pattern Reference](#quick-pattern-reference)

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
    const step = self.nextTimingStep();  // Advance clock
    const scanline = self.clock.scanline();
    const dot = self.clock.dot();

    // 1. PPU rendering (pixel output)
    var ppu_result = self.stepPpuCycle(scanline, dot);

    // 2. APU processing (BEFORE CPU for IRQ state)
    if (step.apu_tick) {
        const apu_result = self.stepApuCycle();
    }

    // 3. CPU memory operations (reads/writes including $2002)
    if (step.cpu_tick) {
        self.cpu.irq_line = ...;
        _ = self.stepCpuCycle();  // ← CPU executes FIRST
    }

    // 4. PPU flag updates (VBlank set, sprite eval, etc.)
    self.applyPpuCycleResult(ppu_result);  // ← VBlank flag set AFTER CPU
}
```

**Critical Race Condition:**
When CPU reads $2002 at scanline 241, dot 1 (same cycle VBlank is set):
- CPU reads $2002 → sees VBlank bit = 0 (flag not set yet)
- PPU sets VBlank flag → flag becomes 1
- Result: CPU missed VBlank flag (same-cycle race)

**Hardware Citation:** https://www.nesdev.org/wiki/PPU_frame_timing

**Files:**
- `src/emulation/State.zig:tick()` lines 617-699
- `src/emulation/State.zig:applyPpuCycleResult()` lines 701-727
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

## DMA Interaction Model

**Core Concept:** Hardware-accurate DMC/OAM DMA time-sharing with functional pattern.

### Time-Sharing Behavior

**From nesdev.org specification:**

```
DMC DMA has absolute priority over OAM DMA.

When DMC triggers during OAM:
- OAM pauses ONLY during DMC halt (cycle 1) and read (cycle 4)
- OAM continues during DMC dummy (cycle 2) and alignment (cycle 3)
- Total DMC: 4 cycles (halt, dummy, align, read)
- OAM resumes after DMC read completes
```

### Implementation Pattern

```zig
// Functional edge detection (no state machine)
pub fn tickOamDma(state: *EmulationState) void {
    // Check if DMC is halting OAM
    const dmc_is_halting = state.dmc_dma.rdy_low and
        (state.dmc_dma.stall_cycles_remaining == 4 or  // Halt cycle
         state.dmc_dma.stall_cycles_remaining == 1);   // Read cycle

    if (dmc_is_halting) {
        return;  // Pause OAM during DMC cycles 1 and 4 only
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

**Version:** 1.0
**Last Updated:** 2025-10-17
**Status:** Complete reference for Phase 2 patterns
