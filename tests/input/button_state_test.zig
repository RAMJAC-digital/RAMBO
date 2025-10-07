//! Unit tests for ButtonState
//!
//! Tests the core NES controller button state structure

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const ButtonState = RAMBO.ButtonState;

// ============================================================================
// Size and Layout Tests
// ============================================================================

test "ButtonState: size is exactly 1 byte" {
    try testing.expectEqual(@sizeOf(ButtonState), 1);
}

test "ButtonState: default initialization all buttons off" {
    const state = ButtonState{};
    try testing.expect(!state.a);
    try testing.expect(!state.b);
    try testing.expect(!state.select);
    try testing.expect(!state.start);
    try testing.expect(!state.up);
    try testing.expect(!state.down);
    try testing.expect(!state.left);
    try testing.expect(!state.right);
    try testing.expectEqual(@as(u8, 0), state.toByte());
}

// ============================================================================
// Byte Conversion Tests
// ============================================================================

test "ButtonState: toByte/fromByte roundtrip" {
    const original = ButtonState{
        .a = true,
        .select = true,
        .up = true,
        .left = true,
    };

    const byte = original.toByte();
    const restored = ButtonState.fromByte(byte);

    try testing.expect(restored.a == original.a);
    try testing.expect(restored.b == original.b);
    try testing.expect(restored.select == original.select);
    try testing.expect(restored.start == original.start);
    try testing.expect(restored.up == original.up);
    try testing.expect(restored.down == original.down);
    try testing.expect(restored.left == original.left);
    try testing.expect(restored.right == original.right);
}

test "ButtonState: all buttons pressed toByte" {
    const state = ButtonState{
        .a = true,
        .b = true,
        .select = true,
        .start = true,
        .up = true,
        .down = true,
        .left = true,
        .right = true,
    };

    try testing.expectEqual(@as(u8, 0xFF), state.toByte());
}

test "ButtonState: no buttons pressed toByte" {
    const state = ButtonState{};
    try testing.expectEqual(@as(u8, 0x00), state.toByte());
}

test "ButtonState: fromByte with all bits set" {
    const state = ButtonState.fromByte(0xFF);
    try testing.expect(state.a);
    try testing.expect(state.b);
    try testing.expect(state.select);
    try testing.expect(state.start);
    try testing.expect(state.up);
    try testing.expect(state.down);
    try testing.expect(state.left);
    try testing.expect(state.right);
}

// ============================================================================
// Individual Button Tests
// ============================================================================

test "ButtonState: A button only" {
    const state = ButtonState{ .a = true };
    try testing.expectEqual(@as(u8, 0b00000001), state.toByte());
}

test "ButtonState: B button only" {
    const state = ButtonState{ .b = true };
    try testing.expectEqual(@as(u8, 0b00000010), state.toByte());
}

test "ButtonState: Select button only" {
    const state = ButtonState{ .select = true };
    try testing.expectEqual(@as(u8, 0b00000100), state.toByte());
}

test "ButtonState: Start button only" {
    const state = ButtonState{ .start = true };
    try testing.expectEqual(@as(u8, 0b00001000), state.toByte());
}

test "ButtonState: Up button only" {
    const state = ButtonState{ .up = true };
    try testing.expectEqual(@as(u8, 0b00010000), state.toByte());
}

test "ButtonState: Down button only" {
    const state = ButtonState{ .down = true };
    try testing.expectEqual(@as(u8, 0b00100000), state.toByte());
}

test "ButtonState: Left button only" {
    const state = ButtonState{ .left = true };
    try testing.expectEqual(@as(u8, 0b01000000), state.toByte());
}

test "ButtonState: Right button only" {
    const state = ButtonState{ .right = true };
    try testing.expectEqual(@as(u8, 0b10000000), state.toByte());
}

// ============================================================================
// Sanitization Tests
// ============================================================================

test "ButtonState: sanitize opposing Up+Down clears both" {
    var state = ButtonState{ .up = true, .down = true };
    state.sanitize();
    try testing.expect(!state.up);
    try testing.expect(!state.down);
}

test "ButtonState: sanitize opposing Left+Right clears both" {
    var state = ButtonState{ .left = true, .right = true };
    state.sanitize();
    try testing.expect(!state.left);
    try testing.expect(!state.right);
}

test "ButtonState: sanitize preserves non-opposing buttons" {
    var state = ButtonState{
        .a = true,
        .b = true,
        .up = true,
        .down = true,
        .left = true,
    };
    state.sanitize();

    // A and B should be preserved
    try testing.expect(state.a);
    try testing.expect(state.b);

    // Up+Down cleared
    try testing.expect(!state.up);
    try testing.expect(!state.down);

    // Left preserved (no opposing Right)
    try testing.expect(state.left);
}

test "ButtonState: sanitize diagonal Up+Left allowed" {
    var state = ButtonState{ .up = true, .left = true };
    state.sanitize();
    try testing.expect(state.up);
    try testing.expect(state.left);
}

test "ButtonState: sanitize all opposing directions" {
    var state = ButtonState{
        .up = true,
        .down = true,
        .left = true,
        .right = true,
    };
    state.sanitize();
    try testing.expect(!state.up);
    try testing.expect(!state.down);
    try testing.expect(!state.left);
    try testing.expect(!state.right);
}
