//! Unit tests for KeyboardMapper
//!
//! Tests keyboard event to NES button mapping

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const KeyboardMapper = RAMBO.KeyboardMapper;
const ButtonState = RAMBO.ButtonState;

// ============================================================================
// Initialization Tests
// ============================================================================

test "KeyboardMapper: default initialization no buttons pressed" {
    const mapper = KeyboardMapper{};
    const state = mapper.getState();
    try testing.expectEqual(@as(u8, 0), state.toByte());
}

// ============================================================================
// Individual Key Press Tests
// ============================================================================

test "KeyboardMapper: press Up sets up button" {
    var mapper = KeyboardMapper{};
    mapper.keyPress(KeyboardMapper.Keymap.KEY_UP);
    try testing.expect(mapper.getState().up);
}

test "KeyboardMapper: press Down sets down button" {
    var mapper = KeyboardMapper{};
    mapper.keyPress(KeyboardMapper.Keymap.KEY_DOWN);
    try testing.expect(mapper.getState().down);
}

test "KeyboardMapper: press Left sets left button" {
    var mapper = KeyboardMapper{};
    mapper.keyPress(KeyboardMapper.Keymap.KEY_LEFT);
    try testing.expect(mapper.getState().left);
}

test "KeyboardMapper: press Right sets right button" {
    var mapper = KeyboardMapper{};
    mapper.keyPress(KeyboardMapper.Keymap.KEY_RIGHT);
    try testing.expect(mapper.getState().right);
}

test "KeyboardMapper: press Z sets B button" {
    var mapper = KeyboardMapper{};
    mapper.keyPress(KeyboardMapper.Keymap.KEY_Z);
    try testing.expect(mapper.getState().b);
}

test "KeyboardMapper: press X sets A button" {
    var mapper = KeyboardMapper{};
    mapper.keyPress(KeyboardMapper.Keymap.KEY_X);
    try testing.expect(mapper.getState().a);
}

test "KeyboardMapper: press RShift sets Select button" {
    var mapper = KeyboardMapper{};
    mapper.keyPress(KeyboardMapper.Keymap.KEY_RSHIFT);
    try testing.expect(mapper.getState().select);
}

test "KeyboardMapper: press Enter sets Start button" {
    var mapper = KeyboardMapper{};
    mapper.keyPress(KeyboardMapper.Keymap.KEY_ENTER);
    try testing.expect(mapper.getState().start);
}

test "KeyboardMapper: press Keypad Enter sets Start button" {
    var mapper = KeyboardMapper{};
    mapper.keyPress(KeyboardMapper.Keymap.KEY_KP_ENTER);
    try testing.expect(mapper.getState().start);
}

// ============================================================================
// Individual Key Release Tests
// ============================================================================

test "KeyboardMapper: release Up clears up button" {
    var mapper = KeyboardMapper{};
    mapper.keyPress(KeyboardMapper.Keymap.KEY_UP);
    mapper.keyRelease(KeyboardMapper.Keymap.KEY_UP);
    try testing.expect(!mapper.getState().up);
}

test "KeyboardMapper: release A clears A button" {
    var mapper = KeyboardMapper{};
    mapper.keyPress(KeyboardMapper.Keymap.KEY_X);
    mapper.keyRelease(KeyboardMapper.Keymap.KEY_X);
    try testing.expect(!mapper.getState().a);
}

// ============================================================================
// Multiple Button Tests
// ============================================================================

test "KeyboardMapper: press multiple buttons simultaneously" {
    var mapper = KeyboardMapper{};
    mapper.keyPress(KeyboardMapper.Keymap.KEY_X); // A
    mapper.keyPress(KeyboardMapper.Keymap.KEY_UP);
    mapper.keyPress(KeyboardMapper.Keymap.KEY_RIGHT);

    const state = mapper.getState();
    try testing.expect(state.a);
    try testing.expect(state.up);
    try testing.expect(state.right);
}

test "KeyboardMapper: press and release sequence" {
    var mapper = KeyboardMapper{};

    // Press A
    mapper.keyPress(KeyboardMapper.Keymap.KEY_X);
    try testing.expect(mapper.getState().a);

    // Press B (A still held)
    mapper.keyPress(KeyboardMapper.Keymap.KEY_Z);
    try testing.expect(mapper.getState().a);
    try testing.expect(mapper.getState().b);

    // Release A
    mapper.keyRelease(KeyboardMapper.Keymap.KEY_X);
    try testing.expect(!mapper.getState().a);
    try testing.expect(mapper.getState().b);

    // Release B
    mapper.keyRelease(KeyboardMapper.Keymap.KEY_Z);
    try testing.expect(!mapper.getState().b);
}

// ============================================================================
// Sanitization Tests
// ============================================================================

test "KeyboardMapper: opposing Up+Down cleared by sanitize" {
    var mapper = KeyboardMapper{};
    mapper.keyPress(KeyboardMapper.Keymap.KEY_UP);
    mapper.keyPress(KeyboardMapper.Keymap.KEY_DOWN);

    const state = mapper.getState();
    try testing.expect(!state.up);
    try testing.expect(!state.down);
}

test "KeyboardMapper: opposing Left+Right cleared by sanitize" {
    var mapper = KeyboardMapper{};
    mapper.keyPress(KeyboardMapper.Keymap.KEY_LEFT);
    mapper.keyPress(KeyboardMapper.Keymap.KEY_RIGHT);

    const state = mapper.getState();
    try testing.expect(!state.left);
    try testing.expect(!state.right);
}

test "KeyboardMapper: diagonal input allowed" {
    var mapper = KeyboardMapper{};
    mapper.keyPress(KeyboardMapper.Keymap.KEY_UP);
    mapper.keyPress(KeyboardMapper.Keymap.KEY_LEFT);

    const state = mapper.getState();
    try testing.expect(state.up);
    try testing.expect(state.left);
}

// ============================================================================
// Edge Case Tests
// ============================================================================

test "KeyboardMapper: unknown keycode ignored" {
    var mapper = KeyboardMapper{};
    mapper.keyPress(9999); // Invalid keycode
    try testing.expectEqual(@as(u8, 0), mapper.getState().toByte());
}

test "KeyboardMapper: release without press is no-op" {
    var mapper = KeyboardMapper{};
    mapper.keyRelease(KeyboardMapper.Keymap.KEY_X);
    try testing.expect(!mapper.getState().a);
}

test "KeyboardMapper: double press same key idempotent" {
    var mapper = KeyboardMapper{};
    mapper.keyPress(KeyboardMapper.Keymap.KEY_X);
    mapper.keyPress(KeyboardMapper.Keymap.KEY_X);
    try testing.expect(mapper.getState().a);

    mapper.keyRelease(KeyboardMapper.Keymap.KEY_X);
    try testing.expect(!mapper.getState().a);
}

test "KeyboardMapper: rapid press/release sequence" {
    var mapper = KeyboardMapper{};

    // Simulate 10 rapid presses
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        mapper.keyPress(KeyboardMapper.Keymap.KEY_X);
        try testing.expect(mapper.getState().a);
        mapper.keyRelease(KeyboardMapper.Keymap.KEY_X);
        try testing.expect(!mapper.getState().a);
    }
}

// ============================================================================
// State Persistence Tests
// ============================================================================

test "KeyboardMapper: state persists across unrelated key events" {
    var mapper = KeyboardMapper{};

    mapper.keyPress(KeyboardMapper.Keymap.KEY_X); // Press A
    try testing.expect(mapper.getState().a);

    // Press unrelated key
    mapper.keyPress(KeyboardMapper.Keymap.KEY_UP);
    try testing.expect(mapper.getState().a); // A still pressed

    // Release unrelated key
    mapper.keyRelease(KeyboardMapper.Keymap.KEY_UP);
    try testing.expect(mapper.getState().a); // A still pressed
}
