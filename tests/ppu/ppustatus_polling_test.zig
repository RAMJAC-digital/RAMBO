//! PPUSTATUS Polling Tests
//!
//! Verifies that the VBlank flag can be reliably detected by tight CPU polling loops,
//! and that reads from $2002 have the correct side effects.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

// Helper to read the VBlank flag from the $2002 PPUSTATUS register
fn isVBlankSet(h: *Harness) bool {
    const status_byte = h.state.busRead(0x2002);
    return (status_byte & 0x80) != 0;
}

test "PPUSTATUS Polling: Reading $2002 clears VBlank immediately" {
    var h = try Harness.init();
    defer h.deinit();

    // Go to a time when VBlank is active
    h.seekTo(245, 100);
    try testing.expect(isVBlankSet(&h)); // Should be set

    // The read above should have cleared the flag for subsequent reads.
    try testing.expect(!isVBlankSet(&h));
}

test "PPUSTATUS Polling: Tight loop can detect VBlank" {
    var h = try Harness.init();
    defer h.deinit();

    // Load BIT $2002 instruction once at start
    h.loadRam(&[_]u8{ 0x2C, 0x02, 0x20 }, 0x0000);

    // Start just before VBlank
    h.seekToCpuBoundary(240, 0);

    var vblank_detected = false;
    var poll_count: usize = 0;
    const max_polls = 3000; // More than enough to get through the VBlank period

    while (poll_count < max_polls) : (poll_count += 1) {
        // Execute BIT $2002 (4 CPU cycles)
        h.setupCpuExecution(0x0000);
        h.tickCpu(4);

        if (h.state.cpu.p.negative) { // BIT sets N flag if bit 7 is set
            vblank_detected = true;
            break;
        }
    }

    try testing.expect(vblank_detected);
}

test "PPUSTATUS Polling: Race condition at exact VBlank set point" {
    var h = try Harness.init();
    defer h.deinit();

    // Position at the exact cycle VBlank sets
    h.seekTo(241, 1);

    // A read on this exact cycle should see the flag as set
    try testing.expect(isVBlankSet(&h));

    // Hardware behavior: Reading $2002 clears the flag, even on race reads
    // Subsequent reads should see the flag as cleared
    try testing.expect(!isVBlankSet(&h));
}
