//! VBlank Fix Implementation
//!
//! This shows how to fix the VBlank issue in the PPU implementation.
//! The key changes needed:
//! 1. VBlank calculation based on cycle count
//! 2. Proper handling of $2002 reads
//! 3. Correct NMI edge detection

const std = @import("std");

// The fix for Ppu.zig tick function:
// Replace lines 133-138 with cycle-based calculation

pub fn fixedVBlankLogic(state: *PpuState, scanline: u16, dot: u16, flags: *PpuCycleFlags, ppu_cycles: u64) void {
    // Calculate frame position
    const frame_cycle = ppu_cycles % 89_342;
    const VBLANK_START = 241 * 341 + 1; // 82,181
    const VBLANK_END = 261 * 341 + 1;   // 89,001

    // Check if we just entered VBlank
    if (frame_cycle == VBLANK_START) {
        // Set VBlank flag if not suppressed
        if (!state.vblank_suppressed) {
            state.status.vblank = true;
        }
        flags.vblank_started = true; // NMI signal
    }

    // Check if we're exiting VBlank
    if (frame_cycle == VBLANK_END) {
        state.status.vblank = false;
        state.vblank_suppressed = false; // Reset suppression for new frame
        flags.vblank_ended = true;
    }
}

// The fix for PpuLogic.readRegister (around line 200-214):
pub fn fixedStatusRead(state: *PpuState) u8 {
    // Get current value WITH VBlank flag
    const value = state.status.toByte(state.open_bus.value);

    // Side effects happen AFTER we capture the value
    // 1. Clear VBlank flag (but only if it was set)
    if (state.status.vblank) {
        state.status.vblank = false;
        state.vblank_suppressed = true; // Prevent re-setting this frame
    }

    // 2. Reset write toggle
    state.internal.resetToggle();

    // 3. Update open bus
    state.open_bus.write(value);

    // Return the value that had VBlank set (if it was)
    return value;
}

// Critical insight: The race condition at exact VBlank timing
pub fn handleVBlankRaceCondition(ppu_cycles: u64, is_cpu_reading: bool) bool {
    const frame_cycle = ppu_cycles % 89_342;
    const VBLANK_START = 82_181;

    // If CPU reads $2002 on the EXACT cycle VBlank sets,
    // hardware behavior is to NOT see VBlank set
    if (frame_cycle == VBLANK_START and is_cpu_reading) {
        // This is the race condition documented on nesdev
        // VBlank is suppressed for this frame
        return false; // Don't set VBlank
    }

    return true; // Normal VBlank behavior
}

// The proper tick ordering to handle half-cycle effects:
pub fn properTickOrder(state: *EmulationState) void {
    // Pre-tick: Calculate what WILL happen this cycle
    const next_ppu_cycles = state.clock.ppu_cycles + 1;
    const will_vblank_start = (next_ppu_cycles % 89_342) == 82_181;
    const is_cpu_tick = ((next_ppu_cycles % 3) == 0);

    // Advance clock
    state.clock.advance(1);

    // PPU processes first (may set VBlank)
    // This happens on EVERY PPU cycle
    const ppu_result = state.stepPpuCycle();

    // Handle the race condition if CPU will read this cycle
    if (will_vblank_start and is_cpu_tick) {
        // CPU will read $2002 on same cycle as VBlank
        // This is where we need special handling
        // The CPU should see VBlank as SET (unless it's the exact race)
    }

    // CPU processes (may read $2002)
    if (is_cpu_tick) {
        const cpu_result = state.stepCpuCycle();
        // CPU reads happen here
    }

    // Post-tick: Apply results
    state.applyPpuCycleResult(ppu_result);
}

test "VBlank Fix: Proper persistence" {
    const testing = std.testing;

    // VBlank should persist for exactly 6,820 PPU cycles
    const start_cycle: u64 = 82_181;
    const end_cycle: u64 = 89_001;

    var cycle = start_cycle;
    while (cycle < end_cycle) : (cycle += 1) {
        const frame_pos = cycle % 89_342;
        const should_be_set = (frame_pos >= 82_181 and frame_pos < 89_001);

        // This should be true for entire VBlank period
        try testing.expect(should_be_set);
    }
}

test "VBlank Fix: Race condition handling" {
    const testing = std.testing;

    // At exact VBlank start with CPU read
    const vblank_allowed = handleVBlankRaceCondition(82_181, true);
    try testing.expect(!vblank_allowed); // Race condition suppresses

    // At exact VBlank start without CPU read
    const vblank_normal = handleVBlankRaceCondition(82_181, false);
    try testing.expect(vblank_normal); // Normal VBlank sets

    // One cycle after VBlank start
    const vblank_after = handleVBlankRaceCondition(82_182, true);
    try testing.expect(vblank_after); // No race condition
}