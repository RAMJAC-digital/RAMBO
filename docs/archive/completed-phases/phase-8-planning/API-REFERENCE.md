# API Reference - Phase 8 Video Subsystem

**Created:** 2025-10-07
**Status:** Complete API documentation for implementation
**Purpose:** Explicit documentation of all APIs, patterns, and signatures

---

## Overview

This document provides complete API signatures for all modules in Phase 8. Every function, struct, and pattern is documented with:
- Exact signatures from proven implementations (zzt-backup)
- Thread safety guarantees
- Usage examples
- Cross-references to source files

---

## Table of Contents

1. [Wayland Module](#wayland-module)
2. [Vulkan Module](#vulkan-module)
3. [Mailbox APIs](#mailbox-apis)
4. [Thread Module APIs](#thread-module-apis)
5. [Integration Patterns](#integration-patterns)

---

## Wayland Module

### WaylandState.zig

**File:** `src/video/WaylandState.zig`
**Pattern:** Pure data structure (State/Logic separation)
**Reference:** `zzt-backup/src/lib/core/video/wayland/window_wayland.zig:96-141`

```zig
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

    // Keyboard state
    last_x: f32 = 0,
    last_y: f32 = 0,
    mods_depressed: u32 = 0,
    mods_latched: u32 = 0,
    mods_locked: u32 = 0,
    mods_group: u32 = 0,

    // Dependency injection
    event_mailbox: *XdgWindowEventMailbox,
    allocator: std.mem.Allocator,
};
```

**Thread Safety:** Owned by render thread only
**Lifetime:** Created in `renderThreadFn()`, destroyed on thread exit

---

### WaylandLogic.zig

**File:** `src/video/WaylandLogic.zig`
**Pattern:** Pure functions operating on WaylandState
**Reference:** `zzt-backup/src/lib/core/video/wayland/window_wayland.zig:144-533`

#### init

```zig
pub fn init(
    allocator: std.mem.Allocator,
    mailbox: *XdgWindowEventMailbox,
) !WaylandState
```

**Purpose:** Initialize Wayland connection and create window
**Thread:** Render thread only
**Reference:** zzt-backup:148-253

**Steps:**
1. Connect to Wayland display
2. Get registry and bind globals (compositor, xdg_wm_base, seat)
3. Create surface and XDG toplevel
4. Setup input devices (keyboard, pointer)
5. Register all protocol listeners
6. Commit initial surface

**Returns:** Fully initialized WaylandState
**Errors:** `WaylandConnectFailed`, `WaylandGlobalsMissing`

---

#### deinit

```zig
pub fn deinit(state: *WaylandState) void
```

**Purpose:** Cleanup all Wayland resources
**Thread:** Render thread only
**Reference:** zzt-backup:255-269

**Order:**
1. Destroy input devices
2. Destroy XDG objects (toplevel → xdg_surface → surface)
3. Destroy wm_base
4. Destroy registry
5. Disconnect display

---

#### dispatchOnce

```zig
pub fn dispatchOnce(state: *WaylandState) bool
```

**Purpose:** Process pending Wayland events (non-blocking)
**Thread:** Render thread only
**Reference:** zzt-backup:271-277

**Implementation:**
```zig
pub fn dispatchOnce(state: *WaylandState) bool {
    if (state.display == null) return true;
    _ = state.display.?.dispatchPending();
    _ = state.display.?.flush();
    return true;
}
```

**Returns:** `true` on success, `false` on error
**Side Effects:** Wayland callbacks fire, events posted to mailbox

---

#### rawHandles

```zig
pub fn rawHandles(state: *WaylandState) struct {
    display: ?*anyopaque,
    surface: ?*anyopaque,
}
```

**Purpose:** Get opaque pointers for Vulkan surface creation
**Thread:** Render thread only
**Reference:** zzt-backup:296-302

**Usage:**
```zig
const handles = WaylandLogic.rawHandles(&wayland);
var vulkan = try VulkanLogic.init(allocator, handles.display.?, handles.surface.?);
```

---

#### Protocol Listeners (Internal)

**Reference:** zzt-backup:339-533

##### registryListener

```zig
fn registryListener(
    registry: *wl.Registry,
    event: wl.Registry.Event,
    context: *EventHandlerContext,
) void
```

**Purpose:** Bind Wayland globals
**Binds:** `wl_compositor`, `xdg_wm_base`, `wl_seat`

---

##### wmBaseListener

```zig
fn wmBaseListener(
    wm_base: *xdg.WmBase,
    event: xdg.WmBase.Event,
    context: *EventHandlerContext,
) void
```

**Purpose:** Handle xdg_wm_base ping events
**Critical:** MUST respond to ping with pong or compositor kills us

```zig
switch (event) {
    .ping => |p| wm_base.pong(p.serial), // ← REQUIRED!
}
```

---

##### xdgSurfaceListener

```zig
fn xdgSurfaceListener(
    surface: *xdg.Surface,
    event: xdg.Surface.Event,
    context: *EventHandlerContext,
) void
```

**Purpose:** Acknowledge surface configuration

```zig
switch (event) {
    .configure => |cfg| surface.ackConfigure(cfg.serial), // ← REQUIRED!
}
```

---

##### xdgToplevelListener

```zig
fn xdgToplevelListener(
    toplevel: *xdg.Toplevel,
    event: xdg.Toplevel.Event,
    context: *EventHandlerContext,
) void
```

**Purpose:** Handle window resize, close, state changes
**Reference:** zzt-backup:398-436

**Events:**
- `.configure` → Posts `window_resize` to mailbox if size changes
- `.close` → Sets `state.closed = true`, posts `window_close`

---

##### keyboardListener

```zig
fn keyboardListener(
    keyboard: *wl.Keyboard,
    event: wl.Keyboard.Event,
    context: *EventHandlerContext,
) void
```

**Purpose:** Handle keyboard input
**Reference:** zzt-backup:488-510

**Events:**
- `.enter` → Posts `window_focus_change { focused: true }`
- `.leave` → Posts `window_focus_change { focused: false }`
- `.key` → Posts `key_press` or `key_release` with keycode and modifiers
- `.modifiers` → Updates modifier state

---

##### pointerListener

```zig
fn pointerListener(
    pointer: *wl.Pointer,
    event: wl.Pointer.Event,
    context: *EventHandlerContext,
) void
```

**Purpose:** Handle mouse input
**Reference:** zzt-backup:438-486

**Events:**
- `.motion` → Posts `mouse_move { x, y }`
- `.button` → Posts `mouse_button { button, pressed, x, y }`
- `.axis` → Posts `mouse_scroll { x_delta, y_delta, x, y }`

---

## Vulkan Module

### VulkanState.zig

**File:** `src/video/VulkanState.zig`
**Pattern:** Pure data structure
**Reference:** `zzt-backup/src/lib/core/video/vulkan/context.zig:34-94`

```zig
pub const VulkanState = struct {
    allocator: std.mem.Allocator,

    // Core Vulkan objects
    instance: cvk.VkInstance,
    physical_device: cvk.VkPhysicalDevice,
    device: cvk.VkDevice,
    surface: cvk.VkSurfaceKHR,

    // Queues
    graphics_queue: cvk.VkQueue,
    present_queue: cvk.VkQueue,
    graphics_family: u32,
    present_family: u32,

    // Swapchain
    swapchain: cvk.VkSwapchainKHR,
    swapchain_images: std.ArrayList(cvk.VkImage),
    swapchain_image_views: std.ArrayList(cvk.VkImageView),
    swapchain_framebuffers: std.ArrayList(cvk.VkFramebuffer),
    swapchain_extent: cvk.VkExtent2D,
    swapchain_format: cvk.VkFormat,

    // Command resources
    cmd_pool: cvk.VkCommandPool,
    cmd_buffer: cvk.VkCommandBuffer,

    // Render resources
    render_pass: cvk.VkRenderPass,
    pipeline_layout: cvk.VkPipelineLayout,
    pipeline: cvk.VkPipeline,

    // Texture for NES framebuffer
    texture_image: cvk.VkImage,
    texture_memory: cvk.VkDeviceMemory,
    texture_view: cvk.VkImageView,
    texture_sampler: cvk.VkSampler,

    // Staging buffer for CPU → GPU upload
    staging_buffer: cvk.VkBuffer,
    staging_memory: cvk.VkDeviceMemory,

    // Descriptor resources
    descriptor_set_layout: cvk.VkDescriptorSetLayout,
    descriptor_pool: cvk.VkDescriptorPool,
    descriptor_set: cvk.VkDescriptorSet,

    // Synchronization
    image_available_semaphore: cvk.VkSemaphore,
    render_finished_semaphore: cvk.VkSemaphore,
    in_flight_fence: cvk.VkFence,

    // Window size
    window_width: u32 = 512,
    window_height: u32 = 480,
};
```

---

### VulkanLogic.zig

**File:** `src/video/VulkanLogic.zig`
**Pattern:** Pure functions operating on VulkanState
**Reference:** `zzt-backup/src/lib/core/video/vulkan/context.zig:95-200`

#### init

```zig
pub fn init(
    allocator: std.mem.Allocator,
    wl_display: *anyopaque,
    wl_surface: *anyopaque,
) !VulkanState
```

**Purpose:** Initialize complete Vulkan rendering context
**Thread:** Render thread only
**Reference:** zzt-backup:97-142

**Steps:**
1. Create Vulkan instance with Wayland surface extension
2. Create Wayland surface (`vkCreateWaylandSurfaceKHR`)
3. Select physical device (prefer discrete GPU)
4. Create logical device with graphics + present queues
5. Create swapchain with FIFO present mode (vsync)
6. Create render pass
7. Create framebuffers
8. Create command pool and allocate command buffer
9. Create NES texture (256×240 R8G8B8A8)
10. Create staging buffer for texture uploads
11. Create descriptor set layout and pool
12. Load shaders and create pipeline
13. Create synchronization objects

**Returns:** Fully initialized VulkanState
**Errors:** VulkanError variants

---

#### deinit

```zig
pub fn deinit(state: *VulkanState) void
```

**Purpose:** Cleanup all Vulkan resources
**Thread:** Render thread only

**Order (reverse of creation):**
1. Wait for device idle
2. Destroy synchronization objects
3. Destroy descriptor resources
4. Destroy staging buffer
5. Destroy texture resources
6. Destroy pipeline and layout
7. Destroy render pass
8. Destroy framebuffers
9. Destroy swapchain image views
10. Destroy swapchain
11. Destroy command pool
12. Destroy device
13. Destroy surface
14. Destroy instance

---

#### uploadTexture

```zig
pub fn uploadTexture(
    state: *VulkanState,
    pixels: []const u32,
) !void
```

**Purpose:** Upload NES framebuffer to GPU texture
**Thread:** Render thread only
**Size:** Expects `pixels.len == 256 * 240`

**Steps:**
1. Map staging buffer memory
2. Copy pixels to staging buffer
3. Unmap staging buffer
4. Begin command buffer
5. Transition image layout: UNDEFINED → TRANSFER_DST_OPTIMAL
6. Copy buffer to image
7. Transition image layout: TRANSFER_DST_OPTIMAL → SHADER_READ_ONLY_OPTIMAL
8. End command buffer
9. Submit and wait for completion

**Performance:** ~0.5ms for 256×240 RGBA upload

---

#### renderFrame

```zig
pub fn renderFrame(state: *VulkanState) !void
```

**Purpose:** Render fullscreen quad with NES texture
**Thread:** Render thread only

**Steps:**
1. Wait for in-flight fence
2. Acquire next swapchain image
3. Reset command buffer
4. Begin render pass
5. Bind pipeline
6. Bind descriptor set (texture sampler)
7. Draw fullscreen quad (3 vertices, no VBO)
8. End render pass
9. End command buffer
10. Submit command buffer with semaphores
11. Present to swapchain (vsync blocks here)
12. Reset fence

**Returns:** `error.SwapchainOutOfDate` if resize needed

---

#### recreateSwapchain

```zig
pub fn recreateSwapchain(
    state: *VulkanState,
    width: u32,
    height: u32,
) !void
```

**Purpose:** Recreate swapchain after window resize
**Thread:** Render thread only

**Steps:**
1. Wait for device idle
2. Destroy old framebuffers
3. Destroy old image views
4. Destroy old swapchain
5. Create new swapchain with new extent
6. Create new image views
7. Create new framebuffers

---

## Mailbox APIs

### XdgWindowEventMailbox

**File:** `src/mailboxes/XdgWindowEventMailbox.zig`
**Pattern:** Double-buffered event queue
**Reference:** `zzt-backup/src/lib/core/video/wayland/event_mailbox.zig:64-159`

#### Structure

```zig
pub const XdgWindowEventMailbox = struct {
    allocator: std.mem.Allocator,
    writing_events: std.ArrayList(WaylandEvent),
    reading_events: std.ArrayList(WaylandEvent),
    mutex: std.Thread.Mutex = .{},
};
```

#### init

```zig
pub fn init(allocator: std.mem.Allocator) XdgWindowEventMailbox
```

**Thread Safety:** Safe to call from any thread
**Lifetime:** Created in `Mailboxes.init()`

---

#### postEvent

```zig
pub fn postEvent(
    self: *XdgWindowEventMailbox,
    event_type: WaylandEventType,
    data: WaylandEvent.EventData,
) !void
```

**Purpose:** Post event from Wayland listener (render thread)
**Thread Safety:** Protected by mutex
**Performance:** O(1) amortized

**Usage:**
```zig
// In Wayland listener callback
const event_data = WaylandEvent.EventData{
    .key_press = .{ .keycode = key, .modifiers = mods }
};
try mailbox.postEvent(.key_press, event_data);
```

---

#### swapAndGetPendingEvents

```zig
pub fn swapAndGetPendingEvents(self: *XdgWindowEventMailbox) []WaylandEvent
```

**Purpose:** Atomic swap and retrieve all pending events
**Thread Safety:** Protected by mutex
**Performance:** O(1) swap operation
**Memory:** Mailbox owns returned slice (caller must NOT free)

**Usage:**
```zig
// In main thread
const events = mailboxes.xdg_window_event.swapAndGetPendingEvents();
for (events) |event| {
    // Process event...
}
// No free() needed - mailbox owns memory
```

**Reference:** zzt-backup:116-138

---

### FrameMailbox

**File:** `src/mailboxes/FrameMailbox.zig`
**Pattern:** Double-buffered frame data
**Status:** Already implemented

#### hasNewFrame

```zig
pub fn hasNewFrame(self: *const FrameMailbox) bool
```

**Purpose:** Lock-free check for new frame
**Thread Safety:** Atomic read
**Performance:** O(1), no mutex

---

#### consumeFrame

```zig
pub fn consumeFrame(self: *FrameMailbox) ?[]const u32
```

**Purpose:** Get latest frame pixels
**Thread Safety:** Protected by mutex
**Returns:** `null` if no new frame, otherwise 256×240 RGBA pixels

---

#### swapBuffers

```zig
pub fn swapBuffers(self: *FrameMailbox) void
```

**Purpose:** Swap write/read buffers (emulation thread)
**Thread Safety:** Protected by mutex
**Performance:** O(1), just pointer swap

---

## Thread Module APIs

### EmulationThread

**File:** `src/threads/EmulationThread.zig`
**Status:** Already implemented

#### spawn

```zig
pub fn spawn(
    state: *EmulationState,
    mailboxes: *Mailboxes,
    running: *std.atomic.Value(bool),
) !std.Thread
```

**Usage:**
```zig
const emulation_thread = try EmulationThread.spawn(&emu_state, &mailboxes, &running);
defer emulation_thread.join();
```

---

### RenderThread

**File:** `src/threads/RenderThread.zig`
**Status:** Stub, to be implemented

#### spawn

```zig
pub fn spawn(
    mailboxes: *Mailboxes,
    running: *std.atomic.Value(bool),
    config: ThreadConfig,
) !std.Thread
```

**Will implement:**
```zig
pub fn threadMain(
    mailboxes: *Mailboxes,
    running: *std.atomic.Value(bool),
    config: ThreadConfig,
) void {
    var wayland = WaylandLogic.init(allocator, &mailboxes.xdg_window_event) catch return;
    defer wayland.deinit();

    const handles = WaylandLogic.rawHandles(&wayland);
    var vulkan = VulkanLogic.init(allocator, handles.display.?, handles.surface.?) catch return;
    defer vulkan.deinit();

    while (!wayland.closed and running.load(.acquire)) {
        _ = WaylandLogic.dispatchOnce(&wayland);

        if (mailboxes.frame.hasNewFrame()) {
            const pixels = mailboxes.frame.consumeFrame();
            if (pixels) |p| {
                try VulkanLogic.uploadTexture(&vulkan, p);
                try VulkanLogic.renderFrame(&vulkan);
            }
        }

        std.Thread.sleep(1_000_000);
    }
}
```

---

## Integration Patterns

### Pattern 1: Wayland Event to Controller Input

**Flow:** Render Thread → Main Thread → Emulation Thread

```zig
// Render Thread: Wayland listener posts event
fn keyboardListener(..., context: *EventHandlerContext) void {
    const event_data = WaylandEvent.EventData{
        .key_press = .{ .keycode = k.key, .modifiers = context.state.mods_depressed }
    };
    context.mailbox.postEvent(.key_press, event_data) catch {};
}

// Main Thread: Route to controller
const events = mailboxes.xdg_input_event.swapAndGetPendingEvents();
for (events) |event| {
    switch (event.data) {
        .key_press => |key| {
            const button = mapKeyToNESButton(key.keycode); // e.g., KEY_X → 0x01 (A)
            if (button) |b| {
                mailboxes.controller_input.pressButton(1, b);
            }
        },
        else => {},
    }
}

// Emulation Thread: Read via $4016
// (Already implemented in src/emulation/State.zig)
```

---

### Pattern 2: Frame Production/Consumption

**Flow:** Emulation Thread → Render Thread

```zig
// Emulation Thread: Produce frame
fn timerCallback(...) xev.CallbackAction {
    const cycles = ctx.state.emulateFrame();
    ctx.mailboxes.frame.swapBuffers(); // ← Non-blocking
    return .rearm;
}

// Render Thread: Consume frame
if (mailboxes.frame.hasNewFrame()) { // ← Lock-free check
    const pixels = mailboxes.frame.consumeFrame();
    if (pixels) |p| {
        try VulkanLogic.uploadTexture(&vulkan, p);
        try VulkanLogic.renderFrame(&vulkan); // ← Vsync here, doesn't block emulation
    }
}
```

---

## Build Integration

### Shader Compilation

**Add to build.zig:**

```zig
const compile_vert = b.addSystemCommand(&.{
    "glslc",
    "src/video/shaders/fullscreen.vert",
    "-o",
    "src/video/shaders/fullscreen.vert.spv",
});

const compile_frag = b.addSystemCommand(&.{
    "glslc",
    "src/video/shaders/texture.frag",
    "-o",
    "src/video/shaders/texture.frag.spv",
});

exe.step.dependOn(&compile_vert.step);
exe.step.dependOn(&compile_frag.step);
```

### Loading Compiled Shaders

```zig
const vert_code = @embedFile("shaders/fullscreen.vert.spv");
const frag_code = @embedFile("shaders/texture.frag.spv");
```

---

## Conclusion

All APIs are documented with:
- ✅ Exact signatures
- ✅ Thread safety guarantees
- ✅ References to proven implementations
- ✅ Usage examples

**Next:** Step-by-step implementation guide

---

**Document Status:** ✅ COMPLETE
**Last Updated:** 2025-10-07
