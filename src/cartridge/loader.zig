//! Cartridge File Loader (Generic/Comptime Implementation)
//!
//! Handles loading .nes ROM files from the filesystem.
//! Works with generic Cartridge(MapperType) for compile-time dispatch.
//!
//! Currently uses synchronous std.fs API for simplicity.
//! Future enhancement: Integrate with libxev for async file I/O when event loop is active.

const std = @import("std");
const Cartridge = @import("Cartridge.zig").Cartridge;
const Mapper0 = @import("mappers/Mapper0.zig").Mapper0;

/// Maximum ROM file size (1MB - reasonable limit for NES ROMs)
const MAX_ROM_SIZE: usize = 1024 * 1024;

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
