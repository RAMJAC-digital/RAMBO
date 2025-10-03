//! iNES ROM Format Parser
//!
//! Implements parsing and validation of the iNES ROM file format (.nes files).
//! See: https://www.nesdev.org/wiki/INES
//!
//! Format: 16-byte header + optional trainer (512 bytes) + PRG ROM + CHR ROM
//!
//! This is the primary format for NES ROM distribution and is supported by
//! virtually all NES emulators.

const std = @import("std");

/// iNES format errors
pub const InesError = error{
    InvalidMagic,
    FileTooSmall,
    InvalidPrgSize,
    InvalidChrSize,
    UnsupportedMapper,
    TrainerNotSupported,
};

/// Mirroring mode for nametables
pub const Mirroring = enum(u2) {
    horizontal = 0,
    vertical = 1,
    four_screen = 2,
};

/// iNES file header (16 bytes)
/// Byte order: Little-endian
pub const InesHeader = struct {
    /// Magic number: "NES\x1A"
    magic: [4]u8,

    /// PRG ROM size in 16KB units
    /// Actual size = prg_rom_size * 16384 bytes
    prg_rom_size: u8,

    /// CHR ROM size in 8KB units
    /// 0 = CHR RAM (8KB of RAM instead of ROM)
    /// Actual size = chr_rom_size * 8192 bytes
    chr_rom_size: u8,

    /// Flags 6: Mapper low nibble, mirroring, battery, trainer
    /// Bit 0: Mirroring (0 = horizontal, 1 = vertical)
    /// Bit 1: Battery-backed PRG RAM at $6000-$7FFF
    /// Bit 2: 512-byte trainer at $7000-$71FF
    /// Bit 3: Four-screen VRAM
    /// Bits 4-7: Lower nibble of mapper number
    flags6: u8,

    /// Flags 7: Mapper high nibble, VS/PlayChoice
    /// Bits 0-3: VS Unisystem/PlayChoice-10 (ignore for now)
    /// Bits 4-7: Upper nibble of mapper number
    flags7: u8,

    /// PRG RAM size in 8KB units (rarely used, usually 0 = infer 8KB if battery flag set)
    prg_ram_size: u8,

    /// TV system (flags 9)
    /// Bit 0: 0 = NTSC, 1 = PAL
    flags9: u8,

    /// TV system and PRG RAM presence (unofficial, rarely used)
    flags10: u8,

    /// Unused padding (should be zero, but often contains garbage)
    padding: [5]u8,

    /// Parse iNES header from raw bytes
    /// Validates magic number and basic structure
    pub fn parse(data: []const u8) InesError!InesHeader {
        if (data.len < 16) {
            return InesError.FileTooSmall;
        }

        const header = InesHeader{
            .magic = data[0..4].*,
            .prg_rom_size = data[4],
            .chr_rom_size = data[5],
            .flags6 = data[6],
            .flags7 = data[7],
            .prg_ram_size = data[8],
            .flags9 = data[9],
            .flags10 = data[10],
            .padding = data[11..16].*,
        };

        try header.validate();
        return header;
    }

    /// Validate header integrity
    pub fn validate(self: *const InesHeader) InesError!void {
        // Check magic number "NES\x1A"
        if (self.magic[0] != 'N' or
            self.magic[1] != 'E' or
            self.magic[2] != 'S' or
            self.magic[3] != 0x1A)
        {
            return InesError.InvalidMagic;
        }

        // PRG ROM must exist (at least 1 unit = 16KB)
        if (self.prg_rom_size == 0) {
            return InesError.InvalidPrgSize;
        }

        // CHR can be 0 (CHR RAM), but if present must be valid
        // Note: CHR size of 0 means 8KB CHR RAM, not an error
    }

    /// Get mapper number (0-255)
    /// Lower nibble from flags6[4:7], upper nibble from flags7[4:7]
    pub inline fn getMapperNumber(self: *const InesHeader) u8 {
        const lower = (self.flags6 >> 4) & 0x0F;
        const upper = (self.flags7 >> 4) & 0x0F;
        return (upper << 4) | lower;
    }

    /// Get mirroring mode
    pub inline fn getMirroring(self: *const InesHeader) Mirroring {
        if ((self.flags6 & 0x08) != 0) {
            // Four-screen VRAM
            return .four_screen;
        }

        if ((self.flags6 & 0x01) != 0) {
            return .vertical;
        }

        return .horizontal;
    }

    /// Check if cartridge has battery-backed RAM
    pub inline fn hasBatteryRam(self: *const InesHeader) bool {
        return (self.flags6 & 0x02) != 0;
    }

    /// Check if ROM has 512-byte trainer at $7000-$71FF
    pub inline fn hasTrainer(self: *const InesHeader) bool {
        return (self.flags6 & 0x04) != 0;
    }

    /// Get PRG ROM size in bytes
    pub inline fn getPrgRomSize(self: *const InesHeader) usize {
        return @as(usize, self.prg_rom_size) * 16384;
    }

    /// Get CHR ROM size in bytes
    /// Returns 0 if CHR RAM should be used instead
    pub inline fn getChrRomSize(self: *const InesHeader) usize {
        return @as(usize, self.chr_rom_size) * 8192;
    }

    /// Get PRG RAM size in bytes (defaults to 8KB if not specified)
    pub inline fn getPrgRamSize(self: *const InesHeader) usize {
        if (self.prg_ram_size == 0) {
            // Default: 8KB if battery flag set, otherwise 0
            return if (self.hasBatteryRam()) 8192 else 0;
        }
        return @as(usize, self.prg_ram_size) * 8192;
    }

    /// Check if this is NTSC (false = NTSC, true = PAL)
    pub inline fn isPal(self: *const InesHeader) bool {
        return (self.flags9 & 0x01) != 0;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "InesHeader: parse valid header" {
    const valid_header = [_]u8{
        'N', 'E', 'S', 0x1A, // Magic
        0x02, // 2 x 16KB PRG ROM (32KB)
        0x01, // 1 x 8KB CHR ROM
        0x00, // Flags 6: horizontal mirroring, no battery, no trainer, mapper 0 (low)
        0x00, // Flags 7: mapper 0 (high)
        0x00, // PRG RAM size
        0x00, // Flags 9: NTSC
        0x00, // Flags 10
        0x00, 0x00, 0x00, 0x00, 0x00, // Padding
    };

    const header = try InesHeader.parse(&valid_header);
    try testing.expectEqual(@as(u8, 0x02), header.prg_rom_size);
    try testing.expectEqual(@as(u8, 0x01), header.chr_rom_size);
}

test "InesHeader: invalid magic" {
    const invalid_header = [_]u8{
        'X', 'X', 'X', 0x1A, // Bad magic
        0x02, 0x01, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
    };

    const result = InesHeader.parse(&invalid_header);
    try testing.expectError(InesError.InvalidMagic, result);
}

test "InesHeader: file too small" {
    const small_file = [_]u8{ 'N', 'E', 'S' }; // Only 3 bytes
    const result = InesHeader.parse(&small_file);
    try testing.expectError(InesError.FileTooSmall, result);
}

test "InesHeader: mapper number extraction" {
    var header = InesHeader{
        .magic = [_]u8{ 'N', 'E', 'S', 0x1A },
        .prg_rom_size = 1,
        .chr_rom_size = 1,
        .flags6 = 0x10, // Mapper low nibble = 1
        .flags7 = 0x00, // Mapper high nibble = 0
        .prg_ram_size = 0,
        .flags9 = 0,
        .flags10 = 0,
        .padding = [_]u8{0} ** 5,
    };

    try testing.expectEqual(@as(u8, 1), header.getMapperNumber());

    // Test mapper 4 (MMC3)
    header.flags6 = 0x40; // Lower nibble = 4
    header.flags7 = 0x00; // Upper nibble = 0
    try testing.expectEqual(@as(u8, 4), header.getMapperNumber());

    // Test mapper 255 (max)
    header.flags6 = 0xF0; // Lower nibble = F
    header.flags7 = 0xF0; // Upper nibble = F
    try testing.expectEqual(@as(u8, 255), header.getMapperNumber());
}

test "InesHeader: mirroring modes" {
    var header = InesHeader{
        .magic = [_]u8{ 'N', 'E', 'S', 0x1A },
        .prg_rom_size = 1,
        .chr_rom_size = 1,
        .flags6 = 0x00, // Horizontal
        .flags7 = 0x00,
        .prg_ram_size = 0,
        .flags9 = 0,
        .flags10 = 0,
        .padding = [_]u8{0} ** 5,
    };

    try testing.expectEqual(Mirroring.horizontal, header.getMirroring());

    header.flags6 = 0x01; // Vertical
    try testing.expectEqual(Mirroring.vertical, header.getMirroring());

    header.flags6 = 0x08; // Four-screen
    try testing.expectEqual(Mirroring.four_screen, header.getMirroring());

    header.flags6 = 0x09; // Four-screen takes precedence
    try testing.expectEqual(Mirroring.four_screen, header.getMirroring());
}

test "InesHeader: battery and trainer flags" {
    var header = InesHeader{
        .magic = [_]u8{ 'N', 'E', 'S', 0x1A },
        .prg_rom_size = 1,
        .chr_rom_size = 1,
        .flags6 = 0x00,
        .flags7 = 0x00,
        .prg_ram_size = 0,
        .flags9 = 0,
        .flags10 = 0,
        .padding = [_]u8{0} ** 5,
    };

    try testing.expect(!header.hasBatteryRam());
    try testing.expect(!header.hasTrainer());

    header.flags6 = 0x02; // Battery
    try testing.expect(header.hasBatteryRam());
    try testing.expect(!header.hasTrainer());

    header.flags6 = 0x04; // Trainer
    try testing.expect(!header.hasBatteryRam());
    try testing.expect(header.hasTrainer());

    header.flags6 = 0x06; // Both
    try testing.expect(header.hasBatteryRam());
    try testing.expect(header.hasTrainer());
}

test "InesHeader: size calculations" {
    const header = InesHeader{
        .magic = [_]u8{ 'N', 'E', 'S', 0x1A },
        .prg_rom_size = 2, // 2 x 16KB = 32KB
        .chr_rom_size = 1, // 1 x 8KB = 8KB
        .flags6 = 0x00,
        .flags7 = 0x00,
        .prg_ram_size = 0,
        .flags9 = 0,
        .flags10 = 0,
        .padding = [_]u8{0} ** 5,
    };

    try testing.expectEqual(@as(usize, 32768), header.getPrgRomSize());
    try testing.expectEqual(@as(usize, 8192), header.getChrRomSize());
}

test "InesHeader: CHR RAM detection" {
    const header = InesHeader{
        .magic = [_]u8{ 'N', 'E', 'S', 0x1A },
        .prg_rom_size = 1,
        .chr_rom_size = 0, // 0 = CHR RAM
        .flags6 = 0x00,
        .flags7 = 0x00,
        .prg_ram_size = 0,
        .flags9 = 0,
        .flags10 = 0,
        .padding = [_]u8{0} ** 5,
    };

    try testing.expectEqual(@as(usize, 0), header.getChrRomSize());
}

test "InesHeader: AccuracyCoin.nes format" {
    // Actual header from AccuracyCoin.nes
    const accuracycoin_header = [_]u8{
        'N', 'E', 'S', 0x1A, // Magic
        0x02, // 2 x 16KB PRG ROM (32KB)
        0x01, // 1 x 8KB CHR ROM
        0x00, // Horizontal mirroring, mapper 0
        0x00, // Mapper 0
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
    };

    const header = try InesHeader.parse(&accuracycoin_header);

    try testing.expectEqual(@as(u8, 0), header.getMapperNumber());
    try testing.expectEqual(Mirroring.horizontal, header.getMirroring());
    try testing.expectEqual(@as(usize, 32768), header.getPrgRomSize());
    try testing.expectEqual(@as(usize, 8192), header.getChrRomSize());
    try testing.expect(!header.hasBatteryRam());
    try testing.expect(!header.hasTrainer());
    try testing.expect(!header.isPal());
}
