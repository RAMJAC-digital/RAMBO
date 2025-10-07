//! XDG Input Event Mailbox
//!
//! Lock-free SPSC mailbox for XDG input protocol events
//! Render thread (producer) posts events, main thread (consumer) polls
//!
//! Events: keyboard, mouse input from wl_seat protocol

const std = @import("std");
const SpscRingBuffer = @import("SpscRingBuffer.zig").SpscRingBuffer;

/// XDG input event types
pub const XdgInputEvent = union(enum) {
    key_press: struct {
        keycode: u32,
        modifiers: u32,
    },
    key_release: struct {
        keycode: u32,
        modifiers: u32,
    },
    mouse_move: struct {
        x: f64,
        y: f64,
    },
    mouse_button: struct {
        button: u32,
        pressed: bool,
    },
};

/// Lock-free SPSC input event mailbox
pub const XdgInputEventMailbox = struct {
    /// Lock-free ring buffer (256 events max)
    buffer: SpscRingBuffer(XdgInputEvent, 256),

    /// Initialize mailbox
    pub fn init(allocator: std.mem.Allocator) XdgInputEventMailbox {
        _ = allocator;
        return .{
            .buffer = SpscRingBuffer(XdgInputEvent, 256).init(),
        };
    }

    /// Cleanup mailbox
    pub fn deinit(self: *XdgInputEventMailbox) void {
        _ = self;
    }

    /// Post event to mailbox (called by render thread - producer)
    /// Returns error if buffer is full
    pub fn postEvent(self: *XdgInputEventMailbox, event: XdgInputEvent) !void {
        if (!self.buffer.push(event)) {
            return error.BufferFull;
        }
    }

    /// Poll next event (called by main thread - consumer)
    /// Returns null if no events available
    pub fn pollEvent(self: *XdgInputEventMailbox) ?XdgInputEvent {
        return self.buffer.pop();
    }

    /// Check if events are pending (lock-free)
    pub fn hasEvents(self: *const XdgInputEventMailbox) bool {
        return !self.buffer.isEmpty();
    }

    /// Drain all events into provided buffer (for batch processing)
    /// Returns number of events drained
    pub fn drainEvents(self: *XdgInputEventMailbox, out_buffer: []XdgInputEvent) usize {
        var count: usize = 0;
        while (count < out_buffer.len) {
            if (self.buffer.pop()) |event| {
                out_buffer[count] = event;
                count += 1;
            } else {
                break;
            }
        }
        return count;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "XdgInputEventMailbox: basic post and poll" {
    const allocator = std.testing.allocator;

    var mailbox = XdgInputEventMailbox.init(allocator);
    defer mailbox.deinit();

    // Post some events
    try mailbox.postEvent(.{ .key_press = .{ .keycode = 65, .modifiers = 0 } }); // 'A' key
    try mailbox.postEvent(.{ .mouse_move = .{ .x = 100.0, .y = 200.0 } });

    // Poll events
    const event1 = mailbox.pollEvent().?;
    try std.testing.expectEqual(@as(u32, 65), event1.key_press.keycode);

    const event2 = mailbox.pollEvent().?;
    try std.testing.expectEqual(@as(f64, 100.0), event2.mouse_move.x);

    // Should be empty
    try std.testing.expect(mailbox.pollEvent() == null);
}

test "XdgInputEventMailbox: drain events" {
    const allocator = std.testing.allocator;

    var mailbox = XdgInputEventMailbox.init(allocator);
    defer mailbox.deinit();

    // Post multiple events
    try mailbox.postEvent(.{ .key_press = .{ .keycode = 13, .modifiers = 0 } }); // Enter
    try mailbox.postEvent(.{ .key_release = .{ .keycode = 13, .modifiers = 0 } });
    try mailbox.postEvent(.{ .mouse_move = .{ .x = 50.0, .y = 75.0 } });

    // Drain all events
    var events: [10]XdgInputEvent = undefined;
    const count = mailbox.drainEvents(&events);

    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expectEqual(@as(u32, 13), events[0].key_press.keycode);
    try std.testing.expectEqual(@as(u32, 13), events[1].key_release.keycode);
}

test "XdgInputEventMailbox: hasEvents check" {
    const allocator = std.testing.allocator;

    var mailbox = XdgInputEventMailbox.init(allocator);
    defer mailbox.deinit();

    // Should start with no events
    try std.testing.expect(!mailbox.hasEvents());

    // Post event
    try mailbox.postEvent(.{ .key_press = .{ .keycode = 27, .modifiers = 0 } }); // Escape
    try std.testing.expect(mailbox.hasEvents());

    // Poll clears event
    _ = mailbox.pollEvent();
    try std.testing.expect(!mailbox.hasEvents());
}

test "XdgInputEventMailbox: all event types" {
    const allocator = std.testing.allocator;

    var mailbox = XdgInputEventMailbox.init(allocator);
    defer mailbox.deinit();

    // Post all event types
    try mailbox.postEvent(.{ .key_press = .{ .keycode = 65, .modifiers = 1 } });
    try mailbox.postEvent(.{ .key_release = .{ .keycode = 65, .modifiers = 1 } });
    try mailbox.postEvent(.{ .mouse_move = .{ .x = 150.5, .y = 250.75 } });
    try mailbox.postEvent(.{ .mouse_button = .{ .button = 1, .pressed = true } }); // Left click

    // Poll all events
    const e1 = mailbox.pollEvent().?;
    try std.testing.expectEqual(@as(u32, 65), e1.key_press.keycode);
    try std.testing.expectEqual(@as(u32, 1), e1.key_press.modifiers);

    const e2 = mailbox.pollEvent().?;
    try std.testing.expectEqual(@as(u32, 65), e2.key_release.keycode);

    const e3 = mailbox.pollEvent().?;
    try std.testing.expectEqual(@as(f64, 150.5), e3.mouse_move.x);
    try std.testing.expectEqual(@as(f64, 250.75), e3.mouse_move.y);

    const e4 = mailbox.pollEvent().?;
    try std.testing.expectEqual(@as(u32, 1), e4.mouse_button.button);
    try std.testing.expect(e4.mouse_button.pressed);
}

test "XdgInputEventMailbox: keyboard modifiers" {
    const allocator = std.testing.allocator;

    var mailbox = XdgInputEventMailbox.init(allocator);
    defer mailbox.deinit();

    // Shift key modifier (example)
    const SHIFT = 0x0001;
    const CTRL = 0x0004;

    try mailbox.postEvent(.{ .key_press = .{ .keycode = 65, .modifiers = SHIFT } }); // Shift+A
    try mailbox.postEvent(.{ .key_press = .{ .keycode = 67, .modifiers = CTRL } }); // Ctrl+C
    try mailbox.postEvent(.{ .key_press = .{ .keycode = 86, .modifiers = CTRL | SHIFT } }); // Ctrl+Shift+V

    try std.testing.expectEqual(@as(u32, SHIFT), mailbox.pollEvent().?.key_press.modifiers);
    try std.testing.expectEqual(@as(u32, CTRL), mailbox.pollEvent().?.key_press.modifiers);
    try std.testing.expectEqual(@as(u32, CTRL | SHIFT), mailbox.pollEvent().?.key_press.modifiers);
}

test "XdgInputEventMailbox: mouse button states" {
    const allocator = std.testing.allocator;

    var mailbox = XdgInputEventMailbox.init(allocator);
    defer mailbox.deinit();

    // Left button press and release
    try mailbox.postEvent(.{ .mouse_button = .{ .button = 1, .pressed = true } });
    try mailbox.postEvent(.{ .mouse_button = .{ .button = 1, .pressed = false } });

    // Right button
    try mailbox.postEvent(.{ .mouse_button = .{ .button = 2, .pressed = true } });

    // Middle button
    try mailbox.postEvent(.{ .mouse_button = .{ .button = 3, .pressed = true } });

    const e1 = mailbox.pollEvent().?;
    try std.testing.expectEqual(@as(u32, 1), e1.mouse_button.button);
    try std.testing.expect(e1.mouse_button.pressed);

    const e2 = mailbox.pollEvent().?;
    try std.testing.expectEqual(@as(u32, 1), e2.mouse_button.button);
    try std.testing.expect(!e2.mouse_button.pressed);

    try std.testing.expectEqual(@as(u32, 2), mailbox.pollEvent().?.mouse_button.button);
    try std.testing.expectEqual(@as(u32, 3), mailbox.pollEvent().?.mouse_button.button);
}

test "XdgInputEventMailbox: empty poll" {
    const allocator = std.testing.allocator;

    var mailbox = XdgInputEventMailbox.init(allocator);
    defer mailbox.deinit();

    // Poll with no events
    try std.testing.expect(mailbox.pollEvent() == null);
}
