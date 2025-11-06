//! CHR Integration Tests
//!
//! Tests PPU CHR ROM/RAM access through the emulator architecture.
//! Verifies the complete integration chain: Cartridge → EmulationState → PPU

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;
const Cartridge = RAMBO.CartridgeType;

// Test PPU CHR ROM access via cartridge
test "PPU VRAM: CHR ROM read through cartridge" {
    const allocator = testing.allocator;

    // Create minimal valid iNES ROM with CHR data
    var rom_data = [_]u8{0} ** (16 + 16384 + 8192);

    // iNES header (Mapper 0, 16KB PRG, 8KB CHR)
    rom_data[0] = 'N';
    rom_data[1] = 'E';
    rom_data[2] = 'S';
    rom_data[3] = 0x1A;
    rom_data[4] = 1; // 1 × 16KB PRG ROM
    rom_data[5] = 1; // 1 × 8KB CHR ROM
    rom_data[6] = 0; // Mapper 0, horizontal mirroring
    rom_data[7] = 0;

    // Put test pattern in CHR ROM
    // Pattern table 0, tile 0
    const chr_start = 16 + 16384;
    rom_data[chr_start + 0] = 0x42; // Test byte at $0000
    rom_data[chr_start + 7] = 0x99; // Test byte at $0007
    rom_data[chr_start + 8] = 0xAA; // Test byte at $0008 (bitplane 1)

    // Pattern table 1, tile 0
    rom_data[chr_start + 0x1000] = 0xCD; // Test byte at $1000
    rom_data[chr_start + 0x1FFF] = 0xEF; // Test byte at $1FFF (last CHR byte)

    // Load cartridge
    const cart = try Cartridge.loadFromData(allocator, &rom_data);

    // Create harness and load cartridge (takes ownership)
    var harness = try Harness.init();
    defer harness.deinit();
    harness.loadNromCartridge(cart);

    // Test CHR ROM reads
    try testing.expectEqual(@as(u8, 0x42), harness.ppuReadVram(0x0000));
    try testing.expectEqual(@as(u8, 0x99), harness.ppuReadVram(0x0007));
    try testing.expectEqual(@as(u8, 0xAA), harness.ppuReadVram(0x0008));
    try testing.expectEqual(@as(u8, 0xCD), harness.ppuReadVram(0x1000));
    try testing.expectEqual(@as(u8, 0xEF), harness.ppuReadVram(0x1FFF));
}

// Test PPU CHR RAM write/read cycle
test "PPU VRAM: CHR RAM write and read" {
    const allocator = testing.allocator;

    // Create iNES ROM with CHR RAM (chr_rom_size = 0)
    var rom_data = [_]u8{0} ** (16 + 16384);

    // iNES header (Mapper 0, 16KB PRG, NO CHR ROM = CHR RAM)
    rom_data[0] = 'N';
    rom_data[1] = 'E';
    rom_data[2] = 'S';
    rom_data[3] = 0x1A;
    rom_data[4] = 1; // 1 × 16KB PRG ROM
    rom_data[5] = 0; // 0 CHR ROM = 8KB CHR RAM will be allocated
    rom_data[6] = 0; // Mapper 0
    rom_data[7] = 0;

    // Load cartridge (will allocate 8KB CHR RAM)
    const cart = try Cartridge.loadFromData(allocator, &rom_data);

    // Create harness and load cartridge (takes ownership)
    var harness = try Harness.init();
    defer harness.deinit();
    harness.loadNromCartridge(cart);

    // CHR RAM should be initialized to zero
    try testing.expectEqual(@as(u8, 0x00), harness.ppuReadVram(0x0000));

    // Write to CHR RAM via PPU
    harness.ppuWriteVram(0x0000, 0x42);
    harness.ppuWriteVram(0x0FFF, 0x99);
    harness.ppuWriteVram(0x1000, 0xAA);
    harness.ppuWriteVram(0x1FFF, 0xBB);

    // Read back and verify
    try testing.expectEqual(@as(u8, 0x42), harness.ppuReadVram(0x0000));
    try testing.expectEqual(@as(u8, 0x99), harness.ppuReadVram(0x0FFF));
    try testing.expectEqual(@as(u8, 0xAA), harness.ppuReadVram(0x1000));
    try testing.expectEqual(@as(u8, 0xBB), harness.ppuReadVram(0x1FFF));
}

// Test mirroring synchronization from cartridge header
test "PPU VRAM: Mirroring from cartridge header" {
    const allocator = testing.allocator;

    // Create ROM with VERTICAL mirroring
    var rom_data = [_]u8{0} ** (16 + 16384 + 8192);

    // iNES header
    rom_data[0] = 'N';
    rom_data[1] = 'E';
    rom_data[2] = 'S';
    rom_data[3] = 0x1A;
    rom_data[4] = 1; // 1 × 16KB PRG ROM
    rom_data[5] = 1; // 1 × 8KB CHR ROM
    rom_data[6] = 0x01; // Mapper 0, VERTICAL mirroring (bit 0 = 1)
    rom_data[7] = 0;

    // Load cartridge
    const cart = try Cartridge.loadFromData(allocator, &rom_data);

    // Verify vertical mirroring is set from cartridge header
    try testing.expectEqual(@as(@TypeOf(cart.mirroring), .vertical), cart.mirroring);

    // Create harness and load cartridge (takes ownership)
    var harness = try Harness.init();
    defer harness.deinit();
    harness.loadNromCartridge(cart);

    // Test vertical mirroring behavior
    // NT0 ($2000) and NT2 ($2800) should map to same VRAM
    harness.ppuWriteVram(0x2000, 0xAA);
    try testing.expectEqual(@as(u8, 0xAA), harness.ppuReadVram(0x2800)); // Same as NT0

    // NT1 ($2400) and NT3 ($2C00) should map to same VRAM
    harness.ppuWriteVram(0x2400, 0xBB);
    try testing.expectEqual(@as(u8, 0xBB), harness.ppuReadVram(0x2C00)); // Same as NT1
}

// Test PPUDATA ($2007) accessing CHR region
test "PPU VRAM: PPUDATA CHR access with buffering" {
    const allocator = testing.allocator;

    // Create ROM with CHR data
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

    // CHR test data
    const chr_start = 16 + 16384;
    rom_data[chr_start + 0] = 0x11;
    rom_data[chr_start + 1] = 0x22;
    rom_data[chr_start + 2] = 0x33;

    // Load cartridge
    const cart = try Cartridge.loadFromData(allocator, &rom_data);

    // Create harness and load cartridge (takes ownership)
    var harness = try Harness.init();
    defer harness.deinit();
    harness.loadNromCartridge(cart);

    // Set PPUADDR to CHR region ($0000)
    harness.ppuWriteRegister(0x2006, 0x00); // High byte
    harness.ppuWriteRegister(0x2006, 0x00); // Low byte

    // First read from PPUDATA returns buffer (0), fills buffer with $11
    const read1 = harness.ppuReadRegister(0x2007);
    try testing.expectEqual(@as(u8, 0x00), read1);

    // Second read returns $11, fills buffer with $22
    const read2 = harness.ppuReadRegister(0x2007);
    try testing.expectEqual(@as(u8, 0x11), read2);

    // Third read returns $22
    const read3 = harness.ppuReadRegister(0x2007);
    try testing.expectEqual(@as(u8, 0x22), read3);
}

// Test open bus behavior without cartridge
test "PPU VRAM: Open bus when no cartridge" {
    var harness = try Harness.init();
    defer harness.deinit();

    // No cartridge loaded - accessing CHR region should return open bus value
    // Set open bus to known value via PPU write
    harness.state.ppu.open_bus.setAll(0x42, harness.state.ppu.frame_count);

    // Reading CHR with no cartridge should return open bus value
    const value = harness.ppuReadVram(0x0000);
    try testing.expectEqual(@as(u8, 0x42), value);

    // Change open bus value
    harness.state.ppu.open_bus.setAll(0x99, harness.state.ppu.frame_count);

    // Should return new open bus value
    const value2 = harness.ppuReadVram(0x1000);
    try testing.expectEqual(@as(u8, 0x99), value2);
}

// Test CHR ROM is read-only (writes ignored)
test "PPU VRAM: CHR ROM writes are ignored" {
    const allocator = testing.allocator;

    // Create ROM with CHR ROM (not RAM)
    var rom_data = [_]u8{0} ** (16 + 16384 + 8192);

    // iNES header
    rom_data[0] = 'N';
    rom_data[1] = 'E';
    rom_data[2] = 'S';
    rom_data[3] = 0x1A;
    rom_data[4] = 1;
    rom_data[5] = 1; // CHR ROM, not RAM
    rom_data[6] = 0;
    rom_data[7] = 0;

    // CHR ROM data
    const chr_start = 16 + 16384;
    rom_data[chr_start + 0] = 0x42;

    // Load cartridge
    const cart = try Cartridge.loadFromData(allocator, &rom_data);

    // Create harness and load cartridge (takes ownership)
    var harness = try Harness.init();
    defer harness.deinit();
    harness.loadNromCartridge(cart);

    // Verify initial value
    try testing.expectEqual(@as(u8, 0x42), harness.ppuReadVram(0x0000));

    // Try to write (should be ignored for CHR ROM)
    harness.ppuWriteVram(0x0000, 0x99);

    // Value should remain unchanged
    try testing.expectEqual(@as(u8, 0x42), harness.ppuReadVram(0x0000));
}
