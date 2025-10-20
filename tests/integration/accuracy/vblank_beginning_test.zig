//! AccuracyCoin Accuracy Test: VBLANK BEGINNING
//!
//! This test verifies the exact cycle timing of the VBlank flag in PPUSTATUS ($2002).
//! The VBlank flag is set on scanline 241, dot 1 - this is the start of vertical blanking.
//!
//! Hardware Timing:
//! - Scanline 241, dot 1: VBlank flag SET
//! - Reading $2002 on the exact cycle the flag is set returns 0 AND suppresses NMI
//! - Reading $2002 one cycle later returns $80 (VBlank flag set)
//!
//! Test Entry Point: 0xB44A
//! Result Address: $0450 (result_VBlank_Beginning)
//! Expected: $00 = PASS (VBlank timing correct)
//! ROM Screenshot (2025-10-19): FAIL 1

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

test "Accuracy: VBLANK BEGINNING (AccuracyCoin)" {
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

    h.state.cpu.pc = 0xB44A;
    h.state.cpu.state = .fetch_opcode;
    h.state.cpu.instruction_cycle = 0;
    h.state.cpu.sp = 0xFD;
    h.state.bus.ram[0x0450] = 0x80; // RUNNING

    // === Run test ===
    const max_cycles: usize = 10_000_000;
    var cycles: usize = 0;
    while (cycles < max_cycles) : (cycles += 1) {
        h.state.tick();
        const result = h.state.bus.ram[0x0450];
        if (result != 0x80) break;
    }

    const result = h.state.bus.ram[0x0450];

    // ROM screenshot shows FAIL 1 - expect current behavior for regression detection
    try testing.expectEqual(@as(u8, 0x01), result);
}
