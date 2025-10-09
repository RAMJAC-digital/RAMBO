//! VBlank Flag Behavior Tests
//!
//! Comprehensive tests for VBlank flag lifecycle and timing.
//! Consolidates: vblank_minimal, vblank_tracking, vblank_persistence, vblank_polling_simple
//!
//! Coverage:
//! - VBlank flag set timing (241.1)
//! - VBlank flag clear timing (261.1)
//! - Flag persistence across scanlines
//! - Multi-frame VBlank transitions
//! - No VBlank during visible scanlines

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Harness = RAMBO.TestHarness.Harness;

test "VBlank: Flag sets at scanline 241 dot 1" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;

    // Seek to scanline 241, dot 0 (just before VBlank sets)
    harness.seekToScanlineDot(241, 0);

    // VBlank flag MUST NOT be set yet
    try testing.expect(!harness.state.ppu.status.vblank);

    // Tick once to advance to 241.1
    harness.state.tick();

    // NOW at scanline 241, dot 1
    try testing.expectEqual(@as(u16, 241), harness.getScanline());
    try testing.expectEqual(@as(u16, 1), harness.getDot());

    // VBlank flag MUST be set
    try testing.expect(harness.state.ppu.status.vblank);
}

test "VBlank: Flag sets with dot-level precision at 241.1" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;

    // Seek to scanline 241, dot 0
    harness.seekToScanlineDot(241, 0);

    // Track VBlank state at each dot from 0 to 10
    var vblank_states: [11]bool = undefined;
    var dots: [11]u16 = undefined;

    var i: usize = 0;
    while (i < 11) : (i += 1) {
        dots[i] = harness.getDot();
        vblank_states[i] = harness.state.ppu.status.vblank;
        harness.state.tick();
    }

    // VBlank should be:
    // - false at dot 0
    // - true at dots 1 through 10
    try testing.expect(!vblank_states[0]); // Dot 0: not set
    try testing.expect(vblank_states[1]); // Dot 1: SET!
    try testing.expect(vblank_states[2]); // Dot 2: still set
    try testing.expect(vblank_states[3]); // Dot 3: still set
    try testing.expect(vblank_states[10]); // Dot 10: still set
}

test "VBlank: Flag clears at scanline 261 dot 1" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;

    // Seek to scanline 245 (middle of VBlank period)
    harness.seekToScanlineDot(245, 150);

    // VBlank flag MUST be set
    try testing.expect(harness.state.ppu.status.vblank);

    // Seek to scanline 261, dot 0 (just before VBlank clears)
    harness.seekToScanlineDot(261, 0);

    // VBlank flag should STILL be set
    try testing.expect(harness.state.ppu.status.vblank);

    // Tick once to advance to 261.1
    harness.state.tick();

    // NOW at scanline 261, dot 1
    try testing.expectEqual(@as(u16, 261), harness.getScanline());
    try testing.expectEqual(@as(u16, 1), harness.getDot());

    // VBlank flag MUST be cleared
    try testing.expect(!harness.state.ppu.status.vblank);
}

test "VBlank: Flag persists across scanlines without reads" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;

    // Seek to scanline 241, dot 1 (VBlank just set)
    harness.seekToScanlineDot(241, 1);

    // VBlank flag MUST be set
    try testing.expect(harness.state.ppu.status.vblank);

    // Tick through multiple scanlines WITHOUT reading $2002
    // VBlank should STAY set
    var scanlines_checked: usize = 0;
    while (harness.getScanline() < 260) {
        harness.state.tick();

        // Every scanline, verify VBlank is still set
        if (harness.getDot() == 0) {
            try testing.expect(harness.state.ppu.status.vblank);
            scanlines_checked += 1;
        }
    }

    // Should have checked many scanlines (241-259 = ~18 scanlines)
    try testing.expect(scanlines_checked > 15);

    // Advance to 261.1 (where VBlank clears)
    harness.seekToScanlineDot(261, 1);

    // VBlank flag MUST be cleared
    try testing.expect(!harness.state.ppu.status.vblank);
}

test "VBlank: Multiple frame transitions" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;

    // Track VBlank transitions over 2 frames
    var vblank_set_count: usize = 0;
    var vblank_clear_count: usize = 0;
    var last_vblank = false;

    // Run for 2 frames (89342 PPU cycles per frame)
    const cycles_per_frame: usize = 89342;
    var cycles: usize = 0;
    while (cycles < cycles_per_frame * 2) : (cycles += 1) {
        harness.state.tick();

        const current_vblank = harness.state.ppu.status.vblank;

        // Track transitions
        if (!last_vblank and current_vblank) {
            vblank_set_count += 1;
        }
        if (last_vblank and !current_vblank) {
            vblank_clear_count += 1;
        }

        last_vblank = current_vblank;
    }

    // Should have seen VBlank set and clear twice (once per frame)
    try testing.expect(vblank_set_count >= 2);
    try testing.expect(vblank_clear_count >= 2);
}

test "VBlank: Flag not set during visible scanlines" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;

    // Seek to middle of visible scanline region
    harness.seekToScanlineDot(100, 150);

    // VBlank flag MUST NOT be set
    try testing.expect(!harness.state.ppu.status.vblank);

    // Read $2002
    const status = harness.state.busRead(0x2002);

    // Bit 7 MUST be clear (no VBlank during rendering)
    try testing.expectEqual(@as(u8, 0x00), status & 0x80);

    // Try another visible scanline
    harness.seekToScanlineDot(200, 50);

    // Still no VBlank
    try testing.expect(!harness.state.ppu.status.vblank);
}

test "VBlank: Flag not set at scanline 0 (after clear)" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;

    // Seek to scanline 0 (start of new frame, after VBlank clear)
    harness.seekToScanlineDot(0, 100);

    // VBlank flag MUST NOT be set
    try testing.expect(!harness.state.ppu.status.vblank);

    // Read $2002
    const status = harness.state.busRead(0x2002);

    // Bit 7 MUST be clear
    try testing.expectEqual(@as(u8, 0x00), status & 0x80);
}
