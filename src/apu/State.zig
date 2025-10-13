//! APU State
//!
//! This module defines the pure data structures for the APU state.
//! All state is owned directly by EmulationState (no pointers).

const std = @import("std");
const Envelope = @import("Envelope.zig").Envelope;
const Sweep = @import("Sweep.zig").Sweep;

/// APU Frame Counter State
/// Drives envelope, sweep, and length counter clocks at ~240 Hz
pub const ApuState = struct {
    // ===== Frame Counter State =====

    /// Frame counter mode: false = 4-step (14915 CPU cycles), true = 5-step (18641 CPU cycles)
    frame_counter_mode: bool = false,

    /// IRQ inhibit flag (bit 6 of $4017)
    /// Hardware default: IRQ disabled at power-on (nesdev.org/wiki/APU)
    irq_inhibit: bool = true,

    /// Frame IRQ flag (readable via $4015 bit 6)
    frame_irq_flag: bool = false,

    /// Current cycle within frame sequence
    /// Resets to 0 at end of each frame sequence
    frame_counter_cycles: u32 = 0,

    // ===== Channel Enable Flags (from $4015) =====

    pulse1_enabled: bool = false,
    pulse2_enabled: bool = false,
    triangle_enabled: bool = false,
    noise_enabled: bool = false,
    dmc_enabled: bool = false,

    // ===== Length Counters =====
    // Each channel has a length counter that:
    // - Loads from LENGTH_TABLE when $400X register 3 is written
    // - Decrements on half-frame clock events (~120 Hz)
    // - Silences channel when it reaches zero
    // - Can be halted (prevented from decrementing) by halt flag

    pulse1_length: u8 = 0,
    pulse2_length: u8 = 0,
    triangle_length: u8 = 0,
    noise_length: u8 = 0,

    // ===== Length Counter Halt Flags =====
    // From $4000 bit 5 (pulse1), $4004 bit 5 (pulse2),
    // $4008 bit 7 (triangle), $400C bit 5 (noise)
    // When set: Length counter does NOT decrement (infinite play)

    pulse1_halt: bool = false,
    pulse2_halt: bool = false,
    triangle_halt: bool = false,
    noise_halt: bool = false,

    // ===== Envelopes =====
    // Each channel with volume control has an envelope generator
    // Clocked at 240 Hz (quarter-frame rate)
    // Provides either constant volume or decaying volume (0-15)

    pulse1_envelope: Envelope = .{},
    pulse2_envelope: Envelope = .{},
    noise_envelope: Envelope = .{},

    // ===== Linear Counter (Triangle Channel) =====
    // Triangle channel uses a linear counter instead of an envelope
    // Clocked at 240 Hz (quarter-frame rate)
    // Controls triangle channel timing along with length counter

    /// Linear counter value (7-bit, 0-127)
    /// Counts down each quarter frame when not reloading
    /// Triangle is silenced when zero
    triangle_linear_counter: u7 = 0,

    /// Linear counter reload value (from $4008 bits 0-6)
    /// Loaded into linear_counter when reload_flag is set
    triangle_linear_reload: u7 = 0,

    /// Linear counter reload flag
    /// Set when $400B is written (triangle length counter load)
    /// Cleared when halt flag is clear and quarter frame clocks
    triangle_linear_reload_flag: bool = false,

    // ===== Sweep Units (Pulse Channels) =====
    // Each pulse channel has a sweep unit that modulates its period
    // Clocked at 120 Hz (half-frame rate)
    // Controls frequency sweeps (pitch bends)

    pulse1_sweep: Sweep = .{},
    pulse2_sweep: Sweep = .{},

    // ===== Pulse Channel Periods (Timers) =====
    // 11-bit timer periods for pulse channels
    // Modified by sweep units, used for waveform generation (Phase 3+)
    // Formula: frequency = CPU_CLOCK / (16 * (period + 1))

    /// Pulse 1 timer period (11-bit, $4002/$4003)
    pulse1_period: u11 = 0,

    /// Pulse 2 timer period (11-bit, $4006/$4007)
    pulse2_period: u11 = 0,

    // ===== DMC (DPCM) Channel State =====

    /// DMC sample playback active
    dmc_active: bool = false,

    /// DMC IRQ flag (bit 7 of $4015)
    dmc_irq_flag: bool = false,

    /// DMC IRQ enable flag (bit 7 of $4010)
    dmc_irq_enabled: bool = false,

    /// DMC loop flag (bit 6 of $4010)
    dmc_loop_flag: bool = false,

    /// DMC sample address (16-bit)
    /// Computed as $C000 + (dmc_sample_address × 64)
    dmc_sample_address: u8 = 0,

    /// DMC sample length (in bytes)
    /// Computed as (dmc_sample_length × 16) + 1
    dmc_sample_length: u8 = 0,

    /// DMC bytes remaining in current sample
    dmc_bytes_remaining: u16 = 0,

    /// DMC current address (increments as sample plays)
    dmc_current_address: u16 = 0,

    /// DMC sample buffer holds the next byte to be played
    dmc_sample_buffer: u8 = 0,

    /// DMC sample buffer empty flag (true when buffer needs refill)
    dmc_sample_buffer_empty: bool = true,

    /// DMC output shift register (shifts out bits for playback)
    dmc_shift_register: u8 = 0,

    /// DMC bits remaining in shift register (0-8)
    dmc_bits_remaining: u4 = 0,

    /// DMC silence flag (set when no sample data available)
    dmc_silence_flag: bool = true,

    /// DMC output level (7-bit DAC, 0-127)
    dmc_output: u7 = 0,

    /// DMC rate timer (counts down each CPU cycle)
    dmc_timer: u16 = 0,

    /// DMC timer period (from rate table, NTSC/PAL-specific)
    dmc_timer_period: u16 = 0,

    // ===== Channel Register Storage (write-only for Phase 1) =====
    // These are stubs - we're not implementing audio synthesis yet

    pulse1_regs: [4]u8 = [_]u8{0} ** 4,
    pulse2_regs: [4]u8 = [_]u8{0} ** 4,
    triangle_regs: [4]u8 = [_]u8{0} ** 4,
    noise_regs: [4]u8 = [_]u8{0} ** 4,
    dmc_regs: [4]u8 = [_]u8{0} ** 4,

    /// Initialize APU to power-on state
    pub fn init() ApuState {
        return .{};
    }
};
