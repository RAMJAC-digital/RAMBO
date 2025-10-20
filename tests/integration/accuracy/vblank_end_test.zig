//! AccuracyCoin Accuracy Test: VBLANK END
//!
//! This test verifies the exact cycle timing of VBlank flag CLEAR in PPUSTATUS ($2002).
//! The VBlank flag is cleared on scanline 261, dot 1 (pre-render scanline).
//!
//! Hardware Timing:
//! - Scanline 261, dot 1: VBlank flag CLEARED
//! - Reading $2002 just before: returns $80 (VBlank still set)
//! - Reading $2002 on/after dot 1: returns $00 (VBlank cleared)
//!
//! Test Entry Point: 0xB49C
//! Result Address: $0451 (result_VBlank_End)
//! Expected: $00 = PASS (VBlank clear timing correct)
//! ROM Screenshot (2025-10-19): FAIL 1

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

test "Accuracy: VBLANK END (AccuracyCoin)" {
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
    h.state.bus.ram[0x10] = 0x00; // ErrorCode
    h.state.bus.ram[0x50] = 0x00;
    h.state.bus.ram[0xF0] = 0x00;
    h.state.bus.ram[0xF1] = 0x00;

    h.seekToScanlineDot(241, 1);

    h.state.cpu.pc = 0xB49C;
    h.state.cpu.state = .fetch_opcode;
    h.state.cpu.instruction_cycle = 0;
    h.state.cpu.sp = 0xFD;
    h.state.bus.ram[0x0451] = 0x80; // RUNNING

    // === Run test ===
    const max_cycles: usize = 10_000_000;
    var cycles: usize = 0;
    while (cycles < max_cycles) : (cycles += 1) {
        h.state.tick();
        const result = h.state.bus.ram[0x0451];
        if (result != 0x80) break;
    }

    const result = h.state.bus.ram[0x0451];

    // With proper initialization, test returns PASS (differs from ROM screenshot FAIL 1)
    // Expecting current emulator behavior for regression detection
    try testing.expectEqual(@as(u8, 0x00), result);
}
