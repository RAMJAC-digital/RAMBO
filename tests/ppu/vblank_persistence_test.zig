//! Test VBlank flag persistence

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;

test "VBlank Persistence: Flag stays set for 20 scanlines" {
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

    // Should be at 241.1, VBlank should be set
    try testing.expectEqual(@as(u16, 241), state.clock.scanline());
    try testing.expectEqual(@as(u16, 1), state.clock.dot());
    try testing.expect(state.ppu.status.vblank);

    // Tick through multiple scanlines WITHOUT reading $2002
    // VBlank should STAY set
    var scanlines_checked: usize = 0;
    while (state.clock.scanline() < 260) {
        state.tick();

        // Every scanline, verify VBlank is still set
        if (state.clock.dot() == 0) {
            try testing.expect(state.ppu.status.vblank);
            scanlines_checked += 1;
        }
    }

    // Should have checked many scanlines
    try testing.expect(scanlines_checked > 15);

    // Advance to 261.0 (just before clear)
    while (state.clock.scanline() < 261 or state.clock.dot() < 1) {
        state.tick();
    }

    // At 261.1, VBlank should be cleared
    try testing.expectEqual(@as(u16, 261), state.clock.scanline());
    try testing.expectEqual(@as(u16, 1), state.clock.dot());
    try testing.expect(!state.ppu.status.vblank);
}

test "VBlank Persistence: Direct check without harness" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.reset();
    state.ppu.warmup_complete = true;

    // Track VBlank transitions
    var vblank_set_count: usize = 0;
    var vblank_clear_count: usize = 0;
    var last_vblank = false;

    // Run for 2 frames
    const cycles_per_frame = 89342;
    var cycles: usize = 0;
    while (cycles < cycles_per_frame * 2) : (cycles += 1) {
        state.tick();

        const current_vblank = state.ppu.status.vblank;

        // Track transitions
        if (!last_vblank and current_vblank) {
            vblank_set_count += 1;
        }
        if (last_vblank and !current_vblank) {
            vblank_clear_count += 1;
        }

        last_vblank = current_vblank;
    }

    // Should have seen VBlank set and clear once per frame
    try testing.expect(vblank_set_count >= 1);
    try testing.expect(vblank_clear_count >= 1);
}