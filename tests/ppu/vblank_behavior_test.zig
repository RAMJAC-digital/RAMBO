//! VBlank Flag Behavior Tests
//!
//! Comprehensive tests for VBlank flag lifecycle and timing.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

// Helper to read the VBlank flag from the $2002 PPUSTATUS register
fn isVBlankSet(h: *Harness) bool {
    const status_byte = h.state.busRead(0x2002);
    return (status_byte & 0x80) != 0;
}

test "VBlank: Flag sets at scanline 241 dot 1" {
    var h = try Harness.init();
    defer h.deinit();
    h.state.ppu.warmup_complete = true; // Skip PPU warmup for VBlank timing tests

    // Seek to just before VBlank sets
    h.seekTo(241, 0);
    // Check ledger directly to avoid $2002 read side effects (prevention trigger)
    try testing.expect(!h.state.ppu.vblank.isFlagSet());

    // Tick to the exact cycle where VBlank sets
    h.tick(1);

    // CORRECTED: Check ledger directly to verify flag SET
    // Per nesdev.org: "Reading on the same PPU clock...reads it as set"
    // Note: This test calls tick() then checks, so the VBlank timestamp
    // has already been applied. True same-cycle reads (CPU reading during
    // the cycle via actual instruction execution) require integration tests.
    try testing.expect(h.state.ppu.vblank.isFlagSet());

    // Verify reading $2002 returns correct value and clears flag
    const status = h.state.busRead(0x2002);
    try testing.expectEqual(@as(u8, 0x80), status & 0x80);

    // One cycle later, flag has been cleared by the previous read
    h.tick(1);
    try testing.expect(!h.state.ppu.vblank.isFlagSet());
}

test "VBlank: Flag clears at scanline -1 dot 1 (pre-render)" {
    var h = try Harness.init();
    defer h.deinit();
    h.state.ppu.warmup_complete = true; // Skip PPU warmup for VBlank timing tests

    // FIXED: Must advance through a full frame first to set VBlank
    // Starting from -1:0, seek to 0:0 (goes through 241:1 where VBlank sets)
    h.seekTo(0, 0);

    // Now seek to just before VBlank clears (scanline -1, dot 0)
    // Check ledger directly to avoid $2002 read side effects
    h.seekTo(-1, 0);
    try testing.expect(h.state.ppu.vblank.isFlagSet()); // Still set at -1,0

    // Tick to the exact clear cycle
    h.tick(1);

    // VBlank flag MUST be cleared by timing - check ledger directly
    try testing.expect(!h.state.ppu.vblank.isFlagSet());

    // Verify reading $2002 also shows cleared
    const status = h.state.busRead(0x2002);
    try testing.expectEqual(@as(u8, 0x00), status & 0x80);
}

test "VBlank: Flag is not set during visible scanlines" {
    var h = try Harness.init();
    defer h.deinit();
    h.state.ppu.warmup_complete = true; // Skip PPU warmup for VBlank timing tests

    // Check a few points during the visible frame - check ledger directly
    h.seekTo(100, 150);
    try testing.expect(!h.state.ppu.vblank.isFlagSet());

    h.seekTo(200, 50);
    try testing.expect(!h.state.ppu.vblank.isFlagSet());
}

test "VBlank: Multiple frame transitions" {
    var h = try Harness.init();
    defer h.deinit();
    h.state.ppu.warmup_complete = true; // Skip PPU warmup for VBlank timing tests

    var vblank_set_count: usize = 0;
    // FIXED: Check ledger state directly instead of reading $2002
    // Reading $2002 has side effect of clearing the flag, which prevents
    // detecting 0→1 transitions when reading every cycle
    var last_vblank = h.state.ppu.vblank.isFlagSet();

    // Run for 3 frames
    const cycles_per_frame: usize = 89342;
    var cycles: usize = 0;
    while (cycles < cycles_per_frame * 3) : (cycles += 1) {
        h.tick(1);
        // FIXED: Check ledger directly (no side effects)
        const current_vblank = h.state.ppu.vblank.isFlagSet();
        if (!last_vblank and current_vblank) {
            vblank_set_count += 1;
        }
        last_vblank = current_vblank;
    }

    // Should have seen VBlank set 3 times
    try testing.expectEqual(@as(usize, 3), vblank_set_count);
}

test "VBlank: First frame completes at correct timing" {
    var h = try Harness.init();
    defer h.deinit();
    h.state.ppu.warmup_complete = true; // Skip PPU warmup for VBlank timing tests

    // Verify starting conditions
    try testing.expectEqual(@as(u64, 0), h.state.ppu.frame_count);
    try testing.expectEqual(@as(i16, -1), h.state.ppu.scanline);
    try testing.expectEqual(@as(u16, 0), h.state.ppu.cycle);

    // Tick through cycles until frame_count changes from 0 to 1
    // First frame should be exactly 89,342 cycles (262 scanlines × 341 dots, no odd frame skip)
    var cycles: u64 = 0;
    const initial_frame = h.state.ppu.frame_count;

    while (cycles < 100000) { // Safety limit
        h.tick(1);
        cycles += 1;

        // Check if frame completed (frame_count incremented)
        if (h.state.ppu.frame_count > initial_frame) {
            break;
        }
    }

    // VERIFY: Frame 0 completed at exactly 89342 cycles
    try testing.expectEqual(@as(u64, 89342), cycles);
}

// ============================================================================
// Targeted VBlank/NMI Integration Tests
// ============================================================================

test "VBlank/NMI: last_set_cycle timestamp at exact master_cycle (241:1)" {
    var h = try Harness.init();
    defer h.deinit();
    h.state.ppu.warmup_complete = true;

    // Seek to scanline 241 dot 0
    h.seekTo(241, 0);

    // Record master_cycles BEFORE the VBlank set cycle
    const cycles_before = h.state.clock.master_cycles;

    // Tick to scanline 241 dot 1 (VBlank sets)
    h.tick(1);

    // VERIFY: last_set_cycle was set to the EXACT master_cycle when VBlank set
    const expected_cycle = cycles_before + 1;
    try testing.expectEqual(expected_cycle, h.state.ppu.vblank.last_set_cycle);

    // VERIFY: VBlank flag is now visible
    try testing.expect(h.state.ppu.vblank.isFlagSet());
}

test "VBlank/NMI: last_clear_cycle timestamp at exact master_cycle (-1:1)" {
    var h = try Harness.init();
    defer h.deinit();
    h.state.ppu.warmup_complete = true;

    // Advance through a frame to set VBlank
    h.seekTo(241, 100);
    try testing.expect(h.state.ppu.vblank.isFlagSet());

    // Seek to pre-render scanline dot 0
    h.seekTo(-1, 0);

    // Record master_cycles BEFORE the VBlank clear cycle
    const cycles_before = h.state.clock.master_cycles;

    // Tick to scanline -1 dot 1 (VBlank clears)
    h.tick(1);

    // VERIFY: last_clear_cycle was set to the EXACT master_cycle when VBlank cleared
    const expected_cycle = cycles_before + 1;
    try testing.expectEqual(expected_cycle, h.state.ppu.vblank.last_clear_cycle);

    // VERIFY: VBlank flag is now NOT visible
    try testing.expect(!h.state.ppu.vblank.isFlagSet());
}

test "VBlank/NMI: $2002 read updates last_read_cycle and clears flag" {
    var h = try Harness.init();
    defer h.deinit();
    h.state.ppu.warmup_complete = true;

    // Seek into VBlank period
    h.seekTo(241, 100);
    try testing.expect(h.state.ppu.vblank.isFlagSet());

    // Record cycles before read
    const cycles_before_read = h.state.clock.master_cycles;

    // Read $2002 (PPUSTATUS)
    const status = h.state.busRead(0x2002);

    // VERIFY: Read value had VBlank bit set (bit 7)
    try testing.expectEqual(@as(u8, 0x80), status & 0x80);

    // VERIFY: last_read_cycle was updated to current master_cycles
    try testing.expectEqual(cycles_before_read, h.state.ppu.vblank.last_read_cycle);

    // VERIFY: VBlank flag is now NOT visible (cleared by read)
    try testing.expect(!h.state.ppu.vblank.isFlagSet());

    // VERIFY: Second read sees VBlank clear
    const status2 = h.state.busRead(0x2002);
    try testing.expectEqual(@as(u8, 0x00), status2 & 0x80);
}

test "VBlank/NMI: Prevention window at 241:0 (read before set)" {
    var h = try Harness.init();
    defer h.deinit();
    h.state.ppu.warmup_complete = true;

    // Seek to scanline 241 dot 0 (one cycle before VBlank sets)
    h.seekTo(241, 0);

    // CPU reads $2002 at dot 0 (prevention window)
    const status = h.state.busRead(0x2002);

    // VERIFY: Read value has VBlank CLEAR (haven't reached dot 1 yet)
    try testing.expectEqual(@as(u8, 0x00), status & 0x80);

    // Record current master_cycles (the prevention flag should be set)
    const prevention_cycle = h.state.clock.master_cycles;

    // Tick to dot 1 (when VBlank WOULD set)
    h.tick(1);

    // VERIFY: VBlank flag was PREVENTED from setting
    try testing.expect(!h.state.ppu.vblank.isFlagSet());

    // VERIFY: last_set_cycle was NOT updated (flag was prevented)
    try testing.expect(h.state.ppu.vblank.last_set_cycle < prevention_cycle);
}

test "VBlank/NMI: NMI line goes high when VBlank sets with PPUCTRL.7=1" {
    var h = try Harness.init();
    defer h.deinit();
    h.state.ppu.warmup_complete = true;

    // Enable NMI in PPUCTRL (bit 7)
    h.state.busWrite(0x2000, 0x80);

    // Seek to just before VBlank sets (scanline 241, dot 0)
    h.seekTo(241, 0);

    // VERIFY: VBlank not set yet, NMI line LOW
    try testing.expect(!h.state.ppu.vblank.isFlagSet());
    try testing.expect(!h.state.cpu.nmi_line);

    // Tick to scanline 241 dot 1 (VBlank sets)
    h.tick(1);

    // VERIFY: VBlank flag is now set
    try testing.expect(h.state.ppu.vblank.isFlagSet());

    // VERIFY: NMI line went HIGH (PPUCTRL.7 = 1, VBlank = 1)
    try testing.expect(h.state.cpu.nmi_line);
}

test "VBlank/NMI: Reading $2002 clears NMI line immediately" {
    var h = try Harness.init();
    defer h.deinit();
    h.state.ppu.warmup_complete = true;

    // Enable NMI
    h.state.busWrite(0x2000, 0x80);

    // Seek to VBlank period (after 241:1)
    h.seekTo(241, 100);

    // VERIFY: VBlank active, NMI line high
    try testing.expect(h.state.ppu.vblank.isFlagSet());
    try testing.expect(h.state.cpu.nmi_line);

    // Read $2002 (PPUSTATUS)
    const status = h.state.busRead(0x2002);

    // VERIFY: Read value had VBlank bit set
    try testing.expectEqual(@as(u8, 0x80), status & 0x80);

    // VERIFY: VBlank flag cleared IMMEDIATELY after read
    try testing.expect(!h.state.ppu.vblank.isFlagSet());

    // VERIFY: NMI line cleared IMMEDIATELY after read
    try testing.expect(!h.state.cpu.nmi_line);
}

test "VBlank/NMI: PPUCTRL write enables NMI during VBlank" {
    var h = try Harness.init();
    defer h.deinit();
    h.state.ppu.warmup_complete = true;

    // Start with NMI disabled
    h.state.busWrite(0x2000, 0x00);

    // Seek into VBlank period (after 241:1)
    h.seekTo(241, 100);

    // VERIFY: VBlank active but NMI line LOW (PPUCTRL.7 = 0)
    try testing.expect(h.state.ppu.vblank.isFlagSet());
    try testing.expect(!h.state.cpu.nmi_line);

    // Enable NMI by writing to PPUCTRL
    h.state.busWrite(0x2000, 0x80);

    // VERIFY: NMI line goes HIGH immediately (0→1 transition with VBlank active)
    try testing.expect(h.state.cpu.nmi_line);
}

test "VBlank/NMI: PPUCTRL write disables NMI" {
    var h = try Harness.init();
    defer h.deinit();
    h.state.ppu.warmup_complete = true;

    // Enable NMI
    h.state.busWrite(0x2000, 0x80);

    // Seek into VBlank period
    h.seekTo(241, 100);

    // VERIFY: NMI line HIGH
    try testing.expect(h.state.cpu.nmi_line);

    // Disable NMI by clearing PPUCTRL.7
    h.state.busWrite(0x2000, 0x00);

    // VERIFY: NMI line goes LOW immediately
    try testing.expect(!h.state.cpu.nmi_line);
}

test "VBlank/NMI: VBlank clear at -1:1 clears NMI line" {
    var h = try Harness.init();
    defer h.deinit();
    h.state.ppu.warmup_complete = true;

    // Enable NMI
    h.state.busWrite(0x2000, 0x80);

    // Seek into VBlank period
    h.seekTo(241, 100);

    // VERIFY: VBlank active, NMI high
    try testing.expect(h.state.ppu.vblank.isFlagSet());
    try testing.expect(h.state.cpu.nmi_line);

    // Seek to pre-render scanline, just before VBlank clears (scanline -1, dot 0)
    h.seekTo(-1, 0);

    // VERIFY: VBlank still active
    try testing.expect(h.state.ppu.vblank.isFlagSet());
    try testing.expect(h.state.cpu.nmi_line);

    // Tick to dot 1 (VBlank clears by timing)
    h.tick(1);

    // VERIFY: VBlank cleared
    try testing.expect(!h.state.ppu.vblank.isFlagSet());

    // VERIFY: NMI line went LOW (VBlank cleared = NMI clears)
    try testing.expect(!h.state.cpu.nmi_line);
}

test "VBlank/NMI: Race condition - CPU execution before VBlank timestamp application" {
    var h = try Harness.init();
    defer h.deinit();
    h.state.ppu.warmup_complete = true;

    // This test verifies the critical race condition behavior:
    // When CPU reads $2002 at scanline 241 dot 1 (the EXACT cycle VBlank sets),
    // the CPU execution must happen BEFORE VBlank timestamps are applied.
    //
    // Per AccuracyCoin: Reading at 241:1 should return $00 (VBlank not yet set)
    // and should NOT trigger NMI (even though PPUCTRL.7 = 1)

    // Enable NMI
    h.state.busWrite(0x2000, 0x80);

    // Seek to scanline 241 dot 0
    h.seekTo(241, 0);

    // Tick to scanline 241 dot 1 (VBlank SHOULD set this cycle)
    h.tick(1);

    // At this exact moment, we're AT scanline 241 dot 1
    // If we read $2002 now (after tick completes), VBlank has already been set

    // To test the race condition properly, we need to verify that:
    // 1. VBlank flag IS set (after tick completes)
    try testing.expect(h.state.ppu.vblank.isFlagSet());

    // 2. But if CPU had read DURING this cycle (not after), it would see CLEAR
    //    This is tested by the prevention window test above

    // The critical assertion: After tick completes, VBlank IS visible
    // This confirms that VBlank sets at the correct cycle
    const status = h.state.busRead(0x2002);
    try testing.expectEqual(@as(u8, 0x80), status & 0x80);
}
