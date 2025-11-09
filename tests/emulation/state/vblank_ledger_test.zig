//! VBlank Integration Tests
//!
//! Tests the VBlank mechanism via the top-level EmulationState, ensuring
//! PPU-owned VBlank state works correctly.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

fn isFlagVisible(h: *Harness) bool {
    return h.state.ppu.vblank.isFlagSet();
}

fn readVBlankBit(h: *Harness) bool {
    const status_byte = h.state.busRead(0x2002);
    return (status_byte & 0x80) != 0;
}

test "VBlank: Read before VBlank is clear" {
    var h = try Harness.init();
    defer h.deinit();
    try testing.expect(!isFlagVisible(&h));
}

test "VBlankLedger: Flag is set at scanline 241, dot 1" {
    var h = try Harness.init();
    defer h.deinit();

    // Seek to just before VBlank set
    h.seekTo(241, 0);
    try testing.expect(!isFlagVisible(&h));

    // Advance past the race window to dot 4 (race window is dots 0-2)
    // VBlank is set at dot 1, but hardware masks bit 7 for dots < 3
    h.seekTo(241, 4);

    // Now we're past the race window, flag should be visible
    try testing.expect(isFlagVisible(&h));

    // Verify VBlank was set (last_set_cycle should be non-zero)
    try testing.expect(h.state.ppu.vblank.last_set_cycle > 0);

    // Subsequent read clears the flag
    try testing.expect(readVBlankBit(&h));  // First read sees set (and clears it)
    try testing.expect(!readVBlankBit(&h)); // Second read sees CLEAR
}

test "VBlankLedger: First read clears flag, subsequent read sees cleared" {
    var h = try Harness.init();
    defer h.deinit();

    // Seek past the race window (VBlank set at dot 1, race window is dots 0-2)
    h.seekTo(241, 4);

    // Flag should be visible (we're past the race window)
    try testing.expect(isFlagVisible(&h));

    // Reading the visible flag clears it and updates last_read_cycle
    try testing.expect(readVBlankBit(&h));
    try testing.expect(h.state.ppu.vblank.last_read_cycle > 0);

    // Second read should see flag cleared (cleared by first read)
    try testing.expect(!readVBlankBit(&h));  // Second read sees CLEAR

    // Tick forward - flag stays cleared (no new VBlank set)
    h.tick(1);
    try testing.expect(!isFlagVisible(&h));  // Still cleared
}

test "VBlankLedger: Flag is cleared at scanline -1, dot 1 (pre-render)" {
    var h = try Harness.init();
    defer h.deinit();

    // VBlank is set at scanline 241, dot 1
    h.seekTo(241, 1);

    // Seek to just before VBlank clear without performing a $2002 read
    // (so we can test timing-based clearing, not read-based clearing)
    h.seekTo(-1, 0);

    // At -1,0, VBlank should still be active (hasn't cleared by timing yet)
    try testing.expect(h.state.ppu.vblank.isFlagSet());

    // Tick to the exact clear cycle
    h.tick(1);
    try testing.expect(h.state.ppu.scanline == -1 and h.state.ppu.dot == 1);

    // The flag is now cleared by timing
    try testing.expect(!h.state.ppu.vblank.isFlagSet());

    // Verify VBlank was cleared (last_clear_cycle should be non-zero)
    try testing.expect(h.state.ppu.vblank.last_clear_cycle > 0);
}

test "VBlankLedger: Race condition - read on same cycle as set" {
    var h = try Harness.init();
    defer h.deinit();

    // PHASE-INDEPENDENT: Position before VBlank, then advance to first CPU tick during race window
    h.seekTo(240, 340); // Position at end of scanline 240
    h.seekToCpuBoundary(241, 0); // Advance to first CPU tick of scanline 241 (race window: dots 0-2)

    // Per nesdev.org/wiki/PPU_frame_timing and BUG #1 fix:
    // Reading $2002 ALWAYS updates last_read_cycle (Mesen2 UpdateStatusFlag() unconditional)
    //
    // Hardware behavior during race window (scanline 241, dots 0-2):
    // - Dot 0: Reading PREVENTS flag from being set (returns 0, flag never sets)
    // - Dot 1-2: Reading SEES flag as set (returns 1), then clears it
    //
    // After BUG #1 fix: NMI suppression happens automatically because:
    // 1. $2002 read updates last_read_cycle to current cycle
    // 2. isFlagVisible() returns false when last_read_cycle >= last_set_cycle
    // 3. NMI line computation uses isFlagVisible() - no separate race tracking needed
    const first_read = readVBlankBit(&h);
    _ = first_read; // Phase-dependent (may be 0 or 1)

    // Verify last_read_cycle was updated (BUG #1 fix - unconditional update)
    try testing.expect(h.state.ppu.vblank.last_read_cycle > 0);

    // Second read should ALWAYS see flag as cleared (by last_read_cycle timestamp)
    try testing.expect(!readVBlankBit(&h));
}

test "VBlankLedger: SMB polling pattern" {
    var h = try Harness.init();
    defer h.deinit();

    // Seek to VBlank
    h.seekTo(241, 10);

    // 1. First poll reads the flag, it should be set.
    try testing.expect(readVBlankBit(&h));

    // 2. Second poll, a few cycles later. Should be clear because of the first read.
    h.tick(5);
    try testing.expect(!readVBlankBit(&h));

    // 3. Third poll, a few more cycles later. Should still be clear.
    h.tick(5);
    try testing.expect(!readVBlankBit(&h));
}

test "VBlankLedger: Reset clears all cycle counters" {
    var h = try Harness.init();
    defer h.deinit();
    h.seekTo(241, 10);
    _ = readVBlankBit(&h); // Perform a read to populate the ledger

    try testing.expect(h.state.ppu.vblank.last_set_cycle > 0);
    try testing.expect(h.state.ppu.vblank.last_read_cycle > 0);

    h.state.reset();

    try testing.expectEqual(@as(u64, 0), h.state.ppu.vblank.last_set_cycle);
    try testing.expectEqual(@as(u64, 0), h.state.ppu.vblank.last_clear_cycle);
    try testing.expectEqual(@as(u64, 0), h.state.ppu.vblank.last_read_cycle);
}
