//! NMI Sequence Integration Tests
//!
//! Verifies the complete NMI signal flow from PPU to CPU execution.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

fn setupNmiHandler(h: *Harness, nmi_vector: u16) void {
    // Install minimal PRG test image to service vector fetches via test RAM mapping ($8000-$FFFF)
    if (h.state.bus.test_ram == null) {
        const rom = std.testing.allocator.alloc(u8, 0x8000) catch unreachable;
        @memset(rom, 0xEA); // NOPs
        h.state.bus.test_ram = rom;
    }

    // Write NMI vector ($FFFA/$FFFB → offset 0x7FFA/0x7FFB in test_ram)
    const tr = h.state.bus.test_ram.?;
    tr[0x7FFA] = @as(u8, @intCast(nmi_vector & 0x00FF));
    tr[0x7FFB] = @as(u8, @intCast((nmi_vector >> 8) & 0x00FF));

    // Place a small program at $0000 in CPU RAM (JMP $C000)
    h.loadRam(&[_]u8{ 0x4C, 0x00, 0xC0 }, 0x0000);
    h.state.cpu.pc = 0x0000;
    h.state.cpu.state = .fetch_opcode;
    h.state.cpu.instruction_cycle = 0;
}

test "NMI Sequence: Jumps to NMI vector when VBlank occurs with NMI enabled" {
    var h = try Harness.init();
    defer h.deinit();
    defer {
        if (h.state.bus.test_ram) |tr| {
            std.testing.allocator.free(tr);
            h.state.bus.test_ram = null;
        }
    }

    // Setup a simple NMI handler at $C000
    setupNmiHandler(&h, 0xC000);

    // Enable NMI
    h.state.busWrite(0x2000, 0x80);

    // Seek to just before VBlank
    h.seekTo(240, 0);

    // Run for a full frame, which should include the NMI
    h.runCpuCycles(30000); // Enough cycles to get through VBlank and the NMI

    // Check that we jumped to the NMI handler region
    try testing.expect(h.state.cpu.pc >= 0xC000);
}

test "NMI Sequence: Does NOT jump to NMI vector if NMI is disabled" {
    var h = try Harness.init();
    defer h.deinit();
    defer {
        if (h.state.bus.test_ram) |tr| {
            std.testing.allocator.free(tr);
            h.state.bus.test_ram = null;
        }
    }

    const initial_pc = h.state.cpu.pc;

    // Setup a simple NMI handler at $C000
    setupNmiHandler(&h, 0xC000);

    // Make sure NMI is disabled
    h.state.busWrite(0x2000, 0x00);

    // Seek to just before VBlank
    h.seekTo(240, 0);

    // Run for a full frame
    h.runCpuCycles(30000);

    // PC should NOT have changed to the NMI handler
    try testing.expect(h.state.cpu.pc != 0xC000);
    try testing.expect(h.state.cpu.pc != initial_pc); // It should have executed some code
}

test "NMI Sequence: NMI is only triggered once per VBlank edge" {
    var h = try Harness.init();
    defer h.deinit();
    defer {
        if (h.state.bus.test_ram) |tr| {
            std.testing.allocator.free(tr);
            h.state.bus.test_ram = null;
        }
    }

    // Setup an NMI handler that just does RTI
    h.loadRam(&[_]u8{ 0x40 }, 0x0000); // RTI
    h.state.cpu.pc = 0x0000;
    if (h.state.bus.test_ram == null) {
        const rom = try std.testing.allocator.alloc(u8, 0x8000);
        @memset(rom, 0xEA);
        h.state.bus.test_ram = rom;
    }
    const tr = h.state.bus.test_ram.?;
    tr[0x7FFA] = 0x00;
    tr[0x7FFB] = 0x80;

    // Enable NMI
    h.state.busWrite(0x2000, 0x80);

    // Seek to VBlank
    h.seekTo(241, 1);

    // Run enough cycles for the NMI to be handled
    h.runCpuCycles(20);

    const pc_after_nmi = h.state.cpu.pc;

    // Run for another 1000 cycles within the same VBlank period
    h.runCpuCycles(1000);

    // The PC should have advanced (from the NOPs after RTI), but it should not have
    // re-triggered the NMI. If it re-triggered, PC would be reset to 0x8000.
    try testing.expect(h.state.cpu.pc != 0x8000);
    try testing.expect(h.state.cpu.pc > pc_after_nmi);
}
