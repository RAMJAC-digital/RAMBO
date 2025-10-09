//! Track VBlank flag through every tick

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;

test "VBlank Tracking: Watch flag through 241.0 to 241.10" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.reset();
    state.ppu.warmup_complete = true;

    // Advance to scanline 241, dot 0
    while (state.clock.scanline() < 241) {
        state.tick();
    }

    // Track VBlank state at each dot
    var vblank_states: [20]bool = undefined;
    var dots: [20]u16 = undefined;

    var i: usize = 0;
    while (i < 20) : (i += 1) {
        dots[i] = state.clock.dot();
        vblank_states[i] = state.ppu.status.vblank;
        state.tick();
    }

    // VBlank should be:
    // - false at dot 0
    // - true at dots 1 and beyond
    try testing.expect(!vblank_states[0]); // Dot 0: not set
    try testing.expect(vblank_states[1]);  // Dot 1: SET!
    try testing.expect(vblank_states[2]);  // Dot 2: still set
    try testing.expect(vblank_states[3]);  // Dot 3: still set
}