//! Minimal test for BIT $2002 instruction with VBlank flag
//!
//! This test isolates the exact sequence that should occur when waiting for VBlank:
//! 1. Execute BIT $2002 when VBlank is clear (N flag should be 0)
//! 2. Execute BIT $2002 when VBlank is set (N flag should be 1, VBlank should clear)

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config;

test "BIT $2002: N flag reflects VBlank state before clearing" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    state.reset();

    std.debug.print("\n=== Test: BIT $2002 with VBlank ===\n", .{});

    // Setup: BIT $2002 instruction at 0x0000
    state.bus.ram[0] = 0x2C; // BIT absolute
    state.bus.ram[1] = 0x02; // Low byte of $2002
    state.bus.ram[2] = 0x20; // High byte of $2002
    state.cpu.pc = 0x0000;

    // Test 1: VBlank clear
    std.debug.print("\nTest 1: VBlank CLEAR\n", .{});
    state.ppu.status.vblank = false;

    // Execute BIT $2002 (4 cycles)
    var cycles: usize = 0;
    while (cycles < 12) : (cycles += 1) { // 12 PPU cycles = 4 CPU cycles
        state.tick();
    }

    std.debug.print("  After BIT: N={}, VBlank={}\n", .{ state.cpu.p.negative, state.ppu.status.vblank });
    try testing.expect(!state.cpu.p.negative); // N should be 0
    try testing.expect(!state.ppu.status.vblank); // VBlank should still be clear

    // Test 2: VBlank set
    std.debug.print("\nTest 2: VBlank SET\n", .{});
    state.cpu.pc = 0x0000; // Reset PC
    state.ppu.status.vblank = true;

    cycles = 0;
    while (cycles < 12) : (cycles += 1) { // 12 PPU cycles = 4 CPU cycles
        state.tick();
    }

    std.debug.print("  After BIT: N={}, VBlank={}\n", .{ state.cpu.p.negative, state.ppu.status.vblank });
    try testing.expect(state.cpu.p.negative); // N should be 1 (bit 7 was set)
    try testing.expect(!state.ppu.status.vblank); // VBlank should be cleared by read

    std.debug.print("\n✓ BIT $2002 correctly sets N flag and clears VBlank\n", .{});
}

test "BIT $2002 then BPL: Loop should exit when VBlank set" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    state.reset();

    std.debug.print("\n=== Test: BIT $2002 + BPL loop exit ===\n", .{});

    // Setup: BIT $2002, BPL -5 loop at 0x0000
    state.bus.ram[0] = 0x2C; // BIT absolute
    state.bus.ram[1] = 0x02; // $2002
    state.bus.ram[2] = 0x20;
    state.bus.ram[3] = 0x10; // BPL relative
    state.bus.ram[4] = 0xFB; // -5 (back to 0x0000)
    state.cpu.pc = 0x0000;

    // Set VBlank
    state.ppu.status.vblank = true;
    std.debug.print("  VBlank set before loop\n", .{});

    // Execute BIT $2002 (4 CPU cycles = 12 PPU cycles)
    var ppu_cycles: usize = 0;
    while (ppu_cycles < 12) : (ppu_cycles += 1) {
        state.tick();
    }

    std.debug.print("  After BIT: N={}, PC=0x{x:0>4}\n", .{ state.cpu.p.negative, state.cpu.pc });
    try testing.expect(state.cpu.p.negative); // N should be 1

    // Execute BPL (2 CPU cycles = 6 PPU cycles, branch not taken)
    ppu_cycles = 0;
    while (ppu_cycles < 6) : (ppu_cycles += 1) {
        state.tick();
    }

    std.debug.print("  After BPL: PC=0x{x:0>4}\n", .{state.cpu.pc});

    // PC should have advanced past BPL (not branched)
    try testing.expect(state.cpu.pc == 0x0005); // BPL not taken, PC moved forward

    std.debug.print("\n✓ BPL correctly did NOT branch when N=1\n", .{});
}
