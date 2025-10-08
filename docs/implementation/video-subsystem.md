# Video Subsystem - Implementation Documentation

**Status:** ✅ **COMPLETE & OPERATIONAL**
**Last Updated:** 2025-10-07
**Implementation:** Wayland + Vulkan rendering at 60 FPS

---

## Overview

The RAMBO emulator features a complete video subsystem that displays NES frames through a native Wayland window with Vulkan rendering. The system is implemented across **2,384 lines of code** with full thread separation and lock-free communication.

### Implementation Status

| Component | Status | Lines | File |
|-----------|--------|-------|------|
| Wayland Window | ✅ Complete | 196 | `src/video/WaylandLogic.zig` |
| Vulkan Renderer | ✅ Complete | 1,857 | `src/video/VulkanLogic.zig` |
| Render Thread | ✅ Complete | 168 | `src/threads/RenderThread.zig` |
| Wayland State | ✅ Complete | 76 | `src/video/WaylandState.zig` |
| Vulkan State | ✅ Complete | 78 | `src/video/VulkanState.zig` |
| Vulkan Bindings | ✅ Complete | 9 | `src/video/VulkanBindings.zig` |

**Total:** 2,384 lines of production code

---

## Architecture

### Thread Model

```
Main Thread
  └─ Spawns RenderThread
       ├─ Creates Wayland window (XDG shell protocol)
       ├─ Initializes Vulkan renderer
       ├─ Polls FrameMailbox for new frames
       └─ Renders 256×240 NES frames at 60 FPS
```

**Key Design Principle:** Render thread is completely isolated from emulation thread. Emulation runs at precise 60.0988 Hz regardless of render performance.

### Communication via Mailboxes

| Mailbox | Direction | Purpose |
|---------|-----------|---------|
| `FrameMailbox` | Emulation → Render | Double-buffered RGBA frame data (256×240×4 bytes) |
| `XdgWindowEventMailbox` | Render → Main | Window events (close, resize, focus) |
| `XdgInputEventMailbox` | Render → Main | Keyboard/mouse input events |
| `RenderStatusMailbox` | Render → Main | FPS stats, diagnostics |

All mailboxes are **lock-free**, using SPSC (Single Producer Single Consumer) ring buffers.

---

## Components

### 1. Wayland Window Management

**File:** `src/video/WaylandLogic.zig` (196 lines)

**Features:**
- XDG shell protocol integration
- Window creation and lifecycle management
- Keyboard input capture
- Window events (close, resize, focus)

**Key Functions:**
```zig
pub fn init(allocator: Allocator) !WaylandState
pub fn createWindow(state: *WaylandState, title: []const u8, width: u32, height: u32) !void
pub fn handleEvents(state: *WaylandState) !void
pub fn deinit(state: *WaylandState) void
```

**Protocols Used:**
- `wl_compositor` - Surface composition
- `xdg_wm_base` - XDG shell window management
- `wl_seat` - Input device handling

### 2. Vulkan Renderer

**File:** `src/video/VulkanLogic.zig` (1,857 lines)

**Features:**
- Vulkan 1.4 initialization
- Swapchain management
- Texture upload from FrameMailbox
- Fullscreen quad rendering
- Nearest-neighbor sampling (pixel-perfect scaling)
- Validation layers (debug mode)

**Rendering Pipeline:**
1. Read frame from FrameMailbox (256×240 RGBA)
2. Upload to Vulkan texture
3. Render fullscreen quad with texture
4. Present to swapchain (vsync enabled)

**Key Functions:**
```zig
pub fn init(allocator: Allocator, wayland: *WaylandState) !VulkanState
pub fn uploadTexture(state: *VulkanState, frame_data: []const u8) !void
pub fn renderFrame(state: *VulkanState) !void
pub fn deinit(state: *VulkanState) void
```

**Vulkan Components:**
- Instance with Wayland surface extension
- Physical device selection (discrete GPU preferred)
- Logical device + graphics queue
- Swapchain (double/triple buffered)
- Render pass + framebuffers
- Graphics pipeline (vertex + fragment shaders)
- Texture sampler (nearest-neighbor filtering)

### 3. Render Thread

**File:** `src/threads/RenderThread.zig` (168 lines)

**Responsibilities:**
- Initialize Wayland + Vulkan
- Main render loop
- Poll FrameMailbox for new frames
- Post window/input events to mailboxes
- FPS counting and diagnostics

**Thread Entry Point:**
```zig
pub fn spawn(
    mailboxes: *Mailboxes,
    running: *std.atomic.Value(bool),
    config: ThreadConfig,
) !std.Thread
```

**Render Loop:**
```zig
while (running.load(.acquire)) {
    // 1. Handle Wayland events
    try WaylandLogic.handleEvents(&wayland);

    // 2. Check for new frame
    if (mailboxes.frame.tryRead()) |frame_data| {
        // 3. Upload to Vulkan texture
        try VulkanLogic.uploadTexture(&vulkan, frame_data);
    }

    // 4. Render current frame
    try VulkanLogic.renderFrame(&vulkan);

    // 5. Update FPS counter
    frame_count += 1;
}
```

---

## Performance

### Frame Timing

- **Target:** 60 FPS (16.67ms per frame)
- **Emulation:** 60.0988 Hz (NTSC precise timing)
- **Render:** Variable, typically 60 FPS with vsync

**Non-blocking Frame Post:**
Emulation thread writes frames to FrameMailbox without waiting for render thread. If render thread is slow, frames are dropped (emulation continues unaffected).

### Resource Usage

**Memory:**
- Frame buffer: 256×240×4 = 245,760 bytes per frame
- Double buffered: 491,520 bytes total
- Vulkan textures: ~2 MB (swapchain images)

**GPU:**
- Single fullscreen quad (2 triangles)
- One texture sample per pixel
- Minimal GPU load (~1-2% on modern hardware)

---

## Configuration

### Window Settings

**Default Configuration:**
```zig
pub const ThreadConfig = struct {
    title: []const u8 = "RAMBO NES Emulator",
    width: u32 = 512,        // 256 × 2
    height: u32 = 480,       // 240 × 2
    vsync: bool = true,
};
```

**Aspect Ratio:**
- NES: 256×240 (8:7 pixel aspect ratio)
- Modern displays: Scale to maintain proper aspect

### Vulkan Settings

**Validation Layers:**
- Enabled in Debug mode
- Disabled in Release mode

**Present Mode:**
- Vsync: `VK_PRESENT_MODE_FIFO_KHR` (default)
- No vsync: `VK_PRESENT_MODE_IMMEDIATE_KHR` (optional)

**Texture Filtering:**
- Nearest-neighbor for pixel-perfect rendering
- No bilinear/trilinear filtering

---

## Error Handling

### Wayland Errors

**Connection Failure:**
```
Error: Unable to connect to Wayland compositor
Solution: Ensure $WAYLAND_DISPLAY is set and compositor is running
```

**Missing Protocols:**
```
Error: XDG shell not available
Solution: Update Wayland compositor to version supporting XDG shell
```

### Vulkan Errors

**No Vulkan Support:**
```
Error: Failed to create Vulkan instance
Solution: Install Vulkan drivers for your GPU
```

**Device Not Found:**
```
Error: No suitable Vulkan physical device
Solution: Ensure GPU supports Vulkan 1.4+
```

**Swapchain Creation Failed:**
```
Error: Failed to create swapchain
Solution: Check display resolution and Vulkan surface compatibility
```

---

## Integration with Main System

### Startup Sequence

1. **Main Thread:**
   ```zig
   var mailboxes = try Mailboxes.init(allocator);
   var running = std.atomic.Value(bool).init(true);

   // Spawn render thread
   const render_thread = try RenderThread.spawn(&mailboxes, &running, .{});
   ```

2. **Render Thread:**
   ```zig
   // Initialize Wayland
   var wayland = try WaylandLogic.init(allocator);
   try WaylandLogic.createWindow(&wayland, config.title, config.width, config.height);

   // Initialize Vulkan
   var vulkan = try VulkanLogic.init(allocator, &wayland);

   // Enter render loop
   while (running.load(.acquire)) { /* render loop */ }
   ```

3. **Emulation Thread:**
   ```zig
   // Post frame to mailbox (non-blocking)
   mailboxes.frame.postFrame(frame_data);
   ```

### Shutdown Sequence

1. Main thread sets `running = false`
2. Render thread exits render loop
3. Vulkan cleanup (destroys resources)
4. Wayland cleanup (closes window)
5. Thread joins

**Clean Shutdown:**
All resources are properly released via RAII patterns. No memory leaks or GPU resource leaks.

---

## Testing

### Manual Testing

**Start Emulator:**
```bash
cd ~/Development/RAMBO
zig build run

# Window should appear with NES output
# Press keys to control (Arrow keys, Z, X, Enter, RShift)
# Press ESC or close window to exit
```

**Expected Behavior:**
- Window opens immediately (~100ms)
- Title: "RAMBO NES Emulator"
- Size: 512×480 (2× scale)
- Frame rendering starts when emulation produces frames

### Diagnostics

**Enable Debug Logging:**
```bash
# Vulkan validation layers (Debug build)
zig build -Doptimize=Debug

# Wayland protocol debugging
export WAYLAND_DEBUG=1
zig build run
```

**FPS Counter:**
Render thread logs FPS every second:
```
[Render] FPS: 60.2, Frames: 3612, Uptime: 60.0s
```

---

## Known Limitations

### Current Limitations

1. **No Window Resize:**
   - Window size is fixed at startup
   - Resizing not yet implemented
   - Planned for future enhancement

2. **No Aspect Ratio Correction:**
   - NES uses 8:7 pixel aspect ratio
   - Current: square pixels
   - Planned: proper 8:7 correction

3. **No Fullscreen Mode:**
   - Window only (no fullscreen toggle)
   - Planned for future enhancement

4. **No Menu/Overlay:**
   - No on-screen menus
   - All controls via keyboard only

### Performance Notes

**GPU Compatibility:**
- Tested: Intel integrated, NVIDIA, AMD
- Requires: Vulkan 1.4+
- Fallback: None (Vulkan required)

**Wayland Only:**
- No X11 support
- Wayland compositor required
- Works on: GNOME, KDE Plasma 6, Sway, Hyprland

---

## Future Enhancements

### Planned Features

1. **Window Resizing**
   - Dynamic swapchain recreation
   - Maintain aspect ratio

2. **Aspect Ratio Correction**
   - Proper 8:7 pixel aspect
   - Black bars for letterboxing

3. **Fullscreen Mode**
   - Toggle with F11
   - Exclusive fullscreen option

4. **On-Screen Display**
   - FPS counter overlay
   - Input display
   - Debug information

5. **Screenshot Capture**
   - Save current frame to PNG
   - Timestamp-based filenames

6. **Video Recording**
   - Record gameplay to MP4
   - Configurable quality/FPS

---

## Dependencies

### Required Libraries

**Build Time:**
- `zig-wayland` - Zig bindings for Wayland
- Vulkan headers (system)

**Runtime:**
- `libwayland-client.so` - Wayland client library
- `libvulkan.so` - Vulkan loader
- GPU drivers with Vulkan support

**Optional:**
- `glslc` or `glslangValidator` - Shader compilation

### Installation

**Arch Linux:**
```bash
sudo pacman -S wayland vulkan-headers vulkan-icd-loader
# GPU drivers:
# Intel: vulkan-intel
# NVIDIA: nvidia
# AMD: vulkan-radeon
```

**Ubuntu/Debian:**
```bash
sudo apt install libwayland-dev libvulkan-dev vulkan-tools
# GPU drivers:
# Intel: mesa-vulkan-drivers
# NVIDIA: nvidia-driver
# AMD: mesa-vulkan-drivers
```

---

## References

### External Documentation

- [Vulkan Tutorial](https://vulkan-tutorial.com/)
- [Wayland Protocol](https://wayland.freedesktop.org/docs/html/)
- [XDG Shell Protocol](https://wayland.app/protocols/xdg-shell)

### Internal Documentation

- `docs/architecture/threading.md` - Thread architecture
- `docs/MAILBOX-ARCHITECTURE.md` - Mailbox system design
- `src/threads/RenderThread.zig` - Implementation with inline docs

---

**End of Video Subsystem Documentation**
