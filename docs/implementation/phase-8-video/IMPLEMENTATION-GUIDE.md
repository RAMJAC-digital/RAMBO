# Phase 8 Implementation Guide - Video Subsystem

**Created:** 2025-10-07
**Status:** Ready for implementation
**Estimated Time:** 13-17 hours
**Prerequisites:** All documentation reviewed and approved

---

## Document Navigation

- **[THREAD-SEPARATION-VERIFICATION.md](./THREAD-SEPARATION-VERIFICATION.md)** - Thread isolation guarantees
- **[API-REFERENCE.md](./API-REFERENCE.md)** - Complete API documentation
- **This document** - Step-by-step implementation guide

---

## Implementation Philosophy

1. **Incremental:** Each phase builds and tests independently
2. **Test-Driven:** Test after each major component
3. **Reference-Based:** Copy proven patterns from zzt-backup
4. **Thread-Safe:** Verify isolation at each step

---

## Phase Overview

| Phase | Time | Deliverable | Test Method |
|-------|------|-------------|-------------|
| **Phase 1** | 3-4h | Wayland window opens | See window on screen |
| **Phase 2** | 4-5h | Vulkan renders solid color | Blue window |
| **Phase 3** | 4-5h | NES frames display | AccuracyCoin visible |
| **Phase 4** | 2-3h | Input works, aspect ratio correct | Playable |

---

## Phase 1: Wayland Window (3-4 hours)

**Goal:** Open a 512×480 Wayland window that responds to events

### Step 1.1: Create Project Structure (15 min)

```bash
mkdir -p ~/Development/RAMBO/src/video/shaders
touch ~/Development/RAMBO/src/video/Video.zig
touch ~/Development/RAMBO/src/video/WaylandState.zig
touch ~/Development/RAMBO/src/video/WaylandLogic.zig
touch ~/Development/RAMBO/src/video/VulkanState.zig
touch ~/Development/RAMBO/src/video/VulkanLogic.zig
touch ~/Development/RAMBO/src/video/shaders/fullscreen.vert
touch ~/Development/RAMBO/src/video/shaders/texture.frag
```

### Step 1.2: Implement WaylandState.zig (30 min)

**File:** `src/video/WaylandState.zig`
**Reference:** `zzt-backup/src/lib/core/video/wayland/window_wayland.zig:96-141`

```zig
//! Wayland Window State
//! Pure data structure - no logic

const std = @import("std");
const build = @import("build_options");

// Conditional Wayland imports (build-time gating)
const wayland = if (build.with_wayland) @import("wayland") else struct {};
const wl = if (build.with_wayland) wayland.client.wl else struct {};
const xdg = if (build.with_wayland) wayland.client.xdg else struct {};

const XdgWindowEventMailbox = @import("../mailboxes/XdgWindowEventMailbox.zig").XdgWindowEventMailbox;

/// Event handler context for passing state and mailbox to listeners
pub const EventHandlerContext = struct {
    state: *WaylandState,
    mailbox: *XdgWindowEventMailbox,
};

pub const WaylandState = struct {
    // Core Wayland protocol objects
    display: ?*wl.Display = null,
    registry: ?*wl.Registry = null,
    compositor: ?*wl.Compositor = null,
    wm_base: ?*xdg.WmBase = null,

    // Window surface and XDG shell
    surface: ?*wl.Surface = null,
    xdg_surface: ?*xdg.Surface = null,
    toplevel: ?*xdg.Toplevel = null,

    // Input devices
    seat: ?*wl.Seat = null,
    keyboard: ?*wl.Keyboard = null,
    pointer: ?*wl.Pointer = null,

    // Window state tracking
    current_width: u32 = 512,
    current_height: u32 = 480,
    closed: bool = false,
    is_fullscreen: bool = false,
    is_maximized: bool = false,
    is_activated: bool = true,

    // Content area from XDG configure
    content_width: u32 = 0,
    content_height: u32 = 0,

    // Pending resize (from configure events)
    pending_width: ?u32 = null,
    pending_height: ?u32 = null,

    // Mouse state
    last_x: f32 = 0,
    last_y: f32 = 0,

    // Keyboard modifiers
    mods_depressed: u32 = 0,
    mods_latched: u32 = 0,
    mods_locked: u32 = 0,
    mods_group: u32 = 0,

    // Dependency injection
    event_mailbox: *XdgWindowEventMailbox,
    allocator: std.mem.Allocator,
};
```

**Test:** File compiles without errors

---

### Step 1.3: Implement WaylandLogic.zig (2.5 hours)

**File:** `src/video/WaylandLogic.zig`
**Reference:** `zzt-backup/src/lib/core/video/wayland/window_wayland.zig:144-533`

This is the largest file. Copy patterns from zzt-backup line-by-line:

#### Section A: Imports and Helper Functions (15 min)

```zig
//! Wayland Window Logic
//! Pure functions operating on WaylandState

const std = @import("std");
const log = std.log.scoped(.wayland);
const build = @import("build_options");

const WaylandState = @import("WaylandState.zig").WaylandState;
const EventHandlerContext = @import("WaylandState.zig").EventHandlerContext;
const XdgWindowEventMailbox = @import("../mailboxes/XdgWindowEventMailbox.zig").XdgWindowEventMailbox;
const WaylandEvent = @import("../mailboxes/XdgWindowEventMailbox.zig").WaylandEvent;
const WaylandEventType = @import("../mailboxes/XdgWindowEventMailbox.zig").WaylandEventType;

const wayland = if (build.with_wayland) @import("wayland") else struct {};
const wl = if (build.with_wayland) wayland.client.wl else struct {};
const xdg = if (build.with_wayland) wayland.client.xdg else struct {};

// Helper functions to post events to mailbox
fn postResizeEvent(mailbox: *XdgWindowEventMailbox, width: u32, height: u32) void {
    const event_data = WaylandEvent.EventData{
        .window_resize = .{ .width = width, .height = height }
    };
    mailbox.postEvent(.window_resize, event_data) catch |err| {
        log.warn("Failed to post resize event: {}", .{err});
    };
}

fn postCloseEvent(mailbox: *XdgWindowEventMailbox) void {
    const event_data = WaylandEvent.EventData{ .window_close = {} };
    mailbox.postEvent(.window_close, event_data) catch |err| {
        log.warn("Failed to post close event: {}", .{err});
    };
}

fn postKeyEvent(mailbox: *XdgWindowEventMailbox, keycode: u32, modifiers: u32, pressed: bool) void {
    if (pressed) {
        const event_data = WaylandEvent.EventData{
            .key_press = .{ .keycode = keycode, .modifiers = modifiers }
        };
        mailbox.postEvent(.key_press, event_data) catch {};
    } else {
        const event_data = WaylandEvent.EventData{
            .key_release = .{ .keycode = keycode, .modifiers = modifiers }
        };
        mailbox.postEvent(.key_release, event_data) catch {};
    }
}

fn postMouseMoveEvent(mailbox: *XdgWindowEventMailbox, x: f32, y: f32) void {
    const event_data = WaylandEvent.EventData{ .mouse_move = .{ .x = x, .y = y } };
    mailbox.postEvent(.mouse_move, event_data) catch {};
}
```

**Reference:** zzt-backup:38-93

#### Section B: Protocol Listeners (1 hour)

Copy these functions from zzt-backup:339-533:

1. `registryListener` - Binds compositor, xdg_wm_base, seat
2. `wmBaseListener` - **CRITICAL:** Handles ping/pong
3. `xdgSurfaceListener` - Acknowledges configure
4. `xdgToplevelListener` - Handles resize and close
5. `keyboardListener` - Posts keyboard events
6. `pointerListener` - Posts mouse events

**Critical Pattern:**
```zig
fn wmBaseListener(wm_base: *xdg.WmBase, event: xdg.WmBase.Event, context: *EventHandlerContext) void {
    _ = context;
    switch (event) {
        .ping => |p| wm_base.pong(p.serial), // ← MUST respond!
    }
}
```

#### Section C: Public API (1 hour)

```zig
pub fn init(
    allocator: std.mem.Allocator,
    mailbox: *XdgWindowEventMailbox,
) !WaylandState {
    var state = WaylandState{
        .event_mailbox = mailbox,
        .allocator = allocator,
    };

    if (!build.with_wayland) {
        log.warn("Wayland disabled at build", .{});
        return state;
    }

    // 1. Connect to display
    const display = wl.Display.connect(null) catch |err| {
        log.err("Failed to connect to Wayland display: {}", .{err});
        return error.WaylandConnectFailed;
    };
    state.display = display;

    // 2. Get registry
    const registry = try display.getRegistry();
    state.registry = registry;

    // 3. Setup registry listener
    const registry_context = try allocator.create(EventHandlerContext);
    registry_context.* = .{ .state = &state, .mailbox = mailbox };
    registry.setListener(*EventHandlerContext, registryListener, registry_context);

    // 4. Roundtrip to bind globals
    _ = display.roundtrip();

    if (state.compositor == null or state.wm_base == null) {
        log.err("Required globals missing", .{});
        return error.WaylandGlobalsMissing;
    }

    // 5. Create surface and XDG toplevel
    const surface = try state.compositor.?.createSurface();
    state.surface = surface;

    const xdg_surface = try state.wm_base.?.getXdgSurface(surface);
    state.xdg_surface = xdg_surface;
    const xdg_context = try allocator.create(EventHandlerContext);
    xdg_context.* = .{ .state = &state, .mailbox = mailbox };
    xdg_surface.setListener(*EventHandlerContext, xdgSurfaceListener, xdg_context);

    const toplevel = try xdg_surface.getToplevel();
    state.toplevel = toplevel;
    const toplevel_context = try allocator.create(EventHandlerContext);
    toplevel_context.* = .{ .state = &state, .mailbox = mailbox };
    toplevel.setListener(*EventHandlerContext, xdgToplevelListener, toplevel_context);

    toplevel.setTitle("RAMBO NES Emulator");
    toplevel.setAppId("rambo.nes.emulator");

    // 6. Setup input devices if seat available
    if (state.seat) |seat| {
        state.keyboard = seat.getKeyboard() catch null;
        if (state.keyboard) |kb| {
            const kb_context = try allocator.create(EventHandlerContext);
            kb_context.* = .{ .state = &state, .mailbox = mailbox };
            kb.setListener(*EventHandlerContext, keyboardListener, kb_context);
        }

        state.pointer = seat.getPointer() catch null;
        if (state.pointer) |ptr| {
            const ptr_context = try allocator.create(EventHandlerContext);
            ptr_context.* = .{ .state = &state, .mailbox = mailbox };
            ptr.setListener(*EventHandlerContext, pointerListener, ptr_context);
        }
    }

    // 7. Commit initial surface
    surface.commit();
    _ = display.flush();

    log.info("Wayland window initialized", .{});
    return state;
}

pub fn deinit(state: *WaylandState) void {
    if (!build.with_wayland) return;

    if (state.pointer) |p| p.release();
    if (state.keyboard) |k| k.release();
    if (state.toplevel) |t| t.destroy();
    if (state.xdg_surface) |xs| xs.destroy();
    if (state.surface) |s| s.destroy();
    if (state.wm_base) |wm| wm.destroy();
    if (state.registry) |r| r.destroy();
    if (state.display) |dpy| wl.Display.disconnect(dpy);
}

pub fn dispatchOnce(state: *WaylandState) bool {
    if (!build.with_wayland or state.display == null) return true;
    _ = state.display.?.dispatchPending();
    _ = state.display.?.flush();
    return true;
}

pub fn rawHandles(state: *WaylandState) struct { display: ?*anyopaque, surface: ?*anyopaque } {
    if (!build.with_wayland) return .{ .display = null, .surface = null };
    return .{
        .display = if (state.display) |d| @ptrCast(d) else null,
        .surface = if (state.surface) |s| @ptrCast(s) else null,
    };
}
```

**Reference:** zzt-backup:148-302

**Test:** File compiles without errors

---

### Step 1.4: Update RenderThread.zig (45 min)

**File:** `src/threads/RenderThread.zig`
**Current:** Stub implementation
**New:** Full Wayland integration

```zig
//! Render Thread Module
//!
//! Wayland window management + Vulkan rendering on dedicated thread
//! Communicates with main/emulation threads via lock-free mailboxes

const std = @import("std");
const xev = @import("xev");
const Mailboxes = @import("../mailboxes/Mailboxes.zig").Mailboxes;
const WaylandLogic = @import("../video/WaylandLogic.zig");

pub const ThreadConfig = struct {
    title: []const u8 = "RAMBO NES Emulator",
    width: u32 = 512,
    height: u32 = 480,
    vsync: bool = true,
    verbose: bool = false,
};

pub fn threadMain(
    mailboxes: *Mailboxes,
    running: *std.atomic.Value(bool),
    config: ThreadConfig,
) void {
    _ = config;

    std.debug.print("[Render] Thread started (TID: {d})\n", .{std.Thread.getCurrentId()});

    // Initialize Wayland with mailbox injection
    var wayland = WaylandLogic.init(std.heap.c_allocator, &mailboxes.xdg_window_event) catch |err| {
        std.debug.print("[Render] Failed to init Wayland: {}\n", .{err});
        return;
    };
    defer wayland.deinit();

    std.debug.print("[Render] Wayland window created\n", .{});

    // Render loop
    while (!wayland.closed and running.load(.acquire)) {
        // 1. Dispatch Wayland events (non-blocking)
        _ = WaylandLogic.dispatchOnce(&wayland);

        // 2. Check for new frame (TODO: Vulkan in Phase 2)
        if (mailboxes.frame.hasNewFrame()) {
            _ = mailboxes.frame.consumeFrame();
        }

        // 3. Small sleep to avoid busy-wait
        std.Thread.sleep(1_000_000); // 1ms
    }

    std.debug.print("[Render] Thread stopping\n", .{});
}

pub fn spawn(
    mailboxes: *Mailboxes,
    running: *std.atomic.Value(bool),
    config: ThreadConfig,
) !std.Thread {
    return try std.Thread.spawn(.{}, threadMain, .{ mailboxes, running, config });
}
```

**Test:**
```bash
zig build run
```

**Expected:**
- Window opens at 512×480
- Title: "RAMBO NES Emulator"
- Can close with X button
- No crashes

**Verification:**
- Check `[Render] Wayland window created` in output
- Window visible on screen
- Emulation still runs at 60 FPS (check terminal output)

---

## Phase 2: Vulkan Context (4-5 hours)

**Goal:** Render solid navy blue color with Vulkan

### Step 2.1: Implement VulkanState.zig (30 min)

**File:** `src/video/VulkanState.zig`

```zig
//! Vulkan Rendering State
//! Pure data structure

const std = @import("std");
const cvk = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("vulkan/vulkan_wayland.h");
});

pub const VulkanState = struct {
    allocator: std.mem.Allocator,

    // Core objects
    instance: cvk.VkInstance = null,
    physical_device: cvk.VkPhysicalDevice = null,
    device: cvk.VkDevice = null,
    surface: cvk.VkSurfaceKHR = null,

    // Queues
    graphics_queue: cvk.VkQueue = null,
    present_queue: cvk.VkQueue = null,
    graphics_family: u32 = 0,
    present_family: u32 = 0,

    // Swapchain
    swapchain: cvk.VkSwapchainKHR = null,
    swapchain_images: std.ArrayList(cvk.VkImage),
    swapchain_image_views: std.ArrayList(cvk.VkImageView),
    swapchain_framebuffers: std.ArrayList(cvk.VkFramebuffer),
    swapchain_extent: cvk.VkExtent2D = .{ .width = 512, .height = 480 },
    swapchain_format: cvk.VkFormat = 0,

    // Command resources
    cmd_pool: cvk.VkCommandPool = null,
    cmd_buffer: cvk.VkCommandBuffer = null,

    // Render pass
    render_pass: cvk.VkRenderPass = null,

    // Synchronization
    image_available_sem: cvk.VkSemaphore = null,
    render_finished_sem: cvk.VkSemaphore = null,
    in_flight_fence: cvk.VkFence = null,

    // Window size
    window_width: u32 = 512,
    window_height: u32 = 480,
};
```

### Step 2.2: Implement VulkanLogic.zig (3-4 hours)

This is complex. Break into sub-steps:

**Sub-step 2.2a:** Instance creation (45 min)
**Sub-step 2.2b:** Device selection and creation (45 min)
**Sub-step 2.2c:** Swapchain creation (45 min)
**Sub-step 2.2d:** Render pass and command resources (45 min)
**Sub-step 2.2e:** renderFrame (solid color) (30 min)

**Reference:** `zzt-backup/src/lib/core/video/vulkan/` (multiple files)

See DETAILED-VULKAN-STEPS.md for full Vulkan implementation (would be very long to include here).

**Test after Phase 2:**
```bash
zig build run
```

**Expected:**
- Window shows solid navy blue color
- No Vulkan validation errors
- 60 FPS vsync

---

## Phase 3: NES Frame Rendering (4-5 hours)

**Goal:** Display actual NES frames from FrameMailbox

### Step 3.1: Create Shaders (1 hour)

**File:** `src/video/shaders/fullscreen.vert`
```glsl
#version 450

layout(location = 0) out vec2 fragTexCoord;

void main() {
    // Generate fullscreen triangle from gl_VertexIndex
    fragTexCoord = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
    gl_Position = vec4(fragTexCoord * 2.0 - 1.0, 0.0, 1.0);
}
```

**File:** `src/video/shaders/texture.frag`
```glsl
#version 450

layout(binding = 0) uniform sampler2D texSampler;

layout(location = 0) in vec2 fragTexCoord;
layout(location = 0) out vec4 outColor;

void main() {
    outColor = texture(texSampler, fragTexCoord);
}
```

**Compile:**
```bash
glslc src/video/shaders/fullscreen.vert -o src/video/shaders/fullscreen.vert.spv
glslc src/video/shaders/texture.frag -o src/video/shaders/texture.frag.spv
```

### Step 3.2: Add Texture Resources to VulkanState (15 min)

Add to VulkanState struct:
```zig
// Texture for NES framebuffer
texture_image: cvk.VkImage = null,
texture_memory: cvk.VkDeviceMemory = null,
texture_view: cvk.VkImageView = null,
texture_sampler: cvk.VkSampler = null,

// Staging buffer
staging_buffer: cvk.VkBuffer = null,
staging_memory: cvk.VkDeviceMemory = null,

// Descriptor resources
descriptor_set_layout: cvk.VkDescriptorSetLayout = null,
descriptor_pool: cvk.VkDescriptorPool = null,
descriptor_set: cvk.VkDescriptorSet = null,

// Graphics pipeline
pipeline_layout: cvk.VkPipelineLayout = null,
pipeline: cvk.VkPipeline = null,
```

### Step 3.3: Implement uploadTexture (1.5 hours)

Add to VulkanLogic.zig:
```zig
pub fn uploadTexture(state: *VulkanState, pixels: []const u32) !void {
    // Implementation details in DETAILED-VULKAN-STEPS.md
    // 1. Map staging buffer
    // 2. Copy pixels
    // 3. Unmap
    // 4. Transition image layout
    // 5. Copy buffer to image
    // 6. Transition to shader-read-only
}
```

### Step 3.4: Update renderFrame (1 hour)

Replace solid color clear with texture sampling.

### Step 3.5: Integrate with RenderThread (30 min)

Update render loop:
```zig
if (mailboxes.frame.hasNewFrame()) {
    const pixels = mailboxes.frame.consumeFrame();
    if (pixels) |p| {
        try VulkanLogic.uploadTexture(&vulkan, p);
        try VulkanLogic.renderFrame(&vulkan);
    }
}
```

**Test:**
```bash
zig build run
```

**Expected:**
- NES frames visible on screen
- AccuracyCoin test pattern visible
- 60 FPS

---

## Phase 4: Input Integration & Polish (2-3 hours)

### Step 4.1: Implement Key Mapping (1 hour)

**File:** `src/main.zig` (update coordination loop)

```zig
fn mapKeyToNESButton(keycode: u32) ?u8 {
    return switch (keycode) {
        30 => 0x01, // KEY_X → A button
        44 => 0x02, // KEY_Z → B button
        42 => 0x04, // KEY_RSHIFT → Select
        28 => 0x08, // KEY_ENTER → Start
        103 => 0x10, // KEY_UP
        108 => 0x20, // KEY_DOWN
        105 => 0x40, // KEY_LEFT
        106 => 0x80, // KEY_RIGHT
        else => null,
    };
}

// In main loop:
const input_events = mailboxes.xdg_input_event.swapAndGetPendingEvents();
for (input_events) |event| {
    switch (event.data) {
        .key_press => |key| {
            if (mapKeyToNESButton(key.keycode)) |button| {
                mailboxes.controller_input.pressButton(1, button);
            }
        },
        .key_release => |key| {
            if (mapKeyToNESButton(key.keycode)) |button| {
                mailboxes.controller_input.releaseButton(1, button);
            }
        },
        else => {},
    }
}
```

### Step 4.2: Aspect Ratio Correction (1 hour)

NES: 256×240 @ 8:7 pixel aspect = 2048:1680 ≈ 1.219:1

Add viewport calculation to VulkanLogic.

### Step 4.3: Window Resize Handling (30 min)

Process window events:
```zig
const window_events = mailboxes.xdg_window_event.swapAndGetPendingEvents();
for (window_events) |event| {
    switch (event.data) {
        .window_resize => |r| {
            try VulkanLogic.recreateSwapchain(&vulkan, r.width, r.height);
        },
        .window_close => running.store(false, .release),
        else => {},
    }
}
```

**Final Test:**
```bash
zig build test  # All 571 tests still pass
zig build run    # Full playable experience
```

**Expected:**
- ✅ Window opens
- ✅ NES frames display correctly
- ✅ Keyboard input works
- ✅ Correct aspect ratio
- ✅ Can resize window
- ✅ 60 FPS stable
- ✅ All tests passing

---

## Development Notes

### Testing Strategy

After each phase:
1. Run `zig build` - must compile
2. Run specific functionality test
3. Check thread separation (no cross-thread calls)
4. Run full test suite

### Common Issues

**Issue:** Wayland connection fails
**Solution:** Check `$WAYLAND_DISPLAY` and socket exists

**Issue:** Vulkan validation errors
**Solution:** Enable validation layers in Debug only

**Issue:** Frame drops
**Solution:** Check mailbox overflow, verify emulation timing

### Performance Targets

- Emulation: 60.0988 FPS (timer-driven)
- Render: 60 FPS (vsync)
- Frame latency: < 33ms (2 frames)

---

## Completion Checklist

- [ ] Phase 1: Window opens and responds
- [ ] Phase 2: Vulkan renders solid color
- [ ] Phase 3: NES frames display
- [ ] Phase 4: Input works, aspect ratio correct
- [ ] All 571 tests pass
- [ ] Thread separation maintained
- [ ] No validation errors
- [ ] Performance targets met

---

**Document Status:** ✅ COMPLETE
**Last Updated:** 2025-10-07
**Ready for Implementation:** YES

**Next:** Review all documents for consistency
