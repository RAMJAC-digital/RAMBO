//! Clock Synchronization Test
//! Verifies that PPU state matches clock position after tick()

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;

test "Clock Sync: PPU processes current position, not next" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.reset();
    state.ppu.warmup_complete = true;

    // Advance to just before VBlank (scanline 241, dot 0)
    while (state.clock.scanline() < 241) {
        state.tick();
    }

    // Now at scanline 241, dot 0
    try testing.expectEqual(@as(u16, 241), state.clock.scanline());
    try testing.expectEqual(@as(u16, 0), state.clock.dot());

    // VBlank should NOT be set yet
    try testing.expect(!state.ppu.status.vblank);

    // Tick once - this should process dot 0, advance to dot 1
    state.tick();

    // Clock should now show 241, dot 1
    try testing.expectEqual(@as(u16, 241), state.clock.scanline());
    try testing.expectEqual(@as(u16, 1), state.clock.dot());

    // But PPU just processed dot 0, so VBlank still NOT set
    try testing.expect(!state.ppu.status.vblank);

    // Tick again - this processes dot 1, advances to dot 2
    state.tick();

    // Clock now at 241, dot 2
    try testing.expectEqual(@as(u16, 241), state.clock.scanline());
    try testing.expectEqual(@as(u16, 2), state.clock.dot());

    // NOW VBlank should be set (PPU processed dot 1)
    try testing.expect(state.ppu.status.vblank);
}

test "Clock Sync: VBlank sets when PPU processes 241.1" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.reset();
    state.ppu.warmup_complete = true;

    // Track when VBlank actually sets
    var vblank_set_at_clock_sl: ?u16 = null;
    var vblank_set_at_clock_dot: ?u16 = null;

    // Advance through VBlank start
    while (state.clock.scanline() < 242) {
        const before_vblank = state.ppu.status.vblank;

        state.tick();

        const after_vblank = state.ppu.status.vblank;

        // Capture the clock position when VBlank transitions false->true
        if (!before_vblank and after_vblank and vblank_set_at_clock_sl == null) {
            vblank_set_at_clock_sl = state.clock.scanline();
            vblank_set_at_clock_dot = state.clock.dot();
            break;
        }
    }

    // VBlank should have set when clock showed 241.2
    // (because PPU processed 241.1 during that tick)
    try testing.expectEqual(@as(u16, 241), vblank_set_at_clock_sl.?);
    try testing.expectEqual(@as(u16, 2), vblank_set_at_clock_dot.?);
}