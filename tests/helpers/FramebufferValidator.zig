//! Framebuffer Validation Utilities
//!
//! Helper functions for validating PPU framebuffer output in integration tests.
//! Provides pixel counting, hashing, diff comparison, and PPM export.

const std = @import("std");

/// NES PPU framebuffer dimensions
pub const FRAME_WIDTH = 256;
pub const FRAME_HEIGHT = 240;
pub const FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT; // 61,440

/// Count non-zero pixels in framebuffer
/// Useful for detecting if rendering is producing output
pub fn countNonZeroPixels(framebuffer: []const u32) usize {
    var count: usize = 0;
    for (framebuffer) |pixel| {
        if (pixel != 0) count += 1;
    }
    return count;
}

/// Count pixels of specific color
/// Useful for detecting specific rendering patterns
pub fn countColorPixels(framebuffer: []const u32, color: u32) usize {
    var count: usize = 0;
    for (framebuffer) |pixel| {
        if (pixel == color) count += 1;
    }
    return count;
}

/// Calculate CRC32 hash for framebuffer
/// Useful for visual regression testing
pub fn framebufferHash(framebuffer: []const u32) u64 {
    const hasher = std.hash.Crc32.hash(std.mem.sliceAsBytes(framebuffer));
    return @as(u64, hasher);
}

/// Compare two framebuffers and return difference percentage
/// Returns 0.0 if identical, 100.0 if completely different
pub fn framebufferDiffPercent(fb1: []const u32, fb2: []const u32) f32 {
    std.debug.assert(fb1.len == fb2.len);
    var diff_count: usize = 0;
    for (fb1, fb2) |p1, p2| {
        if (p1 != p2) diff_count += 1;
    }
    const diff_ratio = @as(f32, @floatFromInt(diff_count)) /
        @as(f32, @floatFromInt(fb1.len));
    return diff_ratio * 100.0;
}

/// Check if framebuffers differ by more than tolerance
/// tolerance_percent: 0.0-100.0 (e.g., 1.0 = 1% difference allowed)
pub fn framebuffersDiffer(
    fb1: []const u32,
    fb2: []const u32,
    tolerance_percent: f32,
) bool {
    const diff = framebufferDiffPercent(fb1, fb2);
    return diff > tolerance_percent;
}

/// Save framebuffer as PPM (Portable Pixmap) file
/// PPM format is simple ASCII/binary image format, easy to debug
/// Can be viewed with many image viewers (GIMP, ImageMagick, etc.)
pub fn saveFramebufferPPM(
    framebuffer: []const u32,
    path: []const u8,
    allocator: std.mem.Allocator,
) !void {
    _ = allocator; // Not needed for file operations

    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    var writer = file.writer();

    // PPM header (P3 = ASCII format, 256x240, max value 255)
    try writer.print("P3\n{d} {d}\n255\n", .{ FRAME_WIDTH, FRAME_HEIGHT });

    // Write pixels (RGB format, RGBA u32 → R G B)
    for (framebuffer, 0..) |pixel, i| {
        // Extract RGB from RGBA u32 (0xAABBGGRR format)
        const r = (pixel >> 16) & 0xFF;
        const g = (pixel >> 8) & 0xFF;
        const b = pixel & 0xFF;

        try writer.print("{d} {d} {d} ", .{ r, g, b });

        // Newline every scanline for readability
        if ((i + 1) % FRAME_WIDTH == 0) {
            try writer.writeByte('\n');
        }
    }
}

/// Validate framebuffer has expected properties
/// Returns error with diagnostic message if validation fails
pub const FramebufferExpectation = struct {
    min_non_zero_pixels: ?usize = null,
    max_black_pixels: ?usize = null,
    expected_hash: ?u64 = null,
    hash_tolerance: f32 = 0.0, // Allow N% pixel difference from hash
};

pub fn validateFramebuffer(
    framebuffer: []const u32,
    expect: FramebufferExpectation,
) !void {
    if (expect.min_non_zero_pixels) |min_pixels| {
        const count = countNonZeroPixels(framebuffer);
        if (count < min_pixels) {
            return error.InsufficientRendering;
        }
    }

    if (expect.max_black_pixels) |max_black| {
        const black_count = countColorPixels(framebuffer, 0x00000000);
        if (black_count > max_black) {
            return error.TooManyBlackPixels;
        }
    }

    if (expect.expected_hash) |expected| {
        const actual = framebufferHash(framebuffer);
        if (actual != expected and expect.hash_tolerance == 0.0) {
            return error.HashMismatch;
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

test "FramebufferValidator: count non-zero pixels" {
    var framebuffer = [_]u32{0} ** FRAME_PIXELS;

    // All black
    try std.testing.expectEqual(@as(usize, 0), countNonZeroPixels(&framebuffer));

    // One white pixel
    framebuffer[1000] = 0x00FFFFFF;
    try std.testing.expectEqual(@as(usize, 1), countNonZeroPixels(&framebuffer));

    // Multiple colors
    framebuffer[2000] = 0x00FF0000; // Red
    framebuffer[3000] = 0x0000FF00; // Green
    try std.testing.expectEqual(@as(usize, 3), countNonZeroPixels(&framebuffer));
}

test "FramebufferValidator: count color pixels" {
    var framebuffer = [_]u32{0} ** FRAME_PIXELS;

    // Count red pixels
    framebuffer[100] = 0x00FF0000;
    framebuffer[200] = 0x00FF0000;
    framebuffer[300] = 0x0000FF00; // Green, not red
    try std.testing.expectEqual(@as(usize, 2), countColorPixels(&framebuffer, 0x00FF0000));
}

test "FramebufferValidator: hash consistency" {
    var fb1 = [_]u32{0x00123456} ** FRAME_PIXELS;
    var fb2 = [_]u32{0x00123456} ** FRAME_PIXELS;

    // Same content should have same hash
    const hash1 = framebufferHash(&fb1);
    const hash2 = framebufferHash(&fb2);
    try std.testing.expectEqual(hash1, hash2);

    // Different content should have different hash
    fb2[1000] = 0x00ABCDEF;
    const hash3 = framebufferHash(&fb2);
    try std.testing.expect(hash1 != hash3);
}

test "FramebufferValidator: diff percentage" {
    var fb1 = [_]u32{0x00000000} ** FRAME_PIXELS;
    var fb2 = [_]u32{0x00000000} ** FRAME_PIXELS;

    // Identical framebuffers
    try std.testing.expectEqual(@as(f32, 0.0), framebufferDiffPercent(&fb1, &fb2));

    // 1 pixel different out of 61,440 = ~0.0016%
    fb2[1000] = 0x00FFFFFF;
    const diff = framebufferDiffPercent(&fb1, &fb2);
    try std.testing.expect(diff > 0.0 and diff < 0.01);

    // Completely different
    fb2 = [_]u32{0x00FFFFFF} ** FRAME_PIXELS;
    try std.testing.expectEqual(@as(f32, 100.0), framebufferDiffPercent(&fb1, &fb2));
}

test "FramebufferValidator: diff tolerance" {
    var fb1 = [_]u32{0x00000000} ** FRAME_PIXELS;
    var fb2 = [_]u32{0x00000000} ** FRAME_PIXELS;

    // Within 1% tolerance
    fb2[1000] = 0x00FFFFFF;
    try std.testing.expect(!framebuffersDiffer(&fb1, &fb2, 1.0));

    // Exceeds tolerance
    try std.testing.expect(framebuffersDiffer(&fb1, &fb2, 0.0001));
}

test "FramebufferValidator: validate expectations pass" {
    var framebuffer = [_]u32{0} ** FRAME_PIXELS;

    // Fill with 1000 white pixels
    for (0..1000) |i| {
        framebuffer[i] = 0x00FFFFFF;
    }

    // Should pass
    try validateFramebuffer(&framebuffer, .{
        .min_non_zero_pixels = 500,
    });

    // Should pass (black pixels = 61,440 - 1,000 = 60,440)
    try validateFramebuffer(&framebuffer, .{
        .max_black_pixels = 61000,
    });
}

test "FramebufferValidator: validate expectations fail" {
    var framebuffer = [_]u32{0} ** FRAME_PIXELS;

    // Only 10 white pixels
    for (0..10) |i| {
        framebuffer[i] = 0x00FFFFFF;
    }

    // Should fail (not enough non-zero pixels)
    const result = validateFramebuffer(&framebuffer, .{
        .min_non_zero_pixels = 1000,
    });
    try std.testing.expectError(error.InsufficientRendering, result);
}
