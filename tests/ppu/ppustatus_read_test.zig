//! Test that $2002 reads return correct value

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;
const Harness = RAMBO.TestHarness.Harness;

test "PPUSTATUS Read: Returns VBlank flag correctly" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.reset();
    state.ppu.warmup_complete = true;

    // Set VBlank flag directly
    state.ppu.status.vblank = true;

    // Read $2002
    const status = state.busRead(0x2002);

    // Bit 7 should be set
    try testing.expectEqual(@as(u8, 0x80), status & 0x80);

    // Flag should now be cleared
    try testing.expect(!state.ppu.status.vblank);
}

test "PPUSTATUS Read: Returns correct value when VBlank clear" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.reset();
    state.ppu.warmup_complete = true;

    // Ensure VBlank flag is clear
    state.ppu.status.vblank = false;

    // Read $2002
    const status = state.busRead(0x2002);

    // Bit 7 should be clear
    try testing.expectEqual(@as(u8, 0x00), status & 0x80);

    // Flag should still be clear
    try testing.expect(!state.ppu.status.vblank);
}

test "PPUSTATUS Read: VBlank at scanline 241 dot 1 via seekToScanlineDot" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;

    // Seek to scanline 241, dot 1 - VBlank sets here
    harness.seekToScanlineDot(241, 1);

    // VBlank flag MUST be set
    try testing.expect(harness.state.ppu.status.vblank);

    // Read $2002
    const status = harness.state.busRead(0x2002);

    // Returned value MUST have bit 7 set
    try testing.expectEqual(@as(u8, 0x80), status & 0x80);

    // VBlank flag cleared after read
    try testing.expect(!harness.state.ppu.status.vblank);
}

test "PPUSTATUS Read: VBlank at scanline 245 middle of VBlank" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;

    // Seek to middle of VBlank period
    harness.seekToScanlineDot(245, 150);

    // VBlank flag MUST be set
    try testing.expect(harness.state.ppu.status.vblank);

    // Read $2002
    const status = harness.state.busRead(0x2002);

    // Returned value MUST have bit 7 set
    try testing.expectEqual(@as(u8, 0x80), status & 0x80);
}

test "PPUSTATUS Read: No VBlank at scanline 100" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;

    // Seek to visible scanline
    harness.seekToScanlineDot(100, 100);

    // VBlank flag MUST NOT be set
    try testing.expect(!harness.state.ppu.status.vblank);

    // Read $2002
    const status = harness.state.busRead(0x2002);

    // Returned value MUST have bit 7 clear
    try testing.expectEqual(@as(u8, 0x00), status & 0x80);
}

test "PPUSTATUS Read: VBlank cleared at scanline 261 dot 1" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;

    // Seek to scanline 261, dot 1 - VBlank clears here
    harness.seekToScanlineDot(261, 1);

    // VBlank flag MUST be cleared
    try testing.expect(!harness.state.ppu.status.vblank);

    // Read $2002
    const status = harness.state.busRead(0x2002);

    // Returned value MUST have bit 7 clear
    try testing.expectEqual(@as(u8, 0x00), status & 0x80);
}

test "PPUSTATUS Read: Polling simulation - advance 12 ticks and read" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;

    // Seek to scanline 241, dot 1 - VBlank just set
    harness.seekToScanlineDot(241, 1);

    // VBlank MUST be set
    try testing.expect(harness.state.ppu.status.vblank);

    // Now simulate a BIT instruction: advance 12 PPU ticks (4 CPU cycles)
    var i: usize = 0;
    while (i < 12) : (i += 1) {
        harness.state.tick();
    }

    // After 12 ticks, we're at scanline 241, dot 13
    try testing.expectEqual(@as(u16, 241), harness.getScanline());
    try testing.expectEqual(@as(u16, 13), harness.getDot());

    // VBlank flag should STILL be set
    try testing.expect(harness.state.ppu.status.vblank);

    // NOW read $2002
    const status = harness.state.busRead(0x2002);

    // Returned value MUST have bit 7 set
    try testing.expectEqual(@as(u8, 0x80), status & 0x80);
}

test "PPUSTATUS Read: Loop polling from 240.340 - exact replica" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;

    // Start at scanline 240, dot 340 (just before VBlank)
    harness.seekToScanlineDot(240, 340);

    var detected_count: usize = 0;
    var poll_count: usize = 0;

    // Poll continuously through VBlank period
    // From scanline 240.340 to 261.10 (well into pre-render)
    while (harness.getScanline() <= 261 and harness.getDot() < 20) {
        const status = harness.state.busRead(0x2002);

        if ((status & 0x80) != 0) {
            detected_count += 1;
        }

        poll_count += 1;

        // Advance by 1 CPU instruction worth of time
        // BIT $2002 takes 4 CPU cycles = 12 PPU cycles
        var i: usize = 0;
        while (i < 12) : (i += 1) {
            harness.state.tick();
        }
    }

    // We should have detected VBlank at least once
    // Note: After first detection, subsequent reads will see it as cleared
    try testing.expect(detected_count >= 1);

    // We should have polled many times (VBlank lasts ~20 scanlines)
    try testing.expect(poll_count > 10);
}