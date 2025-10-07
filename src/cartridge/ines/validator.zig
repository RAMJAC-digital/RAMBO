// iNES ROM Format Validator
//
// Comprehensive validation beyond basic parsing.
// Checks header consistency, reserved bytes, mapper compatibility, etc.

const std = @import("std");
const types = @import("types.zig");
const errors = @import("errors.zig");

const InesHeader = types.InesHeader;
const Rom = types.Rom;
const Format = types.Format;
const InesError = errors.InesError;

/// Validation warning (non-fatal issue)
pub const ValidationWarning = struct {
    message: []const u8,
    severity: Severity,

    pub const Severity = enum {
        minor, // Cosmetic issue, ROM likely works
        moderate, // May affect compatibility
        severe, // Likely to cause issues
    };
};

/// Complete validation result
pub const ValidationResult = struct {
    valid: bool,
    errors: std.ArrayList(InesError),
    warnings: std.ArrayList(ValidationWarning),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ValidationResult {
        return .{
            .valid = true,
            .errors = std.ArrayList(InesError){},
            .warnings = std.ArrayList(ValidationWarning){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ValidationResult) void {
        self.errors.deinit(self.allocator);
        self.warnings.deinit(self.allocator);
    }

    pub fn addError(self: *ValidationResult, err: InesError) !void {
        self.valid = false;
        try self.errors.append(self.allocator, err);
    }

    pub fn addWarning(self: *ValidationResult, message: []const u8, severity: ValidationWarning.Severity) !void {
        try self.warnings.append(self.allocator, .{
            .message = message,
            .severity = severity,
        });
    }
};

/// Validate iNES header
///
/// Performs comprehensive checks beyond basic parsing.
///
/// Parameters:
///   - allocator: Allocator for validation result lists
///   - header: Parsed iNES header
///
/// Returns: Validation result with errors and warnings
pub fn validateHeader(allocator: std.mem.Allocator, header: *const InesHeader) !ValidationResult {
    var result = ValidationResult.init(allocator);
    errdefer result.deinit();

    // Check magic bytes
    if (!header.isValid()) {
        try result.addError(InesError.InvalidMagic);
        return result; // Fatal - can't continue
    }

    // Check PRG ROM size
    if (header.prg_rom_banks == 0) {
        try result.addError(InesError.ZeroPrgRomSize);
    }

    const prg_size = header.getPrgRomSize();
    if (prg_size > 32 * 1024 * 1024) {
        try result.addError(InesError.PrgRomSizeTooLarge);
    }

    // Check format-specific constraints
    const format = header.getFormat();
    switch (format) {
        .ines_1_0 => try validateInes1(allocator, header, &result),
        .nes_2_0 => try validateNes2(allocator, header, &result),
        .archaic => try result.addWarning("Archaic iNES format (pre-1.0)", .moderate),
    }

    // Check mapper number
    const mapper = header.getMapperNumber();
    if (mapper > 255 and format == .ines_1_0) {
        try result.addError(InesError.InvalidMapperNumber);
    }

    // Check reserved bytes (iNES 1.0)
    if (format == .ines_1_0) {
        const has_nonzero_padding = (header.padding0 != 0 or
            header.padding1 != 0 or
            header.padding2 != 0 or
            header.padding3 != 0 or
            header.padding4 != 0);

        if (has_nonzero_padding) {
            try result.addWarning("Reserved bytes contain non-zero values", .minor);
        }
    }

    return result;
}

/// Validate complete ROM structure
///
/// Checks data integrity, size consistency, and configuration validity.
///
/// Parameters:
///   - allocator: Allocator for validation result lists
///   - rom: Parsed ROM structure
///
/// Returns: Validation result with errors and warnings
pub fn validateRom(allocator: std.mem.Allocator, rom: *const Rom) !ValidationResult {
    var result = ValidationResult.init(allocator);
    errdefer result.deinit();

    // Validate PRG ROM
    if (rom.prg_rom.len == 0) {
        try result.addError(InesError.ZeroPrgRomSize);
    }

    if (rom.prg_rom.len != rom.header.getPrgRomSize()) {
        try result.addError(InesError.FileSizeMismatch);
    }

    // Validate CHR ROM/RAM
    const expected_chr_size = rom.header.getChrRomSize();
    if (rom.chr_is_ram) {
        if (expected_chr_size != 0) {
            try result.addWarning("CHR RAM specified but header indicates CHR ROM", .moderate);
        }
    } else {
        if (rom.chr_rom.len != expected_chr_size) {
            try result.addError(InesError.FileSizeMismatch);
        }
    }

    // Validate trainer
    if (rom.header.hasTrainer()) {
        if (rom.trainer == null) {
            try result.addError(InesError.MissingTrainer);
        } else if (rom.trainer.?.len != 512) {
            try result.addError(InesError.InvalidTrainerSize);
        }
    }

    // Validate mapper compatibility
    if (rom.mapper_number > 255) {
        if (rom.format != .nes_2_0) {
            try result.addError(InesError.InvalidMapperNumber);
        }
    }

    // Check for common misconfigurations
    if (rom.mirroring == .four_screen and rom.mapper_number == 0) {
        try result.addWarning("Four-screen mirroring specified for Mapper 0 (NROM)", .severe);
    }

    return result;
}

/// Validate iNES 1.0 specific constraints
fn validateInes1(allocator: std.mem.Allocator, header: *const InesHeader, result: *ValidationResult) !void {
    _ = allocator;

    // Check flags 9 reserved bits
    if (header.flags9.reserved != 0) {
        try result.addWarning("Flags 9 reserved bits are non-zero", .minor);
    }

    // Check byte 8 (should be PRG RAM size, often zero)
    if (header.byte8 > 16) {
        try result.addWarning("Byte 8 (PRG RAM size) unusually large", .moderate);
    }
}

/// Validate NES 2.0 specific constraints
fn validateNes2(allocator: std.mem.Allocator, header: *const InesHeader, result: *ValidationResult) !void {
    _ = allocator;

    // Verify NES 2.0 identifier (bits 2-3 of flags 7 = 0b10)
    if (!header.flags7.isNes2()) {
        try result.addError(InesError.InvalidNes2Identifier);
    }

    // Check submapper validity (mapper-specific, for now just warn if non-zero)
    const submapper = header.getSubmapper();
    if (submapper > 0) {
        try result.addWarning("NES 2.0 submapper specified", .minor);
    }
}

/// Quick validation check (returns boolean)
///
/// Fast path for basic "is this ROM valid?" checks.
///
/// Parameters:
///   - header: Parsed iNES header
///
/// Returns: true if valid, false otherwise
pub fn isValid(header: *const InesHeader) bool {
    // Check magic
    if (!header.isValid()) return false;

    // Check PRG ROM size
    if (header.prg_rom_banks == 0) return false;

    const prg_size = header.getPrgRomSize();
    if (prg_size == 0 or prg_size > 32 * 1024 * 1024) return false;

    return true;
}

/// Check if mapper is commonly supported
///
/// Returns true for well-known mappers (0-4, 7, 9, etc.)
///
/// Parameters:
///   - mapper_number: Mapper number to check
///
/// Returns: true if mapper is common, false otherwise
pub fn isCommonMapper(mapper_number: u12) bool {
    return switch (mapper_number) {
        0, // NROM
        1, // MMC1
        2, // UxROM
        3, // CNROM
        4, // MMC3
        7, // AxROM
        9, // MMC2
        10, // MMC4
        11, // Color Dreams
        66, // GxROM
        => true,
        else => false,
    };
}

/// Get mapper name for common mappers
///
/// Returns mapper name or "Unknown" for unsupported mappers.
///
/// Parameters:
///   - mapper_number: Mapper number
///
/// Returns: Mapper name string
pub fn getMapperName(mapper_number: u12) []const u8 {
    return switch (mapper_number) {
        0 => "NROM",
        1 => "MMC1",
        2 => "UxROM",
        3 => "CNROM",
        4 => "MMC3",
        7 => "AxROM",
        9 => "MMC2",
        10 => "MMC4",
        11 => "Color Dreams",
        66 => "GxROM",
        else => "Unknown",
    };
}
