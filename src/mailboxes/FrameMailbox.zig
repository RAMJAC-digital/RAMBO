//! Frame Buffer Mailbox
//!
//! Double-buffered mailbox for PPU frame buffers
//! Emulation thread writes completed frames, render thread reads them
//!
//! NES Resolution: 256x240 pixels
//! Format: RGB888 (u32 per pixel, 0x00RRGGBB)

const std = @import("std");

/// NES PPU frame dimensions
pub const FRAME_WIDTH = 256;
pub const FRAME_HEIGHT = 240;
pub const FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT;

/// Frame buffer (256×240 RGB888 pixels)
pub const FrameBuffer = [FRAME_PIXELS]u32;

/// Double-buffered frame mailbox for lock-free communication
pub const FrameMailbox = struct {
    /// Write buffer (Emulation thread writes here)
    write_buffer: *FrameBuffer,

    /// Read buffer (Render thread reads from here)
    read_buffer: *FrameBuffer,

    /// Mutex to protect buffer swap
    mutex: std.Thread.Mutex = .{},

    /// Allocator for buffers
    allocator: std.mem.Allocator,

    /// Frame counter
    frame_count: u64 = 0,

    /// Initialize mailbox with two framebuffers
    pub fn init(allocator: std.mem.Allocator) !FrameMailbox {
        const write_buffer = try allocator.create(FrameBuffer);
        errdefer allocator.destroy(write_buffer);

        const read_buffer = try allocator.create(FrameBuffer);
        errdefer allocator.destroy(read_buffer);

        // Clear buffers to black
        @memset(write_buffer, 0x00000000);
        @memset(read_buffer, 0x00000000);

        return .{
            .write_buffer = write_buffer,
            .read_buffer = read_buffer,
            .allocator = allocator,
        };
    }

    /// Cleanup mailbox
    pub fn deinit(self: *FrameMailbox) void {
        self.allocator.destroy(self.read_buffer);
        self.allocator.destroy(self.write_buffer);
    }

    /// Get write buffer for emulation thread
    /// Emulation thread calls this at frame start
    pub fn getWriteBuffer(self: *FrameMailbox) []u32 {
        return self.write_buffer;
    }

    /// Swap buffers after frame complete (called by emulation thread)
    pub fn swapBuffers(self: *FrameMailbox) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Swap buffers
        const tmp = self.write_buffer;
        self.write_buffer = self.read_buffer;
        self.read_buffer = tmp;

        self.frame_count += 1;
    }

    /// Get read buffer for render thread
    /// Render thread calls this to get latest complete frame
    pub fn getReadBuffer(self: *FrameMailbox) []const u32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.read_buffer;
    }

    /// Get frame count
    pub fn getFrameCount(self: *const FrameMailbox) u64 {
        return self.frame_count;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "FrameMailbox: buffer swap" {
    const allocator = std.testing.allocator;

    var mailbox = try FrameMailbox.init(allocator);
    defer mailbox.deinit();

    // Write to buffer
    const write_buf = mailbox.getWriteBuffer();
    write_buf[0] = 0x00FF0000; // Red pixel

    // Swap buffers
    mailbox.swapBuffers();

    // Read buffer should now have the red pixel
    const read_buf = mailbox.getReadBuffer();
    try std.testing.expectEqual(@as(u32, 0x00FF0000), read_buf[0]);

    // Frame count should increment
    try std.testing.expectEqual(@as(u64, 1), mailbox.getFrameCount());
}

test "FrameMailbox: initialization clears buffers" {
    const allocator = std.testing.allocator;

    var mailbox = try FrameMailbox.init(allocator);
    defer mailbox.deinit();

    // Buffers should start black
    const write_buf = mailbox.getWriteBuffer();
    try std.testing.expectEqual(@as(u32, 0x00000000), write_buf[0]);
    try std.testing.expectEqual(@as(u32, 0x00000000), write_buf[FRAME_PIXELS - 1]);
}
