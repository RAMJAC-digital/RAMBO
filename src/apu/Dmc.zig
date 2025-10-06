//! DMC (Delta Modulation Channel) Logic
//!
//! Implements the NES DMC channel timer and output unit.
//! The DMC plays 1-bit delta-encoded samples from cartridge ROM/RAM.
//!
//! Hardware Behavior:
//! - Timer counts down every CPU cycle
//! - On timer expiration: clock output unit (shift out 1 bit)
//! - Output level modified by +2 or -2 based on bit value
//! - Output level clamped to 0-127 range
//! - Sample buffer refilled via DMA when empty
//! - IRQ generated when sample completes (if enabled)

const std = @import("std");
const ApuState = @import("State.zig").ApuState;

/// DMC rate table (NTSC) - timer periods in CPU cycles
/// Indexed by bits 0-3 of $4010
pub const RATE_TABLE_NTSC: [16]u16 = .{
    428, 380, 340, 320, 286, 254, 226, 214,
    190, 160, 142, 128, 106, 84,  72,  54,
};

/// Tick the DMC timer and output unit (called every CPU cycle)
/// Returns true if DMA should be triggered to load next sample byte
pub fn tick(apu: *ApuState) bool {
    // If DMC not enabled or no bytes remaining, nothing to do
    if (!apu.dmc_enabled) return false;

    var trigger_dma = false;

    // Timer countdown
    if (apu.dmc_timer > 0) {
        apu.dmc_timer -= 1;
    } else {
        // Timer expired - reload and clock output unit
        apu.dmc_timer = apu.dmc_timer_period;
        trigger_dma = clockOutputUnit(apu);
    }

    return trigger_dma;
}

/// Clock the DMC output unit (shift out 1 bit, modify output level)
/// Returns true if DMA should be triggered
fn clockOutputUnit(apu: *ApuState) bool {
    var trigger_dma = false;

    if (!apu.dmc_silence_flag) {
        // Shift out one bit from the shift register
        const bit = apu.dmc_shift_register & 0x01;
        apu.dmc_shift_register >>= 1;
        apu.dmc_bits_remaining -= 1;

        // Modify output level based on bit value
        // bit=1: increment by 2 (if <= 125)
        // bit=0: decrement by 2 (if >= 2)
        if (bit == 1) {
            if (apu.dmc_output <= 125) {
                apu.dmc_output += 2;
            }
        } else {
            if (apu.dmc_output >= 2) {
                apu.dmc_output -= 2;
            }
        }

        // Check if we've shifted out all 8 bits
        if (apu.dmc_bits_remaining == 0) {
            apu.dmc_bits_remaining = 8;

            // Try to load next byte from sample buffer
            if (apu.dmc_sample_buffer_empty) {
                // No data available - enter silence mode
                apu.dmc_silence_flag = true;
            } else {
                // Load new byte into shift register
                apu.dmc_shift_register = apu.dmc_sample_buffer;
                apu.dmc_sample_buffer_empty = true;

                // If we still have bytes to play, trigger DMA for next byte
                if (apu.dmc_bytes_remaining > 0) {
                    trigger_dma = true;
                }
            }
        }
    }

    return trigger_dma;
}

/// Load a sample byte into the DMC sample buffer
/// Called by the DMA controller when a byte is read from memory
pub fn loadSampleByte(apu: *ApuState, byte: u8) void {
    // Store byte in sample buffer
    apu.dmc_sample_buffer = byte;
    apu.dmc_sample_buffer_empty = false;

    // If we were in silence mode and have data, exit silence
    if (apu.dmc_silence_flag and apu.dmc_bits_remaining == 0) {
        // Start playing the new byte
        apu.dmc_silence_flag = false;
        apu.dmc_shift_register = byte;
        apu.dmc_bits_remaining = 8;
        apu.dmc_sample_buffer_empty = true;
    }

    // Decrement bytes remaining
    if (apu.dmc_bytes_remaining > 0) {
        apu.dmc_bytes_remaining -= 1;

        // Increment address (wrap at $FFFF → $8000)
        if (apu.dmc_current_address == 0xFFFF) {
            apu.dmc_current_address = 0x8000;
        } else {
            apu.dmc_current_address += 1;
        }

        // Check if sample complete
        if (apu.dmc_bytes_remaining == 0) {
            // Sample finished
            if (apu.dmc_loop_flag) {
                // Loop: restart sample
                restartSample(apu);
            } else {
                // No loop: generate IRQ if enabled
                if (apu.dmc_irq_enabled) {
                    apu.dmc_irq_flag = true;
                }
            }
        }
    }
}

/// Restart DMC sample playback (used for looping)
fn restartSample(apu: *ApuState) void {
    // Reload address and length from registers
    apu.dmc_current_address = 0xC000 | (@as(u16, apu.dmc_sample_address) << 6);
    apu.dmc_bytes_remaining = (@as(u16, apu.dmc_sample_length) << 4) | 1;
}

/// Start DMC sample playback (called when $4015 bit 4 written)
pub fn startSample(apu: *ApuState) void {
    // If bytes_remaining is 0, reload from registers
    if (apu.dmc_bytes_remaining == 0) {
        restartSample(apu);
    }
}

/// Stop DMC sample playback (called when $4015 bit 4 cleared)
pub fn stopSample(apu: *ApuState) void {
    apu.dmc_bytes_remaining = 0;
}

/// Write to $4010 (DMC flags and rate)
pub fn write4010(apu: *ApuState, value: u8) void {
    // Bit 7: IRQ enable
    apu.dmc_irq_enabled = (value & 0x80) != 0;

    // Bit 6: Loop flag
    apu.dmc_loop_flag = (value & 0x40) != 0;

    // Bits 0-3: Rate index
    const rate_index = value & 0x0F;
    apu.dmc_timer_period = RATE_TABLE_NTSC[rate_index];

    // If IRQ disabled, clear IRQ flag
    if (!apu.dmc_irq_enabled) {
        apu.dmc_irq_flag = false;
    }
}

/// Write to $4011 (DMC direct load)
pub fn write4011(apu: *ApuState, value: u8) void {
    // Bits 0-6: Direct load output level
    apu.dmc_output = @intCast(value & 0x7F);
}

/// Write to $4012 (DMC sample address)
pub fn write4012(apu: *ApuState, value: u8) void {
    apu.dmc_sample_address = value;
}

/// Write to $4013 (DMC sample length)
pub fn write4013(apu: *ApuState, value: u8) void {
    apu.dmc_sample_length = value;
}
