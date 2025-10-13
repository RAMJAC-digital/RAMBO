//! Envelope Logic (Pure Functions)
//!
//! Pure function implementation of the NES APU envelope generator.
//! Used by Pulse 1, Pulse 2, and Noise channels.
//!
//! Hardware Behavior (nesdev.org):
//! - Clocked at 240 Hz (quarter-frame rate)
//! - Start flag triggers reload: decay_level = 15, divider = period
//! - Divider counts down each quarter frame
//! - When divider expires: reload divider, decrement decay_level
//! - Decay level decrements from 15 → 0 (or loops back to 15)
//! - Output: constant volume OR decay level (based on constant_volume flag)

const std = @import("std");
const Envelope = @import("../Envelope.zig").Envelope;

/// Clock the envelope (called at 240 Hz / quarter-frame rate)
/// Pure function - takes const envelope state, returns new state
///
/// Hardware correspondence:
/// - Quarter frame tick (240 Hz)
/// - Start flag triggers reload
/// - Divider countdown
/// - Decay level update with optional loop
pub fn clock(envelope: *const Envelope) Envelope {
    var result = envelope.*;

    if (result.start_flag) {
        // Start flag set - restart envelope
        result.start_flag = false;
        result.decay_level = 15;
        result.divider = result.volume_envelope;
    } else {
        // Normal operation - countdown divider
        if (result.divider > 0) {
            result.divider -= 1;
        } else {
            // Divider expired - reload and update decay level
            result.divider = result.volume_envelope;

            if (result.decay_level > 0) {
                result.decay_level -= 1;
            } else if (result.loop_flag) {
                // Loop mode: reload decay level
                result.decay_level = 15;
            }
            // Non-loop mode: stays at 0
        }
    }

    return result;
}

/// Restart the envelope (typically called when $4003/$4007/$400F written)
/// Pure function - sets start_flag which triggers reload on next clock()
pub fn restart(envelope: *const Envelope) Envelope {
    var result = envelope.*;
    result.start_flag = true;
    return result;
}

/// Write to envelope control register ($4000 bits 0-5, $4004 bits 0-5, $400C bits 0-5)
/// Pure function - updates control bits
///
/// Format: --LC VVVV
///   Bit 5 (L): Loop flag / length counter halt
///   Bit 4 (C): Constant volume flag
///   Bits 0-3 (V): Volume / envelope period
pub fn writeControl(envelope: *const Envelope, value: u8) Envelope {
    var result = envelope.*;
    result.loop_flag = (value & 0x20) != 0;
    result.constant_volume = (value & 0x10) != 0;
    result.volume_envelope = @intCast(value & 0x0F);
    return result;
}
