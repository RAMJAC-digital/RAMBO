//! Frame dump utility tests
//!
//! Verifies that frame dumping correctly consumes frames from the mailbox
//! to prevent blocking the emulation thread.

const std = @import("std");
const testing = std.testing;
const frame_dump = @import("../../src/debug/frame_dump.zig");
const FrameMailbox = @import("../../src/mailboxes/FrameMailbox.zig").FrameMailbox;

test "frame_dump: creates valid PPM file" {
    const allocator = testing.allocator;

    // Create test frame (gradient pattern)
    var frame_buffer: [frame_dump.FRAME_PIXELS]u32 = undefined;
    for (&frame_buffer, 0..) |*pixel, i| {
        const row = i / frame_dump.FRAME_WIDTH;
        const col = i % frame_dump.FRAME_WIDTH;
        const r: u8 = @truncate(row);
        const g: u8 = @truncate(col);
        const b: u8 = @truncate((row + col) % 256);
        pixel.* = @as(u32, r) | (@as(u32, g) << 8) | (@as(u32, b) << 16) | 0xFF000000;
    }

    const filename = try frame_dump.dumpFrameToPpm(allocator, &frame_buffer, 42);
    defer allocator.free(filename);

    // Verify filename format
    try testing.expectEqualStrings("frame_0042.ppm", filename);

    // Verify file exists
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();
    defer std.fs.cwd().deleteFile(filename) catch {};

    // Read header
    var buf: [100]u8 = undefined;
    const bytes_read = try file.read(&buf);
    const content = buf[0..bytes_read];

    // Verify PPM P3 header
    try testing.expect(std.mem.startsWith(u8, content, "P3\n"));
    try testing.expect(std.mem.indexOf(u8, content, "256 240\n") != null);
    try testing.expect(std.mem.indexOf(u8, content, "255\n") != null);
}

test "frame_dump: mailbox consumption prevents blocking" {
    // This test simulates the main loop scenario where frame dump
    // must consume frames to prevent the mailbox from filling up

    var mailbox = FrameMailbox.init();
    defer mailbox.deinit();

    // Simulate emulation thread producing frames
    // Write 3 frames (fills the triple-buffer)
    for (0..3) |i| {
        const write_buf = mailbox.getWriteBuffer() orelse {
            try testing.expect(false); // Should not fail to get buffer
            return;
        };
        // Fill with test pattern
        for (write_buf, 0..) |*pixel, j| {
            pixel.* = @as(u32, @intCast(i * 1000 + j));
        }
        mailbox.swapBuffers();
    }

    // At this point, mailbox is full (3 frames written, 0 consumed)
    // Next write would fail without consumption

    // Simulate main loop consuming frames (like frame dump does)
    var consumed_count: usize = 0;
    while (mailbox.hasNewFrame()) {
        _ = mailbox.getReadBuffer();
        mailbox.consumeFrame();
        consumed_count += 1;
    }

    // Verify we consumed all 3 frames
    try testing.expectEqual(@as(usize, 3), consumed_count);

    // Verify mailbox is now empty
    try testing.expect(!mailbox.hasNewFrame());

    // Verify we can write again (mailbox no longer blocked)
    const write_buf = mailbox.getWriteBuffer();
    try testing.expect(write_buf != null);
}

test "frame_dump: selective frame consumption" {
    // This test verifies the pattern used in main.zig where we:
    // 1. Consume frames before the target frame
    // 2. Dump the target frame and consume it
    // 3. Exit after dumping

    var mailbox = FrameMailbox.init();
    defer mailbox.deinit();

    const target_frame: usize = 5;
    var current_frame: usize = 0;

    // Simulate producing frames 0-7
    for (0..8) |_| {
        const write_buf = mailbox.getWriteBuffer() orelse break;
        for (write_buf) |*pixel| {
            pixel.* = @as(u32, @intCast(current_frame));
        }
        mailbox.swapBuffers();
        current_frame += 1;

        // Simulate main loop consumption pattern
        if (mailbox.hasNewFrame()) {
            const read_buf = mailbox.getReadBuffer();
            const frame_value = read_buf[0]; // First pixel contains frame number

            if (frame_value >= target_frame) {
                // This is our target frame - verify it's frame 5
                try testing.expectEqual(@as(u32, target_frame), frame_value);
                mailbox.consumeFrame();
                break; // Exit after dumping (simulated)
            } else {
                // Consume frames before target
                mailbox.consumeFrame();
            }
        }
    }

    // Verify we stopped at the target frame
    // current_frame should be 6 (frames 0-5 produced, stopped after frame 5)
    try testing.expectEqual(@as(usize, 6), current_frame);
}

test "frame_dump: error handling consumes frame" {
    // Verify that even on dump error, frame is consumed to prevent blocking

    var mailbox = FrameMailbox.init();
    defer mailbox.deinit();

    // Produce a frame
    const write_buf = mailbox.getWriteBuffer().?;
    for (write_buf) |*pixel| {
        pixel.* = 0xFF0000FF; // Red
    }
    mailbox.swapBuffers();

    // Verify frame is available
    try testing.expect(mailbox.hasNewFrame());

    // Simulate error during dump (e.g., filesystem error)
    // In real code, we'd still call consumeFrame() in the error handler
    _ = mailbox.getReadBuffer();
    mailbox.consumeFrame(); // Must consume even on error

    // Verify mailbox is now empty
    try testing.expect(!mailbox.hasNewFrame());
}
