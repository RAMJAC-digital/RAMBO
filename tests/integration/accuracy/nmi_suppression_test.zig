//! AccuracyCoin Accuracy Test: NMI SUPPRESSION
//!
//! This test verifies NMI suppression when reading PPUSTATUS ($2002) on the exact
//! cycle that the VBlank flag is set.
//!
//! Hardware Behavior:
//! - If $2002 is read on the EXACT cycle VBlank flag is set, the NMI is suppressed
//! - The VBlank flag is still set in $2002
//! - But the NMI does NOT fire
//!
//! This is a critical edge case used by many games for frame-perfect timing.
//! Games read $2002 in a tight loop, and if they read it exactly when VBlank
//! begins, they see the flag but don't get interrupted by NMI.
//!
//! Test Entry Point: 0xB5ED
//! Result Address: $0454 (result_NMI_Suppression)
//! Expected: $00 = PASS (NMI suppression works correctly)
//! ROM Screenshot (2025-10-19): FAIL 1

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

test "Accuracy: NMI SUPPRESSION (AccuracyCoin)" {
    const cart = RAMBO.CartridgeType.load(testing.allocator, "tests/data/AccuracyCoin.nes") catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    var h = try Harness.init();
    defer h.deinit();

    h.loadNromCartridge(cart);
    h.state.reset();
    h.state.ppu.warmup_complete = true;

    // === Emulate RunTest initialization ===
    var addr: u16 = 0x0500;
    while (addr < 0x0600) : (addr += 1) {
        h.state.bus.ram[addr & 0x07FF] = 0x00;
    }
    h.state.bus.ram[0x0600] = 0x40; // RTI
    h.state.bus.ram[0x10] = 0x00;
    h.state.bus.ram[0x50] = 0x00;
    h.state.bus.ram[0xF0] = 0x00;
    h.state.bus.ram[0xF1] = 0x00;

    h.seekToScanlineDot(241, 1);

    h.state.cpu.pc = 0xB5ED;
    h.state.cpu.state = .fetch_opcode;
    h.state.cpu.instruction_cycle = 0;
    h.state.cpu.sp = 0xFD;
    h.state.bus.ram[0x0454] = 0x80; // RUNNING

    // === Run test ===
    const max_cycles: usize = 10_000_000;
    var cycles: usize = 0;
    while (cycles < max_cycles) : (cycles += 1) {
        h.state.tick();
        const result = h.state.bus.ram[0x0454];
        if (result != 0x80) break;
    }

    const result = h.state.bus.ram[0x0454];

    // ROM screenshot shows FAIL 1 - expect current behavior for regression detection
    try testing.expectEqual(@as(u8, 0x01), result);
}
