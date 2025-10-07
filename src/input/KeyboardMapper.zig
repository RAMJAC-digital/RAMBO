//! Keyboard Mapper - Wayland Keyboard Events to NES Controller Buttons
//!
//! Maps Wayland keyboard events to NES controller button states.
//! Maintains button state across key press/release events and applies
//! hardware constraints (no opposing D-pad directions).
//!
//! Default Keyboard Mapping:
//! - Arrow Keys    → D-pad (Up, Down, Left, Right)
//! - Z             → B button
//! - X             → A button
//! - Right Shift   → Select
//! - Enter         → Start

const ButtonState = @import("ButtonState.zig").ButtonState;

/// Maps Wayland keyboard events to NES controller buttons
pub const KeyboardMapper = struct {
    /// Current button state
    buttons: ButtonState = .{},

    /// Wayland keycode constants for NES button mapping
    ///
    /// These keycodes match the Wayland/XKB keycode space.
    /// Derived from xkbcommon keysym definitions.
    pub const Keymap = struct {
        // D-pad (Arrow keys)
        pub const KEY_UP: u32 = 111;
        pub const KEY_DOWN: u32 = 116;
        pub const KEY_LEFT: u32 = 113;
        pub const KEY_RIGHT: u32 = 114;

        // Action buttons
        pub const KEY_Z: u32 = 52; // B button
        pub const KEY_X: u32 = 53; // A button

        // System buttons
        pub const KEY_RSHIFT: u32 = 62; // Select
        pub const KEY_ENTER: u32 = 36; // Start
    };

    /// Process a key press event
    ///
    /// Updates button state and applies sanitization to prevent
    /// opposing D-pad directions (Up+Down, Left+Right).
    ///
    /// Args:
    ///     keycode: Wayland keycode
    pub fn keyPress(self: *KeyboardMapper, keycode: u32) void {
        switch (keycode) {
            Keymap.KEY_UP => self.buttons.up = true,
            Keymap.KEY_DOWN => self.buttons.down = true,
            Keymap.KEY_LEFT => self.buttons.left = true,
            Keymap.KEY_RIGHT => self.buttons.right = true,
            Keymap.KEY_Z => self.buttons.b = true,
            Keymap.KEY_X => self.buttons.a = true,
            Keymap.KEY_RSHIFT => self.buttons.select = true,
            Keymap.KEY_ENTER => self.buttons.start = true,
            else => {}, // Unknown keycode - no-op
        }

        // Apply hardware constraints (no opposing directions)
        self.buttons.sanitize();
    }

    /// Process a key release event
    ///
    /// Clears the corresponding button. Does not apply sanitization
    /// since releasing a button cannot create an invalid state.
    ///
    /// Args:
    ///     keycode: Wayland keycode
    pub fn keyRelease(self: *KeyboardMapper, keycode: u32) void {
        switch (keycode) {
            Keymap.KEY_UP => self.buttons.up = false,
            Keymap.KEY_DOWN => self.buttons.down = false,
            Keymap.KEY_LEFT => self.buttons.left = false,
            Keymap.KEY_RIGHT => self.buttons.right = false,
            Keymap.KEY_Z => self.buttons.b = false,
            Keymap.KEY_X => self.buttons.a = false,
            Keymap.KEY_RSHIFT => self.buttons.select = false,
            Keymap.KEY_ENTER => self.buttons.start = false,
            else => {}, // Unknown keycode - no-op
        }
    }

    /// Get current button state
    ///
    /// Returns the current button state for posting to ControllerInputMailbox.
    ///
    /// Returns: ButtonState with current button presses
    pub fn getState(self: *const KeyboardMapper) ButtonState {
        return self.buttons;
    }
};
