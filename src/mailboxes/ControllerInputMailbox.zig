//! Controller Input Mailbox
//!
//! Atomic mailbox for NES controller button states
//! UI/Input thread posts button updates, emulation thread reads current state
//!
//! NES Controller buttons (8 per controller):
//! Bit 0: A
//! Bit 1: B
//! Bit 2: Select
//! Bit 3: Start
//! Bit 4: Up
//! Bit 5: Down
//! Bit 6: Left
//! Bit 7: Right

const std = @import("std");

/// Button state for a single NES controller (8 buttons)
pub const ButtonState = packed struct {
    a: bool = false,
    b: bool = false,
    select: bool = false,
    start: bool = false,
    up: bool = false,
    down: bool = false,
    left: bool = false,
    right: bool = false,

    /// Convert to u8 for serial shift register
    pub fn toU8(self: ButtonState) u8 {
        return @bitCast(self);
    }

    /// Create from u8
    pub fn fromU8(value: u8) ButtonState {
        return @bitCast(value);
    }
};

/// Controller input state (2 controllers)
pub const ControllerInput = struct {
    controller1: ButtonState = .{},
    controller2: ButtonState = .{},
};

/// Atomic controller input mailbox
pub const ControllerInputMailbox = struct {
    /// Current controller input state
    state: ControllerInput = .{},

    /// Mutex to protect state updates
    mutex: std.Thread.Mutex = .{},

    /// Initialize mailbox
    pub fn init(allocator: std.mem.Allocator) ControllerInputMailbox {
        _ = allocator;
        return .{};
    }

    /// Cleanup mailbox
    pub fn deinit(self: *ControllerInputMailbox) void {
        _ = self;
    }

    /// Update controller input state (called by input thread)
    pub fn postInput(self: *ControllerInputMailbox, input: ControllerInput) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.state = input;
    }

    /// Update single controller (convenience method)
    pub fn postController1(self: *ControllerInputMailbox, buttons: ButtonState) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.state.controller1 = buttons;
    }

    /// Update controller 2 (convenience method)
    pub fn postController2(self: *ControllerInputMailbox, buttons: ButtonState) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.state.controller2 = buttons;
    }

    /// Read current controller input state (called by emulation thread)
    /// Returns current button state (does not clear)
    pub fn getInput(self: *ControllerInputMailbox) ControllerInput {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.state;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ControllerInputMailbox: basic post and get" {
    const allocator = std.testing.allocator;

    var mailbox = ControllerInputMailbox.init(allocator);
    defer mailbox.deinit();

    // Post controller 1 input (A button pressed)
    mailbox.postController1(.{ .a = true });

    // Get should return the button state
    const input = mailbox.getInput();
    try std.testing.expect(input.controller1.a == true);
    try std.testing.expect(input.controller1.b == false);

    // State should persist on second read
    const input2 = mailbox.getInput();
    try std.testing.expect(input2.controller1.a == true);
}

test "ControllerInputMailbox: button state updates" {
    const allocator = std.testing.allocator;

    var mailbox = ControllerInputMailbox.init(allocator);
    defer mailbox.deinit();

    // Press A
    mailbox.postController1(.{ .a = true });
    var input = mailbox.getInput();
    try std.testing.expect(input.controller1.a == true);

    // Release A, press B
    mailbox.postController1(.{ .b = true });
    input = mailbox.getInput();
    try std.testing.expect(input.controller1.a == false);
    try std.testing.expect(input.controller1.b == true);
}

test "ControllerInputMailbox: multiple buttons" {
    const allocator = std.testing.allocator;

    var mailbox = ControllerInputMailbox.init(allocator);
    defer mailbox.deinit();

    // Press A + Start
    mailbox.postController1(.{ .a = true, .start = true });

    const input = mailbox.getInput();
    try std.testing.expect(input.controller1.a == true);
    try std.testing.expect(input.controller1.start == true);
    try std.testing.expect(input.controller1.b == false);
}

test "ControllerInputMailbox: both controllers" {
    const allocator = std.testing.allocator;

    var mailbox = ControllerInputMailbox.init(allocator);
    defer mailbox.deinit();

    // Press A on controller 1
    mailbox.postController1(.{ .a = true });

    // Press B on controller 2
    mailbox.postController2(.{ .b = true });

    const input = mailbox.getInput();
    try std.testing.expect(input.controller1.a == true);
    try std.testing.expect(input.controller1.b == false);
    try std.testing.expect(input.controller2.a == false);
    try std.testing.expect(input.controller2.b == true);
}

test "ButtonState: toU8 conversion" {
    // Button order: A, B, Select, Start, Up, Down, Left, Right
    const buttons = ButtonState{
        .a = true, // bit 0
        .start = true, // bit 3
    };

    const value = buttons.toU8();
    try std.testing.expectEqual(@as(u8, 0b00001001), value); // A (bit 0) + Start (bit 3)
}

test "ButtonState: fromU8 conversion" {
    const buttons = ButtonState.fromU8(0b10000001); // A + Right
    try std.testing.expect(buttons.a == true);
    try std.testing.expect(buttons.right == true);
    try std.testing.expect(buttons.b == false);
}
