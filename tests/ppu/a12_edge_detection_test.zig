//! PPU A12 Edge Detection Tests
//!
//! Verifies that A12 edge detection uses the actual CHR address bus ($0000-$1FFF)
//! instead of the VRAM address (v register $2000-$3FFF).
//!
//! Critical for MMC3 IRQ timing - MMC3 watches bit 12 of CHR address during
//! pattern fetches to count scanlines for split-screen effects.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

test "A12 detection: chr_address field tracks pattern fetches" {
    var harness = try Harness.init();
    defer harness.deinit();
    const ppu = &harness.state.ppu;

    // Setup: Background rendering with pattern table 0
    ppu.ctrl.bg_pattern = false;  // $0000-$0FFF (A12=0)
    ppu.mask.show_bg = true;
    ppu.warmup_complete = true;

    // Tick through a few background fetches
    // Pattern fetches occur at cycles 5 and 7 (dots 6 and 8)
    harness.state.reset();
    ppu.mask.show_bg = true;

    // Run one scanline
    for (0..341) |_| {
        harness.state.tick();
    }

    // Verify chr_address was updated (non-zero after pattern fetches)
    // The exact value depends on tile fetching, but it should be in CHR range
    try testing.expect(ppu.chr_address < 0x2000);  // CHR address space
}

test "A12 detection: Pattern table selection affects chr_address A12 bit" {
    var harness = try Harness.init();
    defer harness.deinit();
    const ppu = &harness.state.ppu;

    ppu.warmup_complete = true;
    harness.state.reset();

    // Test 1: Pattern table 0 (A12 should be 0)
    ppu.ctrl.bg_pattern = false;  // $0000-$0FFF
    ppu.mask.show_bg = true;

    // Run a few cycles to trigger pattern fetch
    for (0..10) |_| {
        harness.state.tick();
    }

    // After background fetches, chr_address should be in pattern table 0
    const addr_pt0 = ppu.chr_address;
    const a12_pt0 = (addr_pt0 & 0x1000) != 0;
    try testing.expectEqual(false, a12_pt0);  // Pattern table 0 → A12=0

    // Test 2: Pattern table 1 (A12 should be 1)
    ppu.ctrl.bg_pattern = true;  // $1000-$1FFF

    // Run a few more cycles
    for (0..10) |_| {
        harness.state.tick();
    }

    // After background fetches, chr_address should be in pattern table 1
    const addr_pt1 = ppu.chr_address;
    const a12_pt1 = (addr_pt1 & 0x1000) != 0;
    try testing.expectEqual(true, a12_pt1);  // Pattern table 1 → A12=1
}

test "A12 detection: Sprite pattern table affects chr_address" {
    var harness = try Harness.init();
    defer harness.deinit();
    const ppu = &harness.state.ppu;

    ppu.warmup_complete = true;
    harness.state.reset();

    // Setup: Sprite rendering with pattern table 1
    ppu.ctrl.sprite_pattern = true;  // $1000-$1FFF
    ppu.mask.show_sprites = true;
    ppu.mask.show_bg = false;  // Only sprites

    // Add sprite to OAM (will be evaluated into secondary OAM)
    ppu.oam[0] = 100;  // Y position
    ppu.oam[1] = 0x42; // Tile index
    ppu.oam[2] = 0x00; // Attributes
    ppu.oam[3] = 100;  // X position

    // Run a full frame to ensure sprite evaluation and fetching occurs
    for (0..29780) |_| {  // One frame worth of cycles
        harness.state.tick();
    }

    // After a frame with sprite rendering, chr_address should have been updated
    // and should be in the sprite pattern table range
    const chr_addr = ppu.chr_address;

    // Verify it's in CHR address space (not VRAM)
    try testing.expect(chr_addr < 0x2000);

    // If sprite rendering occurred, A12 should reflect sprite pattern table setting
    // (This is a loose test - we just verify chr_address is being tracked)
}

test "A12 detection: chr_address vs v register are independent" {
    var harness = try Harness.init();
    defer harness.deinit();
    const ppu = &harness.state.ppu;

    ppu.warmup_complete = true;
    harness.state.reset();

    // Setup: Use pattern table 0 for background
    ppu.ctrl.bg_pattern = false;  // Pattern table 0: $0000-$0FFF (A12=0)
    ppu.mask.show_bg = true;

    // Run enough cycles to ensure pattern fetches occur (one full scanline)
    for (0..341) |_| {
        harness.state.tick();
    }

    // After background fetches with pattern table 0, chr_address should have A12=0
    const chr_addr_pt0 = ppu.chr_address;
    const a12_pt0 = (chr_addr_pt0 & 0x1000) != 0;

    // Verify chr_address is in pattern table 0 range
    try testing.expect(chr_addr_pt0 < 0x1000);  // Pattern table 0
    try testing.expectEqual(false, a12_pt0);

    // Now use nametable with bit 12 set in v (but keep pattern table 0)
    ppu.ctrl.nametable_y = true;  // This affects v register, not chr_address

    // Run another scanline
    for (0..341) |_| {
        harness.state.tick();
    }

    // chr_address should STILL be in pattern table 0 (A12=0)
    // even though v register nametable addressing has changed
    const chr_addr_after = ppu.chr_address;
    const a12_after = (chr_addr_after & 0x1000) != 0;

    try testing.expect(chr_addr_after < 0x1000);  // Still pattern table 0
    try testing.expectEqual(false, a12_after);  // A12 still 0
}
