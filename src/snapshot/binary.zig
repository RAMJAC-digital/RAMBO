// Binary snapshot format serialization/deserialization
const std = @import("std");
const checksum = @import("checksum.zig");

/// Snapshot format version
pub const SNAPSHOT_VERSION: u32 = 1;

/// Snapshot header (72 bytes total when serialized)
/// Uses regular struct with manual serialization to ensure cross-platform compatibility
/// Layout: magic(8) + version(4) + timestamp(8) + emulator_version(16) + total_size(8) +
///         state_size(4) + cartridge_size(4) + framebuffer_size(4) + flags(4) + checksum(4) + reserved(8)
pub const SnapshotHeader = struct {
    magic: [8]u8 = "RAMBO\x00\x00\x00".*,  // Magic identifier
    version: u32,                           // Format version (1)
    timestamp: i64,                         // Unix timestamp (little-endian)
    emulator_version: [16]u8,               // RAMBO version string
    total_size: u64,                        // Total snapshot size (little-endian)
    state_size: u32,                        // EmulationState size (little-endian)
    cartridge_size: u32,                    // Cartridge data size (little-endian)
    framebuffer_size: u32,                  // Framebuffer size (little-endian)
    flags: u32,                             // Feature flags (little-endian)
    checksum_value: u32,                    // CRC32 of data after header (little-endian)
    reserved: [8]u8 = [_]u8{0} ** 8,        // Future use
};

/// Feature flags for snapshot header
pub const SnapshotFlags = packed struct(u32) {
    has_framebuffer: bool = false,      // Bit 0: Framebuffer included
    cartridge_embedded: bool = false,   // Bit 1: Cartridge ROM embedded
    compressed: bool = false,           // Bit 2: Data is compressed (reserved)
    _padding: u29 = 0,                  // Bits 3-31: Reserved

    pub fn toU32(self: SnapshotFlags) u32 {
        return @bitCast(self);
    }

    pub fn fromU32(value: u32) SnapshotFlags {
        return @bitCast(value);
    }
};

/// Emulator version string (padded to 16 bytes)
pub fn getEmulatorVersion() [16]u8 {
    var version: [16]u8 = [_]u8{0} ** 16;
    const version_str = "RAMBO-0.1.0";
    @memcpy(version[0..version_str.len], version_str);
    return version;
}

/// Create snapshot header (values stored in native byte order, converted during write/read)
pub fn createHeader(
    total_size: u64,
    state_size: u32,
    cartridge_size: u32,
    framebuffer_size: u32,
    flags: SnapshotFlags,
) SnapshotHeader {
    return .{
        .version = SNAPSHOT_VERSION,
        .timestamp = std.time.timestamp(),
        .emulator_version = getEmulatorVersion(),
        .total_size = total_size,
        .state_size = state_size,
        .cartridge_size = cartridge_size,
        .framebuffer_size = framebuffer_size,
        .flags = flags.toU32(),
        .checksum_value = 0,  // Filled in after data is written
    };
}

/// Write header to buffer (little-endian format for cross-platform compatibility)
pub fn writeHeader(writer: anytype, header: *const SnapshotHeader) !void {
    // Write all fields in little-endian byte order
    try writer.writeAll(&header.magic);
    try writer.writeInt(u32, header.version, .little);
    try writer.writeInt(i64, header.timestamp, .little);
    try writer.writeAll(&header.emulator_version);
    try writer.writeInt(u64, header.total_size, .little);
    try writer.writeInt(u32, header.state_size, .little);
    try writer.writeInt(u32, header.cartridge_size, .little);
    try writer.writeInt(u32, header.framebuffer_size, .little);
    try writer.writeInt(u32, header.flags, .little);
    try writer.writeInt(u32, header.checksum_value, .little);
    try writer.writeAll(&header.reserved);
}

/// Read header from buffer (little-endian format)
pub fn readHeader(reader: anytype) !SnapshotHeader {
    var header: SnapshotHeader = undefined;

    // Read all fields in little-endian byte order
    try reader.readNoEof(&header.magic);
    header.version = try reader.readInt(u32, .little);
    header.timestamp = try reader.readInt(i64, .little);
    try reader.readNoEof(&header.emulator_version);
    header.total_size = try reader.readInt(u64, .little);
    header.state_size = try reader.readInt(u32, .little);
    header.cartridge_size = try reader.readInt(u32, .little);
    header.framebuffer_size = try reader.readInt(u32, .little);
    header.flags = try reader.readInt(u32, .little);
    header.checksum_value = try reader.readInt(u32, .little);
    try reader.readNoEof(&header.reserved);

    return header;
}

/// Verify header magic and version
pub fn verifyHeader(header: *const SnapshotHeader) !void {
    const expected_magic = "RAMBO\x00\x00\x00".*;
    if (!std.mem.eql(u8, &header.magic, &expected_magic)) {
        return error.InvalidMagic;
    }

    if (header.version != SNAPSHOT_VERSION) {
        return error.UnsupportedVersion;
    }
}

/// Calculate and update checksum in header
pub fn updateChecksum(header: *SnapshotHeader, data: []const u8) void {
    header.checksum_value = checksum.calculate(data);
}

/// Verify data checksum matches header
pub fn verifyChecksum(header: *const SnapshotHeader, data: []const u8) !void {
    if (!checksum.verify(data, header.checksum_value)) {
        return error.ChecksumMismatch;
    }
}

// Tests
const testing = std.testing;

test "Binary: serialized header is 72 bytes" {
    const flags = SnapshotFlags{};
    const header = createHeader(100, 50, 25, 0, flags);

    // Write header and verify serialized size
    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(testing.allocator);

    try writeHeader(buffer.writer(testing.allocator), &header);

    // Serialized size: magic(8) + version(4) + timestamp(8) + emulator_version(16) + total_size(8) +
    //                 state_size(4) + cartridge_size(4) + framebuffer_size(4) + flags(4) + checksum(4) + reserved(8) = 72 bytes
    try testing.expectEqual(@as(usize, 72), buffer.items.len);
}

test "Binary: create header" {
    const flags = SnapshotFlags{ .has_framebuffer = true, .cartridge_embedded = false };
    const header = createHeader(1024, 512, 256, 245760, flags);

    // Verify magic
    const expected_magic = "RAMBO\x00\x00\x00".*;
    try testing.expectEqualSlices(u8, &expected_magic, &header.magic);

    // Verify version (stored in native format)
    try testing.expectEqual(SNAPSHOT_VERSION, header.version);

    // Verify sizes (stored in native format)
    try testing.expectEqual(@as(u64, 1024), header.total_size);
    try testing.expectEqual(@as(u32, 512), header.state_size);
    try testing.expectEqual(@as(u32, 256), header.cartridge_size);
    try testing.expectEqual(@as(u32, 245760), header.framebuffer_size);
}

test "Binary: write and read header" {
    const flags = SnapshotFlags{};
    var header = createHeader(2048, 1024, 512, 0, flags);

    // Write to buffer
    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(testing.allocator);

    try writeHeader(buffer.writer(testing.allocator), &header);

    // Read back
    var fbs = std.io.fixedBufferStream(buffer.items);
    const read_header = try readHeader(fbs.reader());

    // Verify identical
    try testing.expectEqualSlices(u8, &header.magic, &read_header.magic);
    try testing.expectEqual(header.version, read_header.version);
    try testing.expectEqual(header.total_size, read_header.total_size);
}

test "Binary: verify header magic and version" {
    const flags = SnapshotFlags{};
    var header = createHeader(100, 50, 25, 0, flags);

    // Should pass
    try verifyHeader(&header);

    // Corrupt magic
    var bad_header = header;
    bad_header.magic[0] = 'X';
    try testing.expectError(error.InvalidMagic, verifyHeader(&bad_header));

    // Corrupt version
    bad_header = header;
    bad_header.version = 999;
    try testing.expectError(error.UnsupportedVersion, verifyHeader(&bad_header));
}

test "Binary: checksum calculation and verification" {
    const flags = SnapshotFlags{};
    var header = createHeader(100, 50, 25, 0, flags);

    const test_data = "test snapshot data";

    // Update checksum
    updateChecksum(&header, test_data);

    // Should verify successfully
    try verifyChecksum(&header, test_data);

    // Corrupted data should fail
    const corrupted_data = "test snapshot DATA";  // Changed case
    try testing.expectError(error.ChecksumMismatch, verifyChecksum(&header, corrupted_data));
}

test "Binary: feature flags" {
    var flags = SnapshotFlags{};
    flags.has_framebuffer = true;
    flags.cartridge_embedded = true;

    const value = flags.toU32();
    const restored = SnapshotFlags.fromU32(value);

    try testing.expectEqual(flags.has_framebuffer, restored.has_framebuffer);
    try testing.expectEqual(flags.cartridge_embedded, restored.cartridge_embedded);
}
