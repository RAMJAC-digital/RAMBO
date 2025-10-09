//! Simulate Bomberman's exact VBlank wait loop
//!
//! The game hangs at $C00D with this loop:
//!   BIT $2002  ; Test PPUSTATUS
//!   BPL $C00D  ; Loop if bit 7 clear
//!
//! This test simulates that exact behavior to understand why it hangs.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;

test "Bomberman Simulation: VBlank wait loop behavior" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.reset();
    state.ppu.warmup_complete = true;

    // Start before VBlank
    while (state.clock.scanline() < 240) {
        state.tick();
    }

    // Simulate the BIT $2002 / BPL loop
    var iterations: usize = 0;
    var vblank_detected = false;
    const max_iterations = 1000; // Should only take a few iterations

    while (iterations < max_iterations and !vblank_detected) {
        // BIT $2002 instruction (4 CPU cycles = 12 PPU cycles)
        // This reads PPUSTATUS and sets N flag based on bit 7

        // Simulate the 4 CPU cycles of BIT $2002
        // Cycle 1: Fetch opcode
        state.tick(); // PPU cycle
        if (state.clock.isCpuTick()) {
            // CPU would fetch opcode here
        }

        // Cycle 2: Fetch address low
        state.tick();
        if (state.clock.isCpuTick()) {
            // CPU would fetch low byte
        }

        // Cycle 3: Fetch address high
        state.tick();
        if (state.clock.isCpuTick()) {
            // CPU would fetch high byte
        }

        // Cycle 4: Read from $2002
        var ppustatus_value: u8 = 0;
        state.tick();
        if (state.clock.isCpuTick()) {
            ppustatus_value = state.busRead(0x2002);
        }

        state.tick();
        state.tick();
        state.tick();
        state.tick();
        state.tick();
        state.tick();
        state.tick();
        state.tick(); // Total 12 PPU cycles for BIT instruction

        // Check if bit 7 was set
        if ((ppustatus_value & 0x80) != 0) {
            vblank_detected = true;
            break;
        }

        // BPL instruction (2-3 CPU cycles = 6-9 PPU cycles)
        // If bit 7 was clear, branch is taken
        state.tick();
        state.tick();
        state.tick();
        state.tick();
        state.tick();
        state.tick(); // 6 PPU cycles for BPL when taken

        iterations += 1;

        // Safety check - are we in VBlank period?
        if (state.clock.scanline() >= 241 and state.clock.scanline() <= 260) {
            // We're in VBlank but haven't detected it yet
            if (iterations > 10) {
                // This is the bug! We should have detected VBlank by now
                try testing.expectEqual(@as(bool, true), vblank_detected);
                return;
            }
        }
    }

    // Must have detected VBlank
    try testing.expect(vblank_detected);
    try testing.expect(iterations < max_iterations);
}