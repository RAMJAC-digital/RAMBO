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
//! - Enter/KP_Enter→ Start

const ButtonState = @import("ButtonState.zig").ButtonState;

/// Maps Wayland keyboard events to NES controller buttons
pub const KeyboardMapper = struct {
    /// Current button state
    buttons: ButtonState = .{},

    /// XKB keysym constants for NES button mapping (layout-independent)
    ///
    /// These keysyms work across all keyboard layouts (QWERTY, AZERTY, Dvorak, etc.)
    /// Reference: https://xkbcommon.org/doc/current/xkbcommon-keysyms_8h.html
    ///
    /// Values are from <xkbcommon/xkbcommon-keysyms.h>
    pub const Keymap = struct {
        // D-pad (Arrow keys)
        pub const KEY_UP: u32 = 0xff52; // XKB_KEY_Up
        pub const KEY_DOWN: u32 = 0xff54; // XKB_KEY_Down
        pub const KEY_LEFT: u32 = 0xff51; // XKB_KEY_Left
        pub const KEY_RIGHT: u32 = 0xff53; // XKB_KEY_Right

        // Action buttons
        pub const KEY_Z: u32 = 0x007a; // XKB_KEY_z (B button)
        pub const KEY_X: u32 = 0x0078; // XKB_KEY_x (A button)

        // System buttons
        pub const KEY_RSHIFT: u32 = 0xffe2; // XKB_KEY_Shift_R (Select)
        pub const KEY_ENTER: u32 = 0xff0d; // XKB_KEY_Return (Start)
        pub const KEY_KP_ENTER: u32 = 0xff8d; // XKB_KEY_KP_Enter (Start - Keypad Enter)

        // Menu input keys
        pub const KEY_Y: u32 = 0x0079; // XKB_KEY_y (Yes confirmation)
        pub const KEY_N: u32 = 0x006e; // XKB_KEY_n (No confirmation)
    };

    /// Process a key press event
    ///
    /// Updates button state and applies sanitization to prevent
    /// opposing D-pad directions (Up+Down, Left+Right).
    ///
    /// Args:
    ///     keysym: XKB keysym (layout-independent)
    pub fn keyPress(self: *KeyboardMapper, keysym: u32) void {
        switch (keysym) {
            Keymap.KEY_UP => self.buttons.up = true,
            Keymap.KEY_DOWN => self.buttons.down = true,
            Keymap.KEY_LEFT => self.buttons.left = true,
            Keymap.KEY_RIGHT => self.buttons.right = true,
            Keymap.KEY_Z => self.buttons.b = true,
            Keymap.KEY_X => self.buttons.a = true,
            Keymap.KEY_RSHIFT => self.buttons.select = true,
            Keymap.KEY_ENTER, Keymap.KEY_KP_ENTER => self.buttons.start = true, // Both Enter keys
            else => {}, // Unknown keysym - no-op
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
    ///     keysym: XKB keysym (layout-independent)
    pub fn keyRelease(self: *KeyboardMapper, keysym: u32) void {
        switch (keysym) {
            Keymap.KEY_UP => self.buttons.up = false,
            Keymap.KEY_DOWN => self.buttons.down = false,
            Keymap.KEY_LEFT => self.buttons.left = false,
            Keymap.KEY_RIGHT => self.buttons.right = false,
            Keymap.KEY_Z => self.buttons.b = false,
            Keymap.KEY_X => self.buttons.a = false,
            Keymap.KEY_RSHIFT => self.buttons.select = false,
            Keymap.KEY_ENTER, Keymap.KEY_KP_ENTER => self.buttons.start = false, // Both Enter keys
            else => {}, // Unknown keysym - no-op
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
