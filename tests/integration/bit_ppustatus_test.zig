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

    // Setup: BIT $2002 instruction at 0x0000
    h.loadRam(&[_]u8{ 0x2C, 0x02, 0x20 }, 0x0000); // BIT $2002
    h.setupCpuExecution(0x0000);

    // --- Test 1: VBlank is clear ---
    h.state.cpu.p.negative = true; // Pre-set flag to ensure it gets cleared
    h.tickCpu(4); // BIT abs takes 4 CPU cycles
    try testing.expect(!h.state.cpu.p.negative); // N flag should be cleared

    // --- Test 2: VBlank is set ---
    // Align so BIT's memory read happens exactly at 241.1
    // BIT absolute reads on CPU cycle 4 = +9 PPU cycles from instruction start
    // To read at 241.1 (PPU cycle 82182), start at 82173 = scanline 240, dot 333
    h.state.vblank_ledger.reset(); // Clean slate for this test
    h.seekToCpuBoundary(240, 333);
    h.setupCpuExecution(0x0000);
    h.tickCpu(4); // BIT abs takes 4 CPU cycles
    try testing.expect(h.state.cpu.p.negative); // N flag should be set

    // --- Test 3: Mid-VBlank clear-on-read behavior ---
    // Advance past current frame, then seek to mid-VBlank in next frame
    const current_frame = h.state.clock.frame();
    while (h.state.clock.frame() <= current_frame) {
        h.tick(1);
    }
    // Now in next frame - seek to mid-VBlank (well after 241.1)
    // Don't reset ledger - we want to preserve VBlank state from frame crossing
    h.seekToCpuBoundary(245, 100); // Seek to mid-VBlank in this frame
    h.setupCpuExecution(0x0000);
    h.tickCpu(4); // First read during mid-VBlank (4 CPU cycles)
    try testing.expect(h.state.cpu.p.negative); // N set
    // Next BIT should see cleared flag
    h.setupCpuExecution(0x0000);
    h.tickCpu(4); // 4 CPU cycles
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
    h.setupCpuExecution(0x0000);

    // --- Loop while VBlank is clear ---
    // Ensure branch is taken at least once (pc not advanced past BPL)
    h.tickCpu(10); // Run a few loops (10 CPU cycles)
    try testing.expect(h.state.cpu.pc != 0x0005);

    // --- Set VBlank and see if it exits ---
    // Align so BIT's read occurs at 241.1 again
    // BIT absolute reads on CPU cycle 4 = +9 PPU cycles from instruction start
    h.state.vblank_ledger.reset(); // Clean slate for VBlank test
    h.seekToCpuBoundary(240, 333);
    h.setupCpuExecution(0x0000);
    h.tickCpu(4); // BIT takes 4 CPU cycles
    try testing.expect(h.state.cpu.p.negative); // N flag is set

    // Execute BPL (2 CPU cycles, branch NOT taken)
    h.tickCpu(2);

    // PC should have advanced past BPL
    try testing.expect(h.state.cpu.pc == 0x0005);
}
