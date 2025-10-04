# Phase 4.3: State Snapshot + Debugger System Specification

**Version:** 1.0
**Date:** 2025-10-03
**Status:** Design Complete - Ready for Implementation

## Executive Summary

This specification defines the complete architecture for a state snapshot and debugger system for RAMBO NES emulator. The system provides:

1. **State Snapshots**: Complete emulation state serialization (binary + JSON formats)
2. **Debugger Interface**: External wrapper for breakpoints, watchpoints, and step execution
3. **Perfect Reproducibility**: Capture/restore complete system state including all components

**Key Design Principles:**
- External wrapper (not embedded in EmulationState)
- No allocator in core state structures (maintains purity)
- State/Logic separation preserved
- No RT-safety violations
- Zero conflicts with current architecture

---

## Table of Contents

1. [Current Architecture Analysis](#1-current-architecture-analysis)
2. [State Snapshot Design](#2-state-snapshot-design)
3. [Debugger Interface Design](#3-debugger-interface-design)
4. [API Specification](#4-api-specification)
5. [Integration Strategy](#5-integration-strategy)
6. [Test Strategy](#6-test-strategy)
7. [Implementation Roadmap](#7-implementation-roadmap)
8. [Conflict Analysis](#8-conflict-analysis)
9. [Critical Questions & Decisions](#9-critical-questions--decisions)

---

## 1. Current Architecture Analysis

### 1.1 EmulationState Structure

**Current State (src/emulation/State.zig):**
```zig
pub const EmulationState = struct {
    clock: MasterClock,           // 8 bytes (u64)
    cpu: CpuState,                // ~200 bytes
    ppu: PpuState,                // ~3KB (VRAM + OAM + palette)
    bus: BusState,                // ~2KB (RAM)
    config: *const Config.Config, // 8 bytes (pointer)
    frame_complete: bool,         // 1 byte
    odd_frame: bool,              // 1 byte
    rendering_enabled: bool,      // 1 byte
};
```

**Total Core State Size:** ~5.2 KB (without config)

### 1.2 Component State Breakdown

#### CPU State (src/cpu/State.zig)
```zig
pub const CpuState = struct {
    // Registers: 7 bytes
    a: u8, x: u8, y: u8, sp: u8, pc: u16, p: StatusFlags,

    // Cycle tracking: 17 bytes
    cycle_count: u64, instruction_cycle: u8, state: ExecutionState,

    // Instruction context: 10 bytes
    opcode: u8, operand_low: u8, operand_high: u8,
    effective_address: u16, address_mode: AddressingMode,
    page_crossed: bool,

    // Open bus + interrupts: 6 bytes
    data_bus: u8, pending_interrupt: InterruptType,
    nmi_line: bool, nmi_edge_detected: bool, irq_line: bool,

    // Temporary storage: 4 bytes
    halted: bool, temp_value: u8, temp_address: u16,
};
// Total: ~44 bytes
```

#### PPU State (src/ppu/State.zig)
```zig
pub const PpuState = struct {
    // Registers: 18 bytes
    ctrl: PpuCtrl, mask: PpuMask, status: PpuStatus,
    oam_addr: u8, open_bus: OpenBus, internal: InternalRegisters,

    // Memory: 2,594 bytes
    oam: [256]u8,           // 256 bytes
    secondary_oam: [32]u8,  // 32 bytes
    vram: [2048]u8,         // 2KB
    palette_ram: [32]u8,    // 32 bytes

    // Background state: 28 bytes (shift registers + latches)
    bg_state: BackgroundState,

    // Metadata: 19 bytes
    mirroring: Mirroring, cartridge: ?*NromCart,
    nmi_occurred: bool, scanline: u16, dot: u16, frame: u64,
};
// Total: ~2,659 bytes
```

#### Bus State (src/bus/State.zig)
```zig
pub const BusState = struct {
    ram: [2048]u8,            // 2KB
    cycle: u64,               // 8 bytes
    open_bus: OpenBus,        // 16 bytes
    test_ram: ?[]u8,          // 16 bytes (pointer + len)
    cartridge: ?*NromCart,    // 8 bytes (pointer)
    ppu: ?*PpuState,          // 8 bytes (pointer)
};
// Total: ~2,104 bytes
```

### 1.3 Config Structure Analysis

**Critical Finding:** Config owns ArenaAllocator (src/config/Config.zig):
```zig
pub const Config = struct {
    // ... config fields (all plain data) ...
    arena: std.heap.ArenaAllocator,  // ⚠️ Owns allocator
    mutex: std.Thread.Mutex,         // ⚠️ Runtime state
};
```

**Snapshot Strategy for Config:**
- **Serialize:** Only the configuration values (enums, integers, booleans)
- **Skip:** `arena` and `mutex` (runtime-only, not state)
- **Restore:** Config pointer must be provided externally during deserialization

---

## 2. State Snapshot Design

### 2.1 Snapshot Format Overview

Two formats supported:

1. **Binary Format** (Production - ~500KB with framebuffer)
   - Compact, cross-platform compatible
   - Little-endian for all multi-byte values
   - Header with version + checksum

2. **JSON Format** (Debugging - ~800KB with framebuffer)
   - Human-readable, easy to inspect/diff
   - Schema versioned for compatibility
   - Base64 encoding for binary data (RAM, VRAM, etc.)

### 2.2 Binary Snapshot Format

#### Header Structure (64 bytes)
```zig
pub const SnapshotHeader = packed struct {
    magic: [8]u8 = "RAMBO\x00\x00\x00".*,  // Magic identifier
    version: u32,                           // Format version (1)
    timestamp: i64,                         // Unix timestamp
    emulator_version: [16]u8,               // RAMBO version string
    total_size: u64,                        // Total snapshot size
    state_size: u32,                        // EmulationState size
    cartridge_size: u32,                    // Cartridge data size
    framebuffer_size: u32,                  // Framebuffer size (optional)
    flags: u32,                             // Feature flags
    checksum: u32,                          // CRC32 of data after header
    reserved: [8]u8,                        // Future use
};
```

#### Data Layout
```
[Header: 64 bytes]
[Config: Variable - serialized config values]
[MasterClock: 8 bytes]
[CpuState: 44 bytes]
[PpuState: 2,659 bytes - includes VRAM, OAM, palette]
[BusState.ram: 2,048 bytes]
[BusState metadata: 40 bytes]
[Cartridge Header: 16 bytes - iNES header]
[Cartridge PRG ROM: Variable - reference or embed based on flag]
[Cartridge CHR data: Variable - reference or embed based on flag]
[Cartridge state: Variable - mapper-specific state]
[Optional Framebuffer: 256×240×4 = 245,760 bytes]
```

**Total Size Estimates:**
- **Without framebuffer:** ~5KB core state + cartridge reference
- **With framebuffer:** ~250KB (includes rendered frame)
- **Full cartridge embed:** +ROM size (32KB typical)

### 2.3 Cartridge Data Handling

**Critical Decision: Reference vs. Embed**

**Option 1: Reference (Recommended for production)**
- Store ROM file path or hash
- Snapshot only contains mapper state
- Requires original ROM for restoration
- Tiny snapshots (~5KB)

**Option 2: Embed (Recommended for debugging)**
- Store complete ROM data in snapshot
- Fully self-contained
- Larger snapshots (~40KB with typical ROM)
- Portable across systems

**Implementation:**
```zig
pub const CartridgeSnapshotMode = enum {
    reference,  // Store path/hash only
    embed,      // Store full ROM data
};

pub const CartridgeSnapshot = union(CartridgeSnapshotMode) {
    reference: struct {
        rom_path: []const u8,
        rom_hash: [32]u8,  // SHA-256 hash
    },
    embed: struct {
        header: InesHeader,
        prg_rom: []const u8,
        chr_data: []const u8,
    },
};
```

### 2.4 JSON Snapshot Format

**Schema Version 1:**
```json
{
  "version": 1,
  "timestamp": "2025-10-03T12:34:56Z",
  "emulator_version": "RAMBO-0.1.0",

  "config": {
    "console": "NES-NTSC-FrontLoader",
    "cpu": { "variant": "RP2A03G", "region": "NTSC" },
    "ppu": { "variant": "RP2C02G", "region": "NTSC", "accuracy": "cycle" }
  },

  "clock": {
    "ppu_cycles": 123456789
  },

  "cpu": {
    "registers": {
      "a": 0x42, "x": 0x10, "y": 0x20,
      "sp": 0xFD, "pc": 0x8000,
      "p": { "carry": false, "zero": true, ... }
    },
    "cycle_count": 41152963,
    "state": "fetch_opcode",
    ...
  },

  "ppu": {
    "ctrl": { "nmi_enable": true, ... },
    "mask": { "show_bg": true, ... },
    "vram": "base64_encoded_2KB_data",
    "oam": "base64_encoded_256B_data",
    "palette_ram": "base64_encoded_32B_data",
    ...
  },

  "bus": {
    "ram": "base64_encoded_2KB_data",
    "cycle": 123456789,
    ...
  },

  "cartridge": {
    "mode": "reference",
    "rom_path": "/path/to/game.nes",
    "rom_hash": "sha256_hex_string",
    "mapper_state": { ... }
  },

  "framebuffer": "base64_encoded_245KB_data"  // Optional
}
```

### 2.5 Cross-Platform Compatibility

**Endianness Handling:**
- All binary data stored in **little-endian** format
- Conversion functions for big-endian systems
- JSON format is naturally platform-independent

**Pointer Handling:**
- No raw pointers stored
- References stored as indices or paths
- Reconstruction uses current allocator

**Alignment:**
- Binary format uses natural alignment
- No packed structs that vary by platform

---

## 3. Debugger Interface Design

### 3.1 Debugger Architecture

**External Wrapper Pattern:**
```zig
/// Debugger wraps EmulationState with debugging capabilities
/// Does NOT modify EmulationState internals
pub const Debugger = struct {
    /// Wrapped emulation state (owned or borrowed)
    state: *EmulationState,

    /// Allocator for debugger-owned data
    allocator: std.mem.Allocator,

    /// Breakpoint management
    breakpoints: BreakpointManager,

    /// Watchpoint management
    watchpoints: WatchpointManager,

    /// Execution history (circular buffer)
    history: ExecutionHistory,

    /// Step mode state
    step_mode: StepMode,

    /// Callback system
    callbacks: CallbackManager,
};
```

### 3.2 Breakpoint System

**Breakpoint Types:**
```zig
pub const BreakpointType = enum {
    pc,              // Break when PC reaches address
    opcode,          // Break on specific opcode
    read,            // Break on memory read
    write,           // Break on memory write
    register_value,  // Break when register equals value
    flag_change,     // Break on status flag change
};

pub const Breakpoint = struct {
    id: u32,
    type: BreakpointType,
    enabled: bool,
    hit_count: u64,
    condition: BreakpointCondition,
};

pub const BreakpointCondition = union(BreakpointType) {
    pc: u16,
    opcode: u8,
    read: u16,
    write: u16,
    register_value: struct {
        register: Register,
        value: u8,
    },
    flag_change: struct {
        flag: StatusFlag,
        value: bool,
    },
};
```

**Breakpoint Manager:**
```zig
pub const BreakpointManager = struct {
    breakpoints: std.ArrayList(Breakpoint),
    next_id: u32,

    pub fn add(self: *Self, condition: BreakpointCondition) !u32;
    pub fn remove(self: *Self, id: u32) !void;
    pub fn enable(self: *Self, id: u32) !void;
    pub fn disable(self: *Self, id: u32) !void;
    pub fn clear(self: *Self) void;
    pub fn check(self: *Self, state: *const EmulationState) ?u32;
};
```

### 3.3 Watchpoint System

**Watchpoint Types:**
```zig
pub const WatchpointType = enum {
    read,      // Watch memory reads
    write,     // Watch memory writes
    access,    // Watch any access (read or write)
};

pub const Watchpoint = struct {
    id: u32,
    type: WatchpointType,
    address_range: AddressRange,
    enabled: bool,
    hit_count: u64,
    log_access: bool,  // Log all accesses or just break?
};

pub const AddressRange = struct {
    start: u16,
    end: u16,  // Inclusive
};
```

### 3.4 Step Execution Modes

```zig
pub const StepMode = enum {
    none,              // Normal execution (run until breakpoint)
    instruction,       // Step one CPU instruction
    cycle_cpu,         // Step one CPU cycle
    cycle_ppu,         // Step one PPU cycle
    scanline,          // Step one scanline
    frame,             // Step one frame
    until_pc,          // Run until PC reaches value
    until_scanline,    // Run until scanline
};

pub const StepState = struct {
    mode: StepMode,
    target: ?u64,      // Target value for until_* modes
    steps_remaining: u64,
};
```

### 3.5 Execution History

**Circular Buffer for Recent Instructions:**
```zig
pub const ExecutionHistoryEntry = struct {
    cycle: u64,
    pc: u16,
    opcode: u8,
    a: u8, x: u8, y: u8, sp: u8, p: u8,
    scanline: u16,
    dot: u16,
};

pub const ExecutionHistory = struct {
    entries: []ExecutionHistoryEntry,  // Fixed-size circular buffer
    capacity: usize,
    write_index: usize,
    count: usize,

    pub fn push(self: *Self, entry: ExecutionHistoryEntry) void;
    pub fn get(self: *const Self, index: usize) ?ExecutionHistoryEntry;
    pub fn clear(self: *Self) void;
};
```

### 3.6 Callback System

**Event Callbacks:**
```zig
pub const DebugEvent = enum {
    breakpoint_hit,
    watchpoint_hit,
    step_complete,
    frame_complete,
    nmi_triggered,
    irq_triggered,
};

pub const DebugCallback = *const fn(
    event: DebugEvent,
    context: ?*anyopaque,
    state: *const EmulationState
) void;

pub const CallbackManager = struct {
    callbacks: std.ArrayList(struct {
        event: DebugEvent,
        callback: DebugCallback,
        context: ?*anyopaque,
    }),

    pub fn register(self: *Self, event: DebugEvent, callback: DebugCallback, context: ?*anyopaque) !void;
    pub fn unregister(self: *Self, callback: DebugCallback) void;
    pub fn trigger(self: *Self, event: DebugEvent, state: *const EmulationState) void;
};
```

---

## 4. API Specification

### 4.1 Snapshot API

```zig
/// Snapshot module - serialize/deserialize complete emulation state
pub const Snapshot = struct {

    /// Save state to binary format
    ///
    /// Parameters:
    ///   - allocator: Allocator for temporary buffers
    ///   - state: EmulationState to save
    ///   - config: Configuration to save
    ///   - cartridge: Optional cartridge (if null, uses state.bus.cartridge)
    ///   - mode: Cartridge snapshot mode (reference or embed)
    ///   - framebuffer: Optional framebuffer to include
    ///
    /// Returns: Owned slice containing binary snapshot data
    pub fn saveBinary(
        allocator: std.mem.Allocator,
        state: *const EmulationState,
        config: *const Config.Config,
        cartridge: ?*NromCart,
        mode: CartridgeSnapshotMode,
        framebuffer: ?[]const u32,
    ) ![]u8;

    /// Load state from binary format
    ///
    /// Parameters:
    ///   - allocator: Allocator for state reconstruction
    ///   - data: Binary snapshot data
    ///   - config: Existing config (must match snapshot or be compatible)
    ///   - cartridge: Optional cartridge (if null, will attempt to load from snapshot)
    ///
    /// Returns: Reconstructed EmulationState
    pub fn loadBinary(
        allocator: std.mem.Allocator,
        data: []const u8,
        config: *const Config.Config,
        cartridge: ?*NromCart,
    ) !EmulationState;

    /// Save state to JSON format
    pub fn saveJson(
        allocator: std.mem.Allocator,
        state: *const EmulationState,
        config: *const Config.Config,
        cartridge: ?*NromCart,
        mode: CartridgeSnapshotMode,
        framebuffer: ?[]const u32,
    ) ![]u8;

    /// Load state from JSON format
    pub fn loadJson(
        allocator: std.mem.Allocator,
        data: []const u8,
        config: *const Config.Config,
        cartridge: ?*NromCart,
    ) !EmulationState;

    /// Verify snapshot integrity (checksum validation)
    pub fn verify(data: []const u8) !void;

    /// Get snapshot metadata without full deserialization
    pub fn getMetadata(data: []const u8) !SnapshotMetadata;
};

pub const SnapshotMetadata = struct {
    version: u32,
    timestamp: i64,
    emulator_version: [16]u8,
    total_size: u64,
    has_framebuffer: bool,
    cartridge_mode: CartridgeSnapshotMode,
};
```

### 4.2 Debugger API

```zig
/// Debugger - external wrapper for debugging capabilities
pub const Debugger = struct {

    /// Initialize debugger wrapping an EmulationState
    pub fn init(allocator: std.mem.Allocator, state: *EmulationState) !Debugger;

    /// Cleanup debugger resources
    pub fn deinit(self: *Debugger) void;

    // ===== Breakpoint Management =====

    /// Add PC breakpoint
    pub fn addBreakpointPc(self: *Debugger, address: u16) !u32;

    /// Add opcode breakpoint
    pub fn addBreakpointOpcode(self: *Debugger, opcode: u8) !u32;

    /// Add memory read breakpoint
    pub fn addBreakpointRead(self: *Debugger, address: u16) !u32;

    /// Add memory write breakpoint
    pub fn addBreakpointWrite(self: *Debugger, address: u16) !u32;

    /// Remove breakpoint by ID
    pub fn removeBreakpoint(self: *Debugger, id: u32) !void;

    /// Enable/disable breakpoint
    pub fn setBreakpointEnabled(self: *Debugger, id: u32, enabled: bool) !void;

    /// Clear all breakpoints
    pub fn clearBreakpoints(self: *Debugger) void;

    // ===== Watchpoint Management =====

    /// Add watchpoint for address range
    pub fn addWatchpoint(
        self: *Debugger,
        type: WatchpointType,
        start: u16,
        end: u16,
    ) !u32;

    /// Remove watchpoint by ID
    pub fn removeWatchpoint(self: *Debugger, id: u32) !void;

    /// Clear all watchpoints
    pub fn clearWatchpoints(self: *Debugger) void;

    // ===== Execution Control =====

    /// Run until breakpoint or step completion
    /// Returns reason for stopping
    pub fn run(self: *Debugger) !DebugStopReason;

    /// Step one CPU instruction
    pub fn stepInstruction(self: *Debugger) !void;

    /// Step one CPU cycle
    pub fn stepCpuCycle(self: *Debugger) !void;

    /// Step one PPU cycle
    pub fn stepPpuCycle(self: *Debugger) !void;

    /// Step one scanline
    pub fn stepScanline(self: *Debugger) !void;

    /// Step one frame
    pub fn stepFrame(self: *Debugger) !void;

    /// Run until PC reaches target
    pub fn runUntilPc(self: *Debugger, target: u16) !void;

    /// Run until scanline
    pub fn runUntilScanline(self: *Debugger, scanline: u16) !void;

    // ===== State Inspection =====

    /// Get current CPU state (read-only view)
    pub fn getCpuState(self: *const Debugger) *const CpuState;

    /// Get current PPU state (read-only view)
    pub fn getPpuState(self: *const Debugger) *const PpuState;

    /// Get execution history
    pub fn getHistory(self: *const Debugger) []const ExecutionHistoryEntry;

    /// Get last N instructions
    pub fn getRecentInstructions(self: *const Debugger, count: usize) []const ExecutionHistoryEntry;

    // ===== State Manipulation =====

    /// Set CPU register
    pub fn setCpuRegister(self: *Debugger, register: CpuRegister, value: u16) !void;

    /// Set CPU PC
    pub fn setCpuPc(self: *Debugger, pc: u16) void;

    /// Set status flag
    pub fn setCpuFlag(self: *Debugger, flag: StatusFlag, value: bool) void;

    /// Write to memory (via bus)
    pub fn writeMemory(self: *Debugger, address: u16, value: u8) void;

    /// Read from memory (via bus)
    pub fn readMemory(self: *const Debugger, address: u16) u8;

    // ===== Callback Management =====

    /// Register event callback
    pub fn onEvent(
        self: *Debugger,
        event: DebugEvent,
        callback: DebugCallback,
        context: ?*anyopaque,
    ) !void;

    /// Unregister callback
    pub fn offEvent(self: *Debugger, callback: DebugCallback) void;
};

pub const DebugStopReason = enum {
    breakpoint,
    watchpoint,
    step_complete,
    frame_complete,
    error,
};

pub const CpuRegister = enum {
    a, x, y, sp, pc,
};

pub const StatusFlag = enum {
    carry, zero, interrupt, decimal, overflow, negative,
};
```

### 4.3 Disassembler API (Bonus)

```zig
/// Disassembly utilities for debugger
pub const Disassembler = struct {

    /// Disassemble instruction at address
    pub fn disassemble(
        state: *const EmulationState,
        address: u16,
    ) !DisassembledInstruction;

    /// Disassemble range of memory
    pub fn disassembleRange(
        allocator: std.mem.Allocator,
        state: *const EmulationState,
        start: u16,
        count: usize,
    ) ![]DisassembledInstruction;
};

pub const DisassembledInstruction = struct {
    address: u16,
    opcode: u8,
    mnemonic: []const u8,  // e.g., "LDA"
    operand: ?[]const u8,  // e.g., "$1234,X"
    bytes: [3]u8,          // Raw bytes
    length: u8,            // Instruction length (1-3)
    cycles: u8,            // Base cycle count
    mode: AddressingMode,
};
```

---

## 5. Integration Strategy

### 5.1 File Organization

```
src/
├── snapshot/
│   ├── Snapshot.zig         # Main snapshot API
│   ├── binary.zig           # Binary serialization
│   ├── json.zig             # JSON serialization
│   ├── cartridge.zig        # Cartridge snapshot handling
│   └── checksum.zig         # CRC32 implementation
│
├── debugger/
│   ├── Debugger.zig         # Main debugger API
│   ├── breakpoints.zig      # Breakpoint manager
│   ├── watchpoints.zig      # Watchpoint manager
│   ├── history.zig          # Execution history
│   ├── callbacks.zig        # Callback system
│   └── disassembler.zig     # Disassembly utilities
│
└── root.zig                 # Export snapshot & debugger APIs
```

### 5.2 Dependencies

**No new external dependencies required!**

- `std.json` - JSON serialization (already available)
- `std.base64` - Base64 encoding for JSON (already available)
- `std.crypto.hash.crc32` - Checksum (already available)
- `std.ArrayList` - Dynamic arrays (already available)

### 5.3 Build System Integration

**Update build.zig:**
```zig
// Add snapshot module
const snapshot_module = b.addModule("snapshot", .{
    .root_source_file = .{ .path = "src/snapshot/Snapshot.zig" },
});

// Add debugger module
const debugger_module = b.addModule("debugger", .{
    .root_source_file = .{ .path = "src/debugger/Debugger.zig" },
});

// Add snapshot tests
const snapshot_tests = b.addTest(.{
    .root_source_file = .{ .path = "src/snapshot/Snapshot.zig" },
    .target = target,
    .optimize = optimize,
});

// Add debugger tests
const debugger_tests = b.addTest(.{
    .root_source_file = .{ .path = "src/debugger/Debugger.zig" },
    .target = target,
    .optimize = optimize,
});

const test_step = b.step("test-snapshot", "Run snapshot tests");
test_step.dependOn(&b.addRunArtifact(snapshot_tests).step);

const test_debugger_step = b.step("test-debugger", "Run debugger tests");
test_debugger_step.dependOn(&b.addRunArtifact(debugger_tests).step);
```

---

## 6. Test Strategy

### 6.1 Snapshot Tests

**Round-Trip Tests:**
```zig
test "Snapshot: binary round-trip" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config, BusState.init());
    state.connectComponents();

    // Modify state to non-default values
    state.cpu.a = 0x42;
    state.cpu.pc = 0x8000;
    state.ppu.ctrl.nmi_enable = true;
    state.bus.ram[0x100] = 0xAA;

    // Save snapshot
    const snapshot_data = try Snapshot.saveBinary(
        testing.allocator,
        &state,
        &config,
        null,
        .reference,
        null,
    );
    defer testing.allocator.free(snapshot_data);

    // Load snapshot
    var restored = try Snapshot.loadBinary(
        testing.allocator,
        snapshot_data,
        &config,
        null,
    );

    // Verify state matches
    try testing.expectEqual(state.cpu.a, restored.cpu.a);
    try testing.expectEqual(state.cpu.pc, restored.cpu.pc);
    try testing.expectEqual(state.ppu.ctrl.nmi_enable, restored.ppu.ctrl.nmi_enable);
    try testing.expectEqual(state.bus.ram[0x100], restored.bus.ram[0x100]);
}

test "Snapshot: JSON round-trip" {
    // Similar to binary test but with JSON format
}

test "Snapshot: cartridge embed mode" {
    // Test embedding full cartridge data
}

test "Snapshot: cartridge reference mode" {
    // Test ROM path/hash reference
}

test "Snapshot: with framebuffer" {
    // Test including framebuffer data
}

test "Snapshot: checksum validation" {
    // Test corrupted snapshot detection
}

test "Snapshot: cross-version compatibility" {
    // Test loading snapshots with different version numbers
}
```

**Serialization Tests:**
```zig
test "Snapshot: CPU state serialization" {
    // Test individual component serialization
}

test "Snapshot: PPU state serialization" {
    // Test VRAM, OAM, palette serialization
}

test "Snapshot: Bus state serialization" {
    // Test RAM serialization
}

test "Snapshot: Config serialization" {
    // Test config values only (skip arena/mutex)
}
```

### 6.2 Debugger Tests

**Breakpoint Tests:**
```zig
test "Debugger: PC breakpoint" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = createTestState(&config);
    var debugger = try Debugger.init(testing.allocator, &state);
    defer debugger.deinit();

    // Add breakpoint at 0x8000
    const bp_id = try debugger.addBreakpointPc(0x8000);

    // Run until breakpoint
    const reason = try debugger.run();
    try testing.expectEqual(DebugStopReason.breakpoint, reason);
    try testing.expectEqual(@as(u16, 0x8000), state.cpu.pc);
}

test "Debugger: opcode breakpoint" {
    // Test breaking on specific opcode (e.g., BRK)
}

test "Debugger: memory read/write breakpoints" {
    // Test breaking on memory access
}

test "Debugger: conditional breakpoints" {
    // Test breaking on register value or flag state
}
```

**Step Execution Tests:**
```zig
test "Debugger: step instruction" {
    var debugger = createTestDebugger();
    defer debugger.deinit();

    const initial_pc = debugger.state.cpu.pc;
    try debugger.stepInstruction();

    // PC should have advanced by instruction length
    try testing.expect(debugger.state.cpu.pc != initial_pc);
}

test "Debugger: step CPU cycle" {
    // Test single CPU cycle stepping
}

test "Debugger: step PPU cycle" {
    // Test single PPU cycle stepping
}

test "Debugger: step scanline" {
    // Test scanline stepping
}

test "Debugger: step frame" {
    // Test frame stepping
}
```

**Watchpoint Tests:**
```zig
test "Debugger: watchpoint read" {
    // Test breaking on memory read
}

test "Debugger: watchpoint write" {
    // Test breaking on memory write
}

test "Debugger: watchpoint address range" {
    // Test watchpoint covering multiple addresses
}
```

**State Manipulation Tests:**
```zig
test "Debugger: set CPU register" {
    var debugger = createTestDebugger();
    defer debugger.deinit();

    try debugger.setCpuRegister(.a, 0x42);
    try testing.expectEqual(@as(u8, 0x42), debugger.state.cpu.a);
}

test "Debugger: set PC" {
    // Test PC modification
}

test "Debugger: write memory" {
    // Test memory modification via debugger
}
```

**History Tests:**
```zig
test "Debugger: execution history" {
    var debugger = createTestDebugger();
    defer debugger.deinit();

    // Execute several instructions
    for (0..10) |_| {
        try debugger.stepInstruction();
    }

    // Verify history captures last N instructions
    const history = debugger.getRecentInstructions(5);
    try testing.expectEqual(@as(usize, 5), history.len);
}

test "Debugger: history circular buffer" {
    // Test history wraps correctly when buffer is full
}
```

### 6.3 Integration Tests

**Phase 4.3 Test Requirements:**
```zig
test "Phase 4.3: complete snapshot cycle" {
    // 1. Create emulation state with complex state
    // 2. Save binary snapshot
    // 3. Save JSON snapshot
    // 4. Load binary snapshot
    // 5. Load JSON snapshot
    // 6. Verify all states match exactly
}

test "Phase 4.3: debugger with snapshots" {
    // 1. Run debugger with breakpoint
    // 2. Save snapshot at breakpoint
    // 3. Continue execution
    // 4. Restore snapshot
    // 5. Verify execution resumes from same point
}

test "Phase 4.3: cartridge state preservation" {
    // 1. Load cartridge with mapper state
    // 2. Modify mapper state (bank switching, etc.)
    // 3. Save snapshot
    // 4. Load snapshot
    // 5. Verify mapper state preserved
}
```

---

## 7. Implementation Roadmap

### Phase 1: Snapshot System (8-10 hours)

**Task 1.1: Binary Serialization (3-4 hours)**
- Implement SnapshotHeader structure
- Implement binary save/load for EmulationState
- Implement CRC32 checksum
- Test round-trip serialization

**Task 1.2: Cartridge Handling (2-3 hours)**
- Implement reference mode (ROM path/hash)
- Implement embed mode (full ROM data)
- Test cartridge snapshot/restore

**Task 1.3: JSON Serialization (2-3 hours)**
- Implement JSON schema
- Implement Base64 encoding for binary data
- Test JSON round-trip

**Task 1.4: Integration & Testing (1 hour)**
- Add snapshot module to build system
- Write comprehensive tests
- Document snapshot API

### Phase 2: Debugger Core (10-12 hours)

**Task 2.1: Debugger Foundation (2-3 hours)**
- Implement Debugger struct
- Implement init/deinit
- Implement state wrapping

**Task 2.2: Breakpoint System (3-4 hours)**
- Implement BreakpointManager
- Implement PC, opcode, memory breakpoints
- Test breakpoint functionality

**Task 2.3: Watchpoint System (2-3 hours)**
- Implement WatchpointManager
- Implement read/write/access watchpoints
- Test watchpoint functionality

**Task 2.4: Step Execution (2-3 hours)**
- Implement step modes (instruction, cycle, scanline, frame)
- Implement run-until modes
- Test step execution

**Task 2.5: Execution History (1 hour)**
- Implement circular buffer
- Implement history tracking
- Test history capture

### Phase 3: Debugger Advanced (6-8 hours)

**Task 3.1: State Manipulation (2-3 hours)**
- Implement register modification
- Implement memory modification
- Test state manipulation

**Task 3.2: Callback System (2-3 hours)**
- Implement CallbackManager
- Implement event triggers
- Test callback functionality

**Task 3.3: Disassembler (2-3 hours)**
- Implement instruction disassembly
- Implement range disassembly
- Test disassembler

**Task 3.4: Integration & Testing (1 hour)**
- Add debugger module to build system
- Write comprehensive tests
- Document debugger API

### Phase 4: Documentation & Polish (2-3 hours)

**Task 4.1: User Documentation**
- Write snapshot format specification
- Write debugger usage guide
- Write API reference

**Task 4.2: Example Code**
- Write snapshot save/load examples
- Write debugger usage examples
- Write integration examples

**Total Estimated Time: 26-33 hours**

---

## 8. Conflict Analysis

### 8.1 Architecture Compatibility

✅ **EmulationState Purity Maintained**
- No allocator added to EmulationState
- No hidden state introduced
- State/Logic separation preserved
- All snapshot/debug state is external

✅ **State/Logic Separation Preserved**
- Snapshot system operates on pure data structures
- Debugger wraps EmulationState externally
- No logic embedded in state structs

✅ **No RT-Safety Violations**
- Snapshot/debugger are non-RT tools (offline usage)
- No blocking operations in EmulationState.tick()
- No mutexes or locks in core emulation

✅ **Config Handling Resolved**
- Config values serialized, arena/mutex skipped
- Config provided externally during deserialization
- No ownership issues

✅ **Cartridge Handling Resolved**
- Reference mode: Store ROM path/hash only
- Embed mode: Store full ROM data
- Mapper state serialized separately
- Cartridge provided externally during restore

### 8.2 Potential Issues & Mitigations

**Issue 1: Pointer Reconstruction**
- **Problem:** EmulationState contains pointers (config, cartridge, ppu)
- **Solution:** Pointers provided externally during load, then connected via connectComponents()

**Issue 2: Allocator Absence**
- **Problem:** EmulationState has no allocator for reconstruction
- **Solution:** Allocator passed to load functions, only used for temporary buffers

**Issue 3: Cross-Version Compatibility**
- **Problem:** State structures may change between versions
- **Solution:** Version numbers in snapshot header, migration functions for old versions

**Issue 4: ROM File Availability**
- **Problem:** Reference mode requires original ROM file
- **Solution:** Store ROM hash, verify on load, fall back to embed mode for portability

---

## 9. Critical Questions & Decisions

### 9.1 Resolved Questions

✅ **Q1: Does Config.Config own allocated data?**
- **Answer:** Yes, owns ArenaAllocator and Mutex
- **Solution:** Serialize config values only, skip arena/mutex, provide config externally on restore

✅ **Q2: How to handle cartridge ROM data in snapshots?**
- **Answer:** Two modes - reference (path/hash) and embed (full data)
- **Solution:** CartridgeSnapshotMode enum, store mode in snapshot header

✅ **Q3: Binary format endianness?**
- **Answer:** Little-endian for cross-platform compatibility
- **Solution:** Conversion functions for big-endian systems if needed

✅ **Q4: JSON schema versioning?**
- **Answer:** Schema version in JSON root, migration support for old versions
- **Solution:** Version field, backward-compatible loading with warnings

✅ **Q5: Include framebuffer in snapshot?**
- **Answer:** Optional - flag in header determines presence
- **Solution:** Framebuffer parameter nullable, size tracked in header

### 9.2 Open Questions (Implementation Decisions)

**Q6: Execution History Buffer Size?**
- **Options:** 256, 512, 1024, or configurable?
- **Recommendation:** 512 entries (~16KB) - covers typical debug scenarios
- **Trade-off:** Memory vs. history depth

**Q7: Snapshot Compression?**
- **Options:** None, zlib, lz4?
- **Recommendation:** Start without compression (simplicity), add later if needed
- **Trade-off:** Size vs. complexity/speed

**Q8: Mapper State Serialization?**
- **Options:** Generic interface or per-mapper serialization?
- **Recommendation:** Generic `getState()`/`setState()` interface for all mappers
- **Trade-off:** Flexibility vs. implementation effort

**Q9: Breakpoint Expression Language?**
- **Options:** None (simple conditions only) or expression parser?
- **Recommendation:** Start with simple conditions, add expressions in Phase 5
- **Trade-off:** Simplicity vs. power

**Q10: Memory Inspection Format?**
- **Options:** Raw bytes, hex dump, disassembly?
- **Recommendation:** Provide all three via separate APIs
- **Trade-off:** API surface vs. usability

### 9.3 Risk Assessment

**Low Risk:**
- ✅ Snapshot binary format (well-defined)
- ✅ Breakpoint/watchpoint system (straightforward)
- ✅ Step execution (clear semantics)

**Medium Risk:**
- ⚠️ JSON serialization size (Base64 overhead ~33%)
  - **Mitigation:** Provide binary format as primary, JSON for debugging
- ⚠️ Cartridge state variation across mappers
  - **Mitigation:** Generic interface, mapper-specific implementations

**High Risk:**
- ❌ Cross-version compatibility (state structure changes)
  - **Mitigation:** Version-specific loaders, migration functions
  - **Long-term:** Stable snapshot format specification

---

## 10. Success Criteria

### 10.1 Functional Requirements

✅ **Snapshot System:**
- [ ] Save/load EmulationState to binary format
- [ ] Save/load EmulationState to JSON format
- [ ] Support cartridge reference mode (ROM path/hash)
- [ ] Support cartridge embed mode (full ROM data)
- [ ] Optional framebuffer inclusion
- [ ] CRC32 checksum validation
- [ ] Cross-platform compatibility (endianness handling)

✅ **Debugger System:**
- [ ] PC breakpoints
- [ ] Opcode breakpoints
- [ ] Memory read/write breakpoints
- [ ] Watchpoints with address ranges
- [ ] Step execution (instruction, cycle, scanline, frame)
- [ ] Run-until modes (PC, scanline)
- [ ] Execution history (circular buffer)
- [ ] State manipulation (registers, memory)
- [ ] Event callbacks

✅ **Integration:**
- [ ] No modifications to EmulationState
- [ ] State/Logic separation maintained
- [ ] No RT-safety violations
- [ ] Build system integration
- [ ] Comprehensive test coverage (>90%)

### 10.2 Quality Metrics

**Test Coverage:**
- Snapshot round-trip tests: 100% pass rate
- Debugger functionality tests: 100% pass rate
- Integration tests: 100% pass rate

**Performance:**
- Binary snapshot save/load: <10ms for typical state (~5KB)
- JSON snapshot save/load: <50ms for typical state (~8KB)
- Debugger breakpoint check: <1μs overhead per instruction

**Memory:**
- Snapshot overhead: <1MB temporary allocations during save/load
- Debugger overhead: <100KB for typical debug session (512 history entries)

---

## 11. Future Enhancements (Phase 5+)

**Advanced Debugger Features:**
- Conditional breakpoints with expression parser
- Symbol file support (.sym, .dbg)
- Assembly editing and hot-patching
- Visual debugger UI integration
- Network debugging protocol (GDB-like)

**Advanced Snapshot Features:**
- Incremental snapshots (delta compression)
- Snapshot recording (movie files)
- Rewind/replay functionality
- Snapshot diffing tools
- Cloud sync for snapshots

**Mapper Extensions:**
- Generic mapper state interface
- Automatic mapper state detection
- Mapper-specific debug info

---

## Appendix A: File Paths

**New Files to Create:**

```
src/snapshot/
├── Snapshot.zig          # Main API (300 lines)
├── binary.zig            # Binary serialization (400 lines)
├── json.zig              # JSON serialization (300 lines)
├── cartridge.zig         # Cartridge snapshot (200 lines)
└── checksum.zig          # CRC32 utilities (100 lines)

src/debugger/
├── Debugger.zig          # Main API (400 lines)
├── breakpoints.zig       # Breakpoint manager (250 lines)
├── watchpoints.zig       # Watchpoint manager (200 lines)
├── history.zig           # Execution history (150 lines)
├── callbacks.zig         # Callback system (150 lines)
└── disassembler.zig      # Disassembly (300 lines)

tests/snapshot/
├── binary_test.zig       # Binary format tests
├── json_test.zig         # JSON format tests
├── cartridge_test.zig    # Cartridge tests
└── integration_test.zig  # Integration tests

tests/debugger/
├── breakpoint_test.zig   # Breakpoint tests
├── watchpoint_test.zig   # Watchpoint tests
├── step_test.zig         # Step execution tests
├── history_test.zig      # History tests
└── integration_test.zig  # Integration tests
```

**Estimated Total Lines:** ~3,500 lines (excluding tests)

---

## Appendix B: Example Usage

### Example 1: Save/Load Snapshot

```zig
const std = @import("std");
const Snapshot = @import("snapshot").Snapshot;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create emulation state
    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config, BusState.init());
    state.connectComponents();

    // Run emulation for a while
    _ = state.emulateFrame();

    // Save snapshot
    const snapshot = try Snapshot.saveBinary(
        allocator,
        &state,
        &config,
        null,  // Use cartridge from state.bus
        .reference,  // Store ROM path only
        null,  // No framebuffer
    );
    defer allocator.free(snapshot);

    // Write to file
    try std.fs.cwd().writeFile("savestate.rambo", snapshot);

    // Later: Load snapshot
    const loaded_data = try std.fs.cwd().readFileAlloc(allocator, "savestate.rambo", 1024 * 1024);
    defer allocator.free(loaded_data);

    var restored = try Snapshot.loadBinary(allocator, loaded_data, &config, null);

    // Continue execution from restored state
    _ = restored.emulateFrame();
}
```

### Example 2: Debugger with Breakpoints

```zig
const std = @import("std");
const Debugger = @import("debugger").Debugger;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create emulation state
    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config, BusState.init());
    state.connectComponents();

    // Create debugger
    var debugger = try Debugger.init(allocator, &state);
    defer debugger.deinit();

    // Add breakpoint at 0x8000
    const bp_id = try debugger.addBreakpointPc(0x8000);
    std.debug.print("Breakpoint added: {d}\n", .{bp_id});

    // Register callback
    try debugger.onEvent(.breakpoint_hit, onBreakpoint, null);

    // Run until breakpoint
    const reason = try debugger.run();
    std.debug.print("Stopped: {s}\n", .{@tagName(reason)});

    // Inspect state
    const cpu = debugger.getCpuState();
    std.debug.print("PC: 0x{X:0>4}\n", .{cpu.pc});
    std.debug.print("A: 0x{X:0>2}\n", .{cpu.a});

    // Step one instruction
    try debugger.stepInstruction();

    // Continue execution
    _ = try debugger.run();
}

fn onBreakpoint(
    event: DebugEvent,
    context: ?*anyopaque,
    state: *const EmulationState,
) void {
    _ = context;
    _ = event;
    std.debug.print("Breakpoint hit at PC: 0x{X:0>4}\n", .{state.cpu.pc});
}
```

### Example 3: Memory Inspection

```zig
// Inspect memory range
const start: u16 = 0x8000;
const end: u16 = 0x8010;

std.debug.print("Memory dump:\n", .{});
var addr = start;
while (addr <= end) : (addr += 1) {
    const value = debugger.readMemory(addr);
    std.debug.print("${X:0>4}: ${X:0>2}\n", .{addr, value});
}

// Disassemble instructions
const instructions = try Disassembler.disassembleRange(
    allocator,
    debugger.state,
    0x8000,
    10,  // 10 instructions
);
defer allocator.free(instructions);

for (instructions) |instr| {
    std.debug.print("${X:0>4}: {s} {s}\n", .{
        instr.address,
        instr.mnemonic,
        instr.operand orelse "",
    });
}
```

---

## Document Version History

- **v1.0 (2025-10-03):** Initial specification - comprehensive design complete
  - Architecture analysis complete
  - Snapshot format defined (binary + JSON)
  - Debugger interface designed
  - API specification complete
  - Test strategy defined
  - Implementation roadmap with estimates
  - All critical questions addressed

---

**Status:** ✅ **READY FOR IMPLEMENTATION**

This specification provides a complete, conflict-free design for Phase 4.3 snapshot and debugger systems. All architectural concerns have been addressed, and the implementation path is clear with detailed estimates.
