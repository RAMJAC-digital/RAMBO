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

    // Trigger VBlank (set vblank flag)
    harness.state.ppu.status.vblank = true;

    // Manually trigger NMI (assert NMI line)
    harness.state.ppu_nmi_active = true;
    harness.state.cpu.nmi_line = true;

    // This should trigger NMI on next CPU tick
    // Step 1: Interrupt detection
    harness.state.tickCpu();
    try expect(harness.state.cpu.state == .interrupt_sequence);
    try expect(harness.state.cpu.instruction_cycle == 0);

    const pc_before = harness.state.cpu.pc;

    // Step 2: Cycle 0 - Dummy read
    harness.state.tickCpu();
    try expect(harness.state.cpu.instruction_cycle == 1);
    try expect(harness.state.cpu.pc == pc_before); // PC unchanged

    // Step 3: Cycle 1 - Push PCH
    const sp_before = harness.state.cpu.sp;
    harness.state.tickCpu();
    try expect(harness.state.cpu.instruction_cycle == 2);
    try expect(harness.state.bus.ram[0x01FD - 0x0000] == 0x80); // PCH = $80
    try expect(harness.state.cpu.sp == sp_before - 1);

    // Step 4: Cycle 2 - Push PCL
    harness.state.tickCpu();
    try expect(harness.state.cpu.instruction_cycle == 3);
    try expect(harness.state.bus.ram[0x01FC - 0x0000] == 0x00); // PCL = $00
    try expect(harness.state.cpu.sp == sp_before - 2);

    // Step 5: Cycle 3 - Push P (B=0)
    harness.state.tickCpu();
    try expect(harness.state.cpu.instruction_cycle == 4);
    const stacked_p = harness.state.bus.ram[0x01FB - 0x0000];
    try expect((stacked_p & 0x10) == 0); // B flag clear
    try expect((stacked_p & 0x20) != 0); // Unused flag set
    try expect((stacked_p & 0x01) != 0); // Carry preserved
    try expect(harness.state.cpu.sp == sp_before - 3);

    // Step 6: Cycle 4 - Fetch vector low, set I flag
    harness.state.tickCpu();
    try expect(harness.state.cpu.instruction_cycle == 5);
    try expect(harness.state.cpu.operand_low == 0x00);
    try expect(harness.state.cpu.p.interrupt == true); // I flag set

    // Step 7: Cycle 5 - Fetch vector high
    harness.state.tickCpu();
    try expect(harness.state.cpu.instruction_cycle == 6);
    try expect(harness.state.cpu.operand_high == 0xC0);

    // Step 8: Cycle 6 - Jump to handler
    harness.state.tickCpu();
    try expect(harness.state.cpu.pc == 0xC000); // Jumped to handler
    try expect(harness.state.cpu.state == .fetch_opcode); // Back to fetch
    try expect(harness.state.cpu.instruction_cycle == 0);
    try expect(harness.state.cpu.pending_interrupt == .none); // Cleared
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

    // Manually trigger VBlank
    harness.state.ppu.status.vblank = true;
    harness.state.ppu_nmi_active = true;
    harness.state.cpu.nmi_line = true;

    // Step CPU - should detect NMI
    harness.state.tickCpu();
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

    // Manually trigger VBlank
    harness.state.ppu.status.vblank = true;
    harness.state.ppu_nmi_active = false; // NMI not active because nmi_enable=false
    harness.state.cpu.nmi_line = false;

    // Step CPU - should NOT detect NMI
    harness.state.tickCpu();
    try expect(harness.state.cpu.pending_interrupt == .none);
    // Note: State will have transitioned from fetch_opcode to executing NOP
    // We only care that NMI didn't trigger
}
