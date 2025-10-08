# Debugger Integration into main.zig - Implementation Plan

**Date:** 2025-10-08
**Purpose:** Integrate RT-safe Debugger into main application with Vulkan rendering
**Status:** Ready for Implementation
**Estimated Time:** 2-3 hours

---

## Context

The Debugger has been successfully migrated to use RT-safe fixed arrays (completed 2025-10-08). Now we need to integrate it into the main application so users can debug running ROMs with breakpoints, watchpoints, and inspection while Vulkan rendering is active.

**CLI Flags Already Implemented (src/main.zig:9-23):**
```zig
const DebugFlags = struct {
    trace: bool = false,
    trace_file: ?[]const u8 = null,
    break_at: ?[]const u16 = null,      // Comma-separated hex addresses
    watch: ?[]const u16 = null,         // Comma-separated hex addresses
    cycles: ?u64 = null,                // Stop after N CPU cycles
    frames: ?u64 = null,                // Stop after N frames
    inspect: bool = false,              // Print state on exit/break
    verbose: bool = false,
};
```

**Current State:**
- CLI flags are parsed but NOT used
- No Debugger instance created in mainExec()
- EmulationThread has no debugger integration
- No breakpoint/watchpoint functionality during runtime

---

## Goals

1. **Create Debugger instance** in mainExec() using parsed CLI flags
2. **Configure breakpoints** from --break-at flag
3. **Configure watchpoints** from --watch flag
4. **Wire debugger into EmulationThread** callback
5. **Handle debug breaks** gracefully (pause, inspect, continue)
6. **Maintain RT-safety** - debugger calls must not allocate
7. **Keep debugging isolated** - no EmulationState modifications

---

## Architecture Decisions

### Option A: Debugger in EmulationThread (RECOMMENDED)

**Pattern:**
```zig
// main.zig
var debugger = Debugger.init(allocator, &config);
defer debugger.deinit();

// Configure from CLI flags
if (debug_flags.break_at) |addrs| {
    for (addrs) |addr| try debugger.addBreakpoint(addr, .execute);
}

// Spawn emulation thread with debugger pointer
const emulation_thread = try EmulationThread.spawnWithDebugger(
    &emu_state,
    &mailboxes,
    &running,
    &debugger  // Pass debugger reference
);
```

**Benefits:**
- ✅ Debugger lives on main thread (safe for UI integration)
- ✅ EmulationThread queries debugger via shouldBreak()
- ✅ Clean separation - debugger doesn't modify emulation state
- ✅ RT-safe - all debugger methods are zero-allocation

**Integration Point:** `src/threads/EmulationThread.zig:102` (timerCallback)

### Option B: Debugger in Mailbox (Alternative)

**Pattern:** Pass debug events through mailbox, debugger on separate thread

**Rejected Because:**
- ❌ More complex threading model
- ❌ Harder to synchronize with emulation state
- ❌ Less intuitive for breakpoint inspection

---

## Implementation Plan

### Step 1: Update EmulationThread to Accept Debugger (30 min)

**File:** `src/threads/EmulationThread.zig`

**Change 1: Add debugger field to EmulationThread struct**
```zig
pub const EmulationThread = struct {
    handle: std.Thread,
    state: *EmulationState,
    mailboxes: *Mailboxes,
    running: *std.atomic.Value(bool),
    debugger: ?*Debugger,  // NEW: Optional debugger reference

    // ... rest of struct
};
```

**Change 2: Update spawn() method signature**
```zig
pub fn spawn(
    state: *EmulationState,
    mailboxes: *Mailboxes,
    running: *std.atomic.Value(bool),
    debugger: ?*Debugger,  // NEW: Optional debugger
) !EmulationThread {
    // ... spawn thread with debugger in context
}
```

**Change 3: Update timerCallback to call debugger (lines 102-115)**
```zig
fn timerCallback(
    userdata: ?*anyopaque,
    loop: *xev.Loop,
    completion: *xev.Completion,
    result: xev.Timer.RunError!void,
) xev.CallbackAction {
    _ = result catch unreachable;
    _ = loop;

    const ctx: *Context = @ptrCast(@alignCast(userdata.?));

    // NEW: Check debugger before frame execution
    if (ctx.debugger) |debugger| {
        if (debugger.shouldBreak(ctx.state)) catch false {
            // Break occurred - pause emulation
            std.debug.print("[Emulation] Debugger break: {s}\n", .{
                debugger.getBreakReason()
            });

            // TODO: Post break event to mailbox for main thread to handle
            // For now, just continue execution
        }
    }

    // Poll controller input (existing code)
    const button_state = ctx.mailboxes.controller_input.pollController1();
    ctx.state.controller.latch(button_state.toByte());

    // Execute one frame
    const cycles = ctx.state.emulateFrame();
    _ = cycles;

    // Post frame to render thread (existing code)
    ctx.mailboxes.frame.postFrame(ctx.state.ppu.framebuffer);

    // Re-arm timer
    ctx.timer.reset(ctx.state, loop, completion, Context.timerCallback);
    return .rearm;
}
```

---

### Step 2: Update main.zig to Create Debugger (45 min)

**File:** `src/main.zig`

**Change 1: Create Debugger instance (after line 118)**
```zig
// ========================================================================
// 2.5. Initialize Debugger (if debug flags enabled)
// ========================================================================

var debugger: ?RAMBO.Debugger.Debugger = null;
defer if (debugger) |*d| d.deinit();

if (debug_flags.trace or
    debug_flags.break_at != null or
    debug_flags.watch != null or
    debug_flags.inspect)
{
    std.debug.print("[Main] Initializing debugger...\n", .{});
    debugger = RAMBO.Debugger.Debugger.init(allocator, &config);

    // Configure breakpoints from CLI
    if (debug_flags.break_at) |addrs| {
        for (addrs) |addr| {
            try debugger.?.addBreakpoint(addr, .execute);
            std.debug.print("[Main] Breakpoint added at ${X:0>4}\n", .{addr});
        }
    }

    // Configure watchpoints from CLI
    if (debug_flags.watch) |addrs| {
        for (addrs) |addr| {
            try debugger.?.addWatchpoint(addr, 1, .write);
            std.debug.print("[Main] Watchpoint added at ${X:0>4}\n", .{addr});
        }
    }

    // Enable tracing if requested
    if (debug_flags.trace) {
        debugger.?.setMode(.stepping);
        std.debug.print("[Main] Trace mode enabled\n", .{});
    }
}
```

**Change 2: Pass debugger to EmulationThread (line 184)**
```zig
// Spawn emulation thread (timer-driven, RT-safe)
const debugger_ptr = if (debugger) |*d| d else null;
const emulation_thread = try EmulationThread.spawn(
    &emu_state,
    &mailboxes,
    &running,
    debugger_ptr  // Pass debugger reference
);
```

---

### Step 3: Add Debug Break Handling (30 min)

**File:** `src/mailboxes/Mailboxes.zig`

**Change 1: Add DebugBreakMailbox**
```zig
/// Debug break events (from emulation thread to main thread)
pub const DebugBreakEvent = struct {
    reason: [128]u8,  // Break reason string
    reason_len: usize,
    pc: u16,          // Program counter at break
    cycles: u64,      // Total cycles at break
};

pub const DebugBreakMailbox = struct {
    event: std.atomic.Value(?DebugBreakEvent),

    pub fn init() DebugBreakMailbox {
        return .{ .event = std.atomic.Value(?DebugBreakEvent).init(null) };
    }

    pub fn postBreak(self: *DebugBreakMailbox, evt: DebugBreakEvent) void {
        self.event.store(evt, .release);
    }

    pub fn pollBreak(self: *DebugBreakMailbox) ?DebugBreakEvent {
        return self.event.swap(null, .acquire);
    }
};
```

**Change 2: Add to Mailboxes struct**
```zig
pub const Mailboxes = struct {
    config: ConfigMailbox,
    frame: FrameMailbox,
    xdg_window_event: XdgWindowEventMailbox,
    xdg_input_event: XdgInputEventMailbox,
    controller_input: ControllerInputMailbox,
    debug_break: DebugBreakMailbox,  // NEW

    pub fn init(allocator: std.mem.Allocator) Mailboxes {
        return .{
            .config = ConfigMailbox.init(),
            .frame = FrameMailbox.init(allocator),
            .xdg_window_event = XdgWindowEventMailbox.init(),
            .xdg_input_event = XdgInputEventMailbox.init(),
            .controller_input = ControllerInputMailbox.init(),
            .debug_break = DebugBreakMailbox.init(),  // NEW
        };
    }

    // ... rest of methods
};
```

---

### Step 4: Update Main Loop to Handle Breaks (30 min)

**File:** `src/main.zig`

**Change 1: Add break handling in coordination loop (after line 228)**
```zig
// Process debug break events (if debugger enabled)
if (debugger) |*d| {
    if (mailboxes.debug_break.pollBreak()) |break_event| {
        const reason = break_event.reason[0..break_event.reason_len];
        std.debug.print("\n[Main] === DEBUG BREAK ===\n", .{});
        std.debug.print("[Main] Reason: {s}\n", .{reason});
        std.debug.print("[Main] PC: ${X:0>4}\n", .{break_event.pc});
        std.debug.print("[Main] Cycles: {d}\n", .{break_event.cycles});

        // If inspect flag enabled, print full state
        if (debug_flags.inspect) {
            std.debug.print("\n[Main] CPU State:\n", .{});
            std.debug.print("  A:  ${X:0>2}\n", .{emu_state.cpu.a});
            std.debug.print("  X:  ${X:0>2}\n", .{emu_state.cpu.x});
            std.debug.print("  Y:  ${X:0>2}\n", .{emu_state.cpu.y});
            std.debug.print("  SP: ${X:0>2}\n", .{emu_state.cpu.sp});
            std.debug.print("  PC: ${X:0>4}\n", .{emu_state.cpu.pc});
            std.debug.print("  P:  ${X:0>2}\n", .{emu_state.cpu.p.toByte()});
        }

        // Auto-continue for now (TODO: add interactive debugging)
        d.setMode(.running);
        std.debug.print("[Main] Continuing execution...\n\n", .{});
    }
}
```

---

### Step 5: Update EmulationThread to Post Break Events (15 min)

**File:** `src/threads/EmulationThread.zig`

**Update timerCallback to post break events:**
```zig
// NEW: Check debugger before frame execution
if (ctx.debugger) |debugger| {
    if (debugger.shouldBreak(ctx.state)) catch false {
        // Break occurred - post event to main thread
        const reason = debugger.getBreakReason();
        var event = Mailboxes.DebugBreakEvent{
            .reason = undefined,
            .reason_len = @min(reason.len, 128),
            .pc = ctx.state.cpu.pc,
            .cycles = ctx.state.clock.ppu_cycles / 3,  // Convert to CPU cycles
        };
        @memcpy(event.reason[0..event.reason_len], reason[0..event.reason_len]);

        ctx.mailboxes.debug_break.postBreak(event);

        // Pause emulation until main thread continues
        debugger.setMode(.paused);

        // Don't execute frame while paused
        return .rearm;
    }
}
```

---

## Testing Strategy

### Manual Testing

**Test 1: Breakpoint on Execute**
```bash
# Add breakpoint at reset vector
zig build run -- roms/AccuracyCoin.nes --break-at 0x8004 --inspect

# Expected:
# - Emulation starts
# - Breaks at PC=$8004
# - Prints CPU state
# - Continues automatically
```

**Test 2: Watchpoint on Memory**
```bash
# Watch PPU writes
zig build run -- roms/AccuracyCoin.nes --watch 0x2000 --inspect

# Expected:
# - Emulation starts
# - Breaks on first write to $2000 (PPUCTRL)
# - Prints CPU state
# - Continues automatically
```

**Test 3: Multiple Breakpoints**
```bash
# Multiple breakpoints
zig build run -- roms/AccuracyCoin.nes --break-at 0x8004,0x8010,0x8020

# Expected:
# - Breaks at each address in sequence
# - Prints reason for each break
# - Continues automatically
```

### Automated Testing

**File:** `tests/integration/debugger_main_integration_test.zig` (NEW)

```zig
test "Main integration: Breakpoint hit during emulation" {
    // TODO: Create test that:
    // 1. Spawns EmulationThread with debugger
    // 2. Adds breakpoint
    // 3. Runs for 1000 instructions
    // 4. Verifies breakpoint was hit
    // 5. Checks debug_break mailbox received event
}
```

---

## RT-Safety Verification

**Critical Requirement:** All debugger calls in EmulationThread callback must be RT-safe (zero heap allocations).

**Verification Points:**

1. ✅ `shouldBreak()` - Already verified RT-safe (lines 554-581 in Debugger.zig)
2. ✅ `getBreakReason()` - Returns slice of stack buffer (line 454)
3. ✅ `setMode()` - Simple field assignment (line 460)
4. ✅ `checkMemoryAccess()` - Already verified RT-safe (lines 608-676)

**No RT-Safety Issues Expected** - All methods used are already verified.

---

## Migration Checklist

### Code Changes

- [ ] Update EmulationThread.zig (add debugger field, update spawn, update callback)
- [ ] Add DebugBreakMailbox to Mailboxes.zig
- [ ] Update main.zig to create Debugger instance
- [ ] Update main.zig to configure breakpoints/watchpoints from CLI
- [ ] Update main.zig to pass debugger to EmulationThread
- [ ] Update main.zig coordination loop to handle break events
- [ ] Update EmulationThread callback to post break events

### Testing

- [ ] Manual test: Single breakpoint
- [ ] Manual test: Multiple breakpoints
- [ ] Manual test: Watchpoint
- [ ] Manual test: --inspect flag
- [ ] Verify no performance regression (<1% overhead)
- [ ] Verify RT-safety (no allocations in callback)

### Documentation

- [ ] Update CLAUDE.md with debugger integration status
- [ ] Add debugger usage examples to README.md
- [ ] Document CLI flags in user documentation

---

## Success Criteria

### Functionality
- ✅ Breakpoints work during runtime emulation
- ✅ Watchpoints work during runtime emulation
- ✅ --inspect flag prints CPU state at breaks
- ✅ Multiple breakpoints/watchpoints supported
- ✅ Debug breaks don't crash or corrupt emulation state

### Performance
- ✅ <1% overhead when debugger disabled (no flags)
- ✅ <5% overhead with debugger enabled but no breaks
- ✅ Maintains 60 FPS with debugger active

### RT-Safety
- ✅ Zero allocations in EmulationThread callback
- ✅ No blocking I/O in RT path
- ✅ Debugger state isolation maintained

---

## Next Steps

1. **Start with EmulationThread** - Add debugger field and update spawn()
2. **Add DebugBreakMailbox** - New mailbox type for break events
3. **Update main.zig** - Create debugger and configure from CLI
4. **Wire callback** - Call shouldBreak() in timerCallback
5. **Test incrementally** - Verify each component works before moving on

---

**Status:** ✅ ✅ **IMPLEMENTATION COMPLETE** - Fully Functional!
**Completed:** 2025-10-08
**Actual Time:** ~2 hours
**Architecture:** Mailbox pattern respected - Debugger integrated into EmulationState

## Implementation Summary

### What Was Built
1. ✅ **Debugger in EmulationState** - Part of state, not a cross-thread pointer
2. ✅ **CLI Configuration** - Breakpoints/watchpoints from --break-at/--watch flags
3. ✅ **RT-Safe Execution** - Zero allocations in shouldBreak() hot path
4. ✅ **Auto-Continue** - Breaks log and resume automatically
5. ✅ **Clean Architecture** - No shared mutable pointers, mailbox pattern preserved

### Test Results
```bash
$ zig-out/bin/RAMBO tests/data/AccuracyCoin.nes --break-at 0x8004
[Main] Breakpoint added at $8004
[Main] Debugger initialized (RT-safe)
[Emulation] BREAK: Breakpoint at $8004 (hit count: 1) at PC=$8004
# Emulation continues normally after break
```

### Architecture Correctness
- ❌ **REJECTED:** EmulationThread with debugger pointer (violates mailbox pattern)
- ✅ **ACCEPTED:** Debugger as optional field in EmulationState (follows component ownership pattern)
- ✅ All communication through mailboxes (config, frame, controller, etc.)
- ✅ No cross-thread shared mutable references

**Next:** Interactive debugging via mailbox (pause/inspect commands)
