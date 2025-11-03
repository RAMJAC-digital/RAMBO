//! PpuState Unit Tests
//!
//! Tests for PpuState initialization and basic functionality.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const PpuState = RAMBO.Ppu.State.PpuState;
const PpuLogic = RAMBO.Ppu.Logic;

test "PpuState: Clock initialized to pre-render state" {
    const ppu = PpuState.init();

    // PPU should start at pre-render scanline (scanline -1, cycle 0, frame 0)
    // Hardware: NES PPU begins at scanline -1 (pre-render) after power-on
    // Mesen2 reference: _scanline = -1, _cycle = 0, _frameCount = 0
    try testing.expectEqual(@as(u16, 0), ppu.cycle);
    try testing.expectEqual(@as(i16, -1), ppu.scanline);
    try testing.expectEqual(@as(u64, 0), ppu.frame_count);
}

test "PPU Clock: Normal advancement (cycle 0→340→0)" {
    var ppu = PpuState.init();

    // Start at cycle 0
    try testing.expectEqual(@as(u16, 0), ppu.cycle);
    try testing.expectEqual(@as(i16, -1), ppu.scanline);

    // Advance through normal cycles (0→340)
    var i: u16 = 0;
    while (i < 340) : (i += 1) {
        PpuLogic.advanceClock(&ppu, false); // rendering_enabled = false
        try testing.expectEqual(i + 1, ppu.cycle);
        try testing.expectEqual(@as(i16, -1), ppu.scanline); // Still on pre-render
    }

    // At cycle 340, still on pre-render scanline
    try testing.expectEqual(@as(u16, 340), ppu.cycle);
    try testing.expectEqual(@as(i16, -1), ppu.scanline);

    // One more advance wraps to cycle 0, scanline 0
    PpuLogic.advanceClock(&ppu, false);
    try testing.expectEqual(@as(u16, 0), ppu.cycle);
    try testing.expectEqual(@as(i16, 0), ppu.scanline);
}

test "PPU Clock: Scanline wrap" {
    var ppu = PpuState.init();
    ppu.cycle = 340;
    ppu.scanline = 100;

    // Advance from cycle 340 should wrap to cycle 0, scanline 101
    PpuLogic.advanceClock(&ppu, false);
    try testing.expectEqual(@as(u16, 0), ppu.cycle);
    try testing.expectEqual(@as(i16, 101), ppu.scanline);
}

test "PPU Clock: Frame wrap" {
    var ppu = PpuState.init();
    ppu.cycle = 340;
    ppu.scanline = 260; // Last scanline of frame before wrap
    ppu.frame_count = 5;

    // Advance from (260, 340) should wrap to (-1, 0), frame 6
    PpuLogic.advanceClock(&ppu, false);
    try testing.expectEqual(@as(u16, 0), ppu.cycle);
    try testing.expectEqual(@as(i16, -1), ppu.scanline);
    try testing.expectEqual(@as(u64, 6), ppu.frame_count);
}

test "PPU Clock: Odd frame skip when rendering enabled" {
    var ppu = PpuState.init();
    ppu.cycle = 338;
    ppu.scanline = -1; // Pre-render scanline
    ppu.frame_count = 1; // Odd frame

    // Advance cycle 338→339, but skip immediately sets it to 340
    // Mesen2: Increments to 339, then if conditions met, immediately sets to 340
    // Hardware: Odd frames with rendering skip cycle 339 (pre-render is 1 cycle shorter)
    PpuLogic.advanceClock(&ppu, true); // rendering_enabled = true
    try testing.expectEqual(@as(u16, 340), ppu.cycle); // Skip happened!
    try testing.expectEqual(@as(i16, -1), ppu.scanline);

    // Next advance wraps to scanline 0 (frame is 1 cycle shorter)
    PpuLogic.advanceClock(&ppu, true);
    try testing.expectEqual(@as(u16, 0), ppu.cycle);
    try testing.expectEqual(@as(i16, 0), ppu.scanline);
}

test "PPU Clock: No skip on even frames" {
    var ppu = PpuState.init();
    ppu.cycle = 338;
    ppu.scanline = -1; // Pre-render scanline
    ppu.frame_count = 2; // Even frame

    // Advance cycle 338→339
    PpuLogic.advanceClock(&ppu, true); // rendering_enabled = true
    try testing.expectEqual(@as(u16, 339), ppu.cycle);

    // Advance cycle 339→340 (NO skip on even frames)
    PpuLogic.advanceClock(&ppu, true);
    try testing.expectEqual(@as(u16, 340), ppu.cycle);
    try testing.expectEqual(@as(i16, -1), ppu.scanline);

    // Verify we're still on pre-render (no premature wrap)
    try testing.expectEqual(@as(i16, -1), ppu.scanline);
}

test "PPU Clock: No skip when rendering disabled" {
    var ppu = PpuState.init();
    ppu.cycle = 338;
    ppu.scanline = -1; // Pre-render scanline
    ppu.frame_count = 1; // Odd frame

    // Advance cycle 338→339
    PpuLogic.advanceClock(&ppu, false); // rendering_enabled = FALSE
    try testing.expectEqual(@as(u16, 339), ppu.cycle);

    // Advance cycle 339→340 (NO skip when rendering disabled)
    PpuLogic.advanceClock(&ppu, false);
    try testing.expectEqual(@as(u16, 340), ppu.cycle);
    try testing.expectEqual(@as(i16, -1), ppu.scanline);
}
