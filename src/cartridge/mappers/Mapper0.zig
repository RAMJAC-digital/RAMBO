//! Mapper 0: NROM
//!
//! The simplest NES mapper with no bank switching capabilities.
//! See: https://www.nesdev.org/wiki/NROM
//!
//! PRG ROM: 16KB or 32KB at $8000-$FFFF
//! - 32KB: $8000-$BFFF (first 16KB), $C000-$FFFF (last 16KB)
//! - 16KB: $8000-$BFFF (ROM), $C000-$FFFF (mirror of $8000-$BFFF)
//!
//! CHR: 8KB ROM or RAM at PPU $0000-$1FFF
//! - No bank switching
//! - CHR RAM writes allowed if CHR ROM size is 0
//!
//! Mirroring: Fixed by solder pads (horizontal or vertical)
//!
//! Examples: Super Mario Bros., Donkey Kong, Ice Climber

const std = @import("std");
const MapperMod = @import("../Mapper.zig");
const Cartridge = @import("../Cartridge.zig").Cartridge;

const Mapper = MapperMod.Mapper;

/// Mapper 0 (NROM) implementation
/// Contains no state - all configuration is in the Cartridge
pub const Mapper0 = struct {
    /// Base mapper interface
    base: Mapper,

    /// Initialize Mapper 0
    /// Returns a Mapper interface pointing to the NROM vtable
    pub fn init() Mapper0 {
        return .{
            .base = .{
                .vtable = &vtable,
            },
        };
    }

    /// Get the base Mapper interface
    pub inline fn getMapper(self: *Mapper0) *Mapper {
        return &self.base;
    }

    // ========================================================================
    // Implementation Functions
    // ========================================================================

    fn cpuReadImpl(mapper_ptr: *Mapper, cart: *const Cartridge, address: u16) u8 {
        _ = mapper_ptr; // Mapper 0 has no state

        return switch (address) {
            // PRG ROM: $8000-$FFFF
            0x8000...0xFFFF => {
                const prg_size = cart.prg_rom.len;
                var offset: usize = undefined;

                if (prg_size > 16384) {
                    // 32KB ROM: Direct mapping
                    // $8000-$BFFF → ROM[0x0000-0x3FFF]
                    // $C000-$FFFF → ROM[0x4000-0x7FFF]
                    offset = @as(usize, address - 0x8000);
                } else {
                    // 16KB ROM: Mirrored
                    // $8000-$BFFF → ROM[0x0000-0x3FFF]
                    // $C000-$FFFF → ROM[0x0000-0x3FFF] (mirror)
                    offset = @as(usize, address & 0x3FFF);
                }

                return cart.prg_rom[offset];
            },

            // PRG RAM: $6000-$7FFF (if present)
            // Note: Most NROM games don't have PRG RAM
            // For now, return open bus (will be handled by Bus)
            else => 0xFF, // Open bus
        };
    }

    fn cpuWriteImpl(mapper_ptr: *Mapper, cart: *Cartridge, address: u16, value: u8) void {
        _ = mapper_ptr;
        _ = cart;
        _ = address;
        _ = value;

        // Mapper 0 has no writable registers
        // Writes to $8000-$FFFF are ignored (ROM is read-only)
        // PRG RAM writes (if present) would go here in the future
    }

    fn ppuReadImpl(mapper_ptr: *Mapper, cart: *const Cartridge, address: u16) u8 {
        _ = mapper_ptr;

        // CHR: $0000-$1FFF (8KB, no banking)
        const chr_addr = @as(usize, address & 0x1FFF);

        if (cart.chr_data.len > 0) {
            return cart.chr_data[chr_addr];
        }

        // No CHR data - return open bus
        return 0xFF;
    }

    fn ppuWriteImpl(mapper_ptr: *Mapper, cart: *Cartridge, address: u16, value: u8) void {
        _ = mapper_ptr;

        // CHR writes only valid for CHR RAM
        // If chr_data exists and is mutable, allow writes
        const chr_addr = @as(usize, address & 0x1FFF);

        if (cart.chr_data.len > 0 and chr_addr < cart.chr_data.len) {
            cart.chr_data[chr_addr] = value;
        }

        // Writes to CHR ROM are ignored
    }

    fn resetImpl(mapper_ptr: *Mapper, cart: *Cartridge) void {
        _ = mapper_ptr;
        _ = cart;

        // Mapper 0 has no state to reset
        // All behavior is determined by ROM size
    }

    // ========================================================================
    // VTable
    // ========================================================================

    const vtable = Mapper.VTable{
        .cpuRead = cpuReadImpl,
        .cpuWrite = cpuWriteImpl,
        .ppuRead = ppuReadImpl,
        .ppuWrite = ppuWriteImpl,
        .reset = resetImpl,
    };
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "Mapper0: 32KB PRG ROM mapping" {
    var mapper0 = Mapper0.init();
    const mapper_ptr = mapper0.getMapper();

    // Create fake 32KB PRG ROM
    var prg_rom = [_]u8{0} ** 32768;
    prg_rom[0x0000] = 0xAA; // $8000
    prg_rom[0x3FFF] = 0xBB; // $BFFF
    prg_rom[0x4000] = 0xCC; // $C000
    prg_rom[0x7FFF] = 0xDD; // $FFFF

    var chr_data = [_]u8{0} ** 8192;

    var cart = Cartridge{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = mapper_ptr,
        .header = undefined,
        .mirroring = .horizontal,
        .mutex = .{},
        .allocator = undefined,
        .mapper_storage = .{ .mapper0 = mapper0 },
    };

    // Test 32KB mapping
    try testing.expectEqual(@as(u8, 0xAA), mapper_ptr.cpuRead(&cart, 0x8000));
    try testing.expectEqual(@as(u8, 0xBB), mapper_ptr.cpuRead(&cart, 0xBFFF));
    try testing.expectEqual(@as(u8, 0xCC), mapper_ptr.cpuRead(&cart, 0xC000));
    try testing.expectEqual(@as(u8, 0xDD), mapper_ptr.cpuRead(&cart, 0xFFFF));
}

test "Mapper0: 16KB PRG ROM mirroring" {
    var mapper0 = Mapper0.init();
    const mapper_ptr = mapper0.getMapper();

    // Create fake 16KB PRG ROM
    var prg_rom = [_]u8{0} ** 16384;
    prg_rom[0x0000] = 0x11; // $8000
    prg_rom[0x3FFF] = 0x22; // $BFFF

    var chr_data = [_]u8{0} ** 8192;

    var cart = Cartridge{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = mapper_ptr,
        .header = undefined,
        .mirroring = .horizontal,
        .mutex = .{},
        .allocator = undefined,
        .mapper_storage = .{ .mapper0 = mapper0 },
    };

    // $8000-$BFFF: First 16KB
    try testing.expectEqual(@as(u8, 0x11), mapper_ptr.cpuRead(&cart, 0x8000));
    try testing.expectEqual(@as(u8, 0x22), mapper_ptr.cpuRead(&cart, 0xBFFF));

    // $C000-$FFFF: Mirrored 16KB
    try testing.expectEqual(@as(u8, 0x11), mapper_ptr.cpuRead(&cart, 0xC000));
    try testing.expectEqual(@as(u8, 0x22), mapper_ptr.cpuRead(&cart, 0xFFFF));
}

test "Mapper0: CHR ROM read" {
    var mapper0 = Mapper0.init();
    const mapper_ptr = mapper0.getMapper();

    var prg_rom = [_]u8{0} ** 16384;
    var chr_data = [_]u8{0} ** 8192;
    chr_data[0x0000] = 0x33;
    chr_data[0x0FFF] = 0x44;
    chr_data[0x1000] = 0x55;
    chr_data[0x1FFF] = 0x66;

    var cart = Cartridge{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = mapper_ptr,
        .header = undefined,
        .mirroring = .horizontal,
        .mutex = .{},
        .allocator = undefined,
        .mapper_storage = .{ .mapper0 = mapper0 },
    };

    try testing.expectEqual(@as(u8, 0x33), mapper_ptr.ppuRead(&cart, 0x0000));
    try testing.expectEqual(@as(u8, 0x44), mapper_ptr.ppuRead(&cart, 0x0FFF));
    try testing.expectEqual(@as(u8, 0x55), mapper_ptr.ppuRead(&cart, 0x1000));
    try testing.expectEqual(@as(u8, 0x66), mapper_ptr.ppuRead(&cart, 0x1FFF));
}

test "Mapper0: CHR RAM write" {
    var mapper0 = Mapper0.init();
    const mapper_ptr = mapper0.getMapper();

    var prg_rom = [_]u8{0} ** 16384;
    var chr_data = [_]u8{0} ** 8192;

    var cart = Cartridge{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = mapper_ptr,
        .header = undefined,
        .mirroring = .horizontal,
        .mutex = .{},
        .allocator = undefined,
        .mapper_storage = .{ .mapper0 = mapper0 },
    };

    // Write to CHR RAM
    mapper_ptr.ppuWrite(&cart, 0x0000, 0x77);
    mapper_ptr.ppuWrite(&cart, 0x1FFF, 0x88);

    // Verify writes
    try testing.expectEqual(@as(u8, 0x77), mapper_ptr.ppuRead(&cart, 0x0000));
    try testing.expectEqual(@as(u8, 0x88), mapper_ptr.ppuRead(&cart, 0x1FFF));
}

test "Mapper0: CPU writes ignored" {
    var mapper0 = Mapper0.init();
    const mapper_ptr = mapper0.getMapper();

    var prg_rom = [_]u8{0} ** 16384;
    prg_rom[0] = 0x99;

    var chr_data = [_]u8{0} ** 8192;

    var cart = Cartridge{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = mapper_ptr,
        .header = undefined,
        .mirroring = .horizontal,
        .mutex = .{},
        .allocator = undefined,
        .mapper_storage = .{ .mapper0 = mapper0 },
    };

    // Try to write to ROM (should be ignored)
    mapper_ptr.cpuWrite(&cart, 0x8000, 0xAA);

    // Value should remain unchanged
    try testing.expectEqual(@as(u8, 0x99), mapper_ptr.cpuRead(&cart, 0x8000));
}
