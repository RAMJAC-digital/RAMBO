//! Mapper 2: UxROM (Comptime Generic Implementation)
//!
//! 16KB switchable PRG bank + 16KB fixed PRG bank.
//! See: https://www.nesdev.org/wiki/UxROM
//!
//! This is a duck-typed mapper implementation using comptime generics.
//! No VTable, no runtime overhead - all dispatch is compile-time.
//!
//! PRG ROM: Up to 256KB (16 banks × 16KB)
//! - $8000-$BFFF: 16KB switchable PRG bank (bank select via $8000-$FFFF writes)
//! - $C000-$FFFF: 16KB fixed to LAST bank (contains reset vector)
//!
//! CHR: 8KB CHR RAM (or CHR ROM if present)
//! - Fixed at PPU $0000-$1FFF
//! - No banking
//!
//! Mirroring: Fixed by solder pads (horizontal or vertical)
//! - Not software-controlled
//!
//! Examples: Mega Man, Castlevania, Contra, Duck Tales
//!
//! Variants:
//! - UNROM: 3-bit bank select (8 banks, 128KB)
//! - UOROM: 4-bit bank select (16 banks, 256KB)

const std = @import("std");

/// Mapper 2 (UxROM) - Duck-Typed Implementation
///
/// Required Interface (for use with generic Cartridge):
/// - cpuRead(self: *const Mapper2, cart: anytype, address: u16) u8
/// - cpuWrite(self: *Mapper2, cart: anytype, address: u16, value: u8) void
/// - ppuRead(self: *const Mapper2, cart: anytype, address: u16) u8
/// - ppuWrite(self: *Mapper2, cart: anytype, address: u16, value: u8) void
/// - reset(self: *Mapper2, cart: anytype) void
///
/// UxROM state: PRG bank select only (mirroring is fixed by hardware).
pub const Mapper2 = struct {
    /// PRG bank select register (4 bits for up to 16 banks)
    /// Selects 16KB bank at $8000-$BFFF
    /// $C000-$FFFF is always fixed to last bank
    prg_bank: u4 = 0,

    /// CPU read from cartridge address space ($6000-$FFFF)
    ///
    /// Parameters use duck typing:
    /// - self: Mapper instance
    /// - cart: anytype - must have .prg_rom field
    /// - address: CPU address
    ///
    /// Returns: Byte from PRG ROM, or 0xFF for unmapped regions
    pub fn cpuRead(_: *const Mapper2, cart: anytype, address: u16) u8 {
        return switch (address) {
            // PRG RAM: $6000-$7FFF (not supported by UxROM)
            0x6000...0x7FFF => 0xFF, // Open bus

            // PRG ROM: $8000-$BFFF (16KB switchable bank)
            0x8000...0xBFFF => {
                const bank_offset: usize = @as(usize, cart.mapper.prg_bank) * 0x4000;
                const addr_offset: usize = @as(usize, address - 0x8000);
                const prg_offset = bank_offset + addr_offset;

                if (prg_offset < cart.prg_rom.len) {
                    return cart.prg_rom[prg_offset];
                }

                return 0xFF; // Beyond PRG ROM
            },

            // PRG ROM: $C000-$FFFF (16KB fixed to last bank)
            0xC000...0xFFFF => {
                // Last bank: Calculate based on total PRG ROM size
                // Each bank is 16KB (0x4000 bytes)
                const num_banks = (cart.prg_rom.len + 0x3FFF) / 0x4000;
                const last_bank = if (num_banks > 0) num_banks - 1 else 0;
                const bank_offset: usize = last_bank * 0x4000;
                const addr_offset: usize = @as(usize, address - 0xC000);
                const prg_offset = bank_offset + addr_offset;

                if (prg_offset < cart.prg_rom.len) {
                    return cart.prg_rom[prg_offset];
                }

                return 0xFF; // Beyond PRG ROM
            },

            // Unmapped regions
            else => 0xFF,
        };
    }

    /// CPU write to cartridge space ($6000-$FFFF)
    ///
    /// - $6000-$7FFF: Not supported (UxROM has no PRG RAM)
    /// - $8000-$FFFF: Bank select register
    ///   - Bits 0-3: PRG bank (0-15 for UOROM, 0-7 for UNROM)
    ///
    /// Note: UxROM is subject to bus conflicts. The actual hardware reads
    /// the ROM value during write. For compatibility, we implement the write
    /// regardless, but games should write values that match ROM contents.
    pub fn cpuWrite(self: *Mapper2, _: anytype, address: u16, value: u8) void {
        switch (address) {
            // PRG RAM: Not supported by UxROM
            0x6000...0x7FFF => {
                // Writes ignored (no PRG RAM)
            },

            // Bank Select: $8000-$FFFF
            0x8000...0xFFFF => {
                // Update PRG bank register (bits 0-3)
                // UNROM uses only bits 0-2 (8 banks)
                // UOROM uses bits 0-3 (16 banks)
                // We support the full 4 bits for maximum compatibility
                self.prg_bank = @truncate(value & 0x0F);
            },

            // Other addresses - ignored
            else => {},
        }
    }

    /// PPU read from CHR space ($0000-$1FFF)
    ///
    /// UxROM typically uses CHR RAM (writable), though some carts have CHR ROM.
    /// All 8KB is fixed at $0000-$1FFF (no banking).
    ///
    /// Parameters:
    /// - cart: anytype - must have .chr_data field
    /// - address: PPU address
    ///
    /// Returns: Byte from CHR RAM/ROM
    pub fn ppuRead(_: *const Mapper2, cart: anytype, address: u16) u8 {
        // CHR: $0000-$1FFF (8KB, no banking)
        const chr_addr = @as(usize, address & 0x1FFF);

        if (chr_addr < cart.chr_data.len) {
            return cart.chr_data[chr_addr];
        }

        // Beyond CHR data - return open bus
        return 0xFF;
    }

    /// PPU write to CHR space ($0000-$1FFF)
    ///
    /// UxROM typically uses CHR RAM (writable).
    /// If cart has CHR ROM, writes are silently ignored.
    pub fn ppuWrite(_: *Mapper2, cart: anytype, address: u16, value: u8) void {
        // CHR: $0000-$1FFF (8KB)
        const chr_addr = @as(usize, address & 0x1FFF);

        // Check if CHR is RAM (writable)
        // If header.chr_rom_size == 0, then chr_data is RAM
        const is_chr_ram = cart.header.getChrRomSize() == 0;

        if (is_chr_ram and chr_addr < cart.chr_data.len) {
            cart.chr_data[chr_addr] = value;
        }
        // If CHR ROM, writes are silently ignored (correct NES behavior)
    }

    /// Reset mapper to power-on state
    ///
    /// UxROM power-on state: PRG bank 0
    /// (though hardware behavior may vary)
    pub fn reset(self: *Mapper2, _: anytype) void {
        self.prg_bank = 0;
    }

    // ========================================================================
    // IRQ Interface (UxROM doesn't support IRQ - all stubs)
    // ========================================================================

    /// Poll for IRQ assertion
    ///
    /// UxROM has no IRQ support - always returns false.
    pub fn tickIrq(_: *Mapper2) bool {
        return false; // UxROM never asserts IRQ
    }

    /// Notify of PPU A12 rising edge
    ///
    /// UxROM doesn't use PPU A12 - this is a no-op.
    pub fn ppuA12Rising(_: *Mapper2) void {
        // UxROM ignores PPU A12 edges
    }

    /// Acknowledge IRQ (clear pending flag)
    ///
    /// UxROM has no IRQ to acknowledge - this is a no-op.
    pub fn acknowledgeIrq(_: *Mapper2) void {
        // UxROM has no IRQ state to clear
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
    mapper: Mapper2,
    header: struct {
        chr_rom_size: u8,

        pub fn getChrRomSize(self: @This()) u32 {
            return @as(u32, self.chr_rom_size) * 8192;
        }
    },
};

test "Mapper2: Power-on state" {
    const mapper = Mapper2{};

    // Power-on: PRG bank should be 0
    try testing.expectEqual(@as(u4, 0), mapper.prg_bank);
}

test "Mapper2: PRG bank switching - switchable bank" {
    var prg_rom = [_]u8{0} ** (256 * 1024); // 16 banks × 16KB

    // Mark each bank with distinct values at start of bank
    @memset(prg_rom[0x00000..0x04000], 0xAA); // Bank 0
    @memset(prg_rom[0x04000..0x08000], 0xBB); // Bank 1
    @memset(prg_rom[0x08000..0x0C000], 0xCC); // Bank 2
    @memset(prg_rom[0x0C000..0x10000], 0xDD); // Bank 3
    @memset(prg_rom[0x10000..0x14000], 0xEE); // Bank 4
    @memset(prg_rom[0x14000..0x18000], 0xFF); // Bank 5

    var chr_data = [_]u8{0} ** 8192;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = Mapper2{},
        .header = .{ .chr_rom_size = 0 }, // CHR RAM
    };

    // Test bank 0 (default) - switchable area $8000-$BFFF
    try testing.expectEqual(@as(u8, 0xAA), cart.mapper.cpuRead(&cart, 0x8000));
    try testing.expectEqual(@as(u8, 0xAA), cart.mapper.cpuRead(&cart, 0xBFFF));

    // Switch to bank 1
    cart.mapper.cpuWrite(&cart, 0x8000, 0x01);
    try testing.expectEqual(@as(u4, 1), cart.mapper.prg_bank);
    try testing.expectEqual(@as(u8, 0xBB), cart.mapper.cpuRead(&cart, 0x8000));
    try testing.expectEqual(@as(u8, 0xBB), cart.mapper.cpuRead(&cart, 0xBFFF));

    // Switch to bank 5
    cart.mapper.cpuWrite(&cart, 0xC000, 0x05);
    try testing.expectEqual(@as(u4, 5), cart.mapper.prg_bank);
    try testing.expectEqual(@as(u8, 0xFF), cart.mapper.cpuRead(&cart, 0x8000));
    try testing.expectEqual(@as(u8, 0xFF), cart.mapper.cpuRead(&cart, 0xBFFF));
}

test "Mapper2: PRG bank - fixed last bank" {
    var prg_rom = [_]u8{0} ** (256 * 1024); // 16 banks × 16KB

    // Mark last bank (15) with distinctive pattern
    @memset(prg_rom[0x3C000..0x40000], 0x99); // Bank 15 (last)

    // Mark bank 0 differently
    @memset(prg_rom[0x00000..0x04000], 0xAA); // Bank 0

    var chr_data = [_]u8{0} ** 8192;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = Mapper2{},
        .header = .{ .chr_rom_size = 0 },
    };

    // $C000-$FFFF should ALWAYS read from last bank (15), regardless of bank register
    try testing.expectEqual(@as(u8, 0x99), cart.mapper.cpuRead(&cart, 0xC000));
    try testing.expectEqual(@as(u8, 0x99), cart.mapper.cpuRead(&cart, 0xFFFF));

    // Switch to bank 0 (should only affect $8000-$BFFF)
    cart.mapper.cpuWrite(&cart, 0x8000, 0x00);

    // $8000-$BFFF should now show bank 0
    try testing.expectEqual(@as(u8, 0xAA), cart.mapper.cpuRead(&cart, 0x8000));
    try testing.expectEqual(@as(u8, 0xAA), cart.mapper.cpuRead(&cart, 0xBFFF));

    // $C000-$FFFF should STILL be bank 15 (last)
    try testing.expectEqual(@as(u8, 0x99), cart.mapper.cpuRead(&cart, 0xC000));
    try testing.expectEqual(@as(u8, 0x99), cart.mapper.cpuRead(&cart, 0xFFFF));
}

test "Mapper2: PRG bank masking - 4 bits" {
    var prg_rom = [_]u8{0} ** (256 * 1024);
    var chr_data = [_]u8{0} ** 8192;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = Mapper2{},
        .header = .{ .chr_rom_size = 0 },
    };

    // Write value with upper bits set
    cart.mapper.cpuWrite(&cart, 0x8000, 0xFF);

    // Only bits 0-3 should be used (bank 15)
    try testing.expectEqual(@as(u4, 15), cart.mapper.prg_bank);
}

test "Mapper2: 128KB ROM (8 banks)" {
    var prg_rom = [_]u8{0} ** (128 * 1024); // 8 banks × 16KB

    // Mark bank 0 and last bank (7)
    @memset(prg_rom[0x00000..0x04000], 0xAA); // Bank 0
    @memset(prg_rom[0x1C000..0x20000], 0x77); // Bank 7 (last)

    var chr_data = [_]u8{0} ** 8192;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = Mapper2{},
        .header = .{ .chr_rom_size = 0 },
    };

    // Bank 0 in switchable area
    try testing.expectEqual(@as(u8, 0xAA), cart.mapper.cpuRead(&cart, 0x8000));

    // Last bank (7) in fixed area
    try testing.expectEqual(@as(u8, 0x77), cart.mapper.cpuRead(&cart, 0xC000));
    try testing.expectEqual(@as(u8, 0x77), cart.mapper.cpuRead(&cart, 0xFFFF));
}

test "Mapper2: CHR RAM writes (CHR RAM mode)" {
    var prg_rom = [_]u8{0} ** 32768;
    var chr_data = [_]u8{0} ** 8192;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = Mapper2{},
        .header = .{ .chr_rom_size = 0 }, // 0 = CHR RAM
    };

    // Write to CHR RAM (should succeed)
    cart.mapper.ppuWrite(&cart, 0x0000, 0x42);
    cart.mapper.ppuWrite(&cart, 0x1FFF, 0x99);

    // Read back values
    try testing.expectEqual(@as(u8, 0x42), cart.mapper.ppuRead(&cart, 0x0000));
    try testing.expectEqual(@as(u8, 0x99), cart.mapper.ppuRead(&cart, 0x1FFF));
}

test "Mapper2: CHR ROM writes ignored (CHR ROM mode)" {
    var prg_rom = [_]u8{0} ** 32768;
    var chr_data = [_]u8{0x88} ** 8192; // Pre-filled with 0x88

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = Mapper2{},
        .header = .{ .chr_rom_size = 1 }, // 1 = CHR ROM present
    };

    // Try to write to CHR ROM (should be ignored)
    cart.mapper.ppuWrite(&cart, 0x0000, 0x42);

    // Value should remain unchanged (0x88)
    try testing.expectEqual(@as(u8, 0x88), cart.mapper.ppuRead(&cart, 0x0000));
}

test "Mapper2: Reset sets bank 0" {
    var prg_rom = [_]u8{0} ** (256 * 1024);
    var chr_data = [_]u8{0} ** 8192;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = Mapper2{},
        .header = .{ .chr_rom_size = 0 },
    };

    // Set to bank 15
    cart.mapper.cpuWrite(&cart, 0x8000, 0x0F);
    try testing.expectEqual(@as(u4, 15), cart.mapper.prg_bank);

    // Reset
    cart.mapper.reset(&cart);

    // Should be back to bank 0
    try testing.expectEqual(@as(u4, 0), cart.mapper.prg_bank);
}

test "Mapper2: No PRG RAM support" {
    var prg_rom = [_]u8{0} ** 32768;
    var chr_data = [_]u8{0} ** 8192;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = Mapper2{},
        .header = .{ .chr_rom_size = 0 },
    };

    // Try to read from PRG RAM region
    const value = cart.mapper.cpuRead(&cart, 0x6000);
    try testing.expectEqual(@as(u8, 0xFF), value); // Open bus

    // Try to write to PRG RAM region (should be ignored)
    cart.mapper.cpuWrite(&cart, 0x6000, 0x42);
    // No crash = success (write ignored)
}

test "Mapper2: IRQ interface stubs" {
    var mapper = Mapper2{};

    // IRQ never asserts
    try testing.expect(!mapper.tickIrq());

    // These should not crash (no-ops)
    mapper.ppuA12Rising();
    mapper.acknowledgeIrq();
}
