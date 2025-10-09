//! Test to understand seekToScanlineDot behavior

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;

test "Seek Behavior: What state after seekToScanlineDot(241,1)?" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.reset();
    state.ppu.warmup_complete = true;

    // Manually advance to scanline 241, dot 0
    while (state.clock.scanline() < 241) {
        state.tick();
    }

    // Clock should be at 241, dot 0
    try testing.expectEqual(@as(u16, 241), state.clock.scanline());
    try testing.expectEqual(@as(u16, 0), state.clock.dot());

    // VBlank should NOT be set (we're at dot 0, VBlank sets at dot 1)
    try testing.expect(!state.ppu.status.vblank);

    // Now tick ONCE
    state.tick();

    // Clock should advance to 241, dot 1
    try testing.expectEqual(@as(u16, 241), state.clock.scanline());
    try testing.expectEqual(@as(u16, 1), state.clock.dot());

    // Has VBlank been set?
    // If PPU processes AFTER advance: YES (PPU processed dot 1)
    // If PPU processes BEFORE advance: NO (PPU processed dot 0)
    const vblank_after_one_tick = state.ppu.status.vblank;

    // Show the result
    try testing.expectEqual(true, vblank_after_one_tick);
}