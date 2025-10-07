// iNES ROM Format Data Structures
//
// Concrete type definitions for iNES 1.0 and NES 2.0 formats.
// All types are explicitly defined - NO anytype usage.
// Designed for zero-copy parsing where possible.

const std = @import("std");

/// iNES format version
pub const Format = enum(u8) {
    /// Original iNES 1.0 format (most common)
    ines_1_0 = 0,
    /// NES 2.0 format (extended features)
    nes_2_0 = 2,
    /// Archaic iNES format (pre-1.0, rare)
    archaic = 1,

    pub fn toString(self: Format) []const u8 {
        return switch (self) {
            .ines_1_0 => "iNES 1.0",
            .nes_2_0 => "NES 2.0",
            .archaic => "Archaic iNES",
        };
    }
};

/// Nametable mirroring mode
pub const MirroringMode = enum(u2) {
    /// Horizontal mirroring (vertical arrangement)
    horizontal = 0,
    /// Vertical mirroring (horizontal arrangement)
    vertical = 1,
    /// Four-screen VRAM (cartridge provides extra 2KB)
    four_screen = 2,
    /// Single-screen mirroring (mapper-controlled)
    single_screen = 3,

    pub fn toString(self: MirroringMode) []const u8 {
        return switch (self) {
            .horizontal => "Horizontal",
            .vertical => "Vertical",
            .four_screen => "Four-Screen",
            .single_screen => "Single-Screen",
        };
    }
};

/// Console region/timing mode
pub const Region = enum(u2) {
    /// NTSC (North America, Japan) - 60 Hz
    ntsc = 0,
    /// PAL (Europe, Australia) - 50 Hz
    pal = 1,
    /// Dual-compatible (both NTSC and PAL)
    dual = 2,
    /// Dendy (Russia) - PAL variant
    dendy = 3,

    pub fn toString(self: Region) []const u8 {
        return switch (self) {
            .ntsc => "NTSC",
            .pal => "PAL",
            .dual => "Dual (NTSC/PAL)",
            .dendy => "Dendy",
        };
    }
};

/// Console type for NES 2.0
pub const ConsoleType = enum(u2) {
    /// Standard NES/Famicom
    nes = 0,
    /// Nintendo Vs. System
    vs_system = 1,
    /// Nintendo Playchoice 10
    playchoice = 2,
    /// Extended console type (see byte 13)
    extended = 3,

    pub fn toString(self: ConsoleType) []const u8 {
        return switch (self) {
            .nes => "NES/Famicom",
            .vs_system => "Vs. System",
            .playchoice => "Playchoice 10",
            .extended => "Extended",
        };
    }
};

/// iNES header flags 6 (byte 6)
pub const Flags6 = packed struct(u8) {
    /// Mirroring mode (0 = horizontal, 1 = vertical)
    mirroring: bool,
    /// Battery-backed PRG RAM present
    battery: bool,
    /// 512-byte trainer present
    trainer: bool,
    /// Four-screen VRAM (overrides mirroring bit)
    four_screen: bool,
    /// Lower 4 bits of mapper number
    mapper_low: u4,

    pub fn getMirroring(self: Flags6) MirroringMode {
        if (self.four_screen) return .four_screen;
        return if (self.mirroring) .vertical else .horizontal;
    }
};

/// iNES header flags 7 (byte 7)
pub const Flags7 = packed struct(u8) {
    /// VS Unisystem
    vs_unisystem: bool,
    /// PlayChoice-10 (8KB of hint screen data after CHR)
    playchoice: bool,
    /// NES 2.0 format identifier (bits 2-3 = 0b10)
    format_id: u2,
    /// Upper 4 bits of mapper number
    mapper_high: u4,

    pub fn isNes2(self: Flags7) bool {
        return self.format_id == 0b10;
    }

    pub fn getFormat(self: Flags7) Format {
        return switch (self.format_id) {
            0b10 => .nes_2_0,
            0b00 => .ines_1_0,
            else => .archaic,
        };
    }
};

/// iNES header flags 9 (byte 9) - TV system for iNES 1.0
pub const Flags9 = packed struct(u8) {
    /// TV system (0 = NTSC, 1 = PAL)
    tv_system: bool,
    /// Reserved (should be zero)
    reserved: u7,

    pub fn getRegion(self: Flags9) Region {
        return if (self.tv_system) .pal else .ntsc;
    }
};

/// iNES header flags 10 (byte 10) - unofficial, rarely used
pub const Flags10 = packed struct(u8) {
    /// TV system (0 = NTSC, 1 = PAL, 2 = dual, 3 = Dendy)
    tv_system: u2,
    /// Reserved (should be zero)
    reserved_1: u2,
    /// PRG RAM present (unofficial)
    prg_ram: bool,
    /// Bus conflicts (unofficial)
    bus_conflicts: bool,
    /// Reserved (should be zero)
    reserved_2: u2,
};

/// Complete 16-byte iNES header
pub const InesHeader = packed struct(u128) {
    /// Magic bytes: "NES\x1A"
    magic0: u8,
    magic1: u8,
    magic2: u8,
    magic3: u8,
    /// PRG ROM size in 16KB units
    prg_rom_banks: u8,
    /// CHR ROM size in 8KB units (0 = CHR RAM)
    chr_rom_banks: u8,
    /// Flags 6
    flags6: Flags6,
    /// Flags 7
    flags7: Flags7,
    /// Mapper variant / PRG RAM size (NES 2.0: submapper / PRG RAM, iNES: PRG RAM)
    byte8: u8,
    /// Flags 9 (TV system)
    flags9: Flags9,
    /// Flags 10 (unofficial)
    flags10: Flags10,
    /// Padding bytes (should be zero)
    padding0: u8,
    padding1: u8,
    padding2: u8,
    padding3: u8,
    padding4: u8,

    /// Verify magic bytes
    pub fn isValid(self: *const InesHeader) bool {
        return self.magic0 == 'N' and
               self.magic1 == 'E' and
               self.magic2 == 'S' and
               self.magic3 == 0x1A;
    }

    /// Get format version
    pub fn getFormat(self: *const InesHeader) Format {
        return self.flags7.getFormat();
    }

    /// Get mapper number (8-bit for iNES 1.0, 12-bit for NES 2.0)
    pub fn getMapperNumber(self: *const InesHeader) u12 {
        const low: u12 = @as(u12, self.flags6.mapper_low);
        const high: u12 = @as(u12, self.flags7.mapper_high);

        if (self.getFormat() == .nes_2_0) {
            // NES 2.0: 12-bit mapper number (byte 8 bits 0-3 are upper 4 bits)
            const upper: u12 = @as(u12, self.byte8 & 0x0F);
            return (upper << 8) | (high << 4) | low;
        } else {
            // iNES 1.0: 8-bit mapper number
            return (high << 4) | low;
        }
    }

    /// Get submapper number (NES 2.0 only)
    pub fn getSubmapper(self: *const InesHeader) u4 {
        if (self.getFormat() == .nes_2_0) {
            return @truncate((self.byte8 >> 4) & 0x0F);
        }
        return 0;
    }

    /// Get PRG ROM size in bytes
    pub fn getPrgRomSize(self: *const InesHeader) u32 {
        if (self.getFormat() == .nes_2_0) {
            // NES 2.0: exponential notation if byte 9 high nibble is non-zero
            const exponent = (self.byte8 >> 4) & 0x0F;
            if (exponent != 0) {
                const multiplier: u32 = @as(u32, 1) << @truncate(exponent);
                const base: u32 = @as(u32, self.prg_rom_banks) * 2 + 1;
                return base * multiplier;
            }
        }
        // iNES 1.0 or NES 2.0 linear notation
        return @as(u32, self.prg_rom_banks) * 16384;
    }

    /// Get CHR ROM size in bytes (0 = CHR RAM)
    pub fn getChrRomSize(self: *const InesHeader) u32 {
        if (self.chr_rom_banks == 0) return 0;

        if (self.getFormat() == .nes_2_0) {
            // NES 2.0: similar exponential notation
            const exponent = (self.flags9.reserved >> 4) & 0x0F;
            if (exponent != 0) {
                const multiplier: u32 = @as(u32, 1) << @truncate(exponent);
                const base: u32 = @as(u32, self.chr_rom_banks) * 2 + 1;
                return base * multiplier;
            }
        }
        // iNES 1.0 or NES 2.0 linear notation
        return @as(u32, self.chr_rom_banks) * 8192;
    }

    /// Get mirroring mode
    pub fn getMirroring(self: *const InesHeader) MirroringMode {
        return self.flags6.getMirroring();
    }

    /// Check if trainer is present
    pub fn hasTrainer(self: *const InesHeader) bool {
        return self.flags6.trainer;
    }

    /// Check if battery-backed RAM is present
    pub fn hasBattery(self: *const InesHeader) bool {
        return self.flags6.battery;
    }

    /// Get region/timing mode
    pub fn getRegion(self: *const InesHeader) Region {
        if (self.getFormat() == .nes_2_0) {
            // NES 2.0: byte 12 bits 0-1 (padding2 is byte 12)
            return @enumFromInt(self.padding2 & 0x03);
        }
        // iNES 1.0: flags 9
        return self.flags9.getRegion();
    }

    /// Get console type (NES 2.0 only)
    pub fn getConsoleType(self: *const InesHeader) ConsoleType {
        if (self.getFormat() == .nes_2_0) {
            return @enumFromInt(self.flags7.format_id);
        }
        return .nes;
    }
};

// Compile-time verification that header is exactly 16 bytes
comptime {
    if (@sizeOf(InesHeader) != 16) {
        @compileError("InesHeader must be exactly 16 bytes");
    }
}

/// Mapper metadata (compile-time database)
pub const MapperInfo = struct {
    /// Mapper number
    number: u12,
    /// Mapper name
    name: []const u8,
    /// Whether mapper supports IRQ
    has_irq: bool,
    /// Whether mapper supports CHR RAM banking
    has_chr_ram: bool,
    /// Whether mapper supports PRG RAM
    has_prg_ram: bool,
};

/// Complete ROM structure (result of parsing)
pub const Rom = struct {
    /// Format version
    format: Format,
    /// Mapper number (8-bit iNES 1.0, 12-bit NES 2.0)
    mapper_number: u12,
    /// Submapper number (NES 2.0 only)
    submapper: u4,
    /// Mirroring mode
    mirroring: MirroringMode,
    /// Region/timing mode
    region: Region,
    /// Console type (NES 2.0)
    console_type: ConsoleType,
    /// Battery-backed save RAM present
    has_battery: bool,
    /// PRG ROM data (allocated, caller owns)
    prg_rom: []const u8,
    /// CHR ROM/RAM data (allocated, caller owns, may be empty for CHR RAM)
    chr_rom: []const u8,
    /// Trainer data (512 bytes if present, null otherwise)
    trainer: ?[]const u8,
    /// Whether CHR is RAM (true) or ROM (false)
    chr_is_ram: bool,
    /// Original header for debugging
    header: InesHeader,

    /// Free allocated ROM data
    pub fn deinit(self: *Rom, allocator: std.mem.Allocator) void {
        allocator.free(self.prg_rom);
        if (self.chr_rom.len > 0) {
            allocator.free(self.chr_rom);
        }
        if (self.trainer) |trainer| {
            allocator.free(trainer);
        }
    }

    /// Get PRG ROM size in bytes
    pub fn getPrgRomSize(self: *const Rom) usize {
        return self.prg_rom.len;
    }

    /// Get CHR data size in bytes
    pub fn getChrDataSize(self: *const Rom) usize {
        return self.chr_rom.len;
    }

    /// Check if ROM uses CHR RAM
    pub fn usesChrRam(self: *const Rom) bool {
        return self.chr_is_ram;
    }

    /// Get human-readable format string
    pub fn getFormatString(self: *const Rom) []const u8 {
        return self.format.toString();
    }

    /// Get human-readable mirroring string
    pub fn getMirroringString(self: *const Rom) []const u8 {
        return self.mirroring.toString();
    }

    /// Get human-readable region string
    pub fn getRegionString(self: *const Rom) []const u8 {
        return self.region.toString();
    }
};
