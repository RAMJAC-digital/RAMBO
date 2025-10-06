//! Envelope Logic (Reusable APU Component)
//!
//! Implements the NES APU envelope generator used by Pulse 1, Pulse 2, and Noise channels.
//! The envelope provides volume control with optional decay over time.
//!
//! Hardware Behavior:
//! - Clocked at 240 Hz (quarter-frame rate)
//! - Start flag triggers reload: decay_level = 15, divider = period
//! - Divider counts down each quarter frame
//! - When divider expires: reload divider, decrement decay_level
//! - Decay level decrements from 15 → 0 (or loops back to 15)
//! - Output: constant volume OR decay level (based on constant_volume flag)
//!
//! Usage: Pulse1, Pulse2, and Noise channels each have an independent Envelope instance.

const std = @import("std");

/// Envelope State Structure
/// Reusable component - each channel has its own instance
pub const Envelope = struct {
    /// Start flag (set when length counter reloaded, typically on $4003/$4007/$400F write)
    /// Triggers envelope restart: decay_level = 15, divider = volume_envelope
    start_flag: bool = false,

    /// Divider counter (counts down from volume_envelope to 0)
    /// Determines envelope decay rate
    divider: u4 = 0,

    /// Decay level (current envelope output, 0-15)
    /// Decrements over time unless constant_volume is set
    decay_level: u4 = 0,

    /// Loop flag (bit 5 of $4000/$4004/$400C)
    /// When set: decay_level reloads to 15 instead of stopping at 0
    /// Also functions as length counter halt flag
    loop_flag: bool = false,

    /// Constant volume flag (bit 4 of $4000/$4004/$400C)
    /// When set: output = volume_envelope (constant)
    /// When clear: output = decay_level (decays over time)
    constant_volume: bool = false,

    /// Volume/envelope period (bits 0-3 of $4000/$4004/$400C)
    /// Constant mode: Direct volume output (0-15)
    /// Decay mode: Divider reload value (controls decay speed)
    volume_envelope: u4 = 0,
};

/// Clock the envelope (called at 240 Hz / quarter-frame rate)
/// Updates divider and decay_level according to NES hardware behavior
pub fn clock(envelope: *Envelope) void {
    if (envelope.start_flag) {
        // Start flag set - restart envelope
        envelope.start_flag = false;
        envelope.decay_level = 15;
        envelope.divider = envelope.volume_envelope;
    } else {
        // Normal operation - countdown divider
        if (envelope.divider > 0) {
            envelope.divider -= 1;
        } else {
            // Divider expired - reload and update decay level
            envelope.divider = envelope.volume_envelope;

            if (envelope.decay_level > 0) {
                envelope.decay_level -= 1;
            } else if (envelope.loop_flag) {
                // Loop mode: reload decay level
                envelope.decay_level = 15;
            }
            // Non-loop mode: stays at 0
        }
    }
}

/// Get current envelope output volume (0-15)
/// Returns either constant volume or current decay level
pub fn getVolume(envelope: *const Envelope) u4 {
    if (envelope.constant_volume) {
        return envelope.volume_envelope;
    } else {
        return envelope.decay_level;
    }
}

/// Restart the envelope (typically called when $4003/$4007/$400F written)
/// Sets start_flag which triggers reload on next clock()
pub fn restart(envelope: *Envelope) void {
    envelope.start_flag = true;
}

/// Write to envelope control register ($4000 bits 0-5, $4004 bits 0-5, $400C bits 0-5)
/// Format: --LC VVVV
///   Bit 5 (L): Loop flag / length counter halt
///   Bit 4 (C): Constant volume flag
///   Bits 0-3 (V): Volume / envelope period
pub fn writeControl(envelope: *Envelope, value: u8) void {
    envelope.loop_flag = (value & 0x20) != 0;
    envelope.constant_volume = (value & 0x10) != 0;
    envelope.volume_envelope = @intCast(value & 0x0F);
}
