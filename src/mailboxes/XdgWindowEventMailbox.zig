//! XDG Window Event Mailbox
//!
//! Lock-free SPSC mailbox for XDG window protocol events
//! Render thread (producer) posts events, main thread (consumer) polls
//!
//! Window events ONLY (no input - see XdgInputEventMailbox for keyboard/mouse)

const std = @import("std");
const SpscRingBuffer = @import("SpscRingBuffer.zig").SpscRingBuffer;

/// XDG window event types
pub const XdgWindowEvent = union(enum) {
    window_resize: struct {
        width: u32,
        height: u32,
    },
    window_close: void,
    window_focus: struct {
        focused: bool,
    },
    window_focus_change: struct {
        focused: bool,
    },
    window_state: struct {
        fullscreen: bool,
        maximized: bool,
    },
};

/// Lock-free SPSC window event mailbox
pub const XdgWindowEventMailbox = struct {
    /// Lock-free ring buffer (64 events max)
    buffer: SpscRingBuffer(XdgWindowEvent, 64),

    /// Initialize mailbox
    pub fn init(allocator: std.mem.Allocator) XdgWindowEventMailbox {
        _ = allocator;
        return .{
            .buffer = SpscRingBuffer(XdgWindowEvent, 64).init(),
        };
    }

    /// Cleanup mailbox
    pub fn deinit(self: *XdgWindowEventMailbox) void {
        _ = self;
    }

    /// Post event to mailbox (called by render thread - producer)
    /// Returns error if buffer is full
    pub fn postEvent(self: *XdgWindowEventMailbox, event: XdgWindowEvent) !void {
        if (!self.buffer.push(event)) {
            return error.BufferFull;
        }
    }

    /// Poll next event (called by main thread - consumer)
    /// Returns null if no events available
    pub fn pollEvent(self: *XdgWindowEventMailbox) ?XdgWindowEvent {
        return self.buffer.pop();
    }

    /// Check if events are pending (lock-free)
    pub fn hasEvents(self: *const XdgWindowEventMailbox) bool {
        return !self.buffer.isEmpty();
    }

    /// Drain all events into provided buffer (for batch processing)
    /// Returns number of events drained
    pub fn drainEvents(self: *XdgWindowEventMailbox, out_buffer: []XdgWindowEvent) usize {
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

test "XdgWindowEventMailbox: basic post and poll" {
    const allocator = std.testing.allocator;

    var mailbox = XdgWindowEventMailbox.init(allocator);
    defer mailbox.deinit();

    // Post window events
    try mailbox.postEvent(.{ .window_resize = .{ .width = 800, .height = 600 } });
    try mailbox.postEvent(.window_close);

    // Poll events
    const e1 = mailbox.pollEvent().?;
    try std.testing.expectEqual(@as(u32, 800), e1.window_resize.width);
    try std.testing.expectEqual(@as(u32, 600), e1.window_resize.height);

    const e2 = mailbox.pollEvent().?;
    _ = e2.window_close;

    // Should be empty
    try std.testing.expect(mailbox.pollEvent() == null);
}

test "XdgWindowEventMailbox: drain events" {
    const allocator = std.testing.allocator;

    var mailbox = XdgWindowEventMailbox.init(allocator);
    defer mailbox.deinit();

    // Post multiple events
    try mailbox.postEvent(.{ .window_resize = .{ .width = 800, .height = 600 } });
    try mailbox.postEvent(.window_close);
    try mailbox.postEvent(.{ .window_focus = .{ .focused = true } });

    // Drain all events
    var events: [10]XdgWindowEvent = undefined;
    const count = mailbox.drainEvents(&events);

    try std.testing.expectEqual(@as(usize, 3), count);
}

test "XdgWindowEventMailbox: window focus" {
    const allocator = std.testing.allocator;

    var mailbox = XdgWindowEventMailbox.init(allocator);
    defer mailbox.deinit();

    // Focus gained
    try mailbox.postEvent(.{ .window_focus = .{ .focused = true } });
    const e1 = mailbox.pollEvent().?;
    try std.testing.expect(e1.window_focus.focused);

    // Focus lost
    try mailbox.postEvent(.{ .window_focus = .{ .focused = false } });
    const e2 = mailbox.pollEvent().?;
    try std.testing.expect(!e2.window_focus.focused);
}

test "XdgWindowEventMailbox: window state" {
    const allocator = std.testing.allocator;

    var mailbox = XdgWindowEventMailbox.init(allocator);
    defer mailbox.deinit();

    // Fullscreen + maximized
    try mailbox.postEvent(.{ .window_state = .{ .fullscreen = true, .maximized = true } });
    const event = mailbox.pollEvent().?;
    try std.testing.expect(event.window_state.fullscreen);
    try std.testing.expect(event.window_state.maximized);
}

test "XdgWindowEventMailbox: hasEvents check" {
    const allocator = std.testing.allocator;

    var mailbox = XdgWindowEventMailbox.init(allocator);
    defer mailbox.deinit();

    // Should start with no events
    try std.testing.expect(!mailbox.hasEvents());

    // Post event
    try mailbox.postEvent(.window_close);
    try std.testing.expect(mailbox.hasEvents());

    // Poll clears event
    _ = mailbox.pollEvent();
    try std.testing.expect(!mailbox.hasEvents());
}

test "XdgWindowEventMailbox: all event types" {
    const allocator = std.testing.allocator;

    var mailbox = XdgWindowEventMailbox.init(allocator);
    defer mailbox.deinit();

    // Post all event types
    try mailbox.postEvent(.{ .window_resize = .{ .width = 1920, .height = 1080 } });
    try mailbox.postEvent(.window_close);
    try mailbox.postEvent(.{ .window_focus = .{ .focused = true } });
    try mailbox.postEvent(.{ .window_state = .{ .fullscreen = false, .maximized = true } });

    // Poll all events
    _ = mailbox.pollEvent().?;
    _ = mailbox.pollEvent().?;
    _ = mailbox.pollEvent().?;
    _ = mailbox.pollEvent().?;

    // Should be empty
    try std.testing.expect(mailbox.pollEvent() == null);
}
