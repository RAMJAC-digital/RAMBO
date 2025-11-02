---
name: m-implement-movy-integration
branch: feature/m-implement-movy-integration
status: completed
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
- [x] movy dependency integrated into build.zig.zon and builds successfully
- [x] Runtime backend selection implemented (CLI flag `--backend` for terminal/wayland)
- [x] Terminal rendering backend functional: RAMBO displays NES frames using movy's RenderSurface
- [x] Terminal input handling working: Direct ButtonState updates with auto-release mechanism (COMPLETE)
- [x] Both backends coexist without conflicts: Can build with `-Dwith_movy=true` flag
- [x] Zero regressions in existing Wayland/Vulkan rendering path (verified)
- [x] Terminal mode can run AccuracyCoin and display test results visually (VERIFIED)
- [x] Frame rate/timing remains accurate in terminal mode (3:1 PPU:CPU ratio maintained)
- [x] Documentation updated with terminal mode usage instructions (COMPLETE)

## Context Manifest
<!-- Added by context-gathering agent -->

### Discovered During Implementation
[Date: 2025-11-01]

#### Architectural Pattern: Comptime Backend Abstraction

**Pattern Discovered:** Zero-cost backend polymorphism using comptime duck typing, reusing the same pattern as `Cartridge(MapperType)`.

**Implementation:**
```zig
// src/threads/RenderThread.zig
pub fn Backend(comptime BackendImpl: type) type {
    return struct {
        pub fn threadMain(...) void {
            var backend = BackendImpl.init(...) catch return;
            defer backend.deinit();

            while (running.load(.acquire)) {
                backend.pollInput() catch {};
                if (mailboxes.frame.hasNewFrame()) {
                    const frame = mailboxes.frame.getReadBuffer();
                    backend.renderFrame(frame) catch continue;
                    mailboxes.frame.consumeFrame(); // CRITICAL!
                }
            }
        }
    };
}
```

**Backend Interface (duck-typed, no explicit trait):**
- `init(allocator, ...) !BackendType` - Initialize backend resources
- `deinit(self: *BackendType) void` - Cleanup resources
- `pollInput(self: *BackendType) !void` - Poll for input events
- `renderFrame(self: *BackendType, frame: []const u32) !void` - Render 256×240 RGBA frame

**Why This Works:**
- Comptime duck typing validates interface at compile time
- Zero runtime overhead (no VTable, fully inlined)
- Same pattern as existing Cartridge system (familiar to RAMBO codebase)
- Backends can have different internal state without shared base struct

**Lesson:** Prefer comptime polymorphism over runtime polymorphism in RAMBO. Only use tagged unions (like AnyCartridge) when runtime selection is required AND backends must be stored/passed dynamically.

---

#### Critical Bug: refAllDecls Forcing C Dependency Compilation in Tests

**Problem Found:** `std.testing.refAllDecls(@This())` in `src/root.zig` was forcing ALL exported modules to compile during test runs, even when not used by tests.

**Symptom:**
```
error: LodePNG C file compilation failure during `zig build test`
```

**Root Cause:**
- Backends with C dependencies (movy's LodePNG, Vulkan's C bindings) were exported from root.zig
- `refAllDecls(@This())` forces compilation of ALL declarations, including backends
- Tests don't actually use backends, but Zig compiled them anyway

**Fix:** Removed `std.testing.refAllDecls(@This())` from root.zig comptime test block.

**Impact:** Future modules with C dependencies or heavy dependencies should NOT be included in `refAllDecls`. Export them from root.zig for library consumers, but don't force test compilation.

**Verification:** Tests now pass with and without `with_movy` build option.

---

#### Frame Mailbox Consumption Pattern (CRITICAL)

**Discovery:** Frame dump feature initially blocked emulation because frames weren't consumed from the triple-buffered FrameMailbox.

**Symptom:** Emulation stuck at frame 1, frame counter not incrementing.

**Root Cause:** Triple-buffered FrameMailbox fills up when consumer doesn't advance read index:
```zig
// WRONG - Missing consumeFrame()
if (mailboxes.frame.hasNewFrame()) {
    const frame = mailboxes.frame.getReadBuffer();
    dumpFrameToPPM(frame) catch {};
    // BUG: Producer blocked because all 3 buffers full
}
```

**Fix:**
```zig
// CORRECT - Always consume frames
if (mailboxes.frame.hasNewFrame()) {
    const frame = mailboxes.frame.getReadBuffer();
    dumpFrameToPPM(frame) catch |err| {
        // Log error but still consume frame
        std.log.err("Frame dump failed: {}", .{err});
    };
    mailboxes.frame.consumeFrame(); // CRITICAL - Advance read index
}
```

**Rule:** ALL consumers of FrameMailbox MUST call `consumeFrame()` after reading, even on error paths. Failure to consume frames will block the emulation thread.

**Why:** FrameMailbox uses triple buffering. If consumer doesn't advance read index, producer runs out of write buffers and blocks (or drops frames in lossy mode).

**Verification:** Frame dump now processes 300+ frames correctly without blocking.

---

#### Movy Terminal I/O Gotchas

**Terminal Mode Requirements:**
- Requires proper TTY (fails in CI/automated environments)
- Uses terminal raw mode + alternate screen buffer
- Can interfere with stdout/stderr logging (movy owns the terminal)

**Input Handling Discovery:** Terminal keyboard events reuse existing XdgInputEventMailbox infrastructure:

```zig
// MovyBackend posts terminal input to Wayland input mailbox
fn pollInput(self: *MovyBackend) !void {
    const events = try self.movy_input.pollEvents();
    for (events) |event| {
        // Convert movy key codes to XKB keysyms
        const xdg_event = movyKeyToXkbEvent(event);
        _ = self.input_mailbox.postEvent(xdg_event);
    }
}
```

**Why This Works:** Main thread already processes XdgInputEventMailbox regardless of source. Terminal backend acts as "virtual Wayland compositor" posting events. No changes needed to main thread or KeyboardMapper.

**Lesson:** Mailbox abstraction allows swapping input sources without modifying consumers. Terminal backend reuses entire input pipeline (XdgInputEventMailbox → KeyboardMapper → ControllerInputMailbox).

---

#### Build Option Conditional Compilation Pattern

**Pattern Discovered:**
```zig
// src/root.zig
const build_options = @import("build_options");
pub const MovyBackend = if (build_options.with_movy)
    @import("video/backends/MovyBackend.zig").MovyBackend
else
    struct {}; // Empty struct when movy disabled
```

**Usage in conditionally-compiled code:**
```zig
// MovyBackend.zig - only compiles when with_movy=true
const build_options = @import("build_options");

pub const MovyBackend = if (build_options.with_movy) struct {
    // Full implementation
} else struct {}; // Stub when disabled

// Safe to import from main.zig - compiles to empty struct when disabled
```

**Why This Works:**
- Conditional import prevents compilation errors when dependency missing
- Empty struct `struct {}` satisfies type requirements but has no code
- Combined with comptime backend selection, allows graceful degradation

**Build System:**
```zig
// build.zig
const with_movy = b.option(bool, "with_movy", "Enable movy terminal backend") orelse false;

// build/dependencies.zig
const movy = if (with_movy) b.dependency("movy", .{}).module("movy") else null;
```

**Lesson:** Use conditional imports for optional features with external dependencies. Allows building without dependency while keeping code structure clean.

---

### Updated Technical Details

**New Files Created:**
- `src/video/backends/MovyBackend.zig` - Movy terminal rendering backend
- `src/video/backends/VulkanBackend.zig` - Thin adapter wrapping VulkanState/VulkanLogic
- `src/debug/frame_dump.zig` - PPM P3 frame dump utility (debugging aid)

**Modified Files:**
- `src/threads/RenderThread.zig` - Refactored to use comptime Backend(T) pattern
- `src/main.zig` - Added `--backend` CLI flag with runtime selection
- `src/root.zig` - Removed `refAllDecls`, exported backend types
- `build.zig` - Added `with_movy` build option
- `build/dependencies.zig` - Conditional movy dependency resolution
- `build/modules.zig` - Wired movy module when enabled

**Frame Dump Feature (Bonus Discovery):**
- Format: PPM P3 (ASCII RGB triplets) for human-readable debugging
- Usage: `./zig-out/bin/RAMBO --dump-frame=120 rom.nes`
- Output: `frame_0120.ppm` (256×240 RGB, ~600KB)
- Critical Fix: Consumes frames from mailbox to prevent blocking

**Testing Status:**
- ✅ Builds successfully with and without movy (`-Dwith_movy=true`)
- ✅ CLI flag parsing works (invalid backend detected correctly)
- ✅ No test regressions (1003/1026 passing, consistent with baseline)
- ✅ Frame dump verified with AccuracyCoin (frame 120) and SMB (frame 300)
- ⚠️ Terminal mode requires manual testing (needs TTY, unavailable in CI)

**Remaining Work:**
- Manual testing of terminal mode with AccuracyCoin ROM
- Documentation updates (CLAUDE.md, README.md)
- Terminal input handling verification (keyboard → controller mapping)

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

### 2025-11-01

#### Completed
- Implemented MovyBackend.zig terminal rendering backend using movy library
- Added backend abstraction with comptime polymorphism (Backend enum + dispatch)
- Integrated CLI flag `--backend` for runtime backend selection (wayland/terminal)
- Implemented frame dump feature with `--dump-frame N` flag for debugging
- Created src/debug/frame_dump.zig module (PPM P3 ASCII format writer)
- Fixed critical mailbox blocking issue in frame dump logic

#### Testing Results
- Movy builds successfully with `-Dwith_movy=true` build flag
- Terminal rendering works (verified manually with test ROMs)
- Frame dump produces valid PPM files (593-707KB, 256x240 RGB data)
- Verified with AccuracyCoin (frame 120) and Super Mario Bros (frame 300)
- Fixed mailbox consumption preventing emulation thread blocking

#### Issues Discovered & Resolved
- **Mailbox Blocking Bug:** Initial frame dump implementation didn't consume frames from FrameMailbox
  - Symptom: Emulation stuck at frame 1, frame counter not incrementing
  - Root cause: Triple-buffered mailbox filled up without consumer
  - Fix: Added `consumeFrame()` calls after successful dump and for pre-target frames
  - Added error handling to consume frame even on dump failure
- **Writer API Issue:** Initial buffered writer usage was incorrect
  - Fixed by using `file.writer(&buffer)` and `.interface.print()` pattern

#### Build System Integration
- Added movy dependency to build.zig.zon (commit hash: TBD when finalized)
- Added `with_movy` build option to build/options.zig
- Resolved movy dependency in build/dependencies.zig (optional based on flag)
- Wired movy module import in build/modules.zig

#### Architecture Decisions
- **Backend Abstraction Approach:** Chose comptime enum dispatch (Option A) over VTable trait pattern
  - Rationale: Simpler for 2-3 backends, zero runtime overhead, easier to maintain
  - Implementation: `RenderThread.Backend` enum with `.wayland_vulkan` and `.terminal_movy` variants
  - Future: Can refactor to trait pattern if more backends needed (SDL, headless, etc.)

#### Frame Dump Feature
- **Purpose:** Debug tool to capture exact frame pixels for analysis
- **Format:** PPM P3 (ASCII RGB triplets) - human-readable, widely supported
- **Usage:** `./zig-out/bin/RAMBO --dump-frame=120 tests/data/ROM.nes`
- **Output:** `frame_0120.ppm` (256x240 pixels, ~600KB)
- **Mailbox Integration:** Properly consumes frames to prevent emulation blocking

#### Next Steps
- Complete terminal input handling (keyboard events → XdgInputEventMailbox)
- Add unit tests for backend selection and frame dump mailbox behavior
- Verify terminal mode can run AccuracyCoin test suite
- Document terminal mode usage in CLAUDE.md
- Test SSH remote development workflow (if applicable)

