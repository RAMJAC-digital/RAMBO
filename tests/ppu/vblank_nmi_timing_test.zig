//! VBlank NMI Timing Tests

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

// Helper to read the VBlank flag from the $2002 PPUSTATUS register
fn isVBlankSet(h: *Harness) bool {
    const status_byte = h.state.busRead(0x2002);
    return (status_byte & 0x80) != 0;
}

test "VBlank NMI: Flag NOT set at scanline 241 dot 0" {
    var h = try Harness.init();
    defer h.deinit();

    h.seekTo(241, 0);
    try testing.expect(!isVBlankSet(&h));
}

test "VBlank NMI: Flag set at scanline 241 dot 1" {
    var h = try Harness.init();
    defer h.deinit();

    h.seekTo(241, 1);
    try testing.expect(isVBlankSet(&h));
}

test "VBlank NMI: NMI fires when vblank && nmi_enable both true" {
    var h = try Harness.init();
    defer h.deinit();

    // Enable NMI
    h.state.busWrite(0x2000, 0x80);

    // Seek to just before VBlank
    h.seekTo(241, 0);
    try testing.expect(!h.state.cpu.nmi_line);

    // Tick to VBlank
    h.tick(1);

    // NMI line should now be asserted
    try testing.expect(h.state.cpu.nmi_line);
}

test "VBlank NMI: Reading $2002 at 241.1 does not clear flag (race hold) and NMI fires" {
    var h = try Harness.init();
    defer h.deinit();

    h.state.busWrite(0x2000, 0x80); // Enable NMI

    // Go to the exact cycle of the race condition
    h.seekTo(241, 1);

    // At this point, NMI line is asserted
    try testing.expect(h.state.cpu.nmi_line);

    // Reading $2002 should see the flag and not clear it for the next read (race hold)
    try testing.expect(isVBlankSet(&h));
    try testing.expect(isVBlankSet(&h));

    // The NMI line should remain asserted until the CPU services it
    try testing.expect(h.state.cpu.nmi_line);
}
