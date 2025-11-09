//! Unit Tests for ControllerState
//!
//! Tests the controller shift register and button state management.
//! These are white-box tests of the ControllerState implementation.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const ControllerModule = RAMBO.Controller;
const ControllerState = ControllerModule.ControllerState;
const ControllerLogic = ControllerModule.Logic;

// ============================================================================
// Shift Register Behavior Tests
// ============================================================================

test "ControllerState: shift register fills with 1s after 8 reads" {
    var controller = ControllerState{};

    // No buttons pressed
    controller.buttons1 = 0x00;
    ControllerLogic.writeStrobe(&controller, 0x01);
    ControllerLogic.writeStrobe(&controller, 0x00);

    // Read 8 zeros (8 button states)
    for (0..8) |_| {
        try testing.expectEqual(@as(u8, 0), ControllerLogic.read1(&controller));
    }

    // Further reads return 1 (shift register = 0xFF after 8 shifts)
    // This is hardware behavior - reading beyond 8 bits returns 1s
    for (0..5) |_| {
        try testing.expectEqual(@as(u8, 1), ControllerLogic.read1(&controller));
    }
}

// ============================================================================
// Strobe Behavior Tests
// ============================================================================

test "ControllerState: updateButtons while strobe high reloads immediately" {
    var controller = ControllerState{};

    // Strobe high, update buttons
    ControllerLogic.writeStrobe(&controller, 0x01);
    ControllerLogic.updateButtons(&controller, 0xFF, 0x00);

    // Should immediately reload shift registers (continuous reload mode)
    try testing.expectEqual(@as(u8, 0xFF), controller.shift1);
}

test "ControllerState: writeStrobe(1) while high re-latches current buttons" {
    var controller = ControllerState{};

    // Strobe high once with initial buttons (A)
    controller.buttons1 = 0b00000001;
    ControllerLogic.writeStrobe(&controller,0x01); // latch
    try testing.expectEqual(@as(u8, 0b00000001), controller.shift1);

    // Change buttons directly (simulate new state before mailbox update)
    controller.buttons1 = 0b00000010; // B

    // Write 1 again while already high — should re-latch immediately
    ControllerLogic.writeStrobe(&controller,0x01);
    try testing.expectEqual(@as(u8, 0b00000010), controller.shift1);

    // Drop low and verify shift behavior uses latest latched state
    ControllerLogic.writeStrobe(&controller,0x00);
    const first_bit = ControllerLogic.read1(&controller);
    try testing.expectEqual(@as(u8, 0), first_bit); // B is bit 1, so first read (A) is 0
}

test "ControllerState: updateButtons while strobe low does not reload" {
    var controller = ControllerState{};

    // Latch initial state (all buttons pressed)
    ControllerLogic.updateButtons(&controller,0xFF, 0x00);
    ControllerLogic.writeStrobe(&controller,0x01);
    ControllerLogic.writeStrobe(&controller,0x00); // Latch shift register

    // Update buttons to different state while shifting
    ControllerLogic.updateButtons(&controller,0x00, 0x00);

    // Shift register should still have old data (0xFF)
    // New data only latches on next strobe high→low transition
    try testing.expectEqual(@as(u8, 1), ControllerLogic.read1(&controller)); // LSB of 0xFF
}

// ============================================================================
// Button State Management Tests
// ============================================================================

test "ControllerState: button state persists across reads" {
    var controller = ControllerState{};

    // Press A button (bit 0)
    ControllerLogic.updateButtons(&controller,0x01, 0x00);
    ControllerLogic.writeStrobe(&controller,0x01);
    ControllerLogic.writeStrobe(&controller,0x00);

    // Read A button
    try testing.expectEqual(@as(u8, 1), ControllerLogic.read1(&controller));

    // Read remaining 7 buttons (should be 0)
    for (0..7) |_| {
        try testing.expectEqual(@as(u8, 0), ControllerLogic.read1(&controller));
    }

    // Re-latch same state
    ControllerLogic.writeStrobe(&controller,0x01);
    ControllerLogic.writeStrobe(&controller,0x00);

    // Should read same values again
    try testing.expectEqual(@as(u8, 1), ControllerLogic.read1(&controller)); // A still pressed
}

test "ControllerState: all buttons pressed produces correct shift pattern" {
    var controller = ControllerState{};

    // All 8 buttons pressed (0xFF)
    ControllerLogic.updateButtons(&controller,0xFF, 0x00);
    ControllerLogic.writeStrobe(&controller,0x01);
    ControllerLogic.writeStrobe(&controller,0x00);

    // All 8 reads should return 1
    for (0..8) |_| {
        try testing.expectEqual(@as(u8, 1), ControllerLogic.read1(&controller));
    }
}

test "ControllerState: alternating button pattern" {
    var controller = ControllerState{};

    // Alternating pattern (A, Start, Select, Up - bits 0,3,2,4)
    // Binary: 00011101 = 0x1D
    ControllerLogic.updateButtons(&controller,0x1D, 0x00);
    ControllerLogic.writeStrobe(&controller,0x01);
    ControllerLogic.writeStrobe(&controller,0x00);

    // LSB first: A=1, B=0, Select=1, Start=1, Up=1, Down=0, Left=0, Right=0
    try testing.expectEqual(@as(u8, 1), ControllerLogic.read1(&controller)); // A (bit 0)
    try testing.expectEqual(@as(u8, 0), ControllerLogic.read1(&controller)); // B (bit 1)
    try testing.expectEqual(@as(u8, 1), ControllerLogic.read1(&controller)); // Select (bit 2)
    try testing.expectEqual(@as(u8, 1), ControllerLogic.read1(&controller)); // Start (bit 3)
    try testing.expectEqual(@as(u8, 1), ControllerLogic.read1(&controller)); // Up (bit 4)
    try testing.expectEqual(@as(u8, 0), ControllerLogic.read1(&controller)); // Down (bit 5)
    try testing.expectEqual(@as(u8, 0), ControllerLogic.read1(&controller)); // Left (bit 6)
    try testing.expectEqual(@as(u8, 0), ControllerLogic.read1(&controller)); // Right (bit 7)
}

// ============================================================================
// Edge Case Tests
// ============================================================================

test "ControllerState: multiple strobe cycles without reads" {
    var controller = ControllerState{};

    ControllerLogic.updateButtons(&controller,0xAA, 0x00); // Pattern: 10101010

    // Multiple strobe cycles
    ControllerLogic.writeStrobe(&controller,0x01);
    ControllerLogic.writeStrobe(&controller,0x00);
    ControllerLogic.writeStrobe(&controller,0x01);
    ControllerLogic.writeStrobe(&controller,0x00);
    ControllerLogic.writeStrobe(&controller,0x01);
    ControllerLogic.writeStrobe(&controller,0x00);

    // Should still be able to read the latched value
    try testing.expectEqual(@as(u8, 0), ControllerLogic.read1(&controller)); // LSB of 0xAA
}

test "ControllerState: reading without latch returns uninitialized shift register" {
    var controller = ControllerState{};

    // Don't latch, just read
    // shift1 starts as 0 by default
    try testing.expectEqual(@as(u8, 0), ControllerLogic.read1(&controller));
}

test "ControllerState: controller 2 independence" {
    var controller = ControllerState{};

    // Different button states for each controller
    ControllerLogic.updateButtons(&controller,0xFF, 0x00); // Controller 1: all pressed
    // Controller 2: no buttons pressed (default)

    ControllerLogic.writeStrobe(&controller,0x01);
    ControllerLogic.writeStrobe(&controller,0x00);

    // Controller 1 should return 1
    try testing.expectEqual(@as(u8, 1), ControllerLogic.read1(&controller));

    // Controller 2 should return 0
    try testing.expectEqual(@as(u8, 0), ControllerLogic.read2(&controller));
}
