//! Unit Tests for ControllerState
//!
//! Tests the controller shift register and button state management.
//! These are white-box tests of the ControllerState implementation.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const ControllerState = RAMBO.EmulationState.ControllerState;

// ============================================================================
// Shift Register Behavior Tests
// ============================================================================

test "ControllerState: shift register fills with 1s after 8 reads" {
    var controller = ControllerState{};

    // No buttons pressed
    controller.buttons1 = 0x00;
    controller.writeStrobe(0x01);
    controller.writeStrobe(0x00);

    // Read 8 zeros (8 button states)
    for (0..8) |_| {
        try testing.expectEqual(@as(u8, 0), controller.read1());
    }

    // Further reads return 1 (shift register = 0xFF after 8 shifts)
    // This is hardware behavior - reading beyond 8 bits returns 1s
    for (0..5) |_| {
        try testing.expectEqual(@as(u8, 1), controller.read1());
    }
}

// ============================================================================
// Strobe Behavior Tests
// ============================================================================

test "ControllerState: updateButtons while strobe high reloads immediately" {
    var controller = ControllerState{};

    // Strobe high, update buttons
    controller.writeStrobe(0x01);
    controller.updateButtons(0xFF, 0x00);

    // Should immediately reload shift registers (continuous reload mode)
    try testing.expectEqual(@as(u8, 0xFF), controller.shift1);
}

test "ControllerState: writeStrobe(1) while high re-latches current buttons" {
    var controller = ControllerState{};

    // Strobe high once with initial buttons (A)
    controller.buttons1 = 0b00000001;
    controller.writeStrobe(0x01); // latch
    try testing.expectEqual(@as(u8, 0b00000001), controller.shift1);

    // Change buttons directly (simulate new state before mailbox update)
    controller.buttons1 = 0b00000010; // B

    // Write 1 again while already high — should re-latch immediately
    controller.writeStrobe(0x01);
    try testing.expectEqual(@as(u8, 0b00000010), controller.shift1);

    // Drop low and verify shift behavior uses latest latched state
    controller.writeStrobe(0x00);
    const first_bit = controller.read1();
    try testing.expectEqual(@as(u8, 0), first_bit); // B is bit 1, so first read (A) is 0
}

test "ControllerState: updateButtons while strobe low does not reload" {
    var controller = ControllerState{};

    // Latch initial state (all buttons pressed)
    controller.updateButtons(0xFF, 0x00);
    controller.writeStrobe(0x01);
    controller.writeStrobe(0x00); // Latch shift register

    // Update buttons to different state while shifting
    controller.updateButtons(0x00, 0x00);

    // Shift register should still have old data (0xFF)
    // New data only latches on next strobe high→low transition
    try testing.expectEqual(@as(u8, 1), controller.read1()); // LSB of 0xFF
}

// ============================================================================
// Button State Management Tests
// ============================================================================

test "ControllerState: button state persists across reads" {
    var controller = ControllerState{};

    // Press A button (bit 0)
    controller.updateButtons(0x01, 0x00);
    controller.writeStrobe(0x01);
    controller.writeStrobe(0x00);

    // Read A button
    try testing.expectEqual(@as(u8, 1), controller.read1());

    // Read remaining 7 buttons (should be 0)
    for (0..7) |_| {
        try testing.expectEqual(@as(u8, 0), controller.read1());
    }

    // Re-latch same state
    controller.writeStrobe(0x01);
    controller.writeStrobe(0x00);

    // Should read same values again
    try testing.expectEqual(@as(u8, 1), controller.read1()); // A still pressed
}

test "ControllerState: all buttons pressed produces correct shift pattern" {
    var controller = ControllerState{};

    // All 8 buttons pressed (0xFF)
    controller.updateButtons(0xFF, 0x00);
    controller.writeStrobe(0x01);
    controller.writeStrobe(0x00);

    // All 8 reads should return 1
    for (0..8) |_| {
        try testing.expectEqual(@as(u8, 1), controller.read1());
    }
}

test "ControllerState: alternating button pattern" {
    var controller = ControllerState{};

    // Alternating pattern (A, Start, Select, Up - bits 0,3,2,4)
    // Binary: 00011101 = 0x1D
    controller.updateButtons(0x1D, 0x00);
    controller.writeStrobe(0x01);
    controller.writeStrobe(0x00);

    // LSB first: A=1, B=0, Select=1, Start=1, Up=1, Down=0, Left=0, Right=0
    try testing.expectEqual(@as(u8, 1), controller.read1()); // A (bit 0)
    try testing.expectEqual(@as(u8, 0), controller.read1()); // B (bit 1)
    try testing.expectEqual(@as(u8, 1), controller.read1()); // Select (bit 2)
    try testing.expectEqual(@as(u8, 1), controller.read1()); // Start (bit 3)
    try testing.expectEqual(@as(u8, 1), controller.read1()); // Up (bit 4)
    try testing.expectEqual(@as(u8, 0), controller.read1()); // Down (bit 5)
    try testing.expectEqual(@as(u8, 0), controller.read1()); // Left (bit 6)
    try testing.expectEqual(@as(u8, 0), controller.read1()); // Right (bit 7)
}

// ============================================================================
// Edge Case Tests
// ============================================================================

test "ControllerState: multiple strobe cycles without reads" {
    var controller = ControllerState{};

    controller.updateButtons(0xAA, 0x00); // Pattern: 10101010

    // Multiple strobe cycles
    controller.writeStrobe(0x01);
    controller.writeStrobe(0x00);
    controller.writeStrobe(0x01);
    controller.writeStrobe(0x00);
    controller.writeStrobe(0x01);
    controller.writeStrobe(0x00);

    // Should still be able to read the latched value
    try testing.expectEqual(@as(u8, 0), controller.read1()); // LSB of 0xAA
}

test "ControllerState: reading without latch returns uninitialized shift register" {
    var controller = ControllerState{};

    // Don't latch, just read
    // shift1 starts as 0 by default
    try testing.expectEqual(@as(u8, 0), controller.read1());
}

test "ControllerState: controller 2 independence" {
    var controller = ControllerState{};

    // Different button states for each controller
    controller.updateButtons(0xFF, 0x00); // Controller 1: all pressed
    // Controller 2: no buttons pressed (default)

    controller.writeStrobe(0x01);
    controller.writeStrobe(0x00);

    // Controller 1 should return 1
    try testing.expectEqual(@as(u8, 1), controller.read1());

    // Controller 2 should return 0
    try testing.expectEqual(@as(u8, 0), controller.read2());
}
