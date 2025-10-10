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

    // Initial state
    try testing.expectEqual(@as(u64, 0), state.clock.ppu_cycles);

    // Tick once
    state.tick();
    try testing.expectEqual(@as(u64, 1), state.clock.ppu_cycles);

    // Tick 10 times
    for (0..10) |_| {
        state.tick();
    }
    try testing.expectEqual(@as(u64, 11), state.clock.ppu_cycles);
}

test "EmulationState: CPU ticks every 3 PPU cycles" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    state.power_on();

    const initial_cpu_cycles = state.clock.cpuCycles();

    // Tick 2 PPU cycles (CPU should NOT tick)
    state.tick();
    state.tick();
    try testing.expectEqual(@as(u64, 2), state.clock.ppu_cycles);
    try testing.expectEqual(initial_cpu_cycles, state.clock.cpuCycles());

    // Tick 3rd PPU cycle (CPU SHOULD tick)
    state.tick();
    try testing.expectEqual(@as(u64, 3), state.clock.ppu_cycles);
    try testing.expectEqual(initial_cpu_cycles + 1, state.clock.cpuCycles());

    // Tick 3 more PPU cycles (CPU should tick once more)
    state.tick();
    state.tick();
    state.tick();
    try testing.expectEqual(@as(u64, 6), state.clock.ppu_cycles);
    try testing.expectEqual(initial_cpu_cycles + 2, state.clock.cpuCycles());
}

test "EmulationState: emulateCpuCycles advances correctly" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    state.power_on();

    // Emulate 10 CPU cycles (should be 30 PPU cycles)
    const ppu_cycles = state.emulateCpuCycles(10);
    try testing.expectEqual(@as(u64, 30), ppu_cycles);
    try testing.expectEqual(@as(u64, 30), state.clock.ppu_cycles);
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
    try testing.expect(state.vblank_ledger.isReadableFlagSet(state.clock.ppu_cycles)); // VBlank flag set at 241.1 (NOT frame_complete)
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

    // Advance to scanline 261, dot 340 (last dot of pre-render scanline on odd frame)
    const target_cycle = (261 * 341) + 340;
    state.clock.ppu_cycles = target_cycle;

    // Current position: scanline 261, dot 340
    try testing.expectEqual(@as(u16, 261), state.clock.scanline());
    try testing.expectEqual(@as(u16, 340), state.clock.dot());

    // Tick should skip dot 0 of scanline 0, advancing by 2 PPU cycles instead of 1
    state.tick();

    // After tick: Should be at scanline 0, dot 1 (skipped dot 0)
    try testing.expectEqual(@as(u16, 0), state.clock.scanline());
    try testing.expectEqual(@as(u16, 1), state.clock.dot());

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

    // Advance to scanline 261, dot 340
    const target_cycle = (261 * 341) + 340;
    state.clock.ppu_cycles = target_cycle;

    // Tick should NOT skip, advancing by 1 PPU cycle normally
    state.tick();

    // After tick: Should be at scanline 0, dot 0 (normal progression)
    try testing.expectEqual(@as(u16, 0), state.clock.scanline());
    try testing.expectEqual(@as(u16, 0), state.clock.dot());
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

    // Advance to scanline 261, dot 340
    const target_cycle = (261 * 341) + 340;
    state.clock.ppu_cycles = target_cycle;

    // Tick should NOT skip (rendering disabled), advancing by 1 PPU cycle
    state.tick();

    // After tick: Should be at scanline 0, dot 0 (normal progression)
    try testing.expectEqual(@as(u16, 0), state.clock.scanline());
    try testing.expectEqual(@as(u16, 0), state.clock.dot());
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
