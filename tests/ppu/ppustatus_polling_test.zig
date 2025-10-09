//! PPUSTATUS Polling Test
//!
//! Verifies that VBlank flag can be reliably detected by tight polling loops.
//!
//! Hardware Reference: https://www.nesdev.org/wiki/PPU_frame_timing
//! - VBlank flag set at scanline 241, dot 1
//! - VBlank flag cleared at scanline 261, dot 1
//! - Duration: 6820 PPU clocks (20 scanlines) = ~2273 CPU cycles
//! - Reading $2002 clears VBlank flag immediately
//!
//! Critical test: Can a CPU polling loop detect VBlank before clearing it?

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

test "PPUSTATUS Polling: VBlank flag persists for 20 scanlines" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;

    // Advance to scanline 241, dot 1 (VBlank sets)
    harness.seekToScanlineDot(241, 1);
    try testing.expect(harness.state.ppu.status.vblank);

    // VBlank should persist until scanline 261, dot 1
    // Let's verify it's still set at various points

    // Check at scanline 250 (middle of VBlank)
    harness.seekToScanlineDot(250, 100);
    try testing.expect(harness.state.ppu.status.vblank);

    // Check at scanline 260 (near end of VBlank)
    harness.seekToScanlineDot(260, 340);
    try testing.expect(harness.state.ppu.status.vblank);

    // Check at scanline 261, dot 0 (one cycle before clear)
    harness.seekToScanlineDot(261, 0);
    try testing.expect(harness.state.ppu.status.vblank);

    // Check at scanline 261, dot 1 (should be cleared)
    harness.seekToScanlineDot(261, 1);
    try testing.expect(!harness.state.ppu.status.vblank);
}

test "PPUSTATUS Polling: Reading $2002 clears VBlank immediately" {
    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;

    // Advance to middle of VBlank period
    harness.seekToScanlineDot(245, 100);
    try testing.expect(harness.state.ppu.status.vblank);

    // Read $2002
    const value = harness.state.busRead(0x2002);

    // Value should have bit 7 set (VBlank was active)
    try testing.expect((value & 0x80) != 0);

    // But VBlank flag should now be cleared
    try testing.expect(!harness.state.ppu.status.vblank);
}

test "PPUSTATUS Polling: Tight loop can detect VBlank" {
    // This simulates the exact pattern used by games like Bomberman:
    // Loop: BIT $2002 / BPL Loop

    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;

    // Start BEFORE VBlank
    harness.seekToScanlineDot(240, 340);
    try testing.expect(!harness.state.ppu.status.vblank);

    // Simulate tight polling loop
    // Each iteration: 4 CPU cycles (BIT $2002 = 4 cycles, BPL = 0 cycles when not taken)
    // VBlank duration: ~2273 CPU cycles
    // So we should be able to poll ~568 times before VBlank ends

    var poll_count: usize = 0;
    var vblank_detected = false;
    const max_polls: usize = 3000; // Safety limit (more than enough)

    while (poll_count < max_polls and harness.getScanline() < 262) {
        // Read PPUSTATUS (BIT $2002)
        const status = harness.state.busRead(0x2002);

        // Check bit 7 (VBlank flag)
        if ((status & 0x80) != 0) {
            vblank_detected = true;
            break;
        }

        // Advance 4 CPU cycles (BIT instruction takes 4 cycles)
        // 4 CPU cycles = 12 PPU cycles
        var i: usize = 0;
        while (i < 12) : (i += 1) {
            harness.state.tick();
        }

        poll_count += 1;
    }

    // We MUST detect VBlank
    try testing.expect(vblank_detected);

    // We should detect it relatively quickly (within first frame after VBlank starts)
    try testing.expect(poll_count < 1000);
}

test "PPUSTATUS Polling: Multiple polls within VBlank period" {
    // Verify that even if we poll MULTIPLE times during VBlank,
    // at least ONE poll will succeed in detecting it

    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;

    // Start just before VBlank
    harness.seekToScanlineDot(240, 340);

    var detected_count: usize = 0;
    var poll_count: usize = 0;

    // Poll continuously through VBlank period
    // From scanline 240.340 to 261.10 (well into pre-render)
    while (harness.getScanline() <= 261 and harness.getDot() < 20) {
        const status = harness.state.busRead(0x2002);

        if ((status & 0x80) != 0) {
            detected_count += 1;
        }

        poll_count += 1;

        // Advance by 1 CPU instruction worth of time
        // BIT $2002 takes 4 CPU cycles = 12 PPU cycles
        var i: usize = 0;
        while (i < 12) : (i += 1) {
            harness.state.tick();
        }
    }

    // We should have detected VBlank at least once
    // Note: After first detection, subsequent reads will see it as cleared
    try testing.expect(detected_count >= 1);

    // We should have polled many times (VBlank lasts ~20 scanlines)
    try testing.expect(poll_count > 10);
}

test "PPUSTATUS Polling: Race condition at exact VBlank set point" {
    // Test the edge case mentioned in nesdev.org:
    // "Reading on the same PPU clock or one later reads it as set,
    //  clears it, and suppresses the NMI"

    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;

    // Position at scanline 241, dot 0 (one cycle before VBlank)
    harness.seekToScanlineDot(241, 0);
    try testing.expect(!harness.state.ppu.status.vblank);

    // Tick to dot 1 - VBlank sets
    harness.state.tick();
    try testing.expect(harness.state.ppu.status.vblank);

    // Immediately read $2002 (same frame as VBlank set)
    const status = harness.state.busRead(0x2002);

    // Should read as set (bit 7 = 1)
    try testing.expect((status & 0x80) != 0);

    // But flag is now cleared
    try testing.expect(!harness.state.ppu.status.vblank);
}

test "PPUSTATUS Polling: Can detect VBlank even with frequent reads" {
    // Even if we read $2002 very frequently (every few CPU cycles),
    // we should still catch VBlank because it lasts ~2273 CPU cycles

    var harness = try Harness.init();
    defer harness.deinit();

    harness.state.ppu.warmup_complete = true;

    // Start well before VBlank
    harness.seekToScanlineDot(235, 0);

    var vblank_detected = false;
    var iterations: usize = 0;
    const max_iterations: usize = 10000;

    // Poll every 2 CPU cycles (6 PPU cycles) - very aggressive
    while (!vblank_detected and iterations < max_iterations) {
        const status = harness.state.busRead(0x2002);

        if ((status & 0x80) != 0) {
            vblank_detected = true;
            break;
        }

        // Advance 2 CPU cycles = 6 PPU cycles
        harness.state.tick();
        harness.state.tick();
        harness.state.tick();
        harness.state.tick();
        harness.state.tick();
        harness.state.tick();

        iterations += 1;
    }

    try testing.expect(vblank_detected);
    try testing.expect(iterations < max_iterations);
}

test "PPUSTATUS Polling: BIT instruction timing - when does read occur?" {
    // This test verifies EXACTLY when the bus read of $2002 happens during BIT $2002 execution
    // BIT $2002 takes 4 CPU cycles = 12 PPU cycles
    // The actual read MUST happen on the 4th CPU cycle (cycle 12 in PPU terms)

    var harness = try Harness.init();
    defer harness.deinit();

    // Load BIT $2002 instruction at $8000
    var test_ram = [_]u8{0} ** 0x8000;
    test_ram[0] = 0x2C; // BIT absolute (opcode 0x2C)
    test_ram[1] = 0x02; // Low byte of address ($2002)
    test_ram[2] = 0x20; // High byte of address ($2002)
    test_ram[3] = 0xEA; // NOP (next instruction)
    harness.state.bus.test_ram = &test_ram;

    harness.state.reset();
    harness.state.ppu.warmup_complete = true;

    // Position just before VBlank
    harness.seekToScanlineDot(241, 0);
    try testing.expect(!harness.state.ppu.status.vblank);

    // Tick to scanline 241, dot 1 - VBlank sets
    harness.state.tick();
    try testing.expect(harness.state.ppu.status.vblank);

    // Now VBlank is set. Execute BIT $2002 instruction cycle by cycle
    // According to src/emulation/State.zig:
    // CPU Cycle 1: fetch_opcode - reads 0x2C from PC
    // CPU Cycle 2: fetch_operand_low - reads 0x02 from PC+1
    // CPU Cycle 3: fetch_operand_high - reads 0x20 from PC+2
    // CPU Cycle 4: execute - THIS IS WHEN busRead($2002) HAPPENS

    std.debug.print("\n=== BIT $2002 Execution Trace ===\n", .{});
    std.debug.print("Starting at scanline={}, dot={}\n", .{harness.getScanline(), harness.getDot()});
    std.debug.print("VBlank flag: {}\n\n", .{harness.state.ppu.status.vblank});

    // CPU Cycle 1: fetch_opcode (3 PPU ticks)
    std.debug.print("CPU Cycle 1 (fetch_opcode): Before\n", .{});
    std.debug.print("  State: {s}, VBlank: {}\n", .{@tagName(harness.state.cpu.state), harness.state.ppu.status.vblank});
    harness.state.tick();
    harness.state.tick();
    harness.state.tick();
    std.debug.print("  After: State: {s}, VBlank: {}, PC: 0x{X:0>4}\n", .{@tagName(harness.state.cpu.state), harness.state.ppu.status.vblank, harness.state.cpu.pc});

    // CPU Cycle 2: fetch_operand_low (3 PPU ticks)
    std.debug.print("\nCPU Cycle 2 (fetch_operand_low): Before\n", .{});
    std.debug.print("  State: {s}, VBlank: {}\n", .{@tagName(harness.state.cpu.state), harness.state.ppu.status.vblank});
    harness.state.tick();
    harness.state.tick();
    harness.state.tick();
    std.debug.print("  After: State: {s}, VBlank: {}, operand_low: 0x{X:0>2}\n", .{@tagName(harness.state.cpu.state), harness.state.ppu.status.vblank, harness.state.cpu.operand_low});

    // CPU Cycle 3: fetch_operand_high (3 PPU ticks)
    std.debug.print("\nCPU Cycle 3 (fetch_operand_high): Before\n", .{});
    std.debug.print("  State: {s}, VBlank: {}\n", .{@tagName(harness.state.cpu.state), harness.state.ppu.status.vblank});
    harness.state.tick();
    harness.state.tick();
    harness.state.tick();
    std.debug.print("  After: State: {s}, VBlank: {}, operand_high: 0x{X:0>2}\n", .{@tagName(harness.state.cpu.state), harness.state.ppu.status.vblank, harness.state.cpu.operand_high});

    // CPU Cycle 4: execute - THIS IS WHEN $2002 READ HAPPENS (3 PPU ticks)
    std.debug.print("\nCPU Cycle 4 (execute - SHOULD READ $2002 HERE): Before\n", .{});
    std.debug.print("  State: {s}, VBlank: {}\n", .{@tagName(harness.state.cpu.state), harness.state.ppu.status.vblank});
    std.debug.print("  CRITICAL: VBlank MUST be true here for BIT to see it\n", .{});

    const vblank_before_execute = harness.state.ppu.status.vblank;

    harness.state.tick();
    harness.state.tick();
    harness.state.tick();

    std.debug.print("  After: State: {s}, VBlank: {}\n", .{@tagName(harness.state.cpu.state), harness.state.ppu.status.vblank});
    std.debug.print("  CPU N flag (bit 7): {}, V flag (bit 6): {}\n", .{harness.state.cpu.p.negative, harness.state.cpu.p.overflow});

    // The critical assertion: VBlank MUST have been true when the execute cycle ran
    // If VBlank is false here, then the read happened AFTER VBlank was cleared
    try testing.expect(vblank_before_execute);

    // After reading $2002, VBlank should be cleared
    try testing.expect(!harness.state.ppu.status.vblank);

    // CPU N flag should match bit 7 of PPUSTATUS (which was VBlank)
    try testing.expect(harness.state.cpu.p.negative);
}
