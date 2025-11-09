//! NES Controller Logic Module
//!
//! Provides operations for NES 4021 shift register emulation.
//! Follows State/Logic separation pattern used throughout the codebase.

const ControllerState = @import("State.zig").ControllerState;

/// Controller logic operations
pub const Logic = struct {
    /// Power-on initialization
    /// Initializes controller state to hardware-accurate power-on values
    pub fn power_on(state: *ControllerState) void {
        state.* = .{};
    }

    /// Reset controller state
    /// Clears all controller state (shift registers, strobe, buttons)
    pub fn reset(state: *ControllerState) void {
        state.* = .{};
    }

    /// Latch controller buttons into shift registers
    /// Called when strobe transitions high (bit 0 of $4016 write)
    pub fn latch(state: *ControllerState) void {
        state.shift1 = state.buttons1;
        state.shift2 = state.buttons2;
    }

    /// Update button data from mailbox
    /// Called each frame to sync with current input
    pub fn updateButtons(state: *ControllerState, buttons1: u8, buttons2: u8) void {
        state.buttons1 = buttons1;
        state.buttons2 = buttons2;
        // If strobe is high, immediately reload shift registers
        if (state.strobe) {
            latch(state);
        }
    }

    /// Read controller 1 serial data (bit 0)
    /// Returns next bit from shift register
    pub fn read1(state: *ControllerState) u8 {
        if (state.strobe) {
            // Strobe high: continuously reload shift register
            return state.buttons1 & 0x01;
        } else {
            // Strobe low: shift out bits
            const bit = state.shift1 & 0x01;
            state.shift1 = (state.shift1 >> 1) | 0x80; // Shift right, fill with 1
            return bit;
        }
    }

    /// Read controller 2 serial data (bit 0)
    pub fn read2(state: *ControllerState) u8 {
        if (state.strobe) {
            return state.buttons2 & 0x01;
        } else {
            const bit = state.shift2 & 0x01;
            state.shift2 = (state.shift2 >> 1) | 0x80;
            return bit;
        }
    }

    /// Write strobe state ($4016 write, bit 0)
    /// Transition high→low starts shift mode
    /// Transition low→high latches button state
    pub fn writeStrobe(state: *ControllerState, value: u8) void {
        const new_strobe = (value & 0x01) != 0;

        // Update strobe level first
        state.strobe = new_strobe;

        // Hardware-friendly behavior:
        // - When bit 0 is 1 (strobe high), controllers are continually latched.
        //   Games that briefly or repeatedly write 1 expect an immediate latch.
        // - When bit 0 is 0 (strobe low), controller shifts on reads.
        if (new_strobe) {
            latch(state);
        }
    }
};
