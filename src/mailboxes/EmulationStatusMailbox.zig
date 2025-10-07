//! Emulation Status Mailbox
//!
//! Atomic mailbox for emulation thread status updates
//! Emulation thread posts status, main thread reads for UI/logging
//!
//! Status data: FPS, frame count, running state, errors

const std = @import("std");
const SpeedControlMailbox = @import("SpeedControlMailbox.zig");

/// Emulation status information
pub const EmulationStatus = struct {
    fps: f64 = 0.0,                // Current FPS
    frame_count: u64 = 0,          // Total frames emulated
    is_running: bool = false,      // Emulation running
    is_paused: bool = false,       // Emulation paused
    current_mode: SpeedControlMailbox.SpeedMode = .realtime,
    error_message: ?[]const u8 = null, // Last error (null = no error)
};

/// Atomic status mailbox
pub const EmulationStatusMailbox = struct {
    /// Current status
    status: EmulationStatus,

    /// Mutex to protect status updates
    mutex: std.Thread.Mutex = .{},

    /// Initialize mailbox
    pub fn init(allocator: std.mem.Allocator) EmulationStatusMailbox {
        _ = allocator;
        return .{
            .status = .{},
        };
    }

    /// Cleanup mailbox
    pub fn deinit(self: *EmulationStatusMailbox) void {
        _ = self;
    }

    /// Update status (called by emulation thread)
    pub fn updateStatus(self: *EmulationStatusMailbox, new_status: EmulationStatus) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.status = new_status;
    }

    /// Get current status (called by main thread)
    pub fn getStatus(self: *EmulationStatusMailbox) EmulationStatus {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.status;
    }

    /// Update FPS only (convenience method)
    pub fn updateFPS(self: *EmulationStatusMailbox, fps: f64) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.status.fps = fps;
    }

    /// Increment frame count (convenience method)
    pub fn incrementFrameCount(self: *EmulationStatusMailbox) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.status.frame_count += 1;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "EmulationStatusMailbox: basic update and get" {
    const allocator = std.testing.allocator;

    var mailbox = EmulationStatusMailbox.init(allocator);
    defer mailbox.deinit();

    // Default status
    var status = mailbox.getStatus();
    try std.testing.expectEqual(@as(f64, 0.0), status.fps);
    try std.testing.expect(!status.is_running);

    // Update status
    mailbox.updateStatus(.{
        .fps = 60.0,
        .frame_count = 100,
        .is_running = true,
        .is_paused = false,
        .current_mode = .realtime,
        .error_message = null,
    });

    status = mailbox.getStatus();
    try std.testing.expectEqual(@as(f64, 60.0), status.fps);
    try std.testing.expectEqual(@as(u64, 100), status.frame_count);
    try std.testing.expect(status.is_running);
    try std.testing.expect(!status.is_paused);
}

test "EmulationStatusMailbox: updateFPS convenience method" {
    const allocator = std.testing.allocator;

    var mailbox = EmulationStatusMailbox.init(allocator);
    defer mailbox.deinit();

    // Update FPS
    mailbox.updateFPS(59.94);

    const status = mailbox.getStatus();
    try std.testing.expectEqual(@as(f64, 59.94), status.fps);
}

test "EmulationStatusMailbox: incrementFrameCount" {
    const allocator = std.testing.allocator;

    var mailbox = EmulationStatusMailbox.init(allocator);
    defer mailbox.deinit();

    // Increment 10 times
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        mailbox.incrementFrameCount();
    }

    const status = mailbox.getStatus();
    try std.testing.expectEqual(@as(u64, 10), status.frame_count);
}

test "EmulationStatusMailbox: all speed modes" {
    const allocator = std.testing.allocator;

    var mailbox = EmulationStatusMailbox.init(allocator);
    defer mailbox.deinit();

    const modes = [_]SpeedControlMailbox.SpeedMode{
        .realtime,
        .fast_forward,
        .slow_motion,
        .paused,
        .stepping,
    };

    for (modes) |mode| {
        mailbox.updateStatus(.{
            .fps = 60.0,
            .frame_count = 0,
            .is_running = true,
            .is_paused = false,
            .current_mode = mode,
            .error_message = null,
        });

        const status = mailbox.getStatus();
        try std.testing.expectEqual(mode, status.current_mode);
    }
}

test "EmulationStatusMailbox: error message" {
    const allocator = std.testing.allocator;

    var mailbox = EmulationStatusMailbox.init(allocator);
    defer mailbox.deinit();

    const error_msg = "Test error message";

    // Update with error
    mailbox.updateStatus(.{
        .fps = 0.0,
        .frame_count = 0,
        .is_running = false,
        .is_paused = false,
        .current_mode = .realtime,
        .error_message = error_msg,
    });

    const status = mailbox.getStatus();
    try std.testing.expect(status.error_message != null);
    try std.testing.expectEqualStrings(error_msg, status.error_message.?);

    // Clear error
    mailbox.updateStatus(.{
        .fps = 60.0,
        .frame_count = 0,
        .is_running = true,
        .is_paused = false,
        .current_mode = .realtime,
        .error_message = null,
    });

    const status2 = mailbox.getStatus();
    try std.testing.expect(status2.error_message == null);
}

test "EmulationStatusMailbox: running and paused states" {
    const allocator = std.testing.allocator;

    var mailbox = EmulationStatusMailbox.init(allocator);
    defer mailbox.deinit();

    // Running
    mailbox.updateStatus(.{
        .fps = 60.0,
        .frame_count = 0,
        .is_running = true,
        .is_paused = false,
        .current_mode = .realtime,
        .error_message = null,
    });
    var status = mailbox.getStatus();
    try std.testing.expect(status.is_running);
    try std.testing.expect(!status.is_paused);

    // Paused
    mailbox.updateStatus(.{
        .fps = 0.0,
        .frame_count = 0,
        .is_running = true,
        .is_paused = true,
        .current_mode = .paused,
        .error_message = null,
    });
    status = mailbox.getStatus();
    try std.testing.expect(status.is_running);
    try std.testing.expect(status.is_paused);

    // Stopped
    mailbox.updateStatus(.{
        .fps = 0.0,
        .frame_count = 0,
        .is_running = false,
        .is_paused = false,
        .current_mode = .realtime,
        .error_message = null,
    });
    status = mailbox.getStatus();
    try std.testing.expect(!status.is_running);
    try std.testing.expect(!status.is_paused);
}
