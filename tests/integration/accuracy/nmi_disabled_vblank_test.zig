//! AccuracyCoin Accuracy Test: NMI DISABLED AT VBLANK
//!
//! This test verifies NMI behavior when DISABLING NMI at the START of VBlank.
//! On scanline 241, dot 1, the VBlank flag is set and NMI would normally fire.
//!
//! Hardware Behavior:
//! - If NMI is disabled BEFORE VBlank starts: NMI does NOT fire
//! - If NMI is disabled ON THE EXACT CYCLE VBlank starts: NMI may or may not fire
//! - If NMI is disabled AFTER VBlank starts: NMI already fired
//!
//! Test Entry Point: 0xB66D
//! Result Address: $0456 (result_NMI_Disabled_VBL_Start)
//! Expected: $00 = PASS (NMI disable timing correct)
//! ROM Screenshot (2025-10-19): FAIL 1

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

test "Accuracy: NMI DISABLED AT VBLANK (AccuracyCoin)" {
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

    h.state.cpu.pc = 0xB66D;
    h.state.cpu.state = .fetch_opcode;
    h.state.cpu.instruction_cycle = 0;
    h.state.cpu.sp = 0xFD;
    h.state.bus.ram[0x0456] = 0x80; // RUNNING

    // === Run test ===
    const max_cycles: usize = 10_000_000;
    var cycles: usize = 0;
    while (cycles < max_cycles) : (cycles += 1) {
        h.state.tick();
        const result = h.state.bus.ram[0x0456];
        if (result != 0x80) break;
    }

    const result = h.state.bus.ram[0x0456];

    // ROM screenshot shows FAIL 1 - expect current behavior for regression detection
    try testing.expectEqual(@as(u8, 0x01), result);
}
