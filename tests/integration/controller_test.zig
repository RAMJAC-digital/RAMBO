//! NES Controller Integration Tests
//!
//! Tests cycle-accurate 4021 shift register behavior following nesdev specs
//! Covers AccuracyCoin controller test requirements

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;
const EmulationState = RAMBO.EmulationState.EmulationState;
const ControllerState = RAMBO.EmulationState.ControllerState;

// ============================================================================
// Test 1: Strobe Protocol (AccuracyCoin: Controller Strobing)
// ============================================================================

test "Controller: strobe on bit 0 only" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Set button data (A button pressed)
    harness.state.controller.buttons1 = 0b00000001;

    // Write $02 to $4016 (bit 0 = 0, should NOT strobe)
    harness.state.busWrite(0x4016, 0x02);
    try testing.expect(harness.state.controller.strobe == false);

    // Write $01 to $4016 (bit 0 = 1, should strobe)
    harness.state.busWrite(0x4016, 0x01);
    try testing.expect(harness.state.controller.strobe == true);

    // Write $FF to $4016 (bit 0 = 1, should strobe)
    harness.state.busWrite(0x4016, 0xFF);
    try testing.expect(harness.state.controller.strobe == true);
}

test "Controller: latch on rising edge" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Set button data (A+B pressed)
    harness.state.controller.buttons1 = 0b00000011;

    // Strobe high (latch buttons)
    harness.state.busWrite(0x4016, 0x01);
    try testing.expectEqual(@as(u8, 0b00000011), harness.state.controller.shift1);

    // Strobe low (enter shift mode)
    harness.state.busWrite(0x4016, 0x00);

    // Read should shift out A button (bit 0)
    const bit0 = harness.state.busRead(0x4016);
    try testing.expectEqual(@as(u8, 0x01), bit0 & 0x01);
}

test "Controller: no latch on falling edge" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Initial buttons: A pressed
    harness.state.controller.buttons1 = 0b00000001;
    harness.state.busWrite(0x4016, 0x01); // Latch

    // Change buttons: B pressed (but strobe is still high)
    harness.state.controller.buttons1 = 0b00000010;

    // Go low - should NOT re-latch new button state
    harness.state.busWrite(0x4016, 0x00);

    // Read should return original A button state
    const bit0 = harness.state.busRead(0x4016);
    try testing.expectEqual(@as(u8, 0x01), bit0 & 0x01);
}

// ============================================================================
// Test 2: Shift Register Clocking (AccuracyCoin: Controller Clocking)
// ============================================================================

test "Controller: 8-bit shift sequence" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Button sequence: A, B, Select, Start, Up, Down, Left, Right
    // Press: A (bit 0), Start (bit 3), Right (bit 7)
    harness.state.controller.buttons1 = 0b10001001;

    // Latch buttons
    harness.state.busWrite(0x4016, 0x01);
    harness.state.busWrite(0x4016, 0x00);

    // Read 8 bits in sequence
    try testing.expectEqual(@as(u8, 1), harness.state.busRead(0x4016) & 0x01); // A = 1
    try testing.expectEqual(@as(u8, 0), harness.state.busRead(0x4016) & 0x01); // B = 0
    try testing.expectEqual(@as(u8, 0), harness.state.busRead(0x4016) & 0x01); // Select = 0
    try testing.expectEqual(@as(u8, 1), harness.state.busRead(0x4016) & 0x01); // Start = 1
    try testing.expectEqual(@as(u8, 0), harness.state.busRead(0x4016) & 0x01); // Up = 0
    try testing.expectEqual(@as(u8, 0), harness.state.busRead(0x4016) & 0x01); // Down = 0
    try testing.expectEqual(@as(u8, 0), harness.state.busRead(0x4016) & 0x01); // Left = 0
    try testing.expectEqual(@as(u8, 1), harness.state.busRead(0x4016) & 0x01); // Right = 1
}

test "Controller: reads >8 return 1" {
    var harness = try Harness.init();
    defer harness.deinit();

    // All buttons released
    harness.state.controller.buttons1 = 0x00;

    // Latch and shift
    harness.state.busWrite(0x4016, 0x01);
    harness.state.busWrite(0x4016, 0x00);

    // Read 8 bits (should all be 0)
    for (0..8) |_| {
        try testing.expectEqual(@as(u8, 0), harness.state.busRead(0x4016) & 0x01);
    }

    // Reads 9+ should return 1 (shift register fills with 1s)
    for (0..5) |_| {
        try testing.expectEqual(@as(u8, 1), harness.state.busRead(0x4016) & 0x01);
    }
}

test "Controller: strobe high prevents shifting" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Press A button
    harness.state.controller.buttons1 = 0b00000001;

    // Strobe high (latch mode)
    harness.state.busWrite(0x4016, 0x01);

    // Multiple reads should all return A button (bit 0 = 1)
    for (0..10) |_| {
        try testing.expectEqual(@as(u8, 1), harness.state.busRead(0x4016) & 0x01);
    }

    // Shift register should NOT have shifted
    try testing.expectEqual(@as(u8, 0b00000001), harness.state.controller.shift1);
}

// ============================================================================
// Test 3: Button Sequence Validation
// ============================================================================

test "Controller: correct button order" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Press all buttons
    harness.state.controller.buttons1 = 0xFF;

    // Latch and shift
    harness.state.busWrite(0x4016, 0x01);
    harness.state.busWrite(0x4016, 0x00);

    // Verify button order: A, B, Select, Start, Up, Down, Left, Right
    const expected = [_][]const u8{ "A", "B", "Select", "Start", "Up", "Down", "Left", "Right" };
    for (expected) |button_name| {
        const bit = harness.state.busRead(0x4016) & 0x01;
        try testing.expectEqual(@as(u8, 1), bit); // All pressed
        _ = button_name; // Suppress unused warning
    }
}

test "Controller: individual button isolation" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Test each button individually
    const button_tests = [_]struct {
        buttons: u8,
        expected: [8]u8,
        name: []const u8,
    }{
        .{ .buttons = 0b00000001, .expected = .{ 1, 0, 0, 0, 0, 0, 0, 0 }, .name = "A only" },
        .{ .buttons = 0b00000010, .expected = .{ 0, 1, 0, 0, 0, 0, 0, 0 }, .name = "B only" },
        .{ .buttons = 0b00000100, .expected = .{ 0, 0, 1, 0, 0, 0, 0, 0 }, .name = "Select only" },
        .{ .buttons = 0b00001000, .expected = .{ 0, 0, 0, 1, 0, 0, 0, 0 }, .name = "Start only" },
        .{ .buttons = 0b00010000, .expected = .{ 0, 0, 0, 0, 1, 0, 0, 0 }, .name = "Up only" },
        .{ .buttons = 0b00100000, .expected = .{ 0, 0, 0, 0, 0, 1, 0, 0 }, .name = "Down only" },
        .{ .buttons = 0b01000000, .expected = .{ 0, 0, 0, 0, 0, 0, 1, 0 }, .name = "Left only" },
        .{ .buttons = 0b10000000, .expected = .{ 0, 0, 0, 0, 0, 0, 0, 1 }, .name = "Right only" },
    };

    for (button_tests) |test_case| {
        harness.state.controller.buttons1 = test_case.buttons;
        harness.state.busWrite(0x4016, 0x01);
        harness.state.busWrite(0x4016, 0x00);

        for (test_case.expected) |expected_bit| {
            const actual_bit = harness.state.busRead(0x4016) & 0x01;
            try testing.expectEqual(expected_bit, actual_bit);
        }
    }
}

// ============================================================================
// Test 4: Controller 2 ($4017)
// ============================================================================

test "Controller: controller 2 independent" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Different button states
    harness.state.controller.buttons1 = 0b00000001; // Controller 1: A
    harness.state.controller.buttons2 = 0b00000010; // Controller 2: B

    // Latch both
    harness.state.busWrite(0x4016, 0x01);
    harness.state.busWrite(0x4016, 0x00);

    // Read controller 1 - should get A (1, 0, 0, ...)
    try testing.expectEqual(@as(u8, 1), harness.state.busRead(0x4016) & 0x01);
    try testing.expectEqual(@as(u8, 0), harness.state.busRead(0x4016) & 0x01);

    // Read controller 2 - should get B (0, 1, 0, ...)
    try testing.expectEqual(@as(u8, 0), harness.state.busRead(0x4017) & 0x01);
    try testing.expectEqual(@as(u8, 1), harness.state.busRead(0x4017) & 0x01);
}

// ============================================================================
// Test 5: Open Bus Behavior
// ============================================================================

test "Controller: open bus bits 5-7" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Press A button
    harness.state.controller.buttons1 = 0x01;
    harness.state.busWrite(0x4016, 0x01);
    harness.state.busWrite(0x4016, 0x00);

    // Set open bus to known value (simulates previous bus activity)
    // In real hardware, this would be from a previous read/write cycle
    harness.state.bus.open_bus = 0xFF;

    // Read controller - bit 0 should be button data, bits 5-7 should be open bus
    const value = harness.state.busRead(0x4016);
    try testing.expectEqual(@as(u8, 1), value & 0x01); // Button data (bit 0)
    // Bits 5-7 should reflect open bus value
    try testing.expectEqual(@as(u8, 0xE0), value & 0xE0); // Open bus bits (0xFF & 0xE0 = 0xE0)
}

// ============================================================================
// Test 6: Re-latch (Reset Shift Register Mid-Read)
// ============================================================================

test "Controller: re-latch mid-sequence" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Initial: A+B pressed
    harness.state.controller.buttons1 = 0b00000011;
    harness.state.busWrite(0x4016, 0x01);
    harness.state.busWrite(0x4016, 0x00);

    // Read first 3 buttons
    _ = harness.state.busRead(0x4016); // A = 1
    _ = harness.state.busRead(0x4016); // B = 1
    _ = harness.state.busRead(0x4016); // Select = 0

    // Re-latch (reset sequence)
    harness.state.busWrite(0x4016, 0x01);
    harness.state.busWrite(0x4016, 0x00);

    // Should read from beginning again
    try testing.expectEqual(@as(u8, 1), harness.state.busRead(0x4016) & 0x01); // A = 1
    try testing.expectEqual(@as(u8, 1), harness.state.busRead(0x4016) & 0x01); // B = 1
}

// ============================================================================
// NOTE: Direct ControllerState unit tests moved to:
// tests/emulation/state/peripherals/controller_state_test.zig
// ============================================================================
