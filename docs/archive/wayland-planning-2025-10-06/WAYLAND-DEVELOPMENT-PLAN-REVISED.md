# Wayland Development Plan - REVISED
## Cycle-Accurate Emulation with Speed Control

**Created:** 2025-10-06 (Revision 2)
**Status:** 🟡 **Planning - Awaiting User Approval**
**Estimated Time:** 30-40 hours

---

## Critical Correction: Emulation Isolation

**Previous plan was WRONG:** Attempted to make emulation "free-running" paced by vsync backpressure.

**Correct architecture:** Emulation must be **completely isolated** with timer-driven cycle-accurate execution and independent speed control.

---

## Core Principles

### 1. Complete Emulation Isolation

The emulation thread must operate **independently** of rendering:
- ✅ Timer-driven frame pacing (libxev timers are CORRECT)
- ✅ Configurable speed (real-time, fast-forward, slow-mo, step)
- ✅ Hard sync to wall time when in real-time mode
- ✅ Force PAL/NTSC timing independently
- ✅ Zero dependency on render thread performance
- ✅ RT-safe (no heap allocations in hot path)

### 2. Three-Thread Minimum Architecture

**Thread 1: Main Thread (Coordinator)**
- Spawns and manages all threads
- Coordinates lifecycle (startup, shutdown)
- Processes high-level control commands
- Minimal work (mostly coordination)

**Thread 2: Emulation Thread (Isolated RT-Safe)**
- Own libxev loop for timer-driven ticking
- Cycle-accurate 6502 + PPU emulation
- Configurable speed control
- Posts frames to FrameMailbox
- **Completely independent** of render performance

**Thread 3: Render Thread (Wayland + Vulkan)**
- Own libxev loop for Wayland fd monitoring
- Drains FrameMailbox (lock-free check)
- Uploads textures and presents with vsync
- Posts events to WaylandEventMailbox
- **Completely independent** of emulation timing

**Potential Future Threads:**
- Audio Thread (APU synthesis)
- Network Thread (netplay)
- Debug Thread (remote debugging protocol)

### 3. Emulation Speed Control

The emulation must support from the onset:

**Real-Time Modes:**
- **NTSC Real-Time:** 60.0988 Hz (16,639,267 ns per frame)
- **PAL Real-Time:** 50.0070 Hz (19,997,200 ns per frame)
- **Hard sync to wall time:** Emulation catches up if it falls behind

**Step Modes** (integration with debugger):
- **Step Instruction:** Execute one CPU instruction, then pause
- **Step Scanline:** Execute until next scanline, then pause
- **Step Frame:** Execute one complete frame, then pause
- **Step Over:** Step instruction, skip subroutines
- **Step Out:** Run until return from subroutine

**Speed Multiplier Modes:**
- **Fast Forward:** 2×, 4×, 8×, unlimited (run as fast as possible)
- **Slow Motion:** 0.5×, 0.25×, 0.125× (for debugging)
- **Paused:** Emulation stopped, debugger active

**Dynamic Control:**
- Change speed at runtime via ConfigMailbox
- Switch PAL/NTSC on the fly
- Enable/disable vsync (affects fast-forward behavior)

---

## Emulation Speed Controller Design

### New Module: `src/emulation/SpeedController.zig`

```zig
//! Emulation Speed Controller
//!
//! Manages cycle-accurate timing and speed control for emulation thread.
//! Integrates with debugger step modes for unified control.
//!
//! Modes:
//! - Real-time (hard sync to wall clock)
//! - Fast forward (N× speed or unlimited)
//! - Slow motion (fractional speed)
//! - Paused (stopped, debugger active)
//! - Step modes (instruction, scanline, frame)

const std = @import("std");
const xev = @import("xev");
const Debugger = @import("../debugger/Debugger.zig");

/// Emulation speed mode
pub const SpeedMode = enum {
    /// Real-time (sync to wall clock at NTSC/PAL rate)
    realtime,
    /// Fast forward (N× speed multiplier)
    fast_forward,
    /// Slow motion (fractional speed < 1.0)
    slow_motion,
    /// Paused (emulation stopped)
    paused,
    /// Step mode (controlled by debugger)
    stepping,
};

/// Timing variant (PAL vs NTSC)
pub const TimingVariant = enum {
    ntsc, // 60.0988 Hz
    pal,  // 50.0070 Hz
};

/// Speed controller configuration
pub const SpeedConfig = struct {
    mode: SpeedMode = .realtime,
    timing: TimingVariant = .ntsc,

    /// Speed multiplier (1.0 = real-time, 2.0 = 2×, 0.5 = half speed)
    speed_multiplier: f64 = 1.0,

    /// Hard sync to wall time (catches up if behind)
    hard_sync: bool = true,

    /// Maximum catchup frames (prevent death spiral)
    max_catchup_frames: u32 = 5,
};

/// Frame duration constants (nanoseconds)
pub const FRAME_DURATION_NS = struct {
    pub const NTSC: u64 = 16_639_267; // 60.0988 Hz
    pub const PAL: u64 = 19_997_200;  // 50.0070 Hz
};

/// Emulation speed controller
pub const SpeedController = struct {
    config: SpeedConfig,

    /// Wall time reference for hard sync
    wall_time_ref: i128 = 0,

    /// Frame count for timing calculations
    frame_count: u64 = 0,

    /// Debugger reference (for step mode integration)
    debugger: ?*Debugger = null,

    /// Statistics
    stats: Stats = .{},

    pub const Stats = struct {
        frames_emulated: u64 = 0,
        frames_dropped: u64 = 0,
        catchup_count: u64 = 0,
        avg_frame_time_ns: u64 = 0,
    };

    pub fn init(config: SpeedConfig) SpeedController {
        return .{
            .config = config,
            .wall_time_ref = std.time.nanoTimestamp(),
        };
    }

    /// Attach debugger for step mode integration
    pub fn attachDebugger(self: *SpeedController, debugger: *Debugger) void {
        self.debugger = debugger;
    }

    /// Calculate target frame duration based on current config
    pub fn getFrameDurationNs(self: *const SpeedController) u64 {
        const base_duration = switch (self.config.timing) {
            .ntsc => FRAME_DURATION_NS.NTSC,
            .pal => FRAME_DURATION_NS.PAL,
        };

        // Apply speed multiplier
        const adjusted = @as(f64, @floatFromInt(base_duration)) / self.config.speed_multiplier;
        return @intFromFloat(adjusted);
    }

    /// Check if emulation should tick this frame
    /// Returns: .proceed, .wait, or .skip
    pub fn shouldTick(self: *SpeedController) TickDecision {
        switch (self.config.mode) {
            .paused => return .wait,

            .stepping => {
                // Delegate to debugger
                if (self.debugger) |dbg| {
                    return if (dbg.shouldBreak()) .wait else .proceed;
                }
                return .proceed;
            },

            .realtime, .fast_forward, .slow_motion => {
                if (!self.config.hard_sync) {
                    // No sync: always proceed
                    return .proceed;
                }

                // Hard sync: check if we're on schedule
                const now = std.time.nanoTimestamp();
                const expected_time = self.wall_time_ref +
                    @as(i128, @intCast(self.frame_count * self.getFrameDurationNs()));

                const drift_ns = now - expected_time;

                if (drift_ns < 0) {
                    // We're ahead: wait
                    return .{ .wait_ns = @intCast(-drift_ns) };
                } else if (drift_ns > self.getFrameDurationNs() * self.config.max_catchup_frames) {
                    // We're too far behind: skip frames to catch up
                    const frames_behind = @divTrunc(drift_ns, @as(i128, @intCast(self.getFrameDurationNs())));
                    self.stats.frames_dropped += @intCast(frames_behind);
                    self.stats.catchup_count += 1;

                    // Reset reference to prevent death spiral
                    self.wall_time_ref = now;
                    self.frame_count = 0;
                    return .proceed;
                } else {
                    // We're slightly behind: catch up by running faster
                    return .proceed;
                }
            },
        }
    }

    pub const TickDecision = union(enum) {
        proceed: void,      // Emulate this frame immediately
        wait: void,         // Paused or at breakpoint
        wait_ns: u64,       // Wait this many ns before next frame
    };

    /// Mark frame complete
    pub fn frameDone(self: *SpeedController) void {
        self.frame_count += 1;
        self.stats.frames_emulated += 1;
    }

    /// Update configuration (from ConfigMailbox)
    pub fn updateConfig(self: *SpeedController, new_config: SpeedConfig) void {
        const timing_changed = self.config.timing != new_config.timing;

        self.config = new_config;

        if (timing_changed) {
            // Reset timing reference on PAL/NTSC switch
            self.wall_time_ref = std.time.nanoTimestamp();
            self.frame_count = 0;
        }
    }

    /// Set speed multiplier
    pub fn setSpeedMultiplier(self: *SpeedController, multiplier: f64) void {
        self.config.speed_multiplier = std.math.clamp(multiplier, 0.01, 100.0);
    }

    /// Fast forward modes
    pub fn setFastForward(self: *SpeedController, multiplier: f64) void {
        self.config.mode = .fast_forward;
        self.setSpeedMultiplier(multiplier);
    }

    pub fn setSlowMotion(self: *SpeedController, multiplier: f64) void {
        self.config.mode = .slow_motion;
        self.setSpeedMultiplier(multiplier);
    }

    pub fn setRealtime(self: *SpeedController) void {
        self.config.mode = .realtime;
        self.config.speed_multiplier = 1.0;
        self.wall_time_ref = std.time.nanoTimestamp();
        self.frame_count = 0;
    }

    pub fn pause(self: *SpeedController) void {
        self.config.mode = .paused;
    }

    pub fn resume(self: *SpeedController) void {
        if (self.config.mode == .paused) {
            self.config.mode = .realtime;
            self.wall_time_ref = std.time.nanoTimestamp();
            self.frame_count = 0;
        }
    }
};
```

### Integration with Emulation Thread

```zig
// src/main.zig - Revised emulation thread

fn emulationThreadFn(
    state: *EmulationState,
    mailboxes: *Mailboxes,
    running: *std.atomic.Value(bool),
) void {
    std.log.info("[Emulation] Thread started (timer-driven, isolated)", .{});

    // Create event loop for timer-driven ticking
    var loop = xev.Loop.init(.{}) catch |err| {
        std.log.err("[Emulation] Failed to init loop: {}", .{err});
        return;
    };
    defer loop.deinit();

    // Initialize speed controller
    var speed_controller = SpeedController.init(.{
        .mode = .realtime,
        .timing = .ntsc,
        .hard_sync = true,
    });

    // Optionally attach debugger
    // speed_controller.attachDebugger(&debugger);

    // Context for timer callback
    var ctx = EmulationContext{
        .state = state,
        .mailboxes = mailboxes,
        .running = running,
        .speed_controller = &speed_controller,
    };

    // Start timer
    var timer = xev.Timer{};
    var completion: xev.Completion = undefined;
    const initial_duration_ns = speed_controller.getFrameDurationNs();
    const initial_duration_ms = initial_duration_ns / 1_000_000;
    timer.run(&loop, &completion, initial_duration_ms, EmulationContext, &ctx, emulationTimerCallback);

    // Run loop
    loop.run(.until_done) catch |err| {
        std.log.err("[Emulation] Loop error: {}", .{err});
    };

    std.log.info("[Emulation] Thread stopped", .{});
}

const EmulationContext = struct {
    state: *EmulationState,
    mailboxes: *Mailboxes,
    running: *std.atomic.Value(bool),
    speed_controller: *SpeedController,
    last_report: i128 = 0,
    report_frame_count: u64 = 0,
};

fn emulationTimerCallback(
    userdata: ?*EmulationContext,
    loop: *xev.Loop,
    completion: *xev.Completion,
    result: xev.Timer.RunError!void,
) xev.CallbackAction {
    _ = result catch return .disarm;

    const ctx = userdata orelse return .disarm;

    if (!ctx.running.load(.acquire)) {
        return .disarm;
    }

    // Check for config updates (speed changes, PAL/NTSC switch)
    if (ctx.mailboxes.config.pollUpdate()) |update| {
        // Update speed controller based on config
        _ = update;
        // TODO: Parse update and apply to speed_controller
    }

    // Check if we should tick this frame
    const decision = ctx.speed_controller.shouldTick();

    switch (decision) {
        .wait => {
            // Paused or at breakpoint - rearm timer with same duration
            const duration_ms = ctx.speed_controller.getFrameDurationNs() / 1_000_000;
            var timer = xev.Timer{};
            timer.run(loop, completion, duration_ms, EmulationContext, ctx, emulationTimerCallback);
            return .rearm;
        },

        .wait_ns => |ns| {
            // Need to wait before next frame
            const wait_ms = ns / 1_000_000;
            var timer = xev.Timer{};
            timer.run(loop, completion, wait_ms, EmulationContext, ctx, emulationTimerCallback);
            return .rearm;
        },

        .proceed => {
            // Emulate one frame
            const write_buf = ctx.mailboxes.frame.getWriteBuffer();
            const cycles = ctx.state.emulateFrame();
            _ = cycles;

            // Post frame to mailbox (non-blocking)
            ctx.mailboxes.frame.swapBuffers();

            // Mark frame complete
            ctx.speed_controller.frameDone();

            // Progress reporting (every second)
            ctx.report_frame_count += 1;
            const now = std.time.nanoTimestamp();
            if (ctx.last_report == 0) {
                ctx.last_report = now;
            } else if (now - ctx.last_report >= 1_000_000_000) {
                const elapsed = @as(f64, @floatFromInt(now - ctx.last_report)) / 1_000_000_000.0;
                const fps = @as(f64, @floatFromInt(ctx.report_frame_count)) / elapsed;
                std.log.info("[Emulation] FPS: {d:.2} (target: {d:.2}, mode: {})", .{
                    fps,
                    1_000_000_000.0 / @as(f64, @floatFromInt(ctx.speed_controller.getFrameDurationNs())),
                    ctx.speed_controller.config.mode,
                });
                ctx.report_frame_count = 0;
                ctx.last_report = now;
            }

            // Rearm timer for next frame
            const duration_ms = ctx.speed_controller.getFrameDurationNs() / 1_000_000;
            var timer = xev.Timer{};
            timer.run(loop, completion, duration_ms, EmulationContext, ctx, emulationTimerCallback);
            return .rearm;
        },
    }
}
```

---

## Three-Thread Architecture

### Thread 1: Main (Coordinator)

```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("[Main] RAMBO NES Emulator - Isolated Emulation Architecture", .{});

    // Initialize mailboxes
    var mailboxes = try Mailboxes.init(allocator);
    defer mailboxes.deinit();

    // Initialize emulation state
    var config = Config.init(allocator);
    defer config.deinit();
    var emu_state = EmulationState.init(&config);

    // Shared running flag
    var running = std.atomic.Value(bool).init(true);

    // Spawn emulation thread (isolated, timer-driven)
    const emu_thread = try std.Thread.spawn(.{}, emulationThreadFn, .{
        &emu_state, &mailboxes, &running
    });

    // Spawn render thread (Wayland + Vulkan)
    const render_thread = try std.Thread.spawn(.{}, renderThreadFn, .{
        &mailboxes, &running
    });

    // Main coordination loop (minimal work)
    std.log.info("[Main] Coordination loop active", .{});

    while (running.load(.acquire)) {
        // Process high-level events from WaylandEventMailbox
        const events = mailboxes.wayland.swapAndGetPendingEvents();
        for (events) |event| {
            switch (event) {
                .window_close => {
                    std.log.info("[Main] Window closed, shutting down", .{});
                    running.store(false, .release);
                },
                .key_press => |key| {
                    // Future: Send to ControllerInputMailbox
                    _ = key;
                },
                else => {},
            }
        }

        // Sleep to avoid busy-wait (coordination is low frequency)
        std.Thread.sleep(16_000_000); // 16ms
    }

    // Shutdown
    std.log.info("[Main] Joining threads...", .{});
    emu_thread.join();
    render_thread.join();
    std.log.info("[Main] Shutdown complete", .{});
}
```

### Thread 2: Emulation (Isolated, Timer-Driven)

**Characteristics:**
- Own libxev loop for precise timing
- Timer-driven frame callbacks
- SpeedController manages timing modes
- Posts to FrameMailbox (non-blocking)
- Reads from ConfigMailbox for speed/timing changes
- **Zero dependency on render thread**

**Flow:**
1. Timer fires at configured rate (NTSC/PAL/custom)
2. SpeedController.shouldTick() decides: proceed, wait, or skip
3. If proceed: emulateFrame(), post to FrameMailbox
4. Rearm timer for next frame

### Thread 3: Render (Wayland + Vulkan)

```zig
fn renderThreadFn(
    mailboxes: *Mailboxes,
    running: *std.atomic.Value(bool),
) !void {
    std.log.info("[Render] Thread started", .{});

    // Initialize Wayland state
    var wayland_state = try WaylandState.init(std.heap.c_allocator);
    defer wayland_state.deinit();

    // Initialize Vulkan renderer
    var vulkan_state = try VulkanState.init(std.heap.c_allocator, &wayland_state);
    defer vulkan_state.deinit();

    // libxev loop for Wayland fd monitoring
    var loop = try xev.Loop.init(.{});
    defer loop.deinit();

    // Register Wayland fd with libxev
    const wl_fd = wayland_state.display.getFd();
    // TODO: Setup fd read callback
    _ = wl_fd;

    std.log.info("[Render] Entering render loop", .{});

    while (!wayland_state.closed and running.load(.acquire)) {
        // 1. Run libxev loop (non-blocking Wayland event processing)
        try loop.run(.no_wait);

        // 2. Dispatch Wayland protocol events
        _ = try wayland_state.display.dispatchPending();

        // 3. Check for new frame from emulation (lock-free)
        if (mailboxes.frame.hasNewFrame()) {
            const frame_data = mailboxes.frame.getReadBuffer();

            // Upload texture to GPU
            try VulkanLogic.uploadTexture(&vulkan_state, frame_data);

            // Render and present (natural vsync blocks here)
            try VulkanLogic.present(&vulkan_state);
        } else {
            // No new frame, small sleep to prevent busy-wait
            std.Thread.sleep(1_000_000); // 1ms
        }

        // 4. Flush Wayland requests
        _ = try wayland_state.display.flush();
    }

    std.log.info("[Render] Thread stopped", .{});
}
```

**Characteristics:**
- Own libxev loop for Wayland fd monitoring
- Drains FrameMailbox (non-blocking check)
- Uploads textures and presents with Vulkan vsync
- Posts events to WaylandEventMailbox
- **Zero dependency on emulation timing**

---

## Speed Control Use Cases

### Use Case 1: Real-Time Emulation (Default)

```zig
// Main configures real-time NTSC
mailboxes.config.post(.{
    .emulation = .{
        .speed_mode = .realtime,
        .timing = .ntsc,
        .hard_sync = true,
    },
});
```

**Behavior:**
- Emulation runs at exactly 60.0988 Hz
- Hard sync to wall clock (catches up if behind)
- Frame drops if system can't keep up
- Render thread presents frames at monitor refresh rate
- If emulation is faster than display: extra frames accumulate in mailbox

### Use Case 2: Fast Forward (2×, 4×, Unlimited)

```zig
// User presses fast-forward key
mailboxes.config.post(.{
    .emulation = .{
        .speed_mode = .fast_forward,
        .speed_multiplier = 4.0, // 4× speed
        .hard_sync = false, // Run as fast as possible
    },
});
```

**Behavior:**
- Emulation runs at 4× normal speed (240 FPS)
- No hard sync to wall time
- Render thread consumes frames as fast as possible
- Vsync limits display to 60 FPS (240 emulated, 60 displayed)
- Mailbox handles overflow gracefully

### Use Case 3: Step Frame (Debugger Integration)

```zig
// Debugger triggers step frame
debugger.stepFrame(&emu_state);

// Speed controller enters stepping mode
speed_controller.config.mode = .stepping;
```

**Behavior:**
- Emulation executes exactly one frame
- SpeedController.shouldTick() delegates to debugger
- Debugger returns `.wait` after frame completes
- Emulation pauses until next step command
- Render thread continues displaying last frame

### Use Case 4: Slow Motion (0.5× speed)

```zig
// User enters slow motion mode
mailboxes.config.post(.{
    .emulation = .{
        .speed_mode = .slow_motion,
        .speed_multiplier = 0.5, // Half speed
        .hard_sync = true,
    },
});
```

**Behavior:**
- Emulation runs at 30 FPS (NTSC)
- Each frame takes 33ms instead of 16ms
- Render thread displays every frame (smooth slow-mo)
- Useful for analyzing gameplay or debugging

### Use Case 5: PAL/NTSC Switching

```zig
// Switch to PAL timing at runtime
mailboxes.config.post(.{
    .emulation = .{
        .timing = .pal, // 50.007 Hz
    },
});
```

**Behavior:**
- SpeedController recalculates frame duration
- Timing reference resets to prevent drift
- Emulation immediately switches to PAL rate
- PPU scanline count changes (262 → 312 for PAL)
- Audio pitch changes (if APU implemented)

---

## Enhanced FrameMailbox API

The previous plan's FrameMailbox enhancement is still correct:

```zig
pub const FrameMailbox = struct {
    write_buffer: *FrameBuffer,
    read_buffer: *FrameBuffer,
    mutex: std.Thread.Mutex = .{},
    has_new_frame: std.atomic.Value(bool) = .{ .raw = false },

    /// Emulation thread: Get buffer to write (always available)
    pub fn getWriteBuffer(self: *FrameMailbox) []u32 {
        return self.write_buffer.pixels[0..];
    }

    /// Emulation thread: Post frame (swaps buffers)
    pub fn swapBuffers(self: *FrameMailbox) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        std.mem.swap(*FrameBuffer, &self.write_buffer, &self.read_buffer);
        self.has_new_frame.store(true, .release);
    }

    /// Render thread: Check if new frame available (lock-free)
    pub fn hasNewFrame(self: *const FrameMailbox) bool {
        return self.has_new_frame.load(.acquire);
    }

    /// Render thread: Get read buffer (lock-free)
    pub fn getReadBuffer(self: *FrameMailbox) []const u32 {
        self.has_new_frame.store(false, .release);
        return self.read_buffer.pixels[0..];
    }
};
```

**Key Properties:**
- **Non-blocking:** Emulation never waits on render thread
- **Lock-free read check:** Render thread doesn't block on mutex for checking
- **Overflow handling:** If render is slow, old frames are overwritten
- **Underflow handling:** If emulation is slow, render displays last frame

---

## Implementation Phases (REVISED)

### Phase 8.0: Speed Controller & Mailbox Enhancement (6-8 hours)

**Tasks:**

1. **Implement SpeedController** (4-5 hours)
   - Create `src/emulation/SpeedController.zig`
   - Implement all speed modes
   - Integrate with debugger stepping
   - Hard sync to wall time logic
   - Frame drop/catchup handling

2. **Enhance FrameMailbox** (1-2 hours)
   - Add `has_new_frame` atomic flag
   - Implement lock-free `hasNewFrame()` and `getReadBuffer()`
   - Update tests

3. **Refactor Emulation Thread** (1 hour)
   - Integrate SpeedController
   - Add config update handling
   - Statistics reporting

**Deliverable:** Emulation thread with full speed control, independently testable

### Phase 8.1: Wayland Window & Event System (8-10 hours)

**Tasks:**

1. **Create Wayland State Module** (4-5 hours)
   - `src/video/WaylandState.zig` - Pure protocol state
   - `src/video/WaylandLogic.zig` - Protocol operations
   - Connection, registry, surface, XDG shell

2. **Implement Event Callbacks** (2-3 hours)
   - Configure, resize, close callbacks
   - Keyboard event handling
   - Post to WaylandEventMailbox

3. **libxev Integration** (2 hours)
   - Wayland fd monitoring
   - Event dispatch in render loop

**Deliverable:** Wayland window opens, events flow to mailbox

### Phase 8.2: Vulkan Renderer (10-12 hours)

**Tasks:**

1. **Vulkan State Module** (5-6 hours)
   - `src/video/VulkanState.zig`
   - Instance, device, swapchain (FIFO for vsync)
   - Render pass, pipeline, shaders

2. **Texture Upload** (2-3 hours)
   - Staging buffer
   - Image layout transitions
   - Copy from FrameMailbox

3. **Render Loop** (3 hours)
   - Present logic
   - Swapchain recreation on resize
   - Error handling

**Deliverable:** Vulkan renders frames to window

### Phase 8.3: Three-Thread Integration (4-6 hours)

**Tasks:**

1. **Spawn Render Thread** (2 hours)
   - Add to main.zig
   - Thread coordination
   - Shutdown handling

2. **Full Pipeline Test** (2-3 hours)
   - Test with AccuracyCoin.nes
   - Verify speed modes work
   - Test PAL/NTSC switching
   - Test step modes

3. **Performance Validation** (1 hour)
   - Measure emulation FPS at various speeds
   - Verify independence (emulation runs at target rate regardless of display)
   - Test frame drop behavior

**Deliverable:** Full visual output with speed control

### Phase 8.4: Advanced Speed Control Features (4-6 hours)

**Tasks:**

1. **Hotkey Bindings** (2 hours)
   - Fast forward key (Tab key standard)
   - Pause key (Space)
   - Frame advance (F key)
   - Speed adjustment (+ / -)

2. **Speed Indicator Overlay** (2 hours)
   - FPS counter
   - Speed multiplier display
   - Mode indicator (realtime/fast/slow/paused)

3. **Save State Integration** (2 hours)
   - Pause emulation during save/load
   - Resume at exact frame

**Deliverable:** Production-ready emulation with full speed control

---

## Critical Questions for User

### Architecture Confirmation

**Q1:** Confirm three-thread architecture?
- Main: Coordinator
- Emulation: Timer-driven, isolated
- Render: Wayland + Vulkan

**Q2:** Emulation speed control requirements complete?
- Real-time (NTSC/PAL)
- Fast forward (configurable multiplier)
- Slow motion
- Step modes (instruction, scanline, frame)
- Paused

**Q3:** Should SpeedController be separate module or integrated into EmulationState?
- **Option A:** Separate (cleaner separation of concerns)
- **Option B:** Integrated (fewer indirections)

### Debugger Integration

**Q4:** How should speed control and debugger stepping interact?
- **Proposed:** SpeedController delegates to Debugger when in stepping mode
- **Alternative:** Separate control (debugger overrides speed controller)

**Q5:** Should debugger commands affect speed controller state?
- Example: When setting breakpoint, automatically pause emulation?
- Example: When stepping, temporarily override speed mode?

### Performance & Timing

**Q6:** Frame overflow strategy when emulation > render?
- **Current:** Overwrite (render thread always gets latest frame)
- **Alternative:** Queue (buffer N frames, drop oldest)

**Q7:** Hard sync catchup strategy?
- **Current:** Drop frames if >5 frames behind, reset timing
- **Alternative:** Configurable threshold, warning to user

**Q8:** Should fast-forward disable vsync on render thread?
- **Yes:** Allows faster display (limited by GPU, not monitor)
- **No:** Keep vsync always (smoother but slower fast-forward)

### Configuration

**Q9:** Speed control configuration source?
- **ConfigMailbox:** Requires main thread to relay
- **Direct mailbox:** Dedicated SpeedControlMailbox
- **Hybrid:** Both supported

**Q10:** Should timing variant (PAL/NTSC) affect ROM loading?
- Detect from ROM region byte?
- User override?
- Runtime switching?

---

## Testing Strategy

### Emulation Independence Tests

1. **Render Stall Test:**
   - Artificially slow render thread (add 100ms delay)
   - Verify emulation continues at target rate
   - Verify frames accumulate in mailbox

2. **Fast Forward Test:**
   - Set 10× speed multiplier
   - Verify emulation runs at 600 FPS
   - Verify render displays at 60 FPS

3. **Step Mode Test:**
   - Enter step frame mode
   - Verify emulation pauses after exactly one frame
   - Verify render continues displaying last frame

### Wall Time Sync Tests

4. **Catchup Test:**
   - Artificially delay emulation (sleep in callback)
   - Verify catchup behavior (extra frames emulated)
   - Verify timing reset after max catchup

5. **PAL/NTSC Switch Test:**
   - Start in NTSC mode (60 FPS)
   - Switch to PAL (50 FPS)
   - Verify timing adjusts correctly
   - Verify no frame drops during transition

### Integration Tests

6. **Three-Thread Coordination:**
   - Verify clean startup (all threads initialize)
   - Verify clean shutdown (all threads join)
   - Verify mailbox communication works

7. **End-to-End AccuracyCoin:**
   - Run AccuracyCoin.nes
   - Verify visual output correct
   - Verify can fast-forward
   - Verify can step frame
   - Verify can pause/resume

---

## Success Criteria

### Phase 8.0: Speed Controller
- ✅ SpeedController supports all modes (realtime, fast, slow, paused, stepping)
- ✅ Hard sync to wall time works (no drift over 60 seconds)
- ✅ Debugger integration works (step modes functional)
- ✅ FrameMailbox has lock-free checks
- ✅ All existing tests still pass

### Phase 8.1: Wayland
- ✅ Window opens and displays
- ✅ Events posted to mailbox
- ✅ Render thread runs independently

### Phase 8.2: Vulkan
- ✅ Texture upload from FrameMailbox
- ✅ Vsync works (60 FPS display)
- ✅ No tearing

### Phase 8.3: Integration
- ✅ Three threads coordinate correctly
- ✅ Emulation runs at target rate regardless of display
- ✅ Fast forward works (emulation faster than display)
- ✅ Step modes work
- ✅ AccuracyCoin displays correctly

### Phase 8.4: Advanced Features
- ✅ Hotkeys work
- ✅ Speed indicator displays
- ✅ Save states work with pausing

---

**Status:** 🟡 **Awaiting User Approval**
**Next:** Answer Q1-Q10, confirm architecture is correct
