//! APU Logic
//!
//! This module contains pure functions that operate on APU state.
//! All functions receive ApuState as the first parameter.
//! Side effects (bus writes, IRQ signals) are handled by EmulationState.

const std = @import("std");
const StateModule = @import("State.zig");
const ApuState = StateModule.ApuState;
const Config = @import("../config/Config.zig");
const Dmc = @import("Dmc.zig");
const Envelope = @import("Envelope.zig");
const Sweep = @import("Sweep.zig");

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
// DMC Rate Tables
// ============================================================================

/// NTSC DMC rate table (timer periods in CPU cycles)
const DMC_RATE_TABLE_NTSC: [16]u16 = .{
    428, 380, 340, 320, 286, 254, 226, 214,
    190, 160, 142, 128, 106, 84, 72, 54,
};

/// PAL DMC rate table (timer periods in CPU cycles)
const DMC_RATE_TABLE_PAL: [16]u16 = .{
    398, 354, 316, 298, 276, 236, 210, 198,
    176, 148, 132, 118, 98, 78, 66, 50,
};

// ============================================================================
// Length Counter Table
// ============================================================================

/// Length counter lookup table (32 entries)
/// Indexed by bits 3-7 of $4003/$4007/$400B/$400F
/// Values sourced from NESDev wiki
const LENGTH_TABLE: [32]u8 = .{
    10, 254, 20,  2, 40,  4, 80,  6,   // 0x00-0x07
   160,   8, 60, 10, 14, 12, 26, 14,   // 0x08-0x0F
    12,  16, 24, 18, 48, 20, 96, 22,   // 0x10-0x17
   192,  24, 72, 26, 16, 28, 32, 30,   // 0x18-0x1F
};

// ============================================================================
// Public API
// ============================================================================

/// Initialize APU to power-on state
pub fn init() ApuState {
    return ApuState.init();
}

/// Reset APU (RESET button pressed)
pub fn reset(state: *ApuState) void {
    state.reset();
}

// ============================================================================
// Register Write Operations
// ============================================================================

/// Write to $4000-$4003 (Pulse 1)
pub fn writePulse1(state: *ApuState, offset: u2, value: u8) void {
    state.pulse1_regs[offset] = value;

    switch (offset) {
        0 => { // $4000: DDLC VVVV
            // Bit 5: Length counter halt / Envelope loop
            state.pulse1_halt = (value & 0x20) != 0;
            // Bits 0-5: Envelope control
            Envelope.writeControl(&state.pulse1_envelope, value);
        },
        1 => { // $4001: EPPP NSSS (Sweep control)
            Sweep.writeControl(&state.pulse1_sweep, value);
        },
        2 => { // $4002: TTTT TTTT (Timer low 8 bits)
            // Update low 8 bits of period
            state.pulse1_period = (state.pulse1_period & 0x700) | @as(u11, value);
        },
        3 => { // $4003: LLLL Lttt (Length counter load + timer high 3 bits)
            // Bits 3-7: Length counter table index (load if channel enabled)
            if (state.pulse1_enabled) {
                const table_index = (value >> 3) & 0x1F;
                state.pulse1_length = LENGTH_TABLE[table_index];
            }
            // Bits 0-2: Timer high 3 bits
            const timer_high = @as(u11, value & 0x07) << 8;
            state.pulse1_period = (state.pulse1_period & 0x0FF) | timer_high;
            // Restart envelope (sets start flag)
            Envelope.restart(&state.pulse1_envelope);
        },
    }
}

/// Write to $4004-$4007 (Pulse 2)
pub fn writePulse2(state: *ApuState, offset: u2, value: u8) void {
    state.pulse2_regs[offset] = value;

    switch (offset) {
        0 => { // $4004: DDLC VVVV
            // Bit 5: Length counter halt / Envelope loop
            state.pulse2_halt = (value & 0x20) != 0;
            // Bits 0-5: Envelope control
            Envelope.writeControl(&state.pulse2_envelope, value);
        },
        1 => { // $4005: EPPP NSSS (Sweep control)
            Sweep.writeControl(&state.pulse2_sweep, value);
        },
        2 => { // $4006: TTTT TTTT (Timer low 8 bits)
            // Update low 8 bits of period
            state.pulse2_period = (state.pulse2_period & 0x700) | @as(u11, value);
        },
        3 => { // $4007: LLLL Lttt (Length counter load + timer high 3 bits)
            // Bits 3-7: Length counter table index (load if channel enabled)
            if (state.pulse2_enabled) {
                const table_index = (value >> 3) & 0x1F;
                state.pulse2_length = LENGTH_TABLE[table_index];
            }
            // Bits 0-2: Timer high 3 bits
            const timer_high = @as(u11, value & 0x07) << 8;
            state.pulse2_period = (state.pulse2_period & 0x0FF) | timer_high;
            // Restart envelope (sets start flag)
            Envelope.restart(&state.pulse2_envelope);
        },
    }
}

/// Write to $4008-$400B (Triangle)
pub fn writeTriangle(state: *ApuState, offset: u2, value: u8) void {
    state.triangle_regs[offset] = value;

    switch (offset) {
        0 => { // $4008: CRRR RRRR
            // Bit 7: Length counter halt / Linear counter control
            state.triangle_halt = (value & 0x80) != 0;
            // Bits 0-6: Linear counter reload value
            state.triangle_linear_reload = @intCast(value & 0x7F);
        },
        3 => { // $400B: LLLL Lttt
            // Bits 3-7: Length counter table index (load if channel enabled)
            if (state.triangle_enabled) {
                const table_index = (value >> 3) & 0x1F;
                state.triangle_length = LENGTH_TABLE[table_index];
            }
            // Set linear counter reload flag
            state.triangle_linear_reload_flag = true;
            // TODO Phase 4: Timer high bits
        },
        else => {},
    }
}

/// Write to $400C-$400F (Noise)
pub fn writeNoise(state: *ApuState, offset: u2, value: u8) void {
    state.noise_regs[offset] = value;

    switch (offset) {
        0 => { // $400C: --LC VVVV
            // Bit 5: Length counter halt / Envelope loop
            state.noise_halt = (value & 0x20) != 0;
            // Bits 0-5: Envelope control
            Envelope.writeControl(&state.noise_envelope, value);
        },
        3 => { // $400F: LLLL L---
            // Bits 3-7: Length counter table index (load if channel enabled)
            if (state.noise_enabled) {
                const table_index = (value >> 3) & 0x1F;
                state.noise_length = LENGTH_TABLE[table_index];
            }
            // Restart envelope (sets start flag)
            Envelope.restart(&state.noise_envelope);
        },
        else => {},
    }
}

/// Write to $4010-$4013 (DMC)
pub fn writeDmc(state: *ApuState, offset: u2, value: u8) void {
    state.dmc_regs[offset] = value;

    switch (offset) {
        0 => Dmc.write4010(state, value), // $4010: IRQ enable, loop, frequency
        1 => Dmc.write4011(state, value), // $4011: Direct load (7-bit output level)
        2 => Dmc.write4012(state, value), // $4012: Sample address
        3 => Dmc.write4013(state, value), // $4013: Sample length
    }
}

/// Write to $4015 (Status/Control - channel enables)
pub fn writeControl(state: *ApuState, value: u8) void {
    state.pulse1_enabled = (value & 0x01) != 0;
    state.pulse2_enabled = (value & 0x02) != 0;
    state.triangle_enabled = (value & 0x04) != 0;
    state.noise_enabled = (value & 0x08) != 0;
    state.dmc_enabled = (value & 0x10) != 0;

    // Disabled channels: Clear length counter IMMEDIATELY
    if (!state.pulse1_enabled) state.pulse1_length = 0;
    if (!state.pulse2_enabled) state.pulse2_length = 0;
    if (!state.triangle_enabled) state.triangle_length = 0;
    if (!state.noise_enabled) state.noise_length = 0;

    // If DMC enabled, start sample (if not already playing)
    if (state.dmc_enabled) {
        Dmc.startSample(state);
    }

    // If DMC disabled, stop playback
    if (!state.dmc_enabled) {
        Dmc.stopSample(state);
    }

    // Clear DMC IRQ flag
    state.dmc_irq_flag = false;
}

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
    Envelope.clock(&state.pulse1_envelope);
    Envelope.clock(&state.pulse2_envelope);
    Envelope.clock(&state.noise_envelope);

    // Clock triangle linear counter
    clockLinearCounter(state);
}

/// Clock half-frame events (length counters and sweep units)
/// Called at frame counter steps: 2, 4 (and 5 in 5-step mode)
/// Runs at ~120 Hz (every 14913 CPU cycles)
fn clockHalfFrame(state: *ApuState) void {
    clockLengthCounters(state);

    // Clock sweep units (pulse 1 uses one's complement, pulse 2 uses two's complement)
    Sweep.clock(&state.pulse1_sweep, &state.pulse1_period, true);  // Pulse 1: one's complement
    Sweep.clock(&state.pulse2_sweep, &state.pulse2_period, false); // Pulse 2: two's complement
}

// ============================================================================
// Register Write Operations - Frame Counter
// ============================================================================

/// Write to $4017 (Frame Counter)
pub fn writeFrameCounter(state: *ApuState, value: u8) void {
    const new_mode = (value & 0x80) != 0; // Bit 7: 0=4-step, 1=5-step
    state.frame_counter_mode = new_mode;
    state.irq_inhibit = (value & 0x40) != 0; // Bit 6: IRQ inhibit

    // If 5-step mode: Immediately clock quarter + half frame (hardware behavior)
    // This is tested by AccuracyCoin APU Length Counter error code 3
    if (new_mode) {
        clockQuarterFrame(state);
        clockHalfFrame(state);
    }

    // Reset frame counter
    state.frame_counter_cycles = 0;

    // If IRQ inhibit set, clear frame IRQ flag
    if (state.irq_inhibit) {
        state.frame_irq_flag = false;
    }
}

/// Read from $4015 (Status)
/// Returns frame IRQ (bit 6) and DMC IRQ (bit 7)
/// Channel length counter status (bits 0-4) are stubs for now
pub fn readStatus(state: *const ApuState) u8 {
    var result: u8 = 0;

    // Bits 0-3: Channel length counter status
    if (state.pulse1_length > 0) result |= 0x01;
    if (state.pulse2_length > 0) result |= 0x02;
    if (state.triangle_length > 0) result |= 0x04;
    if (state.noise_length > 0) result |= 0x08;

    // Bit 4: DMC active (bytes remaining > 0)
    if (state.dmc_bytes_remaining > 0) result |= 0x10;

    // Bit 6: Frame interrupt flag
    if (state.frame_irq_flag) result |= 0x40;

    // Bit 7: DMC interrupt flag
    if (state.dmc_irq_flag) result |= 0x80;

    return result;
}

/// Clear frame IRQ flag
/// Called as side effect of reading $4015
pub fn clearFrameIrq(state: *ApuState) void {
    state.frame_irq_flag = false;
}

// ============================================================================
// Frame Counter Tick Logic
// ============================================================================

/// Tick frame counter (called every CPU cycle)
/// Returns true if IRQ should be generated
pub fn tickFrameCounter(state: *ApuState) bool {
    state.frame_counter_cycles += 1;

    const is_5_step = state.frame_counter_mode;
    const cycles = state.frame_counter_cycles;
    var should_irq = false;

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
                should_irq = true;
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

    return should_irq;
}

// ============================================================================
// DMC Channel Logic
// ============================================================================

/// Get current DMC sample address for DMA fetch
pub fn getSampleAddress(state: *const ApuState) u16 {
    return state.dmc_current_address;
}

/// Load sample byte into DMC buffer (called by DMA after fetch)
pub fn loadSampleByte(state: *ApuState, value: u8) void {
    Dmc.loadSampleByte(state, value);
}

/// Tick DMC timer and output unit (called every CPU cycle)
/// Returns true if DMA should be triggered to fetch next sample byte
/// The caller (EmulationState) is responsible for handling the DMA side effect
pub fn tickDmc(state: *ApuState) bool {
    return Dmc.tick(state);
}
