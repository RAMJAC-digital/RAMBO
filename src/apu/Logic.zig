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
    // TODO: Actual pulse channel implementation (Phase 2: Audio Synthesis)
}

/// Write to $4004-$4007 (Pulse 2)
pub fn writePulse2(state: *ApuState, offset: u2, value: u8) void {
    state.pulse2_regs[offset] = value;
    // TODO: Actual pulse channel implementation
}

/// Write to $4008-$400B (Triangle)
pub fn writeTriangle(state: *ApuState, offset: u2, value: u8) void {
    state.triangle_regs[offset] = value;
    // TODO: Actual triangle channel implementation
}

/// Write to $400C-$400F (Noise)
pub fn writeNoise(state: *ApuState, offset: u2, value: u8) void {
    state.noise_regs[offset] = value;
    // TODO: Actual noise channel implementation
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

/// Write to $4017 (Frame Counter)
pub fn writeFrameCounter(state: *ApuState, value: u8) void {
    state.frame_counter_mode = (value & 0x80) != 0; // Bit 7: 0=4-step, 1=5-step
    state.irq_inhibit = (value & 0x40) != 0; // Bit 6: IRQ inhibit

    // Reset frame counter
    state.frame_counter_cycles = 0;

    // If IRQ inhibit set, clear frame IRQ flag
    if (state.irq_inhibit) {
        state.frame_irq_flag = false;
    }

    // TODO: If 5-step mode, immediately clock envelopes/length (hardware quirk)
    // Deferred to Phase 2: Audio Synthesis
}

/// Read from $4015 (Status)
/// Returns frame IRQ (bit 6) and DMC IRQ (bit 7)
/// Channel length counter status (bits 0-4) are stubs for now
pub fn readStatus(state: *const ApuState) u8 {
    var result: u8 = 0;

    // Bit 6: Frame interrupt flag
    if (state.frame_irq_flag) result |= 0x40;

    // Bit 7: DMC interrupt flag
    if (state.dmc_irq_flag) result |= 0x80;

    // Bits 0-4: Channel length counter status (stub, always 0)
    // TODO: Implement length counters (Phase 2: Audio Synthesis)

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
        // 4-step mode
        if (cycles == FRAME_4STEP_IRQ or cycles == FRAME_4STEP_IRQ + 1) {
            // Set IRQ flag if not inhibited
            if (!state.irq_inhibit) {
                state.frame_irq_flag = true;
                should_irq = true; // Signal IRQ to CPU
            }
        }

        // Reset at end of sequence
        if (cycles >= FRAME_4STEP_TOTAL) {
            state.frame_counter_cycles = 0;
        }
    } else {
        // 5-step mode (no IRQ)
        if (cycles >= FRAME_5STEP_TOTAL) {
            state.frame_counter_cycles = 0;
        }
    }

    // TODO: Clock envelopes/length counters at quarter/half frames
    // Deferred to Phase 2: Audio Synthesis

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
