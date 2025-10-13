# iNES ROM File Parser Module - Comprehensive Implementation Plan

**Date:** 2025-10-06
**Status:** Planning Phase
**Location:** `src/cartridge/ines/`
**Purpose:** Stateless, reusable *.nes ROM file parsing module completely decoupled from cartridge emulation

---

## Executive Summary

This plan defines a **stateless iNES ROM parser module** that is completely separated from cartridge emulation behavior. The module will live in `src/cartridge/ines/` and provide a pure data-parsing API that can be used by multiple components.

### Key Architectural Principles

1. **Separation of Concerns:**
   - **iNES Module:** Pure ROM file parsing (data format)
   - **Cartridge Module:** Emulation behavior (CPU/PPU interface)
   - **Clean Boundary:** iNES returns structured data, Cartridge uses that data

2. **Stateless Design:**
   - Zero internal state
   - Pure functions only
   - No caching or memoization
   - Thread-safe by design

3. **Type Safety:**
   - NO `anytype` parameters
   - Concrete struct definitions
   - Explicit error unions
   - Compile-time validation where possible

4. **Comprehensive Testing:**
   - Use `tests/data/*` ROM collection
   - Test multiple regions (NTSC, PAL, Dual)
   - Test all mapper types (0-255)
   - Test malformed/corrupted files
   - Test edge cases (0-byte CHR, trainer, battery RAM)

5. **Reusability:**
   - Can be used by: Cartridge loader, ROM browser, debugger, test harness
   - No dependencies on emulation components
   - Self-contained module

---

## Current State Analysis

### Existing Implementation

**Files:**
- `src/cartridge/ines.zig` (348 lines) - Current iNES parser
- `src/cartridge/loader.zig` (73 lines) - File loading wrapper
- `src/cartridge/Cartridge.zig` (427 lines) - Generic cartridge with `loadFromData()`

### Problems with Current Design

1. **Tight Coupling:**
   ```zig
   // In Cartridge.zig - parsing mixed with emulation
   pub fn loadFromData(allocator: Allocator, data: []const u8) !Self {
       const header = try ines.parseHeader(data);  // Parse
       // ... immediately creates emulation structures
       return Self{
           .mapper = MapperType.init(...),  // Emulation
           .prg_rom = prg_data,
           // ...
       };
   }
   ```

2. **anytype Usage:**
   ```zig
   // snapshot/Snapshot.zig:168
   cartridge: anytype  // Should be concrete type
   ```

3. **Limited Validation:**
   - Minimal error checking
   - No NES 2.0 support
   - No comprehensive format validation

4. **No Test ROM Coverage:**
   - Only tests with AccuracyCoin.nes
   - No malformed file testing
   - No mapper variety testing

---

## Proposed Architecture

### Module Structure

```
src/cartridge/ines/
├── mod.zig              # Module exports and public API
├── types.zig            # Data structures (Header, Rom, Metadata)
├── parser.zig           # Core parsing logic
├── validator.zig        # Format validation
├── mapper_db.zig        # Mapper metadata database
└── errors.zig           # Error types

tests/ines/
├── parser_test.zig      # Core parsing tests
├── validator_test.zig   # Validation tests
├── mapper_test.zig      # Mapper detection tests
├── edge_cases_test.zig  # Malformed files, edge cases
└── region_test.zig      # NTSC/PAL detection tests
```

### Data Structures

#### 1. InesHeader (16 bytes)

```zig
// src/cartridge/ines/types.zig

/// iNES/NES 2.0 ROM header (16 bytes)
/// Packed struct for exact binary layout
pub const InesHeader = packed struct {
    /// Magic bytes: "NES" + MS-DOS EOF (0x4E, 0x45, 0x53, 0x1A)
    magic: [4]u8,

    /// Number of 16 KB PRG ROM banks
    prg_rom_banks: u8,

    /// Number of 8 KB CHR ROM banks (0 = CHR RAM)
    chr_rom_banks: u8,

    /// Flags 6: Mapper lower, mirroring, battery, trainer
    flags6: Flags6,

    /// Flags 7: Mapper upper, VS/PC-10, NES 2.0 signature
    flags7: Flags7,

    /// Flags 8: Mapper/Submapper (NES 2.0) or PRG RAM size (iNES 1.0)
    flags8: u8,

    /// Flags 9: Mapper/Submapper extension (NES 2.0) or TV system (iNES 1.0)
    flags9: u8,

    /// Flags 10: PRG/CHR RAM sizes (NES 2.0) or TV system/PRG RAM (iNES 1.0)
    flags10: u8,

    /// Unused padding (should be zeros in iNES 1.0)
    _padding: [5]u8,

    comptime {
        std.debug.assert(@sizeOf(InesHeader) == 16);
        std.debug.assert(@bitSizeOf(InesHeader) == 128);
    }
};

pub const Flags6 = packed struct(u8) {
    /// Nametable mirroring: 0=horizontal, 1=vertical
    mirroring: bool,

    /// Battery-backed PRG RAM present
    battery_ram: bool,

    /// 512-byte trainer present at $7000-$71FF
    trainer_present: bool,

    /// Alternative nametable layout (ignore mirroring bit)
    alt_nametable: bool,

    /// Lower 4 bits of mapper number
    mapper_lower: u4,
};

pub const Flags7 = packed struct(u8) {
    /// VS Unisystem cartridge
    vs_unisystem: bool,

    /// PlayChoice-10 cartridge
    playchoice10: bool,

    /// NES 2.0 format signature (0b10 = NES 2.0, else iNES 1.0)
    nes2_signature: u2,

    /// Upper 4 bits of mapper number
    mapper_upper: u4,
};
```

#### 2. Rom Structure (Parsed Data)

```zig
/// Parsed ROM data (stateless, owned by caller)
pub const Rom = struct {
    /// ROM format version
    format: Format,

    /// Mapper number (0-4095 for NES 2.0)
    mapper_number: u12,

    /// Submapper number (NES 2.0 only)
    submapper: u8,

    /// Mirroring mode
    mirroring: MirroringMode,

    /// TV system (NTSC, PAL, Dual)
    tv_system: TvSystem,

    /// Has battery-backed PRG RAM
    has_battery_ram: bool,

    /// Has trainer (512 bytes at $7000-$71FF)
    has_trainer: bool,

    /// PRG ROM data (owned slice, caller must free)
    prg_rom: []const u8,

    /// CHR ROM data (owned slice, caller must free)
    /// Empty slice if CHR RAM
    chr_rom: []const u8,

    /// PRG RAM size in bytes
    prg_ram_size: usize,

    /// CHR RAM size in bytes (if chr_rom is empty)
    chr_ram_size: usize,

    /// Trainer data (owned slice if has_trainer, empty otherwise)
    trainer: []const u8,

    /// VS System PPU type (if vs_unisystem)
    vs_ppu_type: ?VsPpuType,

    /// Original header for debugging
    header: InesHeader,

    /// Free all owned memory
    pub fn deinit(self: *Rom, allocator: std.mem.Allocator) void {
        allocator.free(self.prg_rom);
        allocator.free(self.chr_rom);
        if (self.trainer.len > 0) {
            allocator.free(self.trainer);
        }
    }
};

pub const Format = enum {
    ines_1_0,
    nes_2_0,
};

pub const MirroringMode = enum {
    horizontal,
    vertical,
    four_screen,
};

pub const TvSystem = enum {
    ntsc,
    pal,
    dual,
};

pub const VsPpuType = enum(u8) {
    rp2c03b = 0,
    rp2c03g = 1,
    rp2c04_0001 = 2,
    rp2c04_0002 = 3,
    rp2c04_0003 = 4,
    rp2c04_0004 = 5,
    rc2c03b = 6,
    rc2c03c = 7,
    rc2c05_01 = 8,
    rc2c05_02 = 9,
    rc2c05_03 = 10,
    rc2c05_04 = 11,
    rc2c05_05 = 12,
};
```

#### 3. Metadata (Mapper Database)

```zig
/// Mapper metadata (compile-time database)
pub const MapperInfo = struct {
    number: u12,
    name: []const u8,
    board_name: []const u8,
    description: []const u8,
    game_count_estimate: u32,
    has_irq: bool,
    has_prg_ram: bool,
    has_chr_ram: bool,
};

/// Compile-time mapper database
pub const MAPPER_DATABASE = [_]MapperInfo{
    .{
        .number = 0,
        .name = "NROM",
        .board_name = "NES-NROM-128, NES-NROM-256",
        .description = "No mapper, simple 16/32KB PRG, 8KB CHR",
        .game_count_estimate = 95,
        .has_irq = false,
        .has_prg_ram = true,
        .has_chr_ram = true,  // Can have CHR RAM
    },
    .{
        .number = 1,
        .name = "MMC1",
        .board_name = "Nintendo SxROM",
        .description = "5-bit shift register, bank switching",
        .game_count_estimate = 680,
        .has_irq = false,
        .has_prg_ram = true,
        .has_chr_ram = true,
    },
    .{
        .number = 2,
        .name = "UxROM",
        .board_name = "NES-UNROM, NES-UOROM",
        .description = "Simple PRG bank switching",
        .game_count_estimate = 269,
        .has_irq = false,
        .has_prg_ram = false,
        .has_chr_ram = true,  // Always CHR RAM
    },
    .{
        .number = 3,
        .name = "CNROM",
        .board_name = "NES-CNROM",
        .description = "Simple CHR bank switching",
        .game_count_estimate = 155,
        .has_irq = false,
        .has_prg_ram = false,
        .has_chr_ram = false,
    },
    .{
        .number = 4,
        .name = "MMC3",
        .board_name = "Nintendo TxROM",
        .description = "Complex bank switching with scanline IRQ",
        .game_count_estimate = 601,
        .has_irq = true,
        .has_prg_ram = true,
        .has_chr_ram = true,
    },
    // ... more mappers
};

/// Look up mapper info at compile time or runtime
pub fn getMapperInfo(mapper_number: u12) ?*const MapperInfo {
    for (&MAPPER_DATABASE) |*info| {
        if (info.number == mapper_number) {
            return info;
        }
    }
    return null;
}
```

---

### Error Handling

```zig
// src/cartridge/ines/errors.zig

pub const InesError = error{
    /// File too small to contain header
    FileTooSmall,

    /// Invalid magic bytes (not "NES\x1A")
    InvalidMagic,

    /// Unsupported NES 2.0 features
    UnsupportedNes2Feature,

    /// Mapper number not supported
    UnsupportedMapper,

    /// PRG ROM size mismatch
    InvalidPrgRomSize,

    /// CHR ROM size mismatch
    InvalidChrRomSize,

    /// Trainer size mismatch
    InvalidTrainerSize,

    /// File truncated
    UnexpectedEndOfFile,

    /// Header checksum failed (NES 2.0)
    ChecksumMismatch,

    /// Invalid flags combination
    InvalidFlags,

    /// Memory allocation failed
    OutOfMemory,
};
```

---

### Core Parsing API

```zig
// src/cartridge/ines/parser.zig

const std = @import("std");
const types = @import("types.zig");
const errors = @import("errors.zig");
const validator = @import("validator.zig");

/// Parse iNES/NES 2.0 ROM from raw bytes
///
/// Caller owns returned Rom and must call Rom.deinit()
///
/// This function is completely stateless - no internal caching or state.
/// Thread-safe, can be called concurrently.
pub fn parse(
    allocator: std.mem.Allocator,
    file_data: []const u8,
) errors.InesError!types.Rom {
    // Validate minimum size
    if (file_data.len < @sizeOf(types.InesHeader)) {
        return error.FileTooSmall;
    }

    // Parse header (zero-copy view)
    const header = @ptrCast(*const types.InesHeader, @alignCast(@alignOf(types.InesHeader), file_data.ptr));

    // Validate magic bytes
    if (!std.mem.eql(u8, &header.magic, &[_]u8{ 0x4E, 0x45, 0x53, 0x1A })) {
        return error.InvalidMagic;
    }

    // Detect format (iNES 1.0 vs NES 2.0)
    const format = detectFormat(header);

    // Validate header integrity
    try validator.validateHeader(header, format);

    // Extract metadata
    const mapper_number = extractMapperNumber(header, format);
    const submapper = extractSubmapper(header, format);
    const mirroring = extractMirroring(header);
    const tv_system = extractTvSystem(header, format);

    // Calculate ROM layout
    const layout = try calculateLayout(header, format, file_data.len);

    // Validate file size matches header
    try validator.validateFileSize(file_data.len, layout);

    // Allocate and copy ROM data (caller owns)
    var rom = types.Rom{
        .format = format,
        .mapper_number = mapper_number,
        .submapper = submapper,
        .mirroring = mirroring,
        .tv_system = tv_system,
        .has_battery_ram = header.flags6.battery_ram,
        .has_trainer = header.flags6.trainer_present,
        .prg_rom = undefined,  // Set below
        .chr_rom = undefined,  // Set below
        .prg_ram_size = layout.prg_ram_size,
        .chr_ram_size = layout.chr_ram_size,
        .trainer = undefined,  // Set below
        .vs_ppu_type = extractVsPpuType(header),
        .header = header.*,
    };

    // Allocate PRG ROM
    rom.prg_rom = try allocator.dupe(u8, file_data[layout.prg_rom_start..layout.prg_rom_end]);
    errdefer allocator.free(rom.prg_rom);

    // Allocate CHR ROM (if present)
    if (layout.chr_rom_size > 0) {
        rom.chr_rom = try allocator.dupe(u8, file_data[layout.chr_rom_start..layout.chr_rom_end]);
    } else {
        rom.chr_rom = &[_]u8{};  // Empty slice for CHR RAM
    }
    errdefer if (rom.chr_rom.len > 0) allocator.free(rom.chr_rom);

    // Allocate trainer (if present)
    if (layout.trainer_size > 0) {
        rom.trainer = try allocator.dupe(u8, file_data[layout.trainer_start..layout.trainer_end]);
    } else {
        rom.trainer = &[_]u8{};
    }
    errdefer if (rom.trainer.len > 0) allocator.free(rom.trainer);

    return rom;
}

/// Detect iNES 1.0 vs NES 2.0 format
fn detectFormat(header: *const types.InesHeader) types.Format {
    // NES 2.0 signature: bits 2-3 of flags7 = 0b10
    if (header.flags7.nes2_signature == 0b10) {
        return .nes_2_0;
    }
    return .ines_1_0;
}

/// Extract mapper number (handles both iNES 1.0 and NES 2.0)
fn extractMapperNumber(header: *const types.InesHeader, format: types.Format) u12 {
    const lower = @as(u12, header.flags6.mapper_lower);
    const upper = @as(u12, header.flags7.mapper_upper);

    if (format == .nes_2_0) {
        // NES 2.0: 12-bit mapper number
        const extended = @as(u12, header.flags8 & 0x0F);
        return lower | (upper << 4) | (extended << 8);
    } else {
        // iNES 1.0: 8-bit mapper number
        return lower | (upper << 4);
    }
}

/// Extract submapper (NES 2.0 only)
fn extractSubmapper(header: *const types.InesHeader, format: types.Format) u8 {
    if (format == .nes_2_0) {
        return (header.flags8 >> 4) & 0x0F;
    }
    return 0;
}

/// Extract mirroring mode
fn extractMirroring(header: *const types.InesHeader) types.MirroringMode {
    if (header.flags6.alt_nametable) {
        return .four_screen;
    }
    return if (header.flags6.mirroring) .vertical else .horizontal;
}

/// Extract TV system
fn extractTvSystem(header: *const types.InesHeader, format: types.Format) types.TvSystem {
    if (format == .nes_2_0) {
        // NES 2.0: flags9 bits 0-1
        const tv_bits = header.flags9 & 0x03;
        return switch (tv_bits) {
            0 => .ntsc,
            1 => .pal,
            2, 3 => .dual,
            else => unreachable,
        };
    } else {
        // iNES 1.0: flags10 bit 0
        return if ((header.flags10 & 0x01) == 1) .pal else .ntsc;
    }
}

/// Extract VS System PPU type
fn extractVsPpuType(header: *const types.InesHeader) ?types.VsPpuType {
    if (!header.flags7.vs_unisystem) {
        return null;
    }
    const ppu_type_bits = (header.flags flags & 0x0F);
    return @enumFromInt(types.VsPpuType, ppu_type_bits);
}

/// ROM layout calculation
const RomLayout = struct {
    prg_rom_start: usize,
    prg_rom_end: usize,
    chr_rom_start: usize,
    chr_rom_end: usize,
    trainer_start: usize,
    trainer_end: usize,
    prg_rom_size: usize,
    chr_rom_size: usize,
    trainer_size: usize,
    prg_ram_size: usize,
    chr_ram_size: usize,
};

fn calculateLayout(
    header: *const types.InesHeader,
    format: types.Format,
    file_size: usize,
) errors.InesError!RomLayout {
    var layout: RomLayout = undefined;

    // Header is always 16 bytes
    var offset: usize = 16;

    // Trainer (if present)
    if (header.flags6.trainer_present) {
        layout.trainer_start = offset;
        layout.trainer_size = 512;
        layout.trainer_end = offset + 512;
        offset += 512;
    } else {
        layout.trainer_start = 0;
        layout.trainer_size = 0;
        layout.trainer_end = 0;
    }

    // PRG ROM
    layout.prg_rom_start = offset;
    layout.prg_rom_size = @as(usize, header.prg_rom_banks) * 16384;  // 16 KB banks
    layout.prg_rom_end = offset + layout.prg_rom_size;
    offset += layout.prg_rom_size;

    // CHR ROM (0 = CHR RAM)
    layout.chr_rom_start = offset;
    if (header.chr_rom_banks == 0) {
        layout.chr_rom_size = 0;
        layout.chr_ram_size = 8192;  // 8 KB CHR RAM
    } else {
        layout.chr_rom_size = @as(usize, header.chr_rom_banks) * 8192;  // 8 KB banks
        layout.chr_ram_size = 0;
    }
    layout.chr_rom_end = offset + layout.chr_rom_size;
    offset += layout.chr_rom_size;

    // PRG RAM size (NES 2.0 has explicit encoding, iNES 1.0 uses flags8)
    if (format == .nes_2_0) {
        // NES 2.0: flags10 bits 0-3 encode PRG RAM size
        const prg_ram_shift = header.flags10 & 0x0F;
        layout.prg_ram_size = if (prg_ram_shift == 0) 0 else (64 << prg_ram_shift);
    } else {
        // iNES 1.0: flags8 is PRG RAM size in 8 KB units (0 = 8 KB)
        const prg_ram_8kb = if (header.flags8 == 0) 1 else header.flags8;
        layout.prg_ram_size = @as(usize, prg_ram_8kb) * 8192;
    }

    return layout;
}
```

---

## Validation Strategy

```zig
// src/cartridge/ines/validator.zig

const std = @import("std");
const types = @import("types.zig");
const errors = @import("errors.zig");

/// Validate header integrity
pub fn validateHeader(header: *const types.InesHeader, format: types.Format) errors.InesError!void {
    // Check magic bytes (already done in parse, but double-check)
    if (!std.mem.eql(u8, &header.magic, &[_]u8{ 0x4E, 0x45, 0x53, 0x1A })) {
        return error.InvalidMagic;
    }

    // Validate PRG ROM size (must be > 0)
    if (header.prg_rom_banks == 0) {
        return error.InvalidPrgRomSize;
    }

    // Validate format-specific constraints
    if (format == .nes_2_0) {
        // NES 2.0 validation
        try validateNes2Header(header);
    } else {
        // iNES 1.0 validation
        try validateInesHeader(header);
    }
}

fn validateNes2Header(header: *const types.InesHeader) errors.InesError!void {
    // NES 2.0 padding should be zeros
    // (Some emulators ignore this, but we can warn)
    // for (header._padding) |byte| {
    //     if (byte != 0) {
    //         std.log.warn("NES 2.0 padding byte non-zero: 0x{X:0>2}", .{byte});
    //     }
    // }
}

fn validateInesHeader(header: *const types.InesHeader) errors.InesError!void {
    // iNES 1.0 validation (less strict)
    // Padding bytes often contain garbage in old ROMs
    _ = header;
}

/// Validate file size matches header declarations
pub fn validateFileSize(file_size: usize, layout: RomLayout) errors.InesError!void {
    const expected_size = layout.chr_rom_end;

    if (file_size < expected_size) {
        return error.UnexpectedEndOfFile;
    }

    // File can be larger (some ROMs have garbage at end)
    // Just warn if significantly larger
    if (file_size > expected_size + 1024) {
        std.log.warn("ROM file has {d} extra bytes after CHR data", .{file_size - expected_size});
    }
}
```

---

## Testing Strategy

### Test ROM Collection

Use `tests/data/` directory with diverse ROMs:

```
tests/data/
├── mappers/
│   ├── mapper_000_nrom.nes           # Mapper 0 (NROM)
│   ├── mapper_001_mmc1.nes           # Mapper 1 (MMC1)
│   ├── mapper_002_uxrom.nes          # Mapper 2 (UxROM)
│   ├── mapper_003_cnrom.nes          # Mapper 3 (CNROM)
│   ├── mapper_004_mmc3.nes           # Mapper 4 (MMC3)
│   └── mapper_255_unknown.nes        # Unsupported mapper
├── regions/
│   ├── ntsc_game.nes                 # NTSC region
│   ├── pal_game.nes                  # PAL region
│   └── dual_region.nes               # Dual region
├── edge_cases/
│   ├── chr_ram_only.nes              # 0 CHR ROM banks
│   ├── with_trainer.nes              # 512-byte trainer
│   ├── battery_ram.nes               # Battery-backed RAM
│   ├── four_screen.nes               # Four-screen mirroring
│   └── vs_unisystem.nes              # VS System
├── malformed/
│   ├── truncated_header.nes          # < 16 bytes
│   ├── invalid_magic.nes             # Wrong magic bytes
│   ├── truncated_prg.nes             # PRG ROM size mismatch
│   ├── truncated_chr.nes             # CHR ROM size mismatch
│   └── extra_data.nes                # Extra bytes at end
└── nes2/
    ├── nes2_basic.nes                # NES 2.0 format
    ├── nes2_submapper.nes            # With submapper
    └── nes2_extended_mapper.nes      # Mapper > 255
```

### Test Suite Structure

```zig
// tests/ines/parser_test.zig

const std = @import("std");
const testing = std.testing;
const ines = @import("ines");

test "iNES Parser: Valid NROM ROM" {
    const allocator = testing.allocator;

    // Load test ROM
    const rom_data = @embedFile("../data/mappers/mapper_000_nrom.nes");

    // Parse
    var rom = try ines.parse(allocator, rom_data);
    defer rom.deinit(allocator);

    // Validate
    try testing.expectEqual(ines.Format.ines_1_0, rom.format);
    try testing.expectEqual(@as(u12, 0), rom.mapper_number);
    try testing.expect(rom.prg_rom.len > 0);
}

test "iNES Parser: Invalid magic bytes" {
    const allocator = testing.allocator;

    // Create invalid ROM
    var invalid_rom = [_]u8{0} ** 32768;
    @memcpy(invalid_rom[0..4], "TEST");  // Wrong magic

    // Should error
    const result = ines.parse(allocator, &invalid_rom);
    try testing.expectError(error.InvalidMagic, result);
}

test "iNES Parser: CHR RAM (0 banks)" {
    const allocator = testing.allocator;

    const rom_data = @embedFile("../data/edge_cases/chr_ram_only.nes");

    var rom = try ines.parse(allocator, rom_data);
    defer rom.deinit(allocator);

    // CHR ROM should be empty
    try testing.expectEqual(@as(usize, 0), rom.chr_rom.len);
    // CHR RAM size should be 8192
    try testing.expectEqual(@as(usize, 8192), rom.chr_ram_size);
}

test "iNES Parser: Trainer present" {
    const allocator = testing.allocator;

    const rom_data = @embedFile("../data/edge_cases/with_trainer.nes");

    var rom = try ines.parse(allocator, rom_data);
    defer rom.deinit(allocator);

    try testing.expect(rom.has_trainer);
    try testing.expectEqual(@as(usize, 512), rom.trainer.len);
}

test "iNES Parser: NES 2.0 format" {
    const allocator = testing.allocator;

    const rom_data = @embedFile("../data/nes2/nes2_basic.nes");

    var rom = try ines.parse(allocator, rom_data);
    defer rom.deinit(allocator);

    try testing.expectEqual(ines.Format.nes_2_0, rom.format);
}
```

---

## Integration with Cartridge Module

### Before (Current - Tight Coupling)

```zig
// src/cartridge/Cartridge.zig (current)
pub fn loadFromData(allocator: Allocator, data: []const u8) !Self {
    const header = try ines.parseHeader(data);  // Parsing
    // ... immediately creates emulation structures
    const mapper = MapperType.init(...);  // Emulation
    return Self{ .mapper = mapper, ... };
}
```

### After (Clean Separation)

```zig
// src/cartridge/Cartridge.zig (proposed)
pub fn loadFromData(allocator: Allocator, data: []const u8) !Self {
    // Step 1: Parse ROM (pure data)
    var rom = try ines.parse(allocator, data);
    defer rom.deinit(allocator);  // Clean up after extraction

    // Step 2: Validate mapper is supported
    if (rom.mapper_number != 0) {
        return error.UnsupportedMapper;  // For now, only Mapper 0
    }

    // Step 3: Create emulation structures from parsed data
    const mapper = MapperType.initFromRom(&rom);

    // Step 4: Extract ROM data (transfer ownership)
    const prg_rom = try allocator.dupe(u8, rom.prg_rom);
    errdefer allocator.free(prg_rom);

    const chr_data = if (rom.chr_rom.len > 0)
        try allocator.dupe(u8, rom.chr_rom)
    else
        try allocator.alloc(u8, rom.chr_ram_size);  // Allocate CHR RAM
    errdefer allocator.free(chr_data);

    return Self{
        .mapper = mapper,
        .prg_rom = prg_rom,
        .chr_data = chr_data,
        .mirroring = rom.mirroring,
        // ...
    };
}
```

---

## Implementation Phases

### Phase 1: Foundation (4-6 hours)

**Deliverables:**
1. Create `src/cartridge/ines/` directory structure
2. Implement `types.zig` - All data structures
3. Implement `errors.zig` - Error types
4. Implement basic `parser.zig` - iNES 1.0 only
5. Write 10-15 core tests

**Validation:**
- Compiles without errors
- Parses AccuracyCoin.nes successfully
- Basic error handling works

### Phase 2: Validation & Edge Cases (3-4 hours)

**Deliverables:**
1. Implement `validator.zig` - Comprehensive validation
2. Add malformed file tests
3. Add edge case tests (trainer, CHR RAM, etc.)
4. Improve error messages

**Validation:**
- All edge case tests pass
- Malformed files rejected with clear errors

### Phase 3: NES 2.0 Support (2-3 hours)

**Deliverables:**
1. Add NES 2.0 format detection
2. Add extended mapper number support
3. Add submapper support
4. Add NES 2.0 tests

**Validation:**
- NES 2.0 ROMs parse correctly
- Extended mapper numbers work

### Phase 4: Mapper Database (2-3 hours)

**Deliverables:**
1. Implement `mapper_db.zig` - Compile-time database
2. Add mapper metadata for top 10 mappers
3. Add mapper lookup helpers

**Validation:**
- Mapper info lookups work
- Database is accessible at compile-time

### Phase 5: Integration (2-3 hours)

**Deliverables:**
1. Update `Cartridge.zig` to use iNES module
2. Remove old `ines.zig` coupling
3. Update tests to use new API
4. Remove all `anytype` usage

**Validation:**
- All existing tests still pass
- Zero regressions
- Type safety improved

### Phase 6: Documentation (2-3 hours)

**Deliverables:**
1. API documentation for all public functions
2. Usage examples
3. Migration guide from old API
4. Error handling guide

**Total:** 15-22 hours

---

## Success Criteria

1. **✅ Stateless:** Zero internal state, pure functions only
2. **✅ Type Safe:** No `anytype`, all concrete types
3. **✅ Reusable:** Can be used by multiple components
4. **✅ Tested:** 50+ tests covering all edge cases
5. **✅ Separated:** Complete decoupling from emulation
6. **✅ Validated:** Robust error handling for malformed files
7. **✅ Documented:** Comprehensive API docs

---

## Open Questions

1. **Should we support archaic iNES 0.7 format?**
   - Decision: NO - focus on iNES 1.0 and NES 2.0

2. **Should we auto-detect format from file extension?**
   - Decision: NO - parse based on content only

3. **Should we cache parsed ROMs?**
   - Decision: NO - keep module stateless, let caller cache if needed

4. **Should we support writing iNES files?**
   - Decision: DEFER - read-only for now, add writer later if needed

5. **Should we validate mapper number against supported mappers?**
   - Decision: YES - but make it optional via parameter

---

## Conclusion

This plan defines a **stateless, type-safe, reusable iNES ROM parser module** that cleanly separates data parsing from emulation behavior. The module will be:

- **Self-contained** in `src/cartridge/ines/`
- **Fully tested** with diverse ROMs from `tests/data/`
- **Production-ready** with robust error handling
- **Extensible** for future mapper support

**Estimated Time:** 15-22 hours
**Priority:** HIGH (blocks mapper expansion and type safety improvements)
**Dependencies:** None (can be implemented immediately)

---

**Plan Created:** 2025-10-06
**Status:** READY FOR IMPLEMENTATION
**Next Step:** Begin Phase 1 (Foundation)
