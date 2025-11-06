//! PPU Open Bus Behavior Tests
//!
//! Verifies that CPU-side reads observing PPU open bus state preserve
//! hardware-defined masked bits.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

test "PPU Open Bus: palette read preserves high bits" {
    var h = try Harness.init();
    defer h.deinit();

    // Seed CPU open bus high bits and point PPUDATA to palette space
    h.state.bus.open_bus.set(0xC0);
    h.state.ppu.internal.v = 0x3F00;
    h.state.ppu.palette_ram[0] = 0x0F;

    const value = h.state.busRead(0x2007);
    try testing.expectEqual(@as(u8, 0xCF), value);
    try testing.expectEqual(@as(u8, 0xCF), h.state.ppu.open_bus.value);
}

test "PPU Open Bus: OAM attribute read uses open bus bits" {
    var h = try Harness.init();
    defer h.deinit();

    h.state.bus.open_bus.set(0x14); // Bits 2-4 set to 101
    h.state.ppu.oam_addr = 0x02; // Attribute byte slot
    h.state.ppu.oam[0x02] = 0x00;

    const value = h.state.busRead(0x2004);
    try testing.expectEqual(@as(u8, 0x14), value);
    try testing.expectEqual(@as(u8, 0x14), h.state.ppu.open_bus.value);
}
