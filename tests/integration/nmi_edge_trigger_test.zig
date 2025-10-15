// NMI Immediate Trigger Edge Case Test
//
// Verifies that enabling NMI (PPUCTRL bit 7) while the VBlank flag is already set
// triggers an immediate NMI. This is a critical edge case for games that read
// PPUSTATUS to clear VBlank, then enable NMI expecting it to fire next frame.
//
// Reference: https://www.nesdev.org/wiki/PPU_registers#PPUCTRL
// Reference: https://www.nesdev.org/wiki/NMI

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;

test "NMI immediate trigger: enabling NMI while VBlank=1 triggers NMI" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    // Skip PPU warmup period
    state.ppu.warmup_complete = true;

    // Manually set VBlank flag (simulate being in VBlank period)
    state.vblank_ledger.last_set_cycle = 100;
    state.vblank_ledger.last_clear_cycle = 50; // Set > Clear means VBlank=1

    // Ensure NMI is currently disabled
    state.ppu.ctrl.nmi_enable = false;
    state.cpu.nmi_line = false;

    // Write to PPUCTRL ($2000) to enable NMI (bit 7 = 1)
    const ppuctrl_value: u8 = 0x80; // Enable NMI, all other bits 0
    state.busWrite(0x2000, ppuctrl_value);

    // NMI line should now be set (immediate trigger)
    try testing.expect(state.cpu.nmi_line);

    // Verify PPUCTRL was updated
    try testing.expect(state.ppu.ctrl.nmi_enable);
}

test "NMI immediate trigger: no trigger when VBlank=0" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    // Skip PPU warmup period
    state.ppu.warmup_complete = true;

    // VBlank flag is CLEAR (Clear > Set means VBlank=0)
    state.vblank_ledger.last_set_cycle = 50;
    state.vblank_ledger.last_clear_cycle = 100;

    // Ensure NMI disabled
    state.ppu.ctrl.nmi_enable = false;
    state.cpu.nmi_line = false;

    // Enable NMI
    state.busWrite(0x2000, 0x80);

    // NMI should NOT trigger (VBlank not set)
    try testing.expect(!state.cpu.nmi_line);

    // But PPUCTRL should still be updated
    try testing.expect(state.ppu.ctrl.nmi_enable);
}

test "NMI immediate trigger: no trigger when NMI already enabled" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    // Skip PPU warmup period
    state.ppu.warmup_complete = true;

    // VBlank flag is SET
    state.vblank_ledger.last_set_cycle = 100;
    state.vblank_ledger.last_clear_cycle = 50;

    // NMI is ALREADY enabled
    state.ppu.ctrl.nmi_enable = true;
    state.cpu.nmi_line = false;

    // Write to PPUCTRL with NMI still enabled (no 0→1 transition)
    state.busWrite(0x2000, 0x80);

    // NMI should NOT trigger (already enabled, no edge)
    try testing.expect(!state.cpu.nmi_line);
}

test "NMI immediate trigger: disabling NMI does not trigger" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    // Skip PPU warmup period
    state.ppu.warmup_complete = true;

    // VBlank flag is SET
    state.vblank_ledger.last_set_cycle = 100;
    state.vblank_ledger.last_clear_cycle = 50;

    // NMI is currently enabled
    state.ppu.ctrl.nmi_enable = true;
    state.cpu.nmi_line = false;

    // Disable NMI (write 0 to bit 7)
    state.busWrite(0x2000, 0x00);

    // NMI should NOT trigger (1→0 transition, not 0→1)
    try testing.expect(!state.cpu.nmi_line);

    // Verify NMI was disabled
    try testing.expect(!state.ppu.ctrl.nmi_enable);
}

test "NMI immediate trigger: common game pattern" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    // Skip PPU warmup period
    state.ppu.warmup_complete = true;

    // Simulate common game pattern:
    // 1. Read PPUSTATUS (clears VBlank)
    // 2. Do work
    // 3. VBlank starts (VBlank flag set)
    // 4. Enable NMI (should trigger immediately)

    // Step 1: VBlank flag cleared by PPUSTATUS read
    state.vblank_ledger.last_clear_cycle = 100;
    state.vblank_ledger.last_set_cycle = 50;
    state.ppu.ctrl.nmi_enable = false;
    state.cpu.nmi_line = false;

    // Step 2: Game does work...

    // Step 3: VBlank starts (PPU sets flag)
    state.vblank_ledger.last_set_cycle = 200; // Now Set > Clear

    // Step 4: Game enables NMI expecting next frame, but...
    state.busWrite(0x2000, 0x80);

    // Should trigger IMMEDIATELY because VBlank is already set!
    try testing.expect(state.cpu.nmi_line);
}
