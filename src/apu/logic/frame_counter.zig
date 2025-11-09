//! APU Frame Counter Logic
//!
//! Handles the frame counter sequencer that clocks envelopes, length counters,
//! and sweep units at regular intervals (~240 Hz and ~120 Hz).
//!
//! The frame counter runs in either 4-step or 5-step mode:
//! - 4-step mode: Quarter frames at 7457, 14913, 22371 cycles
//!                Half frames at 14913, 29829 cycles (with IRQ)
//! - 5-step mode: Quarter frames at 7457, 14913, 22371, 37281 cycles
//!                Half frames at 14913, 37281 cycles (no IRQ)

const ApuState = @import("../State.zig").ApuState;
const Envelope = @import("../Envelope.zig");
const Sweep = @import("../Sweep.zig");
const envelope_logic = @import("envelope.zig");
const sweep_logic = @import("sweep.zig");

// ============================================================================
// Frame Counter Timing Constants (NTSC)
// ============================================================================

/// 4-step mode cycle counts (NTSC: 14915 total cycles)
const FRAME_4STEP_QUARTER1: u32 = 7457;
const FRAME_4STEP_HALF: u32 = 14913;
const FRAME_4STEP_QUARTER3: u32 = 22371;
const FRAME_4STEP_IRQ: u32 = 29829;
const FRAME_4STEP_TOTAL: u32 = 29830;

/// 5-step mode cycle counts (NTSC: 18641 total cycles)
const FRAME_5STEP_QUARTER1: u32 = 7457;
const FRAME_5STEP_HALF: u32 = 14913;
const FRAME_5STEP_QUARTER3: u32 = 22371;
const FRAME_5STEP_TOTAL: u32 = 37281;

// ============================================================================
// Length Counter Logic
// ============================================================================

/// Clock length counters (called on half-frame events)
/// Decrements each enabled channel's length counter (if not halted)
/// When counter reaches zero, channel is silenced
fn clockLengthCounters(state: *ApuState) void {
    // Pulse 1
    if (state.pulse1_length > 0 and !state.pulse1_halt) {
        state.pulse1_length -= 1;
    }

    // Pulse 2
    if (state.pulse2_length > 0 and !state.pulse2_halt) {
        state.pulse2_length -= 1;
    }

    // Triangle
    if (state.triangle_length > 0 and !state.triangle_halt) {
        state.triangle_length -= 1;
    }

    // Noise
    if (state.noise_length > 0 and !state.noise_halt) {
        state.noise_length -= 1;
    }
}

// ============================================================================
// Linear Counter Logic
// ============================================================================

/// Clock triangle linear counter (called on quarter-frame events)
/// The linear counter controls triangle channel timing
/// Hardware behavior:
/// - If reload flag set: Load counter with reload value
/// - Else if counter > 0: Decrement counter
/// - If halt flag clear: Clear reload flag
///
/// Public for testing
pub fn clockLinearCounter(state: *ApuState) void {
    if (state.triangle_linear_reload_flag) {
        state.triangle_linear_counter = state.triangle_linear_reload;
    } else if (state.triangle_linear_counter > 0) {
        state.triangle_linear_counter -= 1;
    }

    // Clear reload flag if halt flag is not set
    // triangle_halt is the "control flag" (bit 7 of $4008)
    if (!state.triangle_halt) {
        state.triangle_linear_reload_flag = false;
    }
}

// ============================================================================
// Frame Counter Clocking
// ============================================================================

/// Clock quarter-frame events (envelopes and triangle linear counter)
/// Called at frame counter steps: 1, 2, 3 (and 5 in 5-step mode)
/// Runs at ~240 Hz (every 7457 CPU cycles)
fn clockQuarterFrame(state: *ApuState) void {
    // Clock envelopes (pulse 1, pulse 2, noise)
    state.pulse1_envelope = envelope_logic.clock(&state.pulse1_envelope);
    state.pulse2_envelope = envelope_logic.clock(&state.pulse2_envelope);
    state.noise_envelope = envelope_logic.clock(&state.noise_envelope);

    // Clock triangle linear counter
    clockLinearCounter(state);
}

/// Clock half-frame events (length counters and sweep units)
/// Called at frame counter steps: 2, 4 (and 5 in 5-step mode)
/// Runs at ~120 Hz (every 14913 CPU cycles)
fn clockHalfFrame(state: *ApuState) void {
    clockLengthCounters(state);

    // Clock sweep units (pulse 1 uses one's complement, pulse 2 uses two's complement)
    const pulse1_result = sweep_logic.clock(&state.pulse1_sweep, state.pulse1_period, true);  // Pulse 1: one's complement
    state.pulse1_sweep = pulse1_result.sweep;
    state.pulse1_period = pulse1_result.period;

    const pulse2_result = sweep_logic.clock(&state.pulse2_sweep, state.pulse2_period, false); // Pulse 2: two's complement
    state.pulse2_sweep = pulse2_result.sweep;
    state.pulse2_period = pulse2_result.period;
}

// ============================================================================
// Frame Counter Tick Logic
// ============================================================================

/// Tick frame counter (called every CPU cycle)
/// Sets frame_irq_flag internally when IRQ should be generated
pub fn tickFrameCounter(state: *ApuState) void {
    state.frame_counter_cycles += 1;

    const is_5_step = state.frame_counter_mode;
    const cycles = state.frame_counter_cycles;

    if (!is_5_step) {
        // 4-step mode: Quarter frames at 7457, 14913, 22371
        //              Half frames at 14913, 29829
        if (cycles == FRAME_4STEP_QUARTER1) {
            clockQuarterFrame(state);
        } else if (cycles == FRAME_4STEP_HALF) {
            clockQuarterFrame(state);
            clockHalfFrame(state);
        } else if (cycles == FRAME_4STEP_QUARTER3) {
            clockQuarterFrame(state);
        } else if (cycles == FRAME_4STEP_IRQ) {
            clockHalfFrame(state);
        }

        // IRQ Edge Case: Flag is actively RE-SET during cycles 29829-29831
        // Even if $4015 is read at 29829 (clearing the flag), it gets set again on 29830-29831
        if (cycles >= FRAME_4STEP_IRQ and cycles <= FRAME_4STEP_IRQ + 2) {
            if (!state.irq_inhibit) {
                state.frame_irq_flag = true;
            }
        }

        // Reset after IRQ edge case period (after cycle 29831)
        if (cycles >= FRAME_4STEP_IRQ + 3) {
            state.frame_counter_cycles = 0;
        }
    } else {
        // 5-step mode: Quarter frames at 7457, 14913, 22371, 37281
        //              Half frames at 14913, 37281
        if (cycles == FRAME_5STEP_QUARTER1) {
            clockQuarterFrame(state);
        } else if (cycles == FRAME_5STEP_HALF) {
            clockQuarterFrame(state);
            clockHalfFrame(state);
        } else if (cycles == FRAME_5STEP_QUARTER3) {
            clockQuarterFrame(state);
        } else if (cycles == FRAME_5STEP_TOTAL) {
            clockQuarterFrame(state);
            clockHalfFrame(state);
            state.frame_counter_cycles = 0;
        }
    }
}

/// Clock quarter and half frame immediately
/// Called when $4017 is written with 5-step mode enabled
pub fn clockImmediately(state: *ApuState) void {
    clockQuarterFrame(state);
    clockHalfFrame(state);
}
