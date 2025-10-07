//! Mapper 0: NROM (Comptime Generic Implementation)
//!
//! The simplest NES mapper with no bank switching capabilities.
//! See: https://www.nesdev.org/wiki/NROM
//!
//! This is a duck-typed mapper implementation using comptime generics.
//! No VTable, no runtime overhead - all dispatch is compile-time.
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

/// Mapper 0 (NROM) - Duck-Typed Implementation
///
/// Required Interface (for use with generic Cartridge):
/// - cpuRead(self: *const Mapper0, cart: anytype, address: u16) u8
/// - cpuWrite(self: *Mapper0, cart: anytype, address: u16, value: u8) void
/// - ppuRead(self: *const Mapper0, cart: anytype, address: u16) u8
/// - ppuWrite(self: *Mapper0, cart: anytype, address: u16, value: u8) void
/// - reset(self: *Mapper0, cart: anytype) void
///
/// Mapper 0 has no state - all behavior determined by cartridge ROM size.
pub const Mapper0 = struct {
    // No state needed for Mapper 0
    // Future mappers (MMC1, MMC3) would have state fields here

    /// CPU read from cartridge address space ($6000-$FFFF)
    ///
    /// Parameters use duck typing:
    /// - self: Mapper instance (unused for NROM)
    /// - cart: anytype - must have .prg_rom and .prg_ram fields
    /// - address: CPU address
    ///
    /// Returns: Byte from PRG RAM/ROM, or 0xFF for unmapped regions
    pub fn cpuRead(_: *const Mapper0, cart: anytype, address: u16) u8 {
        return switch (address) {
            // PRG RAM: $6000-$7FFF (8KB if present)
            0x6000...0x7FFF => {
                if (cart.prg_ram) |ram| {
                    const offset = @as(usize, address - 0x6000);
                    return ram[offset];
                }
                return 0xFF; // No PRG RAM - open bus
            },

            // PRG ROM: $8000-$FFFF
            0x8000...0xFFFF => {
                const prg_size = cart.prg_rom.len;
                const offset: usize = if (prg_size > 16384)
                    // 32KB ROM: Direct mapping
                    // $8000-$BFFF → ROM[0x0000-0x3FFF]
                    // $C000-$FFFF → ROM[0x4000-0x7FFF]
                    @as(usize, address - 0x8000)
                else
                    // 16KB ROM: Mirrored
                    // $8000-$BFFF → ROM[0x0000-0x3FFF]
                    // $C000-$FFFF → ROM[0x0000-0x3FFF] (mirror)
                    @as(usize, address & 0x3FFF);

                return cart.prg_rom[offset];
            },

            // Unmapped regions
            else => 0xFF,
        };
    }

    /// CPU write to cartridge space ($6000-$FFFF)
    ///
    /// - PRG RAM ($6000-$7FFF): Writable if present
    /// - PRG ROM ($8000-$FFFF): Read-only, writes ignored
    pub fn cpuWrite(_: *Mapper0, cart: anytype, address: u16, value: u8) void {
        switch (address) {
            // PRG RAM: $6000-$7FFF (8KB if present)
            0x6000...0x7FFF => {
                if (cart.prg_ram) |ram| {
                    const offset = @as(usize, address - 0x6000);
                    ram[offset] = value;
                }
                // No PRG RAM - write ignored
            },

            // PRG ROM: $8000-$FFFF (read-only)
            0x8000...0xFFFF => {
                // Mapper 0 has no writable registers
                // Writes to ROM are ignored
            },

            // Other addresses - ignored
            else => {},
        }
    }

    /// PPU read from CHR space ($0000-$1FFF)
    ///
    /// Parameters:
    /// - cart: anytype - must have .chr_data field
    /// - address: PPU address
    ///
    /// Returns: Byte from CHR ROM/RAM
    pub fn ppuRead(_: *const Mapper0, cart: anytype, address: u16) u8 {
        // CHR: $0000-$1FFF (8KB, no banking)
        const chr_addr = @as(usize, address & 0x1FFF);

        if (cart.chr_data.len > 0) {
            return cart.chr_data[chr_addr];
        }

        // No CHR data - return open bus
        return 0xFF;
    }

    /// PPU write to CHR space ($0000-$1FFF)
    ///
    /// Only valid for CHR RAM (when header.chr_rom_size == 0).
    /// Writes to CHR ROM are silently ignored (correct NES behavior).
    pub fn ppuWrite(_: *Mapper0, cart: anytype, address: u16, value: u8) void {
        // CHR writes only valid for CHR RAM
        const chr_addr = @as(usize, address & 0x1FFF);

        // Only allow writes if this is CHR RAM
        // (Cartridge determines this based on header.chr_rom_size)
        if (cart.header.chr_rom_size == 0 and chr_addr < cart.chr_data.len) {
            cart.chr_data[chr_addr] = value;
        }

        // Writes to CHR ROM are silently ignored (correct NES behavior)
    }

    /// Reset mapper to power-on state
    ///
    /// Mapper 0 has no state, so reset is a no-op.
    /// More complex mappers would reset registers here.
    pub fn reset(_: *Mapper0, _: anytype) void {
        // Mapper 0 has no state to reset
        // All behavior is determined by ROM size
    }

    // ========================================================================
    // IRQ Interface (NROM doesn't support IRQ - all stubs)
    // ========================================================================

    /// Poll for IRQ assertion
    ///
    /// NROM has no IRQ support - always returns false.
    /// Called every CPU cycle by EmulationState.tick()
    pub fn tickIrq(_: *Mapper0) bool {
        return false; // NROM never asserts IRQ
    }

    /// Notify of PPU A12 rising edge
    ///
    /// NROM doesn't use PPU A12 - this is a no-op.
    /// MMC3 would decrement its IRQ counter here.
    pub fn ppuA12Rising(_: *Mapper0) void {
        // NROM ignores PPU A12 edges
    }

    /// Acknowledge IRQ (clear pending flag)
    ///
    /// NROM has no IRQ to acknowledge - this is a no-op.
    /// Called when CPU reads interrupt vector ($FFFE).
    pub fn acknowledgeIrq(_: *Mapper0) void {
        // NROM has no IRQ state to clear
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

// Test helper: Minimal cartridge-like struct for testing
const TestCart = struct {
    prg_rom: []const u8,
    chr_data: []u8,
    prg_ram: ?[]u8 = null,
    header: struct {
        chr_rom_size: u8,
    },
};

test "Mapper0: 32KB PRG ROM mapping" {
    const mapper = Mapper0{};

    // Create fake 32KB PRG ROM
    var prg_rom = [_]u8{0} ** 32768;
    prg_rom[0x0000] = 0xAA; // $8000
    prg_rom[0x3FFF] = 0xBB; // $BFFF
    prg_rom[0x4000] = 0xCC; // $C000
    prg_rom[0x7FFF] = 0xDD; // $FFFF

    var chr_data = [_]u8{0} ** 8192;

    const cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .header = .{ .chr_rom_size = 1 },
    };

    // Test 32KB mapping
    try testing.expectEqual(@as(u8, 0xAA), mapper.cpuRead(&cart, 0x8000));
    try testing.expectEqual(@as(u8, 0xBB), mapper.cpuRead(&cart, 0xBFFF));
    try testing.expectEqual(@as(u8, 0xCC), mapper.cpuRead(&cart, 0xC000));
    try testing.expectEqual(@as(u8, 0xDD), mapper.cpuRead(&cart, 0xFFFF));
}

test "Mapper0: 16KB PRG ROM mirroring" {
    const mapper = Mapper0{};

    // Create fake 16KB PRG ROM
    var prg_rom = [_]u8{0} ** 16384;
    prg_rom[0x0000] = 0x11; // $8000
    prg_rom[0x3FFF] = 0x22; // $BFFF

    var chr_data = [_]u8{0} ** 8192;

    const cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .header = .{ .chr_rom_size = 1 },
    };

    // $8000-$BFFF: First 16KB
    try testing.expectEqual(@as(u8, 0x11), mapper.cpuRead(&cart, 0x8000));
    try testing.expectEqual(@as(u8, 0x22), mapper.cpuRead(&cart, 0xBFFF));

    // $C000-$FFFF: Mirrored 16KB
    try testing.expectEqual(@as(u8, 0x11), mapper.cpuRead(&cart, 0xC000));
    try testing.expectEqual(@as(u8, 0x22), mapper.cpuRead(&cart, 0xFFFF));
}

test "Mapper0: CHR ROM read" {
    const mapper = Mapper0{};

    var prg_rom = [_]u8{0} ** 16384;
    var chr_data = [_]u8{0} ** 8192;
    chr_data[0x0000] = 0x33;
    chr_data[0x0FFF] = 0x44;
    chr_data[0x1000] = 0x55;
    chr_data[0x1FFF] = 0x66;

    const cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .header = .{ .chr_rom_size = 1 },
    };

    try testing.expectEqual(@as(u8, 0x33), mapper.ppuRead(&cart, 0x0000));
    try testing.expectEqual(@as(u8, 0x44), mapper.ppuRead(&cart, 0x0FFF));
    try testing.expectEqual(@as(u8, 0x55), mapper.ppuRead(&cart, 0x1000));
    try testing.expectEqual(@as(u8, 0x66), mapper.ppuRead(&cart, 0x1FFF));
}

test "Mapper0: CHR RAM write" {
    var mapper = Mapper0{};

    var prg_rom = [_]u8{0} ** 16384;
    var chr_data = [_]u8{0} ** 8192;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .header = .{ .chr_rom_size = 0 }, // CHR RAM
    };

    // Write to CHR RAM
    mapper.ppuWrite(&cart, 0x0000, 0x77);
    mapper.ppuWrite(&cart, 0x1FFF, 0x88);

    // Verify writes
    try testing.expectEqual(@as(u8, 0x77), mapper.ppuRead(&cart, 0x0000));
    try testing.expectEqual(@as(u8, 0x88), mapper.ppuRead(&cart, 0x1FFF));
}

test "Mapper0: CHR ROM write ignored" {
    var mapper = Mapper0{};

    var prg_rom = [_]u8{0} ** 16384;
    var chr_data = [_]u8{0x99} ** 8192; // Pre-filled with 0x99

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .header = .{ .chr_rom_size = 1 }, // CHR ROM (not RAM)
    };

    // Try to write to CHR ROM (should be ignored)
    mapper.ppuWrite(&cart, 0x0000, 0x42);

    // Value should remain unchanged
    try testing.expectEqual(@as(u8, 0x99), mapper.ppuRead(&cart, 0x0000));
}

test "Mapper0: CPU writes ignored" {
    var mapper = Mapper0{};

    var prg_rom = [_]u8{0} ** 16384;
    prg_rom[0] = 0x99;

    var chr_data = [_]u8{0} ** 8192;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .header = .{ .chr_rom_size = 1 },
    };

    // Try to write to ROM (should be ignored)
    mapper.cpuWrite(&cart, 0x8000, 0xAA);

    // Value should remain unchanged
    try testing.expectEqual(@as(u8, 0x99), mapper.cpuRead(&cart, 0x8000));
}

test "Mapper0: reset is no-op" {
    var mapper = Mapper0{};

    var prg_rom = [_]u8{0} ** 16384;
    var chr_data = [_]u8{0} ** 8192;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .header = .{ .chr_rom_size = 1 },
    };

    // Reset should not crash (Mapper0 has no state)
    mapper.reset(&cart);
}

test "Mapper0: duck typing - no Cartridge import needed" {
    // This test validates that Mapper0 doesn't import Cartridge
    // It uses anytype, enabling structural duck typing

    const mapper = Mapper0{};

    // Custom struct that looks like a cartridge
    const CustomCart = struct {
        prg_rom: []const u8,
        chr_data: []u8,
        prg_ram: ?[]u8 = null,
        header: struct { chr_rom_size: u8 },
    };

    var prg_rom = [_]u8{0x42} ** 16384;
    var chr_data = [_]u8{0} ** 8192;

    const cart = CustomCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .prg_ram = null,
        .header = .{ .chr_rom_size = 1 },
    };

    // Works with any struct that has the required fields!
    try testing.expectEqual(@as(u8, 0x42), mapper.cpuRead(&cart, 0x8000));
}
