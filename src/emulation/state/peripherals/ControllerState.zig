//! NES Controller state for emulation runtime
//! Implements cycle-accurate 4021 8-bit shift register behavior
//! Button order: A, B, Select, Start, Up, Down, Left, Right

/// NES Controller state
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

    /// Latch controller buttons into shift registers
    /// Called when strobe transitions high (bit 0 of $4016 write)
    pub fn latch(self: *ControllerState) void {
        self.shift1 = self.buttons1;
        self.shift2 = self.buttons2;
    }

    /// Update button data from mailbox
    /// Called each frame to sync with current input
    pub fn updateButtons(self: *ControllerState, buttons1: u8, buttons2: u8) void {
        self.buttons1 = buttons1;
        self.buttons2 = buttons2;
        // If strobe is high, immediately reload shift registers
        if (self.strobe) {
            self.latch();
        }
    }

    /// Read controller 1 serial data (bit 0)
    /// Returns next bit from shift register
    pub fn read1(self: *ControllerState) u8 {
        if (self.strobe) {
            // Strobe high: continuously reload shift register
            return self.buttons1 & 0x01;
        } else {
            // Strobe low: shift out bits
            const bit = self.shift1 & 0x01;
            self.shift1 = (self.shift1 >> 1) | 0x80; // Shift right, fill with 1
            return bit;
        }
    }

    /// Read controller 2 serial data (bit 0)
    pub fn read2(self: *ControllerState) u8 {
        if (self.strobe) {
            return self.buttons2 & 0x01;
        } else {
            const bit = self.shift2 & 0x01;
            self.shift2 = (self.shift2 >> 1) | 0x80;
            return bit;
        }
    }

    /// Write strobe state ($4016 write, bit 0)
    /// Transition high→low starts shift mode
    /// Transition low→high latches button state
    pub fn writeStrobe(self: *ControllerState, value: u8) void {
        const new_strobe = (value & 0x01) != 0;

        // Update strobe level first
        self.strobe = new_strobe;

        // Hardware-friendly behavior:
        // - When bit 0 is 1 (strobe high), controllers are continually latched.
        //   Games that briefly or repeatedly write 1 expect an immediate latch.
        // - When bit 0 is 0 (strobe low), controller shifts on reads.
        if (new_strobe) {
            self.latch();
        }
    }

    /// Reset controller state
    pub fn reset(self: *ControllerState) void {
        self.* = .{};
    }
};
