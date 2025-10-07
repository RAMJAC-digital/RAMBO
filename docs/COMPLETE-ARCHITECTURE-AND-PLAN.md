# Complete Architecture & Development Plan
## Cycle-Accurate NES Emulator with Wayland/Vulkan Display

**Created:** 2025-10-06 (Final Authoritative Version)
**Status:** 🟢 **READY FOR IMPLEMENTATION - All Questions Resolved**

---

## Document Purpose

This is the **single authoritative document** for Wayland/Vulkan implementation. All architectural decisions, library usage, data structures, and development phases are defined here with **zero outstanding questions**.

---

## Library Usage - DEFINITIVE

### libxev (Event Loop Library)

**Purpose:** Event-driven async I/O, timers, and non-blocking operations

**What We Use:**
- ✅ `xev.Loop`: One per thread for event-driven operation
- ✅ `xev.Timer`: Frame pacing in emulation thread
- ✅ `xev.File`: Future - Async file I/O (ROM loading, save states)
- ✅ `xev.TCP/UDP`: Future - Network features (netplay)
- ⬜ `xev.ThreadPool`: NOT USED (we spawn threads directly with std.Thread)

**What We DON'T Use:**
- ❌ libxev does NOT provide mutexes/synchronization
- ❌ libxev does NOT provide thread spawning (use std.Thread)
- ❌ libxev does NOT provide atomic operations (use std.atomic)

### std.Thread (Zig Standard Library)

**Purpose:** Thread creation and synchronization primitives

**What We Use:**
- ✅ `std.Thread.spawn()`: Create threads (Main, Emulation, Render)
- ✅ `std.Thread.Mutex`: Protect mailbox shared state
- ✅ `std.atomic.Value(T)`: Lock-free flags and counters
- ✅ `std.Thread.sleep()`: Minimal sleeps to prevent busy-wait

**Example Usage:**
```zig
// Thread creation
const emu_thread = try std.Thread.spawn(.{}, emulationThreadFn, .{ state, mailboxes, &running });

// Mutex protection
pub const FrameMailbox = struct {
    mutex: std.Thread.Mutex = .{},  // ← std.Thread, NOT libxev

    pub fn postFrame(self: *FrameMailbox) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        // ... protected section ...
    }
};

// Atomic flag
has_new_frame: std.atomic.Value(bool) = .{ .raw = false },  // ← std.atomic
```

### zig-wayland (Wayland Protocol Bindings)

**Purpose:** Native Wayland compositor protocol

**What We Use:**
- ✅ Generated protocol bindings from XML (build.zig scanner)
- ✅ `wl_display`, `wl_registry`, `wl_compositor`
- ✅ `xdg_wm_base`, `xdg_surface`, `xdg_toplevel` (window management)
- ✅ `wl_seat`, `wl_keyboard`, `wl_pointer` (input)

### Vulkan (GPU Rendering API)

**Purpose:** Hardware-accelerated frame rendering

**What We Use:**
- ✅ Vulkan 1.0 core API
- ✅ Wayland surface extension
- ✅ FIFO present mode (vsync)
- ✅ Single texture upload per frame

---

## Thread Architecture - DEFINITIVE

### Three Threads (Fixed Count)

```
┌─────────────────────┐
│   Main Thread       │  std.Thread.spawn() ─┐
│   (Coordinator)     │                       │
│                     │                       │
│ - Spawns threads    │                       │
│ - Routes events     │                       ▼
│ - Processes         │              ┌─────────────────┐
│   mailboxes         │              │ Emulation Thread│
│ - Shutdown coord.   │              │  (RT-Safe)      │
└──────────┬──────────┘              │                 │
           │                         │ xev.Loop + Timer│
           │ std.Thread.spawn()      │ Speed control   │
           │                         │ Cycle-accurate  │
           ▼                         └─────────────────┘
┌─────────────────────┐
│  Render Thread      │
│ (Wayland + Vulkan)  │
│                     │
│ xev.Loop (Wayland fd)│
│ Vulkan present      │
│ Input handling      │
└─────────────────────┘
```

**Key Points:**
- ✅ Exactly 3 threads (not 2, not 4)
- ✅ Each thread has own `xev.Loop`
- ✅ Threads communicate ONLY via mailboxes
- ✅ Created with `std.Thread.spawn()`
- ✅ Joined on shutdown in main thread

---

## Mailbox Architecture - DEFINITIVE

### Complete Mailbox Catalog

| Mailbox Name | Direction | Data | Primitives | Purpose |
|--------------|-----------|------|------------|---------|
| **ControllerInputMailbox** ✅ | Main → Emu | Button states | `std.Thread.Mutex` | NES controller input |
| **EmulationCommandMailbox** 🆕 | Main → Emu | Commands (power, reset) | `std.Thread.Mutex` | Lifecycle control |
| **SpeedControlMailbox** 🆕 | Main → Emu | Speed config | `std.Thread.Mutex` + `std.atomic.Value(bool)` | Timing/speed updates |
| **FrameMailbox** ✅ ENHANCED | Emu → Render | RGBA pixels | `std.Thread.Mutex` + `std.atomic.Value(bool)` | Video frames |
| **EmulationStatusMailbox** 🆕 | Emu → Main | Status/stats | `std.Thread.Mutex` | FPS, errors |
| **XdgWindowEventMailbox** ✅ RENAMED | Render → Main | Window events | `std.Thread.Mutex` | Resize, close, focus |
| **XdgInputEventMailbox** 🆕 | Render → Main | Keyboard/mouse | `std.Thread.Mutex` | Raw input events |
| **RenderStatusMailbox** 🆕 | Render → Main | Render stats | `std.Thread.Mutex` | Display FPS, Vulkan errors |

**Total:** 8 mailboxes (2 existing, 1 renamed, 5 new)

### Synchronization Pattern (ALL Mailboxes)

```zig
pub const ExampleMailbox = struct {
    // Data fields
    data: SomeData,

    // ALWAYS use std.Thread.Mutex
    mutex: std.Thread.Mutex = .{},

    // OPTIONAL: Lock-free check with std.atomic
    has_update: std.atomic.Value(bool) = .{ .raw = false },

    // Thread-safe post (writer side)
    pub fn post(self: *ExampleMailbox, new_data: SomeData) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.data = new_data;
        self.has_update.store(true, .release);
    }

    // Lock-free check (reader side - fast path)
    pub fn hasUpdate(self: *const ExampleMailbox) bool {
        return self.has_update.load(.acquire);
    }

    // Thread-safe consume (reader side)
    pub fn poll(self: *ExampleMailbox) ?SomeData {
        if (!self.has_update.load(.acquire)) return null;

        self.mutex.lock();
        defer self.mutex.unlock();
        self.has_update.store(false, .release);
        return self.data;
    }
};
```

**Why This Pattern:**
- ✅ `std.Thread.Mutex` protects critical section
- ✅ `std.atomic.Value` allows lock-free check (fast path)
- ✅ No libxev primitives needed for mailboxes
- ✅ Works with libxev event loops (mailboxes are passive data structures)

---

## Per-Thread libxev Usage - DEFINITIVE

### Main Thread

```zig
pub fn main() !void {
    // NO xev.Loop in main thread (coordination only)

    // Spawn threads
    const emu_thread = try std.Thread.spawn(.{}, emulationThreadFn, .{ ... });
    const render_thread = try std.Thread.spawn(.{}, renderThreadFn, .{ ... });

    // Simple coordination loop
    while (running.load(.acquire)) {
        // Process mailboxes from render thread
        const window_events = mailboxes.xdg_window_event.swapAndGet();
        const input_events = mailboxes.xdg_input_event.swapAndGet();

        // Route events
        for (window_events) |event| { /* ... */ }
        for (input_events) |event| { /* ... */ }

        // Small sleep (not busy-wait)
        std.Thread.sleep(16_000_000); // 16ms
    }

    // Join threads
    emu_thread.join();
    render_thread.join();
}
```

### Emulation Thread

```zig
fn emulationThreadFn(state: *EmulationState, mailboxes: *Mailboxes, running: *std.atomic.Value(bool)) void {
    // Create libxev loop for timer-driven emulation
    var loop = xev.Loop.init(.{}) catch return;
    defer loop.deinit();

    // Speed controller (manages timing)
    var speed_controller = SpeedController.init(.{ .mode = .realtime, .timing = .ntsc });

    // Context for timer callback
    var ctx = EmulationContext{
        .state = state,
        .mailboxes = mailboxes,
        .running = running,
        .speed_controller = &speed_controller,
    };

    // Start timer
    var timer = xev.Timer.init() catch return;
    defer timer.deinit();

    var completion: xev.Completion = undefined;
    const duration_ms = speed_controller.getFrameDurationNs() / 1_000_000;
    timer.run(&loop, &completion, duration_ms, EmulationContext, &ctx, timerCallback);

    // Run loop until disarmed
    loop.run(.until_done) catch |err| {
        std.log.err("Emulation loop error: {}", .{err});
    };
}

fn timerCallback(
    userdata: ?*EmulationContext,
    loop: *xev.Loop,
    completion: *xev.Completion,
    result: xev.Timer.RunError!void,
) xev.CallbackAction {
    _ = result catch return .disarm;
    const ctx = userdata orelse return .disarm;

    if (!ctx.running.load(.acquire)) return .disarm;

    // Check for speed updates via SpeedControlMailbox
    if (ctx.mailboxes.speed_control.poll()) |config| {
        ctx.speed_controller.updateConfig(config);
    }

    // Check for lifecycle commands via EmulationCommandMailbox
    if (ctx.mailboxes.emulation_command.poll()) |cmd| {
        switch (cmd) {
            .reset => ctx.state.reset(),
            .pause => ctx.speed_controller.pause(),
            .resume => ctx.speed_controller.resume(),
            // ... handle other commands ...
        }
    }

    // Decide whether to emulate this frame
    const decision = ctx.speed_controller.shouldTick();
    switch (decision) {
        .proceed => {
            // Emulate one frame
            const write_buf = ctx.mailboxes.frame.getWriteBuffer();
            ctx.state.emulateFrameIntoBuffer(write_buf);
            ctx.mailboxes.frame.postFrame();
            ctx.speed_controller.frameDone();

            // Rearm timer for next frame
            const next_duration_ms = ctx.speed_controller.getFrameDurationNs() / 1_000_000;
            var next_timer = xev.Timer.init() catch return .disarm;
            next_timer.run(loop, completion, next_duration_ms, EmulationContext, ctx, timerCallback);
            return .rearm;
        },
        .wait, .wait_ns => {
            // Paused or waiting - rearm with delay
            const wait_ms = if (decision == .wait) 16 else decision.wait_ns / 1_000_000;
            var next_timer = xev.Timer.init() catch return .disarm;
            next_timer.run(loop, completion, wait_ms, EmulationContext, ctx, timerCallback);
            return .rearm;
        },
    }
}
```

### Render Thread

```zig
fn renderThreadFn(mailboxes: *Mailboxes, running: *std.atomic.Value(bool)) !void {
    // Initialize Wayland
    var wayland_state = try WaylandState.init(std.heap.c_allocator);
    defer wayland_state.deinit();

    // Initialize Vulkan
    var vulkan_state = try VulkanState.init(std.heap.c_allocator, &wayland_state);
    defer vulkan_state.deinit();

    // Create libxev loop for Wayland fd monitoring
    var loop = try xev.Loop.init(.{});
    defer loop.deinit();

    // Register Wayland display fd with libxev
    const wl_fd = wayland_state.display.getFd();
    var fd_completion: xev.Completion = undefined;
    var fd_context = FdContext{ .wayland = &wayland_state, .mailboxes = mailboxes };

    try loop.read(wl_fd, &read_buffer, &fd_completion, FdContext, &fd_context, waylandFdCallback);

    // Render loop
    while (!wayland_state.closed and running.load(.acquire)) {
        // 1. Run libxev loop (non-blocking - processes Wayland fd)
        try loop.run(.no_wait);

        // 2. Dispatch Wayland events
        _ = try wayland_state.display.dispatchPending();

        // 3. Check for new frame (lock-free)
        if (mailboxes.frame.hasNewFrame()) {
            const frame_data = mailboxes.frame.consumeFrame();
            try VulkanLogic.uploadTexture(&vulkan_state, frame_data.?);
            try VulkanLogic.present(&vulkan_state); // Vsync blocks here
        } else {
            // No new frame, small sleep
            std.Thread.sleep(1_000_000); // 1ms
        }

        // 4. Flush Wayland requests
        _ = try wayland_state.display.flush();
    }
}

fn waylandFdCallback(
    userdata: ?*FdContext,
    loop: *xev.Loop,
    completion: *xev.Completion,
    result: xev.ReadError!usize,
) xev.CallbackAction {
    _ = result catch return .disarm;
    const ctx = userdata orelse return .disarm;

    // Wayland fd is readable - dispatch events
    _ = ctx.wayland.display.dispatchPending() catch return .disarm;

    // Rearm for next event batch
    try loop.read(wl_fd, &read_buffer, completion, FdContext, ctx, waylandFdCallback);
    return .rearm;
}
```

---

## State Isolation - DEFINITIVE

### Emulation State (Completely Isolated)

```zig
// src/emulation/State.zig
pub const EmulationState = struct {
    cpu: CpuState,
    ppu: PpuState,
    bus: BusState,
    controller: ControllerState,
    dma: DmaState,

    // NO POINTERS to external state
    // NO knowledge of mailboxes
    // NO knowledge of Wayland/Vulkan
    // Pure emulation logic only

    pub fn emulateFrame(self: *EmulationState) u64 {
        // Cycle-accurate emulation
        // Returns total cycles executed
    }

    pub fn emulateFrameIntoBuffer(self: *EmulationState, buffer: []u32) u64 {
        // Emulate and write pixels directly to buffer
        // Used by emulation thread to write to FrameMailbox.write_buffer
    }
};
```

### Wayland State (Completely Isolated)

```zig
// src/video/WaylandState.zig
pub const WaylandState = struct {
    display: *wl.Display,
    registry: *wl.Registry,
    compositor: *wl.Compositor,
    xdg_wm_base: *xdg.WmBase,
    seat: *wl.Seat,

    surface: *wl.Surface,
    xdg_surface: *xdg.Surface,
    xdg_toplevel: *xdg.Toplevel,

    keyboard: ?*wl.Keyboard,
    pointer: ?*wl.Pointer,

    width: u32 = 800,
    height: u32 = 600,
    closed: bool = false,

    // NO POINTERS to EmulationState
    // NO knowledge of CPU/PPU
    // NO knowledge of mailboxes (callbacks post to them via context)
    // Pure Wayland protocol state only
};
```

### Vulkan State (Completely Isolated)

```zig
// src/video/VulkanState.zig
pub const VulkanState = struct {
    instance: vk.Instance,
    physical_device: vk.PhysicalDevice,
    device: vk.Device,
    surface: vk.SurfaceKHR,
    swapchain: vk.SwapchainKHR,
    render_pass: vk.RenderPass,
    pipeline: vk.Pipeline,
    texture: vk.Image,
    texture_view: vk.ImageView,

    // NO POINTERS to EmulationState
    // NO POINTERS to WaylandState (initialized from it, then independent)
    // NO knowledge of mailboxes
    // Pure Vulkan rendering state only
};
```

---

## Development Plan - DEFINITIVE

### Phase 0: Mailbox Implementation & Testing (8-12 hours)

**Goal:** Complete mailbox architecture with comprehensive testing

**Deliverables:**
1. 5 new mailboxes implemented (all using `std.Thread.Mutex` + `std.atomic`)
2. 1 mailbox renamed (WaylandEventMailbox → XdgWindowEventMailbox)
3. 1 mailbox enhanced (FrameMailbox gets lock-free `hasNewFrame()`)
4. Unit tests for each mailbox
5. Multi-threaded stress tests (1000+ iterations, verify no races/deadlocks)
6. Integration tests for event flows

**Files:**
```
src/mailboxes/
├── EmulationCommandMailbox.zig (NEW)
├── SpeedControlMailbox.zig (NEW)
├── XdgInputEventMailbox.zig (NEW)
├── EmulationStatusMailbox.zig (NEW)
├── RenderStatusMailbox.zig (NEW)
├── XdgWindowEventMailbox.zig (RENAMED from WaylandEventMailbox.zig)
├── FrameMailbox.zig (ENHANCED with has_new_frame flag)
├── ControllerInputMailbox.zig (EXISTS - no changes)
└── Mailboxes.zig (UPDATED to include all 8 mailboxes)

tests/mailboxes/
├── command_mailbox_test.zig
├── speed_control_test.zig
├── input_event_test.zig
├── status_mailbox_test.zig
├── frame_lockfree_test.zig
└── multithread_stress_test.zig
```

**Success Criteria:**
- ✅ All 8 mailboxes use `std.Thread.Mutex`
- ✅ Lock-free flags use `std.atomic.Value`
- ✅ NO libxev primitives in mailboxes
- ✅ All unit tests pass
- ✅ Stress test passes 1000+ iterations
- ✅ All 571 existing tests still pass

---

### Phase 1: Speed Controller (6-8 hours)

**Goal:** Implement comprehensive emulation speed control

**Deliverables:**
1. SpeedController module with all timing modes
2. Integration with emulation thread timer callback
3. Integration with existing Debugger step modes
4. Comprehensive testing

**Files:**
```
src/emulation/
└── SpeedController.zig (NEW - 400-500 lines)

tests/emulation/
└── speed_controller_test.zig (NEW)
```

**Success Criteria:**
- ✅ All speed modes work (realtime, fast-forward, slow-mo, paused, stepping)
- ✅ Hard sync to wall time (no drift over 60 seconds)
- ✅ PAL/NTSC switching works
- ✅ Debugger stepping integrates correctly
- ✅ Can test emulation at various speeds without video

---

### Phase 2: Wayland Integration (8-10 hours)

**Goal:** Wayland window and XDG event system

**Deliverables:**
1. WaylandState/Logic modules (State/Logic separation pattern)
2. XDG protocol initialization and callbacks
3. libxev fd monitoring for Wayland socket
4. Event posting to mailboxes
5. Main thread event routing

**Files:**
```
src/video/
├── WaylandState.zig (NEW)
├── WaylandLogic.zig (NEW)
└── Video.zig (NEW - module re-exports)
```

**Success Criteria:**
- ✅ Wayland window opens at 800×600
- ✅ Window title: "RAMBO NES Emulator"
- ✅ Keyboard events post to XdgInputEventMailbox
- ✅ Window events post to XdgWindowEventMailbox
- ✅ Main thread routes events correctly
- ✅ libxev monitors Wayland fd (no busy-wait)
- ✅ Clean shutdown on window close

---

### Phase 3: Vulkan Renderer (10-12 hours)

**Goal:** Vulkan rendering backend

**Deliverables:**
1. VulkanState/Logic modules
2. Instance, device, swapchain with FIFO (vsync)
3. Fullscreen quad + texture sampling shader
4. Texture upload from FrameMailbox
5. Swapchain recreation on resize

**Files:**
```
src/video/
├── VulkanState.zig (NEW)
├── VulkanLogic.zig (NEW)
└── shaders/
    ├── fullscreen.vert (NEW - GLSL)
    ├── fullscreen.vert.spv (NEW - compiled SPIR-V)
    ├── texture.frag (NEW - GLSL)
    └── texture.frag.spv (NEW - compiled SPIR-V)
```

**Success Criteria:**
- ✅ Vulkan instance and device created
- ✅ Swapchain with FIFO present mode (vsync)
- ✅ Texture upload from FrameMailbox works
- ✅ Fullscreen quad renders correctly
- ✅ Window resize recreates swapchain
- ✅ No crashes, no validation errors

---

### Phase 4: Render Thread Integration (4-6 hours)

**Goal:** Complete three-thread integration

**Deliverables:**
1. Render thread function implementation
2. Thread spawning in main.zig
3. libxev loop in render thread (Wayland fd)
4. Frame consumption and Vulkan present
5. End-to-end testing with AccuracyCoin

**Files:**
```
src/main.zig (UPDATED - spawn render thread)
```

**Success Criteria:**
- ✅ Three threads running (Main, Emulation, Render)
- ✅ AccuracyCoin displays correctly
- ✅ Controller input works
- ✅ Speed control works (can fast-forward, pause, step)
- ✅ Window events handled
- ✅ Emulation independent of render performance
- ✅ Clean shutdown (all threads join)

---

### Phase 5: Polish & Production (4-6 hours)

**Goal:** Production-ready user experience

**Deliverables:**
1. Hotkey system
2. Status overlay (terminal or on-screen)
3. Aspect ratio correction (8:7 pixel aspect)
4. Integer scaling option

**Success Criteria:**
- ✅ Hotkeys work (Tab=fast-forward, Space=pause, R=reset, etc.)
- ✅ Status information displays
- ✅ Aspect ratio correct
- ✅ Production-ready UX

---

## Timeline Summary

| Phase | Hours | Description |
|-------|-------|-------------|
| **Phase 0** | 8-12 | Mailboxes (std.Thread.Mutex + std.atomic) |
| **Phase 1** | 6-8 | SpeedController |
| **Phase 2** | 8-10 | Wayland (libxev fd monitoring) |
| **Phase 3** | 10-12 | Vulkan renderer |
| **Phase 4** | 4-6 | Three-thread integration |
| **Phase 5** | 4-6 | Polish |
| **TOTAL** | **40-54** | **5-7 days full-time** |

---

## Outstanding Questions: ZERO

All architectural questions have been resolved:

✅ **Q: Which threading primitives to use?**
A: `std.Thread.Mutex`, `std.Thread.spawn()`, `std.atomic.Value(T)`

✅ **Q: Does libxev provide synchronization?**
A: No. Use std.Thread primitives.

✅ **Q: How many threads?**
A: Exactly 3 (Main, Emulation, Render)

✅ **Q: What does each libxev.Loop do?**
A: Emulation = timer callbacks, Render = Wayland fd monitoring, Main = none

✅ **Q: How are mailboxes synchronized?**
A: `std.Thread.Mutex` for critical sections, `std.atomic.Value` for lock-free checks

✅ **Q: State isolation strategy?**
A: EmulationState, WaylandState, VulkanState are completely independent with no cross-references

✅ **Q: Who talks to XDG/Wayland?**
A: ONLY render thread. Main and emulation have zero XDG knowledge.

✅ **Q: How does emulation stay cycle-accurate?**
A: Timer-driven with SpeedController, independent of display performance

✅ **Q: How does speed control work?**
A: SpeedController in emulation thread, configured via SpeedControlMailbox

✅ **Q: What primitives does FrameMailbox use?**
A: `std.Thread.Mutex` + `std.atomic.Value(bool)` for has_new_frame

---

## Final Checklist

**Architecture:**
- ✅ All library usage documented
- ✅ All primitives specified (std.Thread.Mutex, std.atomic, libxev.Loop, libxev.Timer)
- ✅ Three-thread model defined
- ✅ State isolation strategy clear
- ✅ Zero outstanding questions

**Mailboxes:**
- ✅ 8 mailboxes catalogued with purposes
- ✅ All use std.Thread.Mutex (not libxev)
- ✅ Lock-free patterns use std.atomic
- ✅ Communication flows documented

**Development Plan:**
- ✅ 5 phases defined with deliverables
- ✅ 40-54 hour timeline
- ✅ Testing-first approach (Phase 0)
- ✅ Success criteria for each phase

**Documentation:**
- ✅ This document is authoritative
- ✅ All other plans reference this
- ✅ Code examples provided
- ✅ Library usage examples provided

---

**Status:** 🟢 **COMPLETE AND READY**
**Next Action:** Begin Phase 0.1 - Implement new mailboxes
