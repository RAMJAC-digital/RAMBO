//! APU Logic
//!
//! Facade module delegating to specialized APU logic modules.
//! All functions operate on APU state with explicit parameters.

const std = @import("std");
const StateModule = @import("State.zig");
const ApuState = StateModule.ApuState;
const Dmc = @import("Dmc.zig");

// Logic modules
const registers = @import("logic/registers.zig");
const frame_counter = @import("logic/frame_counter.zig");
const tables = @import("logic/tables.zig");

// Re-export tables for external use
pub const DMC_RATE_TABLE_NTSC = tables.DMC_RATE_TABLE_NTSC;
pub const DMC_RATE_TABLE_PAL = tables.DMC_RATE_TABLE_PAL;
pub const LENGTH_TABLE = tables.LENGTH_TABLE;

/// Initialize APU to power-on state
pub fn init() ApuState {
    return ApuState.init();
}

/// Reset APU (RESET button pressed)
pub fn reset(state: *ApuState) void {
    // Reset channel enables
    state.pulse1_enabled = false;
    state.pulse2_enabled = false;
    state.triangle_enabled = false;
    state.noise_enabled = false;
    state.dmc_enabled = false;

    // Clear length counters
    state.pulse1_length = 0;
    state.pulse2_length = 0;
    state.triangle_length = 0;
    state.noise_length = 0;

    // Clear IRQ flags
    state.frame_irq_flag = false;
    state.dmc_irq_flag = false;

    // Reset DMC state
    state.dmc_active = false;
    state.dmc_bytes_remaining = 0;
    state.dmc_sample_buffer_empty = true;
    state.dmc_silence_flag = true;
    state.dmc_bits_remaining = 0;
    state.dmc_shift_register = 0;

    // NOTE: frame_counter_mode and irq_inhibit are NOT reset
    // This matches hardware behavior
}

// ============================================================================
// Register Write Operations (delegate to registers.zig)
// ============================================================================

/// Write to $4000-$4003 (Pulse 1)
pub inline fn writePulse1(state: *ApuState, offset: u2, value: u8) void {
    registers.writePulse1(state, offset, value);
}

/// Write to $4004-$4007 (Pulse 2)
pub inline fn writePulse2(state: *ApuState, offset: u2, value: u8) void {
    registers.writePulse2(state, offset, value);
}

/// Write to $4008-$400B (Triangle)
pub inline fn writeTriangle(state: *ApuState, offset: u2, value: u8) void {
    registers.writeTriangle(state, offset, value);
}

/// Write to $400C-$400F (Noise)
pub inline fn writeNoise(state: *ApuState, offset: u2, value: u8) void {
    registers.writeNoise(state, offset, value);
}

/// Write to $4010-$4013 (DMC)
pub inline fn writeDmc(state: *ApuState, offset: u2, value: u8) void {
    registers.writeDmc(state, offset, value);
}

/// Write to $4015 (Status/Control - channel enables)
pub inline fn writeControl(state: *ApuState, value: u8) void {
    registers.writeControl(state, value);
}

/// Write to $4017 (Frame Counter)
pub inline fn writeFrameCounter(state: *ApuState, value: u8) void {
    registers.writeFrameCounter(state, value);
}

/// Read from $4015 (Status)
pub inline fn readStatus(state: *const ApuState) u8 {
    return registers.readStatus(state);
}

/// Clear frame IRQ flag (side effect of reading $4015)
pub inline fn clearFrameIrq(state: *ApuState) void {
    registers.clearFrameIrq(state);
}

// ============================================================================
// Frame Counter Operations (delegate to frame_counter.zig)
// ============================================================================

/// Clock triangle linear counter (public for testing)
pub inline fn clockLinearCounter(state: *ApuState) void {
    frame_counter.clockLinearCounter(state);
}

/// Tick frame counter (called every CPU cycle)
/// Returns true if IRQ should be generated
pub inline fn tickFrameCounter(state: *ApuState) bool {
    return frame_counter.tickFrameCounter(state);
}

// ============================================================================
// DMC Channel Operations (delegate to Dmc.zig)
// ============================================================================

/// Get current DMC sample address for DMA fetch
pub inline fn getSampleAddress(state: *const ApuState) u16 {
    return state.dmc_current_address;
}

/// Load sample byte into DMC buffer (called by DMA after fetch)
pub inline fn loadSampleByte(state: *ApuState, value: u8) void {
    Dmc.loadSampleByte(state, value);
}

/// Tick DMC timer and output unit (called every CPU cycle)
/// Returns true if DMA should be triggered to fetch next sample byte
pub inline fn tickDmc(state: *ApuState) bool {
    return Dmc.tick(state);
}
