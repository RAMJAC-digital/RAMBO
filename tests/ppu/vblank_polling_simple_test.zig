//! Simple VBlank Polling Test
//! Minimal test to understand VBlank behavior

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;

test "VBlank Simple: Can detect VBlank by polling" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.reset();
    state.ppu.warmup_complete = true;

    // Start well before VBlank
    var detected = false;
    var polls: usize = 0;

    // Poll for up to 2 frames worth of cycles
    const max_cycles: usize = 89342 * 2;
    var cycles: usize = 0;

    while (cycles < max_cycles and !detected) {
        // Check if we're near VBlank time
        const sl = state.clock.scanline();

        // Only poll when we're in the VBlank region (scanlines 240-261)
        if (sl >= 240 and sl <= 261) {
            const status = state.busRead(0x2002);
            polls += 1;

            if ((status & 0x80) != 0) {
                detected = true;
                break;
            }
        }

        state.tick();
        cycles += 1;
    }

    // We MUST have detected VBlank
    try testing.expect(detected);
    try testing.expect(polls > 0);
    try testing.expect(cycles < max_cycles);
}

test "VBlank Simple: Direct flag check" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.reset();
    state.ppu.warmup_complete = true;

    // Advance to just before VBlank
    while (state.clock.scanline() < 241 or state.clock.dot() < 1) {
        state.tick();
    }

    // Should be at 241.1 now
    try testing.expectEqual(@as(u16, 241), state.clock.scanline());
    try testing.expectEqual(@as(u16, 1), state.clock.dot());

    // VBlank flag should be set
    try testing.expect(state.ppu.status.vblank);

    // Reading $2002 should return bit 7 set
    const status = state.busRead(0x2002);
    try testing.expect((status & 0x80) != 0);

    // But now flag should be cleared
    try testing.expect(!state.ppu.status.vblank);
}