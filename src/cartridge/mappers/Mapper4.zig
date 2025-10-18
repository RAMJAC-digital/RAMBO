//! Mapper 4: MMC3 (TxROM)
//!
//! The most popular NES mapper, used in ~25% of commercial games including
//! Super Mario Bros. 3, Mega Man 3-6, and Kirby's Adventure.
//!
//! Hardware Features:
//! - PRG ROM: Up to 512KB (64 banks × 8KB)
//! - CHR ROM/RAM: Up to 256KB (256 banks × 1KB)
//! - PRG RAM: 8KB at $6000-$7FFF (optional battery backup)
//! - Banking: 2×8KB PRG switchable, 2×2KB + 4×1KB CHR switchable
//! - IRQ: Scanline counter via PPU A12 edge detection
//! - Mirroring: Software-controlled (H/V)
//!
//! Banking Modes:
//! - PRG Mode 0: $8000 switchable, $C000 fixed to -2
//! - PRG Mode 1: $C000 switchable, $8000 fixed to -2
//! - CHR Mode 0: 2KB banks at $0000-$0FFF, 1KB banks at $1000-$1FFF
//! - CHR Mode 1: 2KB banks at $1000-$1FFF, 1KB banks at $0000-$0FFF
//!
//! IRQ Mechanism:
//! - Counter decrements on PPU A12 rising edge (0→1 transition)
//! - A12 typically rises 8 times per scanline during rendering
//! - When counter reaches 0, IRQ is triggered (if enabled)
//! - Used for split-screen effects and per-scanline processing
//!
//! References:
//! - https://www.nesdev.org/wiki/MMC3
//! - https://www.nesdev.org/wiki/MMC3_scanline_counter

const std = @import("std");

pub const Mapper4 = struct {
    // Bank select register ($8000)
    bank_select: u3 = 0, // Which bank register to update (0-7)
    prg_mode: bool = false, // false = $8000 switchable, true = $C000 switchable
    chr_mode: bool = false, // false = 2KB at $0000, true = 2KB at $1000

    // Mirroring control ($A000)
    mirroring_horizontal: bool = false, // false = vertical, true = horizontal

    // Bank data registers ($8001)
    chr_banks: [6]u8 = [_]u8{0} ** 6, // R0-R5: CHR bank numbers
    prg_banks: [2]u8 = [_]u8{0} ** 2, // R6-R7: PRG bank numbers

    // PRG RAM protect ($A001)
    prg_ram_enabled: bool = true, // false = disabled
    prg_ram_write_protected: bool = false, // true = read-only

    // IRQ registers ($C000, $C001, $E000, $E001)
    irq_latch: u8 = 0, // Reload value for counter
    irq_counter: u8 = 0, // Actual counter value
    irq_reload: bool = false, // Reload flag
    irq_enabled: bool = false, // IRQ enable flag
    irq_pending: bool = false, // IRQ pending flag

    // A12 edge detection for IRQ
    a12_low_count: u8 = 0, // Number of cycles A12 has been low
    debug_a12_count: u32 = 0, // Debug counter for A12 edges (tests only)
    debug_irq_events: u32 = 0, // Debug counter for IRQ pending assertions

    // ========================================================================
    // CPU Memory Interface
    // ========================================================================

    /// Read from CPU address space ($6000-$FFFF)
    pub fn cpuRead(self: *const Mapper4, cart: anytype, address: u16) u8 {
        // PRG RAM at $6000-$7FFF
        if (address >= 0x6000 and address < 0x8000) {
            if (cart.prg_ram) |ram| {
                if (self.prg_ram_enabled) {
                    return ram[@as(usize, address - 0x6000)];
                }
            }
            return 0xFF; // Open bus
        }

        // PRG ROM banking at $8000-$FFFF
        if (address >= 0x8000) {
            const raw_bank: usize = self.getPrgBank(cart, address);
            const bank_size: usize = 0x2000; // 8KB banks
            const total_prg_bytes: usize = cart.prg_rom.len;
            const total_prg_8k_banks: usize = if (total_prg_bytes == 0) 0 else total_prg_bytes / bank_size;
            const bank: usize = if (total_prg_8k_banks == 0) 0 else (raw_bank % total_prg_8k_banks);
            const bank_offset = bank * bank_size;
            const addr_offset = @as(usize, address & 0x1FFF);

            // Bounds check
            if (bank_offset + addr_offset < cart.prg_rom.len) {
                return cart.prg_rom[bank_offset + addr_offset];
            }
            return 0xFF;
        }

        return 0xFF;
    }

    /// Write to CPU address space ($6000-$FFFF)
    pub fn cpuWrite(self: *Mapper4, cart: anytype, address: u16, value: u8) void {
        // PRG RAM at $6000-$7FFF
        if (address >= 0x6000 and address < 0x8000) {
            if (cart.prg_ram) |ram| {
                if (self.prg_ram_enabled and !self.prg_ram_write_protected) {
                    ram[@as(usize, address - 0x6000)] = value;
                }
            }
            return;
        }

        // MMC3 registers at $8000-$FFFF (even/odd address determines register)
        if (address >= 0x8000) {
            if ((address & 0x01) == 0) {
                // Even addresses: $8000, $A000, $C000, $E000
                if (address < 0xA000) {
                    // $8000-$9FFE: Bank select
                    self.bank_select = @truncate(value & 0x07);
                    self.prg_mode = (value & 0x40) != 0;
                    self.chr_mode = (value & 0x80) != 0;
                } else if (address < 0xC000) {
                    // $A000-$BFFE: Mirroring
                    self.mirroring_horizontal = (value & 0x01) != 0;
                    // Cartridge will query mapper for mirroring via getMirroring()
                } else if (address < 0xE000) {
                    // $C000-$DFFE: IRQ latch
                    self.irq_latch = value;
                } else {
                    // $E000-$FFFE: IRQ disable
                    self.irq_enabled = false;
                    self.irq_pending = false;
                }
            } else {
                // Odd addresses: $8001, $A001, $C001, $E001
                if (address < 0xA000) {
                    // $8001-$9FFF: Bank data
                    switch (self.bank_select) {
                        0...5 => self.chr_banks[self.bank_select] = value,
                        6, 7 => self.prg_banks[self.bank_select - 6] = value & 0x3F, // 6-bit PRG banks
                    }
                } else if (address < 0xC000) {
                    // $A001-$BFFF: PRG RAM protect
                    self.prg_ram_enabled = (value & 0x80) != 0;
                    self.prg_ram_write_protected = (value & 0x40) != 0;
                } else if (address < 0xE000) {
                    // $C001-$DFFF: IRQ reload
                    self.irq_reload = true;
                } else {
                    // $E001-$FFFF: IRQ enable
                    // Per nesdev.org: Enables IRQ generation without acknowledging pending IRQ
                    // Only $E000 (disable) acknowledges pending IRQs
                    self.irq_enabled = true;
                }
            }
        }
    }

    // ========================================================================
    // PPU Memory Interface
    // ========================================================================

    /// Read from PPU address space ($0000-$1FFF for CHR)
    pub fn ppuRead(self: *const Mapper4, cart: anytype, address: u16) u8 {
        // Determine 1KB bank with safe wrap to available CHR size
        const raw_bank: usize = self.getChrBank(address);
        const total_chr_bytes: usize = cart.chr_data.len; // CHR ROM/RAM buffer
        const total_chr_1kb_banks: usize = if (total_chr_bytes == 0) 0 else total_chr_bytes / 0x400;

        const bank: usize = if (total_chr_1kb_banks == 0) 0 else (raw_bank % total_chr_1kb_banks);
        const bank_offset = bank * 0x0400; // 1KB banks
        const addr_offset = @as(usize, address & 0x03FF);

        if (bank_offset + addr_offset < cart.chr_data.len) {
            return cart.chr_data[bank_offset + addr_offset];
        }
        return 0xFF;
    }

    /// Write to PPU address space ($0000-$1FFF for CHR)
    pub fn ppuWrite(self: *const Mapper4, cart: anytype, address: u16, value: u8) void {
        // Only allow writes if CHR RAM (header.chr_rom_banks == 0)
        if (cart.header.chr_rom_banks == 0) {
            const raw_bank: usize = self.getChrBank(address);
            const total_chr_bytes: usize = cart.chr_data.len;
            const total_chr_1kb_banks: usize = if (total_chr_bytes == 0) 0 else total_chr_bytes / 0x400;
            const bank: usize = if (total_chr_1kb_banks == 0) 0 else (raw_bank % total_chr_1kb_banks);
            const bank_offset = bank * 0x0400;
            const addr_offset = @as(usize, address & 0x03FF);

            if (bank_offset + addr_offset < cart.chr_data.len) {
                cart.chr_data[bank_offset + addr_offset] = value;
            }
        }
    }

    /// Get current mirroring mode (for cartridge to query)
    pub fn getMirroring(self: *const Mapper4) u1 {
        return if (self.mirroring_horizontal) 1 else 0;
    }

    // ========================================================================
    // Banking Logic
    // ========================================================================

    /// Get PRG bank number for CPU address
    fn getPrgBank(self: *const Mapper4, cart: anytype, address: u16) u8 {
        const num_8k_banks = @as(u8, @intCast((cart.prg_rom.len + 0x1FFF) / 0x2000));
        const last_bank = if (num_8k_banks > 0) num_8k_banks - 1 else 0;
        const second_last_bank = if (num_8k_banks > 1) num_8k_banks - 2 else 0;

        return switch (address & 0xE000) {
            0x8000 => if (!self.prg_mode) self.prg_banks[0] else second_last_bank,
            0xA000 => self.prg_banks[1],
            0xC000 => if (self.prg_mode) self.prg_banks[0] else second_last_bank,
            0xE000 => last_bank,
            else => 0,
        };
    }

    /// Get CHR bank number for PPU address (1KB granularity)
    ///
    /// CHR Mode 0 ($8000.D7=0):
    ///   $0000-$03FF: R0 (2KB, even)
    ///   $0400-$07FF: R0 (2KB, odd)
    ///   $0800-$0BFF: R1 (2KB, even)
    ///   $0C00-$0FFF: R1 (2KB, odd)
    ///   $1000-$13FF: R2 (1KB)
    ///   $1400-$17FF: R3 (1KB)
    ///   $1800-$1BFF: R4 (1KB)
    ///   $1C00-$1FFF: R5 (1KB)
    ///
    /// CHR Mode 1 ($8000.D7=1):
    ///   $0000-$03FF: R2 (1KB)
    ///   $0400-$07FF: R3 (1KB)
    ///   $0800-$0BFF: R4 (1KB)
    ///   $0C00-$0FFF: R5 (1KB)
    ///   $1000-$13FF: R0 (2KB, even)
    ///   $1400-$17FF: R0 (2KB, odd)
    ///   $1800-$1BFF: R1 (2KB, even)
    ///   $1C00-$1FFF: R1 (2KB, odd)
    ///
    /// Reference: https://www.nesdev.org/wiki/MMC3#CHR_Banks
    fn getChrBank(self: *const Mapper4, address: u16) u8 {
        const addr = address & 0x1FFF;

        // CHR mode determines which areas get 2KB vs 1KB banks
        if (!self.chr_mode) {
            // Mode 0: 2KB banks at $0000-$0FFF, 1KB banks at $1000-$1FFF
            return switch (addr) {
                // R0: 2KB bank at $0000-$07FF
                0x0000...0x03FF => self.chr_banks[0] & 0xFE,
                0x0400...0x07FF => self.chr_banks[0] | 0x01,
                // R1: 2KB bank at $0800-$0FFF
                0x0800...0x0BFF => self.chr_banks[1] & 0xFE,
                0x0C00...0x0FFF => self.chr_banks[1] | 0x01,
                // R2-R5: 1KB banks at $1000-$1FFF
                0x1000...0x13FF => self.chr_banks[2], // R2
                0x1400...0x17FF => self.chr_banks[3], // R3
                0x1800...0x1BFF => self.chr_banks[4], // R4
                0x1C00...0x1FFF => self.chr_banks[5], // R5
                else => 0,
            };
        } else {
            // Mode 1: 2KB banks at $1000-$1FFF, 1KB banks at $0000-$0FFF
            return switch (addr) {
                // R2-R5: 1KB banks at $0000-$0FFF
                0x0000...0x03FF => self.chr_banks[2], // R2
                0x0400...0x07FF => self.chr_banks[3], // R3
                0x0800...0x0BFF => self.chr_banks[4], // R4
                0x0C00...0x0FFF => self.chr_banks[5], // R5
                // R0: 2KB bank at $1000-$17FF
                0x1000...0x13FF => self.chr_banks[0] & 0xFE,
                0x1400...0x17FF => self.chr_banks[0] | 0x01,
                // R1: 2KB bank at $1800-$1FFF
                0x1800...0x1BFF => self.chr_banks[1] & 0xFE,
                0x1C00...0x1FFF => self.chr_banks[1] | 0x01,
                else => 0,
            };
        }
    }

    // ========================================================================
    // IRQ Interface
    // ========================================================================

    /// Poll IRQ status (called every CPU cycle)
    pub fn tickIrq(self: *const Mapper4) bool {
        return self.irq_pending;
    }

    /// Notify mapper of PPU A12 rising edge
    ///
    /// Called when PPU address line A12 transitions from 0→1.
    /// This typically happens during rendering when fetching pattern tiles.
    /// MMC3 uses this to count scanlines for IRQ generation.
    ///
    /// Per nesdev.org and blargg's test ROMs:
    /// - IRQ triggers when counter decrements to zero OR when counter==0 naturally
    /// - IRQ does NOT trigger when $C001 reload flag causes reload
    pub fn ppuA12Rising(self: *Mapper4) void {
        self.debug_a12_count +%= 1;
        // Three cases: reload flag, counter==0, or decrement
        if (self.irq_reload) {
            // Case 1: Reload flag set (from $C001 write)
            // Per blargg's tests: Do NOT trigger IRQ when reload flag causes reload
            self.irq_counter = self.irq_latch;
            self.irq_reload = false;
        } else if (self.irq_counter == 0) {
            // Case 2: Counter naturally at 0 (from previous decrement or reload)
            // Reload counter and check for IRQ
            self.irq_counter = self.irq_latch;
            if (self.irq_enabled and self.irq_counter == 0) {
                self.irq_pending = true;
                self.debug_irq_events +%= 1;
            }
        } else {
            // Case 3: Normal decrement
            self.irq_counter -= 1;
            if (self.irq_enabled and self.irq_counter == 0) {
                self.irq_pending = true;
                self.debug_irq_events +%= 1;
            }
        }
    }

    /// Acknowledge IRQ (clear pending flag)
    pub fn acknowledgeIrq(self: *Mapper4) void {
        self.irq_pending = false;
    }

    // ========================================================================
    // Control Interface
    // ========================================================================

    /// Reset mapper to power-on state
    pub fn reset(self: *Mapper4, _: anytype) void {
        self.bank_select = 0;
        self.prg_mode = false;
        self.chr_mode = false;
        self.mirroring_horizontal = false;
        self.chr_banks = [_]u8{0} ** 6;
        self.prg_banks = [_]u8{0} ** 2;
        self.prg_ram_enabled = true;
        self.prg_ram_write_protected = false;
        self.irq_latch = 0;
        self.irq_counter = 0;
        self.irq_reload = false;
        self.irq_enabled = false;
        self.irq_pending = false;
        self.a12_low_count = 0;
        self.debug_a12_count = 0;
        self.debug_irq_events = 0;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "Mapper4: Power-on state" {
    const mapper = Mapper4{};

    try testing.expectEqual(@as(u3, 0), mapper.bank_select);
    try testing.expectEqual(false, mapper.prg_mode);
    try testing.expectEqual(false, mapper.chr_mode);
    try testing.expectEqual(true, mapper.prg_ram_enabled);
    try testing.expectEqual(false, mapper.prg_ram_write_protected);
    try testing.expectEqual(@as(u8, 0), mapper.irq_latch);
    try testing.expectEqual(@as(u8, 0), mapper.irq_counter);
    try testing.expectEqual(false, mapper.irq_reload);
    try testing.expectEqual(false, mapper.irq_enabled);
    try testing.expectEqual(false, mapper.irq_pending);
}

test "Mapper4: Bank select register" {
    var mapper = Mapper4{};

    // Write to $8000: bank select = 3, PRG mode = 1, CHR mode = 1
    mapper.bank_select = @truncate(0xC3 & 0x07);
    mapper.prg_mode = (0xC3 & 0x40) != 0;
    mapper.chr_mode = (0xC3 & 0x80) != 0;

    try testing.expectEqual(@as(u3, 3), mapper.bank_select);
    try testing.expectEqual(true, mapper.prg_mode);
    try testing.expectEqual(true, mapper.chr_mode);
}

test "Mapper4: Bank data registers" {
    var mapper = Mapper4{};

    // Set CHR banks (R0-R5)
    mapper.bank_select = 0;
    mapper.chr_banks[0] = 0x10;

    mapper.bank_select = 1;
    mapper.chr_banks[1] = 0x12;

    mapper.bank_select = 2;
    mapper.chr_banks[2] = 0x14;

    // Set PRG banks (R6-R7)
    mapper.bank_select = 6;
    mapper.prg_banks[0] = 0x05 & 0x3F;

    mapper.bank_select = 7;
    mapper.prg_banks[1] = 0x06 & 0x3F;

    try testing.expectEqual(@as(u8, 0x10), mapper.chr_banks[0]);
    try testing.expectEqual(@as(u8, 0x12), mapper.chr_banks[1]);
    try testing.expectEqual(@as(u8, 0x14), mapper.chr_banks[2]);
    try testing.expectEqual(@as(u8, 0x05), mapper.prg_banks[0]);
    try testing.expectEqual(@as(u8, 0x06), mapper.prg_banks[1]);
}

test "Mapper4: PRG RAM protect" {
    var mapper = Mapper4{};

    // Disable PRG RAM
    mapper.prg_ram_enabled = (0x00 & 0x80) != 0;
    mapper.prg_ram_write_protected = (0x00 & 0x40) != 0;
    try testing.expectEqual(false, mapper.prg_ram_enabled);
    try testing.expectEqual(false, mapper.prg_ram_write_protected);

    // Enable PRG RAM, write protect
    mapper.prg_ram_enabled = (0xC0 & 0x80) != 0;
    mapper.prg_ram_write_protected = (0xC0 & 0x40) != 0;
    try testing.expectEqual(true, mapper.prg_ram_enabled);
    try testing.expectEqual(true, mapper.prg_ram_write_protected);
}

test "Mapper4: IRQ latch and reload" {
    var mapper = Mapper4{};

    // Set IRQ latch
    mapper.irq_latch = 0x08;
    try testing.expectEqual(@as(u8, 0x08), mapper.irq_latch);

    // Reload counter
    mapper.irq_counter = 0;
    mapper.irq_reload = true;
    try testing.expectEqual(@as(u8, 0), mapper.irq_counter);
    try testing.expectEqual(true, mapper.irq_reload);
}

test "Mapper4: IRQ enable/disable" {
    var mapper = Mapper4{};

    // Enable IRQ
    mapper.irq_enabled = true;
    try testing.expectEqual(true, mapper.irq_enabled);

    // Disable IRQ
    mapper.irq_enabled = false;
    mapper.irq_pending = false;
    try testing.expectEqual(false, mapper.irq_enabled);
    try testing.expectEqual(false, mapper.irq_pending);
}

test "Mapper4: A12 rising edge counter" {
    var mapper = Mapper4{};

    // Setup: latch = 3, enable IRQ
    mapper.irq_latch = 3;
    mapper.irq_enabled = true;
    mapper.irq_reload = true;

    // First A12 rise: reload counter from latch
    mapper.ppuA12Rising();
    try testing.expectEqual(@as(u8, 3), mapper.irq_counter);
    try testing.expectEqual(false, mapper.irq_reload);
    try testing.expectEqual(false, mapper.irq_pending);

    // Second A12 rise: decrement to 2
    mapper.ppuA12Rising();
    try testing.expectEqual(@as(u8, 2), mapper.irq_counter);
    try testing.expectEqual(false, mapper.irq_pending);

    // Third A12 rise: decrement to 1
    mapper.ppuA12Rising();
    try testing.expectEqual(@as(u8, 1), mapper.irq_counter);
    try testing.expectEqual(false, mapper.irq_pending);

    // Fourth A12 rise: decrement to 0, trigger IRQ
    mapper.ppuA12Rising();
    try testing.expectEqual(@as(u8, 0), mapper.irq_counter);
    try testing.expectEqual(true, mapper.irq_pending);

    // Acknowledge IRQ
    mapper.acknowledgeIrq();
    try testing.expectEqual(false, mapper.irq_pending);
}

test "Mapper4: IRQ disabled doesn't trigger" {
    var mapper = Mapper4{};

    // Setup: latch = 0, IRQ disabled
    mapper.irq_latch = 0;
    mapper.irq_enabled = false;
    mapper.irq_reload = true;

    // A12 rise should reload but not trigger IRQ
    mapper.ppuA12Rising();
    try testing.expectEqual(@as(u8, 0), mapper.irq_counter);
    try testing.expectEqual(false, mapper.irq_pending);

    // Another A12 rise
    mapper.ppuA12Rising();
    try testing.expectEqual(false, mapper.irq_pending);
}

test "Mapper4: Reset clears state" {
    var mapper = Mapper4{};

    // Set some state
    mapper.bank_select = 5;
    mapper.prg_mode = true;
    mapper.chr_mode = true;
    mapper.irq_enabled = true;
    mapper.irq_pending = true;
    mapper.irq_counter = 42;

    // Reset (pass dummy cart parameter)
    const dummy_cart = undefined;
    mapper.reset(dummy_cart);

    try testing.expectEqual(@as(u3, 0), mapper.bank_select);
    try testing.expectEqual(false, mapper.prg_mode);
    try testing.expectEqual(false, mapper.chr_mode);
    try testing.expectEqual(false, mapper.irq_enabled);
    try testing.expectEqual(false, mapper.irq_pending);
    try testing.expectEqual(@as(u8, 0), mapper.irq_counter);
}

test "Mapper4: CHR Mode 0 bank mapping" {
    var mapper = Mapper4{};
    mapper.chr_mode = false; // Mode 0

    // Setup registers
    mapper.chr_banks[0] = 0x10; // R0
    mapper.chr_banks[1] = 0x20; // R1
    mapper.chr_banks[2] = 0x30; // R2
    mapper.chr_banks[3] = 0x40; // R3
    mapper.chr_banks[4] = 0x50; // R4
    mapper.chr_banks[5] = 0x60; // R5

    // R0 at $0000-$07FF (2KB bank)
    try testing.expectEqual(@as(u8, 0x10), mapper.getChrBank(0x0000)); // Even
    try testing.expectEqual(@as(u8, 0x11), mapper.getChrBank(0x0400)); // Odd

    // R1 at $0800-$0FFF (2KB bank)
    try testing.expectEqual(@as(u8, 0x20), mapper.getChrBank(0x0800)); // Even
    try testing.expectEqual(@as(u8, 0x21), mapper.getChrBank(0x0C00)); // Odd

    // R2-R5 at $1000-$1FFF (1KB banks)
    try testing.expectEqual(@as(u8, 0x30), mapper.getChrBank(0x1000)); // R2
    try testing.expectEqual(@as(u8, 0x40), mapper.getChrBank(0x1400)); // R3
    try testing.expectEqual(@as(u8, 0x50), mapper.getChrBank(0x1800)); // R4
    try testing.expectEqual(@as(u8, 0x60), mapper.getChrBank(0x1C00)); // R5
}

test "Mapper4: CHR Mode 1 bank mapping" {
    var mapper = Mapper4{};
    mapper.chr_mode = true; // Mode 1

    // Setup registers
    mapper.chr_banks[0] = 0x10; // R0
    mapper.chr_banks[1] = 0x20; // R1
    mapper.chr_banks[2] = 0x30; // R2
    mapper.chr_banks[3] = 0x40; // R3
    mapper.chr_banks[4] = 0x50; // R4
    mapper.chr_banks[5] = 0x60; // R5

    // R2-R5 at $0000-$0FFF (1KB banks)
    try testing.expectEqual(@as(u8, 0x30), mapper.getChrBank(0x0000)); // R2
    try testing.expectEqual(@as(u8, 0x40), mapper.getChrBank(0x0400)); // R3
    try testing.expectEqual(@as(u8, 0x50), mapper.getChrBank(0x0800)); // R4
    try testing.expectEqual(@as(u8, 0x60), mapper.getChrBank(0x0C00)); // R5

    // R0 at $1000-$17FF (2KB bank)
    try testing.expectEqual(@as(u8, 0x10), mapper.getChrBank(0x1000)); // Even
    try testing.expectEqual(@as(u8, 0x11), mapper.getChrBank(0x1400)); // Odd

    // R1 at $1800-$1FFF (2KB bank)
    try testing.expectEqual(@as(u8, 0x20), mapper.getChrBank(0x1800)); // Even
    try testing.expectEqual(@as(u8, 0x21), mapper.getChrBank(0x1C00)); // Odd
}

test "Mapper4: CHR 2KB bank bit masking" {
    var mapper = Mapper4{};
    mapper.chr_mode = false; // Mode 0

    // R0/R1 should ignore bit 0 (2KB banks use even addresses)
    mapper.chr_banks[0] = 0xFF; // Odd value
    mapper.chr_banks[1] = 0x55; // Odd value

    // First 1KB of R0 should be 0xFE (bit 0 cleared)
    try testing.expectEqual(@as(u8, 0xFE), mapper.getChrBank(0x0000));

    // Second 1KB of R0 should be 0xFF (bit 0 set)
    try testing.expectEqual(@as(u8, 0xFF), mapper.getChrBank(0x0400));

    // First 1KB of R1 should be 0x54 (bit 0 cleared)
    try testing.expectEqual(@as(u8, 0x54), mapper.getChrBank(0x0800));

    // Second 1KB of R1 should be 0x55 (bit 0 set)
    try testing.expectEqual(@as(u8, 0x55), mapper.getChrBank(0x0C00));
}

test "Mapper4: IRQ enable does NOT clear pending flag" {
    // Per nesdev.org, writing to $E001 (IRQ enable) enables IRQ generation
    // but does NOT acknowledge pending IRQs. Only $E000 (disable) acknowledges.
    // Reference: https://www.nesdev.org/wiki/MMC3#IRQ_Enable_.28.24E001.29
    var mapper = Mapper4{};
    const mock_cart = struct {
        prg_rom: []const u8 = &[_]u8{},
        prg_ram: ?[]u8 = null,
        chr_data: []u8 = &[_]u8{},
        header: struct {
            chr_rom_banks: u8 = 0,
        } = .{},
    }{};

    // Setup: Trigger an IRQ
    mapper.irq_latch = 0;
    mapper.irq_enabled = true;
    mapper.irq_reload = true;
    mapper.ppuA12Rising(); // Counter = 0
    mapper.ppuA12Rising(); // Counter decrements to 0, triggers IRQ
    try testing.expectEqual(true, mapper.irq_pending);

    // Write to $E001 (IRQ enable) - should NOT clear pending flag
    mapper.cpuWrite(mock_cart, 0xE001, 0x00);

    // Verify: IRQ pending flag remains set, IRQ enabled
    try testing.expectEqual(true, mapper.irq_pending);
    try testing.expectEqual(true, mapper.irq_enabled);
}

test "Mapper4: IRQ disable clears pending flag" {
    // Verify that $E000 (IRQ disable) clears pending flag.
    // This should already be working per line 123.
    var mapper = Mapper4{};
    const mock_cart = struct {
        prg_rom: []const u8 = &[_]u8{},
        prg_ram: ?[]u8 = null,
        chr_data: []u8 = &[_]u8{},
        header: struct {
            chr_rom_banks: u8 = 0,
        } = .{},
    }{};

    // Setup: Trigger an IRQ
    mapper.irq_latch = 0;
    mapper.irq_enabled = true;
    mapper.irq_reload = true;
    mapper.ppuA12Rising(); // Counter = 0
    mapper.ppuA12Rising(); // Counter decrements to 0, triggers IRQ
    try testing.expectEqual(true, mapper.irq_pending);

    // Write to $E000 (IRQ disable) - should clear pending flag
    mapper.cpuWrite(mock_cart, 0xE000, 0x00);

    // Verify: IRQ pending flag is cleared and IRQ is disabled
    try testing.expectEqual(false, mapper.irq_pending);
    try testing.expectEqual(false, mapper.irq_enabled);
}

test "Mapper4: CHR bank wraps to available size" {
    // Verify that CHR bank indices wrap modulo available CHR size
    var mapper = Mapper4{};
    mapper.chr_mode = true; // 1KB banks at $0000-$0FFF

    // Dummy cart with 2KB CHR (2 banks of 1KB)
    var chr_buf: [0x800]u8 = undefined;
    for (&chr_buf, 0..) |*b, i| b.* = @truncate(i);

    const mock_cart = struct {
        prg_rom: []const u8 = &[_]u8{},
        prg_ram: ?[]u8 = null,
        chr_data: []u8,
        header: struct { chr_rom_banks: u8 = 1 } = .{},
    }{ .chr_data = chr_buf[0..] };

    // Set R2 (used at $0000 in mode 1) to a large out-of-range bank value
    mapper.chr_banks[2] = 0x1F; // raw value 31 → should wrap to bank 1 (since only 2 banks)

    // Read from $0000 (maps to R2 in mode 1)
    const addr: u16 = 0x0000;
    const value = mapper.ppuRead(mock_cart, addr);

    // Expect value from bank 1 offset 0
    const expected: u8 = chr_buf[1 * 0x400 + 0];
    try testing.expectEqual(expected, value);
}
