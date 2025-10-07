//! Render Status Mailbox
//!
//! Atomic mailbox for render thread status updates
//! Render thread posts status, main thread reads for logging/debugging
//!
//! Status data: Display FPS, Vulkan errors, window size

const std = @import("std");

/// Window size information
pub const WindowSize = struct {
    width: u32 = 0,
    height: u32 = 0,
};

/// Render status information
pub const RenderStatus = struct {
    display_fps: f64 = 0.0,              // Actual display refresh rate
    frames_rendered: u64 = 0,            // Total frames displayed
    is_running: bool = false,            // Render thread active
    vulkan_error: ?[]const u8 = null,    // Last Vulkan error (null = no error)
    window_size: WindowSize = .{},       // Current window dimensions
};

/// Atomic render status mailbox
pub const RenderStatusMailbox = struct {
    /// Current status
    status: RenderStatus,

    /// Mutex to protect status updates
    mutex: std.Thread.Mutex = .{},

    /// Initialize mailbox
    pub fn init(allocator: std.mem.Allocator) RenderStatusMailbox {
        _ = allocator;
        return .{
            .status = .{},
        };
    }

    /// Cleanup mailbox
    pub fn deinit(self: *RenderStatusMailbox) void {
        _ = self;
    }

    /// Update status (called by render thread)
    pub fn updateStatus(self: *RenderStatusMailbox, new_status: RenderStatus) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.status = new_status;
    }

    /// Get current status (called by main thread)
    pub fn getStatus(self: *RenderStatusMailbox) RenderStatus {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.status;
    }

    /// Update display FPS only (convenience method)
    pub fn updateDisplayFPS(self: *RenderStatusMailbox, fps: f64) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.status.display_fps = fps;
    }

    /// Increment frames rendered (convenience method)
    pub fn incrementFramesRendered(self: *RenderStatusMailbox) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.status.frames_rendered += 1;
    }

    /// Update window size (convenience method)
    pub fn updateWindowSize(self: *RenderStatusMailbox, width: u32, height: u32) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.status.window_size = .{ .width = width, .height = height };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "RenderStatusMailbox: basic update and get" {
    const allocator = std.testing.allocator;

    var mailbox = RenderStatusMailbox.init(allocator);
    defer mailbox.deinit();

    // Default status
    var status = mailbox.getStatus();
    try std.testing.expectEqual(@as(f64, 0.0), status.display_fps);
    try std.testing.expect(!status.is_running);

    // Update status
    mailbox.updateStatus(.{
        .display_fps = 60.0,
        .frames_rendered = 120,
        .is_running = true,
        .vulkan_error = null,
        .window_size = .{ .width = 800, .height = 600 },
    });

    status = mailbox.getStatus();
    try std.testing.expectEqual(@as(f64, 60.0), status.display_fps);
    try std.testing.expectEqual(@as(u64, 120), status.frames_rendered);
    try std.testing.expect(status.is_running);
    try std.testing.expectEqual(@as(u32, 800), status.window_size.width);
    try std.testing.expectEqual(@as(u32, 600), status.window_size.height);
}

test "RenderStatusMailbox: updateDisplayFPS convenience method" {
    const allocator = std.testing.allocator;

    var mailbox = RenderStatusMailbox.init(allocator);
    defer mailbox.deinit();

    // Update display FPS
    mailbox.updateDisplayFPS(144.0);

    const status = mailbox.getStatus();
    try std.testing.expectEqual(@as(f64, 144.0), status.display_fps);
}

test "RenderStatusMailbox: incrementFramesRendered" {
    const allocator = std.testing.allocator;

    var mailbox = RenderStatusMailbox.init(allocator);
    defer mailbox.deinit();

    // Increment 5 times
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        mailbox.incrementFramesRendered();
    }

    const status = mailbox.getStatus();
    try std.testing.expectEqual(@as(u64, 5), status.frames_rendered);
}

test "RenderStatusMailbox: updateWindowSize" {
    const allocator = std.testing.allocator;

    var mailbox = RenderStatusMailbox.init(allocator);
    defer mailbox.deinit();

    // Update window size
    mailbox.updateWindowSize(1920, 1080);

    const status = mailbox.getStatus();
    try std.testing.expectEqual(@as(u32, 1920), status.window_size.width);
    try std.testing.expectEqual(@as(u32, 1080), status.window_size.height);
}

test "RenderStatusMailbox: vulkan error handling" {
    const allocator = std.testing.allocator;

    var mailbox = RenderStatusMailbox.init(allocator);
    defer mailbox.deinit();

    const error_msg = "VK_ERROR_OUT_OF_DEVICE_MEMORY";

    // Set error
    mailbox.updateStatus(.{
        .display_fps = 0.0,
        .frames_rendered = 0,
        .is_running = false,
        .vulkan_error = error_msg,
        .window_size = .{},
    });

    var status = mailbox.getStatus();
    try std.testing.expect(status.vulkan_error != null);
    try std.testing.expectEqualStrings(error_msg, status.vulkan_error.?);

    // Clear error
    mailbox.updateStatus(.{
        .display_fps = 60.0,
        .frames_rendered = 0,
        .is_running = true,
        .vulkan_error = null,
        .window_size = .{},
    });

    status = mailbox.getStatus();
    try std.testing.expect(status.vulkan_error == null);
}

test "RenderStatusMailbox: running state transitions" {
    const allocator = std.testing.allocator;

    var mailbox = RenderStatusMailbox.init(allocator);
    defer mailbox.deinit();

    // Start running
    mailbox.updateStatus(.{
        .display_fps = 60.0,
        .frames_rendered = 0,
        .is_running = true,
        .vulkan_error = null,
        .window_size = .{ .width = 800, .height = 600 },
    });
    var status = mailbox.getStatus();
    try std.testing.expect(status.is_running);

    // Stop
    mailbox.updateStatus(.{
        .display_fps = 0.0,
        .frames_rendered = 100,
        .is_running = false,
        .vulkan_error = null,
        .window_size = .{ .width = 800, .height = 600 },
    });
    status = mailbox.getStatus();
    try std.testing.expect(!status.is_running);
}

test "RenderStatusMailbox: multiple window size updates" {
    const allocator = std.testing.allocator;

    var mailbox = RenderStatusMailbox.init(allocator);
    defer mailbox.deinit();

    const sizes = [_]WindowSize{
        .{ .width = 640, .height = 480 },
        .{ .width = 800, .height = 600 },
        .{ .width = 1024, .height = 768 },
        .{ .width = 1920, .height = 1080 },
    };

    for (sizes) |size| {
        mailbox.updateWindowSize(size.width, size.height);
        const status = mailbox.getStatus();
        try std.testing.expectEqual(size.width, status.window_size.width);
        try std.testing.expectEqual(size.height, status.window_size.height);
    }
}
