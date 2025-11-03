//! Emulation Helper Functions - Convenience Wrappers for Testing and High-Level Control
//!
//! This module provides high-level emulation control functions that wrap the core tick() loop.
//! These are primarily used in:
//! - Test harnesses (frame/cycle-based testing)
//! - Benchmarking (controlled execution)
//! - External integrations (simplified API)
//!
//! All functions are built on top of EmulationState.tick() and maintain cycle-accurate timing.

const std = @import("std");

/// Advances master clock by 3 PPU cycles (1 CPU cycle) then ticks CPU
/// Use this in CPU-only tests instead of calling tickCpu() directly
///
/// Parameters:
///   - state: Mutable pointer to emulation state
pub fn tickCpuWithClock(state: anytype) void {
    // 1 CPU cycle = 3 PPU cycles = 3 master cycles
    // Master clock advances monotonically (1 per tick)
    // PPU clock advances via PpuLogic.advanceClock() (handles odd frame skip)
    state.clock.advance(); // master +1
    state.clock.advance(); // master +1
    state.clock.advance(); // master +1
    // Total: master +3 (1 CPU cycle)
    state.tickCpu();
}

/// Emulate a complete frame (convenience wrapper)
/// Advances emulation until frame_complete flag is set
///
/// Timing:
/// - NTSC: ~89,342 PPU cycles per frame
/// - PAL: ~106,392 PPU cycles per frame
///
/// Safety:
/// - Includes max cycle check to prevent infinite loops (110,000 PPU cycles)
/// - Respects debugger halt requests
///
/// Parameters:
///   - state: Mutable pointer to emulation state
///
/// Returns: Number of PPU cycles elapsed during frame
pub fn emulateFrame(state: anytype) u64 {
    // Track elapsed master cycles (monotonic counter)
    const start_cycle = state.clock.master_cycles;
    state.frame_complete = false;

    if (state.debuggerShouldHalt()) {
        return 0;
    }

    // Advance until VBlank (scanline 241, dot 1)
    // NTSC: 89,342 PPU cycles per frame
    // PAL: 106,392 PPU cycles per frame
    while (!state.frame_complete) {
        state.tick();
        if (state.debuggerShouldHalt()) {
            break;
        }

        // Safety: Prevent infinite loop if something goes wrong
        // Maximum frame cycles + 1000 cycle buffer
        // This check is RT-safe: unreachable is optimized out in ReleaseFast
        const max_cycles: u64 = 110_000;
        const current_cycles = state.clock.master_cycles;
        const elapsed = if (current_cycles >= start_cycle)
            current_cycles - start_cycle
        else
            0;
        if (elapsed > max_cycles) {
            if (comptime std.debug.runtime_safety) {
                unreachable; // Debug mode only, no allocation
            }
            break; // Release mode: exit gracefully
        }
    }

    // Return elapsed cycles with underflow protection
    // This can underflow in rare cases with threading tests or state manipulation
    return if (state.clock.master_cycles >= start_cycle)
        state.clock.master_cycles - start_cycle
    else
        0;
}

/// Emulate N CPU cycles (convenience wrapper)
///
/// Parameters:
///   - state: Mutable pointer to emulation state
///   - cpu_cycles: Number of CPU cycles to execute
///
/// Returns: Actual PPU cycles elapsed (approximately cpu_cycles × 3)
pub fn emulateCpuCycles(state: anytype, cpu_cycles: u64) u64 {
    const start_cycle = state.clock.master_cycles;
    const target_cpu_cycle = state.clock.cpuCycles() + cpu_cycles;

    while (state.clock.cpuCycles() < target_cpu_cycle) {
        state.tick();
    }

    // Return elapsed cycles with underflow protection
    return if (state.clock.master_cycles >= start_cycle)
        state.clock.master_cycles - start_cycle
    else
        0;
}
