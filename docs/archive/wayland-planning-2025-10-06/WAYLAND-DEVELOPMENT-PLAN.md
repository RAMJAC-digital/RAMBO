# Wayland Development Plan - Phase 8 Video Subsystem

**Created:** 2025-10-06
**Status:** 🟡 **Planning - Awaiting User Approval**
**Estimated Time:** 24-32 hours (revised from original 20-28)

---

## Executive Summary

This plan addresses **critical architectural conflicts** discovered during research and proposes a comprehensive Wayland + Vulkan implementation following **zzt-backup proven patterns** and **defensive programming principles**.

### Key Decisions

1. **✅ 2-Thread Model** (Main render loop + RT emulation) - NOT 3 threads
2. **✅ Event-Driven Architecture** - libxev monitors Wayland fd, NOT timers
3. **✅ Natural Vsync** - From Vulkan swapchain present, NOT artificial sleep
4. **✅ Mailbox Pattern** - Already implemented correctly (FrameMailbox, WaylandEventMailbox)
5. **✅ State Isolation** - Wayland state completely separate from EmulationState
6. **⚠️ REQUIRES REFACTORING** - Current timer-based emulation must change

---

## CRITICAL ISSUES IDENTIFIED

### Issue 1: Conflicting Architecture Documentation

**Problem:** Multiple architecture documents contradict each other:

- `docs/architecture/video-system.md` (2025-10-04) proposes **3-thread model**
- `docs/archive/video-architecture-review.md` (archived) critiques this as **WRONG**
- Current `src/main.zig` implements **2 threads** with timer-based emulation

**Analysis:**
- The architecture review is a **code review of a previous plan**
- It identifies 3-thread model and timer-based vsync as **incorrect**
- The review recommends zzt-backup's 2-thread, event-driven pattern
- Current main.zig partially follows this but uses timers (wrong approach)

**Resolution Needed:**
- ✅ Confirm we use **2-thread model** (main render + RT emulation)
- ⚠️ Refactor away from timer-based emulation
- ⚠️ Archive conflicting video-system.md document

### Issue 2: Timer-Based vs Event-Driven Architecture

**Current Implementation** (`src/main.zig:123-181`):
```zig
fn emulationTimerCallback(...) xev.CallbackAction {
    // Emulate one frame every 16.6ms via libxev timer
    const cycles = ctx.state.emulateFrame();
    ctx.mailboxes.frame.swapBuffers();

    // Rearm timer for next frame
    timer.run(loop, completion, frame_duration_ms, ...);
    return .rearm;
}
```

**Why This Is Wrong** (from architecture review):
- Artificial vsync (sleep-based timing)
- Main thread idle (100ms sleep in coordination loop)
- Video thread would fight emulation timer for frame pacing
- Not following zzt-backup pattern

**Correct Pattern** (from zzt-backup):
```zig
// Main render loop (NO TIMERS)
while (!window.closed) {
    // 1. Poll Wayland events (non-blocking)
    window.pollEvents();

    // 2. Check for new frame from emulation
    if (mailboxes.frame.drain()) |frame_data| {
        renderer.uploadTexture(frame_data);
        renderer.present(); // Natural vsync here
    } else {
        std.Thread.sleep(1_000_000); // 1ms to prevent busy-wait
    }
}

// Emulation thread (FREE-RUNNING, NO TIMERS)
while (running.load(.acquire)) {
    // Emulate one frame as fast as possible
    const fb = mailboxes.frame.getWriteBuffer();
    state.emulateFrame(fb);
    mailboxes.frame.postFrame();

    // Natural pacing from mailbox backpressure
    // If main render thread is slow, this blocks on mutex
}
```

**Resolution Needed:**
- ⚠️ Remove libxev timer from emulation thread
- ⚠️ Make emulation free-running (paced by mailbox backpressure)
- ⚠️ Main thread becomes active render loop (not coordinator)
- ⚠️ Natural vsync from Vulkan present (60 Hz monitor locks speed)

### Issue 3: libxev Usage Confusion

**Current Usage:**
- libxev used for **timers** (emulation frame pacing)
- Main thread runs libxev loop with `no_wait` and sleeps 100ms

**Correct Usage** (from architecture review and zzt-backup):
- libxev for **Wayland fd monitoring** (event-driven dispatch)
- libxev for **async I/O** (future: ROM loading, save states)
- libxev for **thread pool** (future: background tasks)
- **NOT** for display timing (that comes from vsync)

**Resolution Needed:**
- ⚠️ Use libxev to monitor Wayland display fd
- ⚠️ Wayland events trigger through libxev callbacks
- ⚠️ Remove frame timing from libxev (handled by vsync)

### Issue 4: Thread Model Ambiguity

**Question:** Should main thread be:
- **Option A:** Idle coordinator (current implementation)
- **Option B:** Active render loop (zzt-backup pattern)

**Architecture Review Recommendation:**
> "Main thread becomes main render loop. RT thread only for emulation. Remove dedicated render thread."

**zzt-backup Pattern:**
- Main thread runs Wayland event loop + rendering
- Emulation thread is separate, RT-safe, free-running
- NO third thread needed

**Resolution Needed:**
- ⚠️ Confirm main thread should be active render loop
- ⚠️ Refactor main.zig to match this pattern

### Issue 5: Wayland State Isolation

**Current Implementation:**
- `WaylandEventMailbox` exists and is correct
- No `src/video/` directory exists yet
- Wayland state would need its own struct

**Required:**
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

    width: u32 = 800,
    height: u600,
    closed: bool = false,
    configured: bool = false,

    // NO emulation state references
    // NO frame data storage
    // Pure Wayland protocol state only
};
```

**Resolution Needed:**
- ✅ Create isolated WaylandState struct
- ✅ Use defensive programming (all side effects explicit)
- ✅ State/Logic separation pattern (like CPU/PPU/Bus)

---

## Architecture Decision Record

### Decision 1: 2-Thread Model (CONFIRMED)

**Rationale:**
- ✅ Matches zzt-backup production pattern
- ✅ Main thread utilized (not idle)
- ✅ Simpler coordination (fewer race conditions)
- ✅ Natural vsync timing from monitor refresh
- ✅ Current main.zig already has 2 threads

**Thread Responsibilities:**

**Main Thread (Render Loop):**
- Initialize Wayland connection
- Initialize Vulkan renderer
- Spawn emulation thread
- **Active loop:**
  1. Poll Wayland events via libxev fd monitoring
  2. Process events from WaylandEventMailbox
  3. Check FrameMailbox for new frames
  4. Upload texture and present (vsync here)
- Coordinate shutdown

**Emulation Thread (RT-Safe):**
- Free-running frame emulation
- Write to FrameMailbox write buffer
- Post frame when complete
- Natural pacing from mailbox backpressure
- No timers, no sleeps (except mailbox mutex)

### Decision 2: Event-Driven Wayland Integration

**libxev Usage:**
```zig
// Main thread: Monitor Wayland fd for events
fn waylandFdCallback(
    userdata: ?*WaylandContext,
    loop: *xev.Loop,
    completion: *xev.Completion,
    result: xev.ReadError!usize,
) xev.CallbackAction {
    const ctx = userdata.?;

    // Dispatch pending Wayland events
    _ = ctx.display.dispatchPending() catch |err| {
        std.log.err("Wayland dispatch error: {}", .{err});
        return .disarm;
    };

    // Rearm for next batch of events
    return .rearm;
}

// In main loop initialization
const wl_fd = display.getFd();
var fd_completion: xev.Completion = undefined;
try loop.read(wl_fd, &read_buffer, &fd_completion, WaylandContext, &ctx, waylandFdCallback);
```

**Benefits:**
- ✅ Non-blocking Wayland event handling
- ✅ No busy-waiting on event poll
- ✅ Integrates cleanly with render loop
- ✅ Follows libxev's intended use case (file I/O)

### Decision 3: Natural Vsync from Vulkan

**Swapchain Configuration:**
```zig
const swapchain_info = vk.SwapchainCreateInfo{
    .present_mode = .fifo, // Vsync enabled (blocks until vblank)
    // This provides natural 60 Hz pacing
};
```

**Timing Flow:**
1. Emulation thread runs free (as fast as possible)
2. Emulation posts frames to FrameMailbox
3. Main thread drains mailbox and uploads texture
4. `vkQueuePresentKHR()` **blocks until monitor vblank** (natural vsync)
5. This creates backpressure on emulation thread via mailbox mutex
6. Result: Perfect 60 FPS with no artificial timers

**Benefits:**
- ✅ No timer drift
- ✅ Perfect frame pacing
- ✅ No tearing
- ✅ Lower latency than timer-based approach

### Decision 4: State/Logic Separation for Video

**Following existing pattern:**
```
src/video/
├── WaylandState.zig      # Pure Wayland protocol state
├── WaylandLogic.zig      # Pure functions for Wayland operations
├── VulkanState.zig       # Pure Vulkan state (instance, device, swapchain)
├── VulkanLogic.zig       # Pure rendering functions
└── Video.zig             # Module re-exports
```

**Benefits:**
- ✅ Consistent with CPU/PPU/Bus architecture
- ✅ Easy to test (pure functions)
- ✅ Easy to serialize (for debugging)
- ✅ Explicit side effects

---

## Required Refactoring

### Refactor 1: Remove Timer-Based Emulation

**Current Code** (`src/main.zig:183-220`):
```zig
fn emulationThreadFn(...) void {
    var loop = xev.Loop.init(.{}) catch return;
    defer loop.deinit();

    var ctx = EmulationContext{ ... };

    // START TIMER (THIS IS WRONG)
    var timer = xev.Timer{};
    var completion: xev.Completion = undefined;
    timer.run(&loop, &completion, frame_duration_ms, EmulationContext, &ctx, emulationTimerCallback);

    try loop.run(.until_done);
}
```

**Refactored Code:**
```zig
fn emulationThreadFn(
    state: *EmulationState,
    mailboxes: *Mailboxes,
    running: *std.atomic.Value(bool),
) void {
    std.log.info("[Emulation] Thread started (free-running)", .{});

    // No libxev loop needed in emulation thread
    // No timers needed

    var frame_count: u64 = 0;
    var last_report = std.time.nanoTimestamp();

    while (running.load(.acquire)) {
        // Get write buffer (may block if main thread hasn't consumed previous frame)
        const write_buf = mailboxes.frame.getWriteBuffer();

        // Emulate one frame (cycle-accurate)
        const cycles = state.emulateFrame();

        // Post frame (swaps buffers, releases main thread)
        mailboxes.frame.postFrame();

        // Progress reporting
        frame_count += 1;
        const now = std.time.nanoTimestamp();
        if (now - last_report >= 1_000_000_000) {
            const elapsed = @as(f64, @floatFromInt(now - last_report)) / 1_000_000_000.0;
            const fps = @as(f64, @floatFromInt(frame_count)) / elapsed;
            std.log.info("[Emulation] FPS: {d:.2}", .{fps});
            frame_count = 0;
            last_report = now;
        }
    }

    std.log.info("[Emulation] Thread stopped", .{});
}
```

**Why This Works:**
- Emulation runs as fast as possible
- `mailboxes.frame.postFrame()` blocks on mutex if main thread is slow
- Main thread's vsync creates natural backpressure
- Result: Emulation automatically paces to monitor refresh rate

### Refactor 2: Transform Main Thread to Render Loop

**Current Code** (`src/main.zig:62-84`):
```zig
// Main Coordination Loop (THIS IS WRONG - THREAD IS IDLE)
while (...) {
    const config_update = mailboxes.config.pollUpdate();
    // ... process config ...

    try loop.run(.no_wait);
    std.Thread.sleep(100_000_000); // 100ms sleep - thread is idle!
}
```

**Refactored Code:**
```zig
// Main Render Loop (THIS IS CORRECT - THREAD IS ACTIVE)
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize mailboxes
    var mailboxes = try Mailboxes.init(allocator);
    defer mailboxes.deinit();

    // Initialize emulation state
    var config = Config.init(allocator);
    defer config.deinit();
    var emu_state = EmulationState.init(&config);

    // Initialize Wayland
    var wayland_state = try WaylandState.init(allocator);
    defer wayland_state.deinit();

    // Initialize Vulkan renderer
    var vulkan_state = try VulkanState.init(allocator, &wayland_state);
    defer vulkan_state.deinit();

    // Initialize libxev loop for Wayland fd monitoring
    var loop = try xev.Loop.init(.{});
    defer loop.deinit();

    // Register Wayland fd with libxev
    const wl_fd = wayland_state.display.getFd();
    // TODO: Setup fd monitoring callback

    // Spawn emulation thread
    var running = std.atomic.Value(bool).init(true);
    const emu_thread = try std.Thread.spawn(.{}, emulationThreadFn, .{
        &emu_state, &mailboxes, &running
    });
    defer emu_thread.join();

    // MAIN RENDER LOOP (ACTIVE, NOT IDLE)
    std.log.info("[Main] Entering render loop", .{});

    while (!wayland_state.closed and running.load(.acquire)) {
        // 1. Run libxev loop (processes Wayland fd events non-blocking)
        try loop.run(.no_wait);

        // 2. Dispatch Wayland protocol events
        _ = try wayland_state.display.dispatchPending();

        // 3. Process events from WaylandEventMailbox
        const events = mailboxes.wayland.swapAndGetPendingEvents();
        for (events) |event| {
            switch (event) {
                .window_close => {
                    std.log.info("[Main] Window close requested", .{});
                    running.store(false, .release);
                },
                .window_resize => |r| {
                    std.log.info("[Main] Resize: {}x{}", .{r.width, r.height});
                    try VulkanLogic.recreateSwapchain(&vulkan_state, r.width, r.height);
                },
                .key_press => |k| {
                    // Future: Update controller input
                    _ = k;
                },
                else => {},
            }
        }

        // 4. Check for new frame from emulation
        if (mailboxes.frame.drain()) |frame_data| {
            // Upload texture to GPU
            try VulkanLogic.uploadTexture(&vulkan_state, frame_data);

            // Render and present (vsync blocks here)
            try VulkanLogic.render(&vulkan_state);
        } else {
            // No new frame, small sleep to prevent busy-wait
            std.Thread.sleep(1_000_000); // 1ms
        }

        // 5. Flush Wayland requests
        _ = try wayland_state.display.flush();
    }

    std.log.info("[Main] Shutting down...", .{});
    running.store(false, .release);
}
```

**Why This Works:**
- Main thread is **actively rendering**, not idle
- Wayland events processed via libxev
- Frame consumption from mailbox
- Vsync happens in render call (natural pacing)
- No artificial sleeps except when no frame available

### Refactor 3: FrameMailbox API Adjustment

**Current API** (`src/mailboxes/FrameMailbox.zig`):
```zig
pub fn swapBuffers(self: *FrameMailbox) void {
    self.mutex.lock();
    defer self.mutex.unlock();
    const tmp = self.write_buffer;
    self.write_buffer = self.read_buffer;
    self.read_buffer = tmp;
    self.frame_count += 1;
}
```

**Issue:** No atomic flag for "new frame available"

**Enhanced API:**
```zig
pub const FrameMailbox = struct {
    write_buffer: *FrameBuffer,
    read_buffer: *FrameBuffer,
    mutex: std.Thread.Mutex = .{},
    has_new_frame: std.atomic.Value(bool) = .{ .raw = false },
    allocator: std.mem.Allocator,
    frame_count: u64 = 0,

    /// Emulation thread: Get buffer to write to (always available)
    pub fn getWriteBuffer(self: *FrameMailbox) []u32 {
        return self.write_buffer.pixels[0..];
    }

    /// Emulation thread: Post completed frame (swaps buffers)
    pub fn postFrame(self: *FrameMailbox) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        std.mem.swap(*FrameBuffer, &self.write_buffer, &self.read_buffer);
        self.has_new_frame.store(true, .release);
        self.frame_count += 1;
    }

    /// Main thread: Check if new frame is available (lock-free)
    pub fn hasNewFrame(self: *const FrameMailbox) bool {
        return self.has_new_frame.load(.acquire);
    }

    /// Main thread: Drain new frame if available (returns slice)
    pub fn drain(self: *FrameMailbox) ?[]const u32 {
        if (!self.has_new_frame.load(.acquire)) return null;

        self.mutex.lock();
        defer self.mutex.unlock();
        self.has_new_frame.store(false, .release);

        return self.read_buffer.pixels[0..];
    }
};
```

**Why This Is Better:**
- Lock-free check for new frame (atomic flag)
- Main thread can poll without blocking
- Matches zzt-backup pattern exactly

---

## Implementation Phases

### Phase 8.0: Refactoring (6-8 hours) - NEW PHASE

**Critical:** Must complete before Wayland implementation

**Tasks:**

1. **Refactor FrameMailbox** (1-2 hours)
   - Add `has_new_frame` atomic flag
   - Implement `hasNewFrame()` and `drain()` methods
   - Update tests
   - **Files:** `src/mailboxes/FrameMailbox.zig`

2. **Refactor Emulation Thread** (2-3 hours)
   - Remove libxev loop and timer
   - Implement free-running frame loop
   - Natural pacing from mailbox backpressure
   - **Files:** `src/main.zig`

3. **Refactor Main Thread** (2-3 hours)
   - Transform from idle coordinator to active render loop
   - Add placeholder render logic (will be Vulkan in 8.2)
   - Setup libxev for future Wayland fd monitoring
   - **Files:** `src/main.zig`

4. **Testing** (1 hour)
   - Verify frame pacing without video output
   - Confirm FPS stability
   - Test mailbox backpressure behavior

**Deliverable:** Refactored architecture ready for Wayland integration

### Phase 8.1: Wayland State & Window (8-10 hours)

**Tasks:**

1. **Create Wayland State Module** (3-4 hours)
   ```
   src/video/
   ├── WaylandState.zig     # Pure Wayland state
   ├── WaylandLogic.zig     # Wayland operations
   └── Video.zig            # Module re-exports
   ```

2. **Implement Wayland Connection** (2-3 hours)
   - Connect to display
   - Bind registry globals (compositor, xdg_wm_base, seat)
   - Create surface and XDG toplevel
   - Setup protocol event listeners

3. **Implement Event Callbacks** (2-3 hours)
   - XDG surface configure
   - XDG toplevel close/resize
   - Keyboard key events
   - Post events to WaylandEventMailbox

4. **Integrate with libxev** (1 hour)
   - Monitor Wayland fd
   - Dispatch events in main loop

**Deliverable:** Wayland window opens, responds to events, posts to mailbox

### Phase 8.2: Vulkan Renderer (10-12 hours)

**Tasks:**

1. **Create Vulkan State Module** (4-5 hours)
   ```
   src/video/
   ├── VulkanState.zig      # Vulkan instance, device, swapchain
   ├── VulkanLogic.zig      # Rendering operations
   └── shaders/
       ├── fullscreen.vert.spv
       └── texture.frag.spv
   ```

2. **Implement Vulkan Initialization** (3-4 hours)
   - Create instance with Wayland surface extension
   - Select physical device
   - Create logical device and queues
   - Create swapchain with FIFO present mode (vsync)

3. **Implement Rendering Pipeline** (2-3 hours)
   - Create render pass
   - Compile shaders (fullscreen quad + texture sample)
   - Create graphics pipeline
   - Setup command buffers

4. **Implement Frame Upload** (1 hour)
   - Create staging buffer
   - Upload texture data (256×240 RGBA)
   - Transition image layouts

**Deliverable:** Vulkan renders uploaded frames to window with vsync

### Phase 8.3: Integration & Testing (4-6 hours)

**Tasks:**

1. **Connect PPU Output** (2 hours)
   - PPU writes to FrameMailbox
   - Verify frame data format (RGBA u32)

2. **Full Pipeline Test** (2 hours)
   - Test with AccuracyCoin.nes
   - Verify background rendering
   - Verify sprite rendering
   - Measure FPS (should be locked to 60)

3. **Edge Case Testing** (2 hours)
   - Window resize behavior
   - Minimization handling
   - Focus loss handling
   - Rapid resize coalescing

**Deliverable:** Full emulator visual output on screen

### Phase 8.4: Polish (2-4 hours)

**Tasks:**

1. **Aspect Ratio Correction** (1-2 hours)
   - NES 8:7 pixel aspect calculation
   - Letterboxing for non-matching window sizes
   - Integer scaling option

2. **FPS Counter** (1 hour)
   - Terminal output or simple overlay
   - Frame time statistics

3. **Graceful Shutdown** (1 hour)
   - Cleanup Vulkan resources
   - Close Wayland connection
   - Join threads properly

**Deliverable:** Production-ready video output

---

## Questions & Issues for User Review

### Critical Questions

**Q1:** Confirm 2-thread architecture (Main render + Emulation)?
- **Proposed:** Main thread active render loop, emulation thread free-running
- **Alternative:** Keep 3-thread model from video-system.md

**Q2:** Confirm timer-based emulation should be removed?
- **Proposed:** Free-running emulation with mailbox backpressure
- **Current:** libxev timer fires every 16.6ms

**Q3:** Should we archive conflicting documentation?
- **Proposed:** Move `docs/architecture/video-system.md` to `docs/archive/`
- **Reason:** Contradicts architecture review recommendations

**Q4:** Vulkan vs OpenGL?
- **Proposed:** Vulkan (modern, explicit control)
- **Alternative:** OpenGL (simpler but legacy)
- **Note:** Architecture review critiques OpenGL approach

**Q5:** Wayland-only or fallback to X11?
- **Proposed:** Wayland-only (CLAUDE.md line 32: "System: Linux with Wayland compositor")
- **Alternative:** Add X11 fallback via XWayland

### Implementation Questions

**Q6:** Shader compilation strategy?
- **Option A:** Pre-compiled SPIR-V checked into repo
- **Option B:** Runtime compilation with glslc
- **Option C:** Compile-time embedding via `@embedFile`

**Q7:** Vulkan validation layers in debug builds?
- **Proposed:** Enable in Debug, disable in ReleaseFast
- **Tradeoff:** Performance vs error checking

**Q8:** Frame buffer allocation strategy?
- **Current:** FrameMailbox allocates two 245KB buffers
- **Question:** Should PPU write directly to mailbox buffer to avoid copy?
- **Tradeoff:** Coupling vs performance

**Q9:** Controller input mapping?
- **Wayland keyboard events** → **NES controller buttons**
- **Question:** Hardcoded mapping or configurable?
- **Note:** ControllerInputMailbox already exists

**Q10:** Error handling strategy for Vulkan?
- **Vulkan functions return VkResult** (many error codes)
- **Question:** Panic on errors or graceful degradation?
- **Example:** Swapchain out-of-date (window resize) vs device loss

### Refactoring Questions

**Q11:** Should FrameTimer.zig be deleted?
- **Current:** `src/timing/FrameTimer.zig` (195 lines)
- **Reason:** Timer-based vsync no longer needed
- **Question:** Delete or keep for future use?

**Q12:** Should EmulationState store frame buffer?
- **Current:** PPU renders to internal buffer, copy to mailbox
- **Alternative:** PPU renders directly to mailbox write buffer
- **Tradeoff:** Cleaner separation vs one extra memcpy per frame

**Q13:** Video module organization?
- **Proposed:** `src/video/{WaylandState,WaylandLogic,VulkanState,VulkanLogic}.zig`
- **Alternative:** `src/video/{Wayland.zig,Vulkan.zig}` (State/Logic in same file)
- **Question:** Follow strict State/Logic separation or colocate?

---

## Dependencies & Requirements

### System Requirements

**Already Confirmed:**
- ✅ Linux with Wayland compositor (GNOME, KDE, Sway, etc.)
- ✅ Vulkan 1.0+ compatible GPU
- ✅ Zig 0.15.1

**To Verify:**
- Wayland protocol XMLs at `/usr/share/wayland/wayland.xml`
- XDG shell protocol at `/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml`
- Vulkan SDK installed (or just runtime libraries needed?)

### Build Dependencies

**Already Configured:**
- ✅ libxev (commit 34fa508, in build.zig.zon)
- ✅ zig-wayland (v0.5.0-dev, commit 1b5c038, in build.zig.zon)
- ✅ Wayland scanner configured in build.zig (lines 74-115)

**To Add:**
- ⬜ Vulkan headers (via build.zig linkSystemLibrary?)
- ⬜ glslc for shader compilation (or pre-compile shaders?)

### Existing Infrastructure

**Mailboxes (✅ Already Implemented):**
- `FrameMailbox` - Double-buffer frame passing (needs minor API enhancement)
- `WaylandEventMailbox` - Wayland events (complete)
- `ConfigMailbox` - Configuration updates (complete)
- `ControllerInputMailbox` - Controller input (complete)

**State Modules (✅ Already Implemented):**
- `EmulationState` - Flattened emulation state
- `CpuState`, `PpuState`, `BusState` - Component states
- Pattern established, video state will follow same structure

---

## Risk Assessment

### High Risk Items

1. **Vulkan Complexity**
   - **Risk:** Vulkan has steep learning curve (300+ functions)
   - **Mitigation:** Focus on minimal viable renderer (no advanced features)
   - **Fallback:** OpenGL backend if Vulkan proves too complex

2. **Wayland Protocol Correctness**
   - **Risk:** Incorrect protocol sequencing causes crashes
   - **Mitigation:** Follow zig-wayland examples closely
   - **Testing:** Test on multiple compositors (GNOME, KDE, Sway)

3. **Thread Synchronization Bugs**
   - **Risk:** Mailbox deadlocks or race conditions
   - **Mitigation:** Follow zzt-backup pattern exactly
   - **Testing:** Run with ThreadSanitizer in debug builds

### Medium Risk Items

4. **Frame Pacing Issues**
   - **Risk:** Stuttering or tearing despite vsync
   - **Mitigation:** Profiling and careful swapchain configuration
   - **Note:** Natural vsync should handle this automatically

5. **Swapchain Recreation Edge Cases**
   - **Risk:** Crashes on rapid window resize
   - **Mitigation:** Event coalescing (process only last resize)
   - **Pattern:** From zzt-backup processVulkanMailboxAndRender

### Low Risk Items

6. **Keyboard Input Mapping**
   - **Risk:** Key repeat behavior or incorrect mapping
   - **Mitigation:** Simple state-based input handling

7. **Aspect Ratio Calculation**
   - **Risk:** Incorrect letterboxing or stretching
   - **Mitigation:** Well-tested math (NES 8:7 pixel aspect)

---

## Success Criteria

### Phase 8.0: Refactoring
- ✅ Main thread is active render loop (not idle coordinator)
- ✅ Emulation thread is free-running (no timers)
- ✅ FrameMailbox has lock-free drain() API
- ✅ All existing tests still pass

### Phase 8.1: Wayland
- ✅ Wayland window opens at 800×600
- ✅ Window title shows "RAMBO NES Emulator"
- ✅ Keyboard events posted to WaylandEventMailbox
- ✅ Window close triggers clean shutdown
- ✅ Resize events posted to mailbox

### Phase 8.2: Vulkan
- ✅ Vulkan instance and device initialized
- ✅ Swapchain created with FIFO present mode
- ✅ Fullscreen quad renders texture
- ✅ Texture upload from FrameMailbox works
- ✅ Vsync locks rendering to 60 FPS

### Phase 8.3: Integration
- ✅ AccuracyCoin.nes displays correctly
- ✅ Background tiles render properly
- ✅ Sprites render with correct priority
- ✅ Sprite 0 hit visible
- ✅ No tearing or stuttering
- ✅ FPS locked to 60.0 Hz

### Phase 8.4: Polish
- ✅ Aspect ratio maintained with letterboxing
- ✅ Window resize works smoothly (coalesced events)
- ✅ FPS counter displays in terminal
- ✅ Graceful shutdown (no crashes or leaks)

---

## Next Steps

### Before Development Begins

1. **User Review:** Read this plan and answer critical questions Q1-Q13
2. **Architecture Confirmation:** Approve 2-thread, event-driven model
3. **Documentation:** Archive conflicting documents
4. **Dependency Check:** Verify Vulkan SDK availability on target system

### Implementation Order

1. **Phase 8.0:** Refactoring (must complete first)
2. **Phase 8.1:** Wayland window and events
3. **Phase 8.2:** Vulkan renderer
4. **Phase 8.3:** Integration and testing
5. **Phase 8.4:** Polish and production readiness

---

## References

### Internal Documentation
- `docs/archive/video-architecture-review.md` - Critical architectural review
- `docs/architecture/video-system.md` - Original plan (conflicts with review)
- `src/main.zig` - Current implementation (needs refactoring)
- `src/mailboxes/` - Mailbox pattern implementation (correct)

### External References
- **zzt-backup:** Reference implementation for Wayland + Vulkan patterns
- **zig-wayland:** https://codeberg.org/ifreund/zig-wayland
- **libxev:** https://github.com/mitchellh/libxev
- **Wayland Protocol:** https://wayland.freedesktop.org/docs/html/
- **Vulkan Tutorial:** https://vulkan-tutorial.com/

### Related RAMBO Documentation
- `CLAUDE.md` - Development guide and architecture patterns
- `docs/architecture/threading.md` - Mailbox pattern documentation
- `docs/README.md` - Project status and navigation

---

**Status:** 🟡 **Awaiting User Approval**
**Created:** 2025-10-06
**Next:** User answers critical questions Q1-Q13
