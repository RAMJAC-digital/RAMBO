//! CPU Instruction Integration Tests: BIT $2002 with VBlank flag
//!
//! These tests validate CPU instruction interaction with PPUSTATUS register.
//! Unlike register-level tests, these require direct CPU instruction setup
//! and execution to verify proper CPU flag behavior.
//!
//! This test isolates the exact sequence that should occur when waiting for VBlank:
//! 1. Execute BIT $2002 when VBlank is clear (N flag should be 0)
//! 2. Execute BIT $2002 when VBlank is set (N flag should be 1, VBlank should clear)

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Harness = RAMBO.TestHarness.Harness;

test "BIT $2002: N flag reflects VBlank state" {
    var h = try Harness.init();
    defer h.deinit();

    // Setup: BIT $2002 instruction at 0x8000
    h.loadRam(&[_]u8{ 0x2C, 0x02, 0x20 }, 0x0000); // BIT $2002
    h.state.cpu.pc = 0x0000;

    // --- Test 1: VBlank is clear ---
    h.state.cpu.p.negative = true; // Pre-set flag to ensure it gets cleared
    h.runCpuCycles(4); // BIT abs takes 4 cycles
    try testing.expect(!h.state.cpu.p.negative); // N flag should be cleared

    // --- Test 2: VBlank is set ---
    // Align so BIT's memory read happens exactly at 241.1
    h.seekTo(240, 330);
    h.state.cpu.pc = 0x0000; // Reset PC
    h.state.cpu.state = .fetch_opcode;
    h.state.cpu.instruction_cycle = 0;
    h.state.cpu.p.negative = false; // Pre-clear flag
    h.runCpuCycles(4); // BIT abs takes 4 cycles
    try testing.expect(h.state.cpu.p.negative); // N flag should be set

    // --- Test 3: Mid-VBlank clear-on-read behavior ---
    // First, advance to timing clear to reset race-hold, then into next frame mid-VBlank
    h.seekTo(261, 0);
    h.tick(1); // 261.1: clear VBlank
    // Align to a point well after the set edge in the next frame so a read clears VBlank
    h.seekTo(245, 100);
    h.state.cpu.pc = 0x0000;
    h.state.cpu.state = .fetch_opcode;
    h.state.cpu.instruction_cycle = 0;
    h.runCpuCycles(4); // First read during mid-VBlank
    try testing.expect(h.state.cpu.p.negative); // N set
    // Next BIT should see cleared flag
    h.state.cpu.pc = 0x0000;
    h.state.cpu.state = .fetch_opcode;
    h.state.cpu.instruction_cycle = 0;
    h.runCpuCycles(4);
    try testing.expect(!h.state.cpu.p.negative); // N cleared
}

test "BIT $2002 then BPL: Loop should exit when VBlank set" {
    var h = try Harness.init();
    defer h.deinit();

    // Setup: BIT $2002, BPL -5 loop at 0x0000
    h.loadRam(&[_]u8{
        0x2C, 0x02, 0x20, // BIT $2002
        0x10, 0xFB,       // BPL -5 (jumps back to BIT)
    }, 0x0000);
    h.state.cpu.pc = 0x0000;
    h.state.cpu.state = .fetch_opcode;
    h.state.cpu.instruction_cycle = 0;

    // --- Loop while VBlank is clear ---
    // Ensure branch is taken at least once (pc not advanced past BPL)
    h.runCpuCycles(10); // Run a few loops
    try testing.expect(h.state.cpu.pc != 0x0005);

    // --- Set VBlank and see if it exits ---
    // Align so BIT's read occurs at 241.1 again
    h.seekTo(240, 330);
    h.state.cpu.pc = 0x0000;
    h.state.cpu.state = .fetch_opcode;
    h.state.cpu.instruction_cycle = 0;
    h.runCpuCycles(4);
    try testing.expect(h.state.cpu.p.negative); // N flag is set

    // Execute BPL (2 cycles, branch NOT taken)
    h.runCpuCycles(2);

    // PC should have advanced past BPL
    try testing.expect(h.state.cpu.pc == 0x0005);
}
