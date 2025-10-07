// iNES ROM Format Parser - Public API
//
// Stateless parser for iNES 1.0 and NES 2.0 ROM formats.
// Completely separate from cartridge emulation - handles only data format parsing.
//
// Usage:
//   const ines = @import("cartridge/ines/mod.zig");
//   const rom = try ines.parse(allocator, file_data);
//   defer rom.deinit(allocator);
//
// Key Features:
//   - Stateless design (thread-safe, no caching)
//   - Zero-copy header parsing (packed structs)
//   - Comprehensive validation with warnings
//   - Support for both iNES 1.0 and NES 2.0 formats
//   - NO anytype - all concrete types
//
// Architecture:
//   - types.zig: Data structure definitions (InesHeader, Rom, etc.)
//   - parser.zig: Pure parsing functions (stateless)
//   - validator.zig: Validation logic (errors + warnings)
//   - errors.zig: Error type definitions

const std = @import("std");

// === Core Modules ===
pub const types = @import("types.zig");
pub const parser = @import("parser.zig");
pub const validator = @import("validator.zig");
pub const errors = @import("errors.zig");

// === Type Exports ===

// Format types
pub const Format = types.Format;
pub const MirroringMode = types.MirroringMode;
pub const Region = types.Region;
pub const ConsoleType = types.ConsoleType;

// Header structures
pub const Flags6 = types.Flags6;
pub const Flags7 = types.Flags7;
pub const Flags9 = types.Flags9;
pub const Flags10 = types.Flags10;
pub const InesHeader = types.InesHeader;

// ROM structures
pub const MapperInfo = types.MapperInfo;
pub const Rom = types.Rom;

// Error types
pub const InesError = errors.InesError;

// Validation types
pub const ValidationWarning = validator.ValidationWarning;
pub const ValidationResult = validator.ValidationResult;

// === Function Exports ===

/// Parse complete iNES ROM from file data
///
/// Stateless pure function - thread-safe, no caching.
/// Caller owns returned Rom and must call deinit().
///
/// Example:
///   const rom = try ines.parse(allocator, file_data);
///   defer rom.deinit(allocator);
///
/// Parameters:
///   - allocator: Memory allocator for ROM data
///   - file_data: Complete ROM file contents
///
/// Returns: Parsed Rom structure or error
pub const parse = parser.parse;

/// Parse iNES header only (fast metadata extraction)
///
/// Does not allocate memory or load ROM data.
/// Useful for quick ROM inspection.
///
/// Parameters:
///   - file_data: File data (must be at least 16 bytes)
///
/// Returns: Copy of parsed header or error
pub const parseHeader = parser.parseHeader;

/// Get expected file size from header
///
/// Calculates total file size without full parsing.
///
/// Parameters:
///   - header: Parsed iNES header
///
/// Returns: Expected file size in bytes
pub const getExpectedFileSize = parser.getExpectedFileSize;

/// Calculate SHA-256 hash of PRG ROM
///
/// Useful for ROM identification and verification.
///
/// Parameters:
///   - prg_rom: PRG ROM data
///
/// Returns: 32-byte SHA-256 hash
pub const calculatePrgHash = parser.calculatePrgHash;

/// Calculate SHA-256 hash of complete ROM file
///
/// Useful for ROM verification and database lookups.
///
/// Parameters:
///   - file_data: Complete ROM file contents
///
/// Returns: 32-byte SHA-256 hash
pub const calculateFileHash = parser.calculateFileHash;

/// Validate iNES header
///
/// Performs comprehensive validation with errors and warnings.
///
/// Parameters:
///   - allocator: Allocator for result lists
///   - header: Parsed iNES header
///
/// Returns: Validation result (must call deinit())
pub const validateHeader = validator.validateHeader;

/// Validate complete ROM structure
///
/// Checks data integrity and configuration validity.
///
/// Parameters:
///   - allocator: Allocator for result lists
///   - rom: Parsed ROM structure
///
/// Returns: Validation result (must call deinit())
pub const validateRom = validator.validateRom;

/// Quick validation check (boolean)
///
/// Fast path for "is this valid?" checks.
///
/// Parameters:
///   - header: Parsed iNES header
///
/// Returns: true if valid, false otherwise
pub const isValid = validator.isValid;

/// Check if mapper is commonly supported
///
/// Returns true for well-known mappers (0-4, 7, 9, etc.)
///
/// Parameters:
///   - mapper_number: Mapper number to check
///
/// Returns: true if mapper is common
pub const isCommonMapper = validator.isCommonMapper;

/// Get mapper name for common mappers
///
/// Returns mapper name or "Unknown" for unsupported mappers.
///
/// Parameters:
///   - mapper_number: Mapper number
///
/// Returns: Mapper name string
pub const getMapperName = validator.getMapperName;

/// Convert error to human-readable description
///
/// Parameters:
///   - err: InesError to describe
///
/// Returns: Error description string
pub const errorDescription = errors.errorDescription;

/// Check if error is recoverable
///
/// Returns true if parsing can continue with warnings.
///
/// Parameters:
///   - err: InesError to check
///
/// Returns: true if recoverable
pub const isRecoverable = errors.isRecoverable;

// === Module Tests ===

const testing = std.testing;

test "iNES module: basic imports" {
    // Verify all types are accessible
    _ = Format;
    _ = MirroringMode;
    _ = Region;
    _ = InesHeader;
    _ = Rom;
    _ = InesError;
}

test "iNES module: function exports" {
    // Verify all functions are accessible
    _ = parse;
    _ = parseHeader;
    _ = validateHeader;
    _ = isValid;
}
