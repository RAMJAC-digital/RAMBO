//! Wayland Event Mailbox
//!
//! Double-buffered mailbox for Wayland window events
//! Wayland thread posts events, main thread consumes them
//!
//! Based on zzt-backup's WaylandEventMailbox pattern

const std = @import("std");

/// Wayland window event types
pub const WaylandEvent = union(enum) {
    window_resize: struct {
        width: u32,
        height: u32,
    },
    window_close: void,
    window_focus_change: struct {
        focused: bool,
    },
    window_state_change: struct {
        fullscreen: bool,
        maximized: bool,
        activated: bool,
    },
    key_press: struct {
        keycode: u32,
        modifiers: u32,
    },
    key_release: struct {
        keycode: u32,
        modifiers: u32,
    },
    mouse_move: struct {
        x: f32,
        y: f32,
    },
    mouse_button: struct {
        button: u8,
        pressed: bool,
        x: f32,
        y: f32,
    },
};

/// Double-buffered event mailbox for lock-free communication
pub const WaylandEventMailbox = struct {
    /// Pending events buffer (Wayland thread writes here)
    pending: std.ArrayList(WaylandEvent),

    /// Processing events buffer (Main thread reads from here)
    processing: std.ArrayList(WaylandEvent),

    /// Mutex to protect buffer swap
    mutex: std.Thread.Mutex = .{},

    /// Allocator for ArrayList operations
    allocator: std.mem.Allocator,

    /// Initialize mailbox
    pub fn init(allocator: std.mem.Allocator) !WaylandEventMailbox {
        return .{
            .pending = .{},
            .processing = .{},
            .allocator = allocator,
        };
    }

    /// Cleanup mailbox
    pub fn deinit(self: *WaylandEventMailbox) void {
        self.processing.deinit(self.allocator);
        self.pending.deinit(self.allocator);
    }

    /// Post event to mailbox (called by Wayland thread)
    pub fn postEvent(self: *WaylandEventMailbox, event: WaylandEvent) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.pending.append(self.allocator, event);
    }

    /// Swap buffers and get events for processing (called by main thread)
    /// Returns slice valid until next call to swapAndGetPendingEvents()
    pub fn swapAndGetPendingEvents(self: *WaylandEventMailbox) []WaylandEvent {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Swap buffers
        const tmp = self.processing;
        self.processing = self.pending;
        self.pending = tmp;

        // Clear pending buffer for next batch
        self.pending.clearRetainingCapacity();

        return self.processing.items;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "WaylandEventMailbox: basic post and consume" {
    const allocator = std.testing.allocator;

    var mailbox = try WaylandEventMailbox.init(allocator);
    defer mailbox.deinit();

    // Post some events
    try mailbox.postEvent(.{ .window_resize = .{ .width = 800, .height = 600 } });
    try mailbox.postEvent(.window_close);

    // Consume events
    const events = mailbox.swapAndGetPendingEvents();
    try std.testing.expectEqual(@as(usize, 2), events.len);
    try std.testing.expectEqual(@as(u32, 800), events[0].window_resize.width);
    try std.testing.expectEqual(@as(u32, 600), events[0].window_resize.height);
}

test "WaylandEventMailbox: double buffering" {
    const allocator = std.testing.allocator;

    var mailbox = try WaylandEventMailbox.init(allocator);
    defer mailbox.deinit();

    // Batch 1
    try mailbox.postEvent(.{ .window_resize = .{ .width = 800, .height = 600 } });
    const events1 = mailbox.swapAndGetPendingEvents();
    try std.testing.expectEqual(@as(usize, 1), events1.len);

    // Batch 2 (should be empty from previous swap)
    try mailbox.postEvent(.window_close);
    const events2 = mailbox.swapAndGetPendingEvents();
    try std.testing.expectEqual(@as(usize, 1), events2.len);
}
