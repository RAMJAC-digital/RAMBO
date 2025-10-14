//! NES Cartridge Abstraction (Generic/Comptime Implementation)
//!
//! Represents a loaded NES cartridge with ROM data, mapper, and metadata.
//! Now uses comptime generics for zero-cost mapper polymorphism.
//!
//! Key features:
//! - Generic Cartridge(MapperType) for compile-time dispatch
//! - Duck-typed mapper interface (no VTable overhead)
//! - Single-threaded access from RT emulation loop
//! - Owned ROM data with proper cleanup
//!
//! Usage:
//! ```zig
//! const CartType = Cartridge(Mapper0);
//! const cart = try CartType.loadFromData(allocator, rom_data);
//! defer cart.deinit(allocator);
//! const value = cart.cpuRead(0x8000);
//! ```
//!
//! Note: No mutex needed - cartridge access is exclusively from
//! single-threaded RT loop (EmulationState.tick()). Future multi-threading
//! will use message passing, not shared mutable state.

const std = @import("std");
const ines = @import("ines/mod.zig");
const Mapper0 = @import("mappers/Mapper0.zig").Mapper0;

pub const InesHeader = ines.InesHeader;
pub const Mirroring = ines.MirroringMode;

/// Cartridge errors
pub const CartridgeError = error{
    UnsupportedMapper,
    InvalidRomSize,
    TrainerNotSupported,
} || ines.InesError || std.mem.Allocator.Error;

/// Generic NES Cartridge
///
/// Type factory parameterized by mapper implementation.
/// Each Cartridge(MapperType) is a distinct type with zero-cost dispatch.
///
/// Required Mapper Interface (duck typing):
/// - cpuRead(self: *const MapperType, cart: anytype, address: u16) u8
/// - cpuWrite(self: *MapperType, cart: anytype, address: u16, value: u8) void
/// - ppuRead(self: *const MapperType, cart: anytype, address: u16) u8
/// - ppuWrite(self: *MapperType, cart: anytype, address: u16, value: u8) void
/// - reset(self: *MapperType, cart: anytype) void
/// - tickIrq(self: *MapperType) bool  (return false if no IRQ support)
/// - ppuA12Rising(self: *MapperType) void  (no-op if not used)
/// - acknowledgeIrq(self: *MapperType) void  (no-op if no IRQ support)
pub fn Cartridge(comptime MapperType: type) type {
    return struct {
        const Self = @This();

        /// Mapper instance (concrete type, no indirection)
        mapper: MapperType,

        /// PRG ROM data (immutable after load)
        /// Size: header.prg_rom_size * 16KB
        prg_rom: []const u8,

        /// CHR data (ROM or RAM)
        /// - CHR ROM: Immutable tile data
        /// - CHR RAM: Mutable, used when header.chr_rom_size == 0
        /// Size: header.chr_rom_size * 8KB (or 8KB if CHR RAM)
        chr_data: []u8,

        /// PRG RAM data (battery-backed or work RAM at $6000-$7FFF)
        /// Size: Always 8KB for Mapper 0 (industry standard)
        /// Note: AccuracyCoin and other test ROMs require this even if
        /// the iNES header indicates 0 PRG RAM size
        prg_ram: ?[]u8,

        /// iNES header metadata
        header: InesHeader,

        /// Nametable mirroring mode
        mirroring: Mirroring,

        /// Allocator for cleanup
        allocator: std.mem.Allocator,

        /// Load cartridge from raw iNES file data
        /// Takes ownership of the data, caller should not free it
        pub fn loadFromData(allocator: std.mem.Allocator, data: []const u8) CartridgeError!Self {
            // Parse iNES header
            const header = try ines.parseHeader(data);

            // Check for unsupported features
            if (header.hasTrainer()) {
                return CartridgeError.TrainerNotSupported;
            }

            // Verify mapper matches expected type
            const mapper_num = header.getMapperNumber();

            // Validate mapper number matches MapperType
            // This is a compile-time validation - MapperType must match ROM
            const expected_mapper = comptime blk: {
                if (MapperType == Mapper0) break :blk 0;
                if (MapperType == @import("mappers/Mapper1.zig").Mapper1) break :blk 1;
                if (MapperType == @import("mappers/Mapper2.zig").Mapper2) break :blk 2;
                if (MapperType == @import("mappers/Mapper3.zig").Mapper3) break :blk 3;
                if (MapperType == @import("mappers/Mapper4.zig").Mapper4) break :blk 4;
                if (MapperType == @import("mappers/Mapper7.zig").Mapper7) break :blk 7;
                @compileError("Unknown mapper type");
            };

            if (mapper_num != expected_mapper) {
                return CartridgeError.UnsupportedMapper;
            }

            // Calculate ROM sizes
            const prg_rom_size = header.getPrgRomSize();
            const chr_size = header.getChrRomSize();

            // Validate file size
            const expected_size = 16 + prg_rom_size + chr_size;
            if (data.len < expected_size) {
                return CartridgeError.InvalidRomSize;
            }

            // Extract PRG ROM (starts at byte 16)
            const prg_start: usize = 16;
            const prg_rom = try allocator.dupe(u8, data[prg_start .. prg_start + prg_rom_size]);
            errdefer allocator.free(prg_rom);

            // Extract or allocate CHR data
            const chr_data = blk: {
                if (chr_size > 0) {
                    // CHR ROM: Copy from file
                    const chr_start = prg_start + prg_rom_size;
                    break :blk try allocator.dupe(u8, data[chr_start .. chr_start + chr_size]);
                } else {
                    // CHR RAM: Allocate 8KB of RAM
                    const chr_ram = try allocator.alloc(u8, 8192);
                    @memset(chr_ram, 0);
                    break :blk chr_ram;
                }
            };
            errdefer allocator.free(chr_data);

            // Allocate PRG RAM (8KB - industry standard for Mapper 0)
            // Note: Always allocate for Mapper 0, even if iNES header indicates 0 bytes
            // Many test ROMs (like AccuracyCoin) require PRG RAM but have header.prg_ram_size = 0
            const prg_ram = blk: {
                const ram = try allocator.alloc(u8, 8192);
                @memset(ram, 0);
                break :blk ram;
            };
            errdefer allocator.free(prg_ram);

            // Create cartridge with mapper instance
            var cart = Self{
                .mapper = MapperType{}, // Default init - mappers can add init() if needed
                .prg_rom = prg_rom,
                .chr_data = chr_data,
                .prg_ram = prg_ram,
                .header = header,
                .mirroring = header.getMirroring(),
                .allocator = allocator,
            };

            // Reset mapper to initial state
            cart.mapper.reset(&cart);

            return cart;
        }

        /// Load cartridge from file path
        pub fn load(allocator: std.mem.Allocator, path: []const u8) !Self {
            const loader = @import("loader.zig");
            return try loader.loadCartridgeFile(allocator, path, MapperType);
        }

        /// Clean up cartridge resources
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.prg_rom);
            self.allocator.free(self.chr_data);
            if (self.prg_ram) |ram| {
                self.allocator.free(ram);
            }
        }

        /// Read from CPU address space ($4020-$FFFF)
        ///
        /// Dispatches through mapper - compiler knows exact type, can inline
        pub fn cpuRead(self: *const Self, address: u16) u8 {
            return self.mapper.cpuRead(self, address);
        }

        /// Write to CPU address space ($4020-$FFFF)
        pub fn cpuWrite(self: *Self, address: u16, value: u8) void {
            self.mapper.cpuWrite(self, address, value);
        }

        /// Read from PPU address space ($0000-$1FFF for CHR)
        pub fn ppuRead(self: *const Self, address: u16) u8 {
            return self.mapper.ppuRead(self, address);
        }

        /// Write to PPU address space ($0000-$1FFF for CHR)
        /// Only valid for CHR RAM
        pub fn ppuWrite(self: *Self, address: u16, value: u8) void {
            self.mapper.ppuWrite(self, address, value);
        }

        /// Reset cartridge to power-on state
        pub fn reset(self: *Self) void {
            self.mapper.reset(self);
        }
    };
}

// ============================================================================
// Type Aliases for Common Configurations
// ============================================================================

/// NROM cartridge (Mapper 0)
/// Common configuration for simple games
pub const NromCart = Cartridge(Mapper0);

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "Cartridge: load NROM-256 ROM" {
    // Create a minimal valid iNES file
    var rom_data = [_]u8{0} ** (16 + 32768 + 8192);

    // iNES header
    rom_data[0] = 'N';
    rom_data[1] = 'E';
    rom_data[2] = 'S';
    rom_data[3] = 0x1A;
    rom_data[4] = 2; // 2 x 16KB PRG ROM (32KB)
    rom_data[5] = 1; // 1 x 8KB CHR ROM
    rom_data[6] = 0; // Mapper 0, horizontal mirroring
    rom_data[7] = 0; // Mapper 0

    // Some test data in PRG ROM
    rom_data[16] = 0xAA; // First byte of PRG ROM

    const CartType = Cartridge(Mapper0);
    var cart = try CartType.loadFromData(testing.allocator, &rom_data);
    defer cart.deinit();

    try testing.expectEqual(@as(usize, 32768), cart.prg_rom.len);
    try testing.expectEqual(@as(usize, 8192), cart.chr_data.len);
    try testing.expectEqual(@as(u8, 0xAA), cart.prg_rom[0]);
    try testing.expectEqual(@as(u8, 0), cart.header.getMapperNumber());
    try testing.expectEqual(Mirroring.horizontal, cart.mirroring);
}

test "Cartridge: load NROM-128 ROM" {
    // Create a minimal valid iNES file with 16KB PRG ROM
    var rom_data = [_]u8{0} ** (16 + 16384 + 8192);

    // iNES header
    rom_data[0] = 'N';
    rom_data[1] = 'E';
    rom_data[2] = 'S';
    rom_data[3] = 0x1A;
    rom_data[4] = 1; // 1 x 16KB PRG ROM
    rom_data[5] = 1; // 1 x 8KB CHR ROM
    rom_data[6] = 0x01; // Mapper 0, vertical mirroring
    rom_data[7] = 0x00;

    const CartType = Cartridge(Mapper0);
    var cart = try CartType.loadFromData(testing.allocator, &rom_data);
    defer cart.deinit();

    try testing.expectEqual(@as(usize, 16384), cart.prg_rom.len);
    try testing.expectEqual(Mirroring.vertical, cart.mirroring);
}

test "Cartridge: CHR RAM allocation" {
    // Create ROM with CHR RAM (chr_rom_size = 0)
    var rom_data = [_]u8{0} ** (16 + 16384);

    // iNES header
    rom_data[0] = 'N';
    rom_data[1] = 'E';
    rom_data[2] = 'S';
    rom_data[3] = 0x1A;
    rom_data[4] = 1; // 1 x 16KB PRG ROM
    rom_data[5] = 0; // CHR RAM (not ROM)
    rom_data[6] = 0;
    rom_data[7] = 0;

    const CartType = Cartridge(Mapper0);
    var cart = try CartType.loadFromData(testing.allocator, &rom_data);
    defer cart.deinit();

    // CHR RAM should be allocated (8KB)
    try testing.expectEqual(@as(usize, 8192), cart.chr_data.len);

    // CHR RAM should be zeroed
    try testing.expectEqual(@as(u8, 0), cart.chr_data[0]);
    try testing.expectEqual(@as(u8, 0), cart.chr_data[8191]);
}

test "Cartridge: CPU read through mapper" {
    var rom_data = [_]u8{0} ** (16 + 16384 + 8192);

    // iNES header
    rom_data[0] = 'N';
    rom_data[1] = 'E';
    rom_data[2] = 'S';
    rom_data[3] = 0x1A;
    rom_data[4] = 1; // 1 x 16KB PRG ROM
    rom_data[5] = 1; // 1 x 8KB CHR ROM
    rom_data[6] = 0;
    rom_data[7] = 0;

    // Test data in PRG ROM
    rom_data[16] = 0x42; // $8000

    const CartType = Cartridge(Mapper0);
    var cart = try CartType.loadFromData(testing.allocator, &rom_data);
    defer cart.deinit();

    // Read from $8000 through cartridge interface
    const value = cart.cpuRead(0x8000);
    try testing.expectEqual(@as(u8, 0x42), value);
}

test "Cartridge: PPU read/write through mapper" {
    var rom_data = [_]u8{0} ** (16 + 16384);

    // iNES header (CHR RAM)
    rom_data[0] = 'N';
    rom_data[1] = 'E';
    rom_data[2] = 'S';
    rom_data[3] = 0x1A;
    rom_data[4] = 1;
    rom_data[5] = 0; // CHR RAM
    rom_data[6] = 0;
    rom_data[7] = 0;

    const CartType = Cartridge(Mapper0);
    var cart = try CartType.loadFromData(testing.allocator, &rom_data);
    defer cart.deinit();

    // Write to CHR RAM
    cart.ppuWrite(0x0000, 0x99);

    // Read back
    const value = cart.ppuRead(0x0000);
    try testing.expectEqual(@as(u8, 0x99), value);
}

test "Cartridge: unsupported mapper" {
    var rom_data = [_]u8{0} ** (16 + 16384 + 8192);

    // iNES header with unsupported mapper
    rom_data[0] = 'N';
    rom_data[1] = 'E';
    rom_data[2] = 'S';
    rom_data[3] = 0x1A;
    rom_data[4] = 1;
    rom_data[5] = 1;
    rom_data[6] = 0x10; // Mapper 1 (not implemented yet)
    rom_data[7] = 0x00;

    const CartType = Cartridge(Mapper0);
    const result = CartType.loadFromData(testing.allocator, &rom_data);
    try testing.expectError(CartridgeError.UnsupportedMapper, result);
}

test "Cartridge: trainer not supported" {
    var rom_data = [_]u8{0} ** (16 + 512 + 16384 + 8192);

    // iNES header with trainer
    rom_data[0] = 'N';
    rom_data[1] = 'E';
    rom_data[2] = 'S';
    rom_data[3] = 0x1A;
    rom_data[4] = 1;
    rom_data[5] = 1;
    rom_data[6] = 0x04; // Trainer present
    rom_data[7] = 0x00;

    const CartType = Cartridge(Mapper0);
    const result = CartType.loadFromData(testing.allocator, &rom_data);
    try testing.expectError(CartridgeError.TrainerNotSupported, result);
}

test "Cartridge: generic type factory" {
    // Demonstrates that Cartridge(T) is a type factory
    const Cart1 = Cartridge(Mapper0);
    const Cart2 = Cartridge(Mapper0);

    // Same mapper = same type
    try testing.expect(Cart1 == Cart2);

    // Each cartridge instance has its own mapper instance
    var rom_data = [_]u8{0} ** (16 + 16384 + 8192);
    rom_data[0] = 'N';
    rom_data[1] = 'E';
    rom_data[2] = 'S';
    rom_data[3] = 0x1A;
    rom_data[4] = 1;
    rom_data[5] = 1;
    rom_data[6] = 0;
    rom_data[7] = 0;

    var cart1 = try Cart1.loadFromData(testing.allocator, &rom_data);
    defer cart1.deinit();

    var cart2 = try Cart2.loadFromData(testing.allocator, &rom_data);
    defer cart2.deinit();

    // cart1 and cart2 are different instances
    try testing.expect(&cart1 != &cart2);
}

test "Cartridge: type alias - NromCart" {
    // Validates that NromCart alias works correctly
    var rom_data = [_]u8{0} ** (16 + 16384 + 8192);
    rom_data[0] = 'N';
    rom_data[1] = 'E';
    rom_data[2] = 'S';
    rom_data[3] = 0x1A;
    rom_data[4] = 1;
    rom_data[5] = 1;
    rom_data[6] = 0;
    rom_data[7] = 0;

    var cart = try NromCart.loadFromData(testing.allocator, &rom_data);
    defer cart.deinit();

    // Should have Mapper0
    try testing.expect(@TypeOf(cart.mapper) == Mapper0);
}
