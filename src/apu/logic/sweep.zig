//! APU Sweep Unit Logic (Pure Functions)
//!
//! Pure function implementation of the NES APU sweep units used by Pulse channels.
//! Clocked at 120 Hz (half-frame rate).
//!
//! Hardware Behavior (nesdev.org):
//! - Each pulse channel has a sweep unit
//! - Periodically adjusts channel period (frequency modulation)
//! - Pulse 1 uses one's complement negate
//! - Pulse 2 uses two's complement negate
//! - Sweep can mute channel (period < 8 or target > $7FF)

const std = @import("std");
const Sweep = @import("../Sweep.zig").Sweep;

/// Result of clocking the sweep unit
/// Contains both the new sweep state and potentially updated period
pub const SweepClockResult = struct {
    sweep: Sweep,
    period: u11,
};

/// Clock the sweep unit (called on half-frame events, ~120 Hz)
/// Pure function - takes const sweep and period, returns result with updates
///
/// Parameters:
/// - sweep: Sweep unit state
/// - current_period: Current channel period (11-bit)
/// - ones_complement: If true, use one's complement negate (Pulse 1)
///                    If false, use two's complement negate (Pulse 2)
///
/// The sweep unit:
/// 1. Calculates target period
/// 2. If divider expires and sweep enabled and shift != 0, updates period
/// 3. Decrements divider or reloads on reload flag
pub fn clock(sweep: *const Sweep, current_period: u11, ones_complement: bool) SweepClockResult {
    var result_sweep = sweep.*;
    var result_period = current_period;

    // Calculate target period for sweep
    const change_amount: u12 = current_period >> result_sweep.shift;

    // Calculate target using u12 to prevent wrapping
    const target_period: u12 = if (result_sweep.negate) blk: {
        // Pulse 1 uses one's complement: period - (period >> shift) - 1
        // Pulse 2 uses two's complement: period - (period >> shift)
        const base: u12 = current_period;
        if (ones_complement) {
            break :blk base -% change_amount -% 1;
        } else {
            break :blk base -% change_amount;
        }
    } else blk: {
        // Increase period (lower frequency)
        const base: u12 = current_period;
        break :blk base + change_amount;
    };

    // Clock divider
    if (result_sweep.divider == 0 or result_sweep.reload_flag) {
        // Reload divider
        result_sweep.divider = result_sweep.period;
        result_sweep.reload_flag = false;

        // Update period if conditions met (when divider reloads)
        // Conditions: sweep enabled, shift != 0, target valid (<= $7FF)
        const should_update = result_sweep.enabled and
                             (result_sweep.shift != 0) and
                             (target_period <= 0x7FF);

        if (should_update) {
            result_period = @intCast(target_period);
        }
    } else {
        result_sweep.divider -= 1;
    }

    return .{
        .sweep = result_sweep,
        .period = result_period,
    };
}

/// Write sweep control register ($4001 for Pulse 1, $4005 for Pulse 2)
/// Pure function - updates sweep state
///
/// Format: EPPP NSSS
/// - E (bit 7): Enabled
/// - PPP (bits 4-6): Period
/// - N (bit 3): Negate
/// - SSS (bits 0-2): Shift
///
/// Side effect: Sets reload flag
pub fn writeControl(sweep: *const Sweep, value: u8) Sweep {
    var result = sweep.*;
    result.enabled = (value & 0x80) != 0;
    result.period = @intCast((value >> 4) & 0x07);
    result.negate = (value & 0x08) != 0;
    result.shift = @intCast(value & 0x07);
    result.reload_flag = true;
    return result;
}
