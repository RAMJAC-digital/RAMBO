//! Exact trace of VBlank behavior with Bomberman's polling pattern

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;

test "VBlank Exact Trace: What happens at 241.1?" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.reset();
    state.ppu.warmup_complete = true;

    // Advance to exactly scanline 241, dot 0
    while (state.clock.scanline() != 241 or state.clock.dot() != 0) {
        state.tick();
    }

    // Verify position
    try testing.expectEqual(@as(u16, 241), state.clock.scanline());
    try testing.expectEqual(@as(u16, 0), state.clock.dot());

    // VBlank should NOT be set yet
    const before_tick = state.ppu.status.vblank;
    try testing.expect(!before_tick);

    // Tick once (advances to 241.1)
    state.tick();

    // Now at 241.1 - VBlank should be SET
    try testing.expectEqual(@as(u16, 241), state.clock.scanline());
    try testing.expectEqual(@as(u16, 1), state.clock.dot());

    const after_tick = state.ppu.status.vblank;

    // This is the critical check - IS VBLANK SET?
    if (!after_tick) {
        // VBlank is NOT set - this is the bug!
        // Force failure to show state
        try testing.expectEqual(@as(bool, true), after_tick);
    }

    // If VBlank is set, test polling
    if (after_tick) {
        // Simulate reading $2002
        const status = state.busRead(0x2002);

        // Should read with bit 7 set
        try testing.expectEqual(@as(u8, 0x80), status & 0x80);

        // But now VBlank should be cleared
        try testing.expect(!state.ppu.status.vblank);
    }
}

test "VBlank Exact Trace: Multiple ticks around VBlank" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.reset();
    state.ppu.warmup_complete = true;

    // Advance to scanline 240, dot 340 (just before 241)
    while (state.clock.scanline() != 240 or state.clock.dot() != 340) {
        state.tick();
    }

    // Track VBlank state for next 20 ticks
    var vblank_history: [20]bool = undefined;
    var scanline_history: [20]u16 = undefined;
    var dot_history: [20]u16 = undefined;

    var i: usize = 0;
    while (i < 20) : (i += 1) {
        state.tick();
        vblank_history[i] = state.ppu.status.vblank;
        scanline_history[i] = state.clock.scanline();
        dot_history[i] = state.clock.dot();
    }

    // Find when VBlank sets
    var vblank_set_index: ?usize = null;
    for (vblank_history, 0..) |vblank, idx| {
        if (vblank and vblank_set_index == null) {
            vblank_set_index = idx;
            break;
        }
    }

    if (vblank_set_index) |idx| {
        // VBlank was set - check when
        const set_scanline = scanline_history[idx];
        const set_dot = dot_history[idx];

        // Should be at 241.1
        try testing.expectEqual(@as(u16, 241), set_scanline);
        try testing.expectEqual(@as(u16, 1), set_dot);

        // Should stay set for subsequent ticks
        if (idx + 1 < 20) {
            try testing.expect(vblank_history[idx + 1]);
        }
        if (idx + 2 < 20) {
            try testing.expect(vblank_history[idx + 2]);
        }
    } else {
        // VBlank never set - THIS IS THE BUG
        try testing.expect(false); // Force failure
    }
}