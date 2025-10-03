//! NES Cartridge Abstraction
//!
//! Represents a loaded NES cartridge with ROM data, mapper, and metadata.
//! Provides access to cartridge memory for CPU and PPU.
//!
//! Key features:
//! - Single-threaded access from RT emulation loop
//! - Polymorphic mapper interface
//! - Owned ROM data with proper cleanup
//!
//! Note: No mutex needed - cartridge access is exclusively from
//! single-threaded RT loop (EmulationState.tick()). Future multi-threading
//! will use message passing, not shared mutable state.

const std = @import("std");
const ines = @import("ines.zig");
const MapperMod = @import("Mapper.zig");
const Mapper0 = @import("mappers/Mapper0.zig").Mapper0;

pub const InesHeader = ines.InesHeader;
pub const Mirroring = ines.Mirroring;
pub const Mapper = MapperMod.Mapper;

/// Cartridge errors
pub const CartridgeError = error{
    UnsupportedMapper,
    InvalidRomSize,
    TrainerNotSupported,
} || ines.InesError || std.mem.Allocator.Error;

/// NES Cartridge
/// Contains ROM data, mapper implementation, accessed from single-threaded RT loop
pub const Cartridge = struct {
    /// PRG ROM data (immutable after load)
    /// Size: header.prg_rom_size * 16KB
    prg_rom: []const u8,

    /// CHR data (ROM or RAM)
    /// - CHR ROM: Immutable tile data
    /// - CHR RAM: Mutable, used when header.chr_rom_size == 0
    /// Size: header.chr_rom_size * 8KB (or 8KB if CHR RAM)
    chr_data: []u8,

    /// iNES header metadata
    header: InesHeader,

    /// Mapper implementation (polymorphic)
    mapper: *Mapper,

    /// Nametable mirroring mode
    mirroring: Mirroring,

    /// Allocator for cleanup
    allocator: std.mem.Allocator,

    /// Mapper instance storage
    /// We store the actual mapper here to own its lifetime
    mapper_storage: union(enum) {
        mapper0: Mapper0,
        // Future mappers will be added here
    },

    /// Load cartridge from raw iNES file data
    /// Takes ownership of the data, caller should not free it
    pub fn loadFromData(allocator: std.mem.Allocator, data: []const u8) CartridgeError!*Cartridge {
        // Parse iNES header
        const header = try ines.InesHeader.parse(data);

        // Check for unsupported features
        if (header.hasTrainer()) {
            return CartridgeError.TrainerNotSupported;
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

        // Create cartridge
        const cart = try allocator.create(Cartridge);
        errdefer allocator.destroy(cart);

        // Initialize mapper based on mapper number
        const mapper_num = header.getMapperNumber();

        // Initialize cart with temporary values
        cart.* = Cartridge{
            .prg_rom = prg_rom,
            .chr_data = chr_data,
            .header = header,
            .mapper = undefined, // Set after mapper_storage
            .mirroring = header.getMirroring(),
            .allocator = allocator,
            .mapper_storage = undefined, // Set next
        };

        // Initialize mapper storage and pointer
        switch (mapper_num) {
            0 => {
                cart.mapper_storage = .{ .mapper0 = Mapper0.init() };
                cart.mapper = cart.mapper_storage.mapper0.getMapper();
            },
            else => return CartridgeError.UnsupportedMapper,
        }

        // Reset mapper to initial state
        cart.mapper.reset(cart);

        return cart;
    }

    /// Load cartridge from file path
    pub fn load(allocator: std.mem.Allocator, path: []const u8) !*Cartridge {
        const loader = @import("loader.zig");
        return try loader.loadCartridgeFile(allocator, path);
    }

    /// Clean up cartridge resources
    pub fn deinit(self: *Cartridge) void {
        self.allocator.free(self.prg_rom);
        self.allocator.free(self.chr_data);
        self.allocator.destroy(self);
    }

    /// Read from CPU address space ($4020-$FFFF)
    pub fn cpuRead(self: *const Cartridge, address: u16) u8 {
        return self.mapper.cpuRead(self, address);
    }

    /// Write to CPU address space ($4020-$FFFF)
    pub fn cpuWrite(self: *Cartridge, address: u16, value: u8) void {
        self.mapper.cpuWrite(self, address, value);
    }

    /// Read from PPU address space ($0000-$1FFF for CHR)
    pub fn ppuRead(self: *const Cartridge, address: u16) u8 {
        return self.mapper.ppuRead(self, address);
    }

    /// Write to PPU address space ($0000-$1FFF for CHR)
    /// Only valid for CHR RAM
    pub fn ppuWrite(self: *Cartridge, address: u16, value: u8) void {
        self.mapper.ppuWrite(self, address, value);
    }

    /// Reset cartridge to power-on state
    pub fn reset(self: *Cartridge) void {
        self.mapper.reset(self);
    }
};

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

    const cart = try Cartridge.loadFromData(testing.allocator, &rom_data);
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

    const cart = try Cartridge.loadFromData(testing.allocator, &rom_data);
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

    const cart = try Cartridge.loadFromData(testing.allocator, &rom_data);
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

    const cart = try Cartridge.loadFromData(testing.allocator, &rom_data);
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

    const cart = try Cartridge.loadFromData(testing.allocator, &rom_data);
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

    const result = Cartridge.loadFromData(testing.allocator, &rom_data);
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

    const result = Cartridge.loadFromData(testing.allocator, &rom_data);
    try testing.expectError(CartridgeError.TrainerNotSupported, result);
}
