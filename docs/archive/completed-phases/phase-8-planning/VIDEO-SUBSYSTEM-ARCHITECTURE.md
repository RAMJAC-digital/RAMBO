# Video Subsystem Architecture

**Date:** 2025-10-04
**Status:** Architecture Complete - Ready for Implementation
**Pattern:** Triple Buffering + libxev Async Notification

## Overview

The video subsystem uses **triple buffering** to communicate between the RT emulation thread and the display thread, with libxev async notifications for event-driven wakeup.

## Core Principle: Triple Buffering

Triple buffering provides three pre-allocated frame buffers with atomic index swapping, ensuring the RT thread never blocks while always displaying the latest complete frame.

```
RT Thread (PPU)          Triple Buffer            Display Thread
─────────────────        ─────────────            ──────────────
Writes to back      →    3 pre-allocated     →    Reads from front
Never blocks            RGBA buffers (3×240KB)    Uploads to GPU
Atomic index swap       Lock-free swaps           libxev event loop
```

## Triple Buffer Structure

| Buffer | Used By | Purpose | Access |
|--------|---------|---------|--------|
| **Back Buffer** | RT thread (writing) | PPU renders pixels here | Exclusive write |
| **Ready Buffer** | Neither (complete) | Waiting for display to grab | Read-only |
| **Front Buffer** | Display thread (reading) | Upload to GPU | Exclusive read |

**Key:** Three buffers ensure RT thread never blocks. Atomic index swapping provides latest-frame semantics.

## Data Flow

### 1. Initialization (Main Thread)

```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Initialize triple buffer
    var triple_buffer = try TripleBuffer.init();

    // Initialize renderer (owns GPU resources)
    var renderer = try Renderer.init(allocator);

    // Initialize emulation state
    var emu_state = EmulationState.init(&config, bus);

    // Spawn RT thread
    const rt_thread = try std.Thread.spawn(.{}, rtThreadMain, .{
        &emu_state,
        &triple_buffer,
    });

    // Run display thread on main thread
    displayThreadMain(&triple_buffer, &renderer);

    rt_thread.join();
}
```

### 2. RT Thread (Emulation Loop)

```zig
fn rtThreadMain(emu: *EmulationState, triple_buf: *TripleBuffer) void {
    while (true) {
        // Get back buffer for writing
        const back_buffer = triple_buf.getBackBuffer();

        // Emulate one frame (PPU writes pixels to back buffer)
        _ = emu.emulateFrame();

        // Swap back ↔ ready (atomic, non-blocking)
        triple_buf.swapBuffers();

        // Notify display thread via libxev async
        triple_buf.signalFrameReady();
    }
}
```

**PPU Rendering (inside emulateFrame):**
```zig
pub fn emulateFrame(self: *EmulationState) u64 {
    const back_buffer = self.triple_buffer.getBackBuffer();

    while (!self.frame_complete) {
        self.tick(); // CPU + PPU + Bus

        // PPU writes directly to back_buffer during visible scanlines
        if (self.ppu.scanline < 240 and self.ppu.dot < 256) {
            const pixel_idx = self.ppu.scanline * 256 + self.ppu.dot;
            back_buffer[pixel_idx] = self.ppu.getPixelColor();
        }
    }

    return self.clock.ppu_cycles;
}
```

### 3. Display Thread (libxev Event Loop)

```zig
fn displayThreadMain(triple_buf: *TripleBuffer, renderer: *Renderer) void {
    var loop = try xev.Loop.init(.{});
    defer loop.deinit();

    // Register libxev async notification callback
    var ctx = FrameContext{ .triple_buf = triple_buf, .renderer = renderer };
    var async_handle = try xev.Async.init();
    var completion: xev.Completion = undefined;

    // Callback fires when RT thread calls signalFrameReady()
    async_handle.wait(&loop, &completion, *FrameContext, &ctx, onFrameReady);

    // Event loop - processes completions as they arrive
    while (true) {
        try loop.run(.no_wait); // Process all pending events
        std.time.sleep(1_000_000); // 1ms sleep to avoid CPU spin
    }
}

fn onFrameReady(
    ctx: *FrameContext,
    loop: *xev.Loop,
    completion: *xev.Completion,
    result: xev.Async.WaitError!void,
) xev.CallbackAction {
    _ = loop;
    _ = completion;
    _ = result catch return .disarm;

    // Get front buffer (latest complete frame)
    const front_buffer = ctx.triple_buf.getFrontBuffer();

    // Upload to GPU
    ctx.renderer.uploadTexture(front_buffer) catch {
        return .rearm;
    };

    // Render to screen (blocks on vsync)
    ctx.renderer.drawFrame() catch {
        return .rearm;
    };

    // Re-register callback for next frame
    return .rearm;
}
```

## TripleBuffer Implementation

```zig
//! Triple Buffering for RT Video Frame Passing
//!
//! Provides three pre-allocated frame buffers with atomic index swapping.
//! RT thread writes to back buffer, display thread reads from front buffer.
//! Middle "ready" buffer holds latest complete frame.

const std = @import("std");
const xev = @import("xev");

pub const FrameBuffer = struct {
    pixels: [256 * 240]u32 align(64),
    frame_num: u64,
};

pub const TripleBuffer = struct {
    /// Three pre-allocated frame buffers (back, ready, front)
    buffers: [3]FrameBuffer align(128),

    /// Atomic indices (cache-line aligned to prevent false sharing)
    back_idx: std.atomic.Value(u8) align(128) = .{ .raw = 0 },    // RT writes here
    ready_idx: std.atomic.Value(u8) align(128) = .{ .raw = 1 },   // Complete frame
    front_idx: std.atomic.Value(u8) align(128) = .{ .raw = 2 },   // Display reads

    /// Frame counter for dropped frame detection
    frame_count: std.atomic.Value(u64) align(128) = .{ .raw = 0 },

    /// libxev async notification handle
    async_handle: xev.Async,

    pub fn init() !TripleBuffer {
        return .{
            .buffers = undefined,
            .async_handle = try xev.Async.init(),
        };
    }

    pub fn deinit(self: *TripleBuffer) void {
        self.async_handle.deinit();
    }

    /// RT Thread: Get back buffer for writing (non-blocking)
    pub fn getBackBuffer(self: *TripleBuffer) []u32 {
        const idx = self.back_idx.load(.acquire);
        return &self.buffers[idx].pixels;
    }

    /// RT Thread: Swap back ↔ ready (atomic, non-blocking)
    pub fn swapBuffers(self: *TripleBuffer) void {
        // Ensure all pixel writes complete before swapping indices
        @fence(.release);

        const back = self.back_idx.load(.acquire);
        const ready = self.ready_idx.load(.acquire);

        // Atomic swap: back becomes ready, ready becomes back
        self.back_idx.store(ready, .release);
        self.ready_idx.store(back, .release);

        _ = self.frame_count.fetchAdd(1, .release);
    }

    /// RT Thread: Notify display thread
    pub fn signalFrameReady(self: *TripleBuffer) void {
        self.async_handle.notify() catch {};
    }

    /// Display Thread: Get front buffer (latest complete frame)
    pub fn getFrontBuffer(self: *TripleBuffer) []const u32 {
        const idx = self.front_idx.load(.acquire);
        return &self.buffers[idx].pixels;
    }

    /// Display Thread: Swap front ↔ ready (get latest frame)
    pub fn updateFrontBuffer(self: *TripleBuffer) void {
        const front = self.front_idx.load(.acquire);
        const ready = self.ready_idx.load(.acquire);

        // Atomic swap: front gets ready, ready gets old front
        self.front_idx.store(ready, .release);
        self.ready_idx.store(front, .release);
    }
};
```

## libxev Integration

### How libxev Async Works

```zig
// Linux: Uses eventfd (file descriptor for cross-thread wakeup)
// Darwin: Uses mach port
// Windows: Uses IOCP

var async_handle = try xev.Async.init();

// Display thread registers callback
async_handle.wait(&loop, &completion, Userdata, &data, callback);

// RT thread notifies (writes to eventfd)
async_handle.notify(); // Non-blocking, never fails

// Display thread event loop wakes up
try loop.run(.no_wait); // Processes callback immediately
```

### Event Loop Behavior

```zig
// .no_wait - Process all pending completions, return immediately
try loop.run(.no_wait);

// .once - Process at least one completion, may block
try loop.run(.once);

// .until_done - Run until no more completions (blocks)
try loop.run(.until_done);
```

**Display thread uses `.no_wait` in continuous loop:**
- Processes any pending async notifications
- Handles Wayland events
- Renders current frame
- Sleeps 1ms to avoid CPU spin

## PAL on 60Hz Display Support

When running PAL games (50Hz) on 60Hz displays, frames may be incomplete when grabbed:

```zig
fn onFrameReady(ctx: *FrameContext, ...) xev.CallbackAction {
    // Swap to latest ready frame (may be mid-render for PAL)
    ctx.triple_buf.updateFrontBuffer();
    const front_buffer = ctx.triple_buf.getFrontBuffer();

    // Upload whatever's available - tearing visible but acceptable
    ctx.renderer.uploadTexture(front_buffer) catch {};
    ctx.renderer.drawFrame() catch {};

    return .rearm;
}
```

**Result:** Display grabs frames at 60Hz, PPU produces at 50Hz. Some frames will show partial rendering (screen tearing). This is **acceptable** per requirements.

**Future:** Add XDG display mode setting to match emulation rate (50Hz/60Hz).

## Module Structure

```
src/video/
├── TripleBuffer.zig       # Triple buffering with atomic index swapping
├── Renderer.zig           # Display backend abstraction
├── Window.zig             # Wayland window management
└── backends/
    ├── Vulkan.zig         # Vulkan backend (PRIMARY)
    └── Software.zig       # CPU fallback (testing)

src/emulation/
└── State.zig              # Modified to use TripleBuffer

src/ppu/
└── Logic.zig              # Writes pixels to buffer from TripleBuffer
```

## Implementation Phases

### Phase 1: TripleBuffer Foundation (4-6 hours)

**Files:**
1. `src/video/TripleBuffer.zig` - Triple buffering implementation
2. `tests/video/triple_buffer_test.zig` - Comprehensive tests

**Tests:**
- Basic buffer swapping (RT thread swapBuffers, display thread getFrontBuffer)
- Concurrent producer/consumer
- Frame drop detection (RT faster than display)
- libxev async notification latency
- Stress test (1000 frames/sec production)

**Success Criteria:**
- All tests pass
- <1μs buffer swap latency
- Zero allocations on hot path
- libxev notification <1ms wakeup

### Phase 2: PPU Integration (2-3 hours)

**Files:**
1. Modify `src/emulation/State.zig` - Add TripleBuffer integration
2. Modify `src/ppu/Logic.zig` - Write to TripleBuffer back buffer
3. `tests/video/ppu_integration_test.zig` - Integration tests

**Changes:**
```zig
pub const EmulationState = struct {
    triple_buffer: ?*TripleBuffer = null,

    pub fn emulateFrame(self: *EmulationState) u64 {
        const buffer = if (self.triple_buffer) |tb|
            tb.getBackBuffer()
        else
            null;

        // ... emulation loop writes to buffer ...

        if (self.triple_buffer) |tb| {
            tb.swapBuffers();
            tb.signalFrameReady();
        }
    }
};
```

### Phase 3: Wayland Window (5-6 hours)

**Files:**
1. `src/video/Window.zig` - Wayland surface + XDG shell
2. `tests/video/window_test.zig` - Window creation tests

**Features:**
- Wayland display connection
- XDG toplevel window
- Event handling (resize, close, focus)
- Wayland event dispatch in libxev loop

### Phase 4: Vulkan Renderer (10-12 hours)

**Files:**
1. `src/video/Renderer.zig` - Backend abstraction
2. `src/video/backends/Vulkan.zig` - Vulkan implementation
3. `tests/video/vulkan_test.zig` - Vulkan tests

**Features:**
- Vulkan instance + device selection
- Wayland surface creation
- Swapchain with FIFO present mode (vsync)
- Texture upload pipeline
- Fullscreen quad rendering
- Aspect ratio correction (NTSC 8:7, PAL 11:8)

### Phase 5: Display Thread Integration (3-4 hours)

**Files:**
1. `src/video/DisplayThread.zig` - libxev event loop
2. `src/main.zig` - Application entry point updates
3. `tests/video/integration_test.zig` - Full stack test

**Integration:**
- libxev loop with async callback
- Wayland event processing
- Frame rendering with vsync
- Error handling and recovery

## Total Effort: 24-31 hours

## Performance Targets

**RT Thread (64-core @ 5.2GHz):**
- PPU emulation: <1ms per frame
- Buffer swap: <1μs (atomic operations only)
- Frame notification: <100ns (eventfd write)

**Display Thread:**
- libxev callback latency: <1ms (eventfd read)
- GPU texture upload: <500μs (256×240×4 = 240KB via PCI-E)
- Vulkan present: 16.67ms @ 60Hz (blocks on vsync)

**Frame Budget @ 60Hz:** 16.67ms total
- PPU: 1ms (6%)
- Upload: 0.5ms (3%)
- Present: 16.67ms (vsync wait)
- **Headroom:** 15ms for future features

## RT-Safety Validation

✅ **TripleBuffer operations:**
- `getBackBuffer()` - Atomic load only
- `swapBuffers()` - Memory fence + atomic stores
- `signalFrameReady()` - eventfd write (syscall, but non-blocking)

✅ **No allocations on hot path:**
- 3 buffers pre-allocated at init (3×240KB)
- libxev async handle allocated once

✅ **No blocking on hot path:**
- All atomic operations are lock-free
- eventfd write never blocks (returns EAGAIN if full, acceptable)

## References

1. **libxev Source:**
   - `~/Projects/project_z/libxev/src/watcher/async.zig` - Async implementation
   - `~/Projects/project_z/libxev/examples/async.c` - Usage example
   - `~/Projects/project_z/libxev/src/bench/async1.zig` - Performance benchmark

2. **zzt-backup Patterns:**
   - `~/Projects/project_z/zzt-backup/src/lib/core/video/vulkan/mailbox.zig` - Event mailbox
   - `~/Projects/project_z/zzt-backup/src/bin/zzt_bin.zig` - Main loop integration

3. **Vulkan:**
   - VK_KHR_wayland_surface extension
   - VK_KHR_swapchain extension (FIFO present mode for vsync)

4. **Wayland:**
   - XDG Shell protocol
   - wl_surface + wl_compositor

## Design Principles Summary

1. **Triple Buffering** - Industry-standard pattern for RT video frame passing
2. **Lock-Free Atomic Swapping** - No mutexes, no blocking, pre-allocated buffers
3. **libxev Natural Integration** - Event-driven, not manual polling
4. **Standard Terminology** - Triple buffer, atomic indices, event loop (no made-up names)
5. **Zero Allocations** - All buffers pre-allocated (3×240KB)
6. **Zero Blocking** - RT thread never waits for display
7. **Hardware Accurate** - Captures PPU state as-is (tearing acceptable for PAL/NTSC mismatch)
8. **Latest-Frame Semantics** - Always display most recent complete frame (not FIFO)
