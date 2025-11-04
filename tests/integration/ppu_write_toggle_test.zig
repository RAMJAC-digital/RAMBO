//! PPU Write Toggle (w register) Tests
//!
//! Tests for PPU internal write toggle behavior across frame boundaries.
//! The write toggle is shared between PPUSCROLL and PPUADDR writes.
//!
//! BUG FIX TEST: Write toggle must be cleared at scanline -1 dot 1 (pre-render scanline)
//! Previous bug: Write toggle persisted across frames, causing scroll corruption
//! Hardware: Toggle cleared at end of VBlank along with sprite flags

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Harness = RAMBO.TestHarness.Harness;

test "PPU Write Toggle: Cleared at scanline -1 dot 1" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Set write toggle to 1 by writing to PPUSCROLL once
    harness.state.ppu.internal.w = false; // Start at 0
    _ = RAMBO.Ppu.Logic.readRegister(&harness.state.ppu, null, 0x2005, harness.state.vblank_ledger, harness.state.ppu.scanline, harness.state.ppu.cycle); // Dummy read
    RAMBO.Ppu.Logic.writeRegister(&harness.state.ppu, null, 0x2005, 0x10); // First write (w: 0→1)

    // Verify toggle is now 1
    try testing.expect(harness.state.ppu.internal.w);

    // Advance to scanline -1 dot 0 (just before clear)
    while (harness.state.ppu.scanline < -1 or harness.state.ppu.cycle < 1) {
        harness.state.tick();
    }

    // At this exact moment (scanline -1 dot 1), write toggle should be cleared
    // Verify toggle was reset to 0
    try testing.expect(!harness.state.ppu.internal.w);
}

test "PPU Write Toggle: PPUSCROLL consistency across frames" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Frame 1: Write to PPUSCROLL twice (complete sequence)
    RAMBO.Ppu.Logic.writeRegister(&harness.state.ppu, null, 0x2005, 0x10); // X scroll (w: 0→1)
    RAMBO.Ppu.Logic.writeRegister(&harness.state.ppu, null, 0x2005, 0x20); // Y scroll (w: 1→0)

    // Verify toggle is back to 0 after complete sequence
    try testing.expect(!harness.state.ppu.internal.w);

    // Advance to next frame (scanline 0 of frame 2)
    while (harness.state.ppu.scanline != 0 or harness.state.ppu.cycle < 1) {
        harness.state.tick();
        if (harness.state.ppu.scanline > 260) break; // Wrapped to frame 2
    }

    // Frame 2: Write to PPUSCROLL again
    // If toggle was NOT cleared at scanline -1, this write would be interpreted incorrectly
    const w_before = harness.state.ppu.internal.w;
    try testing.expect(!w_before); // Toggle should start at 0 in new frame

    RAMBO.Ppu.Logic.writeRegister(&harness.state.ppu, null, 0x2005, 0x30); // Should be X scroll

    // Verify toggle advanced to 1 (correct interpretation as first write)
    try testing.expect(harness.state.ppu.internal.w);
}

test "PPU Write Toggle: Cleared on $2002 read" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Set toggle to 1
    RAMBO.Ppu.Logic.writeRegister(&harness.state.ppu, null, 0x2005, 0x10);
    try testing.expect(harness.state.ppu.internal.w);

    // Read $2002 (PPUSTATUS) - should clear toggle
    _ = RAMBO.Ppu.Logic.readRegister(&harness.state.ppu, null, 0x2002, harness.state.vblank_ledger, harness.state.ppu.scanline, harness.state.ppu.cycle);

    // Verify toggle was cleared
    try testing.expect(!harness.state.ppu.internal.w);
}

test "PPU Write Toggle: PPUADDR sequence across frame boundary" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Frame 1: Incomplete PPUADDR write (only first byte)
    RAMBO.Ppu.Logic.writeRegister(&harness.state.ppu, null, 0x2006, 0x20); // High byte (w: 0→1)
    try testing.expect(harness.state.ppu.internal.w); // Toggle at 1

    // Advance to next frame
    while (harness.state.ppu.scanline != 0 or harness.state.ppu.cycle < 1) {
        harness.state.tick();
        if (harness.state.ppu.scanline > 261) break;
    }

    // Frame 2: Toggle should be cleared, so next write is interpreted as high byte again
    try testing.expect(!harness.state.ppu.internal.w); // Cleared at frame boundary

    RAMBO.Ppu.Logic.writeRegister(&harness.state.ppu, null, 0x2006, 0x21); // Should be high byte (not low)
    try testing.expect(harness.state.ppu.internal.w); // Advances to 1

    RAMBO.Ppu.Logic.writeRegister(&harness.state.ppu, null, 0x2006, 0x00); // Low byte
    try testing.expect(!harness.state.ppu.internal.w); // Back to 0

    // VRAM address should be $2100 (not $2000 from incomplete Frame 1 write)
    // The incomplete write from Frame 1 should be ignored
    const expected_addr: u16 = 0x2100;
    try testing.expectEqual(expected_addr, harness.state.ppu.internal.v & 0x3FFF);
}

test "PPU Write Toggle: Mixed PPUSCROLL and PPUADDR across frames" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Frame 1: Write to PPUSCROLL (w: 0→1)
    RAMBO.Ppu.Logic.writeRegister(&harness.state.ppu, null, 0x2005, 0x10);
    try testing.expect(harness.state.ppu.internal.w);

    // Advance to next frame
    while (harness.state.ppu.scanline != 0 or harness.state.ppu.cycle < 1) {
        harness.state.tick();
        if (harness.state.ppu.scanline > 261) break;
    }

    // Frame 2: Toggle should be cleared
    try testing.expect(!harness.state.ppu.internal.w);

    // Write to PPUADDR (different register, same toggle)
    RAMBO.Ppu.Logic.writeRegister(&harness.state.ppu, null, 0x2006, 0x20); // High byte
    try testing.expect(harness.state.ppu.internal.w); // Should be 1

    RAMBO.Ppu.Logic.writeRegister(&harness.state.ppu, null, 0x2006, 0x00); // Low byte
    try testing.expect(!harness.state.ppu.internal.w); // Back to 0

    // Verify PPUADDR write was correctly interpreted (not corrupted by previous PPUSCROLL)
    const expected_addr: u16 = 0x2000;
    try testing.expectEqual(expected_addr, harness.state.ppu.internal.v & 0x3FFF);
}

test "PPU Write Toggle: Not affected by rendering state" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Enable rendering
    harness.state.ppu.mask.show_bg = true;
    harness.state.ppu.mask.show_sprites = true;

    // Set toggle to 1
    RAMBO.Ppu.Logic.writeRegister(&harness.state.ppu, null, 0x2005, 0x10);
    try testing.expect(harness.state.ppu.internal.w);

    // PHASE-INDEPENDENT: Advance to scanline -1 (pre-render) dot 1
    // Toggle is cleared at scanline -1, dot 1 (start of pre-render)
    harness.seekTo(-1, 1);

    // Toggle should be cleared (hardware behavior at pre-render scanline)
    try testing.expect(!harness.state.ppu.internal.w);

    // Disable rendering and verify toggle still cleared correctly
    harness.state.ppu.mask.show_bg = false;
    harness.state.ppu.mask.show_sprites = false;

    // Set toggle again
    RAMBO.Ppu.Logic.writeRegister(&harness.state.ppu, null, 0x2005, 0x10);
    try testing.expect(harness.state.ppu.internal.w);

    // Advance to next frame's pre-render scanline where toggle is cleared
    // First advance to visible region (scanline 0) to ensure we wrap to next frame
    harness.seekTo(0, 0);
    // Then advance to the pre-render scanline -1, dot 1 where toggle is cleared
    harness.seekTo(-1, 1);
    // seekTo positions AT the target but doesn't execute that cycle
    // Advance one more cycle to actually execute the toggle reset
    harness.state.tick();

    // Should still be cleared (rendering disabled doesn't affect toggle clear)
    try testing.expect(!harness.state.ppu.internal.w);
}
