//! EmulationState and MasterClock Tests
//!
//! Tests relocated from src/emulation/State.zig as part of Milestone 1.6
//! Phase 1: Safe Decomposition - Test Relocation

const std = @import("std");
const testing = std.testing;

const RAMBO = @import("RAMBO");
const Config = RAMBO.Config;
const EmulationState = RAMBO.EmulationState.EmulationState;
const MasterClock = RAMBO.EmulationState.MasterClock;

// ============================================================================
// MasterClock Tests
// ============================================================================

test "MasterClock: PPU to CPU cycle conversion" {
    var clock = MasterClock{};

    clock.ppu_cycles = 0;
    try testing.expectEqual(@as(u64, 0), clock.cpuCycles());

    clock.ppu_cycles = 3;
    try testing.expectEqual(@as(u64, 1), clock.cpuCycles());

    clock.ppu_cycles = 6;
    try testing.expectEqual(@as(u64, 2), clock.cpuCycles());

    clock.ppu_cycles = 100;
    try testing.expectEqual(@as(u64, 33), clock.cpuCycles());
}

test "MasterClock: scanline calculation NTSC" {
    var clock = MasterClock{};
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    config.ppu.variant = .rp2c02g_ntsc;

    // Scanline 0, dot 0
    clock.ppu_cycles = 0;
    try testing.expectEqual(@as(u16, 0), clock.scanline());
    try testing.expectEqual(@as(u16, 0), clock.dot());

    // Scanline 0, dot 100
    clock.ppu_cycles = 100;
    try testing.expectEqual(@as(u16, 0), clock.scanline());
    try testing.expectEqual(@as(u16, 100), clock.dot());

    // Scanline 1, dot 0 (after 341 cycles)
    clock.ppu_cycles = 341;
    try testing.expectEqual(@as(u16, 1), clock.scanline());
    try testing.expectEqual(@as(u16, 0), clock.dot());

    // Scanline 10, dot 50
    clock.ppu_cycles = (10 * 341) + 50;
    try testing.expectEqual(@as(u16, 10), clock.scanline());
    try testing.expectEqual(@as(u16, 50), clock.dot());

    // VBlank start: Scanline 241, dot 1
    clock.ppu_cycles = (241 * 341) + 1;
    try testing.expectEqual(@as(u16, 241), clock.scanline());
    try testing.expectEqual(@as(u16, 1), clock.dot());
}

test "MasterClock: frame calculation NTSC" {
    var clock = MasterClock{};
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    config.ppu.variant = .rp2c02g_ntsc;

    // Frame 0
    clock.ppu_cycles = 0;
    try testing.expectEqual(@as(u64, 0), clock.frame());

    // Still frame 0 (one cycle before frame boundary)
    clock.ppu_cycles = 89_341;
    try testing.expectEqual(@as(u64, 0), clock.frame());

    // Frame 1 (262 scanlines × 341 cycles = 89,342 cycles)
    clock.ppu_cycles = 89_342;
    try testing.expectEqual(@as(u64, 1), clock.frame());

    // Frame 10
    clock.ppu_cycles = 89_342 * 10;
    try testing.expectEqual(@as(u64, 10), clock.frame());
}

// ============================================================================
// EmulationState Tests
// ============================================================================

test "EmulationState: initialization" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    const state = EmulationState.init(&config);

    try testing.expectEqual(@as(u64, 0), state.clock.ppu_cycles);
    try testing.expect(!state.frame_complete);
    try testing.expectEqual(@as(u8, 0), state.bus.open_bus);
    try testing.expect(!state.dma.active);
}

test "EmulationState: tick advances PPU clock" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    state.power_on();

    // UPDATED: Initial state is ppu_cycles = 2 (Phase 2 for AccuracyCoin compatibility)
    // See MasterClock.reset() for details on CPU/PPU phase alignment
    try testing.expectEqual(@as(u64, 2), state.clock.ppu_cycles);

    // Tick once
    state.tick();
    try testing.expectEqual(@as(u64, 3), state.clock.ppu_cycles);

    // Tick 10 times
    for (0..10) |_| {
        state.tick();
    }
    try testing.expectEqual(@as(u64, 13), state.clock.ppu_cycles);
}

test "EmulationState: CPU ticks every 3 PPU cycles" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    state.power_on();

    // UPDATED: Initial state is ppu_cycles = 2 (Phase 2)
    // CPU ticks when (ppu_cycles % 3 == 0), so CPU ticks on cycle 3, 6, 9, etc.
    const initial_cpu_cycles = state.clock.cpuCycles();

    // Initial state: at cycle 2, CPU has not ticked yet
    try testing.expectEqual(@as(u64, 2), state.clock.ppu_cycles);

    // Tick once (cycle 2 → 3): CPU SHOULD tick (3 % 3 == 0)
    state.tick();
    try testing.expectEqual(@as(u64, 3), state.clock.ppu_cycles);
    try testing.expectEqual(initial_cpu_cycles + 1, state.clock.cpuCycles());

    // Tick twice more (cycle 3 → 4 → 5): CPU should NOT tick
    state.tick();
    state.tick();
    try testing.expectEqual(@as(u64, 5), state.clock.ppu_cycles);
    try testing.expectEqual(initial_cpu_cycles + 1, state.clock.cpuCycles());

    // Tick once more (5 → 6): CPU SHOULD tick (6 % 3 == 0)
    state.tick();
    try testing.expectEqual(@as(u64, 6), state.clock.ppu_cycles);
    try testing.expectEqual(initial_cpu_cycles + 2, state.clock.cpuCycles());
}

test "EmulationState: emulateCpuCycles advances correctly" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    state.power_on();

    // UPDATED: Starting at ppu_cycles = 2 (Phase 2)
    // Emulate 10 CPU cycles. Each CPU cycle is 3 PPU cycles, but we need to account
    // for the initial offset. From cycle 2, we need to reach a state where 10 CPU
    // ticks have occurred. First CPU tick at cycle 3, so 10 CPU cycles = 30 PPU cycles
    // from the first CPU tick, but we start at 2, so total is 2 + 30 = 32.
    // Wait, let me recalculate: emulateCpuCycles runs until 10 CPU ticks happen.
    // Starting at ppu=2, first tick at ppu=3, 10th tick at ppu=3+27=30.
    // But the function returns number of PPU cycles ELAPSED, not absolute position.
    const ppu_cycles = state.emulateCpuCycles(10);
    try testing.expectEqual(@as(u64, 28), ppu_cycles);  // UPDATED: 30 - 2 = 28 cycles elapsed
    try testing.expectEqual(@as(u64, 30), state.clock.ppu_cycles);  // Absolute position
    try testing.expectEqual(@as(u64, 10), state.clock.cpuCycles());
}

test "EmulationState: VBlank timing at scanline 241, dot 1" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    config.ppu.variant = .rp2c02g_ntsc;

    var state = EmulationState.init(&config);
    state.power_on();

    // Advance to scanline 241, dot 0 (just before VBlank)
    // MasterClock: scanline 241, dot 0 = (241 * 341) + 0 PPU cycles
    state.clock.ppu_cycles = (241 * 341);
    try testing.expect(!state.frame_complete);

    // Tick once to reach scanline 241, dot 1 (VBlank start)
    state.tick();
    try testing.expectEqual(@as(u16, 241), state.clock.scanline());
    try testing.expectEqual(@as(u16, 1), state.clock.dot());

    // UPDATED: After tick() completes, we're at (241, 1) and applyPpuCycleResult() has run.
    // The VBlank flag IS visible because we're reading AFTER the cycle completed.
    // Hardware sub-cycle ordering happens WITHIN a single tick, but after tick returns,
    // both CPU execution and PPU flag updates have completed.
    const status = state.busRead(0x2002);
    try testing.expect((status & 0x80) != 0); // UPDATED: Flag IS visible after tick

    // Second read clears the flag
    const status2 = state.busRead(0x2002);
    try testing.expect((status2 & 0x80) == 0); // Second read sees CLEAR
}

test "EmulationState: odd frame skip when rendering enabled" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    config.ppu.variant = .rp2c02g_ntsc;

    var state = EmulationState.init(&config);
    state.power_on();

    // Set up odd frame with rendering enabled
    state.odd_frame = true;
    state.rendering_enabled = true;

    // Advance to scanline 261, dot 339 (skip occurs FROM here on odd frames)
    const target_cycle = (261 * 341) + 339;
    state.clock.ppu_cycles = target_cycle;

    // Current position: scanline 261, dot 339
    try testing.expectEqual(@as(u16, 261), state.clock.scanline());
    try testing.expectEqual(@as(u16, 339), state.clock.dot());

    // Tick should skip dot 340, advancing by 2 PPU cycles (339→340→0)
    state.tick();

    // After tick: Should be at scanline 0, dot 0 (skipped dot 340)
    try testing.expectEqual(@as(u16, 0), state.clock.scanline());
    try testing.expectEqual(@as(u16, 0), state.clock.dot());

    // Odd frame should be cleared (next frame is even)
    try testing.expect(!state.odd_frame);
}

test "EmulationState: even frame does not skip dot" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    config.ppu.variant = .rp2c02g_ntsc;

    var state = EmulationState.init(&config);
    state.power_on();

    // Set up even frame with rendering enabled
    state.odd_frame = false; // Even frame
    state.rendering_enabled = true;

    // Advance to scanline 261, dot 339 (same position as odd frame test)
    const target_cycle = (261 * 341) + 339;
    state.clock.ppu_cycles = target_cycle;

    // Tick should NOT skip (even frame), advancing by 1 PPU cycle normally
    state.tick();

    // After tick: Should be at scanline 261, dot 340 (normal progression, no skip)
    try testing.expectEqual(@as(u16, 261), state.clock.scanline());
    try testing.expectEqual(@as(u16, 340), state.clock.dot());
}

test "EmulationState: odd frame without rendering does not skip" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    config.ppu.variant = .rp2c02g_ntsc;

    var state = EmulationState.init(&config);
    state.power_on();

    // Set up odd frame WITHOUT rendering enabled
    state.odd_frame = true;
    state.rendering_enabled = false; // Rendering disabled

    // Advance to scanline 261, dot 339
    const target_cycle = (261 * 341) + 339;
    state.clock.ppu_cycles = target_cycle;

    // Tick should NOT skip (rendering disabled), advancing by 1 PPU cycle normally
    state.tick();

    // After tick: Should be at scanline 261, dot 340 (normal progression, no skip)
    try testing.expectEqual(@as(u16, 261), state.clock.scanline());
    try testing.expectEqual(@as(u16, 340), state.clock.dot());
}

test "EmulationState: frame toggle at scanline boundary" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    config.ppu.variant = .rp2c02g_ntsc;

    var state = EmulationState.init(&config);
    state.power_on();

    // Start with even frame (odd_frame = false)
    try testing.expect(!state.odd_frame);
    try testing.expectEqual(@as(u64, 0), state.clock.frame());

    // Advance to end of scanline 261 (last scanline of frame)
    state.clock.ppu_cycles = (261 * 341) + 340;

    // Tick to cross into scanline 0 of next frame
    state.tick();

    // Frame should have incremented
    try testing.expectEqual(@as(u64, 1), state.clock.frame());
    // Should now be odd frame
    try testing.expect(state.odd_frame);

    // Advance to next frame boundary
    state.clock.ppu_cycles = (261 * 341) + 340 + 89342;

    state.tick();

    // Should be back to even frame
    try testing.expect(!state.odd_frame);
}
