//! APU Logic
//!
//! This module contains pure functions that operate on APU state.
//! All functions receive ApuState as the first parameter.
//! Side effects (bus writes, IRQ signals) are handled by EmulationState.

const std = @import("std");
const StateModule = @import("State.zig");
const ApuState = StateModule.ApuState;
const Config = @import("../config/Config.zig");

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
            // TODO Phase 2: Duty, constant volume, envelope period
        },
        3 => { // $4003: LLLL Lttt
            // Bits 3-7: Length counter table index (load if channel enabled)
            if (state.pulse1_enabled) {
                const table_index = (value >> 3) & 0x1F;
                state.pulse1_length = LENGTH_TABLE[table_index];
            }
            // TODO Phase 2: Timer high bits
        },
        else => {}, // $4001 (sweep), $4002 (timer low) - not needed for length counter
    }
}

/// Write to $4004-$4007 (Pulse 2)
pub fn writePulse2(state: *ApuState, offset: u2, value: u8) void {
    state.pulse2_regs[offset] = value;

    switch (offset) {
        0 => { // $4004: DDLC VVVV
            // Bit 5: Length counter halt / Envelope loop
            state.pulse2_halt = (value & 0x20) != 0;
            // TODO Phase 2: Duty, constant volume, envelope period
        },
        3 => { // $4007: LLLL Lttt
            // Bits 3-7: Length counter table index (load if channel enabled)
            if (state.pulse2_enabled) {
                const table_index = (value >> 3) & 0x1F;
                state.pulse2_length = LENGTH_TABLE[table_index];
            }
            // TODO Phase 2: Timer high bits
        },
        else => {},
    }
}

/// Write to $4008-$400B (Triangle)
pub fn writeTriangle(state: *ApuState, offset: u2, value: u8) void {
    state.triangle_regs[offset] = value;

    switch (offset) {
        0 => { // $4008: CRRR RRRR
            // Bit 7: Length counter halt / Linear counter control
            state.triangle_halt = (value & 0x80) != 0;
            // TODO Phase 2: Linear counter reload value
        },
        3 => { // $400B: LLLL Lttt
            // Bits 3-7: Length counter table index (load if channel enabled)
            if (state.triangle_enabled) {
                const table_index = (value >> 3) & 0x1F;
                state.triangle_length = LENGTH_TABLE[table_index];
            }
            // TODO Phase 2: Timer high bits
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
            // TODO Phase 2: Constant volume, envelope period
        },
        3 => { // $400F: LLLL L---
            // Bits 3-7: Length counter table index (load if channel enabled)
            if (state.noise_enabled) {
                const table_index = (value >> 3) & 0x1F;
                state.noise_length = LENGTH_TABLE[table_index];
            }
        },
        else => {},
    }
}

/// Write to $4010-$4013 (DMC)
pub fn writeDmc(state: *ApuState, offset: u2, value: u8) void {
    state.dmc_regs[offset] = value;

    switch (offset) {
        0 => { // $4010: IRQ enable, loop, frequency
            const rate_index = value & 0x0F;
            // Rate table selection depends on NTSC/PAL (caller provides config)
            // For now, use NTSC table (will be parameterized in tickApu)
            state.dmc_timer_period = DMC_RATE_TABLE_NTSC[rate_index];
        },
        1 => { // $4011: Direct load (7-bit output level)
            state.dmc_output = @intCast(value & 0x7F);
        },
        2 => { // $4012: Sample address
            state.dmc_sample_address = value;
        },
        3 => { // $4013: Sample length
            state.dmc_sample_length = value;
        },
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

    // If DMC enabled and no bytes remaining, load sample
    if (state.dmc_enabled and state.dmc_bytes_remaining == 0) {
        // Load sample address and length
        state.dmc_current_address = 0xC000 + (@as(u16, state.dmc_sample_address) << 6);
        state.dmc_bytes_remaining = (@as(u16, state.dmc_sample_length) << 4) + 1;
        state.dmc_active = true;
    }

    // If DMC disabled, stop playback
    if (!state.dmc_enabled) {
        state.dmc_active = false;
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
// Frame Counter Clocking
// ============================================================================

/// Clock quarter-frame events (envelopes and triangle linear counter)
/// Called at frame counter steps: 1, 2, 3 (and 5 in 5-step mode)
fn clockQuarterFrame(state: *ApuState) void {
    // TODO Phase 2: Clock envelopes (pulse 1, pulse 2, noise)
    // TODO Phase 2: Clock triangle linear counter
    _ = state;
}

/// Clock half-frame events (length counters and sweep units)
/// Called at frame counter steps: 2, 4 (and 5 in 5-step mode)
fn clockHalfFrame(state: *ApuState) void {
    clockLengthCounters(state);
    // TODO Phase 2: Clock sweep units (pulse 1, pulse 2)
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

            // Set IRQ flag if not inhibited
            if (!state.irq_inhibit) {
                state.frame_irq_flag = true;
                should_irq = true;
            }
        }

        // Reset at end of sequence
        if (cycles >= FRAME_4STEP_TOTAL) {
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

/// Check if DMC needs to fetch next sample byte
/// Returns true if DMA should be triggered
pub fn needsSampleFetch(state: *const ApuState) bool {
    return state.dmc_active and state.dmc_bytes_remaining > 0;
}

/// Get current DMC sample address for DMA fetch
pub fn getSampleAddress(state: *const ApuState) u16 {
    return state.dmc_current_address;
}

/// Load sample byte into DMC buffer (called by DMA after fetch)
pub fn loadSampleByte(state: *ApuState, value: u8) void {
    state.dmc_sample_buffer = value;

    // Increment address with wrap at $FFFF -> $8000
    if (state.dmc_current_address == 0xFFFF) {
        state.dmc_current_address = 0x8000;
    } else {
        state.dmc_current_address += 1;
    }

    // Decrement bytes remaining
    state.dmc_bytes_remaining -= 1;

    // If sample complete, check for loop or IRQ
    if (state.dmc_bytes_remaining == 0) {
        const loop_flag = (state.dmc_regs[0] & 0x40) != 0;
        const irq_enabled = (state.dmc_regs[0] & 0x80) != 0;

        if (loop_flag) {
            // Restart sample
            state.dmc_current_address = 0xC000 + (@as(u16, state.dmc_sample_address) << 6);
            state.dmc_bytes_remaining = (@as(u16, state.dmc_sample_length) << 4) + 1;
        } else {
            // Sample complete
            state.dmc_active = false;

            // Generate IRQ if enabled
            if (irq_enabled) {
                state.dmc_irq_flag = true;
            }
        }
    }
}
