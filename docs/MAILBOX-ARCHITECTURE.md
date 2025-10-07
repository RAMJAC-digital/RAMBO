# Mailbox Communication Architecture

**Created:** 2025-10-06
**Status:** 🟢 **Design Complete - Ready for Phase 0 Implementation**

---

## Overview

Complete mailbox architecture for thread-safe communication between emulator, render, and coordination threads. All inter-thread communication flows through explicitly named mailboxes with clear ownership and data flow.

---

## Thread Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Main Thread                              │
│                      (Coordinator)                               │
│                                                                  │
│  - Spawns all threads                                           │
│  - Processes XDG window events → routes to mailboxes            │
│  - Processes keyboard/mouse → routes to mailboxes               │
│  - Lifecycle coordination                                        │
└────────┬────────────────────────────────────────────┬───────────┘
         │                                             │
         │ Spawns                                      │ Spawns
         │                                             │
         ▼                                             ▼
┌──────────────────────┐                    ┌────────────────────┐
│  Emulation Thread    │                    │   Render Thread    │
│   (RT-Safe)          │                    │ (Wayland + Vulkan) │
│                      │                    │                    │
│ - Timer-driven       │                    │ - XDG event loop   │
│ - Cycle-accurate     │                    │ - Vulkan present   │
│ - Speed control      │                    │ - Audio output     │
│ - Debugger support   │                    │ - Input handling   │
└──────────────────────┘                    └────────────────────┘
```

---

## Mailbox Catalog

### 1. Emulation Input Mailboxes

#### 1.1 ControllerInputMailbox (✅ EXISTS)

**Direction:** Main Thread → Emulation Thread
**Purpose:** NES controller button states
**Data:** Button state (8 buttons: A, B, Select, Start, Up, Down, Left, Right)
**Update Pattern:** Atomic swap on input event
**File:** `src/mailboxes/ControllerInputMailbox.zig`

```zig
pub const ControllerInput = struct {
    buttons: u8, // Bitfield: A=0, B=1, Select=2, Start=3, Up=4, Down=5, Left=6, Right=7
    player: u8,  // Player 1 or 2
};
```

**Flow:**
```
Wayland keyboard event → Main thread
  → Maps key to button
  → ControllerInputMailbox.post()
  → Emulation reads via $4016/$4017
```

---

#### 1.2 EmulationCommandMailbox (🆕 NEW)

**Direction:** Main Thread → Emulation Thread
**Purpose:** Lifecycle and control commands
**Data:** Power on, reset, pause, resume, save state, load state
**Update Pattern:** Command queue (FIFO)
**File:** `src/mailboxes/EmulationCommandMailbox.zig` (NEW)

```zig
pub const EmulationCommand = enum {
    power_on,        // Cold boot
    reset,           // Warm reset (NES reset button)
    pause,           // Pause emulation
    resume,          // Resume emulation
    save_state,      // Trigger snapshot save
    load_state,      // Trigger snapshot load
    shutdown,        // Clean shutdown
};

pub const EmulationCommandMailbox = struct {
    commands: RingBuffer(EmulationCommand, 16),
    mutex: std.Thread.Mutex = .{},

    pub fn postCommand(self: *EmulationCommandMailbox, cmd: EmulationCommand) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.commands.push(cmd);
    }

    pub fn pollCommand(self: *EmulationCommandMailbox) ?EmulationCommand {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.commands.pop();
    }
};
```

**Flow:**
```
User presses reset key → Main thread
  → EmulationCommandMailbox.postCommand(.reset)
  → Emulation thread polls commands
  → Executes reset logic
```

---

#### 1.3 SpeedControlMailbox (🆕 NEW)

**Direction:** Main Thread → Emulation Thread
**Purpose:** Speed and timing configuration
**Data:** Speed mode, multiplier, PAL/NTSC, hard sync enable
**Update Pattern:** Atomic swap (latest value wins)
**File:** `src/mailboxes/SpeedControlMailbox.zig` (NEW)

```zig
pub const SpeedControlConfig = struct {
    mode: SpeedMode,       // realtime, fast_forward, slow_motion, paused, stepping
    timing: TimingVariant, // ntsc, pal
    speed_multiplier: f64, // 1.0 = realtime, 2.0 = 2×, etc.
    hard_sync: bool,       // Sync to wall clock
};

pub const SpeedControlMailbox = struct {
    pending: SpeedControlConfig,
    active: SpeedControlConfig,
    mutex: std.Thread.Mutex = .{},
    has_update: std.atomic.Value(bool) = .{ .raw = false },

    pub fn postUpdate(self: *SpeedControlMailbox, config: SpeedControlConfig) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.pending = config;
        self.has_update.store(true, .release);
    }

    pub fn pollUpdate(self: *SpeedControlMailbox) ?SpeedControlConfig {
        if (!self.has_update.load(.acquire)) return null;

        self.mutex.lock();
        defer self.mutex.unlock();
        self.has_update.store(false, .release);
        self.active = self.pending;
        return self.active;
    }
};
```

**Flow:**
```
User presses fast-forward key → Main thread
  → SpeedControlMailbox.postUpdate(.{ .mode = .fast_forward, .speed_multiplier = 4.0 })
  → Emulation thread polls in timer callback
  → Updates SpeedController
```

---

### 2. Emulation Output Mailboxes

#### 2.1 FrameMailbox (✅ EXISTS - NEEDS ENHANCEMENT)

**Direction:** Emulation Thread → Render Thread
**Purpose:** Completed video frames (256×240 RGBA)
**Data:** Double-buffered pixel data
**Update Pattern:** Buffer swap with atomic flag
**File:** `src/mailboxes/FrameMailbox.zig`

```zig
pub const FrameMailbox = struct {
    write_buffer: *FrameBuffer,  // Emulation writes here
    read_buffer: *FrameBuffer,   // Render reads here
    mutex: std.Thread.Mutex = .{},
    has_new_frame: std.atomic.Value(bool) = .{ .raw = false }, // 🆕 ADD THIS

    // 🆕 ADD THESE METHODS
    pub fn hasNewFrame(self: *const FrameMailbox) bool {
        return self.has_new_frame.load(.acquire);
    }

    pub fn postFrame(self: *FrameMailbox) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        std.mem.swap(*FrameBuffer, &self.write_buffer, &self.read_buffer);
        self.has_new_frame.store(true, .release);
    }

    pub fn consumeFrame(self: *FrameMailbox) ?[]const u32 {
        if (!self.has_new_frame.load(.acquire)) return null;
        self.has_new_frame.store(false, .release);
        return self.read_buffer.pixels[0..];
    }
};
```

**Flow:**
```
Emulation completes frame → PPU writes pixels to write_buffer
  → FrameMailbox.postFrame() (swaps buffers)
  → Render thread polls hasNewFrame()
  → consumeFrame() → uploads to Vulkan texture
```

---

#### 2.2 AudioSampleMailbox (🆕 NEW - Future Phase)

**Direction:** Emulation Thread → Render Thread (or Audio Thread)
**Purpose:** Audio samples from APU
**Data:** Ring buffer of f32 samples
**Update Pattern:** Lock-free ring buffer
**File:** `src/mailboxes/AudioSampleMailbox.zig` (FUTURE)

```zig
// Future: APU audio output
pub const AudioSampleMailbox = struct {
    samples: RingBuffer(f32, 4096), // ~85ms at 48kHz
    // Lock-free SPSC queue
};
```

**Flow:**
```
APU generates sample → AudioSampleMailbox.pushSample()
  → Audio callback reads samples
  → Outputs to system audio
```

---

#### 2.3 EmulationStatusMailbox (🆕 NEW)

**Direction:** Emulation Thread → Main Thread
**Purpose:** Status updates, statistics, errors
**Data:** FPS, frame count, errors, state changes
**Update Pattern:** Atomic swap (latest value wins)
**File:** `src/mailboxes/EmulationStatusMailbox.zig` (NEW)

```zig
pub const EmulationStatus = struct {
    fps: f64,              // Current FPS
    frame_count: u64,      // Total frames emulated
    is_running: bool,      // Emulation running
    is_paused: bool,       // Emulation paused
    current_mode: SpeedMode,
    error_message: ?[]const u8, // Last error (null = no error)
};

pub const EmulationStatusMailbox = struct {
    status: EmulationStatus,
    mutex: std.Thread.Mutex = .{},

    pub fn updateStatus(self: *EmulationStatusMailbox, new_status: EmulationStatus) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.status = new_status;
    }

    pub fn getStatus(self: *EmulationStatusMailbox) EmulationStatus {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.status;
    }
};
```

**Flow:**
```
Emulation thread updates FPS every second
  → EmulationStatusMailbox.updateStatus()
  → Main thread polls for UI display
  → Logs or displays to user
```

---

### 3. Render Thread Mailboxes

#### 3.1 XdgWindowEventMailbox (✅ EXISTS - RENAME)

**Current Name:** `WaylandEventMailbox`
**New Name:** `XdgWindowEventMailbox` (clearer purpose)
**Direction:** Render Thread → Main Thread
**Purpose:** XDG window protocol events (resize, close, focus)
**Data:** Window state changes
**Update Pattern:** Event queue (batch processing)
**File:** `src/mailboxes/XdgWindowEventMailbox.zig` (RENAME FROM WaylandEventMailbox.zig)

```zig
pub const XdgWindowEvent = union(enum) {
    window_resize: struct { width: u32, height: u32 },
    window_close: void,
    window_focus: struct { focused: bool },
    window_state: struct { fullscreen: bool, maximized: bool },
};

pub const XdgWindowEventMailbox = struct {
    pending: std.ArrayList(XdgWindowEvent),
    processing: std.ArrayList(XdgWindowEvent),
    mutex: std.Thread.Mutex = .{},

    pub fn postEvent(self: *XdgWindowEventMailbox, event: XdgWindowEvent) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.pending.append(event);
    }

    pub fn swapAndGetEvents(self: *XdgWindowEventMailbox) []XdgWindowEvent {
        self.mutex.lock();
        defer self.mutex.unlock();
        std.mem.swap(std.ArrayList(XdgWindowEvent), &self.pending, &self.processing);
        self.pending.clearRetainingCapacity();
        return self.processing.items;
    }
};
```

**Flow:**
```
XDG toplevel configure callback → Render thread
  → XdgWindowEventMailbox.postEvent(.window_resize)
  → Main thread processes events
  → May update config or notify user
```

---

#### 3.2 XdgInputEventMailbox (🆕 NEW)

**Direction:** Render Thread → Main Thread
**Purpose:** XDG input protocol events (keyboard, mouse)
**Data:** Raw input events from Wayland seat
**Update Pattern:** Event queue (batch processing)
**File:** `src/mailboxes/XdgInputEventMailbox.zig` (NEW)

```zig
pub const XdgInputEvent = union(enum) {
    key_press: struct { keycode: u32, modifiers: u32 },
    key_release: struct { keycode: u32, modifiers: u32 },
    mouse_move: struct { x: f64, y: f64 },
    mouse_button: struct { button: u32, pressed: bool },
};

pub const XdgInputEventMailbox = struct {
    pending: std.ArrayList(XdgInputEvent),
    processing: std.ArrayList(XdgInputEvent),
    mutex: std.Thread.Mutex = .{},

    pub fn postEvent(self: *XdgInputEventMailbox, event: XdgInputEvent) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.pending.append(event);
    }

    pub fn swapAndGetEvents(self: *XdgInputEventMailbox) []XdgInputEvent {
        self.mutex.lock();
        defer self.mutex.unlock();
        std.mem.swap(std.ArrayList(XdgInputEvent), &self.pending, &self.processing);
        self.pending.clearRetainingCapacity();
        return self.processing.items;
    }
};
```

**Flow:**
```
Wayland keyboard callback → Render thread
  → XdgInputEventMailbox.postEvent(.key_press)
  → Main thread processes events
  → Maps to NES buttons → ControllerInputMailbox
  → Or maps to emulator commands → EmulationCommandMailbox
```

---

#### 3.3 RenderStatusMailbox (🆕 NEW)

**Direction:** Render Thread → Main Thread
**Purpose:** Render thread status and errors
**Data:** Display FPS, Vulkan errors, swapchain recreations
**Update Pattern:** Atomic swap (latest value wins)
**File:** `src/mailboxes/RenderStatusMailbox.zig` (NEW)

```zig
pub const RenderStatus = struct {
    display_fps: f64,         // Actual display refresh rate
    frames_rendered: u64,     // Total frames displayed
    is_running: bool,         // Render thread active
    vulkan_error: ?[]const u8, // Last Vulkan error
    window_size: struct { width: u32, height: u32 },
};

pub const RenderStatusMailbox = struct {
    status: RenderStatus,
    mutex: std.Thread.Mutex = .{},

    pub fn updateStatus(self: *RenderStatusMailbox, new_status: RenderStatus) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.status = new_status;
    }

    pub fn getStatus(self: *RenderStatusMailbox) RenderStatus {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.status;
    }
};
```

**Flow:**
```
Render thread updates display FPS
  → RenderStatusMailbox.updateStatus()
  → Main thread polls for logging/debugging
```

---

### 4. File Operation Mailboxes (Future)

#### 4.1 FileOperationMailbox (🆕 NEW - Future)

**Direction:** Main Thread → File I/O Thread
**Purpose:** Async file operations (ROM load, save states)
**Data:** File operation commands with callbacks
**Update Pattern:** Command queue
**File:** `src/mailboxes/FileOperationMailbox.zig` (FUTURE)

```zig
pub const FileOperation = union(enum) {
    load_rom: struct { path: []const u8, callback: *const fn(?[]const u8) void },
    save_state: struct { path: []const u8, data: []const u8, callback: *const fn(bool) void },
    load_state: struct { path: []const u8, callback: *const fn(?[]const u8) void },
};
```

**Note:** File operations are separate from XDG events but may be triggered by XDG file picker dialogs.

---

## Mailbox Container

### Updated Mailboxes.zig

```zig
//! Central mailbox container for dependency injection
//! Eliminates global state by providing a single struct that owns all mailbox instances

const std = @import("std");

pub const Mailboxes = struct {
    // ========================================================================
    // Emulation Input Mailboxes (Main → Emulation)
    // ========================================================================

    /// NES controller button states
    controller_input: ControllerInputMailbox,

    /// Lifecycle commands (power, reset, pause, etc.)
    emulation_command: EmulationCommandMailbox,

    /// Speed and timing configuration
    speed_control: SpeedControlMailbox,

    // ========================================================================
    // Emulation Output Mailboxes (Emulation → Render/Main)
    // ========================================================================

    /// Completed video frames (256×240 RGBA)
    frame: FrameMailbox,

    /// Audio samples (future)
    // audio_samples: AudioSampleMailbox,

    /// Emulation status and statistics
    emulation_status: EmulationStatusMailbox,

    // ========================================================================
    // Render Thread Mailboxes (Render → Main)
    // ========================================================================

    /// XDG window events (resize, close, focus)
    xdg_window_event: XdgWindowEventMailbox,

    /// XDG input events (keyboard, mouse)
    xdg_input_event: XdgInputEventMailbox,

    /// Render thread status
    render_status: RenderStatusMailbox,

    // ========================================================================
    // File Operations (Future)
    // ========================================================================

    // file_operation: FileOperationMailbox,

    pub fn init(allocator: std.mem.Allocator) !Mailboxes {
        return Mailboxes{
            // Emulation input
            .controller_input = ControllerInputMailbox.init(),
            .emulation_command = try EmulationCommandMailbox.init(allocator),
            .speed_control = SpeedControlMailbox.init(),

            // Emulation output
            .frame = try FrameMailbox.init(allocator),
            .emulation_status = EmulationStatusMailbox.init(),

            // Render thread
            .xdg_window_event = try XdgWindowEventMailbox.init(allocator),
            .xdg_input_event = try XdgInputEventMailbox.init(allocator),
            .render_status = RenderStatusMailbox.init(),
        };
    }

    pub fn deinit(self: *Mailboxes) void {
        self.render_status.deinit();
        self.xdg_input_event.deinit();
        self.xdg_window_event.deinit();
        self.emulation_status.deinit();
        self.frame.deinit();
        self.speed_control.deinit();
        self.emulation_command.deinit();
        self.controller_input.deinit();
    }
};
```

---

## Communication Flows

### Flow 1: User Presses NES Button

```
User presses "Z" key (mapped to A button)
  ↓
Wayland keyboard callback (render thread)
  ↓
XdgInputEventMailbox.postEvent(.key_press { keycode=Z })
  ↓
Main thread swapAndGetEvents()
  ↓
Maps keycode to NES button (Z → A button)
  ↓
ControllerInputMailbox.updateButtons(player=1, A=pressed)
  ↓
Emulation thread reads $4016
  ↓
Returns button state to game
```

### Flow 2: User Presses Reset

```
User presses "R" key (mapped to reset)
  ↓
Wayland keyboard callback (render thread)
  ↓
XdgInputEventMailbox.postEvent(.key_press { keycode=R })
  ↓
Main thread processes event
  ↓
Recognizes reset hotkey
  ↓
EmulationCommandMailbox.postCommand(.reset)
  ↓
Emulation thread polls commands
  ↓
Executes CPU/PPU reset logic
```

### Flow 3: User Resizes Window

```
User drags window corner
  ↓
XDG toplevel configure callback (render thread)
  ↓
XdgWindowEventMailbox.postEvent(.window_resize { 1024, 768 })
  ↓
Main thread swapAndGetEvents()
  ↓
Logs resize event
  ↓
Render thread handles resize independently
  ↓
Recreates Vulkan swapchain
```

### Flow 4: User Presses Fast Forward

```
User presses Tab key (fast forward)
  ↓
Wayland keyboard callback (render thread)
  ↓
XdgInputEventMailbox.postEvent(.key_press { keycode=Tab })
  ↓
Main thread processes event
  ↓
Recognizes fast-forward hotkey
  ↓
SpeedControlMailbox.postUpdate(.{ .mode = .fast_forward, .speed_multiplier = 4.0 })
  ↓
Emulation thread polls in timer callback
  ↓
Updates SpeedController
  ↓
Emulation runs at 4× speed
```

### Flow 5: Emulation Frame Complete

```
Emulation completes frame (29781 cycles)
  ↓
PPU writes pixels to FrameMailbox.write_buffer
  ↓
FrameMailbox.postFrame() (swaps buffers, sets has_new_frame)
  ↓
Render thread polls hasNewFrame() → true
  ↓
consumeFrame() → gets read_buffer slice
  ↓
Uploads to Vulkan texture
  ↓
vkQueuePresentKHR (vsync here)
```

---

## XDG Communication Clarification

### Who Talks to XDG?

**Render Thread ONLY:**
- Initializes Wayland connection (`wl_display_connect`)
- Binds XDG protocols (xdg_wm_base, wl_seat, wl_compositor)
- Registers protocol callbacks
- Dispatches Wayland events (`wl_display_dispatch_pending`)
- Processes input from wl_seat (keyboard, pointer)
- Processes window events from xdg_surface/xdg_toplevel

**Main Thread:**
- Never touches Wayland directly
- Receives events via mailboxes (XdgWindowEventMailbox, XdgInputEventMailbox)
- Processes events and routes to other mailboxes

**Emulation Thread:**
- Never touches Wayland or XDG
- Completely isolated
- Only knows about mailboxes

### XDG Event Routing

```
XDG Protocol Events (in render thread)
  ↓
Categorize:
  - Window events → XdgWindowEventMailbox
  - Input events → XdgInputEventMailbox
  ↓
Main thread processes mailboxes
  ↓
Route:
  - Controller input → ControllerInputMailbox
  - Emulator commands → EmulationCommandMailbox
  - Speed control → SpeedControlMailbox
  - Window lifecycle → shutdown flag
```

---

## Testing Strategy (Phase 0)

### Test 1: Mailbox Isolation

**Purpose:** Verify mailboxes work independently
**File:** `tests/mailboxes/isolation_test.zig`

```zig
test "mailbox isolation - no cross-contamination" {
    var mailboxes = try Mailboxes.init(testing.allocator);
    defer mailboxes.deinit();

    // Post to controller input
    mailboxes.controller_input.updateButtons(1, 0xFF);

    // Verify other mailboxes unaffected
    try testing.expect(!mailboxes.frame.hasNewFrame());
    try testing.expect(mailboxes.emulation_command.pollCommand() == null);
}
```

### Test 2: Controller Input Flow

**Purpose:** End-to-end controller input
**File:** `tests/mailboxes/controller_flow_test.zig`

```zig
test "controller input flow" {
    var mailboxes = try Mailboxes.init(testing.allocator);
    defer mailboxes.deinit();

    // Simulate: XDG input → Main → Controller mailbox
    const xdg_event = .{ .key_press = .{ .keycode = KEY_Z, .modifiers = 0 } };
    try mailboxes.xdg_input_event.postEvent(xdg_event);

    // Main thread processes
    const events = mailboxes.xdg_input_event.swapAndGetEvents();
    try testing.expectEqual(@as(usize, 1), events.len);

    // Map to NES button (Z → A)
    const button_mask: u8 = 0x01; // A button
    mailboxes.controller_input.updateButtons(1, button_mask);

    // Emulation reads
    const buttons = mailboxes.controller_input.getButtons(1);
    try testing.expectEqual(button_mask, buttons);
}
```

### Test 3: Frame Mailbox Lock-Free

**Purpose:** Verify lock-free hasNewFrame check
**File:** `tests/mailboxes/frame_lockfree_test.zig`

```zig
test "frame mailbox lock-free check" {
    var mailboxes = try Mailboxes.init(testing.allocator);
    defer mailboxes.deinit();

    // Initially no frame
    try testing.expect(!mailboxes.frame.hasNewFrame());

    // Post frame
    const write_buf = mailboxes.frame.getWriteBuffer();
    @memset(write_buf, 0xFF0000FF); // Red
    mailboxes.frame.postFrame();

    // Lock-free check
    try testing.expect(mailboxes.frame.hasNewFrame());

    // Consume
    const frame = mailboxes.frame.consumeFrame();
    try testing.expect(frame != null);
    try testing.expectEqual(@as(u32, 0xFF0000FF), frame.?[0]);

    // No longer has new frame
    try testing.expect(!mailboxes.frame.hasNewFrame());
}
```

### Test 4: Command Mailbox FIFO

**Purpose:** Verify command ordering
**File:** `tests/mailboxes/command_order_test.zig`

```zig
test "emulation command mailbox preserves order" {
    var mailboxes = try Mailboxes.init(testing.allocator);
    defer mailboxes.deinit();

    // Post multiple commands
    try mailboxes.emulation_command.postCommand(.power_on);
    try mailboxes.emulation_command.postCommand(.reset);
    try mailboxes.emulation_command.postCommand(.pause);

    // Poll in order
    try testing.expectEqual(.power_on, mailboxes.emulation_command.pollCommand().?);
    try testing.expectEqual(.reset, mailboxes.emulation_command.pollCommand().?);
    try testing.expectEqual(.pause, mailboxes.emulation_command.pollCommand().?);
    try testing.expect(mailboxes.emulation_command.pollCommand() == null);
}
```

### Test 5: Speed Control Atomic Update

**Purpose:** Verify latest-value-wins
**File:** `tests/mailboxes/speed_atomic_test.zig`

```zig
test "speed control mailbox atomic update" {
    var mailboxes = try Mailboxes.init(testing.allocator);
    defer mailboxes.deinit();

    // Post multiple updates rapidly
    mailboxes.speed_control.postUpdate(.{ .mode = .realtime, .speed_multiplier = 1.0 });
    mailboxes.speed_control.postUpdate(.{ .mode = .fast_forward, .speed_multiplier = 4.0 });

    // Only latest matters
    const config = mailboxes.speed_control.pollUpdate().?;
    try testing.expectEqual(.fast_forward, config.mode);
    try testing.expectEqual(@as(f64, 4.0), config.speed_multiplier);
}
```

### Test 6: Multi-Threaded Stress

**Purpose:** Verify thread safety under load
**File:** `tests/mailboxes/multithread_stress_test.zig`

```zig
test "mailbox thread safety - stress test" {
    var mailboxes = try Mailboxes.init(testing.allocator);
    defer mailboxes.deinit();

    var running = std.atomic.Value(bool).init(true);

    // Spawn emulation thread (posts frames)
    const emu_thread = try std.Thread.spawn(.{}, emuThreadStress, .{ &mailboxes, &running });

    // Spawn render thread (consumes frames)
    const render_thread = try std.Thread.spawn(.{}, renderThreadStress, .{ &mailboxes, &running });

    // Run for 1 second
    std.Thread.sleep(1_000_000_000);
    running.store(false, .release);

    emu_thread.join();
    render_thread.join();

    // Verify no crashes, no deadlocks
    // Success = test completes
}
```

---

## Phase 0: Mailbox Implementation & Testing

### Phase 0.1: Implement New Mailboxes (4-6 hours)

**Tasks:**

1. **EmulationCommandMailbox** (1-2 hours)
   - Ring buffer implementation
   - FIFO command queue
   - Thread-safe push/pop

2. **SpeedControlMailbox** (1-2 hours)
   - Atomic swap implementation
   - Config struct definition
   - Latest-value-wins semantics

3. **XdgInputEventMailbox** (1 hour)
   - Rename WaylandEventMailbox → XdgWindowEventMailbox
   - Create new XdgInputEventMailbox
   - Separate window vs input events

4. **Status Mailboxes** (1-2 hours)
   - EmulationStatusMailbox
   - RenderStatusMailbox
   - Atomic status updates

5. **Update FrameMailbox** (1 hour)
   - Add `has_new_frame` flag
   - Implement lock-free methods
   - Update tests

**Deliverable:** All mailboxes implemented with unit tests

### Phase 0.2: Mailbox Testing (4-6 hours)

**Tasks:**

1. **Unit Tests** (2-3 hours)
   - Test each mailbox independently
   - Verify API contracts
   - Edge cases (empty, full, overflow)

2. **Integration Tests** (2-3 hours)
   - Multi-threaded tests
   - Stress tests
   - Flow tests (end-to-end scenarios)

3. **Documentation** (1 hour)
   - Update Mailboxes.zig docs
   - Add usage examples
   - Document thread safety guarantees

**Deliverable:** Comprehensive test suite, all tests passing

### Phase 0.3: Update Existing Code (2-3 hours)

**Tasks:**

1. **Update main.zig** (1 hour)
   - Initialize new mailboxes
   - Update emulation thread to use EmulationCommandMailbox
   - Update coordination loop

2. **Update Existing Tests** (1-2 hours)
   - Fix any broken tests due to mailbox changes
   - Update integration tests

**Deliverable:** All existing tests passing with new mailbox architecture

---

## Success Criteria - Phase 0

- ✅ All 8 mailboxes implemented
- ✅ Each mailbox has unit tests
- ✅ Multi-threaded stress tests pass (1000+ iterations)
- ✅ No deadlocks, no race conditions
- ✅ All existing tests still pass
- ✅ Documentation updated
- ✅ Ready for Phase 1 (Wayland integration)

---

**Status:** 🟢 **Design Complete**
**Next:** Implement Phase 0 - Mailbox architecture and testing
