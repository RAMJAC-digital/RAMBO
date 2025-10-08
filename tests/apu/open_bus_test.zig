const std = @import("std");
const testing = std.testing;
const EmulationState = @import("RAMBO").EmulationState.EmulationState;
const Config = @import("RAMBO").Config.Config;

// ============================================================================
// APU Register Open Bus Tests
// ============================================================================
//
// Tests that write-only APU registers return open bus values correctly
// and that reading $4015 doesn't update open bus.

// Test helper: Create EmulationState for open bus testing
fn createTestState() EmulationState {
    var config = Config.init(testing.allocator);
    config.deinit(); // Leak for test simplicity - tests are short-lived
    return EmulationState.init(&config);
}

test "Open Bus: $4000-$4013 return open bus" {
    var emu = createTestState();
    defer emu.deinit();

    // Set open bus to known value
    emu.bus.open_bus = 0xAB;

    // All APU channel registers should return open bus
    try testing.expectEqual(@as(u8, 0xAB), emu.busRead(0x4000)); // Pulse 1 Vol
    try testing.expectEqual(@as(u8, 0xAB), emu.busRead(0x4001)); // Pulse 1 Sweep
    try testing.expectEqual(@as(u8, 0xAB), emu.busRead(0x4002)); // Pulse 1 Lo
    try testing.expectEqual(@as(u8, 0xAB), emu.busRead(0x4003)); // Pulse 1 Hi

    try testing.expectEqual(@as(u8, 0xAB), emu.busRead(0x4004)); // Pulse 2 Vol
    try testing.expectEqual(@as(u8, 0xAB), emu.busRead(0x4005)); // Pulse 2 Sweep
    try testing.expectEqual(@as(u8, 0xAB), emu.busRead(0x4006)); // Pulse 2 Lo
    try testing.expectEqual(@as(u8, 0xAB), emu.busRead(0x4007)); // Pulse 2 Hi

    try testing.expectEqual(@as(u8, 0xAB), emu.busRead(0x4008)); // Triangle Linear
    try testing.expectEqual(@as(u8, 0xAB), emu.busRead(0x400A)); // Triangle Lo
    try testing.expectEqual(@as(u8, 0xAB), emu.busRead(0x400B)); // Triangle Hi

    try testing.expectEqual(@as(u8, 0xAB), emu.busRead(0x400C)); // Noise Vol
    try testing.expectEqual(@as(u8, 0xAB), emu.busRead(0x400E)); // Noise Period
    try testing.expectEqual(@as(u8, 0xAB), emu.busRead(0x400F)); // Noise Length

    try testing.expectEqual(@as(u8, 0xAB), emu.busRead(0x4010)); // DMC Freq
    try testing.expectEqual(@as(u8, 0xAB), emu.busRead(0x4011)); // DMC Counter
    try testing.expectEqual(@as(u8, 0xAB), emu.busRead(0x4012)); // DMC Address
    try testing.expectEqual(@as(u8, 0xAB), emu.busRead(0x4013)); // DMC Length
}

test "Open Bus: $4014 (OAMDMA) returns open bus" {
    var emu = createTestState();
    defer emu.deinit();

    // Set open bus to known value
    emu.bus.open_bus = 0xCD;

    try testing.expectEqual(@as(u8, 0xCD), emu.busRead(0x4014));
}

test "Open Bus: $4015 read doesn't update open bus" {
    var emu = createTestState();
    defer emu.deinit();

    // Set open bus to known value
    emu.bus.open_bus = 0x42;

    // Set some APU status flags
    emu.apu.pulse1_length = 10;
    emu.apu.frame_irq_flag = true;

    // Read $4015 - should return status with flags set
    const status = emu.busRead(0x4015);
    try testing.expectEqual(@as(u8, 0x41), status); // Bit 6 (frame IRQ) + Bit 0 (pulse1 active)

    // Open bus should NOT have changed
    try testing.expectEqual(@as(u8, 0x42), emu.bus.open_bus);
}

test "Open Bus: Write to $4000-$4013 updates open bus" {
    var emu = createTestState();
    defer emu.deinit();

    // Write to various APU registers
    emu.busWrite(0x4000, 0x55);
    try testing.expectEqual(@as(u8, 0x55), emu.bus.open_bus);

    emu.busWrite(0x4001, 0x66);
    try testing.expectEqual(@as(u8, 0x66), emu.bus.open_bus);

    emu.busWrite(0x4008, 0x77);
    try testing.expectEqual(@as(u8, 0x77), emu.bus.open_bus);

    emu.busWrite(0x4015, 0x88);
    try testing.expectEqual(@as(u8, 0x88), emu.bus.open_bus);
}

test "Open Bus: Write to $4017 updates open bus" {
    var emu = createTestState();
    defer emu.deinit();

    // Write to frame counter
    emu.busWrite(0x4017, 0x99);
    try testing.expectEqual(@as(u8, 0x99), emu.bus.open_bus);
}

test "Open Bus: Read from other addresses updates open bus" {
    var emu = createTestState();
    defer emu.deinit();

    // Set RAM to known value
    emu.bus.ram[0x100] = 0xAA;

    // Set open bus to different value
    emu.bus.open_bus = 0x00;

    // Read from RAM - should update open bus
    const value = emu.busRead(0x100);
    try testing.expectEqual(@as(u8, 0xAA), value);
    try testing.expectEqual(@as(u8, 0xAA), emu.bus.open_bus);
}

test "Open Bus: $4016/$4017 controller reads preserve bits 5-7" {
    var emu = createTestState();
    defer emu.deinit();

    // Set open bus high bits
    emu.bus.open_bus = 0xE0; // Bits 5-7 set

    // Controller data will be in bit 0, open bus in bits 5-7
    const ctrl1 = emu.busRead(0x4016);
    const ctrl2 = emu.busRead(0x4017);

    // Bits 5-7 should preserve open bus
    try testing.expectEqual(@as(u8, 0xE0), ctrl1 & 0xE0);
    try testing.expectEqual(@as(u8, 0xE0), ctrl2 & 0xE0);
}
