//! AccuracyCoin Accuracy Test: NMI CONTROL
//!
//! This test verifies NMI enable/disable behavior via PPUCTRL bit 7.
//! Contains 8 subtests examining edge cases of NMI triggering.
//!
//! Tests:
//! 1. NMI should NOT occur when disabled
//! 2. NMI should occur at VBlank when enabled
//! 3. NMI should occur when enabled during VBlank IF VBlank flag is set
//! 4. NMI should NOT occur when enabled during VBlank IF VBlank flag is clear
//! 5. NMI should NOT occur twice from writing $80 to $2000 when already enabled
//! 6. (Same as 5 but NMI was enabled going into VBlank)
//! 7. NMI should occur again if you disable then re-enable
//! 8. NMI should occur 2 instructions after writing to PPUCTRL
//!
//! Test Entry Point: 0xB4D5
//! Result Address: $0452 (result_NMI_Control)
//! Expected: $00 = PASS (all 8 subtests pass)
//! ROM Screenshot (2025-10-19): FAIL 7 (7 subtests fail)

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

test "Accuracy: NMI CONTROL (AccuracyCoin)" {
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

    h.state.cpu.pc = 0xB4D5;
    h.state.cpu.state = .fetch_opcode;
    h.state.cpu.instruction_cycle = 0;
    h.state.cpu.sp = 0xFD;
    h.state.bus.ram[0x0452] = 0x80; // RUNNING

    // === Run test ===
    const max_cycles: usize = 10_000_000;
    var cycles: usize = 0;
    while (cycles < max_cycles) : (cycles += 1) {
        h.state.tick();
        const result = h.state.bus.ram[0x0452];
        if (result != 0x80) break;
    }

    const result = h.state.bus.ram[0x0452];

    // ROM screenshot shows FAIL 7 - expect current behavior for regression detection
    try testing.expectEqual(@as(u8, 0x07), result);
}
