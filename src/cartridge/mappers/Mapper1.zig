//! Mapper 1: MMC1 (Comptime Generic Implementation)
//!
//! Complex mapper with 5-bit shift register protocol and multiple banking modes.
//! See: https://www.nesdev.org/wiki/MMC1
//!
//! This is a duck-typed mapper implementation using comptime generics.
//! No VTable, no runtime overhead - all dispatch is compile-time.
//!
//! Serial Protocol:
//! - 5 consecutive writes to $8000-$FFFF load shift register
//! - Write with bit 7 set ($80-$FF) resets shift register
//! - Only fifth write actually updates target register
//!
//! Internal Registers:
//! - Control ($8000-$9FFF): Mirroring, PRG mode, CHR mode
//! - CHR Bank 0 ($A000-$BFFF): First CHR bank (4KB or 8KB mode)
//! - CHR Bank 1 ($C000-$DFFF): Second CHR bank (4KB mode only)
//! - PRG Bank ($E000-$FFFF): PRG bank select + PRG RAM enable
//!
//! PRG ROM: Up to 512KB
//! - Mode 0/1: 32KB switchable at $8000-$FFFF
//! - Mode 2: Fixed first 16KB at $8000, switchable 16KB at $C000
//! - Mode 3: Switchable 16KB at $8000, fixed last 16KB at $C000
//!
//! CHR: Up to 128KB (ROM or RAM)
//! - 8KB mode: Single bank at $0000-$1FFF
//! - 4KB mode: Two banks at $0000-$0FFF and $1000-$1FFF
//!
//! PRG RAM: Optional 8KB at $6000-$7FFF
//! - Can be enabled/disabled via PRG bank register bit 4
//!
//! Mirroring: Software-controlled (4 modes)
//! - One-screen lower ($2000)
//! - One-screen upper ($2400)
//! - Vertical
//! - Horizontal
//!
//! Examples: Zelda, Metroid, Mega Man 2, Kid Icarus, Final Fantasy

const std = @import("std");

/// Mapper 1 (MMC1) - Duck-Typed Implementation
///
/// Required Interface (for use with generic Cartridge):
/// - cpuRead(self: *const Mapper1, cart: anytype, address: u16) u8
/// - cpuWrite(self: *Mapper1, cart: anytype, address: u16, value: u8) void
/// - ppuRead(self: *const Mapper1, cart: anytype, address: u16) u8
/// - ppuWrite(self: *Mapper1, cart: anytype, address: u16, value: u8) void
/// - reset(self: *Mapper1, cart: anytype) void
pub const Mapper1 = struct {
    // Shift register state
    shift_register: u5 = 0,
    shift_count: u3 = 0,

    // Internal registers (loaded from shift register)
    control: u5 = 0x0C, // Power-on: Mode 3, 4KB CHR, vertical mirroring
    chr_bank_0: u5 = 0,
    chr_bank_1: u5 = 0,
    prg_bank: u5 = 0,

    /// CPU read from cartridge address space ($6000-$FFFF)
    pub fn cpuRead(self: *const Mapper1, cart: anytype, address: u16) u8 {
        return switch (address) {
            // PRG RAM: $6000-$7FFF (optional 8KB)
            0x6000...0x7FFF => {
                // Check if PRG RAM is enabled (bit 4 of prg_bank register = 0 means enabled)
                const prg_ram_enabled = (self.prg_bank & 0x10) == 0;

                if (prg_ram_enabled and cart.prg_ram != null) {
                    const ram_addr = @as(usize, address - 0x6000);
                    if (ram_addr < cart.prg_ram.?.len) {
                        return cart.prg_ram.?[ram_addr];
                    }
                }

                return 0xFF; // Open bus if disabled or not present
            },

            // PRG ROM: $8000-$FFFF (banking depends on control register)
            0x8000...0xFFFF => {
                const prg_mode = (self.control >> 2) & 0x03;
                const prg_bank_num = self.prg_bank & 0x0F;

                return switch (prg_mode) {
                    // Mode 0, 1: 32KB banks (ignore low bit)
                    0, 1 => blk: {
                        const bank_32kb = prg_bank_num >> 1;
                        const bank_offset: usize = @as(usize, bank_32kb) * 0x8000;
                        const addr_offset: usize = @as(usize, address - 0x8000);
                        const prg_offset = bank_offset + addr_offset;

                        if (prg_offset < cart.prg_rom.len) {
                            break :blk cart.prg_rom[prg_offset];
                        }
                        break :blk 0xFF;
                    },

                    // Mode 2: Fixed first 16KB at $8000, switchable at $C000
                    2 => blk: {
                        if (address < 0xC000) {
                            // Fixed first bank (bank 0)
                            const addr_offset: usize = @as(usize, address - 0x8000);
                            if (addr_offset < cart.prg_rom.len) {
                                break :blk cart.prg_rom[addr_offset];
                            }
                        } else {
                            // Switchable bank at $C000
                            const bank_offset: usize = @as(usize, prg_bank_num) * 0x4000;
                            const addr_offset: usize = @as(usize, address - 0xC000);
                            const prg_offset = bank_offset + addr_offset;

                            if (prg_offset < cart.prg_rom.len) {
                                break :blk cart.prg_rom[prg_offset];
                            }
                        }
                        break :blk 0xFF;
                    },

                    // Mode 3: Switchable at $8000, fixed last 16KB at $C000
                    3 => blk: {
                        if (address < 0xC000) {
                            // Switchable bank at $8000
                            const bank_offset: usize = @as(usize, prg_bank_num) * 0x4000;
                            const addr_offset: usize = @as(usize, address - 0x8000);
                            const prg_offset = bank_offset + addr_offset;

                            if (prg_offset < cart.prg_rom.len) {
                                break :blk cart.prg_rom[prg_offset];
                            }
                        } else {
                            // Fixed last bank
                            const num_banks = (cart.prg_rom.len + 0x3FFF) / 0x4000;
                            const last_bank = if (num_banks > 0) num_banks - 1 else 0;
                            const bank_offset: usize = last_bank * 0x4000;
                            const addr_offset: usize = @as(usize, address - 0xC000);
                            const prg_offset = bank_offset + addr_offset;

                            if (prg_offset < cart.prg_rom.len) {
                                break :blk cart.prg_rom[prg_offset];
                            }
                        }
                        break :blk 0xFF;
                    },

                    else => 0xFF, // Unreachable, but satisfy compiler
                };
            },

            else => 0xFF,
        };
    }

    /// CPU write to cartridge space ($6000-$FFFF)
    ///
    /// - $6000-$7FFF: PRG RAM (if enabled)
    /// - $8000-$FFFF: Shift register protocol
    ///   - Bit 7 set: Reset shift register
    ///   - Bit 7 clear: Shift in bit 0, increment count
    ///   - Fifth write: Load target register based on address
    pub fn cpuWrite(self: *Mapper1, cart: anytype, address: u16, value: u8) void {
        switch (address) {
            // PRG RAM: $6000-$7FFF
            0x6000...0x7FFF => {
                const prg_ram_enabled = (self.prg_bank & 0x10) == 0;

                if (prg_ram_enabled and cart.prg_ram != null) {
                    const ram_addr = @as(usize, address - 0x6000);
                    if (ram_addr < cart.prg_ram.?.len) {
                        cart.prg_ram.?[ram_addr] = value;
                    }
                }
            },

            // Shift Register: $8000-$FFFF
            0x8000...0xFFFF => {
                // Check for reset (bit 7 set)
                if ((value & 0x80) != 0) {
                    self.shift_register = 0;
                    self.shift_count = 0;
                    // Reset also sets control to mode 3 (per hardware behavior)
                    self.control |= 0x0C;
                    return;
                }

                // Shift in bit 0
                const bit: u5 = @truncate(value & 0x01);
                self.shift_register = (self.shift_register >> 1) | (bit << 4);
                self.shift_count += 1;

                // On fifth write, load target register
                if (self.shift_count == 5) {
                    switch (address) {
                        // Control: $8000-$9FFF
                        0x8000...0x9FFF => {
                            self.control = self.shift_register;
                        },

                        // CHR Bank 0: $A000-$BFFF
                        0xA000...0xBFFF => {
                            self.chr_bank_0 = self.shift_register;
                        },

                        // CHR Bank 1: $C000-$DFFF
                        0xC000...0xDFFF => {
                            self.chr_bank_1 = self.shift_register;
                        },

                        // PRG Bank: $E000-$FFFF
                        0xE000...0xFFFF => {
                            self.prg_bank = self.shift_register;
                        },

                        else => {},
                    }

                    // Reset shift register after load
                    self.shift_register = 0;
                    self.shift_count = 0;
                }
            },

            else => {},
        }
    }

    /// PPU read from CHR space ($0000-$1FFF)
    pub fn ppuRead(self: *const Mapper1, cart: anytype, address: u16) u8 {
        const chr_mode = (self.control >> 4) & 0x01;

        // CHR mode bit 4: 0 = 8KB mode, 1 = 4KB mode
        if (chr_mode == 0) {
            // 8KB mode: Use chr_bank_0, ignore low bit
            const bank_8kb = self.chr_bank_0 >> 1;
            const bank_offset: usize = @as(usize, bank_8kb) * 0x2000;
            const chr_addr = @as(usize, address & 0x1FFF);
            const chr_offset = bank_offset + chr_addr;

            if (chr_offset < cart.chr_data.len) {
                return cart.chr_data[chr_offset];
            }
        } else {
            // 4KB mode: Two separate banks
            if (address < 0x1000) {
                // $0000-$0FFF: Use chr_bank_0
                const bank_offset: usize = @as(usize, self.chr_bank_0) * 0x1000;
                const chr_addr = @as(usize, address & 0x0FFF);
                const chr_offset = bank_offset + chr_addr;

                if (chr_offset < cart.chr_data.len) {
                    return cart.chr_data[chr_offset];
                }
            } else {
                // $1000-$1FFF: Use chr_bank_1
                const bank_offset: usize = @as(usize, self.chr_bank_1) * 0x1000;
                const chr_addr = @as(usize, address & 0x0FFF);
                const chr_offset = bank_offset + chr_addr;

                if (chr_offset < cart.chr_data.len) {
                    return cart.chr_data[chr_offset];
                }
            }
        }

        return 0xFF; // Beyond CHR data
    }

    /// PPU write to CHR space ($0000-$1FFF)
    pub fn ppuWrite(self: *Mapper1, cart: anytype, address: u16, value: u8) void {
        // Check if CHR is RAM (writable)
        const is_chr_ram = cart.header.getChrRomSize() == 0;

        if (!is_chr_ram) {
            return; // CHR ROM - writes ignored
        }

        const chr_mode = (self.control >> 4) & 0x01;

        if (chr_mode == 0) {
            // 8KB mode
            const bank_8kb = self.chr_bank_0 >> 1;
            const bank_offset: usize = @as(usize, bank_8kb) * 0x2000;
            const chr_addr = @as(usize, address & 0x1FFF);
            const chr_offset = bank_offset + chr_addr;

            if (chr_offset < cart.chr_data.len) {
                cart.chr_data[chr_offset] = value;
            }
        } else {
            // 4KB mode
            if (address < 0x1000) {
                const bank_offset: usize = @as(usize, self.chr_bank_0) * 0x1000;
                const chr_addr = @as(usize, address & 0x0FFF);
                const chr_offset = bank_offset + chr_addr;

                if (chr_offset < cart.chr_data.len) {
                    cart.chr_data[chr_offset] = value;
                }
            } else {
                const bank_offset: usize = @as(usize, self.chr_bank_1) * 0x1000;
                const chr_addr = @as(usize, address & 0x0FFF);
                const chr_offset = bank_offset + chr_addr;

                if (chr_offset < cart.chr_data.len) {
                    cart.chr_data[chr_offset] = value;
                }
            }
        }
    }

    /// Reset mapper to power-on state
    pub fn reset(self: *Mapper1, _: anytype) void {
        self.shift_register = 0;
        self.shift_count = 0;
        self.control = 0x0C; // Mode 3, 4KB CHR
        self.chr_bank_0 = 0;
        self.chr_bank_1 = 0;
        self.prg_bank = 0;
    }

    /// Get current mirroring mode from control register
    pub fn getMirroring(self: *const Mapper1) u2 {
        return @truncate(self.control & 0x03);
    }

    // ========================================================================
    // IRQ Interface (MMC1 doesn't support IRQ - all stubs)
    // ========================================================================

    pub fn tickIrq(_: *Mapper1) bool {
        return false;
    }

    pub fn ppuA12Rising(_: *Mapper1) void {}

    pub fn acknowledgeIrq(_: *Mapper1) void {}
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

const TestCart = struct {
    prg_rom: []const u8,
    chr_data: []u8,
    prg_ram: ?[]u8 = null,
    mapper: Mapper1,
    header: struct {
        chr_rom_size: u8,

        pub fn getChrRomSize(self: @This()) u32 {
            return @as(u32, self.chr_rom_size) * 8192;
        }
    },
};

test "Mapper1: Power-on state" {
    var mapper = Mapper1{};

    try testing.expectEqual(@as(u5, 0), mapper.shift_register);
    try testing.expectEqual(@as(u3, 0), mapper.shift_count);
    try testing.expectEqual(@as(u5, 0x0C), mapper.control); // Mode 3

    // Silence unused warning
    _ = &mapper;
}

test "Mapper1: Shift register - single write" {
    const mapper = Mapper1{};
    var prg_rom = [_]u8{0} ** 32768;
    var chr_data = [_]u8{0} ** 8192;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = mapper,
        .header = .{ .chr_rom_size = 0 },
    };

    // Write bit 1
    cart.mapper.cpuWrite(&cart, 0x8000, 0x01);

    try testing.expectEqual(@as(u5, 0x10), cart.mapper.shift_register); // Bit shifted to position 4
    try testing.expectEqual(@as(u3, 1), cart.mapper.shift_count);
}

test "Mapper1: Shift register - five writes load control" {
    const mapper = Mapper1{};
    var prg_rom = [_]u8{0} ** 32768;
    var chr_data = [_]u8{0} ** 8192;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = mapper,
        .header = .{ .chr_rom_size = 0 },
    };

    // Write 5 bits: 1, 0, 1, 1, 0 (binary 01101 = 0x0D)
    cart.mapper.cpuWrite(&cart, 0x8000, 0x01); // Bit 0 = 1
    cart.mapper.cpuWrite(&cart, 0x8000, 0x00); // Bit 1 = 0
    cart.mapper.cpuWrite(&cart, 0x8000, 0x01); // Bit 2 = 1
    cart.mapper.cpuWrite(&cart, 0x8000, 0x01); // Bit 3 = 1
    cart.mapper.cpuWrite(&cart, 0x8000, 0x00); // Bit 4 = 0

    // Control should be loaded with 01101 = 0x0D
    try testing.expectEqual(@as(u5, 0x0D), cart.mapper.control);
    // Shift register should be reset
    try testing.expectEqual(@as(u3, 0), cart.mapper.shift_count);
}

test "Mapper1: Reset clears shift register" {
    const mapper = Mapper1{};
    var prg_rom = [_]u8{0} ** 32768;
    var chr_data = [_]u8{0} ** 8192;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = mapper,
        .header = .{ .chr_rom_size = 0 },
    };

    // Write 3 bits
    cart.mapper.cpuWrite(&cart, 0x8000, 0x01);
    cart.mapper.cpuWrite(&cart, 0x8000, 0x01);
    cart.mapper.cpuWrite(&cart, 0x8000, 0x01);
    try testing.expectEqual(@as(u3, 3), cart.mapper.shift_count);

    // Write with bit 7 set (reset)
    cart.mapper.cpuWrite(&cart, 0x8000, 0x80);

    try testing.expectEqual(@as(u3, 0), cart.mapper.shift_count);
    try testing.expectEqual(@as(u5, 0), cart.mapper.shift_register);
}

test "Mapper1: PRG mode 3 - switchable + fixed last" {
    var prg_rom = [_]u8{0} ** (256 * 1024); // 16 banks × 16KB

    // Mark banks
    @memset(prg_rom[0x00000..0x04000], 0xAA); // Bank 0
    @memset(prg_rom[0x04000..0x08000], 0xBB); // Bank 1
    @memset(prg_rom[0x3C000..0x40000], 0xFF); // Bank 15 (last)

    var chr_data = [_]u8{0} ** 8192;

    var mapper = Mapper1{};
    mapper.control = 0x0C; // Mode 3
    mapper.prg_bank = 0; // Bank 0 at $8000

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = mapper,
        .header = .{ .chr_rom_size = 0 },
    };

    // $8000: Bank 0 (switchable)
    try testing.expectEqual(@as(u8, 0xAA), cart.mapper.cpuRead(&cart, 0x8000));

    // $C000: Bank 15 (fixed last)
    try testing.expectEqual(@as(u8, 0xFF), cart.mapper.cpuRead(&cart, 0xC000));

    // Switch to bank 1
    cart.mapper.prg_bank = 1;

    // $8000: Now bank 1
    try testing.expectEqual(@as(u8, 0xBB), cart.mapper.cpuRead(&cart, 0x8000));

    // $C000: Still bank 15 (fixed)
    try testing.expectEqual(@as(u8, 0xFF), cart.mapper.cpuRead(&cart, 0xC000));
}

test "Mapper1: CHR 4KB mode" {
    var prg_rom = [_]u8{0} ** 32768;
    var chr_data = [_]u8{0} ** (32 * 1024); // 32 banks × 4KB

    @memset(chr_data[0x0000..0x1000], 0xAA); // Bank 0
    @memset(chr_data[0x1000..0x2000], 0xBB); // Bank 1

    var mapper = Mapper1{};
    mapper.control = 0x10; // 4KB CHR mode (bit 4 set)
    mapper.chr_bank_0 = 0;
    mapper.chr_bank_1 = 1;

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .mapper = mapper,
        .header = .{ .chr_rom_size = 4 },
    };

    // $0000-$0FFF: Bank 0
    try testing.expectEqual(@as(u8, 0xAA), cart.mapper.ppuRead(&cart, 0x0000));
    try testing.expectEqual(@as(u8, 0xAA), cart.mapper.ppuRead(&cart, 0x0FFF));

    // $1000-$1FFF: Bank 1
    try testing.expectEqual(@as(u8, 0xBB), cart.mapper.ppuRead(&cart, 0x1000));
    try testing.expectEqual(@as(u8, 0xBB), cart.mapper.ppuRead(&cart, 0x1FFF));
}

test "Mapper1: PRG RAM enable/disable" {
    var prg_rom = [_]u8{0} ** 32768;
    var chr_data = [_]u8{0} ** 8192;
    var prg_ram = [_]u8{0} ** 8192;

    var mapper = Mapper1{};
    mapper.prg_bank = 0x00; // PRG RAM enabled (bit 4 = 0)

    var cart = TestCart{
        .prg_rom = &prg_rom,
        .chr_data = &chr_data,
        .prg_ram = &prg_ram,
        .mapper = mapper,
        .header = .{ .chr_rom_size = 0 },
    };

    // Write to PRG RAM (enabled)
    cart.mapper.cpuWrite(&cart, 0x6000, 0x42);
    try testing.expectEqual(@as(u8, 0x42), cart.mapper.cpuRead(&cart, 0x6000));

    // Disable PRG RAM (bit 4 = 1)
    cart.mapper.prg_bank = 0x10;

    // Read should return open bus
    try testing.expectEqual(@as(u8, 0xFF), cart.mapper.cpuRead(&cart, 0x6000));
}

test "Mapper1: IRQ interface stubs" {
    var mapper = Mapper1{};

    try testing.expect(!mapper.tickIrq());
    mapper.ppuA12Rising();
    mapper.acknowledgeIrq();
}
