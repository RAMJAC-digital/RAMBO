//! Cartridge File Loader (Generic/Comptime Implementation)
//!
//! Handles loading .nes ROM files from the filesystem.
//! Works with generic Cartridge(MapperType) for compile-time dispatch.
//!
//! Currently uses synchronous std.fs API for simplicity.
//! Future enhancement: Integrate with libxev for async file I/O when event loop is active.

const std = @import("std");
const Cartridge = @import("Cartridge.zig").Cartridge;
const AnyCartridge = @import("mappers/registry.zig").AnyCartridge;
const Mapper0 = @import("mappers/Mapper0.zig").Mapper0;
const Mapper1 = @import("mappers/Mapper1.zig").Mapper1;
const Mapper2 = @import("mappers/Mapper2.zig").Mapper2;
const Mapper3 = @import("mappers/Mapper3.zig").Mapper3;
const Mapper4 = @import("mappers/Mapper4.zig").Mapper4;
const Mapper7 = @import("mappers/Mapper7.zig").Mapper7;
const ines = @import("ines/mod.zig");

/// Maximum ROM file size (1MB - reasonable limit for NES ROMs)
const MAX_ROM_SIZE: usize = 1024 * 1024;

/// Load any supported cartridge from memory buffer (dynamic dispatch)
pub fn loadAnyCartridgeBytes(
    allocator: std.mem.Allocator,
    data: []const u8,
) !AnyCartridge {
    if (data.len < 16) return error.InvalidRomSize;
    const header = try ines.parseHeader(data[0..16]);
    const mapper_num = header.getMapperNumber();

    return switch (mapper_num) {
        0 => {
            const cart = try Cartridge(Mapper0).loadFromData(allocator, data);
            return AnyCartridge{ .nrom = cart };
        },
        1 => {
            const cart = try Cartridge(Mapper1).loadFromData(allocator, data);
            return AnyCartridge{ .mmc1 = cart };
        },
        2 => {
            const cart = try Cartridge(Mapper2).loadFromData(allocator, data);
            return AnyCartridge{ .uxrom = cart };
        },
        3 => {
            const cart = try Cartridge(Mapper3).loadFromData(allocator, data);
            return AnyCartridge{ .cnrom = cart };
        },
        4 => {
            const cart = try Cartridge(Mapper4).loadFromData(allocator, data);
            return AnyCartridge{ .mmc3 = cart };
        },
        7 => {
            const cart = try Cartridge(Mapper7).loadFromData(allocator, data);
            return AnyCartridge{ .axrom = cart };
        },
        else => error.UnsupportedMapper,
    };
}

/// Load any supported cartridge from file path (dynamic dispatch)
///
/// Reads the iNES header to determine mapper type, then loads the appropriate
/// cartridge variant into an AnyCartridge union.
///
/// Returns error.UnsupportedMapper if the ROM uses a mapper we don't support.
pub fn loadAnyCartridgeFile(
    allocator: std.mem.Allocator,
    path: []const u8,
) !AnyCartridge {
    // Open file and read data
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const data = try file.readToEndAlloc(allocator, MAX_ROM_SIZE);
    defer allocator.free(data);

    return loadAnyCartridgeBytes(allocator, data);
}

/// Load cartridge from file path (synchronous)
/// Reads entire file into memory, then parses as iNES format
///
/// Generic over mapper type for compile-time dispatch.
///
/// Future: This will be replaced with async libxev-based loading when event loop exists
pub fn loadCartridgeFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    comptime MapperType: type,
) !Cartridge(MapperType) {
    // Open file for reading
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    // Read entire file into memory
    const data = try file.readToEndAlloc(allocator, MAX_ROM_SIZE);
    defer allocator.free(data);

    // Parse iNES format and create cartridge
    const CartType = Cartridge(MapperType);
    return try CartType.loadFromData(allocator, data);
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "loader: load valid file" {
    // Create a temporary test ROM file
    const test_rom_path = "test_rom.nes";
    defer std.fs.cwd().deleteFile(test_rom_path) catch {};

    // Create minimal valid ROM data
    var rom_data = [_]u8{0} ** (16 + 16384 + 8192);
    rom_data[0] = 'N';
    rom_data[1] = 'E';
    rom_data[2] = 'S';
    rom_data[3] = 0x1A;
    rom_data[4] = 1; // 1 x 16KB PRG ROM
    rom_data[5] = 1; // 1 x 8KB CHR ROM
    rom_data[6] = 0;
    rom_data[7] = 0;

    // Write test file
    const file = try std.fs.cwd().createFile(test_rom_path, .{});
    defer file.close();
    try file.writeAll(&rom_data);

    // Load cartridge from file (generic over Mapper0)
    var cart = try loadCartridgeFile(testing.allocator, test_rom_path, Mapper0);
    defer cart.deinit();

    try testing.expectEqual(@as(usize, 16384), cart.prg_rom.len);
    try testing.expectEqual(@as(usize, 8192), cart.chr_data.len);
}

test "loader: file not found" {
    const result = loadCartridgeFile(testing.allocator, "nonexistent_file.nes", Mapper0);
    try testing.expectError(error.FileNotFound, result);
}
