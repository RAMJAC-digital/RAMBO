# RAMBO Architecture Reference

**Purpose:** Quick reference for core architectural patterns and design principles used throughout RAMBO.

**Target Audience:** Developers working on RAMBO codebase.

---

## Table of Contents

1. [Core Principles](#core-principles)
2. [State/Logic Separation Pattern](#statelogic-separation-pattern)
3. [Table-Driven Dispatch Pattern (CPU Execution)](#table-driven-dispatch-pattern-cpu-execution)
4. [Comptime Generics (Zero-Cost Polymorphism)](#comptime-generics-zero-cost-polymorphism)
5. [Bus Handler Architecture](#bus-handler-architecture)
6. [Thread Architecture](#thread-architecture)
7. [VBlank Pattern (Pure Data Ledgers)](#vblank-pattern-pure-data-ledgers)
8. [Master Clock and Phase Independence](#master-clock-and-phase-independence)
9. [DMA Interaction Model](#dma-interaction-model)
10. [RT-Safety Guidelines](#rt-safety-guidelines)
11. [Quick Pattern Reference](#quick-pattern-reference)

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

pub fn power_on(state: *CpuState, reset_vector: u16) void {
    // Hardware-accurate power-on sequence
    // EmulationState delegates instead of direct manipulation
    state.pc = reset_vector;
    state.sp = 0xFD;
    state.p = StatusRegister.init(.{ .i = true });
}

pub fn reset(state: *CpuState, reset_vector: u16) void {
    // Hardware-accurate reset sequence
    // Similar to power_on but preserves some state
    state.pc = reset_vector;
    state.sp -%= 3;  // Decrement stack pointer by 3
    state.p.i = true;  // Set interrupt disable flag
}
```

**Lifecycle Functions:**
- CPU: `power_on()`, `reset()` - Hardware-accurate initialization sequences
- PPU: `power_on()`, `reset()` - Hardware-accurate PPU initialization
- APU: Similar lifecycle functions for APU initialization
- Eliminates direct state manipulation from EmulationState (black box principle)

### Benefits

1. **Testability:** Logic functions can be tested without full system
2. **Serialization:** State can be saved/loaded for save states
3. **Debugging:** State can be inspected without side effects
4. **Refactoring:** Logic changes don't affect State layout
5. **RT-Safety:** No hidden heap allocations or locks

---

## Table-Driven Dispatch Pattern (CPU Execution)

**Core Concept:** Replace nested switch statements with comptime-built lookup tables for declarative dispatch logic with zero runtime overhead.

**Implemented in:** CPU execution system (src/cpu/MicrostepTable.zig, src/cpu/Execution.zig)

### Architecture (Refactored 2025-11-07)

**Before (Nested Switches - 533 lines):**
```zig
// Opcode dispatch required 3 separate switches:
// 1. Check if addressing needed (opcode list)
switch (opcode) {
    0x20, 0x60, 0x40, 0x00, 0x48, 0x08, 0x68, 0x28 => ...,
}
// 2. Dispatch microstep (nested switch on mode + cycle)
switch (address_mode) {
    .absolute => switch (instruction_cycle) {
        0 => fetchAbsLow(bus),
        1 => fetchAbsHigh(bus),
    },
    // ... 12 more modes, 217 lines total
}
// 3. Check completion (threshold per mode)
switch (address_mode) {
    .absolute => instruction_cycle >= 2,
    // ... duplication of structure
}
```

**After (Table-Driven - 279 lines):**
```zig
// Single table lookup
const sequence = MicrostepTable.MICROSTEP_TABLE[opcode];
const microstep_idx = sequence.steps[instruction_cycle];
const early_complete = MicrostepTable.callMicrostep(microstep_idx, bus);
const addressing_done = (instruction_cycle >= sequence.max_cycles);
```

### Table Structure

**MicrostepSequence:**
```zig
pub const MicrostepSequence = struct {
    steps: []const u8,           // Microstep indices to execute (e.g., [5, 6, 7, 8])
    max_cycles: u8,              // Maximum addressing cycles (e.g., 4)
    operand_source: OperandSource, // How to fetch operand (immediate_pc, temp_value, etc.)
};
```

**MICROSTEP_TABLE[256]:**
- Comptime-built at compile time (zero runtime cost)
- Maps every opcode to its complete microstep sequence
- 39 predefined sequences (13 addressing modes × 3 variants: read/write/rmw)
- 8 special opcode sequences (JSR, RTS, RTI, BRK, PHA, PHP, PLA, PLP)

**Example Entry:**
```zig
// Absolute,X read mode (e.g., LDA $1234,X)
const ABSOLUTE_X_READ_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 5, 6, 7, 8 }, // fetchAbsLow, fetchAbsHigh, calcAbsoluteX, fixHighByte
    .max_cycles = 4,               // 2-4 cycles (page cross adds cycle)
    .operand_source = .temp_value, // Value loaded by microsteps
};
```

### Early Completion Pattern

**Problem:** Some instructions complete in fewer cycles based on runtime conditions:
- Branches: 2 cycles (not taken) vs 3 cycles (taken) vs 4 cycles (taken + page cross)
- Indexed reads: 3 cycles (no page cross) vs 4 cycles (page crossed)

**Solution:** Microsteps return bool to signal early completion:
```zig
pub fn branchFetchOffset(state: anytype) bool {
    state.cpu.operand_low = state.busRead(state.cpu.pc);
    state.cpu.pc +%= 1;
    const should_branch = /* check condition based on opcode */;
    if (!should_branch) {
        return true;  // Branch not taken - complete immediately (2 cycles)
    }
    return false;  // Branch taken - continue to next microstep (3-4 cycles)
}
```

**Execution Loop:**
```zig
if (cpu.instruction_cycle < sequence.steps.len) {
    const microstep_idx = sequence.steps[cpu.instruction_cycle];
    const early_complete = MicrostepTable.callMicrostep(microstep_idx, bus);
    if (early_complete) {
        // Instruction done - advance to next instruction
        cpu.state = .fetch_opcode;
        return;
    }
}
```

### Benefits

1. **Single Source of Truth:** Opcode timing defined once in table, not duplicated across 3+ switch sites
2. **Declarative:** Specify WHAT microsteps to run, not HOW to dispatch them
3. **Maintainable:** Adding new opcode = add 1 table entry (not edit 3+ switch cases)
4. **Zero Overhead:** Table built at comptime, no runtime cost vs hand-coded switches
5. **Hardware Accurate:** Preserves variable cycle counts (branches, indexed modes)
6. **Reduced Code:** 533 lines → 279 lines (48% reduction in Execution.zig)

### Implementation Notes

**Microstep Dispatcher (Zero-Cost Polymorphism):**
```zig
pub fn callMicrostep(idx: u8, bus: anytype) bool {
    return switch (idx) {
        0 => CpuMicrosteps.fetchOperandLow(bus),
        1 => CpuMicrosteps.rmwRead(bus),
        // ... 37 more microsteps
        else => unreachable,
    };
}
```
- Comptime switch preserves inline optimization
- No VTable or function pointer overhead
- Duck-typed bus parameter (works with any bus interface)

**Operand Source Enum:**
```zig
pub const OperandSource = enum {
    none,           // Implied/accumulator (no operand)
    immediate_pc,   // Read from PC (LDA #$42)
    temp_value,     // Preloaded by microstep (RMW, indexed modes)
    operand_low,    // Zero page address (LDA $10)
    effective_addr, // Computed address (LDA $10,X)
    operand_hl,     // Absolute address (LDA $1234)
    accumulator,    // Accumulator mode (ASL A)
};
```
- Eliminates nested switch on addressing mode for operand extraction
- Each sequence declares how to fetch its operand

**Bug Fix (INDEXED_INDIRECT vs INDIRECT_INDEXED):**
- Previous code incorrectly shared microstep functions between modes
- (ind,X) now uses: fetchZpBase → addXToBase → fetchIndirectLow/High
- (ind),Y now uses: fetchZpPointer → fetchPointerLow/High → addYCheckPage
- Correct hardware behavior for each addressing mode

### When to Use This Pattern

**Good fit:**
- Dispatch logic with many similar cases (256 opcodes, 13 addressing modes)
- Behavior defined by sequence of operations (microstep sequences)
- Need to eliminate code duplication (opcode lists, timing thresholds)
- Timing precision matters (cycle-accurate emulation)

**Not appropriate:**
- Small number of cases (use simple switch/if)
- Behavior requires complex runtime logic (table can't express)
- Dispatch criteria changes frequently (table rebuild overhead)

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

**Core Concept:** Self-contained bus module with stateless handler delegation pattern, following State/Logic separation established by CPU/PPU/APU/DMA/Controller modules.

### Module Structure (Extracted 2025-11-09)

**Bus Module Files:**
- `src/bus/State.zig` - Bus state (RAM, open bus tracking, handler instances)
- `src/bus/Logic.zig` - Routing operations (read, write, read16, dummyRead)
- `src/bus/Inspection.zig` - Debugger-safe inspection (peek without side effects)
- `src/bus/Bus.zig` - Module facade
- `src/bus/handlers/` - 7 zero-size stateless handlers

**Black Box Pattern:**
- Bus owns all bus-related state (RAM, open bus, handlers)
- Bus Logic provides routing operations (not embedded in EmulationState)
- EmulationState delegates via inline functions (busRead, busWrite, etc.)
- Follows same pattern established for PPU/DMA/Controller subsystems

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
| `PpuHandler` | $2000-$3FFF | ⭐ (1/5) | 2C02 PPU registers (8 regs, mirrored) |
| `ApuHandler` | $4000-$4015 | ⭐⭐⭐ (3/5) | 2A03 APU channels |
| `OamDmaHandler` | $4014 | ⭐⭐ (2/5) | 2C02 OAM DMA trigger |
| `ControllerHandler` | $4016-$4017 | ⭐⭐ (2/5) | Controller ports + APU frame counter |
| `CartridgeHandler` | $4020-$FFFF | ⭐⭐ (2/5) | Cartridge mapper delegation |
| `OpenBusHandler` | unmapped | ⭐ (1/5) | Hardware open bus behavior |

### Integration in EmulationState (Post-Bus-Extraction 2025-11-09)

**Before (handlers owned by EmulationState):**
```zig
pub const EmulationState = struct {
    handlers: struct {
        open_bus: OpenBusHandler = .{},
        ram: RamHandler = .{},
        // ... 5 more handlers
    } = .{},

    pub fn busRead(self: *EmulationState, address: u16) u8 {
        // Routing logic embedded in EmulationState
        const value = switch (address) {
            0x0000...0x1FFF => self.handlers.ram.read(self, address),
            // ...
        };
        self.bus.open_bus = value;
        return value;
    }
};
```

**After (handlers owned by bus module):**
```zig
// Bus owns handlers (src/bus/State.zig)
pub const State = struct {
    ram: [2048]u8,
    open_bus: OpenBus,
    handlers: struct {
        open_bus: OpenBusHandler = .{},
        ram: RamHandler = .{},
        // ... 5 more handlers
    } = .{},
};

// Bus Logic handles routing (src/bus/Logic.zig)
pub fn read(bus: *BusState, state: anytype, address: u16) u8 {
    const value = switch (address) {
        0x0000...0x1FFF => bus.handlers.ram.read(state, address),
        // ...
    };
    if (address != 0x4015) bus.open_bus.set(value);
    return value;
}

// EmulationState delegates (src/emulation/State.zig)
pub const EmulationState = struct {
    bus: BusState = .{},

    pub inline fn busRead(self: *EmulationState, address: u16) u8 {
        return BusLogic.read(&self.bus, self, address);
    }
};
```

### Example: PpuHandler (Pure Routing)

**Responsibilities:**
- Route CPU memory accesses ($2000-$3FFF) to PPU subsystem
- Pure delegation to PpuLogic for all register operations
- Zero internal state - completely stateless routing struct

**Implementation:**
```zig
// src/bus/handlers/PpuHandler.zig
pub const PpuHandler = struct {
    // NO fields - completely stateless!

    pub fn read(_: *const PpuHandler, state: anytype, address: u16) u8 {
        const cart_ptr = if (state.cart) |*cart_ref| cart_ref else null;

        // Delegate to PPU logic - PPU handles ALL side effects internally
        const result = PpuLogic.readRegister(
            &state.ppu,
            cart_ptr,
            address,
            state.clock.master_cycles,
        );

        return result.value;
    }

    pub fn write(_: *PpuHandler, state: anytype, address: u16, value: u8) void {
        const cart_ptr = if (state.cart) |*cart_ref| cart_ref else null;

        // Delegate to PPU logic - PPU handles ALL side effects internally
        PpuLogic.writeRegister(&state.ppu, cart_ptr, address, value);
    }

    pub fn peek(_: *const PpuHandler, state: anytype, address: u16) u8 {
        // No side effects - safe for debugger
        const reg = address & 0x07;
        if (reg == 0x02) {
            const registers = @import("../../ppu/logic/registers.zig");
            const vblank_flag = state.ppu.vblank.isFlagSet();
            return registers.buildStatusByte(
                state.ppu.status.sprite_overflow,
                state.ppu.status.sprite_0_hit,
                vblank_flag,
                state.bus.open_bus.get(),
            );
        }
        return state.bus.open_bus.get();
    }
};
```

**Key Characteristics:**
- Zero-size handler (no fields, verified by unit tests)
- All PPU register side effects implemented in ppu/logic/registers.zig
- Handler contains zero PPU hardware logic - pure routing only
- Follows same pattern as other 6 bus handlers

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

### Benefits of Bus Module Extraction (2025-11-09)

1. **Clear Ownership:** Bus module owns all bus-related state (not scattered in EmulationState)
2. **Consistent Pattern:** Follows State/Logic separation used by CPU/PPU/APU/DMA/Controller
3. **Reduced Coupling:** EmulationState delegates to BusLogic (doesn't embed routing logic)
4. **Module Cohesion:** All bus concerns (routing, handlers, open bus) in single module
5. **Zero Legacy Code:** Complete extraction from emulation/ directory

### See Also

- `src/bus/` - Bus module (State, Logic, Inspection, handlers)
- `src/bus/handlers/` - All handler implementations (7 zero-size stateless handlers)
- `src/cartridge/` - Cartridge mapper pattern (same delegation approach)
- `src/emulation/State.zig` - EmulationState bus delegation integration

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

## VBlank Pattern (PPU Self-Containment - COMPLETED 2025-11-07)

**Core Concept:** PPU owns and manages all VBlank state internally. EmulationState reads output signals only.

### Architecture Changes (2025-11-07)

PPU refactored to self-contained black box:
- Owns VBlank state in `ppu/VBlank.zig` (renamed from VBlankLedger, moved from emulation/)
- Owns `nmi_line` output signal (field in PpuState, computed from vblank_flag AND ctrl.nmi_enable)
- Owns `framebuffer` rendering buffer (field in PpuState)
- Manages VBlank set/clear internally in PPU Logic.tick()

**Implementation Status (Completed):**
- [x] VBlank type moved and renamed (ppu/VBlank.zig)
- [x] nmi_line field added to PpuState
- [x] framebuffer field added to PpuState
- [x] VBlank set/clear logic moved to PPU Logic (scanline 241 dot 1, scanline -1 dot 1)
- [x] NMI line computation moved to PPU (vblank_flag AND ctrl.nmi_enable)
- [x] EmulationState.stepPpuCycle() deleted (no longer extracting PPU internals)
- [x] EmulationState.applyVBlankTimestamps() deleted (PPU manages internally)
- [x] Signal wiring in EmulationState.tick(): ppu.nmi_line → cpu.nmi_line

**Old Pattern (EmulationState-centric):** EmulationState managed VBlankLedger, called applyVBlankTimestamps(), extracted scanline/dot to pass to PPU
**New Pattern (PPU-centric):** PPU manages VBlank state internally, EmulationState reads ppu.nmi_line output signal

### Reference Implementation: VBlank (in ppu/VBlank.zig)

```zig
pub const VBlank = struct {
    // Pure data fields (timestamps only)
    vblank_flag: bool = false,
    vblank_span_active: bool = false,
    last_set_cycle: u64 = 0,
    last_clear_cycle: u64 = 0,
    last_read_cycle: u64 = 0,
    prevent_vbl_set_cycle: u64 = 0,

    // ONLY mutation method
    pub fn reset(self: *VBlank) void {
        self.* = .{};
    }

    // NO business logic
    // NO decision-making
    // Just timestamps
};
```

### Key Principles

1. **Ownership:** PPU owns VBlank state (not EmulationState)
2. **Pure Data:** VBlank stores only timestamps and flags
3. **Single Mutation Method:** Only `reset()` method exists
4. **Internal Management:** All mutations happen inside PPU (during tick())
5. **Signal Output:** PPU outputs `nmi_line` signal for CPU to read

### Usage Pattern

VBlank management is fully internal to PPU module. EmulationState does not manage VBlank at all.

```zig
// In ppu/Logic.zig - VBlank management happens during PPU tick()
pub fn tick(state: *PpuState, cart: ?*AnyCartridge) void {
    // VBlank set/clear happens internally based on scanline/cycle
    // VBlank state stored in state.vblank field (type: VBlank)

    // Scanline 241, dot 1: Set VBlank flag
    if (state.scanline == 241 and state.cycle == 1) {
        if (state.vblank.prevent_vbl_set_cycle != master_cycles) {
            state.vblank.vblank_flag = true;
            state.vblank.last_set_cycle = master_cycles;
        }
    }

    // Scanline -1 (pre-render), dot 1: Clear VBlank flag
    if (state.scanline == -1 and state.cycle == 1) {
        state.vblank.vblank_flag = false;
        state.vblank.last_clear_cycle = master_cycles;
    }

    // Output signal: nmi_line computed from VBlank flag AND NMI enable
    state.nmi_line = state.vblank.vblank_flag and state.ctrl.nmi_enable;
}

// In EmulationState.tick() - Only reads output signals
PpuLogic.tick(&self.ppu, cart_ptr);
self.cpu.nmi_line = self.ppu.nmi_line;  // Wire PPU NMI signal to CPU
```

### Sub-Cycle Execution Order (CRITICAL - Now Handled by PPU)

**LOCKED BEHAVIOR** - Do not modify without hardware justification.

VBlank flag updates must follow hardware-accurate sub-cycle execution order:

**Within a single PPU cycle:**
1. CPU read operations (if CPU active this cycle) - may set VBlank prevention flag
2. CPU write operations (if CPU active this cycle) - may change NMI enable
3. PPU tick() executes - manages VBlank state, respects prevention flags
4. PPU outputs signals via TickFlags and nmi_line field

**Implementation: PPU now owns sub-cycle timing (ppu/Logic.zig:tick)**

VBlank management is completely internal to PPU. The tick() function:
- Reads current scanline/cycle from PpuState (not passed as parameters)
- Manages VBlank state field (type: VBlank)
- Updates nmi_line output signal based on VBlank flag + NMI enable
- Returns TickFlags indicating state changes

**Critical Implementation Detail (2025-11-07):**
PPU self-containment prevents timing bugs:
- VBlank flag state is owned by PPU (not split between emulation state)
- NMI line is computed from VBlank AND ctrl.nmi_enable (co-located)
- Race condition handling (prevent_vbl_set_cycle) is internal to PPU
- One location manages all VBlank logic - reduces coordination bugs

**Critical Race Condition (Hardware Behavior):**
When CPU reads $2002 at scanline 241, dot 1 (same cycle VBlank is set):
- CPU reads $2002 → sees VBlank bit = 0 (flag not set yet)
- PPU's VBlank.prevent_vbl_set_cycle is set by handler
- PPU.tick() checks prevention flag → skips setting VBlank (prevented)
- Result: VBlank flag never sets (correct hardware behavior)

**Hardware Citation:** https://www.nesdev.org/wiki/PPU_frame_timing

**Files:**
- `src/ppu/VBlank.zig` - VBlank state (pure data)
- `src/ppu/Logic.zig:tick()` - VBlank management logic
- `src/ppu/State.zig` - PpuState with vblank field and nmi_line output signal
- `src/bus/handlers/PpuHandler.zig` - $2000-$3FFF handler (pure routing, refactored 2025-11-09)

**Test Coverage:**
- `tests/ppu/*vblank*` - PPU VBlank tests
- `tests/integration/*` - Integration tests verifying coordination

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

## DMA Interaction Model (Consolidated 2025-11-08)

**Core Concept:** Hardware-accurate DMC/OAM DMA time-sharing with self-contained DMA module following black box pattern.

### Module Structure (Consolidated 2025-11-08)

**DMA Subsystem Files:**
- `src/dma/State.zig` - Consolidated DMA state (OamDma, DmcDma, interaction ledger)
- `src/dma/Logic.zig` - DMA execution logic (tickOamDma, tickDmcDma)
- `src/dma/Dma.zig` - DMA coordination module (tick function, signal output)

**Black Box Architecture:**
- DMA owns all internal state (OAM DMA, DMC DMA, interaction tracking)
- DMA outputs RDY line signal to CPU: `dma.rdy_line = !(dmc.rdy_low or oam.active)`
- EmulationState wires signal: `cpu.rdy_line = dma.rdy_line`
- Follows same black box pattern as PPU subsystem (self-contained module with signal output)

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

**State Structure (src/dma/State.zig):**
```zig
// OAM DMA state
pub const OamDma = struct {
    active: bool = false,
    source_page: u8 = 0,
    current_offset: u8 = 0,
    current_cycle: u16 = 0,
    needs_alignment: bool = false,
    temp_value: u8 = 0,

    pub fn trigger(self: *OamDma, page: u8, on_odd_cycle: bool) void { }
    pub fn reset(self: *OamDma) void { }
};

// DMC DMA state
pub const DmcDma = struct {
    active: bool = false,
    address: u16 = 0,
    stall_cycles_remaining: u8 = 0,
    rdy_low: bool = false,

    pub fn triggerFetch(self: *DmcDma, address: u16) void { }
    pub fn reset(self: *DmcDma) void { }
};
```

**Logic Execution (src/dma/Logic.zig):**
```zig
// Functional edge detection (no state machine)
pub fn tickOamDma(state: *DmaState, bus: anytype) void {
    // Check if DMC is stalling OAM
    // Hardware time-sharing: OAM continues during halt/dummy/alignment,
    // only pauses during actual DMC read cycle
    const dmc_is_stalling_oam = state.dmc.rdy_low and
        state.dmc.stall_cycles_remaining == 1;  // Only DMC read cycle

    if (dmc_is_stalling_oam) {
        return;  // Pause OAM during DMC read cycle only
    }

    // Check if post-DMC alignment cycle needed
    if (state.needs_alignment_after_dmc) {
        state.needs_alignment_after_dmc = false;
        return;  // Consume alignment cycle
    }

    // Otherwise OAM executes normally (time-sharing on bus)
    // ... OAM execution logic ...
}
```

### Key Points

1. **Self-Contained Module:** DMA logic consolidated in src/dma/ (not scattered across EmulationState)
2. **Black Box Pattern:** DMA owns state, outputs RDY line signal
3. **No State Machine:** Use functional edge detection instead
4. **Time-Sharing:** OAM continues during DMC cycles 2 and 3
5. **Hardware Accurate:** Matches nesdev.org specification exactly

### Migration from Old Pattern

**Before (2025-11-07):**
- DMA state scattered across EmulationState
- OamDma in `src/emulation/state/peripherals/OamDma.zig`
- DmcDma in `src/emulation/state/peripherals/DmcDma.zig`
- Interaction ledger in `src/emulation/DmaInteractionLedger.zig`
- EmulationState orchestrated DMA execution

**After (2025-11-08):**
- All DMA state consolidated in `src/dma/State.zig`
- DMA logic in `src/dma/Logic.zig` (tickOamDma, tickDmcDma)
- DMA coordination in `src/dma/Dma.zig` (tick function, RDY line computation)
- EmulationState reads DMA signals: `cpu.rdy_line = dma.rdy_line`

**Architecture Benefits:**
- DMA logic no longer scattered across EmulationState
- Clear separation between OAM DMA (PPU sprite upload) and DMC DMA (APU sample fetch)
- Self-contained module following established black box pattern
- Signal-based interface matches PPU nmi_line pattern

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

**Version:** 1.4
**Last Updated:** 2025-11-09
**Status:** Complete reference for Phase 2 patterns + Black Box Subsystems
**Recent Update:** Bus module extraction complete (2025-11-09), follows State/Logic pattern, handlers ownership transferred to bus module
