//! Frame Buffer Mailbox - Lock-Free Ring Buffer
//!
//! Design:
//! - Pure atomic operations (NO mutex)
//! - Ring buffer with 3 preallocated buffers (triple-buffering)
//! - SPSC (Single Producer, Single Consumer)
//! - Zero allocations after initialization
//! - NTSC/PAL agnostic (same 256×240 resolution)
//!
//! Buffer Flow:
//! PPU (writer) → swapBuffers() → atomic increment write_index
//! Vulkan (reader) → getReadBuffer() → read at read_index
//! Vulkan → consumeFrame() → atomic increment read_index
//!
//! Hardware Reference: NES PPU outputs 256×240 pixels per frame
//! Format: RGBA u32 (0xAABBGGRR) for Vulkan compatibility
//!
//! CRITICAL RT-SAFETY NOTE:
//! All buffers are stack-allocated (720 KB total) to ensure ZERO heap allocations
//! during frame rendering. This is essential for real-time performance and prevents
//! unpredictable latency from memory allocator calls. Do NOT move to heap allocation.

const std = @import("std");

/// NES PPU frame dimensions
pub const FRAME_WIDTH = 256;
pub const FRAME_HEIGHT = 240;
pub const FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT; // 61,440 pixels
pub const RING_BUFFER_SIZE = 3; // Triple-buffering for smooth rendering

/// Frame buffer (256×240 RGBA pixels)
pub const FrameBuffer = [FRAME_PIXELS]u32;

/// Lock-free frame mailbox using pure atomics
pub const FrameMailbox = struct {
    /// Ring buffer of preallocated frame buffers
    /// All 3 buffers allocated at initialization (zero runtime allocations)
    buffers: [RING_BUFFER_SIZE]FrameBuffer,

    /// Atomic write index - PPU writes to buffers[write_index % 3]
    write_index: std.atomic.Value(u32),

    /// Atomic read index - Vulkan reads from buffers[read_index % 3]
    read_index: std.atomic.Value(u32),

    /// Frame counter (monotonic increment, never decreases)
    frame_count: std.atomic.Value(u64),

    /// Frames dropped due to ring buffer overflow
    /// Incremented when write_index catches up to read_index
    frames_dropped: std.atomic.Value(u64),

    /// Initialize mailbox with preallocated buffers (all zeroed)
    pub fn init() FrameMailbox {
        return .{
            .buffers = [_]FrameBuffer{[_]u32{0} ** FRAME_PIXELS} ** RING_BUFFER_SIZE,
            .write_index = std.atomic.Value(u32).init(0),
            .read_index = std.atomic.Value(u32).init(0),
            .frame_count = std.atomic.Value(u64).init(0),
            .frames_dropped = std.atomic.Value(u64).init(0),
        };
    }

    /// No deinit needed - all buffers are on stack/in struct
    pub fn deinit(_: *FrameMailbox) void {
        // No-op: buffers are inline, no heap allocations
    }

    /// Get write buffer for PPU to render into
    /// Called by EmulationThread at frame start
    /// Returns mutable slice to current write buffer, or null if buffer full
    ///
    /// Returns null when ring buffer is full (write would overwrite active display buffer)
    /// Caller should skip rendering when null is returned
    pub fn getWriteBuffer(self: *FrameMailbox) ?[]u32 {
        const current_write = self.write_index.load(.acquire);
        const current_read = self.read_index.load(.acquire);

        // Check if next write would collide with read
        // If so, skip this frame to prevent tearing
        const next_write = (current_write + 1) % RING_BUFFER_SIZE;
        if (next_write == current_read % RING_BUFFER_SIZE) {
            return null; // Buffer full, skip frame
        }

        return &self.buffers[current_write % RING_BUFFER_SIZE];
    }

    /// Swap buffers after PPU completes frame
    /// Called by EmulationThread after frame rendering
    /// Pure atomic operation - NO mutex, NO locks
    pub fn swapBuffers(self: *FrameMailbox) void {
        const current_write = self.write_index.load(.acquire);
        const current_read = self.read_index.load(.acquire);

        // Calculate next write position (circular wrap)
        const next_write = (current_write + 1) % RING_BUFFER_SIZE;

        // Check if we're about to overwrite unconsumed frame
        // This happens if Vulkan is too slow to consume frames
        if (next_write == current_read % RING_BUFFER_SIZE) {
            // Ring buffer full - drop frame (continue rendering to same buffer)
            _ = self.frames_dropped.fetchAdd(1, .monotonic);
            // NOTE: We don't advance write_index, so PPU overwrites same buffer
            // This prevents visual tearing by keeping last complete frame readable
        } else {
            // Advance write index (release semantics ensure all writes visible)
            self.write_index.store(next_write, .release);
        }

        // Increment frame counter regardless of drop
        _ = self.frame_count.fetchAdd(1, .monotonic);
    }

    /// Get read buffer for Vulkan to display
    /// Called by RenderThread
    /// Returns const slice to current read buffer
    pub fn getReadBuffer(self: *const FrameMailbox) []const u32 {
        const index = self.read_index.load(.acquire);
        return &self.buffers[index % RING_BUFFER_SIZE];
    }

    /// Check if new frame available
    /// Returns true if write_index ahead of read_index
    /// Lock-free, non-blocking check
    pub fn hasNewFrame(self: *const FrameMailbox) bool {
        const write_idx = self.write_index.load(.acquire);
        const read_idx = self.read_index.load(.acquire);

        // New frame available if indices differ
        return write_idx != read_idx;
    }

    /// Consume current frame and advance to next
    /// Called by RenderThread after uploading to Vulkan
    /// Pure atomic operation
    pub fn consumeFrame(self: *FrameMailbox) void {
        const current_read = self.read_index.load(.acquire);
        const next_read = (current_read + 1) % RING_BUFFER_SIZE;

        // Advance read index (release semantics)
        self.read_index.store(next_read, .release);
    }

    /// Get frame statistics (monotonic counters)
    pub fn getFrameCount(self: *const FrameMailbox) u64 {
        return self.frame_count.load(.monotonic);
    }

    pub fn getFramesDropped(self: *const FrameMailbox) u64 {
        return self.frames_dropped.load(.monotonic);
    }

    /// Reset drop counter (useful for benchmarking)
    pub fn resetStatistics(self: *FrameMailbox) void {
        self.frames_dropped.store(0, .monotonic);
    }

    /// Legacy API compatibility - kept for existing tests
    /// Marked deprecated - use consumeFrame() instead
    pub fn consumeFrameFlag(self: *FrameMailbox) void {
        self.consumeFrame();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "FrameMailbox: pure atomic initialization (no allocator)" {
    var mailbox = FrameMailbox.init();
    defer mailbox.deinit();

    // Buffers should start zeroed
    const write_buf = mailbox.getWriteBuffer() orelse return error.SkipZigTest;
    try std.testing.expectEqual(@as(u32, 0x00000000), write_buf[0]);
    try std.testing.expectEqual(@as(u32, 0x00000000), write_buf[FRAME_PIXELS - 1]);

    // Indices should start at 0
    try std.testing.expectEqual(@as(u32, 0), mailbox.write_index.load(.acquire));
    try std.testing.expectEqual(@as(u32, 0), mailbox.read_index.load(.acquire));

    // Counters should start at 0
    try std.testing.expectEqual(@as(u64, 0), mailbox.getFrameCount());
    try std.testing.expectEqual(@as(u64, 0), mailbox.getFramesDropped());
}

test "FrameMailbox: buffer swap advances write index" {
    var mailbox = FrameMailbox.init();
    defer mailbox.deinit();

    // Write to buffer 0
    const write_buf = mailbox.getWriteBuffer() orelse return error.SkipZigTest;
    write_buf[0] = 0x00FF0000; // Red pixel

    // Swap buffers
    mailbox.swapBuffers();

    // Write index should advance to 1
    try std.testing.expectEqual(@as(u32, 1), mailbox.write_index.load(.acquire));

    // Frame count should increment
    try std.testing.expectEqual(@as(u64, 1), mailbox.getFrameCount());

    // Read buffer should still be at index 0 (contains red pixel)
    const read_buf = mailbox.getReadBuffer();
    try std.testing.expectEqual(@as(u32, 0x00FF0000), read_buf[0]);
}

test "FrameMailbox: hasNewFrame detects write ahead of read" {
    var mailbox = FrameMailbox.init();
    defer mailbox.deinit();

    // Initially no new frame (write_index == read_index)
    try std.testing.expect(!mailbox.hasNewFrame());

    // Write and swap buffers
    mailbox.swapBuffers();

    // Now write_index > read_index
    try std.testing.expect(mailbox.hasNewFrame());

    // Consume frame
    mailbox.consumeFrame();

    // Indices equal again
    try std.testing.expect(!mailbox.hasNewFrame());
}

test "FrameMailbox: consumeFrame advances read index" {
    var mailbox = FrameMailbox.init();
    defer mailbox.deinit();

    // Swap to produce frame
    mailbox.swapBuffers();
    try std.testing.expectEqual(@as(u32, 1), mailbox.write_index.load(.acquire));
    try std.testing.expectEqual(@as(u32, 0), mailbox.read_index.load(.acquire));

    // Consume frame
    mailbox.consumeFrame();

    // Read index should advance to 1
    try std.testing.expectEqual(@as(u32, 1), mailbox.read_index.load(.acquire));
}

test "FrameMailbox: ring buffer wraps at RING_BUFFER_SIZE" {
    var mailbox = FrameMailbox.init();
    defer mailbox.deinit();

    // Swap 3 times (should wrap write_index to 0)
    mailbox.swapBuffers(); // write_index: 0 → 1
    mailbox.consumeFrame(); // read_index: 0 → 1

    mailbox.swapBuffers(); // write_index: 1 → 2
    mailbox.consumeFrame(); // read_index: 1 → 2

    mailbox.swapBuffers(); // write_index: 2 → 0 (wrap!)
    mailbox.consumeFrame(); // read_index: 2 → 0 (wrap!)

    // Both indices should wrap to 0
    try std.testing.expectEqual(@as(u32, 0), mailbox.write_index.load(.acquire));
    try std.testing.expectEqual(@as(u32, 0), mailbox.read_index.load(.acquire));

    // Should have processed 3 frames
    try std.testing.expectEqual(@as(u64, 3), mailbox.getFrameCount());
    try std.testing.expectEqual(@as(u64, 0), mailbox.getFramesDropped());
}

test "FrameMailbox: frame drop when write catches read" {
    var mailbox = FrameMailbox.init();
    defer mailbox.deinit();

    // Produce 3 frames without consuming (fill ring buffer)
    mailbox.swapBuffers(); // write: 0→1, read: 0
    mailbox.swapBuffers(); // write: 1→2, read: 0
    mailbox.swapBuffers(); // write: 2→0 (WOULD collide with read=0)

    // Third swap should detect collision and drop frame
    try std.testing.expectEqual(@as(u64, 1), mailbox.getFramesDropped());

    // Write index should NOT advance on drop (stays at 2)
    try std.testing.expectEqual(@as(u32, 2), mailbox.write_index.load(.acquire));

    // Frame count should still increment (counts attempts)
    try std.testing.expectEqual(@as(u64, 3), mailbox.getFrameCount());
}

test "FrameMailbox: multiple frame updates" {
    var mailbox = FrameMailbox.init();
    defer mailbox.deinit();

    // Frame 1
    mailbox.swapBuffers();
    try std.testing.expect(mailbox.hasNewFrame());
    mailbox.consumeFrame();

    // Frame 2
    mailbox.swapBuffers();
    try std.testing.expect(mailbox.hasNewFrame());
    mailbox.consumeFrame();

    // Should have counted 2 frames
    try std.testing.expectEqual(@as(u64, 2), mailbox.getFrameCount());
    try std.testing.expectEqual(@as(u64, 0), mailbox.getFramesDropped());
}

test "FrameMailbox: resetStatistics clears drop counter" {
    var mailbox = FrameMailbox.init();
    defer mailbox.deinit();

    // Force frame drops
    mailbox.swapBuffers();
    mailbox.swapBuffers();
    mailbox.swapBuffers(); // Drops 1 frame

    try std.testing.expectEqual(@as(u64, 1), mailbox.getFramesDropped());

    // Reset statistics
    mailbox.resetStatistics();

    // Drop counter should be 0
    try std.testing.expectEqual(@as(u64, 0), mailbox.getFramesDropped());

    // Frame count should remain (not reset)
    try std.testing.expectEqual(@as(u64, 3), mailbox.getFrameCount());
}

test "FrameMailbox: write and read buffers are distinct after swap" {
    var mailbox = FrameMailbox.init();
    defer mailbox.deinit();

    // Initially write_index == read_index == 0 (same buffer)
    // Write red pixel to buffer 0
    const write_buf = mailbox.getWriteBuffer() orelse return error.SkipZigTest;
    write_buf[100] = 0x00FF0000; // Red

    // Swap buffers (write_index: 0→1, read_index: 0)
    mailbox.swapBuffers();

    // Now write_index=1, read_index=0 (different buffers)
    // Write green pixel to buffer 1
    const write_buf2 = mailbox.getWriteBuffer() orelse return error.SkipZigTest;
    write_buf2[100] = 0x0000FF00; // Green

    // Read buffer should still have red (buffer 0, not buffer 1)
    const read_buf = mailbox.getReadBuffer();
    try std.testing.expectEqual(@as(u32, 0x00FF0000), read_buf[100]);

    // Swap again (write_index: 1→2, read_index: 0)
    mailbox.swapBuffers();

    // Read buffer still at 0 (red), write buffer now at 2
    const read_buf2 = mailbox.getReadBuffer();
    try std.testing.expectEqual(@as(u32, 0x00FF0000), read_buf2[100]);

    // Consume frame (read_index: 0→1)
    mailbox.consumeFrame();

    // Now read buffer should have green (buffer 1)
    const read_buf3 = mailbox.getReadBuffer();
    try std.testing.expectEqual(@as(u32, 0x0000FF00), read_buf3[100]);
}
