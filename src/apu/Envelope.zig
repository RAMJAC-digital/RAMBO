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

/// Get current envelope output volume (0-15)
/// Returns either constant volume or current decay level
/// NOTE: Mutable operations moved to logic/envelope.zig
pub fn getVolume(envelope: *const Envelope) u4 {
    if (envelope.constant_volume) {
        return envelope.volume_envelope;
    } else {
        return envelope.decay_level;
    }
}
