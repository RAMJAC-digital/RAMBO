# Debugger System API Guide

Complete guide to using the RAMBO debugger system for interactive debugging and analysis.

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Bidirectional Communication](#bidirectional-communication)
4. [API Reference](#api-reference)
5. [Breakpoint System](#breakpoint-system)
6. [Watchpoint System](#watchpoint-system)
7. [Step Execution](#step-execution)
8. [Execution History](#execution-history)
9. [Usage Examples](#usage-examples)
10. [Best Practices](#best-practices)

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

**Last Updated:** 2025-10-08
**Version:** 1.1
**RAMBO Version:** 0.1.0
**Changelog:**
- 2025-10-08: Added bidirectional mailbox communication section
- 2025-10-04: Initial debugger API documentation
