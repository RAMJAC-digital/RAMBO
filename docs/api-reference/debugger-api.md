# Debugger System API Guide

Complete guide to using the RAMBO debugger system for interactive debugging and analysis.

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Bidirectional Communication](#bidirectional-communication)
4. [API Reference](#api-reference)
   - [Initialization](#initialization)
   - [Callback Registration](#callback-registration)
   - [Helper Functions](#helper-functions)
5. [Breakpoint System](#breakpoint-system)
6. [Watchpoint System](#watchpoint-system)
7. [Step Execution](#step-execution)
8. [Execution History](#execution-history)
9. [State Manipulation](#state-manipulation)
   - [CPU Register Manipulation](#cpu-register-manipulation)
   - [CPU Status Flag Manipulation](#cpu-status-flag-manipulation)
   - [Memory Manipulation](#memory-manipulation)
   - [PPU State Manipulation](#ppu-state-manipulation)
   - [Modification History](#modification-history)
10. [Usage Examples](#usage-examples)
11. [Best Practices](#best-practices)

## Overview

The RAMBO debugger provides comprehensive debugging capabilities for NES emulation, enabling:

- **Breakpoints**: Pause execution at specific addresses or memory access
- **Watchpoints**: Monitor memory regions for reads, writes, or value changes
- **Step Execution**: Step through code instruction-by-instruction, over subroutines, or by frame
- **Execution History**: Snapshot-based time-travel debugging with state capture/restore
- **Statistics**: Track execution metrics (instructions, breakpoints hit, etc.)
- **Bidirectional Mailboxes**: RT-safe communication between main and emulation threads

### Key Features

- **External Wrapper Pattern**: Debugger wraps EmulationState without modifying it
- **Snapshot Integration**: Uses snapshot system for execution history
- **Conditional Breakpoints**: Break based on register values or hit counts
- **Multiple Step Modes**: Instruction, over, out, scanline, frame
- **Memory Watching**: Read/write/change detection with range support
- **Zero Performance Impact**: When running mode is active, minimal overhead

### Architecture

```
Debugger (external wrapper)
    ↓
EmulationState (unchanged)
    ↓
shouldBreak() → checks breakpoints/steps → returns true/false
checkMemoryAccess() → checks watchpoints → returns true/false
```

## Quick Start

### Command-Line Debugging

```bash
# Break at reset vector and inspect CPU state
zig-out/bin/RAMBO rom.nes --break-at 0x8000 --inspect

# Output:
[Main] === BREAKPOINT HIT ===
[Main] Reason: Breakpoint at $8000 (hit count: 1)

[Main] CPU State:
  A:  $1A  X:  $00  Y:  $00
  SP: $EF  PC: $8045
  P:  $24  [---I--]
  Cycle: 29780  Frame: 0
```

### Basic Debugging Session

```zig
const std = @import("std");
const RAMBO = @import("RAMBO");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Setup emulation state
    var config = RAMBO.Config.Config.init(allocator);
    defer config.deinit();

    var state = // ... initialize EmulationState
    state.connectComponents();

    // Create debugger
    var debugger = RAMBO.Debugger.Debugger.init(allocator, &config);
    defer debugger.deinit();

    // Add breakpoint at reset vector
    try debugger.addBreakpoint(0x8000, .execute);

    // Add watchpoint for PPU control register
    try debugger.addWatchpoint(0x2000, 1, .write);

    // Execution loop with debugging
    while (true) {
        // Check if we should break before execution
        if (try debugger.shouldBreak(&state)) {
            std.debug.print("Breakpoint hit at ${X:0>4}\n", .{state.cpu.pc});

            // Interactive debugging here...

            // Continue execution
            debugger.continue_();
        }

        // Execute one CPU instruction
        // ... tick cpu ...

        // Check memory access (if any)
        // if (memory_access_occurred) {
        //     _ = try debugger.checkMemoryAccess(&state, address, value, is_write);
        // }
    }
}
```

## Bidirectional Communication

**Status:** ✅ Implemented (2025-10-08)
**Documentation:** `docs/implementation/BIDIRECTIONAL-DEBUG-MAILBOXES-2025-10-08.md`

The debugger supports RT-safe bidirectional communication using lock-free mailboxes:

### Architecture

```
Main Thread                    Emulation Thread
     |                                |
     |  DebugCommandMailbox          |
     |------------------------->      |
     |  (64 commands)                 |
     |                                |
     |  DebugEventMailbox            |
     |<-------------------------|     |
     |  (32 events)                   |
```

### Debug Commands (Main → Emulation)

Send commands to the emulation thread without blocking:

```zig
// Commands available via DebugCommandMailbox
pub const DebugCommand = union(enum) {
    add_breakpoint: struct { address: u16, bp_type: BreakpointType },
    remove_breakpoint: struct { address: u16, bp_type: BreakpointType },
    add_watchpoint: struct { address: u16, size: u16, watch_type: WatchType },
    remove_watchpoint: struct { address: u16, watch_type: WatchType },
    pause,
    resume_execution,
    step_instruction,
    step_frame,
    inspect,
    clear_breakpoints,
    clear_watchpoints,
    set_breakpoint_enabled: struct { address: u16, bp_type: BreakpointType, enabled: bool },
};

// Example: Send command from main thread
_ = mailboxes.debug_command.postCommand(.{
    .add_breakpoint = .{ .address = 0x8000, .bp_type = .execute }
});
```

### Debug Events (Emulation → Main)

Receive debug events with immutable CPU snapshots:

```zig
// Events received via DebugEventMailbox
pub const DebugEvent = union(enum) {
    breakpoint_hit: struct {
        reason: [128]u8,
        reason_len: usize,
        snapshot: CpuSnapshot
    },
    watchpoint_hit: struct {
        reason: [128]u8,
        reason_len: usize,
        snapshot: CpuSnapshot
    },
    inspect_response: struct { snapshot: CpuSnapshot },
    paused: struct { snapshot: CpuSnapshot },
    resumed,
    breakpoint_added: struct { address: u16 },
    breakpoint_removed: struct { address: u16 },
    error_occurred: struct { message: [128]u8, message_len: usize },
};

// Example: Process events in main thread
var debug_events: [16]RAMBO.Mailboxes.DebugEvent = undefined;
const count = mailboxes.debug_event.drainEvents(&debug_events);

for (debug_events[0..count]) |event| {
    switch (event) {
        .breakpoint_hit => |bp| {
            const reason = bp.reason[0..bp.reason_len];
            std.debug.print("Breakpoint: {s}\n", .{reason});
            printCpuSnapshot(bp.snapshot);
        },
        .inspect_response => |resp| {
            printCpuSnapshot(resp.snapshot);
        },
        // ... handle other events
    }
}
```

### CPU Snapshot

Immutable CPU state captured at debug events:

```zig
pub const CpuSnapshot = struct {
    a: u8,      // Accumulator
    x: u8,      // X register
    y: u8,      // Y register
    sp: u8,     // Stack pointer
    pc: u16,    // Program counter
    p: u8,      // Status flags (packed)
    cycle: u64, // CPU cycle count
    frame: u64, // PPU frame count
};
```

### RT-Safety Guarantees

**✅ Zero heap allocations** - All buffers stack-allocated
**✅ Lock-free communication** - Atomic SPSC ring buffers
**✅ Non-blocking operations** - `pollCommand()` returns immediately
**✅ No blocking I/O** - All `std.debug.print` removed from emulation thread

### Usage Pattern

```zig
// Main thread event loop
while (running) {
    // Process debug events (non-blocking)
    var debug_events: [16]DebugEvent = undefined;
    const count = mailboxes.debug_event.drainEvents(&debug_events);

    for (debug_events[0..count]) |event| {
        // Handle event (can use blocking I/O here - not RT-critical)
        handleDebugEvent(event);
    }

    // Send debug commands (non-blocking)
    if (user_wants_to_step) {
        _ = mailboxes.debug_command.postCommand(.step_instruction);
    }

    // Continue main loop
    try loop.run(.no_wait);
}

// Emulation thread (RT-safe)
fn timerCallback(ctx: *EmulationContext) void {
    // Process commands (non-blocking poll)
    while (ctx.mailboxes.debug_command.pollCommand()) |command| {
        handleDebugCommand(ctx, command); // No blocking I/O!
    }

    // Execute frame
    ctx.state.tick();

    // Post events if break occurred
    if (ctx.state.debug_break_occurred) {
        const snapshot = captureSnapshot(ctx);
        _ = ctx.mailboxes.debug_event.postEvent(.{
            .breakpoint_hit = .{ /* ... */ }
        });
    }
}
```

## API Reference

### Debugger Structure

```zig
pub const Debugger = struct {
    allocator: std.mem.Allocator,
    config: *const Config,
    mode: DebugMode,
    breakpoints: std.ArrayList(Breakpoint),
    watchpoints: std.ArrayList(Watchpoint),
    step_state: StepState,
    history: std.ArrayList(HistoryEntry),
    history_max_size: usize,
    stats: DebugStats,
    last_break_reason: ?[]const u8,
};
```

### Debug Modes

```zig
pub const DebugMode = enum {
    running,          // Normal execution
    paused,           // Execution paused
    step_instruction, // Step one instruction
    step_over,        // Step over subroutines
    step_out,         // Step out of subroutines
    step_scanline,    // Step to next scanline
    step_frame,       // Step to next frame
};
```

### Initialization

```zig
pub fn init(allocator: std.mem.Allocator, config: *const Config) Debugger
pub fn deinit(self: *Debugger) void
```

**Parameters:**
- `allocator`: Memory allocator for debugger data
- `config`: Hardware configuration reference

**Returns:** Initialized debugger in `.running` mode

### Callback Registration

The debugger supports user-defined callbacks for custom debugging logic. All callbacks must be RT-safe (no heap allocations, no blocking operations).

```zig
pub fn registerCallback(self: *Debugger, callback: DebugCallback) !void
pub fn unregisterCallback(self: *Debugger, userdata: *anyopaque) bool
pub fn clearCallbacks(self: *Debugger) void
```

**Callback Structure:**

```zig
pub const DebugCallback = struct {
    /// Called before each instruction execution
    /// Return true to break, false to continue
    /// Receives const state - read-only access
    onBeforeInstruction: ?*const fn (self: *anyopaque, state: *const EmulationState) bool = null,

    /// Called on memory access (read or write)
    /// Return true to break, false to continue
    /// address: Memory address being accessed
    /// value: Value being read or written
    /// is_write: true for write, false for read
    onMemoryAccess: ?*const fn (self: *anyopaque, address: u16, value: u8, is_write: bool) bool = null,

    /// User data pointer (context for callbacks)
    userdata: *anyopaque,
};
```

**Parameters:**
- `callback`: Callback structure with optional function pointers
- `userdata`: Opaque pointer for identifying/removing callbacks

**Returns:**
- `registerCallback`: Error if more than 8 callbacks registered
- `unregisterCallback`: true if callback was found and removed, false otherwise

**Errors:**
- `error.TooManyCallbacks`: Maximum of 8 callbacks can be registered simultaneously

**RT-Safety Requirements:**

1. **No Heap Allocations:** Callbacks must not allocate memory
2. **No Blocking Operations:** No I/O, no mutex locks, no syscalls
3. **Deterministic Execution:** Callbacks should complete quickly (<1μs)
4. **Read-Only State:** EmulationState is const, use debugger.readMemory() for inspection

**Example:**

```zig
const TracerContext = struct {
    instruction_count: u64 = 0,
    target_address: u16,

    fn onInstruction(ctx_ptr: *anyopaque, state: *const EmulationState) callconv(.C) bool {
        const self = @ptrCast(*TracerContext, @alignCast(@alignOf(TracerContext), ctx_ptr));
        self.instruction_count += 1;

        // Break at specific address
        if (state.cpu.pc == self.target_address) {
            return true;  // Trigger break
        }

        return false;  // Continue execution
    }

    fn onMemoryWrite(ctx_ptr: *anyopaque, address: u16, value: u8, is_write: bool) callconv(.C) bool {
        if (!is_write) return false;

        // Break on write to PPU control register
        if (address == 0x2000) {
            return true;
        }

        return false;
    }
};

// Register custom callback
var tracer = TracerContext{ .target_address = 0x8000 };
const callback = DebugCallback{
    .onBeforeInstruction = TracerContext.onInstruction,
    .onMemoryAccess = TracerContext.onMemoryWrite,
    .userdata = &tracer,
};

try debugger.registerCallback(callback);

// ... run emulation ...

// Remove callback when done
_ = debugger.unregisterCallback(&tracer);

// Or clear all callbacks
debugger.clearCallbacks();
```

**Advanced Usage - Multiple Callbacks:**

```zig
// Callback 1: Instruction tracer
var tracer = InstructionTracer{};
try debugger.registerCallback(.{
    .onBeforeInstruction = InstructionTracer.callback,
    .userdata = &tracer,
});

// Callback 2: Memory access logger
var memory_logger = MemoryLogger{};
try debugger.registerCallback(.{
    .onMemoryAccess = MemoryLogger.callback,
    .userdata = &memory_logger,
});

// Callback 3: Conditional breakpoint
var conditional = ConditionalBreak{ .break_if_a_equals = 0x42 };
try debugger.registerCallback(.{
    .onBeforeInstruction = ConditionalBreak.callback,
    .userdata = &conditional,
});

// All three callbacks will be invoked in registration order
```

**Common Patterns:**

```zig
// 1. Instruction count limiting
const CountLimiter = struct {
    max_instructions: u64,
    count: u64 = 0,

    fn callback(ctx: *anyopaque, _: *const EmulationState) bool {
        const self = @ptrCast(*CountLimiter, @alignCast(@alignOf(CountLimiter), ctx));
        self.count += 1;
        return self.count >= self.max_instructions;
    }
};

// 2. Address range breakpoint
const RangeBreak = struct {
    start: u16,
    end: u16,

    fn callback(ctx: *anyopaque, state: *const EmulationState) bool {
        const self = @ptrCast(*RangeBreak, @alignCast(@alignOf(RangeBreak), ctx));
        return state.cpu.pc >= self.start and state.cpu.pc < self.end;
    }
};

// 3. Register condition breakpoint
const RegisterCondition = struct {
    fn callback(_: *anyopaque, state: *const EmulationState) bool {
        // Break if A == X and Y != 0
        return state.cpu.a == state.cpu.x and state.cpu.y != 0;
    }
};
```

### Helper Functions

```zig
pub fn getBreakReason(self: *const Debugger) ?[]const u8
pub fn isPaused(self: *const Debugger) bool
pub fn hasMemoryTriggers(self: *const Debugger) bool
```

**getBreakReason:**

Returns the reason for the last break event, or null if no break has occurred.

**Returns:** String describing why execution paused (null if never paused)

**Example:**

```zig
if (try debugger.shouldBreak(&state)) {
    if (debugger.getBreakReason()) |reason| {
        std.debug.print("Execution paused: {s}\n", .{reason});
    }

    // Typical reasons:
    // "Breakpoint at $8000 (hit count: 1)"
    // "Watchpoint: write $2000 = $90"
    // "Step instruction"
    // "Step over complete"
    // "User callback break"
}
```

**isPaused:**

Fast check for whether debugger is currently in paused state.

**Returns:** true if mode is `.paused`, false otherwise

**Example:**

```zig
// Check if debugger is waiting for user input
if (debugger.isPaused()) {
    try showDebuggerPrompt(&debugger, &state);
} else {
    // Continue normal execution
    try state.tick();
}

// Equivalent to:
if (debugger.state.mode == .paused) { ... }
```

**hasMemoryTriggers:**

Fast check for any active memory breakpoints or watchpoints. Optimization hint for emulation loop.

**Returns:** true if any read/write/access breakpoints or watchpoints are enabled

**Example:**

```zig
// Optimize emulation loop - only check memory access if triggers exist
while (running) {
    if (try debugger.shouldBreak(&state)) {
        // Handle breakpoint
        break;
    }

    // Execute instruction
    const address = state.cpu.readByte();  // Example memory access

    // Only check if memory triggers exist (performance optimization)
    if (debugger.hasMemoryTriggers()) {
        if (try debugger.checkMemoryAccess(&state, address, value, is_write)) {
            // Handle memory watchpoint
            break;
        }
    }

    try state.tick();
}
```

**Performance Considerations:**

- `isPaused()`: O(1) - simple enum comparison
- `hasMemoryTriggers()`: O(1) - checks breakpoint/watchpoint counts
- `getBreakReason()`: O(1) - returns pre-formatted string slice

All helper functions are inline and have zero overhead in release builds.

## Breakpoint System

### Breakpoint Types

```zig
pub const BreakpointType = enum {
    execute, // Break when PC reaches address
    read,    // Break when address is read
    write,   // Break when address is written
    access,  // Break on read OR write
};
```

### Conditional Breakpoints

```zig
pub const BreakCondition = union(enum) {
    a_equals: u8,     // Break if A == value
    x_equals: u8,     // Break if X == value
    y_equals: u8,     // Break if Y == value
    hit_count: u64,   // Break after N hits
};
```

### Breakpoint Management

```zig
pub fn addBreakpoint(
    self: *Debugger,
    address: u16,
    bp_type: BreakpointType,
) !void

pub fn removeBreakpoint(
    self: *Debugger,
    address: u16,
    bp_type: BreakpointType,
) bool

pub fn setBreakpointEnabled(
    self: *Debugger,
    address: u16,
    bp_type: BreakpointType,
    enabled: bool,
) bool

pub fn clearBreakpoints(self: *Debugger) void
```

**Example:**

```zig
// Execute breakpoint at entry point
try debugger.addBreakpoint(0x8000, .execute);

// Write breakpoint with condition (break if A == 0x42)
var bp_idx = debugger.breakpoints.items.len;
try debugger.addBreakpoint(0x2000, .write);
debugger.breakpoints.items[bp_idx].condition = .{ .a_equals = 0x42 };

// Temporarily disable breakpoint
_ = debugger.setBreakpointEnabled(0x8000, .execute, false);

// Remove breakpoint
_ = debugger.removeBreakpoint(0x8000, .execute);
```

## Watchpoint System

### Watchpoint Types

```zig
pub const WatchType = enum {
    read,   // Break on read
    write,  // Break on write
    change, // Break only when value changes
};
```

### Watchpoint Structure

```zig
pub const Watchpoint = struct {
    address: u16,
    size: u16 = 1,          // Watch range size
    type: WatchType,
    enabled: bool = true,
    hit_count: u64 = 0,
    old_value: ?u8 = null,  // For change detection
};
```

### Watchpoint Management

```zig
pub fn addWatchpoint(
    self: *Debugger,
    address: u16,
    size: u16,
    watch_type: WatchType,
) !void

pub fn removeWatchpoint(
    self: *Debugger,
    address: u16,
    watch_type: WatchType,
) bool

pub fn clearWatchpoints(self: *Debugger) void
```

**Example:**

```zig
// Watch single byte for writes
try debugger.addWatchpoint(0x2000, 1, .write);

// Watch memory range for reads (64 bytes)
try debugger.addWatchpoint(0x0200, 64, .read);

// Watch for value changes (zero page)
try debugger.addWatchpoint(0x00, 256, .change);

// Check memory access in emulation loop
if (memory_write_occurred) {
    if (try debugger.checkMemoryAccess(&state, address, value, true)) {
        std.debug.print("Watchpoint triggered!\n", .{});
    }
}
```

## Step Execution

### Execution Control

```zig
pub fn continue_(self: *Debugger) void
pub fn pause(self: *Debugger) void
pub fn stepInstruction(self: *Debugger) void
pub fn stepOver(self: *Debugger, state: *const EmulationState) void
pub fn stepOut(self: *Debugger, state: *const EmulationState) void
pub fn stepScanline(self: *Debugger, state: *const EmulationState) void
pub fn stepFrame(self: *Debugger, state: *const EmulationState) void
```

### Execution Hooks

```zig
pub fn shouldBreak(
    self: *Debugger,
    state: *const EmulationState,
) !bool

pub fn checkMemoryAccess(
    self: *Debugger,
    state: *const EmulationState,
    address: u16,
    value: u8,
    is_write: bool,
) !bool
```

**Example:**

```zig
// Step one instruction
debugger.stepInstruction();
// ... execute one instruction ...
// shouldBreak() will return true after instruction completes

// Step over subroutine (JSR)
debugger.stepOver(&state);
// ... execute instructions ...
// Will break when SP returns to same level (after RTS)

// Step out of current subroutine
debugger.stepOut(&state);
// ... execute instructions ...
// Will break when SP increases (RTS executed)

// Step to next scanline
debugger.stepScanline(&state);
// Will break when PPU scanline advances

// Step to next frame
debugger.stepFrame(&state);
// Will break when PPU frame counter increments
```

## Execution History

### History Management

```zig
pub fn captureHistory(
    self: *Debugger,
    state: *const EmulationState,
) !void

pub fn restoreFromHistory(
    self: *Debugger,
    index: usize,
    cartridge: ?AnyCartridge,
) !EmulationState

pub fn clearHistory(self: *Debugger) void
```

**History Entry:**

```zig
pub const HistoryEntry = struct {
    snapshot: []u8,      // Complete state snapshot
    pc: u16,             // PC at capture time
    scanline: u16,       // PPU scanline
    frame: u64,          // PPU frame
    timestamp: i64,      // Unix timestamp
};
```

**Example:**

```zig
// Capture state every N instructions
var instruction_count: u64 = 0;
while (running) {
    if (instruction_count % 1000 == 0) {
        try debugger.captureHistory(&state);
    }

    // ... execute instruction ...
    instruction_count += 1;
}

// Rewind to earlier state
const restored_state = try debugger.restoreFromHistory(5, cartridge);
// Time-travel debugging: state is now at history[5]
```

## State Manipulation

The debugger provides comprehensive state manipulation for testing, save state editing, and dynamic debugging scenarios. All mutations are tracked in the modification history for transparency.

### CPU Register Manipulation

```zig
pub fn setRegisterA(self: *Debugger, state: *EmulationState, value: u8) void
pub fn setRegisterX(self: *Debugger, state: *EmulationState, value: u8) void
pub fn setRegisterY(self: *Debugger, state: *EmulationState, value: u8) void
pub fn setStackPointer(self: *Debugger, state: *EmulationState, value: u8) void
pub fn setProgramCounter(self: *Debugger, state: *EmulationState, value: u16) void
```

**Parameters:**
- `self`: Debugger instance
- `state`: Mutable EmulationState reference
- `value`: New register value (u8 for 8-bit registers, u16 for PC)

**Side Effects:**
- Modifies CPU register immediately
- Records modification in modification history
- Does NOT trigger breakpoints or watchpoints

**Example:**

```zig
// Initialize CPU registers for testing
debugger.setRegisterA(&state, 0x42);
debugger.setRegisterX(&state, 0x10);
debugger.setRegisterY(&state, 0x20);
debugger.setStackPointer(&state, 0xFF);
debugger.setProgramCounter(&state, 0x8000);

// Simulate JSR by manipulating PC and SP
const return_addr = state.cpu.pc + 2;
debugger.setStackPointer(&state, state.cpu.sp -% 2);
debugger.setProgramCounter(&state, 0xC000);

// Verify modifications were tracked
const mods = debugger.getModifications();
std.debug.print("Recorded {} modifications\n", .{mods.len});
```

### CPU Status Flag Manipulation

```zig
pub fn setStatusFlag(
    self: *Debugger,
    state: *EmulationState,
    flag: StatusFlag,
    value: bool,
) void

pub fn setStatusRegister(self: *Debugger, state: *EmulationState, value: u8) void
```

**Status Flags:**

```zig
pub const StatusFlag = enum {
    carry,      // Bit 0: Carry flag
    zero,       // Bit 1: Zero flag
    interrupt,  // Bit 2: Interrupt disable
    decimal,    // Bit 3: Decimal mode (not used on NES)
    overflow,   // Bit 6: Overflow flag
    negative,   // Bit 7: Negative flag
};
```

**Parameters:**
- `flag`: Individual status flag to modify
- `value`: true to set flag, false to clear flag
- For `setStatusRegister`: raw u8 value (bits 4-5 ignored per 6502 spec)

**Example:**

```zig
// Set individual flags
debugger.setStatusFlag(&state, .carry, true);
debugger.setStatusFlag(&state, .zero, false);
debugger.setStatusFlag(&state, .overflow, true);

// Verify flag state
const carry_set = (state.cpu.p.raw() & 0x01) != 0;
try testing.expect(carry_set);

// Set complete status register (bits 4-5 ignored)
debugger.setStatusRegister(&state, 0b1010_0101);
// Result: Carry=1, Zero=1, Interrupt=0, Decimal=0, Overflow=1, Negative=1

// Common use case: Force specific condition for testing
debugger.setStatusFlag(&state, .zero, true);  // Force Z=1 for BEQ test
debugger.setStatusFlag(&state, .carry, false); // Force C=0 for BCC test
```

### Memory Manipulation

```zig
pub fn writeMemory(
    self: *Debugger,
    state: *EmulationState,
    address: u16,
    value: u8,
) void

pub fn writeMemoryRange(
    self: *Debugger,
    state: *EmulationState,
    start_address: u16,
    data: []const u8,
) void

pub fn readMemory(
    self: *Debugger,
    state: *const EmulationState,
    address: u16,
) u8

pub fn readMemoryRange(
    self: *Debugger,
    allocator: std.mem.Allocator,
    state: *const EmulationState,
    start_address: u16,
    length: u16,
) ![]u8
```

**Write Operations:**

**Parameters:**
- `address` / `start_address`: Target memory address (6502 address space: $0000-$FFFF)
- `value`: Byte value to write
- `data`: Slice of bytes to write sequentially

**Side Effects:**
- Writes through normal bus (triggers PPU/APU register writes)
- Records modification in history
- Does NOT trigger watchpoints during debugger writes

**Read Operations:**

**Parameters:**
- `address` / `start_address`: Memory address to read
- `length`: Number of bytes to read
- `allocator`: For range reads, allocates return buffer (caller must free)

**Returns:**
- `readMemory`: Single byte value
- `readMemoryRange`: Allocated slice (caller owns memory)

**Side Effects:**
- Reads WITHOUT side effects (safe for inspection)
- Does NOT trigger PPU latch updates or port reads
- Does NOT increment DMC address or other hardware state

**Example:**

```zig
// Write test data to zero page
const test_data = [_]u8{ 0x01, 0x02, 0x03, 0x04 };
debugger.writeMemoryRange(&state, 0x00, &test_data);

// Write single byte
debugger.writeMemory(&state, 0x10, 0xFF);

// Read for verification (no side effects)
const value = debugger.readMemory(&state, 0x10);
try testing.expectEqual(@as(u8, 0xFF), value);

// Read range for analysis
const buffer = try debugger.readMemoryRange(allocator, &state, 0x0000, 256);
defer allocator.free(buffer);

// Dump zero page contents
for (buffer, 0..) |byte, i| {
    if (i % 16 == 0) std.debug.print("\n${X:0>4}:", .{i});
    std.debug.print(" {X:0>2}", .{byte});
}

// Safe PPU register inspection (no latch side effects)
const ppu_ctrl = debugger.readMemory(&state, 0x2000);
const ppu_status = debugger.readMemory(&state, 0x2002);  // Does NOT clear vblank!
```

**Important Notes:**

1. **Bus Routing:** Writes go through the normal bus system:
   - `$0000-$07FF`: Internal RAM (mirrored to $1FFF)
   - `$2000-$3FFF`: PPU registers (mirrored every 8 bytes)
   - `$4000-$4017`: APU/IO registers
   - `$8000-$FFFF`: Cartridge ROM/RAM

2. **Side-Effect-Free Reads:** `readMemory()` bypasses hardware side effects:
   - Reading `$2002` does NOT clear VBlank flag
   - Reading `$2007` does NOT increment VRAM address
   - Reading `$4016/$4017` does NOT shift controller latches

3. **Watchpoint Suppression:** Debugger writes do NOT trigger watchpoints (prevents infinite recursion during debugging).

### PPU State Manipulation

```zig
pub fn setPpuScanline(self: *Debugger, state: *EmulationState, scanline: u16) void
pub fn setPpuFrame(self: *Debugger, state: *EmulationState, frame: u64) void
```

**Parameters:**
- `scanline`: PPU scanline number (0-261, NTSC timing)
  - 0-239: Visible scanlines
  - 240: Post-render scanline
  - 241-260: VBlank period
  - 261: Pre-render scanline
- `frame`: PPU frame counter (increments at scanline 0)

**Side Effects:**
- Directly modifies PPU timing state
- Does NOT trigger VBlank NMI or other PPU events
- Recorded in modification history

**Example:**

```zig
// Jump to VBlank period for testing
debugger.setPpuScanline(&state, 241);

// Fast-forward to specific frame
debugger.setPpuFrame(&state, 100);

// Test VBlank flag behavior at scanline boundary
debugger.setPpuScanline(&state, 240);  // Pre-VBlank
const status_before = debugger.readMemory(&state, 0x2002);
debugger.setPpuScanline(&state, 241);  // VBlank start
const status_after = debugger.readMemory(&state, 0x2002);
try testing.expect((status_after & 0x80) != 0);  // VBlank flag set

// Verify frame timing
const initial_frame = state.clock.frame();
debugger.setPpuFrame(&state, initial_frame + 10);
try testing.expectEqual(initial_frame + 10, state.clock.frame());
```

### Modification History

All state manipulations are tracked for transparency and debugging:

```zig
pub fn getModifications(self: *const Debugger) []const StateModification
pub fn clearModifications(self: *Debugger) void
```

**State Modification Types:**

```zig
pub const StateModification = union(enum) {
    register_a: u8,
    register_x: u8,
    register_y: u8,
    stack_pointer: u8,
    program_counter: u16,
    status_flag: struct { flag: StatusFlag, value: bool },
    status_register: u8,
    memory_write: struct { address: u16, value: u8 },
    memory_range: struct { start: u16, length: u16 },
    ppu_ctrl: u8,
    ppu_mask: u8,
    ppu_scroll: struct { x: u8, y: u8 },
    ppu_addr: u16,
    ppu_vram: struct { address: u16, value: u8 },
    ppu_scanline: u16,
    ppu_frame: u64,
};
```

**Parameters:**
- `getModifications()`: Returns slice of all recorded modifications (read-only)
- `clearModifications()`: Clears modification history

**Example:**

```zig
// Perform several modifications
debugger.setRegisterA(&state, 0x42);
debugger.setProgramCounter(&state, 0x8000);
debugger.writeMemory(&state, 0x2000, 0x90);

// Review modification history
const mods = debugger.getModifications();
std.debug.print("Recorded {} modifications:\n", .{mods.len});

for (mods) |mod| {
    switch (mod) {
        .register_a => |val| std.debug.print("  A = ${X:0>2}\n", .{val}),
        .program_counter => |val| std.debug.print("  PC = ${X:0>4}\n", .{val}),
        .memory_write => |data| std.debug.print("  [{X:0>4}] = ${X:0>2}\n",
            .{data.address, data.value}),
        else => {},
    }
}

// Clear history for next test
debugger.clearModifications();
try testing.expectEqual(@as(usize, 0), debugger.getModifications().len);
```

**Use Cases:**

1. **Test Verification:** Ensure test setup modifies only intended state
2. **Save State Editing:** Track what changed when editing save states
3. **Debugging Transparency:** Understand what debugger changed vs. emulation
4. **Undo Support:** Potential future feature for reverting modifications

### Statistics

```zig
pub const DebugStats = struct {
    instructions_executed: u64 = 0,
    breakpoints_hit: u64 = 0,
    watchpoints_hit: u64 = 0,
    snapshots_captured: u64 = 0,
};
```

## Usage Examples

### Interactive Debugger

```zig
const Debugger = struct {
    debug: RAMBO.Debugger.Debugger,
    state: *RAMBO.EmulationState.EmulationState,

    pub fn run(self: *Debugger) !void {
        while (true) {
            // Check for breakpoints
            if (try self.debug.shouldBreak(self.state)) {
                try self.showDebugPrompt();
            }

            // Execute one instruction
            // ... tick CPU ...
        }
    }

    fn showDebugPrompt(self: *Debugger) !void {
        std.debug.print("\n=== Debugger ===\n", .{});
        std.debug.print("PC: ${X:0>4}  A: ${X:0>2}  X: ${X:0>2}  Y: ${X:0>2}\n",
            .{self.state.cpu.pc, self.state.cpu.a, self.state.cpu.x, self.state.cpu.y});

        if (self.debug.last_break_reason) |reason| {
            std.debug.print("Reason: {s}\n", .{reason});
        }

        // Interactive commands...
        const cmd = try readCommand();

        switch (cmd) {
            .continue_ => self.debug.continue_(),
            .step => self.debug.stepInstruction(),
            .step_over => self.debug.stepOver(self.state),
            .add_breakpoint => |addr| try self.debug.addBreakpoint(addr, .execute),
            // ... more commands ...
        }
    }
};
```

### Automated Testing

```zig
pub fn runTestWithBreakpoint(
    state: *EmulationState,
    breakpoint_addr: u16,
    expected_a: u8,
) !void {
    var debugger = Debugger.init(testing.allocator, state.config);
    defer debugger.deinit();

    // Break at target address
    try debugger.addBreakpoint(breakpoint_addr, .execute);

    // Run until breakpoint
    var max_instructions: usize = 10000;
    while (max_instructions > 0) : (max_instructions -= 1) {
        if (try debugger.shouldBreak(state)) {
            break;
        }
        // ... execute instruction ...
    }

    // Verify state
    try testing.expectEqual(breakpoint_addr, state.cpu.pc);
    try testing.expectEqual(expected_a, state.cpu.a);
}
```

### Memory Corruption Detector

```zig
pub const CorruptionDetector = struct {
    debugger: Debugger,
    protected_ranges: []MemoryRange,

    pub fn checkMemoryWrite(
        self: *CorruptionDetector,
        state: *EmulationState,
        address: u16,
        value: u8,
    ) !void {
        // Check if write is in protected range
        for (self.protected_ranges) |range| {
            if (address >= range.start and address < range.end) {
                std.debug.print("CORRUPTION DETECTED: Write to protected address ${X:0>4} = ${X:0>2}\n",
                    .{address, value});
                std.debug.print("PC: ${X:0>4}  Stack: ${X:0>2}\n",
                    .{state.cpu.pc, state.cpu.sp});

                // Capture snapshot for analysis
                try self.debugger.captureHistory(state);

                return error.MemoryCorruption;
            }
        }
    }
};
```

### Frame-by-Frame Analysis

```zig
pub fn analyzeFrames(
    state: *EmulationState,
    num_frames: usize,
) !void {
    var debugger = Debugger.init(allocator, state.config);
    defer debugger.deinit();

    var frame: usize = 0;
    while (frame < num_frames) {
        // Capture snapshot at frame start
        try debugger.captureHistory(state);

        debugger.stepFrame(state);

        // Run until frame completes
        while (!try debugger.shouldBreak(state)) {
            // ... execute instructions ...
        }

        // Analyze frame
        std.debug.print("Frame {}: {} instructions, scanline {}\n",
            .{frame, debugger.stats.instructions_executed, state.ppu.scanline});

        frame += 1;
        debugger.continue_();
    }
}
```

## Best Practices

### When to Use Execute Breakpoints

Use `.execute` breakpoints when:
- ✅ Debugging control flow
- ✅ Finding where specific code runs
- ✅ Analyzing subroutine calls
- ✅ Testing reset vectors

### When to Use Memory Breakpoints

Use `.read`/`.write`/`.access` breakpoints when:
- ✅ Finding memory corruption sources
- ✅ Tracking I/O register access
- ✅ Debugging DMA operations
- ✅ Analyzing memory-mapped hardware

### When to Use Watchpoints

Use watchpoints when:
- ✅ Monitoring memory regions
- ✅ Detecting value changes (`.change` type)
- ✅ Tracking sprite OAM updates
- ✅ Watching for specific writes

### Execution History Best Practices

**Circular Buffer Size:**
- Small games: 100-500 snapshots
- Complex games: 1000-5000 snapshots
- Memory usage: ~5KB per snapshot (reference mode)

**Capture Frequency:**
- Every frame: For rendering analysis
- Every N instructions: For general debugging
- On breakpoint: For state comparison
- Before critical operations: For rollback

### Performance Considerations

**Running Mode:**
- Zero overhead when no breakpoints/watchpoints set
- Minimal overhead with breakpoints (hash table lookup)

**Paused/Step Modes:**
- Full debugging checks on every instruction
- Snapshot capture can be expensive (~5ms)

**Optimization:**
- Remove unused breakpoints
- Limit history buffer size
- Use conditional breakpoints to reduce false hits

## Architecture Notes

### External Wrapper Pattern

The debugger wraps EmulationState without modifying it:

```zig
// EmulationState remains pure data
pub const EmulationState = struct {
    cpu: CpuState,
    ppu: PpuState,
    bus: BusState,
    // ... no debugger code here ...
};

// Debugger lives externally
pub const Debugger = struct {
    // Communicates via hooks
    pub fn shouldBreak(state: *const EmulationState) bool
    pub fn checkMemoryAccess(state: *const EmulationState, ...) bool
};
```

### Snapshot Integration

Execution history uses the snapshot system:
- `captureHistory()` calls `Snapshot.saveBinary()`
- `restoreFromHistory()` calls `Snapshot.loadBinary()`
- Circular buffer with automatic cleanup
- Full state preservation including PPU frame

### Step Execution Implementation

**Step Over Logic:**
1. Record initial SP when stepping starts
2. Set `has_stepped = false`
3. First `shouldBreak()` call: set `has_stepped = true`, return false
4. Subsequent calls: break if `SP >= initial_sp`

**Step Out Logic:**
1. Record initial SP
2. Break when `SP > initial_sp` (RTS executed)

**Step Scanline/Frame Logic:**
1. Record target scanline/frame = current + 1
2. Break when target reached

---

**Last Updated:** 2025-10-11
**Version:** 1.2
**RAMBO Version:** 0.2.0-alpha
**Changelog:**
- 2025-10-11: Added comprehensive documentation for 19 missing methods:
  - CPU register manipulation (5 methods)
  - CPU status flag manipulation (2 methods)
  - Memory manipulation (4 methods)
  - PPU state manipulation (2 methods)
  - Modification history (2 methods)
  - Callback registration (3 methods)
  - Helper functions (3 methods)
- 2025-10-08: Added bidirectional mailbox communication section
- 2025-10-04: Initial debugger API documentation
