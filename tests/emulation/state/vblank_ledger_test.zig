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

    // The PPU tick that sets the flag has run, now the CPU can read it.
    try testing.expect(isVBlankSet(&h));
    try testing.expectEqual(@as(u64, 82182), h.state.vblank_ledger.last_set_cycle);
}

test "VBlankLedger: First read sees flag, subsequent read during same VBlank still sees flag (race hold)" {
    var h = try Harness.init();
    defer h.deinit();
    h.seekTo(241, 1); // VBlank is set

    // First read should see the flag
    try testing.expect(isVBlankSet(&h));
    const read_cycle = h.state.clock.ppu_cycles;

    // Verify that EmulationState recorded the read
    try testing.expectEqual(read_cycle, h.state.vblank_ledger.last_read_cycle);

    // Race semantics: subsequent read during same VBlank should still see flag
    h.tick(1);
    try testing.expect(isVBlankSet(&h));
}

test "VBlankLedger: Flag is cleared at scanline 261, dot 1" {
    var h = try Harness.init();
    defer h.deinit();

    // VBlank is set (avoid destructive read until after ledger observation)
    h.seekTo(241, 1);
    // First read should see the flag
    try testing.expect(isVBlankSet(&h));

    // Seek to just before VBlank clear without prior $2002 reads
    h.seekTo(261, 0);
    try testing.expect(isVBlankSet(&h)); // Still set at 261,0

    // Tick to the exact clear cycle
    h.tick(1);
    try testing.expect(h.state.clock.scanline() == 261 and h.state.clock.dot() == 1);

    // The flag is now cleared by timing
    try testing.expect(!isVBlankSet(&h));
    try testing.expectEqual(@as(u64, 89002), h.state.vblank_ledger.last_clear_cycle);
}

test "VBlankLedger: Race condition - read on same cycle as set" {
    var h = try Harness.init();
    defer h.deinit();

    // Seek to the cycle where VBlank is set
    h.seekTo(241, 1);

    // On this exact cycle, the PPU sets the flag, and the CPU reads it.
    // The read should see the flag as SET.
    try testing.expect(isVBlankSet(&h));

    // Hardware: Race read does NOT clear the flag; subsequent reads still see it set
    h.tick(1);
    try testing.expect(isVBlankSet(&h));
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
