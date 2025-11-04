//! NMI VBlank Span vs Flag Test
//!
//! Hardware behavior: NMI line is based on VBlank SPAN (scanlines 241-260),
//! not whether the VBlank FLAG is readable via $2002.
//!
//! Critical edge case:
//! 1. VBlank starts (flag set, NMI fires if enabled)
//! 2. Read $2002 (flag cleared, NMI line cleared)
//! 3. Enable NMI while still in VBlank span (NMI should fire again!)
//!
//! This test exercises the pattern where games read $2002 to clear VBlank,
//! then enable NMI expecting it to fire next frame. But if they're still
//! in the VBlank span, NMI should fire IMMEDIATELY.
//!
//! Reference: https://www.nesdev.org/wiki/PPU_registers#PPUCTRL
//! Reference: https://www.nesdev.org/wiki/NMI

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

test "NMI fires when enabled during VBlank span after $2002 read" {
    var h = try Harness.init();
    defer h.deinit();

    // Skip PPU warmup
    h.state.ppu.warmup_complete = true;

    // Advance clock to a reasonable cycle count
    h.state.clock.master_cycles = 2000;

    // Set up initial state: VBlank active, NMI disabled
    h.state.vblank_ledger.last_set_cycle = 1000;
    h.state.vblank_ledger.last_clear_cycle = 500; // Set > Clear = VBlank active
    h.state.ppu.ctrl.nmi_enable = false;
    h.state.cpu.nmi_line = false;

    // Verify VBlank span is active
    try testing.expect(h.state.vblank_ledger.isActive());

    // Read $2002 to clear VBlank flag
    const status = h.ppuReadRegister(0x2002);
    _ = status;

    // After $2002 read:
    // - VBlank FLAG is cleared (not readable)
    // - VBlank SPAN is still active (hardware timing)
    // - NMI line was cleared by read
    try testing.expect(h.state.vblank_ledger.isActive()); // Span still active
    try testing.expect(!h.state.vblank_ledger.isFlagVisible()); // Flag cleared
    try testing.expect(!h.state.cpu.nmi_line); // NMI cleared by read

    // Enable NMI while still in VBlank span
    h.ppuWriteRegister(0x2000, 0x80); // PPUCTRL bit 7 = 1 (enable NMI)

    // CRITICAL: NMI should fire immediately because we're still in VBlank span
    // Hardware behavior: NMI line asserts when (vblank_span_active AND nmi_enable)
    // Current bug: Uses isFlagVisible() instead of isActive(), so NMI doesn't fire
    try testing.expect(h.state.cpu.nmi_line);
}

test "NMI does NOT fire when enabled outside VBlank span" {
    var h = try Harness.init();
    defer h.deinit();

    // Skip PPU warmup
    h.state.ppu.warmup_complete = true;

    // Set up: VBlank NOT active
    h.state.vblank_ledger.last_set_cycle = 500;
    h.state.vblank_ledger.last_clear_cycle = 1000; // Clear > Set = VBlank NOT active
    h.state.ppu.ctrl.nmi_enable = false;
    h.state.cpu.nmi_line = false;

    // Verify VBlank span is NOT active
    try testing.expect(!h.state.vblank_ledger.isActive());

    // Enable NMI outside VBlank span
    h.ppuWriteRegister(0x2000, 0x80);

    // NMI should NOT fire (not in VBlank span)
    try testing.expect(!h.state.cpu.nmi_line);
}

test "NMI clears when reading $2002 during VBlank" {
    var h = try Harness.init();
    defer h.deinit();

    // Skip PPU warmup
    h.state.ppu.warmup_complete = true;

    // Set up: VBlank active, NMI enabled and asserted
    h.state.vblank_ledger.last_set_cycle = 1000;
    h.state.vblank_ledger.last_clear_cycle = 500;
    h.state.ppu.ctrl.nmi_enable = true;
    h.state.cpu.nmi_line = true; // NMI currently asserted

    // Read $2002
    _ = h.ppuReadRegister(0x2002);

    // NMI line should be cleared by read
    try testing.expect(!h.state.cpu.nmi_line);
}

test "NMI re-asserts if NMI re-enabled after clear during same VBlank span" {
    var h = try Harness.init();
    defer h.deinit();

    // Skip PPU warmup
    h.state.ppu.warmup_complete = true;

    // Start in VBlank with NMI enabled
    h.state.vblank_ledger.last_set_cycle = 1000;
    h.state.vblank_ledger.last_clear_cycle = 500;
    h.state.ppu.ctrl.nmi_enable = true;
    h.state.cpu.nmi_line = true;

    // Disable NMI (clears NMI line)
    h.ppuWriteRegister(0x2000, 0x00); // PPUCTRL bit 7 = 0
    try testing.expect(!h.state.cpu.nmi_line);

    // Re-enable NMI while still in VBlank span
    h.ppuWriteRegister(0x2000, 0x80); // PPUCTRL bit 7 = 1

    // NMI should re-assert (still in VBlank span)
    try testing.expect(h.state.cpu.nmi_line);
}
