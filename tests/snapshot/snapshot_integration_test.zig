//! Snapshot Integration Tests
//!
//! Comprehensive tests for EmulationState save/load functionality.
//! Tests full round-trips with cartridges, config verification, and pointer reconstruction.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Snapshot = RAMBO.Snapshot;
const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;
const Cartridge = RAMBO.Cartridge;

// ============================================================================
// Test Fixtures
// ============================================================================

/// Create a test ROM for Mapper 0 (NROM)
fn createTestRom(allocator: std.mem.Allocator) ![]u8 {
    var rom = std.ArrayListUnmanaged(u8){};
    errdefer rom.deinit(allocator);

    const writer = rom.writer(allocator);

    // iNES header (16 bytes)
    try writer.writeAll("NES\x1A"); // Magic
    try writer.writeByte(2); // 2 x 16KB PRG ROM = 32KB
    try writer.writeByte(1); // 1 x 8KB CHR ROM = 8KB
    try writer.writeByte(0x00); // Flags 6: Horizontal mirroring, Mapper 0
    try writer.writeByte(0x00); // Flags 7: Mapper 0
    try writer.writeAll(&[_]u8{0} ** 8); // Padding

    // PRG ROM (32KB)
    var prg_rom: [32768]u8 = undefined;
    // Fill with test pattern
    for (&prg_rom, 0..) |*byte, i| {
        byte.* = @intCast(i & 0xFF);
    }
    try writer.writeAll(&prg_rom);

    // CHR ROM (8KB)
    var chr_rom: [8192]u8 = undefined;
    // Fill with test pattern
    for (&chr_rom, 0..) |*byte, i| {
        byte.* = @intCast((i * 2) & 0xFF);
    }
    try writer.writeAll(&chr_rom);

    return try rom.toOwnedSlice(allocator);
}

/// Create EmulationState with test data
fn createTestState(config: *const Config) EmulationState {
    var state = EmulationState.init(config);

    // Set distinctive values for verification
    state.clock.ppu_cycles = 123456;
    state.cpu.a = 0x42;
    state.cpu.x = 0x13;
    state.cpu.y = 0x37;
    state.cpu.sp = 0xFD;
    state.cpu.pc = 0x8000;
    state.cpu.p.zero = true;
    state.cpu.p.negative = true;
    // CPU cycle count removed - derived from ppu_cycles (set below)

    state.ppu.ctrl = .{ .nmi_enable = true, .sprite_size = true };
    state.ppu.mask = .{ .show_bg = true, .show_sprites = true };
    state.clock.ppu_cycles = (42 * 89342) + (100 * 341) + 200; // Frame 42, scanline 100, dot 200

    state.bus.ram[0x00] = 0xAA;
    state.bus.ram[0x01] = 0xBB;
    state.bus.ram[0xFF] = 0xCC;

    state.frame_complete = true;
    state.odd_frame = true;
    state.rendering_enabled = true;

    return state;
}

// ============================================================================
// Integration Tests
// ============================================================================

test "Snapshot Integration: Full round-trip without cartridge" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    const state = createTestState(&config);

    // Save snapshot
    const snapshot = try Snapshot.saveBinary(
        testing.allocator,
        &state,
        &config,
        .reference,
        false,
        null,
    );
    defer testing.allocator.free(snapshot);

    // Verify snapshot exists and has reasonable size
    try testing.expect(snapshot.len > 72); // Header + data
    try testing.expect(snapshot.len < 10000); // Should be ~4.6KB

    // Verify snapshot integrity
    try Snapshot.verify(snapshot);

    // Load snapshot
    const restored = try Snapshot.loadBinary(
        testing.allocator,
        snapshot,
        &config,
        @as(?RAMBO.AnyCartridge, null),
    );

    // Verify clock state
    try testing.expectEqual(state.clock.ppu_cycles, restored.clock.ppu_cycles);

    // Verify CPU state
    try testing.expectEqual(state.cpu.a, restored.cpu.a);
    try testing.expectEqual(state.cpu.x, restored.cpu.x);
    try testing.expectEqual(state.cpu.y, restored.cpu.y);
    try testing.expectEqual(state.cpu.sp, restored.cpu.sp);
    try testing.expectEqual(state.cpu.pc, restored.cpu.pc);
    try testing.expectEqual(state.cpu.p.zero, restored.cpu.p.zero);
    try testing.expectEqual(state.cpu.p.negative, restored.cpu.p.negative);
    try testing.expectEqual(state.clock.cpuCycles(), restored.clock.cpuCycles());

    // Verify PPU state
    try testing.expectEqual(state.ppu.ctrl.nmi_enable, restored.ppu.ctrl.nmi_enable);
    try testing.expectEqual(state.ppu.ctrl.sprite_size, restored.ppu.ctrl.sprite_size);
    try testing.expectEqual(state.ppu.mask.show_bg, restored.ppu.mask.show_bg);
    try testing.expectEqual(state.ppu.mask.show_sprites, restored.ppu.mask.show_sprites);
    try testing.expectEqual(state.clock.scanline(), restored.clock.scanline());
    try testing.expectEqual(state.clock.dot(), restored.clock.dot());
    try testing.expectEqual(state.clock.frame(), restored.clock.frame());

    // Verify Bus state
    try testing.expectEqual(state.bus.ram[0x00], restored.bus.ram[0x00]);
    try testing.expectEqual(state.bus.ram[0x01], restored.bus.ram[0x01]);
    try testing.expectEqual(state.bus.ram[0xFF], restored.bus.ram[0xFF]);

    // Verify EmulationState flags
    try testing.expectEqual(state.frame_complete, restored.frame_complete);
    try testing.expectEqual(state.odd_frame, restored.odd_frame);
    try testing.expectEqual(state.rendering_enabled, restored.rendering_enabled);
}

test "Snapshot Integration: Full round-trip with cartridge (reference mode)" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    // Create and load test ROM
    const rom_data = try createTestRom(testing.allocator);
    defer testing.allocator.free(rom_data);

    var nrom_cartridge = try Cartridge.NromCart.loadFromData(testing.allocator, rom_data);
    defer nrom_cartridge.deinit();

    // Create state with cartridge (wrap in AnyCartridge)
    var state = createTestState(&config);
    state.cart = RAMBO.AnyCartridge{ .nrom = nrom_cartridge };

    // Save snapshot (reference mode)
    const snapshot = try Snapshot.saveBinary(
        testing.allocator,
        &state,
        &config,
        .reference,
        false,
        null,
    );
    defer testing.allocator.free(snapshot);

    // Verify snapshot integrity
    try Snapshot.verify(snapshot);

    // Get metadata
    const metadata = try Snapshot.getMetadata(snapshot);
    try testing.expectEqual(@as(u32, 1), metadata.version);
    try testing.expect(!metadata.flags.has_framebuffer);
    try testing.expect(!metadata.flags.cartridge_embedded);

    // Load snapshot (must provide matching cartridge)
    const restored = try Snapshot.loadBinary(
        testing.allocator,
        snapshot,
        &config,
        state.cart,
    );

    // Verify restoration
    try testing.expectEqual(state.cpu.a, restored.cpu.a);
    try testing.expectEqual(state.cpu.pc, restored.cpu.pc);
    try testing.expectEqual(state.clock.frame(), restored.clock.frame());
}

test "Snapshot Integration: Snapshot with framebuffer" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    const state = createTestState(&config);

    // Create test framebuffer (256x240 RGBA)
    const framebuffer_size = 256 * 240 * 4;
    const framebuffer = try testing.allocator.alloc(u8, framebuffer_size);
    defer testing.allocator.free(framebuffer);

    // Fill with test pattern
    for (framebuffer, 0..) |*pixel, i| {
        pixel.* = @intCast(i & 0xFF);
    }

    // Save snapshot with framebuffer
    const snapshot = try Snapshot.saveBinary(
        testing.allocator,
        &state,
        &config,
        .reference,
        true,
        framebuffer,
    );
    defer testing.allocator.free(snapshot);

    // Verify snapshot size includes framebuffer
    try testing.expect(snapshot.len > framebuffer_size);

    // Verify metadata
    const metadata = try Snapshot.getMetadata(snapshot);
    try testing.expect(metadata.flags.has_framebuffer);
    try testing.expectEqual(@as(u32, framebuffer_size), metadata.framebuffer_size);

    // Load and verify
    const restored = try Snapshot.loadBinary(
        testing.allocator,
        snapshot,
        &config,
        @as(?RAMBO.AnyCartridge, null),
    );

    try testing.expectEqual(state.cpu.a, restored.cpu.a);
}

test "Snapshot Integration: Config mismatch detection" {
    var config1 = Config.init(testing.allocator);
    defer config1.deinit();

    const state = createTestState(&config1);

    // Save snapshot with config1
    const snapshot = try Snapshot.saveBinary(
        testing.allocator,
        &state,
        &config1,
        .reference,
        false,
        null,
    );
    defer testing.allocator.free(snapshot);

    // Create different config
    var config2 = Config.init(testing.allocator);
    defer config2.deinit();
    config2.ppu.variant = .rp2c07_pal; // Different from default

    // Attempt to load with mismatched config should fail
    const result = Snapshot.loadBinary(
        testing.allocator,
        snapshot,
        &config2,
        @as(?RAMBO.AnyCartridge, null),
    );
    try testing.expectError(error.ConfigMismatch, result);
}

test "Snapshot Integration: Multiple save/load cycles" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = createTestState(&config);

    // Cycle 1: Save and load
    const snapshot1 = try Snapshot.saveBinary(
        testing.allocator,
        &state,
        &config,
        .reference,
        false,
        null,
    );
    defer testing.allocator.free(snapshot1);

    const restored1 = try Snapshot.loadBinary(
        testing.allocator,
        snapshot1,
        &config,
        @as(?RAMBO.AnyCartridge, null),
    );

    // Modify restored state
    var modified = restored1;
    modified.cpu.a = 0x99;
    modified.clock.ppu_cycles = 100 * 89342; // Frame 100

    // Cycle 2: Save modified state
    const snapshot2 = try Snapshot.saveBinary(
        testing.allocator,
        &modified,
        &config,
        .reference,
        false,
        null,
    );
    defer testing.allocator.free(snapshot2);

    const restored2 = try Snapshot.loadBinary(
        testing.allocator,
        snapshot2,
        &config,
        @as(?RAMBO.AnyCartridge, null),
    );

    // Verify modifications persisted
    try testing.expectEqual(@as(u8, 0x99), restored2.cpu.a);
    try testing.expectEqual(@as(u64, 100), restored2.clock.frame());

    // Original state should be unchanged
    try testing.expectEqual(@as(u8, 0x42), state.cpu.a);
}

test "Snapshot Integration: Metadata inspection" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    const state = createTestState(&config);

    const snapshot = try Snapshot.saveBinary(
        testing.allocator,
        &state,
        &config,
        .reference,
        false,
        null,
    );
    defer testing.allocator.free(snapshot);

    // Get metadata without loading
    const metadata = try Snapshot.getMetadata(snapshot);

    // Verify metadata fields
    try testing.expectEqual(@as(u32, 1), metadata.version);
    try testing.expect(metadata.timestamp > 0);
    try testing.expectEqual(@as(u64, snapshot.len), metadata.total_size);
    try testing.expect(metadata.state_size > 0);
    try testing.expect(!metadata.flags.has_framebuffer);
    try testing.expect(!metadata.flags.compressed);

    // Verify emulator version
    const expected_version = "RAMBO-0.1.0";
    const version_slice = metadata.emulator_version[0..expected_version.len];
    try testing.expectEqualSlices(u8, expected_version, version_slice);
}

test "Snapshot Integration: Snapshot size verification" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    const state = createTestState(&config);

    // Reference mode snapshot (no cartridge)
    const snapshot_ref = try Snapshot.saveBinary(
        testing.allocator,
        &state,
        &config,
        .reference,
        false,
        null,
    );
    defer testing.allocator.free(snapshot_ref);

    // Verify size is reasonable
    // Header (72) + Config (10) + Clock (8) + CPU (33) + PPU (~2407) + Bus (~2065) + Flags (3) + Cartridge (~41)
    // Total: ~4,639 bytes
    try testing.expect(snapshot_ref.len >= 4500);
    try testing.expect(snapshot_ref.len <= 5000);

    // With framebuffer
    const framebuffer_size = 256 * 240 * 4; // 245,760 bytes
    const framebuffer = try testing.allocator.alloc(u8, framebuffer_size);
    defer testing.allocator.free(framebuffer);
    @memset(framebuffer, 0);

    const snapshot_fb = try Snapshot.saveBinary(
        testing.allocator,
        &state,
        &config,
        .reference,
        true,
        framebuffer,
    );
    defer testing.allocator.free(snapshot_fb);

    // Should be ~250KB larger
    try testing.expect(snapshot_fb.len >= snapshot_ref.len + framebuffer_size);
    try testing.expect(snapshot_fb.len <= snapshot_ref.len + framebuffer_size + 100);
}

test "Snapshot Integration: Checksum detection" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    const state = createTestState(&config);

    var snapshot = try Snapshot.saveBinary(
        testing.allocator,
        &state,
        &config,
        .reference,
        false,
        null,
    );
    defer testing.allocator.free(snapshot);

    // Verify original snapshot is valid
    try Snapshot.verify(snapshot);

    // Corrupt data (change byte after header)
    if (snapshot.len > 100) {
        snapshot[100] ^= 0xFF;
    }

    // Verification should fail
    const result = Snapshot.verify(snapshot);
    try testing.expectError(error.ChecksumMismatch, result);
}

test "Snapshot Integration: Invalid snapshot detection" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    // Too small
    const too_small = [_]u8{1} ** 50;
    try testing.expectError(error.InvalidSnapshot, Snapshot.verify(&too_small));

    // Invalid magic
    var invalid_magic = [_]u8{0} ** 100;
    @memcpy(invalid_magic[0..4], "TEST");
    try testing.expectError(error.InvalidMagic, Snapshot.verify(&invalid_magic));

    // Invalid version
    var invalid_version = [_]u8{0} ** 100;
    @memcpy(invalid_version[0..8], "RAMBO\x00\x00\x00");
    // Write version 999 in little-endian at offset 8
    invalid_version[8] = 0xE7;
    invalid_version[9] = 0x03;
    invalid_version[10] = 0x00;
    invalid_version[11] = 0x00;
    try testing.expectError(error.UnsupportedVersion, Snapshot.verify(&invalid_version));
}
