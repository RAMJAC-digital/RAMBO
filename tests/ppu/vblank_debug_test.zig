//! VBlank Debug Test - Diagnose why polling fails

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

test "VBlank Debug: What happens when we poll continuously?" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;

    // Start just before VBlank
    harness.seekToScanlineDot(240, 340);

    var first_detection_scanline: ?u16 = null;
    var first_detection_dot: ?u16 = null;
    var total_detections: usize = 0;
    var poll_count: usize = 0;

    // Poll continuously, recording when VBlank is detected
    while (harness.getScanline() <= 261 and harness.getDot() < 100) {
        const scanline_before = harness.getScanline();
        const dot_before = harness.getDot();
        const vblank_flag_before = harness.state.ppu.status.vblank;

        const status = harness.state.busRead(0x2002);
        const vblank_detected = (status & 0x80) != 0;

        const vblank_flag_after = harness.state.ppu.status.vblank;

        if (vblank_detected and first_detection_scanline == null) {
            first_detection_scanline = scanline_before;
            first_detection_dot = dot_before;
        }

        if (vblank_detected) {
            total_detections += 1;
        }

        poll_count += 1;

        // Advance by BIT $2002 instruction time (4 CPU cycles = 12 PPU cycles)
        var i: usize = 0;
        while (i < 12) : (i += 1) {
            harness.state.tick();
        }

        // If we're AT the VBlank set point, show what happens
        if (scanline_before == 241 and dot_before <= 20) {
            // Force test to show diagnostic info for first few reads after VBlank should set
            try testing.expectEqual(@as(u16, 999), scanline_before); // Show scanline
            try testing.expectEqual(@as(u16, 999), dot_before); // Show dot
            try testing.expectEqual(@as(bool, true), vblank_flag_before); // Show flag before read
            try testing.expectEqual(@as(bool, true), vblank_detected); // Show if bit 7 was set
            try testing.expectEqual(@as(bool, false), vblank_flag_after); // Show flag after read (should be false)
            try testing.expectEqual(@as(usize, 999), poll_count);
        }
    }

    // We must have detected VBlank at least once
    if (total_detections == 0) {
        // Show what happened
        try testing.expectEqual(@as(usize, 999), total_detections); // Will show 0
        try testing.expectEqual(@as(usize, 999), poll_count);
        if (first_detection_scanline) |sl| {
            try testing.expectEqual(@as(u16, 999), sl);
        }
    }

    try testing.expect(total_detections >= 1);
}
