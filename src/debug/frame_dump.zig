//! Frame buffer dumping utilities
//!
//! Writes NES frame buffers to PPM P3 (ASCII) format for debugging.
//! Format: 256×240 RGB triplets, human-readable text.

const std = @import("std");

/// NES frame dimensions
pub const FRAME_WIDTH = 256;
pub const FRAME_HEIGHT = 240;
pub const FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT;

/// Dump frame buffer to PPM P3 file
///
/// Input format: RGBA u32 array (0xAABBGGRR little-endian)
/// Output format: PPM P3 ASCII (human-readable RGB triplets)
///
/// Args:
///   allocator: Memory allocator for file operations
///   frame_buffer: 256×240 RGBA pixels (61,440 u32 values)
///   frame_number: Frame number for filename
///
/// Returns: Filename written to (caller owns memory)
pub fn dumpFrameToPpm(
    allocator: std.mem.Allocator,
    frame_buffer: []const u32,
    frame_number: u64,
) ![]const u8 {
    if (frame_buffer.len != FRAME_PIXELS) {
        return error.InvalidFrameBufferSize;
    }

    // Generate filename: frame_NNNN.ppm
    const filename = try std.fmt.allocPrint(allocator, "frame_{d:0>4}.ppm", .{frame_number});
    errdefer allocator.free(filename);

    // Open file for writing
    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    var buffer: [4096]u8 = undefined;
    var file_writer = file.writer(&buffer);

    // Write PPM P3 header
    try file_writer.interface.print("P3\n", .{});
    try file_writer.interface.print("{d} {d}\n", .{ FRAME_WIDTH, FRAME_HEIGHT });
    try file_writer.interface.print("255\n", .{});

    // Write RGB triplets (RGBA u32 → R G B)
    // Format: 0xAABBGGRR (little-endian)
    for (frame_buffer, 0..) |pixel, i| {
        const r: u8 = @truncate(pixel & 0xFF);
        const g: u8 = @truncate((pixel >> 8) & 0xFF);
        const b: u8 = @truncate((pixel >> 16) & 0xFF);
        // Alpha channel ignored (bits 24-31)

        try file_writer.interface.print("{d} {d} {d}", .{ r, g, b });

        // Add newline every 8 pixels for readability
        if ((i + 1) % 8 == 0) {
            try file_writer.interface.print("\n", .{});
        } else {
            try file_writer.interface.print("  ", .{});
        }
    }

    // Ensure final newline
    try file_writer.interface.print("\n", .{});

    // Flush buffered output
    try file_writer.interface.flush();

    return filename;
}

test "dumpFrameToPpm: creates valid PPM file" {
    const allocator = std.testing.allocator;

    // Create test frame (red gradient)
    var frame_buffer: [FRAME_PIXELS]u32 = undefined;
    for (&frame_buffer, 0..) |*pixel, i| {
        const intensity: u8 = @truncate(i % 256);
        pixel.* = @as(u32, intensity) | 0xFF000000; // Red gradient, full alpha
    }

    const filename = try dumpFrameToPpm(allocator, &frame_buffer, 123);
    defer allocator.free(filename);

    // Verify filename
    try std.testing.expectEqualStrings("frame_0123.ppm", filename);

    // Verify file exists and has content
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();
    defer std.fs.cwd().deleteFile(filename) catch {};

    const stat = try file.stat();
    try std.testing.expect(stat.size > 0);

    // Read first few lines to verify header
    var buf: [100]u8 = undefined;
    const bytes_read = try file.read(&buf);
    const content = buf[0..bytes_read];

    try std.testing.expect(std.mem.startsWith(u8, content, "P3\n"));
    try std.testing.expect(std.mem.indexOf(u8, content, "256 240\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "255\n") != null);
}

test "dumpFrameToPpm: rejects invalid buffer size" {
    const allocator = std.testing.allocator;

    var small_buffer: [100]u32 = undefined;
    const result = dumpFrameToPpm(allocator, &small_buffer, 1);

    try std.testing.expectError(error.InvalidFrameBufferSize, result);
}
