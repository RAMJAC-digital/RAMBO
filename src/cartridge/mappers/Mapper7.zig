//! Mapper 7: AxROM (Comptime Generic Implementation)
//!
//! 32KB PRG banking with single-screen mirroring.
//! See: https://www.nesdev.org/wiki/AxROM
//!
//! This is a duck-typed mapper implementation using comptime generics.
//! No VTable, no runtime overhead - all dispatch is compile-time.
//!
//! PRG ROM: Up to 256KB (8 banks × 32KB), bankswitched at $8000-$FFFF
//! - Bank selection via CPU writes to $8000-$FFFF (bits 0-2)
//!
//! CHR: 8KB CHR RAM (not ROM, writable)
//! - Fixed at PPU $0000-$1FFF
//! - No banking
//!
//! Mirroring: Single-screen, mapper-controlled
//! - Bit 4 of $8000-$FFFF selects which nametable (lower/upper)
//! - 0 = use nametable at $2000 for all mirrors
//! - 1 = use nametable at $2400 for all mirrors
//!
//! Examples: Battletoads, Wizards & Warriors, Marble Madness

const std = @import("std");

/// Mapper 7 (AxROM) - Duck-Typed Implementation
///
/// Required Interface (for use with generic Cartridge):
/// - cpuRead(self: *const Mapper7, cart: anytype, address: u16) u8
/// - cpuWrite(self: *Mapper7, cart: anytype, address: u16, value: u8) void
/// - ppuRead(self: *const Mapper7, cart: anytype, address: u16) u8
/// - ppuWrite(self: *Mapper7, cart: anytype, address: u16, value: u8) void
/// - reset(self: *Mapper7, cart: anytype) void
///
/// Mapper 7 state: PRG bank select + single-screen mirroring select.
pub const Mapper7 = struct {
    /// PRG bank select register (3 bits for up to 8 banks)
    /// Each bank is 32KB
    prg_bank: u3 = 0,

    /// Single-screen mirroring select (1 bit)
    /// 0 = use lower nametable ($2000)
    /// 1 = use upper nametable ($2400)
    mirroring: u1 = 0,

    /// CPU read from cartridge address space ($6000-$FFFF)
    ///
    /// Parameters use duck typing:
    /// - self: Mapper instance
    /// - cart: anytype - must have .prg_rom field
    /// - address: CPU address
    ///
    /// Returns: Byte from PRG ROM, or 0xFF for unmapped regions
    pub fn cpuRead(_: *const Mapper7, cart: anytype, address: u16) u8 {
        return switch (address) {
            // PRG RAM: $6000-$7FFF (not supported by AxROM)
            0x6000...0x7FFF => 0xFF, // Open bus

            // PRG ROM: $8000-$FFFF (32KB bankswitched)
            0x8000...0xFFFF => {
                // Bank offset: prg_bank * 32KB
                const bank_offset: usize = @as(usize, cart.mapper.prg_bank) * 0x8000;
                const addr_offset: usize = @as(usize, address - 0x8000);
                const prg_offset = bank_offset + addr_offset;

                if (prg_offset < cart.prg_rom.len) {
                    return cart.prg_rom[prg_offset];
                }

                // Beyond PRG ROM - return open bus
                return 0xFF;
            },

            // Unmapped regions
            else => 0xFF,
        };
    }

    /// CPU write to cartridge space ($6000-$FFFF)
    ///
    /// - $6000-$7FFF: Not supported (AxROM has no PRG RAM)
    /// - $8000-$FFFF: Bank select + mirroring
    ///   - Bits 0-2: PRG bank (0-7)
    ///   - Bit 4: Single-screen mirroring select
    ///
    /// Note: AxROM variants (AMROM/AOROM) may have bus conflicts.
    /// ANROM/AN1ROM avoid conflicts. Implementation writes regardless.
    pub fn cpuWrite(self: *Mapper7, _: anytype, address: u16, value: u8) void {
        switch (address) {
            // PRG RAM: Not supported by AxROM
            0x6000...0x7FFF => {
                // Writes ignored (no PRG RAM)
            },

            // Bank Select + Mirroring: $8000-$FFFF
            0x8000...0xFFFF => {
                // Bits 0-2: PRG bank select (0-7)
                self.prg_bank = @truncate(value & 0x07);

                // Bit 4: Single-screen mirroring select
                self.mirroring = @truncate((value >> 4) & 0x01);
            },

            // Other addresses - ignored
            else => {},
        }
    }

    /// PPU read from CHR space ($0000-$1FFF)
    ///
    /// AxROM uses CHR RAM (not ROM). All 8KB is fixed at $0000-$1FFF.
    ///
    /// Parameters:
    /// - cart: anytype - must have .chr_data field
    /// - address: PPU address
    ///
    /// Returns: Byte from CHR RAM
    pub fn ppuRead(_: *const Mapper7, cart: anytype, address: u16) u8 {
        // CHR RAM: $0000-$1FFF (8KB, no banking)
        const chr_addr = @as(usize, address & 0x1FFF);

        if (chr_addr < cart.chr_data.len) {
            return cart.chr_data[chr_addr];
        }

        // Beyond CHR data - return open bus
        return 0xFF;
    }

    /// PPU write to CHR space ($0000-$1FFF)
    ///
    /// AxROM uses CHR RAM (writable), unlike CNROM which uses CHR ROM.
    pub fn ppuWrite(_: *Mapper7, cart: anytype, address: u16, value: u8) void {
        // CHR RAM: $0000-$1FFF (8KB, writable)
        const chr_addr = @as(usize, address & 0x1FFF);

        if (chr_addr < cart.chr_data.len) {
            cart.chr_data[chr_addr] = value;
        }
    }

    /// Reset mapper to power-on state
    ///
    /// AxROM power-on state: PRG bank 0, lower nametable mirroring
    /// (though hardware behavior may vary)
    pub fn reset(self: *Mapper7, _: anytype) void {
        self.prg_bank = 0;
        self.mirroring = 0; // Lower nametable ($2000)
    }

    /// Get current mirroring mode (dynamic for Mapper7)
    ///
    /// Returns mirroring mode as u3:
    /// - 4 = single_screen_lower (mirroring bit 0)
    /// - 5 = single_screen_upper (mirroring bit 1)
    ///
    /// This allows Battletoads and other AxROM games to dynamically change
    /// which nametable is active during gameplay.
    ///
    /// Note: Duck-typed return - Cartridge.getMirroring() will cast to proper enum
    pub fn getMirroring(self: *const Mapper7) u3 {
        // Return 4 (single_screen_lower) or 5 (single_screen_upper)
        return if (self.mirroring == 0) 4 else 5;
    }

    // ========================================================================
    // IRQ Interface (AxROM doesn't support IRQ - all stubs)
    // ========================================================================

    /// Poll for IRQ assertion
    ///
    /// AxROM has no IRQ support - always returns false.
    pub fn tickIrq(_: *Mapper7) bool {
        return false; // AxROM never asserts IRQ
    }

    /// Notify of PPU A12 rising edge
    ///
    /// AxROM doesn't use PPU A12 - this is a no-op.
    pub fn ppuA12Rising(_: *Mapper7) void {
        // AxROM ignores PPU A12 edges
    }

    /// Acknowledge IRQ (clear pending flag)
    ///
    /// AxROM has no IRQ to acknowledge - this is a no-op.
    pub fn acknowledgeIrq(_: *Mapper7) void {
        // AxROM has no IRQ state to clear
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
    mapper: Mapper7,
    header: struct {
        chr_rom_size: u8,

        pub fn getChrRomSize(self: @This()) u32 {
            return @as(u32, self.chr_rom_size) * 8192;
        }
    },
};

test "Mapper7: Power-on state" {
    const mapper = Mapper7{};

    // Power-on: PRG bank should be 0, lower nametable
    try testing.expectEqual(@as(u3, 0), mapper.prg_bank);
    try testing.expectEqual(@as(u1, 0), mapper.mirroring);
}

test "Mapper7: PRG bank switching - 8 banks" {
    var prg_rom = [_]u8{0} ** (256 * 1024); // 8 banks × 32KB

    // Mark each bank with distinct values
    @memset(prg_rom[0x00000..0x08000], 0xAA); // Bank 0
    @memset(prg_rom[0x08000..0x10000], 0xBB); // Bank 1
    @memset(prg_rom[0x10000..0x18000], 0xCC); // Bank 2
    @memset(prg_rom[0x18000..0x20000], 0xDD); // Bank 3
    @memset(prg_rom[0x20000..0x28000], 0xEE); // Bank 4
    @memset(prg_rom[0x28000..0x30000], 0xFF); // Bank 5
    @memset(prg_rom[0x30000..0x38000], 0x11); // Bank 6
    @memset(prg_rom[0x38000..0x40000], 0x22); // Bank 7

    var chr_data = [_]u8{0} ** 8192;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = Mapper7{},
        .header = .{ .chr_rom_size = 1 },
    };

    // Test bank 0 (default)
    try testing.expectEqual(@as(u8, 0xAA), cart.mapper.cpuRead(&cart, 0x8000));
    try testing.expectEqual(@as(u8, 0xAA), cart.mapper.cpuRead(&cart, 0xFFFF));

    // Switch to bank 1
    cart.mapper.cpuWrite(&cart, 0x8000, 0x01);
    try testing.expectEqual(@as(u3, 1), cart.mapper.prg_bank);
    try testing.expectEqual(@as(u8, 0xBB), cart.mapper.cpuRead(&cart, 0x8000));
    try testing.expectEqual(@as(u8, 0xBB), cart.mapper.cpuRead(&cart, 0xFFFF));

    // Switch to bank 7
    cart.mapper.cpuWrite(&cart, 0xC000, 0x07);
    try testing.expectEqual(@as(u3, 7), cart.mapper.prg_bank);
    try testing.expectEqual(@as(u8, 0x22), cart.mapper.cpuRead(&cart, 0x8000));
    try testing.expectEqual(@as(u8, 0x22), cart.mapper.cpuRead(&cart, 0xFFFF));
}

test "Mapper7: Single-screen mirroring switching" {
    var prg_rom = [_]u8{0} ** 32768;
    var chr_data = [_]u8{0} ** 8192;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = Mapper7{},
        .header = .{ .chr_rom_size = 1 },
    };

    // Default: lower nametable
    try testing.expectEqual(@as(u1, 0), cart.mapper.mirroring);

    // Switch to upper nametable (bit 4 = 1)
    cart.mapper.cpuWrite(&cart, 0x8000, 0x10);
    try testing.expectEqual(@as(u1, 1), cart.mapper.mirroring);

    // Switch back to lower (bit 4 = 0)
    cart.mapper.cpuWrite(&cart, 0x8000, 0x00);
    try testing.expectEqual(@as(u1, 0), cart.mapper.mirroring);
}

test "Mapper7: Bank and mirroring together" {
    var prg_rom = [_]u8{0} ** (256 * 1024);
    var chr_data = [_]u8{0} ** 8192;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = Mapper7{},
        .header = .{ .chr_rom_size = 1 },
    };

    // Write: Bank 3 + upper nametable
    // xxxM xPPP = 0001 0011 = 0x13
    cart.mapper.cpuWrite(&cart, 0x8000, 0x13);

    try testing.expectEqual(@as(u3, 3), cart.mapper.prg_bank);
    try testing.expectEqual(@as(u1, 1), cart.mapper.mirroring);
}

test "Mapper7: PRG bank masking - only uses bits 0-2 and bit 4" {
    var prg_rom = [_]u8{0} ** (256 * 1024);
    var chr_data = [_]u8{0} ** 8192;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = Mapper7{},
        .header = .{ .chr_rom_size = 1 },
    };

    // Write value with all relevant bits set
    // xxxM xPPP = xxx1 x111 = 0x17 (0001 0111)
    cart.mapper.cpuWrite(&cart, 0x8000, 0x17);

    // Bits 0-2 should give bank 7
    try testing.expectEqual(@as(u3, 7), cart.mapper.prg_bank);
    // Bit 4 should set mirroring
    try testing.expectEqual(@as(u1, 1), cart.mapper.mirroring);

    // Test with bit 4 clear
    // xxxM xPPP = xxx0 x101 = 0x05 (0000 0101)
    cart.mapper.cpuWrite(&cart, 0x8000, 0x05);

    // Bits 0-2 should give bank 5
    try testing.expectEqual(@as(u3, 5), cart.mapper.prg_bank);
    // Bit 4 should clear mirroring
    try testing.expectEqual(@as(u1, 0), cart.mapper.mirroring);
}

test "Mapper7: CHR RAM writes" {
    var prg_rom = [_]u8{0} ** 32768;
    var chr_data = [_]u8{0} ** 8192;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = Mapper7{},
        .header = .{ .chr_rom_size = 1 },
    };

    // Write to CHR RAM
    cart.mapper.ppuWrite(&cart, 0x0000, 0x42);
    cart.mapper.ppuWrite(&cart, 0x1FFF, 0x99);

    // Read back values
    try testing.expectEqual(@as(u8, 0x42), cart.mapper.ppuRead(&cart, 0x0000));
    try testing.expectEqual(@as(u8, 0x99), cart.mapper.ppuRead(&cart, 0x1FFF));
}

test "Mapper7: Reset sets bank 0 and lower nametable" {
    var prg_rom = [_]u8{0} ** (256 * 1024);
    var chr_data = [_]u8{0} ** 8192;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = Mapper7{},
        .header = .{ .chr_rom_size = 1 },
    };

    // Set to bank 7, upper nametable
    cart.mapper.cpuWrite(&cart, 0x8000, 0x17);
    try testing.expectEqual(@as(u3, 7), cart.mapper.prg_bank);
    try testing.expectEqual(@as(u1, 1), cart.mapper.mirroring);

    // Reset
    cart.mapper.reset(&cart);

    // Should be back to bank 0, lower nametable
    try testing.expectEqual(@as(u3, 0), cart.mapper.prg_bank);
    try testing.expectEqual(@as(u1, 0), cart.mapper.mirroring);
}

test "Mapper7: No PRG RAM support" {
    var prg_rom = [_]u8{0} ** 32768;
    var chr_data = [_]u8{0} ** 8192;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = Mapper7{},
        .header = .{ .chr_rom_size = 1 },
    };

    // Try to read from PRG RAM region
    const value = cart.mapper.cpuRead(&cart, 0x6000);
    try testing.expectEqual(@as(u8, 0xFF), value); // Open bus

    // Try to write to PRG RAM region (should be ignored)
    cart.mapper.cpuWrite(&cart, 0x6000, 0x42);
    // No crash = success (write ignored)
}

test "Mapper7: IRQ interface stubs" {
    var mapper = Mapper7{};

    // IRQ never asserts
    try testing.expect(!mapper.tickIrq());

    // These should not crash (no-ops)
    mapper.ppuA12Rising();
    mapper.acknowledgeIrq();
}
