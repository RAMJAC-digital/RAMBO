//! VBlankLedger Integration Tests
//!
//! Tests the VBlank mechanism via the top-level EmulationState, ensuring
//! the entire refactored system works correctly.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

// Helper to read the VBlank flag from the $2002 PPUSTATUS register
fn isVBlankSet(h: *Harness) bool {
    const status_byte = h.state.busRead(0x2002);
    return (status_byte & 0x80) != 0;
}

test "VBlankLedger: Read before VBlank is clear" {
    var h = try Harness.init();
    defer h.deinit();
    try testing.expect(!isVBlankSet(&h));
}

test "VBlankLedger: Flag is set at scanline 241, dot 1" {
    var h = try Harness.init();
    defer h.deinit();

    // Seek to just before VBlank set
    h.seekTo(241, 0);
    try testing.expect(!isVBlankSet(&h));

    // Tick to the exact cycle
    h.tick(1);
    try testing.expect(h.state.clock.scanline() == 241 and h.state.clock.dot() == 1);

    // CORRECTED: Reading at the same cycle as VBlank set sees flag CLEAR (hardware sub-cycle timing)
    // The PPU has set the flag, but CPU read executes before the flag update in the same cycle
    // Reference: AccuracyCoin VBlank Beginning test (hardware-validated)
    try testing.expect(!isVBlankSet(&h));  // CORRECTED: Same-cycle read sees CLEAR
    try testing.expectEqual(@as(u64, 82182), h.state.vblank_ledger.last_set_cycle);

    // One cycle later, the flag should be readable
    h.tick(1);
    try testing.expect(isVBlankSet(&h));  // NOW sees SET
}

test "VBlankLedger: First read clears flag, subsequent read sees cleared" {
    var h = try Harness.init();
    defer h.deinit();
    h.seekTo(241, 1); // VBlank is set

    // CORRECTED: First read at same-cycle as VBlank set sees flag CLEAR (hardware sub-cycle timing)
    try testing.expect(!isVBlankSet(&h));  // CORRECTED: Same-cycle read sees CLEAR

    // CORRECTED: Same-cycle reads do NOT update last_read_cycle because the flag wasn't
    // actually visible when the read happened (CPU read before PPU set)
    try testing.expectEqual(@as(u64, 0), h.state.vblank_ledger.last_read_cycle);

    // Tick forward and read again - flag should now be visible and then get cleared by the read
    h.tick(1);
    try testing.expect(isVBlankSet(&h));  // One cycle after set - flag visible

    // Third read should see flag cleared (cleared by previous read)
    h.tick(1);
    try testing.expect(!isVBlankSet(&h));  // Flag cleared by previous read
}

test "VBlankLedger: Flag is cleared at scanline 261, dot 1" {
    var h = try Harness.init();
    defer h.deinit();

    // VBlank is set at scanline 241, dot 1
    h.seekTo(241, 1);

    // Seek to just before VBlank clear without performing a $2002 read
    // (so we can test timing-based clearing, not read-based clearing)
    h.seekTo(261, 0);

    // At 261,0, VBlank should still be active (hasn't cleared by timing yet)
    try testing.expect(h.state.vblank_ledger.isActive());

    // Tick to the exact clear cycle
    h.tick(1);
    try testing.expect(h.state.clock.scanline() == 261 and h.state.clock.dot() == 1);

    // The flag is now cleared by timing
    try testing.expect(!h.state.vblank_ledger.isActive());
    try testing.expectEqual(@as(u64, 89002), h.state.vblank_ledger.last_clear_cycle);
}

test "VBlankLedger: Race condition - read on same cycle as set" {
    var h = try Harness.init();
    defer h.deinit();

    // Seek to the cycle where VBlank is set
    h.seekTo(241, 1);

    // CORRECTED: Hardware sub-cycle timing - CPU read executes BEFORE PPU flag set
    // Reading at the exact same cycle as VBlank set sees flag CLEAR (not set yet)
    // Reference: AccuracyCoin VBlank Beginning test (hardware-validated)
    // The previous nesdev.org interpretation was incorrect - "same clock" meant same
    // FRAME, not same cycle. Same-cycle reads see the OLD state.
    try testing.expect(!isVBlankSet(&h));  // CORRECTED: Same-cycle read sees CLEAR

    // NMI suppression still occurs even though flag wasn't visible
    try testing.expectEqual(h.state.vblank_ledger.last_set_cycle, h.state.vblank_ledger.last_race_cycle);

    // One cycle later, flag should be visible
    h.tick(1);
    try testing.expect(isVBlankSet(&h));  // Now flag is visible
}

test "VBlankLedger: SMB polling pattern" {
    var h = try Harness.init();
    defer h.deinit();

    // Seek to VBlank
    h.seekTo(241, 10);

    // 1. First poll reads the flag, it should be set.
    try testing.expect(isVBlankSet(&h));

    // 2. Second poll, a few cycles later. Should be clear because of the first read.
    h.tick(5);
    try testing.expect(!isVBlankSet(&h));

    // 3. Third poll, a few more cycles later. Should still be clear.
    h.tick(5);
    try testing.expect(!isVBlankSet(&h));
}

test "VBlankLedger: Reset clears all cycle counters" {
    var h = try Harness.init();
    defer h.deinit();
    h.seekTo(241, 10);
    _ = isVBlankSet(&h); // Perform a read to populate the ledger

    try testing.expect(h.state.vblank_ledger.last_set_cycle > 0);
    try testing.expect(h.state.vblank_ledger.last_read_cycle > 0);

    h.state.reset();

    try testing.expectEqual(@as(u64, 0), h.state.vblank_ledger.last_set_cycle);
    try testing.expectEqual(@as(u64, 0), h.state.vblank_ledger.last_clear_cycle);
    try testing.expectEqual(@as(u64, 0), h.state.vblank_ledger.last_read_cycle);
}
