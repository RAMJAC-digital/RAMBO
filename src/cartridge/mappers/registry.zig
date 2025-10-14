//! Mapper Registry and Type System
//!
//! Defines all supported NES mappers and provides compile-time metadata.
//! Uses tagged union dispatch for zero-overhead polymorphism.
//!
//! Architecture:
//! - MapperId: Enum of all supported mappers
//! - MapperMetadata: Compile-time information per mapper
//! - AnyCartridge: Tagged union for runtime dispatch
//!
//! References:
//! - docs/implementation/MAPPER-SYSTEM-PLAN.md
//! - docs/MAPPER-SYSTEM-SUMMARY.md

const std = @import("std");
const Cartridge = @import("../Cartridge.zig").Cartridge;
const Mapper0 = @import("Mapper0.zig").Mapper0;
const Mapper3 = @import("Mapper3.zig").Mapper3;
const Mapper7 = @import("Mapper7.zig").Mapper7;

/// Mapper ID enum - all supported NES mappers
///
/// Phase 1 mappers (0-4): 75% game coverage
/// - Mapper 0 (NROM):  248 games (~5%)
/// - Mapper 1 (MMC1):  681 games (~28%) [PLANNED]
/// - Mapper 2 (UxROM): 270 games (~11%) [PLANNED]
/// - Mapper 3 (CNROM): 155 games (~6%)  [PLANNED]
/// - Mapper 4 (MMC3):  600 games (~25%) [PLANNED]
pub const MapperId = enum(u8) {
    /// Mapper 0: NROM (No mapper)
    /// 248 games - Super Mario Bros., Donkey Kong, Ice Climber
    nrom = 0,

    /// Mapper 3: CNROM (CHR banking only)
    /// 155 games - Arkanoid, Gradius, Donkey Kong 3
    cnrom = 3,

    /// Mapper 7: AxROM (PRG banking + single-screen mirroring)
    /// ~50 games - Battletoads, Wizards & Warriors, Marble Madness
    axrom = 7,

    // Future mappers (Phase 1):
    // mmc1 = 1,   // Mapper 1: MMC1 (SxROM) - Metroid, Zelda, Mega Man 2
    // uxrom = 2,  // Mapper 2: UxROM - Mega Man, Castlevania
    // mmc3 = 4,   // Mapper 4: MMC3 (TxROM) - Super Mario Bros. 3, Kirby's Adventure

    /// Get mapper name
    pub fn name(self: MapperId) []const u8 {
        return switch (self) {
            .nrom => "NROM",
            .cnrom => "CNROM",
            .axrom => "AxROM",
        };
    }

    /// Get mapper description
    pub fn description(self: MapperId) []const u8 {
        return switch (self) {
            .nrom => "No mapper - fixed 16KB or 32KB PRG ROM",
            .cnrom => "Simple CHR banking - 8KB CHR banks, fixed PRG",
            .axrom => "32KB PRG banking + single-screen mirroring, CHR RAM",
        };
    }

    /// Get nesdev.org wiki link
    pub fn nesdevLink(self: MapperId) []const u8 {
        return switch (self) {
            .nrom => "https://www.nesdev.org/wiki/NROM",
            .cnrom => "https://www.nesdev.org/wiki/CNROM",
            .axrom => "https://www.nesdev.org/wiki/AxROM",
        };
    }

    /// Get approximate game count
    pub fn gameCount(self: MapperId) u16 {
        return switch (self) {
            .nrom => 248,
            .cnrom => 155,
            .axrom => 50,
        };
    }

    /// Supports IRQ generation?
    pub fn supportsIrq(self: MapperId) bool {
        return switch (self) {
            .nrom => false,
            .cnrom => false,
            .axrom => false,
            // mmc3 => true,  // MMC3 has IRQ via A12 edge detection
        };
    }
};

/// Mapper metadata - compile-time information
pub const MapperMetadata = struct {
    id: MapperId,
    name: []const u8,
    description: []const u8,
    nesdev_link: []const u8,
    game_count: u16,
    supports_irq: bool,

    /// Get metadata for a mapper
    pub fn get(id: MapperId) MapperMetadata {
        return .{
            .id = id,
            .name = id.name(),
            .description = id.description(),
            .nesdev_link = id.nesdevLink(),
            .game_count = id.gameCount(),
            .supports_irq = id.supportsIrq(),
        };
    }
};

/// Tagged union of all supported cartridge types
///
/// Uses `inline else` for zero-overhead dispatch - compiles to direct jumps.
/// Each variant is a distinct Cartridge(MapperType) instance.
///
/// Example:
/// ```zig
/// var any_cart = AnyCartridge{ .nrom = nrom_cart };
/// const value = any_cart.cpuRead(0x8000);  // Direct dispatch, no VTable
/// ```
pub const AnyCartridge = union(MapperId) {
    /// NROM cartridge (Mapper 0)
    nrom: Cartridge(Mapper0),

    /// CNROM cartridge (Mapper 3)
    cnrom: Cartridge(Mapper3),

    /// AxROM cartridge (Mapper 7)
    axrom: Cartridge(Mapper7),

    // Future mappers:
    // mmc1: Cartridge(Mapper1),
    // uxrom: Cartridge(Mapper2),
    // mmc3: Cartridge(Mapper4),

    // ========================================================================
    // CPU Interface
    // ========================================================================

    /// Read from CPU address space ($4020-$FFFF)
    ///
    /// Dispatches to active mapper with zero overhead.
    /// The `inline else` causes the switch to compile to direct jumps.
    pub fn cpuRead(self: *const AnyCartridge, address: u16) u8 {
        return switch (self.*) {
            inline else => |*cart| cart.cpuRead(address),
        };
    }

    /// Write to CPU address space ($4020-$FFFF)
    pub fn cpuWrite(self: *AnyCartridge, address: u16, value: u8) void {
        switch (self.*) {
            inline else => |*cart| cart.cpuWrite(address, value),
        }
    }

    // ========================================================================
    // PPU Interface
    // ========================================================================

    /// Read from PPU address space ($0000-$1FFF for CHR)
    pub fn ppuRead(self: *const AnyCartridge, address: u16) u8 {
        return switch (self.*) {
            inline else => |*cart| cart.ppuRead(address),
        };
    }

    /// Write to PPU address space ($0000-$1FFF for CHR)
    pub fn ppuWrite(self: *AnyCartridge, address: u16, value: u8) void {
        switch (self.*) {
            inline else => |*cart| cart.ppuWrite(address, value),
        }
    }

    // ========================================================================
    // IRQ Interface
    // ========================================================================

    /// Poll mapper for IRQ assertion
    ///
    /// Called every CPU cycle. Returns true if IRQ should be asserted.
    /// Mappers without IRQ support (like NROM) return false.
    ///
    /// Note: This is a pure query - side effects stay in EmulationState.tick()
    pub fn tickIrq(self: *AnyCartridge) bool {
        return switch (self.*) {
            inline else => |*cart| cart.mapper.tickIrq(),
        };
    }

    /// Notify mapper of PPU A12 rising edge (0→1 transition)
    ///
    /// Called during PPU rendering when A12 transitions from 0 to 1.
    /// MMC3 uses this to decrement its IRQ scanline counter.
    ///
    /// A12 edge detection:
    /// - Background: fetching new tile ($0xxx → $1xxx or wrap)
    /// - Sprites: fetching sprite pattern data
    pub fn ppuA12Rising(self: *AnyCartridge) void {
        switch (self.*) {
            inline else => |*cart| cart.mapper.ppuA12Rising(),
        }
    }

    /// Acknowledge IRQ (clear pending flag)
    ///
    /// Called when CPU reads interrupt vector ($FFFE).
    /// Mappers like MMC3 clear their IRQ pending flag here.
    pub fn acknowledgeIrq(self: *AnyCartridge) void {
        switch (self.*) {
            inline else => |*cart| cart.mapper.acknowledgeIrq(),
        }
    }

    // ========================================================================
    // Control Interface
    // ========================================================================

    /// Reset cartridge to power-on state
    pub fn reset(self: *AnyCartridge) void {
        switch (self.*) {
            inline else => |*cart| cart.reset(),
        }
    }

    /// Get current mirroring mode
    pub fn getMirroring(self: *const AnyCartridge) @import("../Cartridge.zig").Mirroring {
        return switch (self.*) {
            inline else => |*cart| cart.mirroring,
        };
    }

    /// Clean up cartridge resources
    pub fn deinit(self: *AnyCartridge) void {
        switch (self.*) {
            inline else => |*cart| cart.deinit(),
        }
    }

    // ========================================================================
    // Metadata Interface
    // ========================================================================

    /// Get mapper ID
    pub fn getMapperId(self: *const AnyCartridge) MapperId {
        return @as(MapperId, self.*);
    }

    /// Get mapper metadata
    pub fn getMetadata(self: *const AnyCartridge) MapperMetadata {
        return MapperMetadata.get(self.getMapperId());
    }

    // ========================================================================
    // ROM Data Access (for snapshot system)
    // ========================================================================

    /// Get PRG ROM data (read-only)
    pub fn getPrgRom(self: *const AnyCartridge) []const u8 {
        return switch (self.*) {
            inline else => |*cart| cart.prg_rom,
        };
    }

    /// Get CHR data (may be ROM or RAM)
    pub fn getChrData(self: *const AnyCartridge) []u8 {
        return switch (self.*) {
            inline else => |*cart| cart.chr_data,
        };
    }

    /// Get PRG RAM data (if present)
    pub fn getPrgRam(self: *const AnyCartridge) ?[]u8 {
        return switch (self.*) {
            inline else => |*cart| cart.prg_ram,
        };
    }

    /// Get iNES header
    pub fn getHeader(self: *const AnyCartridge) @import("../Cartridge.zig").InesHeader {
        return switch (self.*) {
            inline else => |*cart| cart.header,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "MapperId: metadata" {
    const nrom_id = MapperId.nrom;

    try testing.expectEqualStrings("NROM", nrom_id.name());
    try testing.expectEqualStrings("No mapper - fixed 16KB or 32KB PRG ROM", nrom_id.description());
    try testing.expectEqualStrings("https://www.nesdev.org/wiki/NROM", nrom_id.nesdevLink());
    try testing.expectEqual(@as(u16, 248), nrom_id.gameCount());
    try testing.expectEqual(false, nrom_id.supportsIrq());
}

test "MapperMetadata: get" {
    const meta = MapperMetadata.get(.nrom);

    try testing.expectEqual(MapperId.nrom, meta.id);
    try testing.expectEqualStrings("NROM", meta.name);
    try testing.expectEqual(@as(u16, 248), meta.game_count);
    try testing.expectEqual(false, meta.supports_irq);
}

test "AnyCartridge: union dispatch with NROM" {
    // Create a minimal NROM ROM
    var rom_data = [_]u8{0} ** (16 + 16384 + 8192);

    // iNES header
    rom_data[0] = 'N';
    rom_data[1] = 'E';
    rom_data[2] = 'S';
    rom_data[3] = 0x1A;
    rom_data[4] = 1; // 1 x 16KB PRG ROM
    rom_data[5] = 1; // 1 x 8KB CHR ROM
    rom_data[6] = 0; // Mapper 0
    rom_data[7] = 0;

    // Test data
    rom_data[16] = 0x42; // $8000

    const NromCart = Cartridge(Mapper0);
    var nrom_cart = try NromCart.loadFromData(testing.allocator, &rom_data);
    defer nrom_cart.deinit();

    // Wrap in union
    var any_cart = AnyCartridge{ .nrom = nrom_cart };

    // Test CPU read through union dispatch
    try testing.expectEqual(@as(u8, 0x42), any_cart.cpuRead(0x8000));

    // Test mapper ID
    try testing.expectEqual(MapperId.nrom, any_cart.getMapperId());

    // Test metadata
    const meta = any_cart.getMetadata();
    try testing.expectEqualStrings("NROM", meta.name);
}

test "AnyCartridge: IRQ methods (NROM stubs)" {
    var rom_data = [_]u8{0} ** (16 + 16384 + 8192);

    // iNES header
    rom_data[0] = 'N';
    rom_data[1] = 'E';
    rom_data[2] = 'S';
    rom_data[3] = 0x1A;
    rom_data[4] = 1;
    rom_data[5] = 1;
    rom_data[6] = 0;
    rom_data[7] = 0;

    const NromCart = Cartridge(Mapper0);
    var nrom_cart = try NromCart.loadFromData(testing.allocator, &rom_data);
    defer nrom_cart.deinit();

    var any_cart = AnyCartridge{ .nrom = nrom_cart };

    // NROM doesn't support IRQ - should always return false
    try testing.expectEqual(false, any_cart.tickIrq());

    // PPU A12 rising edge - should be no-op for NROM
    any_cart.ppuA12Rising();

    // Acknowledge IRQ - should be no-op for NROM
    any_cart.acknowledgeIrq();
}

test "AnyCartridge: reset and mirroring" {
    var rom_data = [_]u8{0} ** (16 + 16384 + 8192);

    // iNES header with vertical mirroring
    rom_data[0] = 'N';
    rom_data[1] = 'E';
    rom_data[2] = 'S';
    rom_data[3] = 0x1A;
    rom_data[4] = 1;
    rom_data[5] = 1;
    rom_data[6] = 0x01; // Vertical mirroring
    rom_data[7] = 0;

    const NromCart = Cartridge(Mapper0);
    var nrom_cart = try NromCart.loadFromData(testing.allocator, &rom_data);
    defer nrom_cart.deinit();

    var any_cart = AnyCartridge{ .nrom = nrom_cart };

    // Test mirroring
    const Mirroring = @import("../Cartridge.zig").Mirroring;
    try testing.expectEqual(Mirroring.vertical, any_cart.getMirroring());

    // Reset should not crash
    any_cart.reset();
}
