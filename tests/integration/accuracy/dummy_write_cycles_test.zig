//! AccuracyCoin Accuracy Test: DUMMY WRITE CYCLES
//!
//! This test verifies that Read-Modify-Write (RMW) instructions perform dummy writes.
//! RMW instructions (ASL, LSR, ROL, ROR, INC, DEC) must write the original value back
//! to memory BEFORE writing the modified value. This is cycle 5 of a 6-cycle RMW instruction.
//!
//! Hardware Behavior:
//! - Cycle 4: Read value from memory
//! - Cycle 5: Write ORIGINAL value back (dummy write) ← CRITICAL
//! - Cycle 6: Write MODIFIED value
//!
//! This is visible to memory-mapped I/O (like PPU registers) and is tested by AccuracyCoin
//! using PPU $2006 writes that affect the internal VRAM address pointer.
//!
//! Test Entry Point: 0xA318 (TEST_DummyWrites)
//! Result Address: $0407 (result_DummyWrites)
//! Expected: $00 = PASS (RMW dummy writes correctly implemented)
//! ROM Screenshot (2025-10-19): PASS

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

test "Accuracy: DUMMY WRITE CYCLES (AccuracyCoin)" {
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

    // 1. Clear RAM page 5 ($0500-$05FF) - AccuracyCoin's scratch space
    var addr: u16 = 0x0500;
    while (addr < 0x0600) : (addr += 1) {
        h.state.bus.ram[addr & 0x07FF] = 0x00;
    }

    // 2. Initialize IRQ handler in RAM (simple RTI to prevent BRK loops)
    h.state.bus.ram[0x0600] = 0x40; // RTI opcode

    // 3. Initialize zero-page variables
    h.state.bus.ram[0x10] = 0x00; // ErrorCode
    h.state.bus.ram[0x50] = 0x00; // Scratch
    h.state.bus.ram[0xF0] = 0x00; // PPUCTRL_COPY
    h.state.bus.ram[0xF1] = 0x00; // PPUMASK_COPY

    // 4. Synchronize to VBlank start (frame boundary)
    h.seekToScanlineDot(241, 1);

    // 5. Set PC to TEST_DummyWrites entry point
    h.state.cpu.pc = 0xA318;
    h.state.cpu.state = .fetch_opcode;
    h.state.cpu.instruction_cycle = 0;
    h.state.cpu.sp = 0xFD;

    // 6. Initialize result to RUNNING
    h.state.bus.ram[0x0407] = 0x80;

    // === Run test ===

    const max_cycles: usize = 10_000_000; // Full frame budget
    var cycles: usize = 0;

    while (cycles < max_cycles) : (cycles += 1) {
        h.state.tick();
        const result = h.state.bus.ram[0x0407];
        if (result != 0x80) break; // Test completed
    }

    const result = h.state.bus.ram[0x0407];

    // EXPECTED: $00 = PASS (ROM screenshot shows PASS)
    try testing.expectEqual(@as(u8, 0x00), result);
}
