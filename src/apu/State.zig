//! APU State
//!
//! This module defines the pure data structures for the APU state.
//! All state is owned directly by EmulationState (no pointers).

const std = @import("std");

/// APU Frame Counter State
/// Drives envelope, sweep, and length counter clocks at ~240 Hz
pub const ApuState = struct {
    // ===== Frame Counter State =====

    /// Frame counter mode: false = 4-step (14915 CPU cycles), true = 5-step (18641 CPU cycles)
    frame_counter_mode: bool = false,

    /// IRQ inhibit flag (bit 6 of $4017)
    irq_inhibit: bool = false,

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

    // ===== DMC (DPCM) Channel State =====

    /// DMC sample playback active
    dmc_active: bool = false,

    /// DMC IRQ flag (bit 7 of $4015)
    dmc_irq_flag: bool = false,

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

    /// DMC sample buffer (8-bit shift register)
    dmc_sample_buffer: u8 = 0,

    /// DMC output level (7-bit DAC)
    dmc_output: u7 = 0,

    /// DMC rate timer (controls playback frequency)
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

    /// Reset APU (RESET button pressed)
    /// Frame counter mode and IRQ inhibit are NOT reset
    /// All channels silenced
    pub fn reset(self: *ApuState) void {
        // Reset channel enables
        self.pulse1_enabled = false;
        self.pulse2_enabled = false;
        self.triangle_enabled = false;
        self.noise_enabled = false;
        self.dmc_enabled = false;

        // Clear length counters
        self.pulse1_length = 0;
        self.pulse2_length = 0;
        self.triangle_length = 0;
        self.noise_length = 0;

        // Clear IRQ flags
        self.frame_irq_flag = false;
        self.dmc_irq_flag = false;

        // Reset DMC state
        self.dmc_active = false;
        self.dmc_bytes_remaining = 0;

        // NOTE: frame_counter_mode and irq_inhibit are NOT reset
        // This matches hardware behavior
    }
};
