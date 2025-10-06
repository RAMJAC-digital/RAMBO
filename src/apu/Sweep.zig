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

/// Clock the sweep unit (called on half-frame events, ~120 Hz)
///
/// Parameters:
/// - sweep: Sweep unit state
/// - current_period: Current channel period (11-bit, will be modified if sweep triggers)
/// - ones_complement: If true, use one's complement negate (Pulse 1)
///                    If false, use two's complement negate (Pulse 2)
///
/// The sweep unit:
/// 1. Calculates target period
/// 2. If divider expires and sweep enabled and shift != 0, updates period
/// 3. Decrements divider or reloads on reload flag
pub fn clock(sweep: *Sweep, current_period: *u11, ones_complement: bool) void {
    // Calculate target period for sweep
    const change_amount: u12 = current_period.* >> sweep.shift;

    // Calculate target using u12 to prevent wrapping
    const target_period: u12 = if (sweep.negate) blk: {
        // Pulse 1 uses one's complement: period - (period >> shift) - 1
        // Pulse 2 uses two's complement: period - (period >> shift)
        const base: u12 = current_period.*;
        if (ones_complement) {
            break :blk base -% change_amount -% 1;
        } else {
            break :blk base -% change_amount;
        }
    } else blk: {
        // Increase period (lower frequency)
        const base: u12 = current_period.*;
        break :blk base + change_amount;
    };

    // Clock divider
    if (sweep.divider == 0 or sweep.reload_flag) {
        // Reload divider
        sweep.divider = sweep.period;
        sweep.reload_flag = false;

        // Update period if conditions met (when divider reloads)
        // Conditions: sweep enabled, shift != 0, target valid (<= $7FF)
        const should_update = sweep.enabled and
                             (sweep.shift != 0) and
                             (target_period <= 0x7FF);

        if (should_update) {
            current_period.* = @intCast(target_period);
        }
    } else {
        sweep.divider -= 1;
    }
}

/// Check if sweep unit is muting the channel
///
/// A channel is muted if:
/// 1. Current period < 8, OR
/// 2. Target period > $7FF (when negate = 0)
///
/// Parameters:
/// - sweep: Sweep unit state
/// - current_period: Current channel period
/// - ones_complement: If true, use one's complement negate (Pulse 1)
///
/// Returns: true if channel should be muted
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

/// Write sweep control register ($4001 for Pulse 1, $4005 for Pulse 2)
///
/// Format: EPPP NSSS
/// - E (bit 7): Enabled
/// - PPP (bits 4-6): Period
/// - N (bit 3): Negate
/// - SSS (bits 0-2): Shift
///
/// Side effect: Sets reload flag
pub fn writeControl(sweep: *Sweep, value: u8) void {
    sweep.enabled = (value & 0x80) != 0;
    sweep.period = @intCast((value >> 4) & 0x07);
    sweep.negate = (value & 0x08) != 0;
    sweep.shift = @intCast(value & 0x07);
    sweep.reload_flag = true;
}
