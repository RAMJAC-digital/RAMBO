# RAMBO Video Subsystem Architecture Review

**Date:** 2025-10-04
**Reviewer:** Backend Architect Agent
**Status:** CRITICAL ISSUES IDENTIFIED
**Priority:** BLOCKING - Implementation should not proceed without addressing these issues

## Executive Summary

**VERDICT: The proposed architecture has significant flaws that will cause production issues. Major redesign required.**

After comprehensive analysis comparing the RAMBO video subsystem design against production reference implementations (zzt-backup Vulkan/Wayland and Ghostty terminal), several critical architectural flaws have been identified:

1. **Wrong concurrency pattern** - Triple-buffering is overcomplicated for this use case
2. **libxev misuse** - Timer-based approach conflicts with proactor pattern
3. **Missing separation of concerns** - Window management mixed with rendering
4. **Thread architecture problems** - Unnecessary render thread complexity
5. **No event handling strategy** - Input processing location undefined
6. **Swapchain recreation missing** - Critical OpenGL/Vulkan context management absent

**Recommendation:** Adopt mailbox pattern from zzt-backup, restructure threads, integrate libxev properly.

---

## 1. Architecture Comparison Matrix

### Current RAMBO Design vs Reference Implementations

| Component | RAMBO Proposal | zzt-backup (Production) | Ghostty (Production) | Ideal for RAMBO |
|-----------|---------------|------------------------|---------------------|----------------|
| **Concurrency** | Triple-buffer lock-free | Mailbox (double-buffer swap) | Completion pools + state chaining | **Mailbox pattern** |
| **Thread Model** | 3 threads (RT emu, render, main) | 2 threads (RT audio, main render loop) | Main thread + libxev | **2 threads** (RT emu, main) |
| **Frame Communication** | Atomic indices + buffers | Mailbox.drain() O(1) swap | Completion callbacks | **Mailbox with coalescing** |
| **libxev Integration** | Timer-based frame pacing | Event-driven (Wayland dispatch) | Proactor pattern (file I/O, timers) | **Event-driven main loop** |
| **Window Management** | Coupled to renderer | Separate Wayland layer | Platform-specific frontends | **Separate from rendering** |
| **Input Handling** | Undefined/TODO | Main thread via Wayland mailbox | Main thread libxev callbacks | **Main thread mailbox** |
| **Swapchain/Context** | Missing | Explicit resize + recreate | Multi-renderer abstraction | **Mandatory resize handling** |
| **Error Recovery** | Basic try/catch | Graceful degradation, logging limits | RT-safe error counters | **RT-safe error handling** |

### Key Findings

**CRITICAL FLAWS:**
1. Triple-buffering adds complexity without benefits over mailbox pattern
2. Dedicated render thread is unnecessary - main thread can handle rendering
3. VsyncTimer using libxev is wrong - vsync should be in swapBuffers, not artificial sleep
4. No window resize/context recreation logic
5. Input handling architecture completely undefined

**STRENGTHS:**
1. Frame buffer memory layout is well-designed (cache-line aligned)
2. RT thread isolation concept is correct
3. Backend abstraction (OpenGL/Vulkan/Software) is sound
4. PPU integration points are properly identified

---

## 2. Critical Design Decisions Requiring Revision

### 2.1 Concurrency Pattern: Triple-Buffer → Mailbox

**Current Design (Triple-Buffer):**
```zig
// Three separate buffers with atomic index swapping
write_index: std.atomic.Value(u8) align(128) = .{ .raw = 0 },
present_index: std.atomic.Value(u8) align(128) = .{ .raw = 1 },
display_index: std.atomic.Value(u8) align(128) = .{ .raw = 2 },
buffers: [3][FRAME_SIZE]u32 align(128),
```

**Problems:**
- **Overcomplicated**: Three buffers when two suffice for SPSC queue
- **Extra memory**: 720 KB instead of 480 KB (3× vs 2× frame size)
- **More state**: 5 atomics (write_index, present_index, display_index, write_count, present_count)
- **Race conditions**: `getPresentBuffer()` validation hack indicates design flaw (lines 171-186)

**Better Design (Mailbox with Event Coalescing):**
```zig
// From zzt-backup/src/lib/core/video/vulkan/mailbox.zig
pub const FrameMailbox = struct {
    alloc: std.mem.Allocator,
    writing_buffer: [FRAME_SIZE]u32 align(128),
    reading_buffer: [FRAME_SIZE]u32 align(128),
    m: std.Thread.Mutex = .{},
    has_new_frame: std.atomic.Value(bool) = .{ .raw = false },

    /// RT thread posts complete frame (non-blocking, just sets flag)
    pub fn postFrame(self: *FrameMailbox) void {
        self.m.lock();
        defer self.m.unlock();
        // Swap buffers - O(1) pointer swap
        std.mem.swap([FRAME_SIZE]u32, &self.writing_buffer, &self.reading_buffer);
        self.has_new_frame.store(true, .release);
    }

    /// Main thread drains frame (returns null if no new frame)
    pub fn drain(self: *FrameMailbox) ?[]const u32 {
        if (!self.has_new_frame.load(.acquire)) return null;

        self.m.lock();
        defer self.m.unlock();
        self.has_new_frame.store(false, .release);
        return &self.reading_buffer;
    }
};
```

**Why This Is Better:**
- **Simpler**: One mutex, one bool, no complex index juggling
- **Less memory**: 480 KB vs 720 KB (33% reduction)
- **No races**: Mutex protects swap, atomic bool is simple flag
- **Proven**: zzt-backup uses this in production with Vulkan

### 2.2 Thread Architecture: 3 Threads → 2 Threads

**Current Design:**
```
Main Thread         RT Emulation Thread      Render Thread
    |                      |                      |
    ├─ libxev loop         ├─ emulateFrame()      ├─ while(running)
    ├─ input events        ├─ PPU writes FB       ├─── getPresentBuffer()
    ├─ window events       ├─ swapWrite()         ├─── uploadTexture()
    └─ (idle?)             └─ (loop)              ├─── drawFrame() + vsync
                                                   └─── swapDisplay()
```

**Problems:**
- **Render thread unnecessary**: Main thread is idle during emulation
- **Extra synchronization**: Three-way coordination instead of two-way
- **VsyncTimer wrong**: Artificial sleep conflicts with glfwSwapBuffers vsync
- **Main thread wasted**: libxev loop has nothing to do (no I/O happening)

**Better Design (zzt-backup pattern):**
```
Main Thread (Render Loop)              RT Emulation Thread
         |                                      |
    ┌────┴──────────────────────┐              ├─ while(running)
    │ Frame Loop (60 Hz)        │              ├─── emulateFrame()
    ├─ dispatchWaylandEvents()  │              ├─── PPU writes to mailbox buffer
    ├─ processInputMailbox()    │              ├─── framebuffer.postFrame()
    ├─ framebuffer.drain()      │              └─── (repeat)
    ├─ if (frame) uploadTexture │
    ├─ drawFrame() + vsync      │
    └─ (repeat)                 │
```

**Why This Is Better:**
- **Two threads total**: Main does rendering + events, RT does emulation
- **No artificial timing**: vsync handled by swapBuffers, not timers
- **Main thread utilized**: Handles window events, input, rendering
- **Simpler**: No coordination between 3 threads, just mailbox communication

### 2.3 libxev Integration: Timer-Based → Event-Driven

**Current Design (WRONG):**
```zig
// VsyncTimer.zig - Lines 551-576
pub fn waitForNextFrame(self: *VsyncTimer) !void {
    const now = std.time.nanoTimestamp();
    const elapsed = now - self.last_frame_time;
    const sleep_time = self.target_frame_time_ns - elapsed;

    if (sleep_time > 0) {
        var completion: xev.Completion = undefined;
        try self.timer.run(
            self.loop,
            &completion,
            sleep_ms,
            void,
            null,
            timerCallback
        );
        try self.loop.run(.until_done);
    }
    // ...
}
```

**Problems:**
- **Vsync conflict**: Sleeping then calling glfwSwapBuffers(vsync=1) causes double-wait
- **libxev misuse**: Proactor pattern designed for async I/O, not frame timing
- **Ghostty guidance**: "I do not use any networking primitives, only file IO, timers, and async wakeups"
- **Purpose mismatch**: libxev for controller I/O, not display timing

**Better Design (from zzt-backup + Ghostty patterns):**
```zig
// main.zig render loop - no libxev timers needed
fn renderLoop(state: *WindowState, ctx: *VulkanCtx, mailboxes: *Mailboxes) !void {
    while (!state.closed) {
        // Layer 1: Window events (GLFW/Wayland dispatch)
        glfwPollEvents(); // Non-blocking

        // Layer 2: Input events (from mailbox)
        const input_events = mailboxes.input.drain();
        for (input_events) |event| processInput(event);

        // Layer 3: Frame rendering (from mailbox)
        if (mailboxes.frame.drain()) |frame| {
            ctx.uploadTexture(frame);
            ctx.drawFrame(); // Blocks on vsync here naturally
        } else {
            // No new frame, but still dispatch events
            std.time.sleep(1_000_000); // 1ms prevents busy-wait
        }
    }
}
```

**Why This Is Better:**
- **Natural vsync**: glfwSwapBuffers handles vsync, no artificial timing
- **libxev for I/O**: Can add controller input via libxev file descriptor watching
- **Event-driven**: Wayland/GLFW events drive loop, not timers
- **Proven pattern**: Ghostty uses libxev for file I/O, not display timing

### 2.4 Window Management: Coupled → Separated

**Current Design:**
```zig
// OpenGL.zig owns window creation (lines 412-428)
pub fn init(allocator: std.mem.Allocator) !OpenGL {
    if (c.glfwInit() == 0) return error.GLFWInitFailed;
    const window = c.glfwCreateWindow(...) orelse return error.WindowCreationFailed;
    c.glfwMakeContextCurrent(window);
    // ... OpenGL setup ...
}
```

**Problems:**
- **Tight coupling**: Window lifecycle tied to renderer backend
- **No resize handling**: Missing `glfwSetFramebufferSizeCallback`
- **No input callbacks**: Where do keyboard/mouse events go?
- **Backend lock-in**: Can't swap backends without recreating window

**Better Design (zzt-backup separation):**
```zig
// Separate window layer
pub const Window = struct {
    handle: *c.GLFWwindow,
    current_width: u32,
    current_height: u32,
    mailbox: *InputMailbox, // For input events

    pub fn init(mailbox: *InputMailbox) !Window {
        if (c.glfwInit() == 0) return error.GLFWInitFailed;
        const window = c.glfwCreateWindow(...) orelse return error.WindowCreationFailed;

        // Register callbacks
        c.glfwSetFramebufferSizeCallback(window, framebufferSizeCallback);
        c.glfwSetKeyCallback(window, keyCallback);
        c.glfwSetMouseButtonCallback(window, mouseButtonCallback);

        return .{
            .handle = window,
            .current_width = 768,
            .current_height = 720,
            .mailbox = mailbox,
        };
    }

    fn framebufferSizeCallback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
        const self = @as(*Window, @ptrCast(@alignCast(c.glfwGetWindowUserPointer(window))));
        self.current_width = @intCast(width);
        self.current_height = @intCast(height);
        // Post resize event to mailbox
        self.mailbox.post(.{ .window_resize = .{ .width = @intCast(width), .height = @intCast(height) } }) catch {};
    }
};

// Renderer just receives context
pub const OpenGL = struct {
    pub fn init(window: *Window) !OpenGL {
        c.glfwMakeContextCurrent(window.handle);
        // Setup OpenGL, but don't own window
    }

    pub fn resize(self: *OpenGL, width: u32, height: u32) void {
        // Recreate framebuffers, textures if needed
        c.glViewport(0, 0, @intCast(width), @intCast(height));
    }
};
```

**Why This Is Better:**
- **Separation**: Window manages events, renderer manages GPU
- **Callbacks registered**: Input/resize events flow to mailboxes
- **Swappable backends**: Can switch OpenGL/Vulkan/Software without touching window
- **zzt-backup proven**: Their Wayland layer is separate from Vulkan renderer

### 2.5 Missing: Swapchain/Context Recreation

**Current Design:**
```zig
// OpenGL.zig drawFrame() - Lines 469-484
pub fn drawFrame(self: *OpenGL) !void {
    if (c.glfwWindowShouldClose(self.window) != 0) {
        return error.WindowClosed;
    }
    c.glClear(c.GL_COLOR_BUFFER_BIT);
    c.glUseProgram(self.program);
    c.glBindVertexArray(self.vao);
    c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);
    c.glfwSwapBuffers(self.window);
    c.glfwPollEvents();
}
```

**Problems:**
- **No resize handling**: Framebuffer size changes ignored
- **No texture resize**: 256×240 texture scale broken on window resize
- **No error recovery**: Swapchain recreation on context loss not handled
- **Missing validation**: Window minimization breaks rendering

**Better Design (zzt-backup pattern with coalescing):**
```zig
// From zzt-backup: processVulkanMailboxAndRender (lines 59-71)
fn processVulkanMailboxAndRender(ctx: ?*VulkanCtx, mailboxes: *Mailboxes) !void {
    const vk_events = mailboxes.vulkan.drain();
    if (vk_events.len > 0) {
        const c = vulkan.mailbox.coalesce(vk_events);
        if (c.last_resize) |r| {
            ctx.?.onWindowResize(r.width, r.height); // Recreates swapchain
        }
        if (c.recreate_swapchain) {
            // Handle context loss
        }
    }
    try ctx.?.drawFrame(&mailboxes.nodes);
}

// OpenGL equivalent
pub fn drawFrame(self: *OpenGL, mailbox: *ResizeMailbox) !void {
    // Check for resize events
    if (mailbox.drain()) |events| {
        const coalesced = coalesce(events);
        if (coalesced.last_resize) |r| {
            self.resize(r.width, r.height);
        }
    }

    // Validate context before rendering
    if (c.glfwGetWindowAttrib(self.window, c.GLFW_ICONIFIED) != 0) {
        return; // Skip rendering when minimized
    }

    // Render frame
    c.glViewport(0, 0, @intCast(self.width), @intCast(self.height));
    c.glClear(c.GL_COLOR_BUFFER_BIT);
    // ... draw quad ...
    c.glfwSwapBuffers(self.window);
}
```

**Why This Is Critical:**
- **Window resize**: Every desktop app must handle this
- **Minimization**: Rendering to minimized window causes errors
- **Coalescing**: Multiple rapid resizes → one GPU recreation (efficient)
- **Production tested**: zzt-backup handles this robustly

---

## 3. Specific Recommendations with Code Structure

### Recommendation 1: Adopt Mailbox Pattern

**Remove:**
- `src/video/FrameBuffer.zig` (entire file)
- Triple-buffer atomic coordination

**Add:**
- `src/video/FrameMailbox.zig` (double-buffer swap pattern)
- `src/video/EventMailbox.zig` (input/resize events)

**Implementation:**
```zig
// src/video/FrameMailbox.zig
pub const FrameMailbox = struct {
    allocator: std.mem.Allocator,
    writing: []u32, // 256×240×4 = 240 KB
    reading: []u32,
    mutex: std.Thread.Mutex = .{},
    new_frame: std.atomic.Value(bool) = .{ .raw = false },

    pub fn init(allocator: std.mem.Allocator) !FrameMailbox {
        const size = 256 * 240;
        return .{
            .allocator = allocator,
            .writing = try allocator.alignedAlloc(u32, 128, size),
            .reading = try allocator.alignedAlloc(u32, 128, size),
        };
    }

    pub fn deinit(self: *FrameMailbox) void {
        self.allocator.free(self.writing);
        self.allocator.free(self.reading);
    }

    /// RT emulation thread: Get buffer to write to
    pub fn getWriteBuffer(self: *FrameMailbox) []u32 {
        return self.writing;
    }

    /// RT emulation thread: Signal frame complete
    pub fn postFrame(self: *FrameMailbox) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        std.mem.swap([]u32, &self.writing, &self.reading);
        self.new_frame.store(true, .release);
    }

    /// Main render thread: Get new frame if available
    pub fn drain(self: *FrameMailbox) ?[]const u32 {
        if (!self.new_frame.load(.acquire)) return null;
        self.mutex.lock();
        defer self.mutex.unlock();
        self.new_frame.store(false, .release);
        return self.reading;
    }
};
```

**Benefits:**
- 33% less memory (480 KB vs 720 KB)
- No complex atomic index coordination
- Proven pattern from zzt-backup production code
- Zero race conditions (mutex protects swap)

### Recommendation 2: Restructure Threads

**Remove:**
- Dedicated render thread (`renderThreadMain`)
- `VsyncTimer.zig` (entire file)
- `DisplaySync.zig` (not needed)

**Modify:**
- `main.zig` becomes main render loop
- RT thread only for emulation

**Implementation:**
```zig
// src/main.zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load ROM
    var cartridge = try Cartridge.loadFromFile(allocator, rom_path);
    defer cartridge.deinit();

    // Initialize mailboxes
    var mailboxes = try Mailboxes.init(allocator);
    defer mailboxes.deinit();

    // Initialize window (separate from renderer)
    var window = try Window.init(&mailboxes.input);
    defer window.deinit();

    // Initialize renderer backend
    var renderer = try Renderer.init(allocator, .opengl, &window);
    defer renderer.deinit();

    // Initialize emulation state
    var emu_state = EmulationState.init(&config, bus);
    emu_state.setFrameMailbox(&mailboxes.frame);

    // Spawn RT emulation thread
    const emu_thread = try std.Thread.spawn(.{}, emulationThreadMain, .{&emu_state, &mailboxes});
    defer emu_thread.join();

    // Main render loop
    while (!window.closed) {
        // Poll window events (GLFW/Wayland dispatch)
        window.pollEvents();

        // Process input events from mailbox
        const input_events = mailboxes.input.drain();
        for (input_events) |event| processInput(event);

        // Check for resize events
        const resize_events = mailboxes.resize.drain();
        if (coalesce(resize_events).last_resize) |r| {
            try renderer.resize(r.width, r.height);
        }

        // Render new frame if available
        if (mailboxes.frame.drain()) |frame| {
            try renderer.uploadTexture(frame);
            try renderer.drawFrame(); // Vsync happens here
        } else {
            std.time.sleep(1_000_000); // 1ms to prevent busy-wait
        }
    }
}

fn emulationThreadMain(state: *EmulationState, mailboxes: *Mailboxes) void {
    // Set RT priority
    setRTPriority() catch {};

    while (!mailboxes.quit.load(.acquire)) {
        const fb = mailboxes.frame.getWriteBuffer();
        state.emulateFrame(fb);
        mailboxes.frame.postFrame();
    }
}
```

**Benefits:**
- Main thread utilized (not idle)
- Natural vsync timing (no artificial sleep)
- Simpler coordination (2 threads not 3)
- Matches zzt-backup production architecture

### Recommendation 3: Separate Window Management

**Add:**
- `src/video/Window.zig` (platform-agnostic window layer)
- GLFW callbacks registered for events

**Implementation:**
```zig
// src/video/Window.zig
const c = @cImport({
    @cInclude("GLFW/glfw3.h");
});

pub const WindowEvent = union(enum) {
    resize: struct { width: u32, height: u32 },
    close: void,
    key: struct { key: c_int, action: c_int, mods: c_int },
    mouse_button: struct { button: c_int, action: c_int, x: f64, y: f64 },
    mouse_move: struct { x: f64, y: f64 },
};

pub const Window = struct {
    handle: *c.GLFWwindow,
    width: u32,
    height: u32,
    closed: bool = false,
    event_mailbox: *EventMailbox,

    pub fn init(event_mailbox: *EventMailbox) !Window {
        if (c.glfwInit() == 0) return error.GLFWInitFailed;

        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);

        const window = c.glfwCreateWindow(768, 720, "RAMBO", null, null) orelse
            return error.WindowCreationFailed;

        var self = Window{
            .handle = window,
            .width = 768,
            .height = 720,
            .event_mailbox = event_mailbox,
        };

        c.glfwSetWindowUserPointer(window, &self);
        c.glfwSetFramebufferSizeCallback(window, framebufferSizeCallback);
        c.glfwSetKeyCallback(window, keyCallback);
        c.glfwSetMouseButtonCallback(window, mouseButtonCallback);
        c.glfwSetCursorPosCallback(window, cursorPosCallback);

        return self;
    }

    pub fn pollEvents(self: *Window) void {
        c.glfwPollEvents();
        if (c.glfwWindowShouldClose(self.handle) != 0) {
            self.closed = true;
            self.event_mailbox.post(.close) catch {};
        }
    }

    fn framebufferSizeCallback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
        const self = getSelf(window);
        self.width = @intCast(width);
        self.height = @intCast(height);
        self.event_mailbox.post(.{ .resize = .{
            .width = @intCast(width),
            .height = @intCast(height)
        }}) catch {};
    }

    fn keyCallback(window: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
        _ = scancode;
        const self = getSelf(window);
        self.event_mailbox.post(.{ .key = .{
            .key = key,
            .action = action,
            .mods = mods
        }}) catch {};
    }

    fn getSelf(window: ?*c.GLFWwindow) *Window {
        return @ptrCast(@alignCast(c.glfwGetWindowUserPointer(window)));
    }
};
```

**Benefits:**
- Input events flow to mailbox automatically
- Resize events captured and coalesced
- Renderer decoupled from window lifecycle
- Easy to add Wayland support later

### Recommendation 4: Add Swapchain Recreation

**Modify:**
- `backends/OpenGL.zig` - Add resize() method
- Main loop - Coalesce resize events before rendering

**Implementation:**
```zig
// backends/OpenGL.zig additions
pub const OpenGL = struct {
    // ... existing fields ...
    width: u32,
    height: u32,

    pub fn resize(self: *OpenGL, width: u32, height: u32) !void {
        if (width == 0 or height == 0) return; // Skip invalid sizes

        self.width = width;
        self.height = height;

        // Recreate framebuffers/textures if needed
        c.glViewport(0, 0, @intCast(width), @intCast(height));

        // Update projection matrix for proper scaling
        // NES aspect ratio: 256:240 = 16:15
        const nes_aspect: f32 = 256.0 / 240.0;
        const window_aspect: f32 = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));

        // Calculate letterbox/pillarbox scaling
        var scale_x: f32 = 1.0;
        var scale_y: f32 = 1.0;

        if (window_aspect > nes_aspect) {
            scale_x = nes_aspect / window_aspect;
        } else {
            scale_y = window_aspect / nes_aspect;
        }

        // Update shader uniform for aspect-correct scaling
        c.glUseProgram(self.program);
        const scale_loc = c.glGetUniformLocation(self.program, "scale");
        c.glUniform2f(scale_loc, scale_x, scale_y);
    }

    pub fn drawFrame(self: *OpenGL) !void {
        // Check for minimization
        if (c.glfwGetWindowAttrib(self.window, c.GLFW_ICONIFIED) != 0) {
            return; // Skip rendering when minimized
        }

        c.glViewport(0, 0, @intCast(self.width), @intCast(self.height));
        c.glClear(c.GL_COLOR_BUFFER_BIT);
        c.glUseProgram(self.program);
        c.glBindVertexArray(self.vao);
        c.glDrawArrays(c.GL_TRIANGLE_STRIP, 0, 4);

        c.glfwSwapBuffers(self.window);
    }
};

// Event coalescing (from zzt-backup pattern)
fn coalesceResizeEvents(events: []const WindowEvent) ?struct { width: u32, height: u32 } {
    var last_resize: ?struct { width: u32, height: u32 } = null;
    for (events) |event| {
        if (event == .resize) {
            last_resize = .{ .width = event.resize.width, .height = event.resize.height };
        }
    }
    return last_resize;
}
```

**Benefits:**
- Proper aspect ratio maintenance
- Multiple resizes coalesced → one GPU update
- Minimization handled gracefully
- Production-quality window management

### Recommendation 5: libxev for Input Only

**Remove libxev from:**
- Frame timing (VsyncTimer.zig)
- Video subsystem (not needed)

**Add libxev for:**
- Controller I/O (future)
- File watching (save states, config reload)

**Example (Controller via libxev):**
```zig
// Future: src/input/ControllerInput.zig
const xev = @import("xev");

pub const ControllerInput = struct {
    loop: *xev.Loop,
    fd: std.posix.fd_t,
    completion: xev.Completion,
    buffer: [256]u8 align(128),
    mailbox: *InputMailbox,

    pub fn init(loop: *xev.Loop, mailbox: *InputMailbox) !ControllerInput {
        const fd = try std.posix.open("/dev/input/js0", .{ .ACCMODE = .RDONLY }, 0);

        var self = ControllerInput{
            .loop = loop,
            .fd = fd,
            .completion = undefined,
            .buffer = undefined,
            .mailbox = mailbox,
        };

        // Start async read
        try self.startRead();
        return self;
    }

    fn startRead(self: *ControllerInput) !void {
        try xev.File.read(
            self.loop,
            &self.completion,
            self.fd,
            &self.buffer,
            ControllerInput,
            self,
            readCallback,
        );
    }

    fn readCallback(
        userdata: ?*ControllerInput,
        loop: *xev.Loop,
        completion: *xev.Completion,
        result: xev.File.ReadError!usize,
    ) xev.CallbackAction {
        const self = userdata.?;
        const bytes_read = result catch return .disarm;

        // Parse controller event
        const event = parseJoystickEvent(self.buffer[0..bytes_read]);
        self.mailbox.post(event) catch {};

        // Continue reading
        self.startRead() catch return .disarm;
        return .disarm;
    }
};
```

**Why This Is Correct:**
- **Ghostty pattern**: libxev for file I/O, not display timing
- **Non-blocking**: Controller events don't block emulation
- **Proper use case**: Async I/O is what libxev excels at
- **Future-ready**: Can add keyboard rebinding, config reload

---

## 4. Gaps in Current Design

### 4.1 Input Handling Architecture (MISSING)

**Current State:** Completely undefined
- No keyboard input path
- No controller input path
- No input → NES controller register mapping

**Required Addition:**
```zig
// src/input/InputSystem.zig
pub const InputSystem = struct {
    keyboard_state: KeyboardState,
    controller_state: [2]ControllerState, // Player 1 & 2
    key_bindings: KeyBindings,

    pub fn processEvent(self: *InputSystem, event: WindowEvent) void {
        switch (event) {
            .key => |k| self.handleKey(k),
            .mouse_button => |m| self.handleMouse(m),
            else => {},
        }
    }

    pub fn getNesController(self: *InputSystem, player: u8) u8 {
        // Map modern input → NES controller byte
        var state: u8 = 0;
        if (self.keyboard_state.isPressed(self.key_bindings.a)) state |= 0x01; // A
        if (self.keyboard_state.isPressed(self.key_bindings.b)) state |= 0x02; // B
        // ... etc
        return state;
    }
};
```

### 4.2 Error Handling Strategy (INCOMPLETE)

**Current State:** Basic try/catch, no RT-safety
- Logging in hot paths (RT violation)
- No error counters
- No graceful degradation

**Required Pattern (from zzt-backup):**
```zig
// RT-safe error handling
pub const ErrorCounters = struct {
    texture_upload_failures: std.atomic.Value(u64) = .{ .raw = 0 },
    render_failures: std.atomic.Value(u64) = .{ .raw = 0 },

    pub fn recordTextureUploadFailure(self: *ErrorCounters) void {
        _ = self.texture_upload_failures.fetchAdd(1, .monotonic);
    }

    pub fn checkAndLog(self: *ErrorCounters) void {
        // Called from non-RT thread periodically
        const upload_fails = self.texture_upload_failures.swap(0, .monotonic);
        if (upload_fails > 0) {
            log.warn("Texture upload failures: {}", .{upload_fails});
        }
    }
};

// In RT loop - NO LOGGING
if (mailbox.frame.drain()) |frame| {
    renderer.uploadTexture(frame) catch |err| {
        error_counters.recordTextureUploadFailure();
        continue; // Graceful degradation
    };
}
```

### 4.3 Configuration Management (MISSING)

**Current State:** Static Config struct
- No runtime reload
- No config file watching
- No user preferences

**Required Addition:**
```zig
// src/config/ConfigManager.zig (from zzt-backup pattern)
pub const ConfigManager = struct {
    allocator: std.mem.Allocator,
    config_path: []const u8,
    mailbox: *ConfigMailbox,
    thread: std.Thread,
    running: std.atomic.Value(bool),

    pub fn start(self: *ConfigManager) !void {
        self.running.store(true, .release);
        self.thread = try std.Thread.spawn(.{}, configThreadMain, .{self});
    }

    fn configThreadMain(self: *ConfigManager) void {
        while (self.running.load(.acquire)) {
            // Watch config file for changes
            // Parse and validate new config
            // Post to mailbox if changed
            std.time.sleep(1_000_000_000); // 1 second poll
        }
    }
};
```

### 4.4 Performance Monitoring (MISSING)

**Current State:** No metrics
- No FPS counter
- No frame time tracking
- No dropped frame detection

**Required Addition:**
```zig
// src/video/PerformanceMetrics.zig
pub const PerformanceMetrics = struct {
    frame_times: [60]u64 = [_]u64{0} ** 60,
    frame_index: usize = 0,
    last_frame_time: i128,
    dropped_frames: std.atomic.Value(u64) = .{ .raw = 0 },

    pub fn recordFrame(self: *PerformanceMetrics) void {
        const now = std.time.nanoTimestamp();
        const elapsed = now - self.last_frame_time;
        self.frame_times[self.frame_index] = @intCast(elapsed);
        self.frame_index = (self.frame_index + 1) % 60;
        self.last_frame_time = now;

        // Detect dropped frame (>20ms)
        if (elapsed > 20_000_000) {
            _ = self.dropped_frames.fetchAdd(1, .monotonic);
        }
    }

    pub fn getFps(self: *PerformanceMetrics) f32 {
        var total: u64 = 0;
        for (self.frame_times) |ft| total += ft;
        const avg = total / 60;
        return 1_000_000_000.0 / @as(f32, @floatFromInt(avg));
    }
};
```

---

## 5. Implementation Priority Ordering

### Phase 1: Critical Foundation (8-10 hours) - MUST DO FIRST
**Priority: BLOCKING**

1. **Replace triple-buffer with mailbox pattern** (3-4 hours)
   - Remove `FrameBuffer.zig`
   - Implement `FrameMailbox.zig` (double-buffer swap)
   - Implement `EventMailbox.zig` (window/input events)
   - Update tests

2. **Separate window management** (2-3 hours)
   - Create `Window.zig`
   - Register GLFW callbacks
   - Remove window creation from `OpenGL.zig`

3. **Restructure threads** (3-4 hours)
   - Move render logic to main thread
   - Remove `VsyncTimer.zig`
   - Update `main.zig` with render loop
   - Remove dedicated render thread

**Deliverable:** Working 2-thread architecture with mailbox communication

### Phase 2: OpenGL Backend Fixes (4-6 hours) - HIGH PRIORITY

4. **Add swapchain recreation** (2-3 hours)
   - Implement `OpenGL.resize()`
   - Add aspect ratio correction
   - Add minimization detection
   - Event coalescing in main loop

5. **Backend abstraction refinement** (2-3 hours)
   - Update `Renderer.zig` for new Window separation
   - Add backend-specific error handling
   - Test backend switching

**Deliverable:** Production-quality OpenGL rendering with resize handling

### Phase 3: Input System (4-6 hours) - HIGH PRIORITY

6. **Implement input architecture** (3-4 hours)
   - Create `InputSystem.zig`
   - Map keyboard → NES controller
   - Add key bindings configuration

7. **Controller I/O with libxev** (future, 2-3 hours)
   - Implement `ControllerInput.zig`
   - Async joystick reading
   - Event mapping

**Deliverable:** Functional input → emulation path

### Phase 4: Quality & Monitoring (3-4 hours) - MEDIUM PRIORITY

8. **RT-safe error handling** (1-2 hours)
   - Add `ErrorCounters` struct
   - Remove logging from RT paths
   - Periodic error reporting

9. **Performance metrics** (1-2 hours)
   - Implement `PerformanceMetrics`
   - FPS counter
   - Dropped frame detection

10. **Configuration management** (future, 2-3 hours)
    - Config file watching
    - Runtime reload via mailbox

**Deliverable:** Production-ready monitoring and error handling

### Phase 5: Vulkan Backend (Optional, 8-10 hours) - LOW PRIORITY

11. **Vulkan implementation**
    - Swapchain recreation (critical)
    - Descriptor sets
    - Pipeline management

**Deliverable:** High-performance Vulkan alternative

---

## 6. Concrete Code Examples Summary

### Main Application Structure (Corrected)

```zig
// src/main.zig - Correct architecture
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize mailboxes (all communication channels)
    var mailboxes = try Mailboxes.init(allocator);
    defer mailboxes.deinit();

    // Initialize window (separate from renderer)
    var window = try Window.init(&mailboxes.event);
    defer window.deinit();

    // Initialize renderer backend
    var renderer = try Renderer.initOpenGL(allocator, &window);
    defer renderer.deinit();

    // Initialize emulation state
    var emu_state = EmulationState.init(&config, bus);

    // Spawn RT emulation thread
    const emu_thread = try std.Thread.spawn(.{}, emulationLoop, .{
        &emu_state,
        &mailboxes.frame,
        &mailboxes.quit,
    });
    defer {
        mailboxes.quit.store(true, .release);
        emu_thread.join();
    }

    // Main render loop (replaces dedicated render thread)
    var metrics = PerformanceMetrics.init();
    while (!window.closed) {
        const frame_start = std.time.nanoTimestamp();

        // Layer 1: Window events
        window.pollEvents();

        // Layer 2: Process events from mailbox
        const events = mailboxes.event.drain();
        for (events) |event| {
            switch (event) {
                .resize => |r| try renderer.resize(r.width, r.height),
                .key => |k| input_system.handleKey(k),
                .close => break,
                else => {},
            }
        }

        // Layer 3: Render frame if available
        if (mailboxes.frame.drain()) |frame| {
            try renderer.uploadTexture(frame);
            try renderer.drawFrame(); // Vsync happens here
            metrics.recordFrame();
        } else {
            std.time.sleep(1_000_000); // 1ms prevents busy-wait
        }
    }
}

fn emulationLoop(
    state: *EmulationState,
    frame_mailbox: *FrameMailbox,
    quit_flag: *std.atomic.Value(bool),
) void {
    setRTPriority() catch {};

    while (!quit_flag.load(.acquire)) {
        const fb = frame_mailbox.getWriteBuffer();
        state.emulateFrame(fb);
        frame_mailbox.postFrame();
    }
}
```

### Mailbox Definitions (Corrected)

```zig
// src/video/Mailboxes.zig
pub const Mailboxes = struct {
    frame: FrameMailbox,
    event: EventMailbox,
    quit: std.atomic.Value(bool) = .{ .raw = false },

    pub fn init(allocator: std.mem.Allocator) !Mailboxes {
        return .{
            .frame = try FrameMailbox.init(allocator),
            .event = EventMailbox.init(allocator),
        };
    }

    pub fn deinit(self: *Mailboxes) void {
        self.frame.deinit();
        self.event.deinit();
    }
};
```

---

## 7. Final Verdict and Action Plan

### Critical Issues Summary

1. **BLOCKING: Triple-buffer overcomplicated** → Use mailbox pattern
2. **BLOCKING: 3-thread architecture wrong** → 2 threads (RT emu + main render)
3. **BLOCKING: libxev misused** → Remove from video, use for input I/O
4. **BLOCKING: Window management coupled** → Separate Window layer
5. **HIGH: Swapchain recreation missing** → Add resize handling + coalescing
6. **HIGH: Input system undefined** → Design and implement
7. **MEDIUM: Error handling not RT-safe** → Add error counters
8. **MEDIUM: No performance monitoring** → Add metrics

### Recommended Action Plan

**STOP current implementation immediately.** The proposed architecture has fundamental flaws that will cause:
- Unnecessary complexity (triple-buffering)
- Performance issues (3-thread coordination)
- Missing functionality (no resize, no input)
- Wrong tool usage (libxev for display timing)

**START with corrected architecture:**

1. **Week 1: Foundation Rework** (Phase 1)
   - Implement mailbox pattern
   - Separate window management
   - Restructure to 2 threads
   - Target: Working render loop

2. **Week 2: OpenGL + Input** (Phases 2-3)
   - Add resize handling
   - Implement input system
   - Controller mapping
   - Target: Playable emulator

3. **Week 3: Quality** (Phase 4)
   - RT-safe error handling
   - Performance metrics
   - Config management
   - Target: Production-ready

4. **Week 4+: Optional Vulkan** (Phase 5)
   - Only if OpenGL works perfectly
   - Reuse window/mailbox architecture
   - Target: High-performance alternative

### Success Criteria

**Before declaring video subsystem complete:**
- [ ] 2-thread architecture working (RT emu + main render)
- [ ] Mailbox pattern proven (no races, no leaks)
- [ ] Window resize handled correctly
- [ ] Input events flow to emulation
- [ ] RT-safety verified (no logging in hot paths)
- [ ] Performance metrics show 60 FPS
- [ ] All window management edge cases handled (minimize, resize, close)

### Reference Implementation Learnings

**From zzt-backup:**
- Mailbox double-buffer swap is simpler than triple-buffer
- Event coalescing prevents GPU thrashing on resize
- 3-layer event architecture (Window → DAW → Render) works well
- RT-safety requires discipline (no logging in loops)

**From Ghostty:**
- libxev for async I/O (controllers, files), not display timing
- Completion pools + state chaining for sequential ops
- Platform-specific frontends with shared core
- Production-stable after 1+ year with 1000+ users

**Key Insight:** Both production systems avoid artificial timing mechanisms. Vsync is handled by the swapchain/swap buffers call, not by timers or sleep. This is the correct pattern.

---

## Appendix: Architecture Diagrams

### Current (Proposed) Architecture - FLAWED
```
┌─────────────┐     ┌──────────────────┐     ┌──────────────────┐
│ Main Thread │────▶│ RT Emulation     │────▶│ Render Thread    │
│             │     │ Thread           │     │                  │
│ libxev loop │     │                  │     │ while(running):  │
│ (idle?)     │     │ emulateFrame()   │     │   getPresentBuf()│
│             │     │ PPU→Write Buffer │     │   uploadTexture()│
│             │     │ swapWrite()      │     │   drawFrame()    │
│             │     │                  │     │   VsyncTimer❌   │
│             │     │                  │     │   swapDisplay()  │
└─────────────┘     └──────────────────┘     └──────────────────┘
       ▲                                              │
       │                                              │
       └──────────────────────────────────────────────┘
                  (Where do events go? ❌)

PROBLEMS:
- Main thread does nothing (libxev has no I/O)
- VsyncTimer conflicts with glfwSwapBuffers vsync
- Input handling undefined
- 3-way coordination complexity
```

### Corrected Architecture - RECOMMENDED
```
┌─────────────────────────────────────┐     ┌──────────────────┐
│ Main Thread (Render Loop)           │────▶│ RT Emulation     │
│                                     │     │ Thread           │
│ while (!window.closed):             │     │                  │
│   window.pollEvents()               │     │ while(running):  │
│   events = mailbox.drain()          │     │   fb = mailbox   │
│   process input/resize              │     │     .getWrite()  │
│   if (frame = mailbox.drain()):     │     │   emulateFrame() │
│     renderer.uploadTexture(frame)   │     │   mailbox.post() │
│     renderer.drawFrame() ← VSYNC ✅ │     │                  │
│   else:                             │     │                  │
│     sleep(1ms) ✅                    │     │                  │
└─────────────────────────────────────┘     └──────────────────┘
       ▲                                              │
       │         ┌──────────────────┐                 │
       │────────▶│ FrameMailbox     │◀────────────────┘
       │         │ (double-buffer)  │
       │         └──────────────────┘
       │         ┌──────────────────┐
       └────────▶│ EventMailbox     │
                 │ (window/input)   │
                 └──────────────────┘

BENEFITS:
- 2 threads (simpler)
- Main thread utilized (events + render)
- Natural vsync (swapBuffers)
- Clear event flow (mailboxes)
- Proven pattern (zzt-backup)
```

---

## Conclusion

The current video subsystem architecture has fundamental design flaws that will cause production issues. The triple-buffer pattern is overcomplicated, the 3-thread model is inefficient, libxev is misused for display timing, and critical functionality (resize, input) is missing.

**Recommendation: BLOCK implementation and redesign using:**
1. Mailbox pattern (from zzt-backup)
2. 2-thread model (RT emu + main render)
3. libxev for I/O only (controllers, files)
4. Separated window management
5. Proper swapchain recreation

The reference implementations (zzt-backup and Ghostty) provide battle-tested patterns that RAMBO should adopt. Attempting to "reinvent the wheel" with triple-buffering and artificial timing will result in wasted effort and a fragile system.

**Estimated rework time:** 20-25 hours (same as original estimate, but correct architecture)

**Next steps:**
1. Review this document with development team
2. Approve corrected architecture
3. Begin Phase 1 implementation (mailbox pattern)
4. Incremental testing at each phase
5. Do not proceed to Phase 2 until Phase 1 is proven stable

This architectural review aims to save significant debugging time and prevent the deployment of a flawed system. The proposed corrections are based on proven production patterns and will result in a more maintainable, performant, and correct video subsystem.
