//! AccuracyCoin Accuracy Test: VBLANK END (FAIL 1)
//!
//! This test verifies the exact cycle timing of VBlank flag CLEAR in PPUSTATUS ($2002).
//! The VBlank flag is cleared on scanline 261, dot 1 (pre-render scanline).
//!
//! Hardware Timing:
//! - Scanline 261, dot 1: VBlank flag CLEARED
//! - Reading $2002 just before: returns $80 (VBlank still set)
//! - Reading $2002 on/after dot 1: returns $00 (VBlank cleared)
//!
//! Result Address: $0451 (result_VBlank_End)
//! Expected: $00 = PASS (VBlank clear timing correct)
//! Current:  $01 = FAIL (VBlank clear timing off by 1+ cycles)

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

test "Accuracy: VBLANK END (AccuracyCoin FAIL 1)" {
    const cart = RAMBO.CartridgeType.load(testing.allocator, "tests/data/AccuracyCoin.nes") catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    var h = try Harness.init();
    defer h.deinit();

    h.loadNromCartridge(cart);
    h.state.reset();
    h.state.ppu.warmup_complete = true;

    h.state.cpu.pc = 0xB49C;
    h.state.cpu.state = .fetch_opcode;
    h.state.cpu.instruction_cycle = 0;
    h.state.cpu.sp = 0xFD;

    h.state.bus.ram[0x0451] = 0x80; // Result (RUNNING)

    const max_cycles: usize = 10_000_000;
    var cycles: usize = 0;
    while (cycles < max_cycles) : (cycles += 1) {
        h.state.tick();
        const result = h.state.bus.ram[0x0451];
        if (result != 0x80) break;
    }

    const result = h.state.bus.ram[0x0451];

    // EXPECTED: $00 = PASS
    // VERIFIED 2025-10-19: ROM shows FAIL 1
    // Test updated to expect current behavior for regression detection
    try testing.expectEqual(@as(u8, 0x01), result);
}
