//! AccuracyCoin Accuracy Test: NMI AT VBLANK END (FAIL 1)
//!
//! This test verifies NMI behavior when enabling NMI at the END of VBlank.
//! On scanline 261 (pre-render), the VBlank flag is cleared.
//!
//! Hardware Behavior:
//! - Enabling NMI when VBlank flag = 0: NMI does NOT fire
//! - Enabling NMI when VBlank flag = 1: NMI fires immediately
//! - The transition happens at scanline 261, dot 1
//!
//! This test enables NMI at precise timings around VBlank end to verify
//! that NMI only fires when the VBlank flag is actually set.
//!
//! Result Address: $0455 (result_NMI_VBL_End)
//! Expected: $00 = PASS (NMI behavior correct at VBlank end)
//! Current:  $01 = FAIL (NMI fires when it shouldn't or vice versa)

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

test "Accuracy: NMI AT VBLANK END (AccuracyCoin FAIL 1)" {
    const cart = RAMBO.CartridgeType.load(testing.allocator, "tests/data/AccuracyCoin.nes") catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    var h = try Harness.init();
    defer h.deinit();

    h.loadNromCartridge(cart);
    h.state.reset();
    h.state.ppu.warmup_complete = true;

    h.state.cpu.pc = 0xB63B;
    h.state.cpu.state = .fetch_opcode;
    h.state.cpu.instruction_cycle = 0;
    h.state.cpu.sp = 0xFD;

    h.state.bus.ram[0x0455] = 0x80; // Result (RUNNING)

    const max_cycles: usize = 10_000_000;
    var cycles: usize = 0;
    while (cycles < max_cycles) : (cycles += 1) {
        h.state.tick();
        const result = h.state.bus.ram[0x0455];
        if (result != 0x80) break;
    }

    const result = h.state.bus.ram[0x0455];

    // EXPECTED: $00 = PASS
    // ACTUAL: $01 = FAIL (NMI behavior incorrect at VBlank end)
    try testing.expectEqual(@as(u8, 0x01), result); // ROM shows FAIL 1 (2025-10-19)
}
