//! NMI VBlank Flag vs Span Test
//!
//! Hardware behavior: NMI triggering is based on VBlank FLAG (readable bit 7 of $2002),
//! NOT the VBlank SPAN (hardware timing window).
//!
//! Critical distinction:
//! - VBlank SPAN: Scanlines 241-260 (hardware timing window)
//! - VBlank FLAG: Readable bit 7 of $2002 (cleared by reads, can be false during span)
//!
//! NMI triggering behavior (per Mesen2 NesPpu.cpp:546-550):
//! - NMI fires on 0→1 PPUCTRL.7 transition ONLY if VBlank FLAG is set
//! - Reading $2002 clears both FLAG and NMI line
//! - Enabling NMI after $2002 read does NOT trigger (even if still in span)
//!
//! Reference: https://www.nesdev.org/wiki/PPU_registers#PPUCTRL
//! Reference: https://www.nesdev.org/wiki/NMI
//! Reference: Mesen2 NesPpu.cpp:546-550 (_statusFlags.VerticalBlank check)

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

test "NMI does NOT fire when enabled after $2002 read (even during span)" {
    var h = try Harness.init();
    defer h.deinit();

    // Skip PPU warmup
    h.state.ppu.warmup_complete = true;

    // Set up initial state: VBlank flag set, span active, NMI disabled
    h.state.ppu.vblank.vblank_flag = true;
    h.state.ppu.vblank.vblank_span_active = true;
    h.state.ppu.ctrl.nmi_enable = false;
    h.state.ppu.nmi_line = false;

    // Verify both flag and span are active
    try testing.expect(h.state.ppu.vblank.isFlagSet());
    try testing.expect(h.state.ppu.vblank.isSpanActive());

    // Read $2002 to clear VBlank flag
    const status = h.ppuReadRegister(0x2002);
    _ = status;

    // After $2002 read:
    // - VBlank FLAG is cleared (bit 7 of $2002 now reads 0)
    // - VBlank SPAN is still active (hardware timing continues)
    // - NMI line was cleared by read
    try testing.expect(h.state.ppu.vblank.isSpanActive()); // Span still active
    try testing.expect(!h.state.ppu.vblank.isFlagSet()); // Flag cleared
    try testing.expect(!h.state.ppu.nmi_line); // NMI cleared by read

    // Enable NMI while still in VBlank span (but flag is cleared)
    h.ppuWriteRegister(0x2000, 0x80); // PPUCTRL bit 7 = 1 (enable NMI)

    // CRITICAL: NMI should NOT fire because FLAG is cleared (even though span is active)
    // Hardware behavior (per Mesen2): NMI checks _statusFlags.VerticalBlank (FLAG), not span
    // This is correct behavior - FLAG-based triggering
    try testing.expect(!h.state.ppu.nmi_line);
}

test "NMI does NOT fire when enabled with flag cleared" {
    var h = try Harness.init();
    defer h.deinit();

    // Skip PPU warmup
    h.state.ppu.warmup_complete = true;

    // Set up: VBlank flag cleared
    h.state.ppu.vblank.vblank_flag = false;
    h.state.ppu.ctrl.nmi_enable = false;
    h.state.ppu.nmi_line = false;

    // Verify VBlank flag is NOT set
    try testing.expect(!h.state.ppu.vblank.isFlagSet());

    // Enable NMI with flag cleared
    h.ppuWriteRegister(0x2000, 0x80);

    // NMI should NOT fire (flag not set)
    try testing.expect(!h.state.ppu.nmi_line);
}

test "NMI clears when reading $2002 during VBlank" {
    var h = try Harness.init();
    defer h.deinit();

    // Skip PPU warmup
    h.state.ppu.warmup_complete = true;

    // Set up: VBlank flag set, NMI enabled and asserted
    h.state.ppu.vblank.vblank_flag = true;
    h.state.ppu.ctrl.nmi_enable = true;
    h.state.ppu.nmi_line = true; // NMI currently asserted

    // Read $2002
    _ = h.ppuReadRegister(0x2002);

    // NMI line should be cleared by read
    try testing.expect(!h.state.ppu.nmi_line);
}

test "NMI re-asserts if NMI re-enabled with flag still set" {
    var h = try Harness.init();
    defer h.deinit();

    // Skip PPU warmup
    h.state.ppu.warmup_complete = true;

    // Start with VBlank flag set and NMI enabled
    h.state.ppu.vblank.vblank_flag = true;
    h.state.ppu.ctrl.nmi_enable = true;
    h.state.ppu.nmi_line = true;

    // Disable NMI (clears NMI line per PpuHandler.write())
    h.ppuWriteRegister(0x2000, 0x00); // PPUCTRL bit 7 = 0
    try testing.expect(!h.state.ppu.nmi_line);

    // Re-enable NMI while flag is still set
    h.ppuWriteRegister(0x2000, 0x80); // PPUCTRL bit 7 = 1

    // NMI should re-assert (0→1 transition with flag set)
    try testing.expect(h.state.ppu.nmi_line);
}
