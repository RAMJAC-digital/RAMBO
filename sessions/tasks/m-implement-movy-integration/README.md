---
name: m-implement-movy-integration
branch: feature/m-implement-movy-integration
status: pending
created: 2025-11-01
---

# Movy Terminal Rendering Integration

## Problem/Goal

Add terminal rendering backend using movy as an alternative to the Wayland/Vulkan stack for development purposes. Currently, the emulator requires a full graphical environment (Wayland compositor + Vulkan), which makes it difficult to develop and debug without visual feedback.

**Goal:** Allow the emulator to run in either:
- **Graphical mode:** Wayland window + Vulkan rendering (current implementation)
- **Terminal mode:** Terminal-based rendering using movy library

**Benefits:**
- Faster iteration during development (no need for graphical environment)
- Easier remote development via SSH
- Visual feedback in terminal-only environments
- Debugging aid for rendering issues

## Success Criteria
- [ ] movy dependency integrated into build.zig.zon and builds successfully
- [ ] Runtime backend selection implemented (CLI flag like `--backend=terminal` or `--backend=wayland`)
- [ ] Terminal rendering backend functional: RAMBO can display NES frames using movy's RenderSurface
- [ ] Terminal input handling working: Keyboard input via terminal maps to NES controller buttons
- [ ] Both backends coexist without conflicts: Can build with either/both backends enabled
- [ ] Zero regressions in existing Wayland/Vulkan rendering path
- [ ] Terminal mode can run AccuracyCoin and display test results visually
- [ ] Frame rate/timing remains accurate in terminal mode (3:1 PPU:CPU ratio maintained)
- [ ] Documentation updated with terminal mode usage instructions

## Context Manifest
<!-- Added by context-gathering agent -->

### Hardware Specification: NES Video Output to Terminal Rendering

**NOT APPLICABLE** - This task is about adding a development tool (terminal rendering backend), not emulating NES hardware. Hardware accuracy requirements do not apply here. The goal is developer convenience, not cycle-accurate terminal rendering.

**What We're Building:**
A secondary rendering backend using the `movy` library to display NES frames (256×240 RGBA) in a terminal window. This is purely a development aid - the terminal backend doesn't need to match NES hardware timing or behavior.

**Key Requirements:**
- Frame data comes from the same FrameMailbox (256×240 RGBA u32 values)
- Runtime selection between Wayland/Vulkan (graphical) and movy (terminal)
- Terminal input (keyboard) maps to NES controller buttons
- Both backends should coexist without breaking existing functionality

### Current Rendering Architecture: Wayland + Vulkan Stack

RAMBO uses a **3-thread mailbox architecture** with dedicated rendering and emulation threads:

**Thread Architecture (from src/main.zig):**
1. **Main Thread (Coordinator):** Minimal work - processes events from other threads and coordinates shutdown
2. **Emulation Thread (EmulationThread.zig):** RT-safe, timer-driven at 60.0988 Hz NTSC. Executes cycle-accurate NES emulation and produces frames
3. **Render Thread (RenderThread.zig):** Runs Wayland window + Vulkan rendering at ~60 FPS, consumes frames from mailbox

**Communication Flow:**
```
EmulationThread → FrameMailbox → RenderThread → Wayland/Vulkan Display
Main Thread → ControllerInputMailbox → EmulationThread
RenderThread → XdgInputEventMailbox → Main Thread → (KeyboardMapper) → ControllerInputMailbox
```

**Frame Data Path (Critical for Terminal Backend):**

1. **EmulationThread produces frames** (src/threads/EmulationThread.zig:99-146):
   ```zig
   // Get write buffer from FrameMailbox triple-buffer
   const write_buffer = ctx.mailboxes.frame.getWriteBuffer();

   if (write_buffer) |buffer| {
       // Set framebuffer pointer on EmulationState
       ctx.state.framebuffer = buffer;

       // Emulate one frame (CPU/PPU execute, PPU writes pixels)
       const cycles = ctx.state.emulateFrame();

       // Publish frame to render thread
       ctx.mailboxes.frame.swapBuffers();

       // Clear reference
       ctx.state.framebuffer = null;
   }
   ```

2. **PPU writes pixels during emulation** (src/ppu/Logic.zig:377-384):
   ```zig
   // During visible scanlines (0-239), dots 1-256
   const color = getPaletteColor(state, final_palette_index);
   if (framebuffer) |fb| {
       // Write RGBA color to framebuffer
       const fb_index = pixel_y * 256 + pixel_x;
       fb[fb_index] = color;  // u32 RGBA format (0xAABBGGRR)
   }
   ```

3. **RenderThread consumes frames** (src/threads/RenderThread.zig:93-106):
   ```zig
   // Check for new frame from emulation thread
   if (mailboxes.frame.hasNewFrame()) {
       const frame_buffer = mailboxes.frame.getReadBuffer();

       // Upload to Vulkan and render
       VulkanLogic.renderFrame(&vulkan, frame_buffer) catch continue;

       // Mark frame consumed
       mailboxes.frame.consumeFrame();
   }
   ```

**FrameMailbox Specification** (src/mailboxes/FrameMailbox.zig):
- **Lock-free triple buffering** using pure atomics (no mutexes)
- **3 preallocated buffers** on stack (720 KB total) - ZERO heap allocations
- **256×240 pixels** = 61,440 pixels per frame
- **RGBA u32 format** (0xAABBGGRR little-endian) for Vulkan compatibility
- **SPSC pattern:** Single producer (EmulationThread), single consumer (RenderThread)
- **API:**
  - `getWriteBuffer() ?[]u32` - Get mutable write buffer for emulation
  - `swapBuffers()` - Publish completed frame (atomic index increment)
  - `hasNewFrame() bool` - Check if new frame available (read_index != write_index)
  - `getReadBuffer() []const u32` - Get const read buffer for rendering
  - `consumeFrame()` - Advance read index (atomic)

**Vulkan Rendering Pipeline** (src/video/VulkanLogic.zig):
```zig
pub fn renderFrame(state: *VulkanState, frame_data: []const u32) !void {
    // 1. Acquire swapchain image
    // 2. Upload frame_data to texture via staging buffer
    // 3. Execute command buffer (render pass, draw fullscreen quad)
    // 4. Present to swapchain
}
```

**For Terminal Backend:** We need to replicate the `renderFrame()` interface but output to terminal using movy instead of Vulkan.

### Current Input System: Wayland Keyboard to NES Buttons

**Input Flow:**
```
Wayland Events → XdgInputEventMailbox → Main Thread → KeyboardMapper → ControllerInputMailbox → EmulationThread
```

**KeyboardMapper** (src/input/KeyboardMapper.zig):
- Converts XKB keysyms (layout-independent) to NES button state
- Default mapping:
  - Arrow Keys → D-pad (Up/Down/Left/Right)
  - Z → B button
  - X → A button
  - Right Shift → Select
  - Enter/KP_Enter → Start
- Maintains stateful ButtonState (8 buttons packed in u8)
- Auto-sanitizes opposing directions (Up+Down, Left+Right cleared)

**ButtonState** (src/input/ButtonState.zig):
```zig
pub const ButtonState = packed struct(u8) {
    a: bool, b: bool, select: bool, start: bool,
    up: bool, down: bool, left: bool, right: bool,

    pub fn toByte(self: ButtonState) u8;
    pub fn fromByte(byte: u8) ButtonState;
    pub fn sanitize(self: *ButtonState) void; // Clear opposing directions
};
```

**ControllerInputMailbox** (src/mailboxes/ControllerInputMailbox.zig):
- Lock-free mailbox for controller state
- Main thread calls `postController1(button_state)` every frame
- Emulation thread polls with `getInput()` to read current state
- Two controllers supported (controller1, controller2)

**For Terminal Backend:** Terminal input events need to update KeyboardMapper, which feeds ControllerInputMailbox. Main thread orchestration handles this regardless of backend.

### State/Logic Separation Pattern (Not Directly Relevant)

RAMBO uses hybrid State/Logic separation for emulation components (CPU/PPU/APU), but **this pattern doesn't apply to the rendering backend**. The terminal backend is a pure development tool - it can follow whatever architecture is simplest.

**What to ignore:**
- State.zig / Logic.zig pattern (for hardware emulation only)
- Cycle timing requirements (terminal rendering doesn't need 60.0988 Hz precision)
- Hardware quirks and edge cases (not applicable to display output)

### Build System Integration Points

**Current Build Structure:**

**Main Entry Point** (build.zig):
```zig
// Thin coordinator - delegates to sub-builders
const Options = @import("build/options.zig");
const Dependencies = @import("build/dependencies.zig");
const Wayland = @import("build/wayland.zig");
const Graphics = @import("build/graphics.zig");
const Modules = @import("build/modules.zig");
```

**Build Options** (build/options.zig):
```zig
pub fn create(b: *std.Build) BuildOptions {
    const options = b.addOptions();
    options.addOption(bool, "with_wayland", true);
    return .{ .step = options, .module = options.createModule() };
}
```

**Dependencies** (build/dependencies.zig):
```zig
pub const DependencyModules = struct {
    xev: *std.Build.Module,  // Event loop (libxev)
    zli: *std.Build.Module,  // CLI parsing
};
```

**Wayland Integration** (build/wayland.zig):
- Runs zig-wayland scanner to generate protocol bindings
- Creates wayland_client module
- Returns WaylandArtifacts{ .module, .protocols, ... }

**Module Wiring** (build/modules.zig):
```zig
const mod = b.addModule("RAMBO", .{
    .root_source_file = b.path("src/root.zig"),
    .imports = &.{
        .{ .name = "build_options", .module = config.build_options.module },
        .{ .name = "wayland_client", .module = config.wayland.module },
        .{ .name = "xev", .module = config.dependencies.xev },
        .{ .name = "zli", .module = config.dependencies.zli },
    },
});

// Executable links system libraries
exe.linkSystemLibrary("wayland-client");
exe.linkSystemLibrary("xkbcommon");
exe.linkSystemLibrary("vulkan");
```

**External Dependencies** (build.zig.zon):
```zig
.dependencies = .{
    .libxev = .{ .url = "...", .hash = "..." },  // Event loop
    .wayland = .{ .url = "...", .hash = "..." }, // Wayland bindings
    .zli = .{ .url = "...", .hash = "..." },     // CLI parsing
},
```

**For Terminal Backend Integration:**

1. **Add movy dependency to build.zig.zon:**
   ```zig
   .dependencies = .{
       .libxev = ...,
       .wayland = ...,
       .zli = ...,
       .movy = .{ .url = "https://github.com/zig-graphics/movy/archive/<commit>.tar.gz", .hash = "..." },
   }
   ```

2. **Add build option for backend selection** (build/options.zig):
   ```zig
   options.addOption(bool, "with_wayland", true);
   options.addOption(bool, "with_movy", true);  // NEW
   ```

3. **Resolve movy dependency** (build/dependencies.zig):
   ```zig
   pub const DependencyModules = struct {
       xev: *std.Build.Module,
       zli: *std.Build.Module,
       movy: ?*std.Build.Module,  // NEW - optional based on build flag
   };
   ```

4. **Wire movy module** (build/modules.zig):
   ```zig
   const imports = &.{
       .{ .name = "build_options", .module = ... },
       .{ .name = "wayland_client", .module = ... },
       .{ .name = "xev", .module = ... },
       .{ .name = "zli", .module = ... },
       .{ .name = "movy", .module = config.dependencies.movy },  // NEW
   };
   ```

5. **Conditional compilation in source:**
   ```zig
   const build_options = @import("build_options");
   const movy = if (build_options.with_movy) @import("movy") else struct {};
   ```

### Implementation Strategy: Backend Abstraction

**Current Architecture Issue:** RenderThread.zig is **tightly coupled to Wayland/Vulkan**:
```zig
pub fn threadMain(mailboxes: *Mailboxes, running: *std.atomic.Value(bool), config: ThreadConfig) void {
    // HARD-CODED Wayland initialization
    var wayland: WaylandState = undefined;
    WaylandLogic.init(&wayland, ...) catch return;

    // HARD-CODED Vulkan initialization
    var vulkan = VulkanLogic.init(..., &wayland) catch return;

    while (!wayland.closed and running.load(.acquire)) {
        // HARD-CODED Wayland dispatch
        _ = WaylandLogic.dispatchOnce(&wayland);

        // Frame rendering (only part that's reusable)
        if (mailboxes.frame.hasNewFrame()) {
            const frame_buffer = mailboxes.frame.getReadBuffer();
            VulkanLogic.renderFrame(&vulkan, frame_buffer) catch continue;
            mailboxes.frame.consumeFrame();
        }
    }
}
```

**Proposed Abstraction - Minimal Intrusion:**

**Option A: Backend Enum + Comptime Dispatch (Recommended)**
```zig
// src/threads/RenderThread.zig
pub const Backend = enum { wayland_vulkan, terminal_movy };

pub fn spawn(
    mailboxes: *Mailboxes,
    running: *std.atomic.Value(bool),
    config: ThreadConfig,
    backend: Backend,  // NEW parameter
) !std.Thread {
    return switch (backend) {
        .wayland_vulkan => spawnWaylandVulkan(mailboxes, running, config),
        .terminal_movy => spawnTerminalMovy(mailboxes, running, config),
    };
}

// Keep existing code in separate function
fn spawnWaylandVulkan(...) !std.Thread {
    // Current RenderThread.threadMain implementation
}

// New terminal backend
fn spawnTerminalMovy(
    mailboxes: *Mailboxes,
    running: *std.atomic.Value(bool),
    config: ThreadConfig,
) !std.Thread {
    return try std.Thread.spawn(.{}, terminalThreadMain, .{ mailboxes, running, config });
}

fn terminalThreadMain(
    mailboxes: *Mailboxes,
    running: *std.atomic.Value(bool),
    config: ThreadConfig,
) void {
    // Initialize movy terminal renderer
    var terminal = MovyTerminal.init() catch return;
    defer terminal.deinit();

    while (running.load(.acquire)) {
        // Poll for terminal input events (keyboard)
        terminal.pollInput() catch {};

        // Render new frames
        if (mailboxes.frame.hasNewFrame()) {
            const frame_buffer = mailboxes.frame.getReadBuffer();
            terminal.renderFrame(frame_buffer) catch continue;
            mailboxes.frame.consumeFrame();
        }

        std.Thread.sleep(16_000_000); // 16ms (~60 FPS)
    }
}
```

**Option B: Backend Trait (More Flexible, More Complex)**
```zig
// src/video/Backend.zig - Abstract interface
pub const Backend = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        init: *const fn (allocator: Allocator) anyerror!*anyopaque,
        deinit: *const fn (ptr: *anyopaque) void,
        renderFrame: *const fn (ptr: *anyopaque, frame: []const u32) anyerror!void,
        pollInput: *const fn (ptr: *anyopaque) anyerror!void,
        shouldClose: *const fn (ptr: *anyopaque) bool,
    };
};

// src/video/WaylandVulkanBackend.zig
pub const WaylandVulkanBackend = struct {
    wayland: WaylandState,
    vulkan: VulkanState,

    pub fn backend(self: *WaylandVulkanBackend) Backend {
        return .{ .ptr = self, .vtable = &vtable };
    }

    const vtable = Backend.VTable{
        .init = init,
        .deinit = deinit,
        .renderFrame = renderFrame,
        .pollInput = pollInput,
        .shouldClose = shouldClose,
    };
};

// src/video/MovyBackend.zig
pub const MovyBackend = struct {
    movy_state: MovyState,

    pub fn backend(self: *MovyBackend) Backend { ... }
};
```

**Recommendation:** Start with **Option A (comptime dispatch)** for simplicity. If more backends are needed later (e.g., headless, SDL), refactor to Option B.

### CLI Integration: Runtime Backend Selection

**Current CLI Parsing** (src/main.zig using zli):
```zig
const app = try zli.Command.init(&writer, allocator, .{
    .name = "rambo",
    .version = ...,
    .description = "RAMBO NES Emulator",
}, mainExec);

// Positional argument
try app.addPositionalArg(.{ .name = "rom", .required = true });

// Flags
try app.addFlag(.{ .name = "trace", .type = .Bool, .default_value = .{ .Bool = false } });
try app.addFlag(.{ .name = "inspect", .type = .Bool, ... });
```

**Add Backend Flag:**
```zig
try app.addFlag(.{
    .name = "backend",
    .description = "Rendering backend: 'wayland' (graphical) or 'terminal' (movy)",
    .type = .String,
    .default_value = .{ .String = "wayland" },
});
```

**Parse and Route in mainExec:**
```zig
fn mainExec(ctx: zli.CommandContext) !void {
    const backend_str = ctx.flag("backend", []const u8);
    const backend: RenderThread.Backend = blk: {
        if (std.mem.eql(u8, backend_str, "terminal")) {
            break :blk .terminal_movy;
        } else if (std.mem.eql(u8, backend_str, "wayland")) {
            break :blk .wayland_vulkan;
        } else {
            try ctx.writer.print("Error: Unknown backend '{s}'. Use 'wayland' or 'terminal'.\n", .{backend_str});
            return error.InvalidBackend;
        }
    };

    // Spawn render thread with selected backend
    const render_thread = try RenderThread.spawn(&mailboxes, &running, .{}, backend);
}
```

### Terminal Input Handling Strategy

**Problem:** Terminal input needs to update ControllerInputMailbox without going through Wayland events.

**Solution:** Terminal backend posts input events to **XdgInputEventMailbox** (reuse existing mailbox), main thread processes as normal.

**Movy Input Handling** (in terminalThreadMain):
```zig
fn terminalThreadMain(...) void {
    var terminal = MovyTerminal.init() catch return;
    defer terminal.deinit();

    while (running.load(.acquire)) {
        // Poll terminal for keyboard events
        var events: [32]MovyKeyEvent = undefined;
        const event_count = terminal.pollKeyboardEvents(&events) catch 0;

        for (events[0..event_count]) |event| {
            // Convert movy key event to XdgInputEvent
            const xdg_event: XdgInputEvent = switch (event.action) {
                .press => .{ .key_press = .{ .keysym = movyKeyToXkbKeysym(event.key) } },
                .release => .{ .key_release = .{ .keysym = movyKeyToXkbKeysym(event.key) } },
            };

            // Post to input mailbox (same path as Wayland)
            _ = mailboxes.xdg_input_event.postEvent(xdg_event);
        }

        // Render frames...
    }
}

// Map movy key codes to XKB keysyms (reuse KeyboardMapper constants)
fn movyKeyToXkbKeysym(key: MovyKey) u32 {
    return switch (key) {
        .up => KeyboardMapper.Keymap.KEY_UP,
        .down => KeyboardMapper.Keymap.KEY_DOWN,
        .left => KeyboardMapper.Keymap.KEY_LEFT,
        .right => KeyboardMapper.Keymap.KEY_RIGHT,
        .z => KeyboardMapper.Keymap.KEY_Z,
        .x => KeyboardMapper.Keymap.KEY_X,
        // ... etc
        else => 0, // Unknown key
    };
}
```

**Why This Works:**
- Main thread already processes XdgInputEventMailbox and feeds KeyboardMapper
- No changes needed to main thread coordination loop
- Terminal backend acts like "virtual Wayland compositor" posting events
- ControllerInputMailbox flow remains unchanged

### Movy Library Integration (External Research Required)

**TODO:** Fetch movy documentation from GitHub to understand:
1. **Initialization:** How to create a movy render surface in terminal
2. **Frame Format:** Does movy accept RGBA u32 buffers? Or does it need RGB conversion?
3. **Rendering:** How to blit 256×240 frame to terminal (scaling/aspect ratio)
4. **Input:** How to poll keyboard events from terminal (raw mode, escape sequences)
5. **Cleanup:** Proper shutdown sequence (restore terminal mode)

**Expected Movy API (hypothetical - verify with actual docs):**
```zig
const movy = @import("movy");

pub const MovyTerminal = struct {
    surface: movy.RenderSurface,

    pub fn init() !MovyTerminal {
        var surface = try movy.RenderSurface.init(.{
            .width = 256,
            .height = 240,
            .title = "RAMBO NES Emulator (Terminal)",
        });
        return .{ .surface = surface };
    }

    pub fn deinit(self: *MovyTerminal) void {
        self.surface.deinit();
    }

    pub fn renderFrame(self: *MovyTerminal, frame: []const u32) !void {
        // Convert RGBA u32 to movy's expected format (if needed)
        // Blit to terminal with block/braille characters
        try self.surface.draw(frame);
        try self.surface.present();
    }

    pub fn pollKeyboardEvents(self: *MovyTerminal, events: []MovyKeyEvent) !usize {
        return self.surface.pollInput(events);
    }
};
```

**Critical Questions for Movy Research:**
- Does movy support 256×240 resolution or require power-of-2 dimensions?
- Does movy handle aspect ratio correction (NES uses 8:7 pixel aspect)?
- Can movy run without a full TTY (e.g., via SSH with TERM=xterm-256color)?
- What's the overhead of terminal rendering (can it maintain 60 FPS)?

### Technical Reference

#### File Locations for Implementation

**Core Files to Modify:**
- `src/threads/RenderThread.zig` - Add backend enum, split threadMain into backend-specific functions
- `src/main.zig` - Add CLI flag parsing for backend selection, pass to RenderThread.spawn()
- `build.zig.zon` - Add movy dependency
- `build/dependencies.zig` - Resolve movy module
- `build/modules.zig` - Wire movy import to RAMBO module

**New Files to Create:**
- `src/video/MovyBackend.zig` - Movy terminal rendering implementation
- `src/video/MovyState.zig` - Movy state structure (if needed)

**Related Files (Read-Only Reference):**
- `src/mailboxes/FrameMailbox.zig` - Frame buffer format and triple-buffering logic
- `src/mailboxes/XdgInputEventMailbox.zig` - Input event mailbox interface
- `src/input/KeyboardMapper.zig` - XKB keysym constants and button mapping
- `src/input/ButtonState.zig` - NES button state structure
- `src/video/VulkanLogic.zig` - Reference implementation of renderFrame()
- `src/video/WaylandLogic.zig` - Reference implementation of input event dispatch

#### Data Structures

**Frame Buffer Format:**
```zig
// src/mailboxes/FrameMailbox.zig
pub const FRAME_WIDTH = 256;
pub const FRAME_HEIGHT = 240;
pub const FRAME_PIXELS = 61_440;
pub const FrameBuffer = [FRAME_PIXELS]u32;  // RGBA little-endian (0xAABBGGRR)
```

**Input Event Format:**
```zig
// src/mailboxes/XdgInputEventMailbox.zig
pub const XdgInputEvent = union(enum) {
    key_press: struct { keysym: u32 },    // XKB keysym
    key_release: struct { keysym: u32 },
    mouse_motion: struct { x: f32, y: f32 },
    mouse_button_press: struct { button: u32 },
    mouse_button_release: struct { button: u32 },
};

// Mailbox API
pub fn postEvent(self: *XdgInputEventMailbox, event: XdgInputEvent) bool;
pub fn drainEvents(self: *XdgInputEventMailbox, buffer: []XdgInputEvent) usize;
```

**Button State Format:**
```zig
// src/input/ButtonState.zig
pub const ButtonState = packed struct(u8) {
    a: bool, b: bool, select: bool, start: bool,
    up: bool, down: bool, left: bool, right: bool,
};

// src/mailboxes/ControllerInputMailbox.zig
pub fn postController1(self: *ControllerInputMailbox, buttons: ButtonState) void;
pub fn getInput(self: *const ControllerInputMailbox) ControllerInput;
```

#### XKB Keysym Constants (Layout-Independent)

**From KeyboardMapper.Keymap:**
```zig
// Arrow keys (D-pad)
pub const KEY_UP: u32 = 0xff52;      // XKB_KEY_Up
pub const KEY_DOWN: u32 = 0xff54;    // XKB_KEY_Down
pub const KEY_LEFT: u32 = 0xff51;    // XKB_KEY_Left
pub const KEY_RIGHT: u32 = 0xff53;   // XKB_KEY_Right

// Action buttons
pub const KEY_Z: u32 = 0x007a;       // XKB_KEY_z (B button)
pub const KEY_X: u32 = 0x0078;       // XKB_KEY_x (A button)

// System buttons
pub const KEY_RSHIFT: u32 = 0xffe2;  // XKB_KEY_Shift_R (Select)
pub const KEY_ENTER: u32 = 0xff0d;   // XKB_KEY_Return (Start)
pub const KEY_KP_ENTER: u32 = 0xff8d;// XKB_KEY_KP_Enter (Start)
```

### Implementation Checklist

**Phase 1: Build System Setup**
- [ ] Add movy to build.zig.zon dependencies (fetch latest commit hash)
- [ ] Add `with_movy` build option to build/options.zig
- [ ] Resolve movy dependency in build/dependencies.zig
- [ ] Wire movy module import in build/modules.zig
- [ ] Verify build succeeds with conditional movy import in src/video/

**Phase 2: Backend Abstraction**
- [ ] Add `Backend` enum to src/threads/RenderThread.zig (.wayland_vulkan, .terminal_movy)
- [ ] Refactor existing threadMain → spawnWaylandVulkan (no logic changes)
- [ ] Add spawn() dispatcher function (comptime switch on backend)
- [ ] Verify existing Wayland/Vulkan path still works

**Phase 3: Movy Terminal Backend**
- [ ] Create src/video/MovyBackend.zig with MovyTerminal struct
- [ ] Implement init() - create movy render surface (256×240)
- [ ] Implement deinit() - cleanup and restore terminal
- [ ] Implement renderFrame() - blit RGBA u32 frame to terminal
- [ ] Implement pollKeyboardEvents() - convert movy keys to XKB keysyms
- [ ] Add terminalThreadMain() to RenderThread.zig
- [ ] Post input events to XdgInputEventMailbox

**Phase 4: CLI Integration**
- [ ] Add `--backend` flag to src/main.zig CLI parser
- [ ] Parse backend string ("wayland" | "terminal") in mainExec()
- [ ] Pass backend enum to RenderThread.spawn()
- [ ] Add error handling for invalid backend selection

**Phase 5: Testing & Validation**
- [ ] Test terminal mode with AccuracyCoin ROM (simple test suite)
- [ ] Verify input mapping works (arrow keys, Z/X, Enter)
- [ ] Test both backends coexist (no regressions in Wayland/Vulkan)
- [ ] Verify frame rate stability in terminal mode
- [ ] Test SSH remote usage (if applicable)

**Phase 6: Documentation**
- [ ] Update CLAUDE.md with terminal backend usage
- [ ] Add build instructions for movy dependency
- [ ] Document CLI flags and backend selection
- [ ] Add troubleshooting section (terminal compatibility)

### Open Questions & Research Needed

1. **Movy API Surface:** Need to fetch actual movy documentation from GitHub:
   - Initialization API (RenderSurface.init?)
   - Frame format (RGBA u32 compatible?)
   - Input polling (keyboard event structure)
   - Terminal restoration (cleanup sequence)

2. **Terminal Compatibility:** What terminals does movy support?
   - xterm-256color? truecolor?
   - SSH forwarding support?
   - Windows terminal (PowerShell/WSL)?

3. **Performance:** Can movy maintain 60 FPS with 256×240 frames?
   - Rendering overhead of terminal escape sequences
   - Block vs. braille character modes
   - Fallback for slow terminals

4. **Aspect Ratio:** Does movy handle NES 8:7 pixel aspect?
   - Automatic correction?
   - Manual scaling needed?

5. **Build Dependencies:** Does movy require system libraries?
   - Pure Zig implementation?
   - C library bindings?
   - Platform-specific (Linux-only?)

## Subtasks
<!-- List of subtask files in this directory -->

## User Notes
<!-- Any specific notes or requirements from the developer -->

## Work Log
<!-- Updated as work progresses -->
- [2025-11-01] Task created

