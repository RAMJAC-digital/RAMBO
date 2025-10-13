# Input System Design - Unified Keyboard + TAS Architecture

**Status:** Phase 3 Complete (Keyboard input wired to emulation!)
**Date:** 2025-10-07
**Last Updated:** 2025-10-07
**Goal:** Support both live keyboard input and TAS playback through single interface

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Main Thread                             │
│                                                              │
│  ┌──────────────────┐        ┌──────────────────┐          │
│  │ Keyboard Input   │        │   TAS Player     │          │
│  │                  │        │                  │          │
│  │ XdgInputEvent   │        │ Frame-based      │          │
│  │ Mailbox (SPSC)  │        │ button data      │          │
│  └────────┬─────────┘        └────────┬─────────┘          │
│           │                           │                     │
│           └───────────┬───────────────┘                     │
│                       ▼                                     │
│              ┌─────────────────┐                           │
│              │  Input Manager  │                           │
│              │                 │                           │
│              │ Maps to NES     │                           │
│              │ ButtonState     │                           │
│              └────────┬────────┘                           │
│                       ▼                                     │
│           ┌──────────────────────┐                         │
│           │ ControllerInput      │                         │
│           │ Mailbox (SPSC)       │                         │
│           └──────────┬───────────┘                         │
└──────────────────────┼──────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────┐
│                   Emulation Thread                           │
│                                                              │
│  ┌───────────────────────────────────────────┐             │
│  │        EmulationState                     │             │
│  │  ┌─────────────────────────────────┐     │             │
│  │  │     ControllerState             │     │             │
│  │  │                                 │     │             │
│  │  │  - Shift register (4021 chip)  │     │             │
│  │  │  - Strobe protocol              │     │             │
│  │  │  - Button sequence: ABSSUDLR    │     │             │
│  │  └─────────────────────────────────┘     │             │
│  └───────────────────────────────────────────┘             │
└──────────────────────────────────────────────────────────────┘
```

---

## Design Principles

1. **Single Entry Point:** ControllerInputMailbox is the ONLY interface to emulation
2. **Unified Button State:** Both keyboard and TAS produce identical ButtonState
3. **Hot-Swappable:** Can switch between keyboard/TAS without restarting
4. **Frame-Synchronized:** TAS advances one frame at a time (matches emulation)
5. **Non-Blocking:** Input processing doesn't block emulation thread

---

## Phase 1: Core Data Structures

### ButtonState (src/input/ButtonState.zig)

```zig
/// NES controller button state (8 buttons)
/// Standard NES button order: A, B, Select, Start, Up, Down, Left, Right
pub const ButtonState = packed struct(u8) {
    a: bool = false,
    b: bool = false,
    select: bool = false,
    start: bool = false,
    up: bool = false,
    down: bool = false,
    left: bool = false,
    right: bool = false,

    pub fn toByte(self: ButtonState) u8 {
        return @bitCast(self);
    }

    pub fn fromByte(byte: u8) ButtonState {
        return @bitCast(byte);
    }

    /// Enforce D-pad constraints (no opposing directions)
    pub fn sanitize(self: *ButtonState) void {
        if (self.up and self.down) {
            self.up = false;
            self.down = false;
        }
        if (self.left and self.right) {
            self.left = false;
            self.right = false;
        }
    }
};
```

### InputMode (src/input/InputMode.zig)

```zig
/// Input source for controller data
pub const InputMode = enum {
    keyboard,  // Live keyboard input from Wayland
    tas,       // Pre-recorded TAS playback
    disabled,  // No input (testing)
};
```

---

## Phase 2: Keyboard Mapping

### KeyboardMapper (src/input/KeyboardMapper.zig)

```zig
/// Maps Wayland keyboard events to NES controller buttons
pub const KeyboardMapper = struct {
    /// Current button state
    buttons: ButtonState = .{},

    /// Default keyboard mapping:
    /// Arrow keys    → D-pad
    /// Z             → B button
    /// X             → A button
    /// Right Shift   → Select
    /// Enter         → Start
    pub const Keymap = struct {
        pub const KEY_UP = 111;     // Wayland keycode
        pub const KEY_DOWN = 116;
        pub const KEY_LEFT = 113;
        pub const KEY_RIGHT = 114;
        pub const KEY_Z = 52;       // B button
        pub const KEY_X = 53;       // A button
        pub const KEY_RSHIFT = 62;  // Select
        pub const KEY_ENTER = 36;   // Start
    };

    /// Process a key press event
    pub fn keyPress(self: *KeyboardMapper, keycode: u32) void {
        switch (keycode) {
            Keymap.KEY_UP => self.buttons.up = true,
            Keymap.KEY_DOWN => self.buttons.down = true,
            Keymap.KEY_LEFT => self.buttons.left = true,
            Keymap.KEY_RIGHT => self.buttons.right = true,
            Keymap.KEY_Z => self.buttons.b = true,
            Keymap.KEY_X => self.buttons.a = true,
            Keymap.KEY_RSHIFT => self.buttons.select = true,
            Keymap.KEY_ENTER => self.buttons.start = true,
            else => {},
        }
        self.buttons.sanitize();
    }

    /// Process a key release event
    pub fn keyRelease(self: *KeyboardMapper, keycode: u32) void {
        switch (keycode) {
            Keymap.KEY_UP => self.buttons.up = false,
            Keymap.KEY_DOWN => self.buttons.down = false,
            Keymap.KEY_LEFT => self.buttons.left = false,
            Keymap.KEY_RIGHT => self.buttons.right = false,
            Keymap.KEY_Z => self.buttons.b = false,
            Keymap.KEY_X => self.buttons.a = false,
            Keymap.KEY_RSHIFT => self.buttons.select = false,
            Keymap.KEY_ENTER => self.buttons.start = false,
            else => {},
        }
    }

    /// Get current button state (for posting to mailbox)
    pub fn getState(self: *const KeyboardMapper) ButtonState {
        return self.buttons;
    }
};
```

---

## Phase 3: TAS Player

### TAS File Format (Simple Frame-Based)

```
# RAMBO TAS Format v1
# Frame | A B Select Start Up Down Left Right
0         0 0 0      0     0  0    0    0
60        0 0 0      1     0  0    0    0     # Press Start at frame 60
120       0 0 0      0     0  0    0    0     # Release Start
180       1 0 0      0     0  0    0    0     # Press A
181       0 0 0      0     0  0    0    0     # Release A
```

### TASPlayer (src/input/TASPlayer.zig)

```zig
/// Plays back pre-recorded button inputs frame-by-frame
pub const TASPlayer = struct {
    allocator: std.mem.Allocator,

    /// Sorted array of frame inputs
    inputs: std.ArrayList(FrameInput),

    /// Current playback frame
    current_frame: u64 = 0,

    /// Next input index to process
    next_input_index: usize = 0,

    pub const FrameInput = struct {
        frame: u64,
        buttons: ButtonState,
    };

    /// Load TAS file from disk
    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !TASPlayer {
        // Parse TAS file
        // Sort by frame number
        // Return initialized player
    }

    /// Advance one frame and return button state
    pub fn advance(self: *TASPlayer) ButtonState {
        defer self.current_frame += 1;

        // Check if we have an input for this frame
        if (self.next_input_index < self.inputs.items.len) {
            const next_input = self.inputs.items[self.next_input_index];
            if (next_input.frame == self.current_frame) {
                self.next_input_index += 1;
                return next_input.buttons;
            }
        }

        // No input for this frame - maintain last state
        if (self.next_input_index > 0) {
            return self.inputs.items[self.next_input_index - 1].buttons;
        }

        // No inputs yet - return empty state
        return .{};
    }
};
```

---

## Phase 4: Main Thread Integration

### Main Thread Loop (src/main.zig)

```zig
// Current coordination loop (lines 95-129)
while (running) {
    // === NEW: Input Processing ===
    if (input_mode == .keyboard) {
        // Poll keyboard events from render thread
        var input_events: [32]XdgInputEvent = undefined;
        const input_count = mailboxes.xdg_input_event.drainEvents(&input_events);

        for (input_events[0..input_count]) |event| {
            switch (event) {
                .key_press => |key| keyboard_mapper.keyPress(key.keycode),
                .key_release => |key| keyboard_mapper.keyRelease(key.keycode),
            }
        }

        // Post current button state to emulation
        const buttons = keyboard_mapper.getState();
        try mailboxes.controller_input.updateButtons(1, buttons); // Controller 1

    } else if (input_mode == .tas) {
        // Advance TAS player one frame
        const buttons = tas_player.advance();
        try mailboxes.controller_input.updateButtons(1, buttons);
    }

    // === Existing: Window/Config Events ===
    // ... (existing code)
}
```

---

## Phase 5: Testing Strategy

### Test Coverage Summary

**Total Tests:** 63 planned (21 passing, 42 scaffolded)
- ✅ ButtonState: 21/21 passing (100% coverage)
- 🔄 KeyboardMapper: 0/20 (test scaffolds ready, mock implementation complete)
- ⬜ TASPlayer: 0/18 (not yet scaffolded)
- ⬜ Integration: 0/22 (test scaffolds ready, need implementation)
- ⬜ Manual Testing: 3 manual test procedures documented

**Test Categories:**
1. **Unit Tests:** 59 tests (21 ButtonState + 20 KeyboardMapper + 18 TASPlayer)
2. **Integration Tests:** 22 tests (end-to-end flow, performance, error handling)
3. **Manual Tests:** 3 procedures (keyboard input, TAS playback, latency verification)

### Unit Tests (tests/input/)

**ButtonState Tests** (21 tests - ✅ ALL PASSING)
1. Size and layout (2 tests)
   - Size is exactly 1 byte
   - Default initialization all buttons off
2. Byte conversion (5 tests)
   - toByte/fromByte roundtrip
   - All buttons pressed toByte = 0xFF
   - No buttons pressed toByte = 0x00
   - fromByte with all bits set
3. Individual buttons (8 tests)
   - Each button sets correct bit (A=bit0, B=bit1, ..., Right=bit7)
4. Sanitization (6 tests)
   - Up+Down clears both
   - Left+Right clears both
   - Non-opposing buttons preserved
   - Diagonal (Up+Left) allowed
   - All opposing directions cleared

**KeyboardMapper Tests** (20 tests - 🔄 SCAFFOLDED, mock implementation complete)
1. Initialization (1 test)
   - Default initialization no buttons pressed
2. Individual key press (8 tests)
   - Each key sets correct button (Up, Down, Left, Right, Z→B, X→A, RShift→Select, Enter→Start)
3. Individual key release (2 tests)
   - Release Up clears up button
   - Release A clears A button
4. Multiple buttons (2 tests)
   - Press multiple buttons simultaneously
   - Press and release sequence
5. Sanitization (3 tests)
   - Opposing Up+Down cleared by sanitize
   - Opposing Left+Right cleared by sanitize
   - Diagonal input (Up+Left) allowed
6. Edge cases (4 tests)
   - Unknown keycode ignored
   - Release without press is no-op
   - Double press same key idempotent
   - Rapid press/release sequence (10 iterations)
7. State persistence (1 test)
   - State persists across unrelated key events

**TASPlayer Tests** (18 tests - ⬜ TODO, not yet scaffolded)
- Load valid TAS file
- Parse frame numbers correctly
- Parse button states correctly
- Handle comments and blank lines
- Advance frame-by-frame
- Hold state between frames
- Loop detection (optional)
- Handle missing frames
- Handle duplicate frames (error)
- Validate frame ordering

### Integration Tests (tests/integration/input_integration_test.zig)

**End-to-End Tests** (22 tests - 🔄 SCAFFOLDED, need implementation)
1. Keyboard → Mailbox → Emulation
2. TAS → Mailbox → Emulation
3. Hot-swap keyboard ↔ TAS mid-game
4. Multi-frame button sequences
5. Input latency measurement (1 frame expected)
6. Controller 1 + Controller 2 simultaneous
7. Button state persistence across frames
8. Rapid button mashing (stress test)
9. D-pad diagonal sanitization
10. Start button recognition (game unpauses)
11. Mailbox overflow handling
12. Input during VBlank vs visible scanlines

### Manual Testing Checklist

**Test 1: Keyboard Input (Balloon Fight)**
```bash
zig build run -- tests/data/Balloon\ Fight\ (USA).nes

Expected behavior:
1. Window opens showing grey screen
2. Press Enter (START) → title screen appears
3. Press Enter again → gameplay starts
4. Arrow keys → character moves
5. Z/X → character actions
```

**Test 2: TAS Playback (Automated)**
```bash
# Create test TAS file
cat > tests/data/balloon_fight_start.tas << 'EOF'
# RAMBO TAS - Press Start at frame 60
# Frame A B Select Start Up Down Left Right
0       0 0 0      0     0  0    0    0
60      0 0 0      1     0  0    0    0
61      0 0 0      0     0  0    0    0
EOF

zig build run -- tests/data/Balloon\ Fight\ (USA).nes --tas tests/data/balloon_fight_start.tas

Expected: Title screen appears after 1 second (60 frames)
```

**Test 3: Input Latency Verification**
```zig
// Add to EmulationThread.zig for testing
if (DEBUG_INPUT_LATENCY) {
    const received_frame = mailboxes.controller_input.getLastUpdateFrame();
    const current_frame = ctx.total_frames;
    const latency = current_frame - received_frame;
    std.debug.print("[Input] Latency: {d} frames\n", .{latency});
}
```

Expected: Latency = 1 frame (mailbox SPSC guarantee)

---

## Implementation Order

1. ✅ **Phase 1:** ButtonState + InputMode (30 min) - **COMPLETE**
   - ButtonState.zig implemented (170 lines)
   - 21 unit tests passing
   - Exported from RAMBO root module
2. ✅ **Phase 2:** KeyboardMapper (1 hour) - **COMPLETE**
   - KeyboardMapper.zig implemented (148 lines)
   - 20 external tests passing + 4 inline tests
   - Exported from RAMBO root module
   - Integrated into build system
3. ✅ **Phase 3:** Main thread keyboard integration (1 hour) - **COMPLETE**
   - KeyboardMapper instantiated in main thread
   - XdgInputEventMailbox drained and processed
   - ButtonState converted and posted to ControllerInputMailbox
   - Pure message passing - no shared references
4. 🔄 **Test keyboard input** (30 min) - **NEXT** ⭐ **Milestone: Playable games!**
5. **Phase 4:** TASPlayer (2 hours)
6. **Phase 5:** TAS integration + testing (1 hour)

**Total Time:** ~6 hours
**Critical Milestone:** Keyboard input now wired - games SHOULD be playable!
**Current Progress:** Phases 1-3 complete (2.5 hours completed, ~3.5 hours remaining)

---

## File Structure

```
src/input/
├── ButtonState.zig      # ✅ Core button state type (170 lines, COMPLETE)
├── KeyboardMapper.zig   # ✅ Wayland → NES mapping (148 lines, COMPLETE)
├── InputMode.zig        # Input source enum (TODO)
└── TASPlayer.zig        # TAS file playback (TODO)

tests/input/
├── button_state_test.zig      # ✅ 21 unit tests PASSING
├── keyboard_mapper_test.zig   # ✅ 20 unit tests PASSING
└── tas_player_test.zig        # 18 unit tests (TODO)

tests/integration/
└── input_integration_test.zig # ✅ 22 integration tests scaffolded (TODOs)

src/main.zig            # Modified to handle input processing (TODO)
src/root.zig            # ✅ ButtonState + KeyboardMapper exported from RAMBO module
```

**Implementation Status:**
- ✅ ButtonState.zig: Complete with 21 passing tests
- ✅ KeyboardMapper.zig: Complete with 20 passing tests + 4 inline tests
- ✅ Test infrastructure: All test files created and scaffolded
- ✅ Module exports: ButtonState + KeyboardMapper accessible via RAMBO module
- ✅ Build integration: Both test suites registered with `zig build test`
- ⬜ TASPlayer: Test scaffolds pending, implementation pending

**Test Status:** 45/63 tests passing (21 ButtonState + 24 KeyboardMapper + 0 Integration)
**Test Coverage:** ButtonState 100%, KeyboardMapper 100%, integration tests pending main thread wiring

---

## Benefits of This Design

✅ **Clean Separation:** Input logic isolated from emulation
✅ **Testable:** Each component can be unit tested
✅ **Extensible:** Easy to add gamepad support later
✅ **RT-Safe:** No heap allocations in hot path
✅ **Debuggable:** Can log all inputs for TAS creation
✅ **Simple:** Single mailbox interface to emulation

---

## Next Steps

1. ✅ Create `src/input/` directory - **COMPLETE**
2. ✅ Implement ButtonState (simplest, no dependencies) - **COMPLETE**
3. ✅ Implement KeyboardMapper (depends on ButtonState) - **COMPLETE**
   - Created `src/input/KeyboardMapper.zig` (148 lines)
   - Updated test imports to use real implementation
   - All 24 tests passing (20 external + 4 inline)
4. ✅ Wire up main thread (depends on KeyboardMapper) - **COMPLETE**
   - KeyboardMapper instantiated in main loop (line 99)
   - XdgInputEventMailbox drained and processed (lines 114-148)
   - ButtonState converted via explicit field mapping (lines 133-144)
   - Posted to ControllerInputMailbox via `postController1()` (line 147)
   - Pure message passing - no shared references
5. 🔄 **Test with keyboard - see games come alive!** 🎮 - **NEXT**

**Current Task:** Test keyboard input with a real NES ROM to verify end-to-end flow
