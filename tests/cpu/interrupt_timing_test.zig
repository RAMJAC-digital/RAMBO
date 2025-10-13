const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Harness = RAMBO.TestHarness.Harness;

test "NMI: Response latency is 7 cycles" {
    var h = try Harness.init();
    defer h.deinit();

    // Provide test RAM for vector fetch ($FFFA/$FFFB via $8000 mapping)
    const rom = try testing.allocator.alloc(u8, 0x8000);
    defer testing.allocator.free(rom);
    @memset(rom, 0xEA);
    h.state.bus.test_ram = rom;
    // Set NMI vector to $C000
    rom[0x7FFA] = 0x00;
    rom[0x7FFB] = 0xC0;
    // Start CPU at $8000, SP at $FD
    h.state.cpu.pc = 0x8000;
    h.state.cpu.sp = 0xFD;

    // Enable NMI
    h.state.busWrite(0x2000, 0x80);
    h.state.ppu.warmup_complete = true;

    // Align on fetch boundary exactly at VBlank set
    h.state.cpu.halted = true;
    h.seekTo(241, 1);
    h.state.cpu.halted = false;

    // Wait until interrupt sequence starts at cycle 1
    while (true) {
        h.runCpuCycles(1);
        if (h.state.cpu.state == .interrupt_sequence and h.state.cpu.instruction_cycle == 1) break;
    }

    // Complete remaining 6 cycles
    h.runCpuCycles(6);

    // Verify we've jumped to the handler
    try testing.expectEqual(@as(u16, 0xC000), h.state.cpu.pc);
    try testing.expect(h.state.cpu.state == .fetch_opcode);
}
