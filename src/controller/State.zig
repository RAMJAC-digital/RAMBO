//! NES Controller State
//!
//! Pure data structure for NES 4021 shift register state.
//! All operations are in Logic.zig following State/Logic separation pattern.
//!
//! Button order: A, B, Select, Start, Up, Down, Left, Right

/// NES Controller state (pure data)
pub const ControllerState = struct {
    /// Controller 1 shift register
    /// Bits shift out LSB-first on each read
    shift1: u8 = 0,

    /// Controller 2 shift register
    shift2: u8 = 0,

    /// Strobe state (latched buttons or shifting mode)
    /// True = reload shift registers on each read (strobe high)
    /// False = shift out bits on each read (strobe low)
    strobe: bool = false,

    /// Button data for controller 1
    /// Reloaded into shift1 when strobe goes high
    buttons1: u8 = 0,

    /// Button data for controller 2
    buttons2: u8 = 0,
};
