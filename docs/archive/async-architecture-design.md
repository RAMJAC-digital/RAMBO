# RAMBO Asynchronous Architecture Design

**Created:** 2025-10-03
**Status:** DESIGN PHASE - Awaiting Review and Approval
**Target:** Full async message-passing architecture with hardware-accurate configuration

## Executive Summary

This document outlines the migration from RAMBO's current synchronous, single-threaded architecture to an asynchronous, message-passing architecture where each emulated component (CPU, PPU, APU, CIC) runs independently with SPSC (Single Producer Single Consumer) queues for inter-component communication.

**Key Goals:**
- Hardware-accurate emulation with configurable variants (RP2A03G/H, RP2C02G, CIC chips, board revisions)
- Async component execution for parallelism and accuracy
- Lock-free SPSC message passing (minimal overhead)
- Pre-allocated memory (no allocations on hot path)
- Thread-safe, real-time friendly design
- Zero regressions (all 112 tests must pass)

---

## Table of Contents

1. [Current Architecture Analysis](#1-current-architecture-analysis)
2. [Research Findings](#2-research-findings)
3. [Proposed Async Architecture](#3-proposed-async-architecture)
4. [Configuration System Design](#4-configuration-system-design)
5. [SPSC Queue Implementation](#5-spsc-queue-implementation)
6. [Component Interface Design](#6-component-interface-design)
7. [Message Bus Architecture](#7-message-bus-architecture)
8. [Timing Synchronization](#8-timing-synchronization)
9. [Migration Strategy](#9-migration-strategy)
10. [Testing Strategy](#10-testing-strategy)
11. [Performance Considerations](#11-performance-considerations)
12. [Open Questions](#12-open-questions)

---

## 1. Current Architecture Analysis

### 1.1 Current Design (Synchronous)

```
┌─────────────────────────────────────────┐
│         main.zig (Entry Point)          │
│  - Creates CPU and Bus                  │
│  - Synchronous initialization           │
└─────────────┬───────────────────────────┘
              │
              ▼
    ┌─────────────────────┐
    │  Bus (Memory Hub)   │
    │  - 2KB RAM          │
    │  - Cartridge I/O    │
    │  - Open Bus         │
    │  - Cycle counter    │
    └─────────┬───────────┘
              │
              ▼
    ┌─────────────────────┐
    │   CPU (6502 Core)   │
    │  - Registers        │
    │  - State machine    │
    │  - Opcode dispatch  │
    │  - Calls bus.read() │
    └─────────────────────┘
```

**Characteristics:**
- ✅ **Simple**: Easy to reason about, single execution flow
- ✅ **Tested**: 112 passing tests, well-validated
- ✅ **Cycle-accurate**: Microstep architecture allows per-cycle control
- ❌ **Monolithic**: All components in same thread
- ❌ **Tight coupling**: CPU directly calls Bus methods
- ❌ **No parallelism**: Cannot leverage multi-core
- ❌ **Single variant**: No configuration for CPU/PPU revisions

### 1.2 Key Components

#### Bus (`src/bus/Bus.zig`)
- **Role**: Central memory hub
- **Size**: ~200 lines
- **Dependencies**: Cartridge
- **State**: 2KB RAM, cycle counter, open bus tracker
- **Thread Safety**: None (single-threaded)

#### CPU (`src/cpu/Cpu.zig`)
- **Role**: 6502 processor emulation
- **Size**: ~300 lines (core) + ~2000 lines (instructions/dispatch)
- **Dependencies**: Bus (for memory access)
- **State**: Registers (A, X, Y, SP, PC, P), execution state, interrupt state
- **Thread Safety**: None (single-threaded)

#### Cartridge (`src/cartridge/Cartridge.zig`)
- **Role**: ROM/mapper abstraction
- **Size**: ~400 lines (cartridge + mappers)
- **Dependencies**: None
- **State**: ROM data, mapper state
- **Thread Safety**: Mutex-protected (prepared for async)

### 1.3 Current Execution Flow

```
1. main() creates CPU and Bus
2. CPU.tick() called in loop
3. CPU.tick() advances state machine
4. State machine calls bus.read() / bus.write()
5. Bus routes to RAM / cartridge
6. Cycle counter increments
7. Repeat
```

**Problems with Current Flow:**
1. No PPU/APU yet - will need tight integration
2. All components share same cycle counter (timing coupling)
3. Cannot run PPU at 3x speed in parallel
4. Cannot simulate component-level parallelism (CPU/PPU bus conflicts)

---

## 2. Research Findings

### 2.1 Hardware Variants (from search-specialist agents)

#### CPU Variants
- **RP2A03 (NTSC)**: 1.79 MHz (21.47727 MHz ÷ 12)
  - RP2A03E: Early revision
  - **RP2A03G**: Standard front-loader (AccuracyCoin target)
  - RP2A03H: Later revision
- **RP2A07 (PAL)**: 1.66 MHz (26.6017 MHz ÷ 16)
- **Dendy**: 1.77 MHz (26.601712 MHz ÷ 15)

**Key Finding**: Opcodes behave identically across RP2A03 revisions. Only unstable unofficial opcodes (SHA, SHX, SHY, SHS, LXA) vary by revision.

#### PPU Variants
- **RP2C02 (NTSC)**: 60 Hz, 341 cycles/scanline, 262 scanlines
  - RP2C02G: Standard (AccuracyCoin target)
- **RP2C07 (PAL)**: 50 Hz, 341 cycles/scanline, 312 scanlines

#### CIC Lockout Chips
- **CIC-NES-3193** (NTSC USA)
- **CIC-NES-3195/3197** (PAL)
- **Important**: 4-bit Sharp SM590 microcontroller @ 4 MHz
- **Finding**: Simple state machine, does NOT need full async execution
- **Emulation**: Can be synchronous state machine integrated with initialization

#### Board Revisions
- **Famicom**: HVC-CPU-01 to -08
- **NES Front-Loader**: NES-CPU-01 to -11
- **NES Top-Loader**: NES-101
- **Controller Differences**: AccuracyCoin tests NES vs Famicom controller reads

### 2.2 SPSC Message Passing (from research)

**Key Patterns:**
1. **Lock-free ring buffer** with atomic head/tail indices
2. **Power-of-2 capacity** for fast modulo
3. **Pre-allocated** buffer (no heap allocations)
4. **Memory ordering**: Sequential Consistency for correctness
5. **Zig std.atomic.Atomic** for thread-safe operations

**Performance Characteristics:**
- Zero locks (lock-free)
- Cache-line aligned to reduce false sharing
- O(1) push/pop operations
- Minimal contention (single producer, single consumer)

### 2.3 Async Emulator Architecture (from research)

**Design Principles:**
1. Each component runs in separate thread
2. Components communicate via SPSC queues
3. Main thread acts as coordinator/message bus
4. Pre-allocate all queues and message buffers
5. Synchronize on frame boundaries or N cycles
6. Use libxev event loop for I/O and timing

---

## 3. Proposed Async Architecture

### 3.1 High-Level Design

```
┌────────────────────────────────────────────────────────┐
│                  Main Thread (Event Loop)               │
│  - libxev event loop                                   │
│  - Routes messages between components                   │
│  - Manages synchronization points                       │
│  - Handles frame timing (V-sync)                        │
└─────┬──────────┬──────────┬──────────┬─────────────────┘
      │          │          │          │
      │ SPSC     │ SPSC     │ SPSC     │ SPSC
      ▼          ▼          ▼          ▼
┌─────────┐ ┌────────┐ ┌────────┐ ┌─────────┐
│ CPU     │ │ PPU    │ │ APU    │ │ CIC     │
│ Thread  │ │ Thread │ │ Thread │ │ (State  │
│         │ │        │ │        │ │ Machine)│
│ 1.79MHz │ │ 5.37MHz│ │ 1.79MHz│ │ Sync    │
│ (NTSC)  │ │ (3x)   │ │ (NTSC) │ │         │
└─────────┘ └────────┘ └────────┘ └─────────┘
     │           │           │           │
     └───────────┴───────────┴───────────┘
                    │
              ┌─────▼──────┐
              │ Shared     │
              │ Memory Bus │
              │ (Lock-free)│
              └────────────┘
```

### 3.2 Message Types

```zig
/// Message types for inter-component communication
pub const Message = union(enum) {
    /// Component has advanced N cycles
    tick: struct {
        component: ComponentId,
        cycles: u32,
    },

    /// Memory read request
    memory_read: struct {
        address: u16,
        cycle: u64,
        requester: ComponentId,
    },

    /// Memory read response
    memory_read_response: struct {
        value: u8,
        cycle: u64,
    },

    /// Memory write
    memory_write: struct {
        address: u16,
        value: u8,
        cycle: u64,
        requester: ComponentId,
    },

    /// Interrupt signal
    interrupt: struct {
        type: InterruptType, // NMI, IRQ
        active: bool, // assert or deassert
    },

    /// Synchronization point reached
    sync: struct {
        component: ComponentId,
        cycle: u64,
    },

    /// Frame complete
    frame_complete: struct {
        frame_number: u64,
    },
};

pub const ComponentId = enum(u8) {
    cpu,
    ppu,
    apu,
    cic,
    bus,
};
```

### 3.3 Component Threading Model

#### Option A: True Async (Multi-threaded)
**Pros:**
- True parallelism (CPU and PPU run simultaneously)
- Matches real hardware (independent chips)
- Can leverage multi-core CPUs

**Cons:**
- Complex synchronization (need to coordinate cycles)
- Memory bus contention (need lock-free design)
- Harder to debug (non-deterministic execution order)
- More overhead (thread context switching)

#### Option B: Cooperative Async (Single thread, libxev)
**Pros:**
- Deterministic execution order
- Simpler debugging
- No thread synchronization needed
- Lower overhead

**Cons:**
- No true parallelism
- Cannot leverage multi-core
- Component "threads" are actually coroutines

#### **RECOMMENDATION: Start with Option B, migrate to Option A later**

**Rationale:**
1. Simpler initial implementation (less risk)
2. Easier to verify correctness (deterministic)
3. Can still use async/await patterns
4. Can migrate to true threads once proven correct
5. CIC doesn't need threads (simple state machine)

### 3.4 Memory Bus Design (Lock-Free)

```zig
/// Lock-free memory bus using atomic operations
pub const AsyncBus = struct {
    /// 2KB RAM (no locking needed if accessed only by CPU)
    ram: [2048]u8,

    /// Atomic cycle counter
    cycle: std.atomic.Atomic(u64),

    /// Open bus state (atomic)
    open_bus_value: std.atomic.Atomic(u8),
    open_bus_cycle: std.atomic.Atomic(u64),

    /// Cartridge (mutex protected for thread safety)
    cartridge: ?*Cartridge,
    cartridge_mutex: std.Thread.Mutex,

    /// Read from bus (atomic)
    pub fn read(self: *@This(), address: u16) u8 {
        const value = self.readInternal(address);

        // Atomically update open bus
        const cycle = self.cycle.load(.Monotonic);
        self.open_bus_value.store(value, .Monotonic);
        self.open_bus_cycle.store(cycle, .Monotonic);

        return value;
    }

    /// Write to bus (atomic)
    pub fn write(self: *@This(), address: u16, value: u8) void {
        self.writeInternal(address, value);

        // Atomically update open bus
        const cycle = self.cycle.load(.Monotonic);
        self.open_bus_value.store(value, .Monotonic);
        self.open_bus_cycle.store(cycle, .Monotonic);
    }
};
```

**Key Decision**: RAM access only by CPU (no locking needed). PPU has separate VRAM/OAM (accessed atomically or via messages).

---

## 4. Configuration System Design

### 4.1 Expanded Configuration

```kdl
// RAMBO NES Emulator Configuration v2.0

// Hardware Configuration
hardware {
    // Console variant
    console "NES-USA-FrontLoader"  // or "Famicom", "PAL-NES", etc.

    // Board revision (affects chipset)
    board_revision "NES-CPU-07"

    // CPU configuration
    cpu {
        variant "RP2A03G"  // RP2A03E, RP2A03G, RP2A03H, RP2A07
        region "NTSC"      // NTSC, PAL, Dendy
        clock_divider 12   // 21.47727 MHz ÷ 12 = 1.79 MHz

        // Unstable opcode behavior
        unstable_opcodes {
            sha_behavior "RP2A03G"  // "RP2A03G" or "RP2A03H"
            lxa_magic 0xEE          // Magic constant for LXA
        }
    }

    // PPU configuration
    ppu {
        variant "RP2C02G"  // RP2C02, RP2C02E, RP2C02G, RP2C07
        region "NTSC"      // NTSC: 60 Hz, 262 lines; PAL: 50 Hz, 312 lines
        accuracy "cycle"   // cycle, scanline, frame
    }

    // APU configuration
    apu {
        enabled true
        region "NTSC"
        sample_rate 48000
    }

    // CIC lockout chip
    cic {
        enabled true
        variant "CIC-NES-3193"  // NTSC USA
        emulation "state_machine"  // state_machine, bypass, disabled
    }

    // Controller ports
    controllers {
        type "NES"  // "NES" or "Famicom"
        // Affects controller clocking behavior per AccuracyCoin tests
    }
}

// Emulation Configuration
emulation {
    execution_mode "async"  // sync, async, async_multithread

    // Async options
    async {
        cpu_thread true
        ppu_thread true
        apu_thread true
        sync_interval 29780  // CPU cycles per frame (NTSC)
    }

    // Performance
    performance {
        spsc_queue_size 1024  // Must be power of 2
        message_pool_size 4096
        preallocate_all true
    }
}

// Video configuration (same as before)
video {
    backend "software"
    vsync true
    scale 3
}
```

### 4.2 Configuration Struct

```zig
/// Complete hardware configuration
pub const HardwareConfig = struct {
    console: ConsoleVariant,
    board_revision: BoardRevision,
    cpu: CpuConfig,
    ppu: PpuConfig,
    apu: ApuConfig,
    cic: CicConfig,
    controllers: ControllerConfig,
};

pub const ConsoleVariant = enum {
    nes_usa_frontloader,
    nes_usa_toploader,
    famicom,
    av_famicom,
    pal_nes,
    dendy,
};

pub const CpuConfig = struct {
    variant: CpuVariant,
    region: VideoRegion,
    clock_divider: u8,
    unstable_opcodes: UnstableOpcodeConfig,
};

pub const CpuVariant = enum {
    rp2a03e,
    rp2a03g,  // AccuracyCoin target
    rp2a03h,
    rp2a07,   // PAL
};

pub const UnstableOpcodeConfig = struct {
    /// SHA/SHS behavior varies by revision
    sha_behavior: SHABehavior,

    /// LXA magic constant (varies: 0x00, 0xFF, 0xEE, or other)
    lxa_magic: u8,
};

pub const SHABehavior = enum {
    rp2a03g_old,  // Older RP2A03G behavior
    rp2a03g_new,  // Newer RP2A03G behavior
    rp2a03h,      // RP2A03H behavior
};

pub const CicConfig = struct {
    enabled: bool,
    variant: CicVariant,
    emulation: CicEmulation,
};

pub const CicVariant = enum {
    cic_nes_3193,  // NTSC USA
    cic_nes_3195,  // PAL B
    cic_nes_3197,  // PAL A
    cic_6113,      // Die shrink
};

pub const CicEmulation = enum {
    state_machine,  // Emulate CIC state machine
    bypass,         // Bypass lockout (like top-loader)
    disabled,       // No CIC chip
};

pub const ControllerConfig = struct {
    type: ControllerType,
};

pub const ControllerType = enum {
    nes,      // Detachable, specific clocking per AccuracyCoin
    famicom,  // Hardwired, different clocking
};
```

---

## 5. SPSC Queue Implementation

### 5.1 Lock-Free Ring Buffer

```zig
/// Single Producer, Single Consumer lock-free queue
pub fn SPSCQueue(comptime T: type, comptime capacity: usize) type {
    // Enforce power-of-2 for fast modulo
    comptime {
        if (@popCount(capacity) != 1) {
            @compileError("SPSCQueue capacity must be power of 2");
        }
    }

    return struct {
        const Self = @This();
        const mask = capacity - 1;

        /// Pre-allocated buffer
        buffer: [capacity]T align(std.atomic.cache_line) = undefined,

        /// Producer index (head)
        /// Only modified by producer thread
        head: std.atomic.Atomic(usize) align(std.atomic.cache_line),

        /// Consumer index (tail)
        /// Only modified by consumer thread
        tail: std.atomic.Atomic(usize) align(std.atomic.cache_line),

        pub fn init() Self {
            return .{
                .head = std.atomic.Atomic(usize).init(0),
                .tail = std.atomic.Atomic(usize).init(0),
            };
        }

        /// Push item (producer only)
        /// Returns true if successful, false if full
        pub fn push(self: *Self, item: T) bool {
            const current_head = self.head.load(.Monotonic);
            const next_head = (current_head + 1) & mask;

            // Check if queue is full
            // We leave one slot empty to distinguish full vs empty
            if (next_head == self.tail.load(.Acquire)) {
                return false; // Queue full
            }

            // Write item
            self.buffer[current_head] = item;

            // Publish the write
            self.head.store(next_head, .Release);

            return true;
        }

        /// Pop item (consumer only)
        /// Returns null if empty
        pub fn pop(self: *Self) ?T {
            const current_tail = self.tail.load(.Monotonic);

            // Check if queue is empty
            if (current_tail == self.head.load(.Acquire)) {
                return null; // Queue empty
            }

            // Read item
            const item = self.buffer[current_tail];

            // Advance tail
            self.tail.store((current_tail + 1) & mask, .Release);

            return item;
        }

        /// Check if queue is empty (consumer only)
        pub fn isEmpty(self: *const Self) bool {
            return self.tail.load(.Monotonic) == self.head.load(.Acquire);
        }

        /// Get approximate size (not exact due to concurrency)
        pub fn size(self: *const Self) usize {
            const h = self.head.load(.Monotonic);
            const t = self.tail.load(.Monotonic);
            return (h -% t) & mask;
        }
    };
}
```

### 5.2 Memory Ordering Justification

- **Monotonic** for local thread reads (no synchronization needed)
- **Acquire** when reading from other thread (see their writes)
- **Release** when writing for other thread (publish our writes)
- **SeqCst** NOT needed (SPSC has clear ordering)

---

## 6. Component Interface Design

### 6.1 Component Trait

```zig
/// Common interface for all emulated components
pub const Component = struct {
    /// Component ID
    id: ComponentId,

    /// Component state
    state: *anyopaque,

    /// Virtual function table
    vtable: *const VTable,

    pub const VTable = struct {
        /// Initialize component with configuration
        init: *const fn(allocator: std.mem.Allocator, config: *const HardwareConfig) anyerror!*anyopaque,

        /// Deinitialize component
        deinit: *const fn(state: *anyopaque, allocator: std.mem.Allocator) void,

        /// Process incoming message
        processMessage: *const fn(state: *anyopaque, msg: Message) anyerror!void,

        /// Tick N cycles (returns messages to send)
        tick: *const fn(state: *anyopaque, cycles: u32, out_msgs: *MessageBuffer) anyerror!void,

        /// Reset component
        reset: *const fn(state: *anyopaque) void,
    };

    /// Create component from concrete type
    pub fn init(comptime T: type, allocator: std.mem.Allocator, config: *const HardwareConfig) !Component {
        const state = try T.init(allocator, config);
        return Component{
            .id = T.component_id,
            .state = state,
            .vtable = &T.vtable,
        };
    }
};
```

### 6.2 CPU Component Implementation

```zig
pub const CpuComponent = struct {
    pub const component_id = ComponentId.cpu;

    cpu: Cpu,
    config: CpuConfig,

    pub const vtable = Component.VTable{
        .init = init,
        .deinit = deinit,
        .processMessage = processMessage,
        .tick = tick,
        .reset = reset,
    };

    fn init(allocator: std.mem.Allocator, config: *const HardwareConfig) !*anyopaque {
        const self = try allocator.create(CpuComponent);
        self.* = .{
            .cpu = Cpu.init(),
            .config = config.cpu,
        };
        return self;
    }

    fn tick(state: *anyopaque, cycles: u32, out_msgs: *MessageBuffer) !void {
        const self: *CpuComponent = @alignCast(@ptrCast(state));

        for (0..cycles) |_| {
            // Tick CPU one cycle
            self.cpu.tick();

            // Generate messages for memory access
            if (self.cpu.needsMemoryRead()) {
                try out_msgs.push(.{
                    .memory_read = .{
                        .address = self.cpu.getMemoryAddress(),
                        .cycle = self.cpu.cycle,
                        .requester = .cpu,
                    },
                });
            }

            // Generate interrupt messages
            if (self.cpu.nmi_triggered) {
                try out_msgs.push(.{
                    .interrupt = .{
                        .type = .nmi,
                        .active = true,
                    },
                });
            }
        }
    }
};
```

---

## 7. Message Bus Architecture

### 7.1 Main Event Loop

```zig
pub const Emulator = struct {
    /// Hardware configuration
    config: HardwareConfig,

    /// Components
    cpu: Component,
    ppu: Component,
    apu: Component,

    /// Message queues (SPSC: component → bus)
    cpu_to_bus: SPSCQueue(Message, 1024),
    ppu_to_bus: SPSCQueue(Message, 1024),
    apu_to_bus: SPSCQueue(Message, 1024),

    /// Response queues (SPSC: bus → component)
    bus_to_cpu: SPSCQueue(Message, 1024),
    bus_to_ppu: SPSCQueue(Message, 1024),
    bus_to_apu: SPSCQueue(Message, 1024),

    /// Shared memory bus
    bus: AsyncBus,

    /// libxev event loop
    loop: xev.Loop,

    /// Frame timer
    frame_timer: FrameTimer,

    pub fn init(allocator: std.mem.Allocator, config: HardwareConfig) !Emulator {
        return Emulator{
            .config = config,
            .cpu = try Component.init(CpuComponent, allocator, &config),
            .ppu = try Component.init(PpuComponent, allocator, &config),
            .apu = try Component.init(ApuComponent, allocator, &config),
            .cpu_to_bus = SPSCQueue(Message, 1024).init(),
            .ppu_to_bus = SPSCQueue(Message, 1024).init(),
            .apu_to_bus = SPSCQueue(Message, 1024).init(),
            .bus_to_cpu = SPSCQueue(Message, 1024).init(),
            .bus_to_ppu = SPSCQueue(Message, 1024).init(),
            .bus_to_apu = SPSCQueue(Message, 1024).init(),
            .bus = AsyncBus.init(),
            .loop = try xev.Loop.init(),
            .frame_timer = FrameTimer.init(config.ppu, config.video.vsync),
        };
    }

    /// Run emulation (main event loop)
    pub fn run(self: *Emulator) !void {
        while (true) {
            // Process messages from components
            try self.processMessages();

            // Tick components (cooperative async)
            try self.tickComponents();

            // Synchronization point
            if (self.shouldSync()) {
                try self.sync();
            }

            // Frame timing
            if (self.isFrameComplete()) {
                self.frame_timer.waitForNextFrame();
            }
        }
    }

    fn processMessages(self: *Emulator) !void {
        // Process CPU messages
        while (self.cpu_to_bus.pop()) |msg| {
            try self.handleMessage(msg, .cpu);
        }

        // Process PPU messages
        while (self.ppu_to_bus.pop()) |msg| {
            try self.handleMessage(msg, .ppu);
        }

        // Process APU messages
        while (self.apu_to_bus.pop()) |msg| {
            try self.handleMessage(msg, .apu);
        }
    }

    fn handleMessage(self: *Emulator, msg: Message, from: ComponentId) !void {
        switch (msg) {
            .memory_read => |req| {
                // Read from bus
                const value = self.bus.read(req.address);

                // Send response
                const response = Message{
                    .memory_read_response = .{
                        .value = value,
                        .cycle = self.bus.cycle.load(.Monotonic),
                    },
                };

                switch (from) {
                    .cpu => _ = self.bus_to_cpu.push(response),
                    .ppu => _ = self.bus_to_ppu.push(response),
                    .apu => _ = self.bus_to_apu.push(response),
                    else => {},
                }
            },

            .memory_write => |req| {
                self.bus.write(req.address, req.value);
            },

            .interrupt => |int| {
                // Route interrupt to CPU
                _ = self.bus_to_cpu.push(msg);
            },

            else => {},
        }
    }
};
```

---

## 8. Timing Synchronization

### 8.1 Challenge: Different Clock Rates

- **CPU**: 1.79 MHz (NTSC)
- **PPU**: 5.37 MHz (3x CPU speed)
- **APU**: 1.79 MHz (same as CPU)

### 8.2 Synchronization Strategy

```zig
/// Synchronization point every N CPU cycles
const SYNC_INTERVAL_CYCLES: u32 = 29780; // 1 frame (NTSC)

pub const SyncManager = struct {
    /// Target cycles for each component at next sync point
    target_cpu_cycles: u64,
    target_ppu_cycles: u64,
    target_apu_cycles: u64,

    /// Current cycles for each component
    current_cpu_cycles: std.atomic.Atomic(u64),
    current_ppu_cycles: std.atomic.Atomic(u64),
    current_apu_cycles: std.atomic.Atomic(u64),

    /// Set next sync point
    pub fn setNextSync(self: *SyncManager) void {
        self.target_cpu_cycles += SYNC_INTERVAL_CYCLES;
        self.target_ppu_cycles += SYNC_INTERVAL_CYCLES * 3; // PPU 3x faster
        self.target_apu_cycles += SYNC_INTERVAL_CYCLES;
    }

    /// Check if component should wait for sync
    pub fn shouldWait(self: *SyncManager, component: ComponentId) bool {
        return switch (component) {
            .cpu => self.current_cpu_cycles.load(.Monotonic) >= self.target_cpu_cycles,
            .ppu => self.current_ppu_cycles.load(.Monotonic) >= self.target_ppu_cycles,
            .apu => self.current_apu_cycles.load(.Monotonic) >= self.target_apu_cycles,
            else => false,
        };
    }

    /// Wait for all components to reach sync point
    pub fn waitForSync(self: *SyncManager) void {
        while (true) {
            const cpu_ready = self.current_cpu_cycles.load(.Monotonic) >= self.target_cpu_cycles;
            const ppu_ready = self.current_ppu_cycles.load(.Monotonic) >= self.target_ppu_cycles;
            const apu_ready = self.current_apu_cycles.load(.Monotonic) >= self.target_apu_cycles;

            if (cpu_ready and ppu_ready and apu_ready) {
                break;
            }

            // Yield to avoid busy-wait (if multi-threaded)
            std.Thread.yield() catch {};
        }
    }
};
```

---

## 9. Migration Strategy

### 9.1 Phased Approach

#### Phase 1: Configuration System (Week 1)
1. ✅ Expand `Config.zig` with hardware variants
2. ✅ Add CPU variant configuration (RP2A03G/H, RP2A07)
3. ✅ Add PPU variant configuration (RP2C02G, RP2C07)
4. ✅ Add CIC configuration (variant, emulation mode)
5. ✅ Add controller type configuration (NES vs Famicom)
6. ✅ Update `rambo.kdl` with new fields
7. ✅ Update KDL parser to handle new fields
8. ✅ Add tests for configuration parsing
9. ✅ Document configuration options

**Deliverables:**
- Updated `Config.zig` with all hardware variants
- Updated `rambo.kdl` with complete hardware description
- 20+ tests for configuration parsing
- Documentation in `docs/configuration.md`

**Acceptance Criteria:**
- All existing tests pass (0 regressions)
- Can load AccuracyCoin target config (RP2A03G + RP2C02G)
- Can load PAL config (RP2A07 + RP2C07)

#### Phase 2: SPSC Queue Implementation (Week 1-2)
1. ✅ Implement `SPSCQueue` generic type
2. ✅ Write unit tests for queue operations
3. ✅ Benchmark queue performance
4. ✅ Validate lock-free properties
5. ✅ Document memory ordering decisions

**Deliverables:**
- `src/async/SPSCQueue.zig` (150-200 lines)
- 15+ unit tests
- Performance benchmarks
- Memory ordering documentation

**Acceptance Criteria:**
- Push/pop operations O(1)
- Lock-free (no std.Thread.Mutex)
- Power-of-2 capacity enforced at compile time
- No allocations after init()

#### Phase 3: Message Types & Component Interface (Week 2)
1. ✅ Define `Message` union type
2. ✅ Define `ComponentId` enum
3. ✅ Define `Component` interface
4. ✅ Implement message buffer pool (pre-allocated)
5. ✅ Write tests for message serialization

**Deliverables:**
- `src/async/Message.zig` (200-300 lines)
- `src/async/Component.zig` (100-150 lines)
- 10+ tests for messages

**Acceptance Criteria:**
- All message types defined
- Component vtable interface works
- Message pool pre-allocates (no heap allocations)

#### Phase 4: Async Bus Implementation (Week 3)
1. ✅ Implement `AsyncBus` with atomic operations
2. ✅ Migrate RAM access to atomic reads/writes
3. ✅ Implement lock-free open bus tracking
4. ✅ Test concurrent access patterns
5. ✅ Validate existing Bus tests still pass

**Deliverables:**
- `src/bus/AsyncBus.zig` (300-400 lines)
- 20+ tests (existing + new async tests)

**Acceptance Criteria:**
- All 16 existing Bus tests pass
- Thread-safe atomic operations
- No data races (validated with ThreadSanitizer)

#### Phase 5: CPU Component Migration (Week 3-4)
1. ✅ Implement `CpuComponent` wrapper
2. ✅ Refactor CPU to generate messages instead of direct bus calls
3. ✅ Implement message handling in CPU
4. ✅ Test CPU in async mode
5. ✅ Validate all CPU tests pass

**Deliverables:**
- `src/cpu/CpuComponent.zig` (200-300 lines)
- Refactored `Cpu.zig` (message-based)
- All 70 CPU tests passing

**Acceptance Criteria:**
- CPU generates memory_read messages
- CPU processes memory_read_response messages
- All existing tests pass (0 regressions)
- Can run CPU in cooperative async mode

#### Phase 6: Emulator Main Loop (Week 4)
1. ✅ Implement `Emulator` struct with event loop
2. ✅ Implement message routing (bus logic)
3. ✅ Implement synchronization manager
4. ✅ Integrate frame timer
5. ✅ Test full emulation loop

**Deliverables:**
- `src/Emulator.zig` (400-500 lines)
- Integration tests

**Acceptance Criteria:**
- CPU runs in async mode via emulator
- Messages route correctly
- Frame timing works (60 FPS NTSC)
- All 112 tests pass

#### Phase 7: CIC State Machine (Week 5)
1. ✅ Implement CIC state machine (synchronous)
2. ✅ Integrate CIC with initialization
3. ✅ Test CIC authentication sequence
4. ✅ Add CIC bypass mode

**Deliverables:**
- `src/cic/CIC.zig` (150-200 lines)
- CIC tests

**Acceptance Criteria:**
- CIC authenticates correctly
- CIC bypass mode works
- CIC disabled mode works

#### Phase 8: PPU Stub & Integration (Week 6)
1. ✅ Implement PPU component stub
2. ✅ Integrate PPU with message bus
3. ✅ Implement PPU-CPU synchronization
4. ✅ Test basic PPU operation

**Deliverables:**
- `src/ppu/PpuComponent.zig` (stub)
- PPU-CPU sync tests

**Acceptance Criteria:**
- PPU stub runs at 3x CPU speed
- Synchronization works
- No regressions in CPU tests

#### Phase 9: Documentation & Cleanup (Week 6-7)
1. ✅ Update all docs in `docs/`
2. ✅ Remove legacy synchronous code (if applicable)
3. ✅ Add code comments
4. ✅ Create architecture diagram
5. ✅ Write migration guide

**Deliverables:**
- Updated documentation
- Architecture diagrams
- Migration guide
- Clean codebase (no unused code)

**Acceptance Criteria:**
- All docs up to date
- No legacy code remains
- Code is well-commented
- Architecture diagrams match implementation

### 9.2 Validation at Each Phase

**After Each Phase:**
1. ✅ Run all tests (`zig build test`)
2. ✅ Verify 0 regressions
3. ✅ Run ThreadSanitizer (for async phases)
4. ✅ Update STATUS.md
5. ✅ Commit with descriptive message

---

## 10. Testing Strategy

### 10.1 Unit Tests

- **SPSC Queue**: Push/pop, empty/full, concurrent access
- **Message Types**: Serialization, deserialization
- **Async Bus**: Atomic reads/writes, open bus, contention
- **Component Interface**: vtable calls, state management
- **CIC State Machine**: Authentication sequence

### 10.2 Integration Tests

- **CPU-Bus Messaging**: CPU reads/writes via messages
- **Synchronization**: Components sync at frame boundaries
- **Frame Timing**: V-sync works correctly
- **Multi-component**: CPU + PPU running together

### 10.3 Regression Tests

**Critical Requirement:** ALL 112 EXISTING TESTS MUST PASS

- **Bus Tests**: 16 tests (RAM mirroring, open bus, etc.)
- **CPU Tests**: 70 tests (instructions, flags, timing)
- **Cartridge Tests**: 42 tests (loading, mappers)

### 10.4 Performance Tests

- **SPSC Queue Throughput**: Messages/second
- **Message Latency**: Time from push to pop
- **Frame Rate**: Actual FPS achieved
- **CPU Utilization**: Thread usage, cache misses

---

## 11. Performance Considerations

### 11.1 Memory Allocation

**Goal: Zero allocations on hot path**

✅ **Pre-allocate:**
- SPSC queues (fixed size)
- Message buffers (pool)
- Component state (allocate once at init)
- RAM/ROM (allocate once)

❌ **Never allocate:**
- During emulation loop
- During message handling
- During component ticking

### 11.2 Cache Optimization

- **Cache-line alignment** for atomic variables (`align(std.atomic.cache_line)`)
- **Separate head/tail** to different cache lines (reduce false sharing)
- **Message batching** (process multiple messages per iteration)

### 11.3 Lock-Free Guarantees

- **No std.Thread.Mutex** on hot path
- **Atomic operations only** for shared state
- **SPSC queues** (single producer/consumer = lock-free)
- **Bus access** via atomics (except cartridge, which uses mutex)

### 11.4 Expected Performance

**Target:**
- 60 FPS NTSC (16.67 ms per frame)
- <10% CPU usage on modern CPU (for CPU component alone)
- <5μs message latency (push to pop)
- >1M messages/sec throughput per queue

---

## 12. Open Questions

### 12.1 For Review by Specialist Agents

1. **Memory Ordering**: Are Acquire/Release sufficient, or do we need SeqCst in some places?
2. **Synchronization Strategy**: Is frame-based sync sufficient, or do we need finer granularity?
3. **Message Types**: Are the defined messages complete for CPU-PPU-APU-Bus communication?
4. **CIC Integration**: Should CIC be a full component or just a utility function?
5. **Cartridge Mutex**: Is mutex acceptable for cartridge, or should we use SPSC for mapper access?
6. **Threading Model**: Should we start with cooperative async (Option B) or go straight to multi-threaded (Option A)?

### 12.2 For User Approval

1. **Migration Timeline**: Is 7 weeks acceptable for full async migration?
2. **Phasing**: Should we complete all phases before implementing PPU, or implement PPU stub earlier?
3. **Testing**: Are 0 regressions and ThreadSanitizer validation sufficient?
4. **Documentation**: What additional docs are needed?

---

## 13. Next Steps

**Immediate Actions:**
1. ✅ Have `architect-reviewer` agent review this design
2. ✅ Have `performance-engineer` agent review performance considerations
3. ✅ Have `code-reviewer` agent review code patterns
4. ✅ Address any concerns raised by agents
5. ✅ Get user approval on design
6. ⬜ Begin Phase 1: Configuration System

**After Approval:**
1. Create detailed task breakdown for Phase 1
2. Implement configuration expansion
3. Write tests
4. Update documentation
5. Move to Phase 2

---

## Appendix A: References

- **AccuracyCoin README**: Hardware target (RP2A03G + RP2C02G)
- **Research: CPU Variants**: RP2A03/RP2A07 differences
- **Research: CIC Chips**: CIC-NES-3193/3195/3197
- **Research: SPSC Queues**: Lock-free patterns in Zig
- **Research: Async Emulators**: Message-passing architectures
- **NESDev Wiki**: https://www.nesdev.org/wiki/
- **Zig std.atomic**: https://ziglang.org/documentation/master/std/#A;std:atomic

---

**End of Design Document**
