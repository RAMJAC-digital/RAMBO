// iNES ROM Format Parser (Stateless)
//
// Pure functional parser - no internal state, thread-safe.
// Takes raw file data, returns structured Rom or error.

const std = @import("std");
const types = @import("types.zig");
const errors = @import("errors.zig");

const InesHeader = types.InesHeader;
const Rom = types.Rom;
const Format = types.Format;
const InesError = errors.InesError;

/// Parse iNES ROM from raw file data
///
/// This is a pure function with no internal state. Thread-safe.
/// The caller owns all allocated memory (prg_rom, chr_rom, trainer).
///
/// Parameters:
///   - allocator: Memory allocator for ROM data
///   - file_data: Complete ROM file contents (must be at least 16 bytes)
///
/// Returns: Parsed Rom structure or error
///
/// Memory ownership: Caller must call Rom.deinit() to free memory
pub fn parse(
    allocator: std.mem.Allocator,
    file_data: []const u8,
) InesError!Rom {
    // === Phase 1: Header Parsing ===
    if (file_data.len < 16) {
        return InesError.FileTooSmall;
    }

    // Parse header (zero-copy via packed struct)
    const header: *const InesHeader = @ptrCast(@alignCast(file_data.ptr));

    // Verify magic bytes
    if (!header.isValid()) {
        return InesError.InvalidMagic;
    }

    // Extract format version
    const format = header.getFormat();

    // === Phase 2: Size Calculation ===
    const prg_rom_size = header.getPrgRomSize();
    const chr_rom_size = header.getChrRomSize();
    const has_trainer = header.hasTrainer();
    const trainer_size: usize = if (has_trainer) 512 else 0;

    // Validate PRG ROM size
    if (prg_rom_size == 0) {
        return InesError.ZeroPrgRomSize;
    }
    if (prg_rom_size > 32 * 1024 * 1024) { // 32 MB limit
        return InesError.PrgRomSizeTooLarge;
    }

    // Calculate expected file size
    const expected_size = 16 + trainer_size + prg_rom_size + chr_rom_size;
    if (file_data.len < expected_size) {
        return InesError.FileSizeMismatch;
    }

    // === Phase 3: Data Extraction ===
    var offset: usize = 16; // Start after header

    // Extract trainer (if present)
    var trainer: ?[]const u8 = null;
    if (has_trainer) {
        if (offset + 512 > file_data.len) {
            return InesError.MissingTrainer;
        }
        const trainer_data = try allocator.alloc(u8, 512);
        errdefer allocator.free(trainer_data);
        @memcpy(trainer_data, file_data[offset .. offset + 512]);
        trainer = trainer_data;
        offset += 512;
    }
    errdefer if (trainer) |t| allocator.free(t);

    // Extract PRG ROM
    if (offset + prg_rom_size > file_data.len) {
        return InesError.UnexpectedEof;
    }
    const prg_rom = try allocator.alloc(u8, prg_rom_size);
    errdefer allocator.free(prg_rom);
    @memcpy(prg_rom, file_data[offset .. offset + prg_rom_size]);
    offset += prg_rom_size;

    // Extract CHR ROM (if present, otherwise CHR RAM)
    const chr_is_ram = (chr_rom_size == 0);
    var chr_rom: []const u8 = &[_]u8{};

    if (!chr_is_ram) {
        if (offset + chr_rom_size > file_data.len) {
            return InesError.UnexpectedEof;
        }
        const chr_data = try allocator.alloc(u8, chr_rom_size);
        errdefer allocator.free(chr_data);
        @memcpy(chr_data, file_data[offset .. offset + chr_rom_size]);
        chr_rom = chr_data;
        offset += chr_rom_size;
    }
    errdefer if (chr_rom.len > 0) allocator.free(chr_rom);

    // === Phase 4: Metadata Extraction ===
    const mapper_number = header.getMapperNumber();
    const submapper = header.getSubmapper();
    const mirroring = header.getMirroring();
    const region = header.getRegion();
    const console_type = header.getConsoleType();
    const has_battery = header.hasBattery();

    // === Phase 5: ROM Structure Construction ===
    return Rom{
        .format = format,
        .mapper_number = mapper_number,
        .submapper = submapper,
        .mirroring = mirroring,
        .region = region,
        .console_type = console_type,
        .has_battery = has_battery,
        .prg_rom = prg_rom,
        .chr_rom = chr_rom,
        .trainer = trainer,
        .chr_is_ram = chr_is_ram,
        .header = header.*,
    };
}

/// Parse iNES header only (fast metadata extraction)
///
/// Useful for quickly inspecting ROM files without loading full data.
/// Does not allocate memory.
///
/// Parameters:
///   - file_data: File data (must be at least 16 bytes)
///
/// Returns: Copy of parsed header or error
pub fn parseHeader(file_data: []const u8) InesError!InesHeader {
    if (file_data.len < 16) {
        return InesError.FileTooSmall;
    }

    const header: *const InesHeader = @ptrCast(@alignCast(file_data.ptr));

    if (!header.isValid()) {
        return InesError.InvalidMagic;
    }

    return header.*;
}

/// Get expected file size from header
///
/// Calculates total file size without parsing full ROM.
///
/// Parameters:
///   - header: Parsed iNES header
///
/// Returns: Expected file size in bytes
pub fn getExpectedFileSize(header: *const InesHeader) usize {
    const prg_size = header.getPrgRomSize();
    const chr_size = header.getChrRomSize();
    const trainer_size: usize = if (header.hasTrainer()) 512 else 0;
    return 16 + trainer_size + prg_size + chr_size;
}

/// Calculate SHA-256 hash of PRG ROM data
///
/// Useful for ROM identification and verification.
///
/// Parameters:
///   - prg_rom: PRG ROM data
///
/// Returns: 32-byte SHA-256 hash
pub fn calculatePrgHash(prg_rom: []const u8) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(prg_rom);
    var hash: [32]u8 = undefined;
    hasher.final(&hash);
    return hash;
}

/// Calculate SHA-256 hash of entire ROM file
///
/// Useful for ROM verification and database lookups.
///
/// Parameters:
///   - file_data: Complete ROM file contents
///
/// Returns: 32-byte SHA-256 hash
pub fn calculateFileHash(file_data: []const u8) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(file_data);
    var hash: [32]u8 = undefined;
    hasher.final(&hash);
    return hash;
}
