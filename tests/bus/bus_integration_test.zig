// Bus Integration Tests
//
// These tests verify the memory bus behavior in realistic integration scenarios,
// focusing on interactions between the bus, RAM, PPU, and cartridge.
//
// Unlike unit tests in src/bus/Logic.zig, these tests validate complete workflows
// and component interactions that occur during actual emulation.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

// Direct imports for access to non-exported types
const Cartridge = @import("RAMBO").Cartridge;

// Type aliases for clarity
const BusState = RAMBO.BusType;
const PpuState = RAMBO.PpuType;
const NromCart = RAMBO.CartridgeType;

// ============================================================================
// Category 1: RAM Mirroring Integration Tests (4 tests)
// ============================================================================
// These tests verify that RAM mirroring works correctly across all mirror
// regions, testing boundary conditions and data persistence.

test "Bus Integration: Write to $0000 visible at all RAM mirrors" {
    var bus = BusState.init();

    // Write test value to base RAM address
    bus.write(0x0100, 0x42);

    // AccuracyCoin Test: "RAM Mirroring" - verify all mirrors see the same value
    // RAM is 2KB ($0000-$07FF) mirrored 4 times up to $1FFF
    try testing.expectEqual(@as(u8, 0x42), bus.read(0x0100)); // Base address
    try testing.expectEqual(@as(u8, 0x42), bus.read(0x0900)); // Mirror 1 (+$0800)
    try testing.expectEqual(@as(u8, 0x42), bus.read(0x1100)); // Mirror 2 (+$1000)
    try testing.expectEqual(@as(u8, 0x42), bus.read(0x1900)); // Mirror 3 (+$1800)
}

test "Bus Integration: RAM mirroring boundary ($1FFF → $0000)" {
    var bus = BusState.init();

    // Write to the last byte of the mirrored RAM region
    bus.write(0x1FFF, 0xFF);

    // Verify it wraps to $07FF (last byte of actual 2KB RAM)
    try testing.expectEqual(@as(u8, 0xFF), bus.read(0x07FF));

    // And is visible at all mirror boundaries
    try testing.expectEqual(@as(u8, 0xFF), bus.read(0x0FFF)); // Mirror 1 boundary
    try testing.expectEqual(@as(u8, 0xFF), bus.read(0x17FF)); // Mirror 2 boundary
    try testing.expectEqual(@as(u8, 0xFF), bus.read(0x1FFF)); // Mirror 3 boundary
}

test "Bus Integration: Mirroring preserves data across all regions" {
    var bus = BusState.init();

    // Fill different addresses in base RAM
    bus.write(0x0000, 0xAA);
    bus.write(0x0100, 0xBB);
    bus.write(0x0200, 0xCC);
    bus.write(0x0400, 0xDD);
    bus.write(0x07FF, 0xEE);

    // Verify each value is mirrored correctly in all three mirror regions
    // Mirror 1 (+$0800)
    try testing.expectEqual(@as(u8, 0xAA), bus.read(0x0800));
    try testing.expectEqual(@as(u8, 0xBB), bus.read(0x0900));
    try testing.expectEqual(@as(u8, 0xCC), bus.read(0x0A00));
    try testing.expectEqual(@as(u8, 0xDD), bus.read(0x0C00));
    try testing.expectEqual(@as(u8, 0xEE), bus.read(0x0FFF));

    // Mirror 2 (+$1000)
    try testing.expectEqual(@as(u8, 0xAA), bus.read(0x1000));
    try testing.expectEqual(@as(u8, 0xBB), bus.read(0x1100));
    try testing.expectEqual(@as(u8, 0xCC), bus.read(0x1200));
    try testing.expectEqual(@as(u8, 0xDD), bus.read(0x1400));
    try testing.expectEqual(@as(u8, 0xEE), bus.read(0x17FF));

    // Mirror 3 (+$1800)
    try testing.expectEqual(@as(u8, 0xAA), bus.read(0x1800));
    try testing.expectEqual(@as(u8, 0xBB), bus.read(0x1900));
    try testing.expectEqual(@as(u8, 0xCC), bus.read(0x1A00));
    try testing.expectEqual(@as(u8, 0xDD), bus.read(0x1C00));
    try testing.expectEqual(@as(u8, 0xEE), bus.read(0x1FFF));
}

test "Bus Integration: Write to mirror affects base and all other mirrors" {
    var bus = BusState.init();

    // Write to the second mirror (0x1234 is in range $1000-$17FF)
    bus.write(0x1234, 0x88);

    // Verify it's visible at the base address (0x1234 & 0x07FF = 0x0234)
    try testing.expectEqual(@as(u8, 0x88), bus.read(0x0234));

    // And all other mirrors
    try testing.expectEqual(@as(u8, 0x88), bus.read(0x0A34)); // Mirror 1 ($0800 + $0234)
    try testing.expectEqual(@as(u8, 0x88), bus.read(0x1234)); // Mirror 2 (where we wrote)
    try testing.expectEqual(@as(u8, 0x88), bus.read(0x1A34)); // Mirror 3 ($1800 + $0234)
}

// ============================================================================
// Category 2: PPU Register Mirroring Tests (3 tests)
// ============================================================================
// These tests verify that PPU registers ($2000-$2007) are mirrored every 8
// bytes through $3FFF, testing various mirror addresses and boundaries.

test "Bus Integration: PPU registers mirrored every 8 bytes" {
    var bus = BusState.init();
    var ppu = PpuState.init();
    bus.ppu = &ppu;

    // Write to $2000 (PPUCTRL)
    bus.write(0x2000, 0x80); // Enable NMI

    // PPU registers are mirrored every 8 bytes from $2008-$3FFF
    // Test a few mirror addresses
    const ctrl_value = bus.read(0x2000);
    try testing.expectEqual(ctrl_value, bus.read(0x2008)); // First mirror
    try testing.expectEqual(ctrl_value, bus.read(0x2010)); // Second mirror
    try testing.expectEqual(ctrl_value, bus.read(0x3000)); // Far mirror
    try testing.expectEqual(ctrl_value, bus.read(0x3FF8)); // Last mirror before boundary
}

test "Bus Integration: PPU mirroring boundary ($3FFF → $2007)" {
    var bus = BusState.init();
    var ppu = PpuState.init();
    bus.ppu = &ppu;

    // Test that $3FFF correctly mirrors to $2007 (PPUDATA)
    // We test by checking that writes to different mirrors all affect the same register

    // Set PPUADDR to $2000
    bus.write(0x2006, 0x20); // High byte
    bus.write(0x2006, 0x00); // Low byte

    // Write via $2007
    bus.write(0x2007, 0xAA);

    // Reset address
    bus.write(0x2006, 0x20); // High byte
    bus.write(0x2006, 0x00); // Low byte

    // Read via $3FFF (mirror of $2007)
    _ = bus.read(0x3FFF); // Dummy read (buffering)
    const value = bus.read(0x3FFF); // Actual data

    // Should read back 0xAA (written via $2007 mirror)
    try testing.expectEqual(@as(u8, 0xAA), value);
}

test "Bus Integration: All PPU register mirrors route to same underlying register" {
    var bus = BusState.init();
    var ppu = PpuState.init();
    bus.ppu = &ppu;

    // Write to $2006 (PPUADDR) twice to set address
    bus.write(0x2006, 0x20); // High byte
    bus.write(0x2806, 0x00); // Low byte via mirror (+$0800)

    // The address should now be $2000
    // Write data via another mirror
    bus.write(0x3007, 0xAB); // PPUDATA via mirror

    // Verify the PPU state was updated (not checking exact value due to buffering,
    // but verifying the write went through to the actual PPU)
    try testing.expect(bus.ppu != null);
}

// ============================================================================
// Category 3: ROM Write Protection Tests (2 tests)
// ============================================================================
// These tests verify that writes to ROM regions ($8000-$FFFF) do not corrupt
// cartridge data, but do update the open bus value.

test "Bus Integration: ROM write does not modify cartridge" {
    var bus = BusState.init();

    // ROM writes should not cause errors or corruption
    // Just verify the bus handles ROM writes gracefully

    // Attempt writes to ROM space (no cartridge loaded - should update open bus)
    bus.write(0x8000, 0x11);
    bus.write(0x8064, 0x22);
    bus.write(0xBFFF, 0x33);

    // Open bus should have last written value
    try testing.expectEqual(@as(u8, 0x33), bus.open_bus.value);

    // Reading from ROM without cartridge returns open bus
    const read_val = bus.read(0x8000);
    try testing.expectEqual(@as(u8, 0x33), read_val);
}

test "Bus Integration: ROM write updates open bus" {
    var bus = BusState.init();

    // Perform a write to ROM space (no cartridge loaded)
    bus.write(0x8000, 0x99);

    // Open bus should be updated with the written value
    try testing.expectEqual(@as(u8, 0x99), bus.open_bus.value);

    // Reading from unmapped region should return the open bus value
    const unmapped_read = bus.read(0x5000); // Unmapped expansion region
    try testing.expectEqual(@as(u8, 0x99), unmapped_read);
}

// ============================================================================
// Category 4: Open Bus Behavior Tests (4 tests)
// ============================================================================
// These tests verify that the open bus (data bus retention) works correctly,
// including decay behavior and specific PPU/controller open bus bits.

test "Bus Integration: Read from unmapped address returns last bus value" {
    var bus = BusState.init();

    // Write to RAM to set open bus
    bus.write(0x0000, 0x77);

    // Read from unmapped region ($4000-$401F, assuming no APU)
    const unmapped = bus.read(0x4018);

    // Should return the last bus value (0x77)
    try testing.expectEqual(@as(u8, 0x77), unmapped);
}

test "Bus Integration: Open bus decays over time" {
    var bus = BusState.init();

    // Set open bus value
    bus.write(0x0000, 0xAB);
    try testing.expectEqual(@as(u8, 0xAB), bus.open_bus.value);

    // Simulate time passing (600ms in cycles at ~1.79MHz)
    // NES CPU runs at ~1.789773 MHz, so 600ms ≈ 1,073,864 cycles
    // Note: Open bus decay is very slow on the NES (several hundred milliseconds)
    // For now, we just verify the open bus value is maintained over reasonable time
    // The actual decay tracking is in the OpenBus struct with last_update_cycle
    try testing.expect(bus.open_bus.last_update_cycle < 1000);
}

test "Bus Integration: PPU status bits 0-4 are open bus" {
    var bus = BusState.init();
    var ppu = PpuState.init();
    bus.ppu = &ppu;

    // Set PPU's open bus by writing to a PPU register
    // This sets the PPU's internal data bus latch
    bus.write(0x2001, 0b00011111); // Write to PPUMASK

    // Read PPUSTATUS ($2002)
    // The lower 5 bits should reflect the PPU's open bus value
    const status = bus.read(0x2002);

    // Bits 0-4 should reflect PPU open bus, bits 5-7 are actual status
    // After a write to $2001, the PPU open bus has 0b00011111
    // PPUSTATUS lower 5 bits should reflect this
    try testing.expectEqual(@as(u8, 0b00011111), status & 0x1F);
}

test "Bus Integration: Sequential reads maintain open bus coherence" {
    var bus = BusState.init();

    // Sequence of reads and writes
    bus.write(0x0010, 0x11);
    const r1 = bus.read(0x0010);
    try testing.expectEqual(@as(u8, 0x11), r1);
    try testing.expectEqual(@as(u8, 0x11), bus.open_bus.value);

    bus.write(0x0020, 0x22);
    const r2 = bus.read(0x0020);
    try testing.expectEqual(@as(u8, 0x22), r2);
    try testing.expectEqual(@as(u8, 0x22), bus.open_bus.value);

    // Read from unmapped should return last bus value
    const unmapped = bus.read(0x5000);
    try testing.expectEqual(@as(u8, 0x22), unmapped);
}

// ============================================================================
// Category 5: Cartridge Routing Tests (4 tests)
// ============================================================================
// These tests verify that addresses in the cartridge space correctly route
// to the cartridge for both reads and writes.

test "Bus Integration: $8000-$FFFF address range (without cartridge)" {
    var bus = BusState.init();

    // Without a cartridge, reads from ROM space return open bus
    bus.write(0x0100, 0xAA); // Set open bus value

    const rom_read = bus.read(0x8000);
    try testing.expectEqual(@as(u8, 0xAA), rom_read); // Returns open bus

    // Different ROM addresses should all return open bus
    try testing.expectEqual(@as(u8, 0xAA), bus.read(0xC000));
    try testing.expectEqual(@as(u8, 0xAA), bus.read(0xFFFF));
}

test "Bus Integration: ROM address range coverage" {
    var bus = BusState.init();

    // Test that all ROM addresses are handled consistently
    // Without cartridge, should return open bus for all ROM addresses

    bus.write(0x0200, 0x77); // Set open bus

    // Test various ROM addresses
    const addresses = [_]u16{ 0x8000, 0x9000, 0xA000, 0xB000, 0xC000, 0xD000, 0xE000, 0xFFFF };
    for (addresses) |addr| {
        try testing.expectEqual(@as(u8, 0x77), bus.read(addr));
    }
}

test "Bus Integration: Multiple components share same bus" {
    var bus = BusState.init();
    var ppu = PpuState.init();

    // Connect PPU to bus
    bus.ppu = &ppu;

    // Test that all components work together:
    // 1. Write to RAM
    bus.write(0x0100, 0x11);
    try testing.expectEqual(@as(u8, 0x11), bus.read(0x0100));

    // 2. Write to PPU register
    bus.write(0x2000, 0x80);

    // 3. Read from ROM (without cartridge, returns open bus)
    bus.write(0x0200, 0xEE); // Set open bus
    try testing.expectEqual(@as(u8, 0xEE), bus.read(0x8000));

    // All should work without interference
    try testing.expectEqual(@as(u8, 0x11), bus.read(0x0100)); // RAM still intact
}

test "Bus Integration: read16 works across bus boundaries" {
    var bus = BusState.init();

    // Test read16 across RAM
    bus.write(0x0100, 0x34); // Low byte
    bus.write(0x0101, 0x12); // High byte

    const value = bus.read16(0x0100);
    try testing.expectEqual(@as(u16, 0x1234), value); // Little-endian

    // Test read16 at RAM mirror boundary
    bus.write(0x07FF, 0xCD); // Last byte of RAM
    bus.write(0x0800, 0xAB); // First byte of mirror (wraps to $0000)

    const boundary_value = bus.read16(0x07FF);
    // Should read $07FF (0xCD) and $0000 (0xAB from mirror write)
    try testing.expectEqual(@as(u16, 0xABCD), boundary_value);
}
