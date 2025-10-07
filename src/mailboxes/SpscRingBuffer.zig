//! Lock-Free SPSC (Single Producer Single Consumer) Ring Buffer
//!
//! Thread-safe ring buffer using atomic operations (no mutexes)
//! Suitable for mailbox communication between exactly 2 threads
//!
//! Properties:
//! - Lock-free: Uses only atomic operations
//! - Wait-free reads/writes (when not full/empty)
//! - Fixed capacity (compile-time or runtime)
//! - Zero-copy: Direct access to buffer elements

const std = @import("std");

/// Lock-free SPSC ring buffer
/// T: Element type
/// capacity: Buffer size (must be power of 2 for efficient modulo)
pub fn SpscRingBuffer(comptime T: type, comptime capacity: usize) type {
    // Validate capacity is power of 2
    comptime {
        if (capacity == 0 or (capacity & (capacity - 1)) != 0) {
            @compileError("SpscRingBuffer capacity must be a power of 2");
        }
    }

    return struct {
        const Self = @This();
        const mask = capacity - 1; // For fast modulo using bitwise AND

        /// Ring buffer storage
        buffer: [capacity]T,

        /// Write index (modified only by producer)
        write_index: std.atomic.Value(usize) = .{ .raw = 0 },

        /// Read index (modified only by consumer)
        read_index: std.atomic.Value(usize) = .{ .raw = 0 },

        /// Initialize empty ring buffer
        pub fn init() Self {
            return .{
                .buffer = undefined, // Will be written before read
            };
        }

        /// Push item to buffer (called by producer thread only)
        /// Returns true if successful, false if buffer is full
        pub fn push(self: *Self, item: T) bool {
            const write = self.write_index.load(.monotonic);
            const read = self.read_index.load(.acquire);

            const next_write = (write + 1) & mask;

            // Buffer is full if next_write == read
            if (next_write == read) {
                return false;
            }

            // Write item
            self.buffer[write] = item;

            // Publish write (release ensures write is visible before index update)
            self.write_index.store(next_write, .release);
            return true;
        }

        /// Pop item from buffer (called by consumer thread only)
        /// Returns null if buffer is empty
        pub fn pop(self: *Self) ?T {
            const read = self.read_index.load(.monotonic);
            const write = self.write_index.load(.acquire);

            // Buffer is empty if read == write
            if (read == write) {
                return null;
            }

            // Read item
            const item = self.buffer[read];

            // Publish read (release ensures read is complete before index update)
            const next_read = (read + 1) & mask;
            self.read_index.store(next_read, .release);

            return item;
        }

        /// Check if buffer is empty (can be called by either thread)
        pub fn isEmpty(self: *const Self) bool {
            const read = self.read_index.load(.monotonic);
            const write = self.write_index.load(.acquire);
            return read == write;
        }

        /// Check if buffer is full (can be called by either thread)
        pub fn isFull(self: *const Self) bool {
            const write = self.write_index.load(.monotonic);
            const read = self.read_index.load(.acquire);
            const next_write = (write + 1) & mask;
            return next_write == read;
        }

        /// Get current number of items in buffer (approximate for concurrent use)
        pub fn len(self: *const Self) usize {
            const write = self.write_index.load(.monotonic);
            const read = self.read_index.load(.acquire);
            return (write -% read) & mask;
        }

        /// Get buffer capacity
        pub fn cap() usize {
            return capacity;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "SpscRingBuffer: basic push and pop" {
    var buffer = SpscRingBuffer(u32, 4).init();

    // Push items
    try std.testing.expect(buffer.push(10));
    try std.testing.expect(buffer.push(20));
    try std.testing.expect(buffer.push(30));

    // Pop items
    try std.testing.expectEqual(@as(u32, 10), buffer.pop().?);
    try std.testing.expectEqual(@as(u32, 20), buffer.pop().?);
    try std.testing.expectEqual(@as(u32, 30), buffer.pop().?);

    // Buffer should be empty
    try std.testing.expect(buffer.pop() == null);
}

test "SpscRingBuffer: capacity enforcement" {
    var buffer = SpscRingBuffer(u8, 4).init();

    // Fill buffer (capacity - 1 due to full detection)
    try std.testing.expect(buffer.push(1));
    try std.testing.expect(buffer.push(2));
    try std.testing.expect(buffer.push(3));

    // Buffer should be full
    try std.testing.expect(!buffer.push(4)); // Should fail
    try std.testing.expect(buffer.isFull());

    // Pop one item
    _ = buffer.pop();

    // Now should be able to push
    try std.testing.expect(buffer.push(4));
}

test "SpscRingBuffer: FIFO ordering" {
    var buffer = SpscRingBuffer(u32, 8).init();

    const values = [_]u32{ 100, 200, 300, 400, 500 };

    // Push all values
    for (values) |val| {
        try std.testing.expect(buffer.push(val));
    }

    // Pop all values in same order
    for (values) |expected| {
        const actual = buffer.pop();
        try std.testing.expect(actual != null);
        try std.testing.expectEqual(expected, actual.?);
    }
}

test "SpscRingBuffer: isEmpty and isFull" {
    var buffer = SpscRingBuffer(i32, 4).init();

    // Should start empty
    try std.testing.expect(buffer.isEmpty());
    try std.testing.expect(!buffer.isFull());

    // Fill buffer
    try std.testing.expect(buffer.push(1));
    try std.testing.expect(buffer.push(2));
    try std.testing.expect(buffer.push(3));

    // Should be full
    try std.testing.expect(!buffer.isEmpty());
    try std.testing.expect(buffer.isFull());

    // Drain buffer
    _ = buffer.pop();
    _ = buffer.pop();
    _ = buffer.pop();

    // Should be empty again
    try std.testing.expect(buffer.isEmpty());
    try std.testing.expect(!buffer.isFull());
}

test "SpscRingBuffer: wrap around" {
    var buffer = SpscRingBuffer(u32, 4).init();

    // Fill and drain multiple times to test wrap-around
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        try std.testing.expect(buffer.push(i));
        try std.testing.expect(buffer.push(i + 100));

        try std.testing.expectEqual(i, buffer.pop().?);
        try std.testing.expectEqual(i + 100, buffer.pop().?);
    }
}

test "SpscRingBuffer: len tracking" {
    var buffer = SpscRingBuffer(u32, 8).init();

    try std.testing.expectEqual(@as(usize, 0), buffer.len());

    try std.testing.expect(buffer.push(1));
    try std.testing.expectEqual(@as(usize, 1), buffer.len());

    try std.testing.expect(buffer.push(2));
    try std.testing.expectEqual(@as(usize, 2), buffer.len());

    _ = buffer.pop();
    try std.testing.expectEqual(@as(usize, 1), buffer.len());

    _ = buffer.pop();
    try std.testing.expectEqual(@as(usize, 0), buffer.len());
}

test "SpscRingBuffer: struct element type" {
    const Point = struct {
        x: i32,
        y: i32,
    };

    var buffer = SpscRingBuffer(Point, 4).init();

    try std.testing.expect(buffer.push(.{ .x = 10, .y = 20 }));
    try std.testing.expect(buffer.push(.{ .x = 30, .y = 40 }));

    const p1 = buffer.pop().?;
    try std.testing.expectEqual(@as(i32, 10), p1.x);
    try std.testing.expectEqual(@as(i32, 20), p1.y);

    const p2 = buffer.pop().?;
    try std.testing.expectEqual(@as(i32, 30), p2.x);
    try std.testing.expectEqual(@as(i32, 40), p2.y);
}
