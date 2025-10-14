//! Mapper 3: CNROM (Comptime Generic Implementation)
//!
//! Simple CHR-ROM banking mapper with fixed PRG-ROM.
//! See: https://www.nesdev.org/wiki/CNROM
//!
//! This is a duck-typed mapper implementation using comptime generics.
//! No VTable, no runtime overhead - all dispatch is compile-time.
//!
//! PRG ROM: 16KB or 32KB at $8000-$FFFF (no banking)
//! - 32KB: $8000-$BFFF (first 16KB), $C000-$FFFF (last 16KB)
//! - 16KB: $8000-$BFFF (ROM), $C000-$FFFF (mirror of $8000-$BFFF)
//!
//! CHR: Up to 32KB ROM at PPU $0000-$1FFF
//! - 8KB banks switchable (up to 4 banks)
//! - Bank selection via CPU writes to $8000-$FFFF
//!
//! Mirroring: Fixed by solder pads (horizontal or vertical)
//!
//! Examples: Arkanoid, Gradius, Donkey Kong 3

const std = @import("std");

/// Mapper 3 (CNROM) - Duck-Typed Implementation
///
/// Required Interface (for use with generic Cartridge):
/// - cpuRead(self: *const Mapper3, cart: anytype, address: u16) u8
/// - cpuWrite(self: *Mapper3, cart: anytype, address: u16, value: u8) void
/// - ppuRead(self: *const Mapper3, cart: anytype, address: u16) u8
/// - ppuWrite(self: *Mapper3, cart: anytype, address: u16, value: u8) void
/// - reset(self: *Mapper3, cart: anytype) void
///
/// Mapper 3 has minimal state - only CHR bank select register.
pub const Mapper3 = struct {
    /// CHR bank select register (2 bits for up to 4 banks)
    /// Updated by any CPU write to $8000-$FFFF
    chr_bank: u2 = 0,

    /// CPU read from cartridge address space ($6000-$FFFF)
    ///
    /// Parameters use duck typing:
    /// - self: Mapper instance
    /// - cart: anytype - must have .prg_rom field
    /// - address: CPU address
    ///
    /// Returns: Byte from PRG ROM, or 0xFF for unmapped regions
    pub fn cpuRead(_: *const Mapper3, cart: anytype, address: u16) u8 {
        return switch (address) {
            // PRG RAM: $6000-$7FFF (not supported by CNROM)
            0x6000...0x7FFF => 0xFF, // Open bus

            // PRG ROM: $8000-$FFFF (no banking, fixed)
            0x8000...0xFFFF => {
                const prg_size = cart.prg_rom.len;
                const offset: usize = if (prg_size > 16384)
                    // 32KB ROM: Direct mapping
                    @as(usize, address - 0x8000)
                else
                    // 16KB ROM: Mirrored
                    @as(usize, address & 0x3FFF);

                return cart.prg_rom[offset];
            },

            // Unmapped regions
            else => 0xFF,
        };
    }

    /// CPU write to cartridge space ($6000-$FFFF)
    ///
    /// - $6000-$7FFF: Not supported (CNROM has no PRG RAM)
    /// - $8000-$FFFF: CHR bank select (bits 0-1)
    ///
    /// Note: CNROM is subject to bus conflicts. The actual hardware reads
    /// the ROM value during write. For compatibility, we implement the write
    /// regardless, but games should write values that match ROM contents.
    pub fn cpuWrite(self: *Mapper3, _: anytype, address: u16, value: u8) void {
        switch (address) {
            // PRG RAM: Not supported by CNROM
            0x6000...0x7FFF => {
                // Writes ignored (no PRG RAM)
            },

            // CHR Bank Select: $8000-$FFFF
            0x8000...0xFFFF => {
                // Update CHR bank register (bits 0-1)
                // Note: Some CNROM boards use only bit 0-1, others may use more bits
                // We support up to 4 banks (2 bits) which covers standard CNROM
                self.chr_bank = @truncate(value & 0x03);
            },

            // Other addresses - ignored
            else => {},
        }
    }

    /// PPU read from CHR space ($0000-$1FFF)
    ///
    /// CHR is banked in 8KB chunks. Bank select register determines which
    /// 8KB bank of CHR ROM is visible at PPU $0000-$1FFF.
    ///
    /// Parameters:
    /// - cart: anytype - must have .chr_data field
    /// - address: PPU address
    ///
    /// Returns: Byte from selected CHR ROM bank
    pub fn ppuRead(self: *const Mapper3, cart: anytype, address: u16) u8 {
        // CHR: $0000-$1FFF (8KB banks)
        const chr_addr = @as(usize, address & 0x1FFF);

        // Calculate offset into CHR ROM based on selected bank
        // Each bank is 8KB (0x2000 bytes)
        const bank_offset: usize = @as(usize, self.chr_bank) * 0x2000;
        const chr_offset = bank_offset + chr_addr;

        if (chr_offset < cart.chr_data.len) {
            return cart.chr_data[chr_offset];
        }

        // Beyond CHR data - return open bus
        return 0xFF;
    }

    /// PPU write to CHR space ($0000-$1FFF)
    ///
    /// CNROM uses CHR ROM (not RAM), so writes are silently ignored.
    /// This is correct NES behavior.
    pub fn ppuWrite(_: *Mapper3, _: anytype, _: u16, _: u8) void {
        // CNROM has CHR ROM (read-only)
        // Writes are silently ignored (correct NES behavior)
    }

    /// Reset mapper to power-on state
    ///
    /// CNROM power-on state: CHR bank register is typically 0
    /// (though hardware behavior may vary)
    pub fn reset(self: *Mapper3, _: anytype) void {
        self.chr_bank = 0;
    }

    // ========================================================================
    // IRQ Interface (CNROM doesn't support IRQ - all stubs)
    // ========================================================================

    /// Poll for IRQ assertion
    ///
    /// CNROM has no IRQ support - always returns false.
    pub fn tickIrq(_: *Mapper3) bool {
        return false; // CNROM never asserts IRQ
    }

    /// Notify of PPU A12 rising edge
    ///
    /// CNROM doesn't use PPU A12 - this is a no-op.
    pub fn ppuA12Rising(_: *Mapper3) void {
        // CNROM ignores PPU A12 edges
    }

    /// Acknowledge IRQ (clear pending flag)
    ///
    /// CNROM has no IRQ to acknowledge - this is a no-op.
    pub fn acknowledgeIrq(_: *Mapper3) void {
        // CNROM has no IRQ state to clear
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

        pub fn getChrRomSize(self: @This()) u32 {
            return @as(u32, self.chr_rom_size) * 8192;
        }
    },
};

test "Mapper3: Power-on state" {
    const mapper = Mapper3{};

    // Power-on: CHR bank should be 0
    try testing.expectEqual(@as(u2, 0), mapper.chr_bank);
}

test "Mapper3: CHR bank switching - 4 banks" {
    var mapper = Mapper3{};

    // Create fake 32KB CHR ROM (4 banks × 8KB)
    var chr_data = [_]u8{0} ** (32 * 1024);

    // Mark each bank with distinct values
    @memset(chr_data[0x0000..0x2000], 0xAA); // Bank 0
    @memset(chr_data[0x2000..0x4000], 0xBB); // Bank 1
    @memset(chr_data[0x4000..0x6000], 0xCC); // Bank 2
    @memset(chr_data[0x6000..0x8000], 0xDD); // Bank 3

    var prg_rom = [_]u8{0} ** 16384;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .header = .{ .chr_rom_size = 4 }, // 4 × 8KB = 32KB
    };

    // Test bank 0 (default)
    try testing.expectEqual(@as(u8, 0xAA), mapper.ppuRead(&cart, 0x0000));
    try testing.expectEqual(@as(u8, 0xAA), mapper.ppuRead(&cart, 0x1FFF));

    // Switch to bank 1
    mapper.cpuWrite(&cart, 0x8000, 0x01);
    try testing.expectEqual(@as(u2, 1), mapper.chr_bank);
    try testing.expectEqual(@as(u8, 0xBB), mapper.ppuRead(&cart, 0x0000));
    try testing.expectEqual(@as(u8, 0xBB), mapper.ppuRead(&cart, 0x1FFF));

    // Switch to bank 2
    mapper.cpuWrite(&cart, 0xC000, 0x02);
    try testing.expectEqual(@as(u2, 2), mapper.chr_bank);
    try testing.expectEqual(@as(u8, 0xCC), mapper.ppuRead(&cart, 0x0000));
    try testing.expectEqual(@as(u8, 0xCC), mapper.ppuRead(&cart, 0x1FFF));

    // Switch to bank 3
    mapper.cpuWrite(&cart, 0xFFFF, 0x03);
    try testing.expectEqual(@as(u2, 3), mapper.chr_bank);
    try testing.expectEqual(@as(u8, 0xDD), mapper.ppuRead(&cart, 0x0000));
    try testing.expectEqual(@as(u8, 0xDD), mapper.ppuRead(&cart, 0x1FFF));
}

test "Mapper3: CHR bank masking - only uses bits 0-1" {
    var mapper = Mapper3{};

    var chr_data = [_]u8{0xAA} ** (32 * 1024);
    var prg_rom = [_]u8{0} ** 16384;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .header = .{ .chr_rom_size = 4 },
    };

    // Write value with upper bits set
    mapper.cpuWrite(&cart, 0x8000, 0xFF); // 11111111

    // Only bits 0-1 should be used (bank 3)
    try testing.expectEqual(@as(u2, 3), mapper.chr_bank);
}

test "Mapper3: 32KB PRG ROM mapping" {
    const mapper = Mapper3{};

    var prg_rom = [_]u8{0} ** 32768;
    prg_rom[0x0000] = 0x11; // $8000
    prg_rom[0x3FFF] = 0x22; // $BFFF
    prg_rom[0x4000] = 0x33; // $C000
    prg_rom[0x7FFF] = 0x44; // $FFFF

    var chr_data = [_]u8{0} ** 8192;

    const cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .header = .{ .chr_rom_size = 1 },
    };

    // Test 32KB mapping
    try testing.expectEqual(@as(u8, 0x11), mapper.cpuRead(&cart, 0x8000));
    try testing.expectEqual(@as(u8, 0x22), mapper.cpuRead(&cart, 0xBFFF));
    try testing.expectEqual(@as(u8, 0x33), mapper.cpuRead(&cart, 0xC000));
    try testing.expectEqual(@as(u8, 0x44), mapper.cpuRead(&cart, 0xFFFF));
}

test "Mapper3: 16KB PRG ROM mirroring" {
    const mapper = Mapper3{};

    var prg_rom = [_]u8{0} ** 16384;
    prg_rom[0x0000] = 0x55; // $8000
    prg_rom[0x3FFF] = 0x66; // $BFFF

    var chr_data = [_]u8{0} ** 8192;

    const cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .header = .{ .chr_rom_size = 1 },
    };

    // $8000-$BFFF: First 16KB
    try testing.expectEqual(@as(u8, 0x55), mapper.cpuRead(&cart, 0x8000));
    try testing.expectEqual(@as(u8, 0x66), mapper.cpuRead(&cart, 0xBFFF));

    // $C000-$FFFF: Mirrored 16KB
    try testing.expectEqual(@as(u8, 0x55), mapper.cpuRead(&cart, 0xC000));
    try testing.expectEqual(@as(u8, 0x66), mapper.cpuRead(&cart, 0xFFFF));
}

test "Mapper3: CHR writes ignored (CHR ROM)" {
    var mapper = Mapper3{};

    var prg_rom = [_]u8{0} ** 16384;
    var chr_data = [_]u8{0x99} ** 8192; // Pre-filled

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .header = .{ .chr_rom_size = 1 },
    };

    // Try to write to CHR ROM (should be ignored)
    mapper.ppuWrite(&cart, 0x0000, 0x42);

    // Value should remain unchanged
    try testing.expectEqual(@as(u8, 0x99), mapper.ppuRead(&cart, 0x0000));
}

test "Mapper3: Reset sets CHR bank to 0" {
    var mapper = Mapper3{};

    var prg_rom = [_]u8{0} ** 16384;
    var chr_data = [_]u8{0} ** 8192;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .header = .{ .chr_rom_size = 1 },
    };

    // Set to bank 3
    mapper.cpuWrite(&cart, 0x8000, 0x03);
    try testing.expectEqual(@as(u2, 3), mapper.chr_bank);

    // Reset
    mapper.reset(&cart);

    // Should be back to bank 0
    try testing.expectEqual(@as(u2, 0), mapper.chr_bank);
}

test "Mapper3: No PRG RAM support" {
    var mapper = Mapper3{};

    var prg_rom = [_]u8{0} ** 16384;
    var chr_data = [_]u8{0} ** 8192;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .header = .{ .chr_rom_size = 1 },
    };

    // Try to read from PRG RAM region
    const value = mapper.cpuRead(&cart, 0x6000);
    try testing.expectEqual(@as(u8, 0xFF), value); // Open bus

    // Try to write to PRG RAM region (should be ignored)
    mapper.cpuWrite(&cart, 0x6000, 0x42);
    // No crash = success (write ignored)
}

test "Mapper3: IRQ interface stubs" {
    var mapper = Mapper3{};

    // IRQ never asserts
    try testing.expect(!mapper.tickIrq());

    // These should not crash (no-ops)
    mapper.ppuA12Rising();
    mapper.acknowledgeIrq();
}
