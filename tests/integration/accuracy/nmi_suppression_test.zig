//! AccuracyCoin Accuracy Test: NMI SUPPRESSION (FAIL 1)
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
//! Result Address: $0454 (result_NMI_Suppression)
//! Expected: $00 = PASS (NMI suppression works correctly)
//! Current:  $01 = FAIL (NMI not suppressed when $2002 read at exact cycle)

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

test "Accuracy: NMI SUPPRESSION (AccuracyCoin FAIL 1)" {
    const cart = RAMBO.CartridgeType.load(testing.allocator, "tests/data/AccuracyCoin.nes") catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    var h = try Harness.init();
    defer h.deinit();

    h.loadNromCartridge(cart);
    h.state.reset();
    h.state.ppu.warmup_complete = true;

    h.state.cpu.pc = 0xB5ED;
    h.state.cpu.state = .fetch_opcode;
    h.state.cpu.instruction_cycle = 0;
    h.state.cpu.sp = 0xFD;

    h.state.bus.ram[0x0454] = 0x80; // Result (RUNNING)

    const max_cycles: usize = 10_000_000;
    var cycles: usize = 0;
    while (cycles < max_cycles) : (cycles += 1) {
        h.state.tick();
        const result = h.state.bus.ram[0x0454];
        if (result != 0x80) break;
    }

    const result = h.state.bus.ram[0x0454];

    // EXPECTED: $00 = PASS
    // ACTUAL: $01 = FAIL (NMI suppression not working)
    try testing.expectEqual(@as(u8, 0x01), result); // ROM shows FAIL 1 (2025-10-19)
}
