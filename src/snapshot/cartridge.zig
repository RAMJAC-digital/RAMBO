// Cartridge snapshot serialization
const std = @import("std");

/// iNES header structure (16 bytes)
pub const InesHeader = struct {
    raw: [16]u8,
};

/// Nametable mirroring mode
pub const Mirroring = enum(u8) {
    horizontal = 0,
    vertical = 1,
    four_screen = 2,
};

/// Cartridge snapshot mode
pub const CartridgeSnapshotMode = enum(u8) {
    reference = 0,  // Store ROM path/hash only
    embed = 1,      // Store full ROM data
};

/// Cartridge reference snapshot (stores ROM metadata only)
pub const CartridgeReference = struct {
    rom_path: []const u8,      // Path to ROM file
    rom_hash: [32]u8,          // SHA-256 hash of ROM data
    mapper_state: []const u8,  // Mapper-specific state (if any)
};

/// Cartridge embed snapshot (stores complete ROM data)
pub const CartridgeEmbed = struct {
    header: InesHeader,        // iNES header (16 bytes)
    prg_rom: []const u8,       // PRG ROM data
    chr_data: []const u8,      // CHR data (ROM or RAM)
    mirroring: Mirroring,      // Nametable mirroring
    mapper_state: []const u8,  // Mapper-specific state (if any)
};

/// Cartridge snapshot (union of modes)
pub const CartridgeSnapshot = union(CartridgeSnapshotMode) {
    reference: CartridgeReference,
    embed: CartridgeEmbed,

    /// Get total serialized size
    pub fn getSerializedSize(self: *const CartridgeSnapshot) usize {
        return switch (self.*) {
            .reference => |ref| blk: {
                // mode(1) + path_len(4) + path + hash(32) + state_len(4) + state
                break :blk 1 + 4 + ref.rom_path.len + 32 + 4 + ref.mapper_state.len;
            },
            .embed => |emb| blk: {
                // mode(1) + header(16) + mirroring(1) + prg_len(4) + prg + chr_len(4) + chr + state_len(4) + state
                break :blk 1 + 16 + 1 + 4 + emb.prg_rom.len + 4 + emb.chr_data.len + 4 + emb.mapper_state.len;
            },
        };
    }
};

/// Write cartridge snapshot to buffer
pub fn writeCartridgeSnapshot(writer: anytype, snapshot: *const CartridgeSnapshot) !void {
    // Write mode
    try writer.writeByte(@intFromEnum(@as(CartridgeSnapshotMode, snapshot.*)));

    switch (snapshot.*) {
        .reference => |ref| {
            // Write ROM path
            try writer.writeInt(u32, @intCast(ref.rom_path.len), .little);
            try writer.writeAll(ref.rom_path);

            // Write ROM hash
            try writer.writeAll(&ref.rom_hash);

            // Write mapper state
            try writer.writeInt(u32, @intCast(ref.mapper_state.len), .little);
            try writer.writeAll(ref.mapper_state);
        },
        .embed => |emb| {
            // Write iNES header (16 bytes)
            try writer.writeAll(&emb.header.raw);

            // Write mirroring
            try writer.writeByte(@intFromEnum(emb.mirroring));

            // Write PRG ROM
            try writer.writeInt(u32, @intCast(emb.prg_rom.len), .little);
            try writer.writeAll(emb.prg_rom);

            // Write CHR data
            try writer.writeInt(u32, @intCast(emb.chr_data.len), .little);
            try writer.writeAll(emb.chr_data);

            // Write mapper state
            try writer.writeInt(u32, @intCast(emb.mapper_state.len), .little);
            try writer.writeAll(emb.mapper_state);
        },
    }
}

/// Read cartridge snapshot from buffer
pub fn readCartridgeSnapshot(allocator: std.mem.Allocator, reader: anytype) !CartridgeSnapshot {
    // Read mode
    const mode_byte = try reader.readByte();
    const mode: CartridgeSnapshotMode = @enumFromInt(mode_byte);

    return switch (mode) {
        .reference => blk: {
            // Read ROM path
            const path_len = try reader.readInt(u32, .little);
            const rom_path = try allocator.alloc(u8, path_len);
            errdefer allocator.free(rom_path);
            try reader.readNoEof(rom_path);

            // Read ROM hash
            var rom_hash: [32]u8 = undefined;
            try reader.readNoEof(&rom_hash);

            // Read mapper state
            const state_len = try reader.readInt(u32, .little);
            const mapper_state = try allocator.alloc(u8, state_len);
            errdefer allocator.free(mapper_state);
            try reader.readNoEof(mapper_state);

            break :blk CartridgeSnapshot{
                .reference = .{
                    .rom_path = rom_path,
                    .rom_hash = rom_hash,
                    .mapper_state = mapper_state,
                },
            };
        },
        .embed => blk: {
            // Read iNES header
            var header: InesHeader = undefined;
            try reader.readNoEof(&header.raw);

            // Read mirroring
            const mirroring_byte = try reader.readByte();
            const mirroring: Mirroring = @enumFromInt(mirroring_byte);

            // Read PRG ROM
            const prg_len = try reader.readInt(u32, .little);
            const prg_rom = try allocator.alloc(u8, prg_len);
            errdefer allocator.free(prg_rom);
            try reader.readNoEof(prg_rom);

            // Read CHR data
            const chr_len = try reader.readInt(u32, .little);
            const chr_data = try allocator.alloc(u8, chr_len);
            errdefer allocator.free(chr_data);
            try reader.readNoEof(chr_data);

            // Read mapper state
            const state_len = try reader.readInt(u32, .little);
            const mapper_state = try allocator.alloc(u8, state_len);
            errdefer allocator.free(mapper_state);
            try reader.readNoEof(mapper_state);

            break :blk CartridgeSnapshot{
                .embed = .{
                    .header = header,
                    .prg_rom = prg_rom,
                    .chr_data = chr_data,
                    .mirroring = mirroring,
                    .mapper_state = mapper_state,
                },
            };
        },
    };
}

/// Free cartridge snapshot allocations
pub fn freeCartridgeSnapshot(allocator: std.mem.Allocator, snapshot: *CartridgeSnapshot) void {
    switch (snapshot.*) {
        .reference => |ref| {
            allocator.free(ref.rom_path);
            allocator.free(ref.mapper_state);
        },
        .embed => |emb| {
            allocator.free(emb.prg_rom);
            allocator.free(emb.chr_data);
            allocator.free(emb.mapper_state);
        },
    }
}

/// Calculate SHA-256 hash of ROM data
pub fn calculateRomHash(rom_data: []const u8) [32]u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(rom_data, &hash, .{});
    return hash;
}

// Tests
const testing = std.testing;

test "Cartridge: embed mode round-trip" {
    // Create test cartridge data
    const test_prg = [_]u8{ 0x01, 0x02, 0x03, 0x04 };
    const test_chr = [_]u8{ 0x05, 0x06 };
    const test_state = [_]u8{ 0xFF };

    var header: InesHeader = undefined;
    @memset(&header.raw, 0);
    header.raw[0] = 'N';
    header.raw[1] = 'E';
    header.raw[2] = 'S';
    header.raw[3] = 0x1A;

    var snapshot = CartridgeSnapshot{
        .embed = .{
            .header = header,
            .prg_rom = &test_prg,
            .chr_data = &test_chr,
            .mirroring = .horizontal,
            .mapper_state = &test_state,
        },
    };

    // Write to buffer
    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(testing.allocator);

    try writeCartridgeSnapshot(buffer.writer(testing.allocator), &snapshot);

    // Verify size
    const expected_size = snapshot.getSerializedSize();
    try testing.expectEqual(expected_size, buffer.items.len);

    // Read back
    var fbs = std.io.fixedBufferStream(buffer.items);
    var restored = try readCartridgeSnapshot(testing.allocator, fbs.reader());
    defer freeCartridgeSnapshot(testing.allocator, &restored);

    // Verify mode
    try testing.expectEqual(CartridgeSnapshotMode.embed, @as(CartridgeSnapshotMode, restored));

    // Verify data
    const restored_embed = restored.embed;
    try testing.expectEqualSlices(u8, "NES\x1A", restored_embed.header.raw[0..4]);
    try testing.expectEqualSlices(u8, &test_prg, restored_embed.prg_rom);
    try testing.expectEqualSlices(u8, &test_chr, restored_embed.chr_data);
    try testing.expectEqual(Mirroring.horizontal, restored_embed.mirroring);
    try testing.expectEqualSlices(u8, &test_state, restored_embed.mapper_state);
}

test "Cartridge: reference mode round-trip" {
    const test_path = "/path/to/rom.nes";
    const test_hash = [_]u8{0xAB} ** 32;
    const test_state = [_]u8{ 0x42, 0x43 };

    var snapshot = CartridgeSnapshot{
        .reference = .{
            .rom_path = test_path,
            .rom_hash = test_hash,
            .mapper_state = &test_state,
        },
    };

    // Write to buffer
    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(testing.allocator);

    try writeCartridgeSnapshot(buffer.writer(testing.allocator), &snapshot);

    // Read back
    var fbs = std.io.fixedBufferStream(buffer.items);
    var restored = try readCartridgeSnapshot(testing.allocator, fbs.reader());
    defer freeCartridgeSnapshot(testing.allocator, &restored);

    // Verify mode
    try testing.expectEqual(CartridgeSnapshotMode.reference, @as(CartridgeSnapshotMode, restored));

    // Verify data
    const restored_ref = restored.reference;
    try testing.expectEqualStrings(test_path, restored_ref.rom_path);
    try testing.expectEqualSlices(u8, &test_hash, &restored_ref.rom_hash);
    try testing.expectEqualSlices(u8, &test_state, restored_ref.mapper_state);
}

test "Cartridge: hash calculation" {
    const test_data = "NES ROM DATA";
    const hash = calculateRomHash(test_data);

    // Verify hash is not all zeros
    var all_zero = true;
    for (hash) |byte| {
        if (byte != 0) {
            all_zero = false;
            break;
        }
    }
    try testing.expect(!all_zero);

    // Verify hash is deterministic
    const hash2 = calculateRomHash(test_data);
    try testing.expectEqualSlices(u8, &hash, &hash2);
}
