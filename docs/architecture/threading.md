# Thread Architecture - Phase 6 Implementation

**Status:** ✅ Phase 6 Complete (Current 2-Thread Implementation)
**Implementation:** `src/main.zig`, `src/mailboxes/`
**Pattern:** 2-thread model with mailbox communication

---

> **⚠️ PHASE 6 DOCUMENTATION - CURRENT IMPLEMENTATION ONLY**
>
> This document describes the **Phase 6 (current) 2-thread implementation**.
>
> For the **Phase 8 (target) 3-thread architecture** (Main + Emulation + Render), see:
> - **[`../COMPLETE-ARCHITECTURE-AND-PLAN.md`](../COMPLETE-ARCHITECTURE-AND-PLAN.md)** ← Authoritative Phase 8 plan
> - **[`../MAILBOX-ARCHITECTURE.md`](../MAILBOX-ARCHITECTURE.md)** ← Complete mailbox specifications

---

## Overview (Phase 6 - Current Implementation)

RAMBO's **Phase 6 implementation** uses a **2-thread architecture** with **mailbox-based communication**:

1. **Main Thread** - Coordinator only (minimal work)
2. **Emulation Thread** - RT-safe emulation with timer-driven pacing

This design ensures:
- ✅ RT-safe emulation (zero heap allocations in hot path)
- ✅ Deterministic execution (no race conditions)
- ✅ Clean thread coordination (no shared mutable state)
- ✅ Foundation for Phase 8 (3-thread Wayland integration)

---

## Thread Model

### Main Thread (Coordinator)

**Responsibilities:**
- Initialize resources (allocators, mailboxes, state)
- Spawn worker threads (emulation, future Wayland)
- Run libxev event loop (coordination only)
- Handle shutdown coordination

**Code:** `src/main.zig:10-112`

```zig
pub fn main() !void {
    // 1. Initialize mailboxes (dependency injection)
    var mailboxes = try RAMBO.Mailboxes.Mailboxes.init(allocator);

    // 2. Initialize emulation state
    var emu_state = RAMBO.EmulationState.EmulationState.init(&config, bus_state);

    // 3. Spawn emulation thread
    const emulation_thread = try std.Thread.spawn(.{}, emulationThreadFn, .{
        &emu_state, &mailboxes, &running
    });

    // 4. Coordination loop (minimal work)
    while (running.load(.acquire)) {
        const config_update = mailboxes.config.pollUpdate();
        try loop.run(.no_wait);
        std.Thread.sleep(100_000_000); // 100ms - just coordinating
    }

    // 5. Shutdown
    running.store(false, .release);
    emulation_thread.join();
}
```

**Key Points:**
- Main thread does **minimal work** (just coordination)
- No emulation logic runs on main thread
- Small sleep (100ms) avoids busy-waiting
- Uses libxev for future event-driven patterns

### Emulation Thread (RT-Safe)

**Responsibilities:**
- Run cycle-accurate emulation (CPU + PPU + Bus)
- Timer-driven frame pacing (60 Hz NTSC target)
- Post completed frames to FrameMailbox
- Poll for configuration updates

**Code:** `src/main.zig:190-233`

```zig
fn emulationThreadFn(
    state: *RAMBO.EmulationState.EmulationState,
    mailboxes: *RAMBO.Mailboxes.Mailboxes,
    running: *std.atomic.Value(bool),
) void {
    // Own libxev loop for timer-driven ticking
    var loop = xev.Loop.init(.{}) catch return;
    var timer = xev.Timer.init() catch return;

    // Timer callback every ~16.6ms (60 Hz NTSC)
    timer.run(&loop, &completion, frame_duration_ms, ...);

    // Run until shutdown signal
    loop.run(.until_done) catch |err| {
        std.debug.print("[Emulation] Loop error: {}\n", .{err});
    };
}
```

**Timer Callback** (`src/main.zig:126-184`):
```zig
fn emulationTimerCallback(...) xev.CallbackAction {
    // 1. Check shutdown signal
    if (!ctx.running.load(.acquire)) return .disarm;

    // 2. Poll config updates (non-blocking)
    if (ctx.mailboxes.config.pollUpdate()) |update| {
        // Apply config (speed, pause, reset)
    }

    // 3. Emulate one frame (cycle-accurate)
    const cycles = ctx.state.emulateFrame();
    ctx.total_cycles += cycles;

    // 4. Post completed frame (double-buffer swap)
    ctx.mailboxes.frame.swapBuffers();

    // 5. Rearm timer for next frame
    timer.run(loop, completion, frame_duration_ms, ...);
    return .rearm;
}
```

**RT-Safety:**
- Zero heap allocations in hot path
- All state pre-allocated at startup
- Deterministic execution (no syscalls except timer)
- Frame pacing via libxev timer (non-blocking)

---

## Mailbox Communication

### Pattern: Double-Buffered + Atomic Updates

**Implementation:** `src/mailboxes/Mailboxes.zig`

```zig
pub const Mailboxes = struct {
    wayland: WaylandEventMailbox,  // Future: Wayland → Main
    frame: FrameMailbox,            // Emulation → Video (future)
    config: ConfigMailbox,          // Main → Emulation
};
```

### 1. FrameMailbox (Double-Buffered)

**Purpose:** Pass completed PPU frames from emulation thread to video thread

**Implementation:** `src/mailboxes/FrameMailbox.zig`

```zig
pub const FrameMailbox = struct {
    write_buffer: *FrameBuffer,  // Emulation writes here
    read_buffer: *FrameBuffer,   // Video reads from here
    mutex: std.Thread.Mutex,
    frame_count: std.atomic.Value(u64),
};

pub fn swapBuffers(self: *FrameMailbox) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    // Atomic pointer swap (lock-protected)
    const tmp = self.write_buffer;
    self.write_buffer = self.read_buffer;
    self.read_buffer = tmp;

    self.frame_count.fetchAdd(1, .release);
}
```

**Properties:**
- **Buffer Size:** 256×240×4 bytes = 245,760 bytes per buffer
- **Total Memory:** 480 KB (2 buffers)
- **Format:** RGBA u32 pixels
- **Synchronization:** Mutex-protected swap

**Usage:**
```zig
// Emulation thread (every ~16ms)
ctx.mailboxes.frame.swapBuffers();  // Atomic swap

// Video thread (future)
const frame_data = mailboxes.frame.getReadBuffer();  // Lock-free read
```

### 2. ConfigMailbox (Single-Value Atomic)

**Purpose:** Send configuration updates from main thread to emulation thread

**Implementation:** `src/mailboxes/ConfigMailbox.zig`

```zig
pub const ConfigMailbox = struct {
    value: std.atomic.Value(?ConfigUpdate),

    pub fn postUpdate(self: *ConfigMailbox, update: ConfigUpdate) void {
        self.value.store(update, .release);
    }

    pub fn pollUpdate(self: *ConfigMailbox) ?ConfigUpdate {
        return self.value.swap(null, .acquire);  // Atomic read-and-clear
    }
};
```

**Properties:**
- **Lock-Free:** Atomic swap for updates
- **Non-Blocking:** Poll returns immediately
- **Single-Value:** Only latest update matters (no queue needed)

**Supported Updates:**
- Speed multiplier changes
- Pause/resume emulation
- Reset signal
- Future: savestate trigger, debug commands

### 3. WaylandEventMailbox (Double-Buffered Queue)

**Purpose:** Pass Wayland window events from Wayland thread to main thread

**Implementation:** `src/mailboxes/WaylandEventMailbox.zig`

**Status:** ✅ Scaffolding complete, awaiting Phase 8 video subsystem

```zig
pub const WaylandEventMailbox = struct {
    write_queue: EventQueue,
    read_queue: EventQueue,
    mutex: std.Thread.Mutex,
    // Double-buffered event queue pattern
};
```

**Event Types (Planned):**
- Window close request
- Keyboard input
- Window resize
- Focus change

---

## Timer-Driven Emulation

### Frame Pacing Strategy

**Goal:** Maintain 60.0988 Hz NTSC frame rate (16,639,267 ns per frame)

**Implementation:**

```zig
// NTSC frame duration
const frame_duration_ns: u64 = 16_639_267;  // 60.0988 Hz
const frame_duration_ms: u64 = 16;          // Truncated to 16ms (libxev limitation)

// Timer fires every 16ms
timer.run(&loop, &completion, frame_duration_ms, EmulationContext, &ctx, callback);
```

**Measured Performance:**
- **Target FPS:** 60.10 (NTSC)
- **Actual FPS:** 62.97 average (4.8% over target)
- **Frame Timing:** 16ms intervals (libxev timer precision)
- **Total Frames:** 630 in 10.01 seconds
- **Deviation:** Acceptable before vsync (future Phase 8)

**Why 16ms vs 16.639ms?**
- libxev timer precision limited to milliseconds
- Truncation: 16.639ms → 16ms
- Results in slightly faster execution (62.97 vs 60.10 FPS)
- Will be corrected with vsync in Phase 8

### Cycle Accuracy vs Real-Time

**Cycle Accuracy:**
- PPU: 341 dots × 262 scanlines = 89,342 PPU cycles per frame
- CPU: ~29,780 CPU cycles per frame (89,342 ÷ 3)
- Emulation counts **exact cycles** per operation

**Real-Time Pacing:**
- Timer fires every 16ms (real-world time)
- Each timer tick = emulate one complete frame
- Disconnect between emulated cycles and real-world time

**Result:**
- **Functionally:** Cycle-accurate hardware emulation
- **Timing:** Slightly faster than real NTSC (4.8% over target)
- **Future Fix:** Vsync in Phase 8 will sync to monitor refresh rate

---

## Thread Coordination

### Startup Sequence

```
1. Main Thread: Initialize mailboxes
2. Main Thread: Initialize emulation state
3. Main Thread: Create libxev loop
4. Main Thread: Spawn emulation thread
   └─→ Emulation Thread: Start timer-driven loop
5. Main Thread: Enter coordination loop (100ms polling)
```

### Shutdown Sequence

```
1. Main Thread: Set running = false (atomic store)
2. Emulation Thread: Detect shutdown signal
3. Emulation Thread: Disarm timer
4. Emulation Thread: Exit loop
5. Main Thread: Join emulation thread
6. Main Thread: Cleanup resources
```

**Atomic Coordination:**
```zig
// Shared flag (atomic for thread-safety)
var running = std.atomic.Value(bool).init(true);

// Main thread signals shutdown
running.store(false, .release);

// Emulation thread checks (in timer callback)
if (!ctx.running.load(.acquire)) {
    return .disarm;  // Exit timer loop
}
```

---

## Memory Management

### Allocation Strategy

**Startup (Main Thread):**
- All memory allocated upfront during initialization
- Mailboxes allocated via GPA allocator
- Frame buffers: 480 KB (double-buffered)
- State structures: stack-allocated or arena

**Runtime (Emulation Thread):**
- **Zero heap allocations** in hot path
- All emulation state pre-allocated
- RT-safe execution (no allocator calls)

**Cleanup:**
- Main thread owns all allocations
- Proper `defer` cleanup on all resources
- Thread join before resource deallocation

---

## Future Expansion

### Phase 8: Wayland Video Thread (Planned)

> **📘 For complete Phase 8 architecture, see:**
> - **[`../COMPLETE-ARCHITECTURE-AND-PLAN.md`](../COMPLETE-ARCHITECTURE-AND-PLAN.md)** - Full 3-thread architecture with library primitives
> - **[`../MAILBOX-ARCHITECTURE.md`](../MAILBOX-ARCHITECTURE.md)** - All 8 mailboxes with synchronization specs

**Planned 3-Thread Model:**
1. **Main Thread** - Coordinator (NO libxev loop)
2. **Emulation Thread** - RT-safe emulation (own xev.Loop + xev.Timer)
3. **Render Thread** - Wayland + Vulkan (own xev.Loop monitoring Wayland fd)

**Key Architectural Changes from Phase 6:**
- Main thread simplifies to pure coordination (removes libxev loop)
- Render thread gets own libxev.Loop for Wayland fd monitoring
- 8 explicit mailboxes replace 3 (see MAILBOX-ARCHITECTURE.md)
- All using `std.Thread.Mutex` + `std.atomic.Value` (NOT libxev primitives)

---

## Performance Metrics

**Measured (Phase 6 Demo):**
- **Duration:** 10.01 seconds
- **Total Frames:** 630
- **Average FPS:** 62.97
- **Target FPS:** 60.10 (NTSC)
- **Deviation:** +4.8% (acceptable before vsync)

**CPU Usage:**
- Emulation thread: ~100% of one core (cycle-accurate emulation)
- Main thread: <1% (just coordinating)

**Memory:**
- Frame buffers: 480 KB (double-buffered)
- State structures: ~50 KB
- Total working set: <1 MB

---

## Design Rationale

### Why 2 Threads (Not 1 or 3)?

**1 Thread (Rejected):**
- ❌ Blocks on video I/O (window events, rendering)
- ❌ Non-deterministic emulation timing
- ❌ Cannot achieve RT-safe emulation

**2 Threads (Current):**
- ✅ RT-safe emulation (dedicated thread)
- ✅ Clean separation of concerns
- ✅ Future-proof (Wayland thread adds cleanly)
- ✅ Minimal coordination overhead

**3 Threads (Future Phase 8):**
- Wayland thread for video I/O
- Keeps emulation thread RT-safe
- Main thread remains coordinator only

### Why Mailboxes (Not Channels or Queues)?

**Mailbox Advantages:**
- ✅ Double-buffering avoids blocking (lock-free reads)
- ✅ Atomic swaps for instant updates
- ✅ No queue overhead (only latest frame matters)
- ✅ Simple mental model (producer/consumer)

**Alternatives Rejected:**
- ❌ Channels: Blocking semantics break RT-safety
- ❌ Lock-free queues: Complexity for no benefit
- ❌ Shared memory: Race condition hell

### Why Timer-Driven (Not Busy-Loop)?

**Timer Benefits:**
- ✅ OS-level scheduling (no busy-waiting)
- ✅ Power efficient (CPU sleeps between frames)
- ✅ Integrates with libxev event loop
- ✅ Easy vsync integration (future)

**Busy-Loop Rejected:**
- ❌ 100% CPU usage for no benefit
- ❌ Power inefficient
- ❌ No natural vsync integration

---

## References

**Implementation:**
- `src/main.zig` - Main thread and emulation thread
- `src/mailboxes/Mailboxes.zig` - Mailbox container
- `src/mailboxes/FrameMailbox.zig` - Double-buffered frame passing
- `src/mailboxes/ConfigMailbox.zig` - Atomic config updates
- `src/mailboxes/WaylandEventMailbox.zig` - Event queue (scaffolding)

**Related Docs:**
- `docs/README.md` - Project overview
- `docs/architecture/video-system.md` - Phase 8 video subsystem plan
- `CLAUDE.md` - Development guide

**Commits:**
- `cc6734f` - Phase 6: Thread architecture complete
- `65e0651` - Phase 7C: Sprite validation (verified thread stability)

---

**Last Updated:** 2025-10-04
**Status:** Production ready
**Next:** Phase 8 - Wayland video thread integration
