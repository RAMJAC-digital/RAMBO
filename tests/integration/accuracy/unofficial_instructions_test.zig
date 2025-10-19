//! AccuracyCoin Accuracy Test: UNOFFICIAL INSTRUCTIONS (FAIL A)
//!
//! This test verifies that unofficial/undocumented 6502 opcodes are implemented.
//! The NES 6502 CPU has 151 documented opcodes and 105 unofficial opcodes.
//! Many games rely on these unofficial opcodes, so they must be implemented.
//!
//! Tested Unofficial Opcodes:
//! - SLO (ASL + ORA)
//! - ANC (AND + copy N to C)
//! - RLA (ROL + AND)
//! - ASR (AND + LSR)
//! - ARR (AND + ROR)
//! - ANE/XAA (unstable: (A | CONST) & X & imm)
//! - LXA/LAX (unstable: (A | CONST) & imm)
//! - AXS/SBX (A & X - imm)
//! - SBC (unofficial $EB same as legal $E9)
//! - NOP variants (various addressing modes)
//!
//! Result Address: $0402 (result_UnofficialInstr)
//! Expected: $00 = PASS (all unofficial opcodes work)
//! Current:  $0A = FAIL (10 subtests fail - opcodes not implemented correctly)

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

test "Accuracy: UNOFFICIAL INSTRUCTIONS (AccuracyCoin FAIL A)" {
    const cart = RAMBO.CartridgeType.load(testing.allocator, "tests/data/AccuracyCoin.nes") catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    var h = try Harness.init();
    defer h.deinit();

    h.loadNromCartridge(cart);
    h.state.reset();
    h.state.ppu.warmup_complete = true;

    // Set PC to TEST_UnofficialInstructionsExist
    h.state.cpu.pc = 0xA557;
    h.state.cpu.state = .fetch_opcode;
    h.state.cpu.instruction_cycle = 0;
    h.state.cpu.sp = 0xFD;

    // Initialize variables
    h.state.bus.ram[0x10] = 0x00; // ErrorCode
    h.state.bus.ram[0x0402] = 0x80; // Result (RUNNING)

    // Run test
    const max_cycles: usize = 1_000_000;
    var cycles: usize = 0;
    while (cycles < max_cycles) : (cycles += 1) {
        h.state.tick();
        const result = h.state.bus.ram[0x0402];
        if (result != 0x80) break;
    }

    const result = h.state.bus.ram[0x0402];

    // EXPECTED: $00 = PASS
    // ACTUAL: $0A = FAIL (10 unofficial opcodes not working)
    try testing.expectEqual(@as(u8, 0x00), result);
}
