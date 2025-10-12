const std = @import("std");
const expect = std.testing.expect;
const Harness = @import("../helpers/Harness.zig");

test "NMI: Response latency is 7 cycles" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Setup: Enable NMI in PPUCTRL
    harness.state.testSetNmiEnable(true);

    // Advance clock to a point before VBlank
    harness.state.clock.advance(82180);
    try expect(harness.state.vblank_ledger.shouldAssertNmiLine(harness.state.clock.ppu_cycles, true) == false);

    // Trigger VBlank (scanline 241, dot 1)
    // This should set the NMI edge pending in the ledger
    harness.state.clock.advance(1);
    const nmi_enabled = harness.state.ppu.ctrl.nmi_enable;
    harness.state.vblank_ledger.recordVBlankSet(harness.state.clock.ppu_cycles, nmi_enabled);
    try expect(harness.state.vblank_ledger.shouldAssertNmiLine(harness.state.clock.ppu_cycles, true));

    // Step 1 CPU cycle - should detect NMI and start the 7-cycle sequence
    harness.state.tickCpuWithClock();
    try expect(harness.state.cpu.state == .interrupt_sequence);
    try expect(harness.state.cpu.instruction_cycle == 1); // Correctly starts at cycle 1

    // Step 6 more CPU cycles to complete the interrupt sequence
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        harness.state.tickCpuWithClock();
    }

    // After 7 total cycles, CPU should have jumped to the NMI vector
    // and be ready to fetch the first instruction of the handler.
    try expect(harness.state.cpu.state == .fetch_opcode);

    // Default NMI vector is $0000 in test harness, let's read it.
    const nmi_vector = harness.state.busRead16(0xFFFA);
    try expect(harness.state.cpu.pc == nmi_vector);
}
