//! APU Register I/O Operations
//!
//! Handles reading and writing APU registers ($4000-$4017).
//! Implements register side effects and state updates.

const std = @import("std");
const ApuState = @import("../State.zig").ApuState;
const Dmc = @import("../Dmc.zig");
const Envelope = @import("../Envelope.zig");
const Sweep = @import("../Sweep.zig");
const tables = @import("tables.zig");
const frame_counter = @import("frame_counter.zig");

// ============================================================================
// Pulse Channel Register Writes
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
                state.pulse1_length = tables.LENGTH_TABLE[table_index];
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
                state.pulse2_length = tables.LENGTH_TABLE[table_index];
            }
            // Bits 0-2: Timer high 3 bits
            const timer_high = @as(u11, value & 0x07) << 8;
            state.pulse2_period = (state.pulse2_period & 0x0FF) | timer_high;
            // Restart envelope (sets start flag)
            Envelope.restart(&state.pulse2_envelope);
        },
    }
}

// ============================================================================
// Triangle Channel Register Writes
// ============================================================================

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
                state.triangle_length = tables.LENGTH_TABLE[table_index];
            }
            // Set linear counter reload flag
            state.triangle_linear_reload_flag = true;
            // TODO Phase 4: Timer high bits
        },
        else => {},
    }
}

// ============================================================================
// Noise Channel Register Writes
// ============================================================================

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
                state.noise_length = tables.LENGTH_TABLE[table_index];
            }
            // Restart envelope (sets start flag)
            Envelope.restart(&state.noise_envelope);
        },
        else => {},
    }
}

// ============================================================================
// DMC Channel Register Writes
// ============================================================================

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

// ============================================================================
// Control/Status Register Operations
// ============================================================================

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

/// Write to $4017 (Frame Counter)
pub fn writeFrameCounter(state: *ApuState, value: u8) void {
    const new_mode = (value & 0x80) != 0; // Bit 7: 0=4-step, 1=5-step
    state.frame_counter_mode = new_mode;
    state.irq_inhibit = (value & 0x40) != 0; // Bit 6: IRQ inhibit

    // If 5-step mode: Immediately clock quarter + half frame (hardware behavior)
    // This is tested by AccuracyCoin APU Length Counter error code 3
    if (new_mode) {
        frame_counter.clockImmediately(state);
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
