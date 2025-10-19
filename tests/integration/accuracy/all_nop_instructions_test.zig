//! AccuracyCoin Accuracy Test: ALL NOP INSTRUCTIONS (FAIL 1)
//!
//! This test verifies that all unofficial NOP instruction variants are implemented correctly.
//! Unofficial NOPs must:
//! - Have the correct number of operands (2 or 3 bytes total)
//! - NOT update CPU flags
//! - NOT update memory
//! - NOT update registers (A, X, Y, SP)
//! - Perform dummy reads (which can have side effects like clearing VBlank flag)
//!
//! Tested NOP Opcodes:
//! - $04, $44, $64 (Zero Page - 2 bytes)
//! - $0C (Absolute - 3 bytes)
//! - $14, $34, $54, $74, $D4, $F4 (Zero Page,X - 2 bytes)
//! - $1C, $3C, $5C, $7C, $DC, $FC (Absolute,X - 3 bytes)
//! - $1A, $3A, $5A, $7A, $DA, $FA (Implied - 1 byte)
//! - $80, $82, $89, $C2, $E2 (Immediate - 2 bytes)
//!
//! Result Address: $047D (result_AllNOPs)
//! Expected: $00 = PASS (all NOP variants correct)
//! Current:  $01 = FAIL (some NOPs have wrong operand count or side effects)

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

test "Accuracy: ALL NOP INSTRUCTIONS (AccuracyCoin FAIL 1)" {
    const cart = RAMBO.CartridgeType.load(testing.allocator, "tests/data/AccuracyCoin.nes") catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    var h = try Harness.init();
    defer h.deinit();

    h.loadNromCartridge(cart);
    h.state.reset();
    h.state.ppu.warmup_complete = true;

    // Set PC to TEST_AllNOPs
    h.state.cpu.pc = 0xE4E3;
    h.state.cpu.state = .fetch_opcode;
    h.state.cpu.instruction_cycle = 0;
    h.state.cpu.sp = 0xFD;

    // Initialize variables
    h.state.bus.ram[0x10] = 0x00; // ErrorCode
    h.state.bus.ram[0x047D] = 0x80; // Result (RUNNING)

    // Run test (this test does VBlank waits, needs more cycles)
    const max_cycles: usize = 5_000_000;
    var cycles: usize = 0;
    while (cycles < max_cycles) : (cycles += 1) {
        h.state.tick();
        const result = h.state.bus.ram[0x047D];
        if (result != 0x80) break;
    }

    const result = h.state.bus.ram[0x047D];

    // EXPECTED: $00 = PASS
    // ACTUAL: $01 = FAIL (NOP operand count or behavior incorrect)
    try testing.expectEqual(@as(u8, 0x00), result);
}
