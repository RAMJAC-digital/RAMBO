//! NES Controller Button State
//!
//! Represents the state of all 8 buttons on an NES controller.
//! Packed into a single byte for efficient storage and transmission.
//!
//! Button order matches NES hardware shift register:
//! A, B, Select, Start, Up, Down, Left, Right

/// NES controller button state (8 buttons packed into 1 byte)
///
/// Standard NES button order: A, B, Select, Start, Up, Down, Left, Right
/// This matches the order returned by the hardware shift register ($4016/$4017)
pub const ButtonState = packed struct(u8) {
    /// A button (bit 0)
    a: bool = false,

    /// B button (bit 1)
    b: bool = false,

    /// Select button (bit 2)
    select: bool = false,

    /// Start button (bit 3)
    start: bool = false,

    /// D-pad Up (bit 4)
    up: bool = false,

    /// D-pad Down (bit 5)
    down: bool = false,

    /// D-pad Left (bit 6)
    left: bool = false,

    /// D-pad Right (bit 7)
    right: bool = false,

    /// Convert button state to byte representation
    ///
    /// Returns: 8-bit value where each bit represents a button
    /// Bit 0 = A, Bit 1 = B, ..., Bit 7 = Right
    pub fn toByte(self: ButtonState) u8 {
        return @bitCast(self);
    }

    /// Create button state from byte value
    ///
    /// Args:
    ///     byte: 8-bit value where each bit represents a button
    ///
    /// Returns: ButtonState with buttons set according to bits
    pub fn fromByte(byte: u8) ButtonState {
        return @bitCast(byte);
    }

    /// Enforce D-pad constraints (no opposing directions)
    ///
    /// NES games expect that Up+Down and Left+Right cannot be pressed
    /// simultaneously (physically impossible on real hardware).
    ///
    /// If opposing directions are detected, BOTH are cleared.
    /// This is the safest behavior to prevent game glitches.
    ///
    /// Note: This is applied automatically by KeyboardMapper but can
    /// also be called manually for safety.
    pub fn sanitize(self: *ButtonState) void {
        // Clear both Up and Down if both are pressed
        if (self.up and self.down) {
            self.up = false;
            self.down = false;
        }

        // Clear both Left and Right if both are pressed
        if (self.left and self.right) {
            self.left = false;
            self.right = false;
        }
    }
};
