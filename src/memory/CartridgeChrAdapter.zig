//! Cartridge CHR Adapter (Duck-Typed, Comptime)
//!
//! This adapter allows PPU to access cartridge CHR ROM/RAM through a
//! duck-typed interface using comptime generics.
//!
//! No VTable, no runtime overhead - pure compile-time dispatch.
//!
//! Required Interface for CHR Providers (duck typing):
//! - read(self: *const Self, address: u16) u8
//! - write(self: *Self, address: u16, value: u8) void
//!
//! Usage:
//! ```zig
//! const adapter = CartridgeChrAdapter(Mapper0).init(&cartridge);
//! const ppu = Ppu(CartridgeChrAdapter(Mapper0)).init(adapter);
//! ```

const std = @import("std");

/// Creates a CHR adapter for a specific cartridge type
///
/// This is a type factory that generates an adapter for compile-time dispatch.
/// The adapter implements the duck-typed CHR provider interface expected by PPU.
pub fn CartridgeChrAdapter(comptime CartridgeType: type) type {
    return struct {
        const Self = @This();

        /// Non-owning pointer to cartridge
        cartridge: *CartridgeType,

        /// Initialize adapter with cartridge reference
        pub fn init(cartridge: *CartridgeType) Self {
            return .{ .cartridge = cartridge };
        }

        /// Read CHR data from cartridge
        ///
        /// Delegates to cartridge's ppuRead() method which dispatches
        /// through the mapper (already comptime-resolved).
        pub fn read(self: *const Self, address: u16) u8 {
            return self.cartridge.ppuRead(address);
        }

        /// Write CHR data to cartridge
        ///
        /// Only effective for CHR-RAM. CHR-ROM writes are ignored
        /// (handled by mapper implementation).
        pub fn write(self: *Self, address: u16, value: u8) void {
            self.cartridge.ppuWrite(address, value);
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;
const Cartridge = @import("../cartridge/Cartridge.zig").Cartridge;
const Mapper0 = @import("../cartridge/mappers/Mapper0.zig").Mapper0;

test "CartridgeChrAdapter: duck-typed interface" {
    // Create test cartridge
    var rom_data = [_]u8{0} ** (16 + 16384);
    rom_data[0] = 'N';
    rom_data[1] = 'E';
    rom_data[2] = 'S';
    rom_data[3] = 0x1A;
    rom_data[4] = 1; // 1x16KB PRG
    rom_data[5] = 0; // CHR RAM
    rom_data[6] = 0;
    rom_data[7] = 0;

    const CartType = Cartridge(Mapper0);
    var cart = try CartType.loadFromData(testing.allocator, &rom_data);
    defer cart.deinit();

    // Create adapter
    const AdapterType = CartridgeChrAdapter(CartType);
    var adapter = AdapterType.init(&cart);

    // Test write (CHR RAM)
    adapter.write(0x0000, 0x42);
    adapter.write(0x1FFF, 0x99);

    // Test read
    try testing.expectEqual(@as(u8, 0x42), adapter.read(0x0000));
    try testing.expectEqual(@as(u8, 0x99), adapter.read(0x1FFF));
}

test "CartridgeChrAdapter: CHR ROM read" {
    // Create test cartridge with CHR ROM
    var rom_data = [_]u8{0} ** (16 + 16384 + 8192);
    rom_data[0] = 'N';
    rom_data[1] = 'E';
    rom_data[2] = 'S';
    rom_data[3] = 0x1A;
    rom_data[4] = 1; // 1x16KB PRG
    rom_data[5] = 1; // 1x8KB CHR ROM
    rom_data[6] = 0;
    rom_data[7] = 0;

    // Put test data in CHR ROM
    const chr_start = 16 + 16384;
    rom_data[chr_start + 0x0000] = 0xAA;
    rom_data[chr_start + 0x1FFF] = 0xBB;

    const CartType = Cartridge(Mapper0);
    var cart = try CartType.loadFromData(testing.allocator, &rom_data);
    defer cart.deinit();

    // Create adapter
    const AdapterType = CartridgeChrAdapter(CartType);
    const adapter = AdapterType.init(&cart);

    // Test read
    try testing.expectEqual(@as(u8, 0xAA), adapter.read(0x0000));
    try testing.expectEqual(@as(u8, 0xBB), adapter.read(0x1FFF));
}

test "CartridgeChrAdapter: comptime type validation" {
    // Validates that adapter works with any Cartridge(T)
    const CartType = Cartridge(Mapper0);
    const AdapterType = CartridgeChrAdapter(CartType);

    // Verify adapter implements required methods
    const has_read = @hasDecl(AdapterType, "read");
    const has_write = @hasDecl(AdapterType, "write");

    try testing.expect(has_read);
    try testing.expect(has_write);
}
