//! APU Sweep Unit
//!
//! This module implements the pulse channel sweep units.
//! Each pulse channel has a sweep unit that periodically adjusts the channel's period.
//! Clocked at 120 Hz (half-frame rate).

const std = @import("std");

/// Sweep unit state
/// Used by both pulse channels to modulate frequency
pub const Sweep = struct {
    /// Sweep enabled flag (bit 7 of $4001/$4005)
    enabled: bool = false,

    /// Divider counter (counts down from period)
    divider: u3 = 0,

    /// Divider period (reload value, bits 4-6 of $4001/$4005)
    period: u3 = 0,

    /// Negate flag (bit 3 of $4001/$4005)
    /// If true, sweep decreases period (increases frequency)
    negate: bool = false,

    /// Shift amount (bits 0-2 of $4001/$4005)
    /// Determines how much to change the period
    shift: u3 = 0,

    /// Reload flag (set when $4001/$4005 is written)
    /// Cleared on next half-frame clock
    reload_flag: bool = false,
};

/// Check if sweep unit is muting the channel
/// A channel is muted if:
/// 1. Current period < 8, OR
/// 2. Target period > $7FF (when negate = 0)
///
/// NOTE: Mutable operations (clock, writeControl) moved to logic/sweep.zig
pub fn isMuting(sweep: *const Sweep, current_period: u11, ones_complement: bool) bool {
    // Mute if period too low
    if (current_period < 8) {
        return true;
    }

    // Calculate target period using u12 to prevent wrapping
    const change_amount: u12 = current_period >> sweep.shift;
    const target_period: u12 = if (sweep.negate) blk: {
        const base: u12 = current_period;
        if (ones_complement) {
            break :blk base -% change_amount -% 1;
        } else {
            break :blk base -% change_amount;
        }
    } else blk: {
        const base: u12 = current_period;
        break :blk base + change_amount;
    };

    // Mute if target period too high (only when not negating)
    if (!sweep.negate and target_period > 0x7FF) {
        return true;
    }

    return false;
}
