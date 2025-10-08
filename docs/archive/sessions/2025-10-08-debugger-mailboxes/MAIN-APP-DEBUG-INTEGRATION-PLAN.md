# Main Application Debug Integration Plan

**Date:** 2025-10-08
**Status:** 🔍 **PLANNING**
**Estimated Time:** 6-8 hours
**Priority:** P0 - Critical for commercial ROM debugging

---

## Objective

Integrate debugging capabilities directly into the main Vulkan application, enabling:
- Real-time execution tracing while visual output renders
- Breakpoint support with state inspection
- Memory watchpoints
- Cycle/frame limits for controlled execution
- Debug output to file or stdout

---

## Architecture Overview

### Current State
```
main.zig
├── Load ROM from command line
├── Spawn EmulationThread (timer-driven)
├── Spawn RenderThread (Vulkan window)
└── Main coordination loop (process input, run libxev)
```

### Target State
```
main.zig
├── CLI parsing (zli) - debug flags
├── Load ROM from command line
├── Debugger wrapper around EmulationState
├── Set breakpoints/watchpoints from CLI flags
├── Spawn EmulationThread (timer-driven)
│   └── Debug callbacks (trace, break, watch)
├── Spawn RenderThread (Vulkan window)
└── Main coordination loop
    ├── Process input
    ├── Check debug state (paused/running)
    └── Output debug logs
```

### Integration Points

```
┌──────────────────────────────────────────────────────┐
│                    main.zig (CLI)                     │
│  zli flags: --trace, --break, --watch, --inspect    │
└───────────────────────┬──────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────┐
│                  Debugger Wrapper                     │
│  - Breakpoints, watchpoints, step control            │
│  - Execution history, state inspection               │
└───────────────────────┬──────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────┐
│              EmulationState (core)                    │
│  EmulationThread reads debug flags before tick()     │
└──────────────────────────────────────────────────────┘
```

---

## Implementation Phases

### Phase 1: CLI Parsing with zli (2-3 hours)

**Objective:** Replace manual argument parsing with zli framework

**Tasks:**
1. Update `main.zig` to use zli App structure
2. Define CLI flags for debugging
3. Parse ROM path and debug options
4. Validate inputs

**CLI Specification:**
```zig
const App = zli.App{
    .name = "rambo",
    .version = "0.1.0",
    .description = "RAMBO NES Emulator - Multi-Threaded with Debugging",
};

const Flags = struct {
    // ROM file (positional argument)
    rom: ?[]const u8 = null,

    // Debug options
    trace: bool = false,              // Enable execution tracing
    trace_file: ?[]const u8 = null,   // Trace output file (default: stdout)

    break_at: ?[]const u16 = null,    // Breakpoint addresses (comma-separated)
    watch: ?[]const u16 = null,       // Watch addresses (comma-separated)

    cycles: ?u64 = null,              // Stop after N CPU cycles
    frames: ?u64 = null,              // Stop after N frames

    inspect: bool = false,            // Print state on exit
    verbose: bool = false,            // Verbose debug output
};
```

**Usage Examples:**
```bash
# Run Mario with Vulkan window (normal mode)
./zig-out/bin/RAMBO mario.nes

# Run with execution tracing to file
./zig-out/bin/RAMBO mario.nes --trace --trace-file mario_trace.txt

# Run with breakpoint at $8000
./zig-out/bin/RAMBO mario.nes --break-at 0x8000 --inspect

# Run for 30000 cycles with trace and breakpoints
./zig-out/bin/RAMBO mario.nes --cycles 30000 --trace --break-at 0x8000,0xFFFA

# Run for 3 frames with memory watch
./zig-out/bin/RAMBO mario.nes --frames 3 --watch 0x2000,0x2001 --verbose
```

**Code Changes:**
```zig
// main.zig (beginning)
const zli = @import("zli");

const DebugFlags = struct {
    trace: bool = false,
    trace_file: ?[]const u8 = null,
    break_at: ?[]const u16 = null,
    watch: ?[]const u16 = null,
    cycles: ?u64 = null,
    frames: ?u64 = null,
    inspect: bool = false,
    verbose: bool = false,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse CLI arguments with zli
    var app = zli.App.init(allocator);
    defer app.deinit();

    app.name = "rambo";
    app.version = "0.1.0";
    app.description = "RAMBO NES Emulator - Multi-Threaded Architecture";

    // Add flags
    try app.addFlag("trace", .{ .type = .bool, .description = "Enable execution tracing" });
    try app.addFlag("trace-file", .{ .type = .string, .description = "Trace output file" });
    try app.addFlag("break-at", .{ .type = .string, .description = "Breakpoint addresses (hex, comma-separated)" });
    try app.addFlag("watch", .{ .type = .string, .description = "Watch memory addresses (hex, comma-separated)" });
    try app.addFlag("cycles", .{ .type = .int, .description = "Stop after N CPU cycles" });
    try app.addFlag("frames", .{ .type = .int, .description = "Stop after N frames" });
    try app.addFlag("inspect", .{ .type = .bool, .description = "Print state on exit" });
    try app.addFlag("verbose", .{ .type = .bool, .description = "Verbose debug output" });

    try app.parse();

    // Extract ROM path (positional)
    const rom_path = app.positional(0) orelse {
        std.debug.print("Error: No ROM file specified\n", .{});
        std.debug.print("Usage: rambo <rom_file> [options]\n", .{});
        return error.NoRomFile;
    };

    // Extract debug flags
    const debug_flags = DebugFlags{
        .trace = app.flag("trace").?.asBool(),
        .trace_file = app.flag("trace-file").?.asString(),
        .break_at = parseHexArray(app.flag("break-at").?.asString()),
        .watch = parseHexArray(app.flag("watch").?.asString()),
        .cycles = if (app.flag("cycles").?.asInt()) |c| @intCast(c) else null,
        .frames = if (app.flag("frames").?.asInt()) |f| @intCast(f) else null,
        .inspect = app.flag("inspect").?.asBool(),
        .verbose = app.flag("verbose").?.asBool(),
    };

    // ... rest of initialization
}
```

**Deliverable:** CLI parsing works, flags extracted into DebugFlags struct

---

### Phase 2: Debugger Integration (2-3 hours)

**Objective:** Wrap EmulationState with Debugger, configure from CLI flags

**Tasks:**
1. Create Debugger instance
2. Configure breakpoints from `--break-at`
3. Configure watchpoints from `--watch`
4. Set execution limits (`--cycles`, `--frames`)
5. Pass debugger to EmulationThread

**Code Changes:**
```zig
// main.zig (after loading ROM)

// Create Debugger wrapper
var debugger = RAMBO.Debugger.Debugger.init(allocator, &config);
defer debugger.deinit();

// Configure breakpoints from CLI
if (debug_flags.break_at) |addresses| {
    for (addresses) |addr| {
        try debugger.addBreakpoint(.{
            .address = addr,
            .type = .execute,
        });
        if (debug_flags.verbose) {
            std.debug.print("[Debug] Breakpoint set at ${x:0>4}\n", .{addr});
        }
    }
}

// Configure watchpoints from CLI
if (debug_flags.watch) |addresses| {
    for (addresses) |addr| {
        try debugger.addWatchpoint(.{
            .address = addr,
            .type = .access,
        });
        if (debug_flags.verbose) {
            std.debug.print("[Debug] Watchpoint set at ${x:0>4}\n", .{addr});
        }
    }
}

// Open trace file if requested
var trace_file: ?std.fs.File = null;
if (debug_flags.trace) {
    if (debug_flags.trace_file) |path| {
        trace_file = try std.fs.cwd().createFile(path, .{});
        std.debug.print("[Debug] Tracing to file: {s}\n", .{path});
    } else {
        std.debug.print("[Debug] Tracing to stdout\n", .{});
    }
}
defer if (trace_file) |f| f.close();
```

**Debugger State Sharing:**
- Store debugger pointer in EmulationThread context
- EmulationThread checks debugger state before tick()
- Debugger callbacks write to trace file

**Deliverable:** Debugger configured from CLI flags, ready for use

---

### Phase 3: Execution Tracing (2-3 hours)

**Objective:** Add debug callbacks to trace execution

**Tasks:**
1. Implement trace callback (onBeforeInstruction)
2. Format trace output (PC, registers, disassembly)
3. Write to file or stdout
4. Handle breakpoints (pause execution)

**Trace Callback Implementation:**
```zig
// Debug callback context
const TraceContext = struct {
    trace_file: ?std.fs.File,
    cycle_count: u64 = 0,
    verbose: bool,

    pub fn onBeforeInstruction(ctx: *anyopaque, state: *const EmulationState) bool {
        const self: *TraceContext = @alignCast(@ptrCast(ctx));

        // Format trace line
        var buf: [256]u8 = undefined;
        const line = std.fmt.bufPrint(&buf,
            "[Cycle {d:8}] PC=${x:0>4}  A=${x:0>2}  X=${x:0>2}  Y=${x:0>2}  SP=${x:0>2}  P=${x:0>2}  Scanline={d}  Dot={d}\n",
            .{
                self.cycle_count,
                state.cpu.pc,
                state.cpu.a,
                state.cpu.x,
                state.cpu.y,
                state.cpu.sp,
                state.cpu.p.toByte(),
                state.clock.scanline(),
                state.clock.dot(),
            }
        ) catch return false;

        // Write to file or stdout
        if (self.trace_file) |f| {
            _ = f.write(line) catch {};
        } else if (self.verbose) {
            std.debug.print("{s}", .{line});
        }

        self.cycle_count += 1;
        return false; // Don't break
    }
};

// In main.zig, register callback
var trace_ctx = TraceContext{
    .trace_file = trace_file,
    .verbose = debug_flags.verbose,
};

try debugger.registerCallback(.{
    .onBeforeInstruction = TraceContext.onBeforeInstruction,
    .userdata = &trace_ctx,
});
```

**Trace Output Format:**
```
[Cycle        0] PC=$8004  A=$00  X=$00  Y=$00  SP=$FD  P=$24  Scanline=0  Dot=0
[Cycle        2] PC=$8005  A=$00  X=$00  Y=$00  SP=$FD  P=$24  Scanline=0  Dot=6
[Cycle        4] PC=$8006  A=$00  X=$00  Y=$00  SP=$FD  P=$24  Scanline=0  Dot=12
[Cycle        6] PC=$8008  A=$10  X=$00  Y=$00  SP=$FD  P=$04  Scanline=0  Dot=18
```

**Deliverable:** Execution tracing works, output to file/stdout

---

### Phase 4: Breakpoint Handling (1-2 hours)

**Objective:** Pause execution at breakpoints, inspect state

**Tasks:**
1. Check breakpoint in EmulationThread tick loop
2. Pause execution when breakpoint hit
3. Print state to console
4. Allow manual continuation (keyboard input)

**EmulationThread Integration:**
```zig
// In EmulationThread.timerCallback()
pub fn timerCallback(userdata: ?*anyopaque, loop: *xev.Loop, c: *xev.Completion, result: xev.Timer.RunError!void) xev.CallbackAction {
    _ = loop;
    _ = result catch unreachable;
    const ctx: *Context = @ptrCast(@alignCast(userdata.?));

    // Check if debugger wants to break
    if (ctx.debugger) |debugger| {
        if (debugger.shouldBreak(ctx.state)) {
            std.debug.print("\n[BREAKPOINT HIT]\n", .{});
            printState(ctx.state, debugger);

            // Pause execution (wait for user input)
            debugger.mode = .paused;

            // TODO: Add keyboard input handling to continue
            // For now, just pause
            return .disarm;
        }
    }

    const cycles = ctx.state.emulateFrame();
    _ = cycles;

    // Re-arm timer
    c.* = xev.Timer.init() catch unreachable;
    ctx.timer.run(loop, c, FRAME_INTERVAL_NS, Context, ctx, timerCallback);
    return .disarm;
}
```

**State Printing:**
```zig
fn printState(state: *const EmulationState, debugger: *Debugger) void {
    std.debug.print("  PC=${x:0>4}  A=${x:0>2}  X=${x:0>2}  Y=${x:0>2}  SP=${x:0>2}\n", .{
        state.cpu.pc, state.cpu.a, state.cpu.x, state.cpu.y, state.cpu.sp
    });
    std.debug.print("  P=${x:0>2} [{}{}I{}{}{}{}{}]\n", .{
        state.cpu.p.toByte(),
        if (state.cpu.p.negative) 'N' else '-',
        if (state.cpu.p.overflow) 'V' else '-',
        if (state.cpu.p.interrupt) 'I' else '-',
        if (state.cpu.p.decimal) 'D' else '-',
        if (state.cpu.p.zero) 'Z' else '-',
        if (state.cpu.p.carry) 'C' else '-',
    });
    std.debug.print("  PPUCTRL=${x:0>2}  PPUMASK=${x:0>2}  Scanline={d}  Dot={d}\n", .{
        state.ppu.ctrl.toByte(), state.ppu.mask.toByte(),
        state.clock.scanline(), state.clock.dot()
    });
    std.debug.print("  Frame={d}  Cycles={d}\n", .{state.clock.frame(), state.clock.cpuCycles()});
}
```

**Deliverable:** Execution pauses at breakpoints, state displayed

---

### Phase 5: Cycle/Frame Limits (1 hour)

**Objective:** Stop execution after N cycles or frames

**Tasks:**
1. Check cycle/frame count in EmulationThread
2. Stop execution when limit reached
3. Print final state if `--inspect` flag set

**Implementation:**
```zig
// In EmulationThread.timerCallback()
pub fn timerCallback(...) xev.CallbackAction {
    // ... existing code ...

    // Check cycle limit
    if (ctx.cycle_limit) |limit| {
        if (ctx.state.clock.cpuCycles() >= limit) {
            std.debug.print("\n[CYCLE LIMIT REACHED: {d}]\n", .{limit});
            if (ctx.inspect_on_exit) {
                printState(ctx.state, ctx.debugger);
            }
            ctx.running.store(false, .release);
            return .disarm;
        }
    }

    // Check frame limit
    if (ctx.frame_limit) |limit| {
        if (ctx.state.clock.frame() >= limit) {
            std.debug.print("\n[FRAME LIMIT REACHED: {d}]\n", .{limit});
            if (ctx.inspect_on_exit) {
                printState(ctx.state, ctx.debugger);
            }
            ctx.running.store(false, .release);
            return .disarm;
        }
    }

    // ... rest of callback ...
}
```

**Deliverable:** Execution stops at cycle/frame limits

---

## Usage Examples

### Example 1: Basic Tracing
```bash
# Run Mario for 30000 cycles with execution trace
./zig-out/bin/RAMBO mario.nes --cycles 30000 --trace --trace-file mario_init.txt

# Output:
[Debug] Tracing to file: mario_init.txt
[Debug] Execution will stop after 30000 CPU cycles
[Main] Loading ROM: mario.nes
... (Vulkan window opens) ...
[CYCLE LIMIT REACHED: 30000]

# Check trace file:
head mario_init.txt
[Cycle        0] PC=$8004  A=$00  X=$00  Y=$00  SP=$FD  P=$24  Scanline=0  Dot=0
[Cycle        2] PC=$8005  A=$00  X=$00  Y=$00  SP=$FD  P=$24  Scanline=0  Dot=6
...
```

### Example 2: Breakpoint Investigation
```bash
# Run with breakpoint at PPUCTRL write location
./zig-out/bin/RAMBO mario.nes --break-at 0x8008 --inspect --verbose

# Output:
[Debug] Breakpoint set at $8008
[Main] Loading ROM: mario.nes
... (execution runs) ...
[BREAKPOINT HIT]
  PC=$8008  A=$10  X=$00  Y=$00  SP=$FD
  P=$04 [--I---Z-]
  PPUCTRL=$00  PPUMASK=$00  Scanline=0  Dot=18
  Frame=0  Cycles=6
```

### Example 3: Memory Watchpoints
```bash
# Watch PPUCTRL and PPUMASK for writes
./zig-out/bin/RAMBO mario.nes --frames 3 --watch 0x2000,0x2001 --verbose

# Output:
[Debug] Watchpoint set at $2000
[Debug] Watchpoint set at $2001
[Debug] Execution will stop after 3 frames
[Main] Loading ROM: mario.nes
[WATCHPOINT HIT] Write to $2000: $10
  PC=$8008  ...
... (continues) ...
[FRAME LIMIT REACHED: 3]
```

---

## Testing Strategy

### Phase 1-2: Basic Integration
```bash
# Test CLI parsing
./zig-out/bin/RAMBO --help
./zig-out/bin/RAMBO mario.nes --trace --cycles 1000

# Test debugger setup
./zig-out/bin/RAMBO mario.nes --break-at 0x8000 --verbose
```

### Phase 3-4: Execution Tracing
```bash
# Trace first 30000 cycles
./zig-out/bin/RAMBO mario.nes --cycles 30000 --trace --trace-file mario_trace.txt

# Verify trace file
wc -l mario_trace.txt  # Should be ~30000 lines
grep "STA \$2000" mario_trace.txt  # Find PPUCTRL writes
grep "PC=\$" mario_trace.txt | head -20  # Check format
```

### Phase 5: Limits and Inspection
```bash
# Run for 3 frames and inspect
./zig-out/bin/RAMBO mario.nes --frames 3 --inspect

# Run for 50000 cycles and inspect
./zig-out/bin/RAMBO mario.nes --cycles 50000 --inspect
```

---

## Success Criteria

### Implementation Complete
- [ ] zli CLI parsing works
- [ ] Debug flags extracted correctly
- [ ] Debugger wraps EmulationState
- [ ] Breakpoints set from CLI
- [ ] Watchpoints set from CLI
- [ ] Execution tracing works
- [ ] Trace output to file/stdout
- [ ] Breakpoints pause execution
- [ ] State inspection on break
- [ ] Cycle/frame limits work
- [ ] No regressions in normal mode (no debug flags)

### Investigation Success
- [ ] Generate trace of Mario initialization
- [ ] Identify why PPUMASK stays $00
- [ ] Find where NMI should execute
- [ ] Understand divergence from correct behavior
- [ ] Fix root cause
- [ ] Mario displays title screen
- [ ] All tests still pass

---

## Timeline

**Phase 1:** 2-3 hours (CLI parsing)
**Phase 2:** 2-3 hours (Debugger integration)
**Phase 3:** 2-3 hours (Execution tracing)
**Phase 4:** 1-2 hours (Breakpoints)
**Phase 5:** 1 hour (Limits)

**Total:** 8-12 hours implementation
**Investigation:** 2-4 hours debugging
**Grand Total:** 10-16 hours to resolution

---

## Next Steps

1. **Begin Phase 1** - Add zli CLI parsing to main.zig
2. **Test incrementally** - Verify each phase works
3. **Generate traces** - Investigate Mario initialization
4. **Fix and verify** - Resolve root cause

---

**Status:** ✅ **PLAN COMPLETE - READY FOR IMPLEMENTATION**
**Advantage:** Real-time visual feedback + debug traces
**Next:** Begin Phase 1 - zli integration
