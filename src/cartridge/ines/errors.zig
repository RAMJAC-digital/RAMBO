// iNES ROM Format Error Types
//
// Comprehensive error handling for iNES 1.0 and NES 2.0 ROM parsing.
// All error conditions are explicitly defined with descriptive names.

/// Errors that can occur during iNES ROM parsing and validation
pub const InesError = error{
    // === File Size Errors ===
    /// File is smaller than minimum 16-byte header
    FileTooSmall,
    /// File size doesn't match header-specified sizes
    FileSizeMismatch,
    /// File is unexpectedly larger than expected (potential corruption)
    UnexpectedExtraData,

    // === Header Format Errors ===
    /// Magic bytes are not "NES\x1A"
    InvalidMagic,
    /// Header indicates invalid format
    InvalidHeaderFormat,
    /// Reserved bytes contain non-zero values
    InvalidReservedBytes,

    // === Size Specification Errors ===
    /// PRG ROM size is zero (invalid)
    ZeroPrgRomSize,
    /// PRG ROM size exceeds reasonable limits
    PrgRomSizeTooLarge,
    /// CHR ROM/RAM size specification is invalid
    InvalidChrSize,
    /// Trainer size is invalid (must be 0 or 512 bytes)
    InvalidTrainerSize,

    // === Mapper Errors ===
    /// Mapper number is not recognized
    UnknownMapper,
    /// Mapper number exceeds valid range
    InvalidMapperNumber,
    /// Submapper number is invalid for this mapper
    InvalidSubmapper,
    /// Mapper configuration is inconsistent
    InconsistentMapperConfig,

    // === Format Version Errors ===
    /// iNES version cannot be determined (corrupt header)
    AmbiguousFormat,
    /// NES 2.0 header has invalid identifier
    InvalidNes2Identifier,
    /// Format version is not supported by this parser
    UnsupportedFormat,

    // === Region/Timing Errors ===
    /// Region specification is invalid
    InvalidRegion,
    /// Multiple conflicting region indicators
    AmbiguousRegion,

    // === Memory Configuration Errors ===
    /// Battery-backed RAM configuration is invalid
    InvalidBatteryRam,
    /// SRAM/PRG RAM size specification is invalid
    InvalidPrgRamSize,
    /// CHR RAM size specification is invalid
    InvalidChrRamSize,

    // === Trainer Errors ===
    /// Trainer data is present but corrupted
    CorruptTrainer,
    /// Trainer flag is set but data is missing
    MissingTrainer,

    // === Data Integrity Errors ===
    /// ROM data appears corrupted (checksum fail, etc.)
    CorruptRomData,
    /// Unexpected end of file during parsing
    UnexpectedEof,
    /// File contains invalid or malformed data
    MalformedData,

    // === Allocation Errors ===
    /// Memory allocation failed during parsing
    OutOfMemory,

    // === Validation Errors ===
    /// ROM fails validation checks
    ValidationFailed,
    /// ROM has inconsistent internal state
    InconsistentState,
};

/// Convert error to human-readable description
pub fn errorDescription(err: InesError) []const u8 {
    return switch (err) {
        // File Size Errors
        error.FileTooSmall => "File is smaller than 16-byte iNES header",
        error.FileSizeMismatch => "File size doesn't match header specification",
        error.UnexpectedExtraData => "File contains unexpected extra data",

        // Header Format Errors
        error.InvalidMagic => "Invalid magic bytes (expected 'NES\\x1A')",
        error.InvalidHeaderFormat => "Header format is invalid or corrupt",
        error.InvalidReservedBytes => "Reserved header bytes are non-zero",

        // Size Specification Errors
        error.ZeroPrgRomSize => "PRG ROM size cannot be zero",
        error.PrgRomSizeTooLarge => "PRG ROM size exceeds maximum",
        error.InvalidChrSize => "CHR ROM/RAM size is invalid",
        error.InvalidTrainerSize => "Trainer size must be 0 or 512 bytes",

        // Mapper Errors
        error.UnknownMapper => "Mapper number is not recognized",
        error.InvalidMapperNumber => "Mapper number exceeds valid range",
        error.InvalidSubmapper => "Submapper is invalid for this mapper",
        error.InconsistentMapperConfig => "Mapper configuration is inconsistent",

        // Format Version Errors
        error.AmbiguousFormat => "Cannot determine iNES format version",
        error.InvalidNes2Identifier => "Invalid NES 2.0 format identifier",
        error.UnsupportedFormat => "ROM format is not supported",

        // Region/Timing Errors
        error.InvalidRegion => "Region specification is invalid",
        error.AmbiguousRegion => "Multiple conflicting region indicators",

        // Memory Configuration Errors
        error.InvalidBatteryRam => "Battery-backed RAM configuration is invalid",
        error.InvalidPrgRamSize => "PRG RAM size specification is invalid",
        error.InvalidChrRamSize => "CHR RAM size specification is invalid",

        // Trainer Errors
        error.CorruptTrainer => "Trainer data is corrupted",
        error.MissingTrainer => "Trainer flag set but data missing",

        // Data Integrity Errors
        error.CorruptRomData => "ROM data appears corrupted",
        error.UnexpectedEof => "Unexpected end of file",
        error.MalformedData => "File contains malformed data",

        // Allocation Errors
        error.OutOfMemory => "Memory allocation failed",

        // Validation Errors
        error.ValidationFailed => "ROM validation failed",
        error.InconsistentState => "ROM has inconsistent internal state",
    };
}

/// Check if error is recoverable (parsing can continue with warnings)
pub fn isRecoverable(err: InesError) bool {
    return switch (err) {
        // Recoverable - can continue with warnings/defaults
        error.InvalidReservedBytes => true,
        error.UnexpectedExtraData => true,
        error.AmbiguousRegion => true,

        // Non-recoverable - parsing must abort
        error.FileTooSmall => false,
        error.FileSizeMismatch => false,
        error.InvalidMagic => false,
        error.InvalidHeaderFormat => false,
        error.ZeroPrgRomSize => false,
        error.PrgRomSizeTooLarge => false,
        error.InvalidChrSize => false,
        error.InvalidTrainerSize => false,
        error.UnknownMapper => false,
        error.InvalidMapperNumber => false,
        error.InvalidSubmapper => false,
        error.InconsistentMapperConfig => false,
        error.AmbiguousFormat => false,
        error.InvalidNes2Identifier => false,
        error.UnsupportedFormat => false,
        error.InvalidRegion => false,
        error.InvalidBatteryRam => false,
        error.InvalidPrgRamSize => false,
        error.InvalidChrRamSize => false,
        error.CorruptTrainer => false,
        error.MissingTrainer => false,
        error.CorruptRomData => false,
        error.UnexpectedEof => false,
        error.MalformedData => false,
        error.OutOfMemory => false,
        error.ValidationFailed => false,
        error.InconsistentState => false,
    };
}
