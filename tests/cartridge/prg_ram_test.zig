const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const CartType = RAMBO.Cartridge.NromCart; // Type alias for Mapper 0 cartridge

// ============================================================================
// PRG RAM Tests for Mapper 0 (NROM)
// ============================================================================
//
// Tests PRG RAM allocation, read/write functionality, and integration with
// the comptime generic Cartridge system.
//
// Key Requirements:
// - Always allocate 8KB PRG RAM for Mapper 0 (industry standard)
// - PRG RAM at CPU $6000-$7FFF
// - Zero-initialized on load
// - Independent from PRG ROM

// ============================================================================
// Test 1: PRG RAM Allocation
// ============================================================================

test "PRG RAM: Always allocated for Mapper 0" {
    // Create minimal NROM ROM with header indicating 0 PRG RAM
    var rom_data = [_]u8{0} ** (16 + 16384 + 8192);

    // iNES header
    rom_data[0] = 'N';
    rom_data[1] = 'E';
    rom_data[2] = 'S';
    rom_data[3] = 0x1A;
    rom_data[4] = 1; // 1 x 16KB PRG ROM
    rom_data[5] = 1; // 1 x 8KB CHR ROM
    rom_data[6] = 0; // Mapper 0, no battery
    rom_data[7] = 0; // Mapper 0
    rom_data[8] = 0; // PRG RAM size = 0 (but we still allocate 8KB)

    var cart = try CartType.loadFromData(testing.allocator, &rom_data);
    defer cart.deinit();

    // Verify PRG RAM is allocated (8KB)
    try testing.expect(cart.prg_ram != null);
    try testing.expectEqual(@as(usize, 8192), cart.prg_ram.?.len);
}

// ============================================================================
// Test 2: PRG RAM Zero-Initialization
// ============================================================================

test "PRG RAM: Zero-initialized on load" {
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

    var cart = try CartType.loadFromData(testing.allocator, &rom_data);
    defer cart.deinit();

    // Verify all PRG RAM bytes are zero
    const ram = cart.prg_ram.?;
    for (ram) |byte| {
        try testing.expectEqual(@as(u8, 0), byte);
    }
}

// ============================================================================
// Test 3: PRG RAM Read/Write via Mapper
// ============================================================================

test "PRG RAM: Read/Write at $6000-$7FFF" {
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

    var cart = try CartType.loadFromData(testing.allocator, &rom_data);
    defer cart.deinit();

    // Write to PRG RAM via cartridge interface
    cart.cpuWrite(0x6000, 0xAA); // First byte
    cart.cpuWrite(0x6FFF, 0xBB); // Middle
    cart.cpuWrite(0x7000, 0xCC); // Second half
    cart.cpuWrite(0x7FFF, 0xDD); // Last byte

    // Read back values
    try testing.expectEqual(@as(u8, 0xAA), cart.cpuRead(0x6000));
    try testing.expectEqual(@as(u8, 0xBB), cart.cpuRead(0x6FFF));
    try testing.expectEqual(@as(u8, 0xCC), cart.cpuRead(0x7000));
    try testing.expectEqual(@as(u8, 0xDD), cart.cpuRead(0x7FFF));
}

// ============================================================================
// Test 4: PRG RAM Address Calculation
// ============================================================================

test "PRG RAM: Correct address offset calculation" {
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

    var cart = try CartType.loadFromData(testing.allocator, &rom_data);
    defer cart.deinit();

    // $6000 → offset 0
    cart.cpuWrite(0x6000, 0x11);
    try testing.expectEqual(@as(u8, 0x11), cart.prg_ram.?[0]);

    // $6001 → offset 1
    cart.cpuWrite(0x6001, 0x22);
    try testing.expectEqual(@as(u8, 0x22), cart.prg_ram.?[1]);

    // $7FFF → offset 8191 (last byte)
    cart.cpuWrite(0x7FFF, 0x33);
    try testing.expectEqual(@as(u8, 0x33), cart.prg_ram.?[8191]);
}

// ============================================================================
// Test 5: PRG RAM Independence from PRG ROM
// ============================================================================

test "PRG RAM: Independent from PRG ROM" {
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

    // Put test data in PRG ROM
    rom_data[16] = 0xFF; // First byte of PRG ROM

    var cart = try CartType.loadFromData(testing.allocator, &rom_data);
    defer cart.deinit();

    // Verify PRG ROM has the data
    try testing.expectEqual(@as(u8, 0xFF), cart.cpuRead(0x8000));

    // Verify PRG RAM is independent (should be zero)
    try testing.expectEqual(@as(u8, 0x00), cart.cpuRead(0x6000));

    // Write to PRG RAM
    cart.cpuWrite(0x6000, 0x42);
    try testing.expectEqual(@as(u8, 0x42), cart.cpuRead(0x6000));

    // PRG ROM should remain unchanged
    try testing.expectEqual(@as(u8, 0xFF), cart.cpuRead(0x8000));
}

// ============================================================================
// Test 6: PRG RAM Persistence Across Reads
// ============================================================================

test "PRG RAM: Values persist across multiple reads" {
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

    var cart = try CartType.loadFromData(testing.allocator, &rom_data);
    defer cart.deinit();

    // Write a pattern to PRG RAM
    cart.cpuWrite(0x6100, 0x55);

    // Read multiple times - should always return same value
    try testing.expectEqual(@as(u8, 0x55), cart.cpuRead(0x6100));
    try testing.expectEqual(@as(u8, 0x55), cart.cpuRead(0x6100));
    try testing.expectEqual(@as(u8, 0x55), cart.cpuRead(0x6100));

    // Overwrite
    cart.cpuWrite(0x6100, 0xAA);

    // New value should persist
    try testing.expectEqual(@as(u8, 0xAA), cart.cpuRead(0x6100));
    try testing.expectEqual(@as(u8, 0xAA), cart.cpuRead(0x6100));
}

// ============================================================================
// Test 7: Full PRG RAM Write/Read Pattern
// ============================================================================

test "PRG RAM: Full 8KB write/read pattern" {
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

    var cart = try CartType.loadFromData(testing.allocator, &rom_data);
    defer cart.deinit();

    // Write pattern to entire PRG RAM
    var addr: u16 = 0x6000;
    while (addr <= 0x7FFF) : (addr += 1) {
        const pattern = @as(u8, @truncate(addr & 0xFF));
        cart.cpuWrite(addr, pattern);
    }

    // Verify pattern
    addr = 0x6000;
    while (addr <= 0x7FFF) : (addr += 1) {
        const expected = @as(u8, @truncate(addr & 0xFF));
        const actual = cart.cpuRead(addr);
        try testing.expectEqual(expected, actual);
    }
}

// ============================================================================
// Test 8: PRG RAM Cleanup (deinit)
// ============================================================================

test "PRG RAM: Properly freed on deinit" {
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


    // Create and destroy multiple times - should not leak
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var cart = try CartType.loadFromData(testing.allocator, &rom_data);
        try testing.expect(cart.prg_ram != null);
        cart.deinit();
    }
}
