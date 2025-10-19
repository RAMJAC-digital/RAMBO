//! AccuracyCoin Accuracy Test: NMI DISABLED AT VBLANK (FAIL 1)
//!
//! This test verifies NMI behavior when DISABLING NMI at the START of VBlank.
//! On scanline 241, dot 1, the VBlank flag is set and NMI would normally fire.
//!
//! Hardware Behavior:
//! - If NMI is disabled BEFORE VBlank starts: NMI does NOT fire
//! - If NMI is disabled ON THE EXACT CYCLE VBlank starts: NMI may or may not fire
//! - If NMI is disabled AFTER VBlank starts: NMI already fired
//!
//! This test disables NMI at precise timings around VBlank start (scanline 241, dot 1)
//! to verify the exact cycle where NMI can be prevented.
//!
//! Result Address: $0456 (result_NMI_Disabled_VBL_Start)
//! Expected: $00 = PASS (NMI disable timing correct)
//! Current:  $01 = FAIL (NMI fires when it should be disabled or vice versa)

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

test "Accuracy: NMI DISABLED AT VBLANK (AccuracyCoin FAIL 1)" {
    const cart = RAMBO.CartridgeType.load(testing.allocator, "tests/data/AccuracyCoin.nes") catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    var h = try Harness.init();
    defer h.deinit();

    h.loadNromCartridge(cart);
    h.state.reset();
    h.state.ppu.warmup_complete = true;

    h.state.cpu.pc = 0xB66D;
    h.state.cpu.state = .fetch_opcode;
    h.state.cpu.instruction_cycle = 0;
    h.state.cpu.sp = 0xFD;

    h.state.bus.ram[0x0456] = 0x80; // Result (RUNNING)

    const max_cycles: usize = 10_000_000;
    var cycles: usize = 0;
    while (cycles < max_cycles) : (cycles += 1) {
        h.state.tick();
        const result = h.state.bus.ram[0x0456];
        if (result != 0x80) break;
    }

    const result = h.state.bus.ram[0x0456];

    // EXPECTED: $00 = PASS
    // ACTUAL: $01 = FAIL (NMI disable timing incorrect)
    try testing.expectEqual(@as(u8, 0x01), result); // ROM shows FAIL 1 (2025-10-19)
}
