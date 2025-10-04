// Checksum utilities for snapshot integrity validation
const std = @import("std");

/// Calculate CRC32 checksum of data
/// Uses IEEE polynomial (0xEDB88320)
pub fn calculate(data: []const u8) u32 {
    var hasher = std.hash.Crc32.init();
    hasher.update(data);
    return hasher.final();
}

/// Verify data matches expected checksum
pub fn verify(data: []const u8, expected: u32) bool {
    return calculate(data) == expected;
}

// Tests
const testing = std.testing;

test "Checksum: calculate CRC32" {
    const data = "RAMBO NES Emulator";
    const checksum = calculate(data);

    // CRC32 should be deterministic
    try testing.expect(checksum != 0);
    try testing.expectEqual(checksum, calculate(data));
}

test "Checksum: verify matches" {
    const data = "test data";
    const checksum = calculate(data);

    try testing.expect(verify(data, checksum));
    try testing.expect(!verify(data, checksum +% 1));
}

test "Checksum: empty data" {
    const empty: []const u8 = &[_]u8{};
    const checksum = calculate(empty);

    // Empty data should have known CRC32 value (0)
    try testing.expectEqual(@as(u32, 0), checksum);
}
