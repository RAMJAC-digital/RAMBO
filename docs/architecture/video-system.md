# Video Subsystem Architecture

**Status:** ⬜ Planned (Phase 8 - Not Started)
**Dependencies:** zig-wayland (configured in build.zig.zon)
**Estimated Time:** 20-28 hours

---

## Overview

Phase 8 implements **Wayland + Vulkan** video output to display PPU rendering on screen.

**Technology Stack:**
- **Wayland** - Native Linux compositor protocol (XDG shell)
- **Vulkan** - Modern GPU rendering API
- **zig-wayland** - Zig bindings for Wayland protocol

**Design Goals:**
- ✅ Native Wayland support (no X11 dependency)
- ✅ Hardware-accelerated rendering (Vulkan)
- ✅ Thread-safe frame consumption (FrameMailbox integration)
- ✅ RT-safe emulation (video thread separate from emulation)
- ✅ Proper aspect ratio (8:7 pixel aspect correction)

---

## Architecture

### Thread Model (3 Threads)

**After Phase 8 completion:**

```
┌─────────────┐         ┌──────────────────┐         ┌─────────────────┐
│ Main Thread │◄────────│ Wayland Thread   │◄────────│ Emulation Thread│
│ (Coordinator)│         │ (Video + Input)  │         │ (RT-Safe)       │
└─────────────┘         └──────────────────┘         └─────────────────┘
       │                         │                             │
       │                         │                             │
       ├── Spawns threads ───────┤                             │
       │                         │                             │
       │                         ├── Reads frames ─────────────┤
       │                         │   (FrameMailbox)            │
       │                         │                             │
       │◄── Window events ───────┤                             │
       │   (WaylandEventMailbox) │                             │
       │                         │                             │
       └── Config updates ────────────────────────────────────►│
           (ConfigMailbox)
```

### Wayland Thread Responsibilities

1. **Window Management:**
   - Create Wayland surface + XDG toplevel
   - Handle window events (resize, close, focus)
   - Post events to WaylandEventMailbox

2. **Rendering:**
   - Initialize Vulkan renderer
   - Read frames from FrameMailbox (lock-free)
   - Upload texture data to GPU
   - Present to screen with vsync

3. **Input Handling:**
   - Keyboard events → controller mapping
   - Future: mouse for debug overlays

---

## Implementation Plan

### Phase 8.1: Wayland Window (6-8 hours)

**Tasks:**

1. **Create Window Module** (`src/video/Window.zig`)

```zig
pub const Window = struct {
    display: *wl.Display,
    surface: *wl.Surface,
    xdg_surface: *xdg.Surface,
    xdg_toplevel: *xdg.Toplevel,

    width: u32 = 800,
    height: u600,

    pub fn init(allocator: std.mem.Allocator) !Window {
        // 1. Connect to Wayland display
        const display = try wl.Display.connect(null);

        // 2. Get registry and bind protocols
        const registry = try display.getRegistry();
        // - wl_compositor
        // - xdg_wm_base
        // - wl_seat (for input)

        // 3. Create surface
        const surface = try compositor.createSurface();

        // 4. Create XDG shell toplevel
        const xdg_surface = try xdg_wm_base.getXdgSurface(surface);
        const xdg_toplevel = try xdg_surface.getToplevel();

        // 5. Configure window
        xdg_toplevel.setTitle("RAMBO NES Emulator");
        surface.commit();

        return Window{ ... };
    }

    pub fn pollEvents(self: *Window, mailbox: *WaylandEventMailbox) !void {
        // Dispatch Wayland events
        _ = try self.display.dispatch();

        // Events posted to mailbox in callbacks
    }
};
```

2. **Event Handling**

```zig
// XDG Surface configure callback
fn xdgSurfaceConfigure(xdg_surface: *xdg.Surface, serial: u32) void {
    xdg_surface.ackConfigure(serial);
}

// XDG Toplevel close callback
fn xdgToplevelClose(xdg_toplevel: *xdg.Toplevel) void {
    // Post close event to mailbox
    mailbox.postEvent(.window_close);
}

// Keyboard key callback
fn keyboardKey(keyboard: *wl.Keyboard, serial: u32, time: u32, key: u32, state: wl.Keyboard.KeyState) void {
    // Map to NES controller buttons
    const button = mapKeyToButton(key);
    mailbox.postEvent(.{ .key_press = .{ .button = button, .pressed = state == .pressed } });
}
```

3. **Integration with libxev**

```zig
// Wayland thread function
fn waylandThreadFn(mailboxes: *Mailboxes, running: *std.atomic.Value(bool)) !void {
    var window = try Window.init(allocator);
    defer window.deinit();

    var loop = try xev.Loop.init(.{});
    defer loop.deinit();

    // Wayland fd for event loop
    const wl_fd = window.display.getFd();

    while (running.load(.acquire)) {
        // 1. Poll Wayland events
        try window.pollEvents(&mailboxes.wayland);

        // 2. Read frame from FrameMailbox (handled in Phase 8.2)

        // 3. Render with Vulkan (handled in Phase 8.2)

        // 4. Run event loop (with Wayland fd)
        try loop.run(.no_wait);
    }
}
```

**Deliverable:** Wayland window opens and closes, keyboard events posted to mailbox

### Phase 8.2: Vulkan Renderer (8-10 hours)

**Tasks:**

1. **Create Renderer Module** (`src/video/VulkanRenderer.zig`)

```zig
pub const VulkanRenderer = struct {
    instance: vk.Instance,
    physical_device: vk.PhysicalDevice,
    device: vk.Device,
    surface: vk.SurfaceKHR,
    swapchain: vk.SwapchainKHR,
    render_pass: vk.RenderPass,
    pipeline: vk.Pipeline,
    command_pool: vk.CommandPool,
    texture: vk.Image,
    texture_view: vk.ImageView,

    pub fn init(window: *Window, allocator: std.mem.Allocator) !VulkanRenderer {
        // 1. Create Vulkan instance
        const instance = try vk.createInstance(.{
            .application_name = "RAMBO",
            .application_version = vk.makeVersion(0, 2, 0),
            .engine_name = "RAMBO",
        });

        // 2. Create Wayland surface
        const surface = try vk.createWaylandSurfaceKHR(instance, .{
            .display = window.display,
            .surface = window.surface,
        });

        // 3. Select physical device (GPU)
        const physical_device = try selectPhysicalDevice(instance);

        // 4. Create logical device and queues
        const device = try vk.createDevice(physical_device, ...);

        // 5. Create swapchain
        const swapchain = try createSwapchain(device, surface, ...);

        // 6. Create render pass
        const render_pass = try createRenderPass(device);

        // 7. Create graphics pipeline
        const pipeline = try createPipeline(device, render_pass);

        return VulkanRenderer{ ... };
    }

    pub fn uploadFrame(self: *VulkanRenderer, frame_data: []const u32) !void {
        // 1. Map texture memory
        // 2. Copy frame data (256×240 RGBA)
        // 3. Unmap memory
        // 4. Transition image layout for rendering
    }

    pub fn render(self: *VulkanRenderer) !void {
        // 1. Acquire swapchain image
        // 2. Begin command buffer
        // 3. Begin render pass
        // 4. Bind pipeline
        // 5. Draw fullscreen quad with texture
        // 6. End render pass
        // 7. Submit command buffer
        // 8. Present swapchain image (vsync)
    }
};
```

2. **Shader Pipeline**

**Vertex Shader** (fullscreen quad):
```glsl
#version 450

layout(location = 0) out vec2 fragTexCoord;

void main() {
    // Fullscreen quad vertices
    vec2 positions[6] = vec2[](
        vec2(-1.0, -1.0), vec2(1.0, -1.0), vec2(1.0, 1.0),
        vec2(-1.0, -1.0), vec2(1.0, 1.0), vec2(-1.0, 1.0)
    );

    vec2 texcoords[6] = vec2[](
        vec2(0.0, 1.0), vec2(1.0, 1.0), vec2(1.0, 0.0),
        vec2(0.0, 1.0), vec2(1.0, 0.0), vec2(0.0, 0.0)
    );

    gl_Position = vec4(positions[gl_VertexIndex], 0.0, 1.0);
    fragTexCoord = texcoords[gl_VertexIndex];
}
```

**Fragment Shader** (texture sampling):
```glsl
#version 450

layout(binding = 0) uniform sampler2D texSampler;
layout(location = 0) in vec2 fragTexCoord;
layout(location = 0) out vec4 outColor;

void main() {
    outColor = texture(texSampler, fragTexCoord);
}
```

3. **Frame Upload Optimization**

```zig
// Double-buffered staging for async upload
pub const FrameUploader = struct {
    staging_buffers: [2]vk.Buffer,
    current_buffer: usize = 0,

    pub fn uploadAsync(self: *FrameUploader, frame_data: []const u32) !void {
        const staging = self.staging_buffers[self.current_buffer];

        // 1. Map staging buffer
        const mapped = try vk.mapMemory(device, staging.memory, ...);

        // 2. Copy frame data
        @memcpy(mapped, frame_data);

        // 3. Unmap
        vk.unmapMemory(device, staging.memory);

        // 4. Queue copy command (async)
        try queueCopyToTexture(staging, self.texture);

        // 5. Swap staging buffers
        self.current_buffer = (self.current_buffer + 1) % 2;
    }
};
```

**Deliverable:** Vulkan renders frame data to window with vsync

### Phase 8.3: Integration (4-6 hours)

**Tasks:**

1. **PPU Frame Output**

```zig
// src/ppu/Logic.zig - at end of frame rendering
pub fn tick(ppu: *PpuState, bus: *BusState) void {
    // ... existing rendering logic ...

    if (ppu.scanline == 241 and ppu.dot == 1) {
        // VBlank start - frame complete

        // Copy PPU output to frame mailbox
        if (ppu.frame_buffer) |frame_buf| {
            const mailbox_buffer = ppu.frame_mailbox.getWriteBuffer();
            @memcpy(mailbox_buffer, frame_buf[0..]);
            ppu.frame_mailbox.swapBuffers();
        }
    }
}
```

2. **Wayland Thread Frame Consumption**

```zig
fn waylandThreadFn(mailboxes: *Mailboxes, running: *std.atomic.Value(bool)) !void {
    var window = try Window.init(allocator);
    var renderer = try VulkanRenderer.init(&window, allocator);

    while (running.load(.acquire)) {
        // 1. Poll Wayland events
        try window.pollEvents(&mailboxes.wayland);

        // 2. Check for new frame
        if (mailboxes.frame.hasNewFrame()) {
            const frame_data = mailboxes.frame.getReadBuffer();

            // 3. Upload to GPU
            try renderer.uploadFrame(frame_data);

            // 4. Render with vsync
            try renderer.render();
        }

        // 5. Small sleep if no frame (avoid busy-wait)
        if (!mailboxes.frame.hasNewFrame()) {
            std.Thread.sleep(1_000_000); // 1ms
        }
    }
}
```

3. **Main Thread Integration**

```zig
// src/main.zig - spawn video thread
pub fn main() !void {
    // ... existing initialization ...

    // Spawn Wayland thread
    const wayland_thread = try std.Thread.spawn(.{}, waylandThreadFn, .{
        &mailboxes, &running
    });

    // Main coordination loop
    while (running.load(.acquire)) {
        // Check for window events
        if (mailboxes.wayland.pollEvent()) |event| {
            switch (event) {
                .window_close => {
                    running.store(false, .release);
                },
                .key_press => |key| {
                    // Update config for controller input (future)
                },
            }
        }

        // ... existing coordination ...
    }

    // Join all threads
    wayland_thread.join();
    emulation_thread.join();
}
```

**Deliverable:** Full PPU output (background + sprites) visible on screen

### Phase 8.4: Polish (2-4 hours)

**Tasks:**

1. **FPS Counter Overlay**

```zig
pub fn renderFpsOverlay(renderer: *VulkanRenderer, fps: f64) !void {
    // Simple text rendering or terminal output
    std.debug.print("FPS: {d:.2}\r", .{fps});
}
```

2. **Aspect Ratio Correction**

```zig
pub fn handleResize(renderer: *VulkanRenderer, width: u32, height: u32) !void {
    // NES: 256×240, 8:7 pixel aspect ratio
    const target_aspect = (256.0 * 8.0 / 7.0) / 240.0;
    const window_aspect = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));

    var render_width: u32 = width;
    var render_height: u32 = height;

    if (window_aspect > target_aspect) {
        // Window too wide - letterbox sides
        render_width = @intFromFloat(@as(f32, @floatFromInt(height)) * target_aspect);
    } else {
        // Window too tall - letterbox top/bottom
        render_height = @intFromFloat(@as(f32, @floatFromInt(width)) / target_aspect);
    }

    // Update viewport
    try renderer.updateViewport(render_width, render_height);
}
```

3. **Vsync Integration**

```zig
// Swapchain creation with vsync
const swapchain = try vk.createSwapchain(device, .{
    .present_mode = .fifo, // Vsync (wait for vertical blank)
    // .present_mode = .immediate, // No vsync (tearing allowed)
});
```

**Impact on FPS:**
- **Before vsync:** 62.97 FPS (timer-driven, 4.8% fast)
- **After vsync:** 60.0 FPS (locked to monitor refresh rate)
- **Result:** Perfect frame pacing, no tearing

4. **Graceful Shutdown**

```zig
// Handle window close event
fn xdgToplevelClose(xdg_toplevel: *xdg.Toplevel) void {
    mailbox.postEvent(.window_close);
}

// Main thread response
if (event == .window_close) {
    std.debug.print("[Main] Window closed by user\n", .{});
    running.store(false, .release);
}
```

**Deliverable:** Production-ready video output with proper presentation

---

## Technical Specifications

### Frame Buffer Format

**PPU Output:**
- Resolution: 256×240 pixels
- Format: RGBA u32 (8 bits per channel)
- Size: 245,760 bytes per frame
- Color Space: NES NTSC palette (64 colors)

**Texture Upload:**
```zig
const texture_info = vk.ImageCreateInfo{
    .imageType = .@"2d",
    .extent = .{ .width = 256, .height = 240, .depth = 1 },
    .format = .r8g8b8a8_unorm,
    .tiling = .optimal,
    .usage = .{ .sampled = true, .transfer_dst = true },
};
```

### Display Properties

**NES Display:**
- Visible Area: 256×240 pixels
- Pixel Aspect Ratio: 8:7 (slightly wider than square)
- Refresh Rate: 60.0988 Hz (NTSC)
- Overscan: None emulated (full 256×240 visible)

**Window Defaults:**
- Initial Size: 800×600 (keeps aspect ratio)
- Scaling: Integer scaling or aspect-correct stretch
- Letterboxing: Black bars when aspect doesn't match

### Performance Targets

**Rendering:**
- Frame Upload: <1ms (DMA transfer)
- GPU Rendering: <1ms (simple fullscreen quad)
- Vsync Wait: ~16ms (60 Hz monitor)
- Total Frame Time: ~16-17ms

**Thread Coordination:**
- Frame Mailbox Swap: <0.1ms (lock-protected pointer swap)
- Event Mailbox Poll: <0.1ms (lock-free atomic read)

---

## Dependencies

### Build Configuration

**build.zig.zon** (already configured):
```zig
.dependencies = .{
    .@"libxev" = .{
        .url = "https://github.com/mitchellh/libxev/archive/8c6447006dcf1ef88509f9c6a1c85b2296e44f96.tar.gz",
        .hash = "...",
    },
    .wayland = .{
        .url = "https://codeberg.org/ifreund/zig-wayland/archive/1b5c038ec1.tar.gz",
        .hash = "wayland-0.5.0-dev-lQa1khrMAQDJDwYFKpdH3HizherB7sHo5dKMECfvxQHe",
    },
},
```

**System Requirements:**
- Wayland compositor (GNOME, KDE Plasma, Sway, etc.)
- Vulkan 1.0+ compatible GPU
- zig-wayland: XDG shell protocol support

### Dependency Status

✅ **libxev** - Integrated, used for timer-driven emulation
✅ **zig-wayland** - Configured in build.zig.zon, not yet used
⬜ **Vulkan** - Not yet integrated (Phase 8.2)

---

## Alternatives Considered

### Why Wayland + Vulkan?

**Wayland Benefits:**
- ✅ Native Linux protocol (no X11 legacy)
- ✅ Modern compositor architecture
- ✅ Better performance and security
- ✅ zig-wayland provides excellent bindings

**Vulkan Benefits:**
- ✅ Modern GPU API with explicit control
- ✅ Low overhead for simple rendering
- ✅ Future: advanced features (HDR, VRR)

### Rejected Alternatives

**SDL2:**
- ❌ C dependency (prefer pure Zig)
- ❌ Abstraction overhead for simple use case
- ❌ Opaque window/rendering management

**OpenGL:**
- ❌ Legacy API (deprecation concerns)
- ❌ Hidden driver overhead
- ❌ Less explicit control than Vulkan

**GLFW:**
- ❌ C dependency
- ❌ X11 fallback (unnecessary complexity)

---

## Testing Strategy

### Manual Testing

1. **Window Management:**
   - Window opens at 800×600
   - Window can be resized
   - Aspect ratio maintained with letterboxing
   - Window close triggers clean shutdown

2. **Rendering:**
   - PPU output displayed correctly
   - Background tiles render properly
   - Sprites render with correct priority
   - No tearing with vsync enabled

3. **Performance:**
   - Maintains 60 FPS with vsync
   - No frame drops during gameplay
   - Low latency (<1 frame)

### Automated Testing

**Phase 8.3 Integration Test:**
```zig
test "video thread frame consumption" {
    var mailboxes = try Mailboxes.init(testing.allocator);
    defer mailboxes.deinit();

    // Post test frame
    const write_buffer = mailboxes.frame.getWriteBuffer();
    @memset(write_buffer, 0xFF0000FF); // Red frame
    mailboxes.frame.swapBuffers();

    // Verify readable
    try testing.expect(mailboxes.frame.hasNewFrame());

    const read_buffer = mailboxes.frame.getReadBuffer();
    try testing.expectEqual(@as(u32, 0xFF0000FF), read_buffer[0]);
}
```

---

## References

**Dependencies:**
- [zig-wayland](https://codeberg.org/ifreund/zig-wayland) - Wayland protocol bindings
- [libxev](https://github.com/mitchellh/libxev) - Event loop library

**Related Documentation:**
- `docs/architecture/threading.md` - Thread architecture overview
- `docs/README.md` - Project status
- `CLAUDE.md` - Development guide

**External Resources:**
- [Wayland Protocol](https://wayland.freedesktop.org/docs/html/) - Official protocol docs
- [Vulkan Tutorial](https://vulkan-tutorial.com/) - Vulkan fundamentals
- [NES Display](https://www.nesdev.org/wiki/PPU) - PPU output specifications

---

**Last Updated:** 2025-10-04
**Status:** Planning complete, awaiting implementation
**Blockers:** None (all dependencies configured)
**Estimated Time:** 20-28 hours
