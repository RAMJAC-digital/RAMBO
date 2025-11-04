//! Integration tests for interrupt execution
//! Tests the full 7-cycle interrupt sequence with bus operations

const std = @import("std");
const testing = std.testing;
const expect = testing.expect;

const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;


test "NMI: Complete 7-cycle execution sequence" {
    var harness = try Harness.init();
    defer harness.deinit();
    
    

    // Using harness.state
    harness.state.reset();

    // Setup: Allocate test ROM with interrupt vectors
    const test_rom = try testing.allocator.alloc(u8, 32768); // 32KB ROM
    defer testing.allocator.free(test_rom);
    @memset(test_rom, 0x00);
    harness.state.bus.test_ram = test_rom;

    // Setup: NMI handler at $C000
    // NMI vector at $FFFA-$FFFB (offset 0x7FFA-0x7FFB in test_rom)
    test_rom[0x7FFA] = 0x00; // NMI vector low
    test_rom[0x7FFB] = 0xC0; // NMI vector high

    // Setup: CPU at $8000, SP at $FD
    harness.state.cpu.pc = 0x8000;
    harness.state.cpu.sp = 0xFD;
    harness.state.cpu.p.carry = true; // Set a flag to verify it's preserved

    // Setup: Enable VBlank NMI
    harness.state.ppu.ctrl.nmi_enable = true;
    harness.state.ppu.warmup_complete = true;

    // PHASE-INDEPENDENT: Seek to just before VBlank, then advance to CPU boundary
    // This works for phases 0, 1, 2 by letting CPU execute during the race window
    harness.state.cpu.halted = true;
    harness.seekTo(240, 340); // End of scanline 240
    harness.seekToCpuBoundary(241, 0); // First CPU tick of scanline 241
    harness.state.cpu.halted = false;
    // With NMI enabled, the NMI line will be asserted by CPU execution logic

    // Wait until interrupt sequence starts at cycle 1
    while (true) {
        harness.runCpuCycles(1);
        if (harness.state.cpu.state == .interrupt_sequence and harness.state.cpu.instruction_cycle == 1) break;
    }

    const sp_before = harness.state.cpu.sp;

    // Cycle 1: Push PCH
    harness.runCpuCycles(1);
    try expect(harness.state.cpu.instruction_cycle == 2);
    try expect(harness.state.bus.ram[0x0100 + @as(usize, sp_before)] == 0x80);
    try expect(harness.state.cpu.sp == sp_before - 1);

    // Cycle 2: Push PCL
    harness.runCpuCycles(1);
    try expect(harness.state.cpu.instruction_cycle == 3);
    try expect(harness.state.bus.ram[0x0100 + @as(usize, sp_before - 1)] == 0x00);
    try expect(harness.state.cpu.sp == sp_before - 2);

    // Cycle 3: Push P (B=0, U=1)
    harness.runCpuCycles(1);
    try expect(harness.state.cpu.instruction_cycle == 4);
    const stacked_p = harness.state.bus.ram[0x0100 + @as(usize, sp_before - 2)];
    try expect((stacked_p & 0x10) == 0);
    try expect((stacked_p & 0x20) != 0);
    try expect(harness.state.cpu.sp == sp_before - 3);

    // Cycle 4: Fetch vector low, set I
    harness.runCpuCycles(1);
    try expect(harness.state.cpu.instruction_cycle == 5);
    try expect(harness.state.cpu.operand_low == 0x00);
    try expect(harness.state.cpu.p.interrupt == true);

    // Cycle 5: Fetch vector high
    harness.runCpuCycles(1);
    try expect(harness.state.cpu.instruction_cycle == 6);
    try expect(harness.state.cpu.operand_high == 0xC0);

    // Cycle 6: Jump to handler
    harness.runCpuCycles(1);
    try expect(harness.state.cpu.pc == 0xC000);
    try expect(harness.state.cpu.state == .fetch_opcode);
    try expect(harness.state.cpu.instruction_cycle == 0);
    try expect(harness.state.cpu.pending_interrupt == .none);
}

test "NMI: Triggers on VBlank with nmi_enable=true" {
    var harness = try Harness.init();
    defer harness.deinit();
    
    

    // Using harness.state
    harness.state.reset();

    // Setup: Allocate test ROM with interrupt vectors
    const test_rom = try testing.allocator.alloc(u8, 32768);
    defer testing.allocator.free(test_rom);
    @memset(test_rom, 0xEA); // Fill with NOP
    harness.state.bus.test_ram = test_rom;

    // Setup: NMI handler at $C000
    test_rom[0x7FFA] = 0x00;
    test_rom[0x7FFB] = 0xC0;

    // Setup: Enable NMI
    harness.state.ppu.ctrl.nmi_enable = true;
    harness.state.ppu.warmup_complete = true;
    harness.state.cpu.pc = 0x8000;

    // PHASE-INDEPENDENT: Seek before VBlank, advance to CPU boundary
    harness.seekTo(240, 340);
    harness.seekToCpuBoundary(241, 0);

    // Advance one full tick cycle (not just CPU) - VBlank will set, NMI will be detected
    harness.tick(1);

    // On the NEXT CPU tick after VBlank set, NMI should be pending
    // (following "second-to-last cycle" rule)
    while (!harness.state.clock.isCpuTick()) {
        harness.tick(1);
    }

    try expect(harness.state.cpu.pending_interrupt == .nmi);
    try expect(harness.state.cpu.state == .interrupt_sequence);
}

test "NMI: Does NOT trigger when nmi_enable=false" {
    var harness = try Harness.init();
    defer harness.deinit();
    
    

    // Using harness.state
    harness.state.reset();

    // Setup: Allocate test ROM
    const test_rom = try testing.allocator.alloc(u8, 32768);
    defer testing.allocator.free(test_rom);
    @memset(test_rom, 0xEA); // Fill with NOP
    harness.state.bus.test_ram = test_rom;

    // Setup: NMI disabled
    harness.state.ppu.ctrl.nmi_enable = false;
    harness.state.ppu.warmup_complete = true;
    harness.state.cpu.pc = 0x8000;
    harness.state.cpu.state = .fetch_opcode;

    // VBlank NOT triggered (ledger span_active defaults to false)
    // Since nmi_enable=false, even if VBlank occurred, NMI wouldn't fire

    // Step CPU - should NOT detect NMI
    harness.state.tickCpu();
    try expect(harness.state.cpu.pending_interrupt == .none);
    // Note: State will have transitioned from fetch_opcode to executing NOP
    // We only care that NMI didn't trigger
}
