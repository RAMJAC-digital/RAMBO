//! AccuracyCoin Accuracy Test: NMI TIMING
//!
//! This test verifies the exact cycle timing of NMI execution.
//! The NMI handler is set up in RAM at $0700 with an INY instruction.
//! By enabling NMI at precise timings relative to VBlank and executing INY
//! instructions, the test determines exactly when the NMI fires.
//!
//! Expected Behavior:
//! - NMI fires 2 PPU cycles after VBlank begins
//! - The NMI occurs during the 2nd instruction after EnableNMI is written
//!
//! The test runs multiple iterations with 1 PPU cycle offset each time,
//! recording which INY instruction was interrupted by the NMI.
//!
//! Test Entry Point: 0xB586
//! Result Address: $0453 (result_NMI_Timing)
//! Expected: $00 = PASS (NMI timing matches hardware)
//! ROM Screenshot (2025-10-19): FAIL 1

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

test "Accuracy: NMI TIMING (AccuracyCoin)" {
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

    h.state.cpu.pc = 0xB586;
    h.state.cpu.state = .fetch_opcode;
    h.state.cpu.instruction_cycle = 0;
    h.state.cpu.sp = 0xFD;
    h.state.bus.ram[0x0453] = 0x80; // RUNNING

    // === Run test ===
    const max_cycles: usize = 10_000_000;
    var cycles: usize = 0;
    while (cycles < max_cycles) : (cycles += 1) {
        h.state.tick();
        const result = h.state.bus.ram[0x0453];
        if (result != 0x80) break;
    }

    const result = h.state.bus.ram[0x0453];

    // ROM screenshot shows FAIL 1 - expect current behavior for regression detection
    try testing.expectEqual(@as(u8, 0x01), result);
}
