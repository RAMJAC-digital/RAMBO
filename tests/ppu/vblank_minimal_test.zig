//! Minimal test to isolate VBlank issue

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;

test "VBlank Minimal: Set and check immediately" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.reset();

    // Directly set VBlank
    state.ppu.status.vblank = true;

    // It should still be set
    try testing.expect(state.ppu.status.vblank);

    // Tick once
    state.tick();

    // Should STILL be set (unless we're at scanline 261.1)
    const sl = state.clock.scanline();
    if (sl != 261) {
        try testing.expect(state.ppu.status.vblank);
    }
}

test "VBlank Minimal: Track through one frame" {
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

    // Not set yet
    try testing.expect(!state.ppu.status.vblank);

    // Tick once (to 241.1)
    state.tick();

    // NOW it should be set
    const sl = state.clock.scanline();
    const dot = state.clock.dot();

    if (sl == 241 and dot == 1) {
        // We're at the exact VBlank set point
        // After the tick that processes 241.1, VBlank MUST be set
        try testing.expect(state.ppu.status.vblank);
    }
}

test "VBlank Minimal: busRead($2002) returns bit 7 when VBlank set" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.reset();
    state.ppu.warmup_complete = true;

    // Manually set clock to 241.0
    state.clock.ppu_cycles = 241 * 341;
    try testing.expect(!state.ppu.status.vblank);

    // Tick to 241.1 - VBlank should set
    state.tick();

    try testing.expectEqual(@as(u16, 241), state.clock.scanline());
    try testing.expectEqual(@as(u16, 1), state.clock.dot());
    try testing.expect(state.ppu.status.vblank);

    // Read $2002 via busRead
    const status_value = state.busRead(0x2002);

    // Bit 7 MUST be 1 (VBlank was set)
    try testing.expect((status_value & 0x80) != 0);

    // VBlank flag should now be cleared
    try testing.expect(!state.ppu.status.vblank);
}

test "VBlank Minimal: Polling loop starting at 240.340" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.reset();
    state.ppu.warmup_complete = true;

    // Start at 240.340 (just before VBlank period)
    state.clock.ppu_cycles = 240 * 341 + 340;

    var detections: usize = 0;
    var iterations: usize = 0;

    // Poll up to 100 times
    while (iterations < 100 and state.clock.scanline() < 262) : (iterations += 1) {
        const status_value = state.busRead(0x2002);

        if ((status_value & 0x80) != 0) {
            detections += 1;
        }

        // Advance 12 PPU cycles (4 CPU cycles)
        var i: usize = 0;
        while (i < 12) : (i += 1) {
            state.tick();
        }
    }

    // MUST have detected VBlank at least once
    try testing.expect(detections > 0);
}