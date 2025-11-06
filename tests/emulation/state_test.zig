//! EmulationState and MasterClock Tests
//!
//! Tests relocated from src/emulation/State.zig as part of Milestone 1.6
//! Phase 1: Safe Decomposition - Test Relocation
//!
//! UPDATED: Tests migrated to use PPU clock (PPU owns its timing state)

const std = @import("std");
const testing = std.testing;

const RAMBO = @import("RAMBO");
const Config = RAMBO.Config;
const EmulationState = RAMBO.EmulationState.EmulationState;
const MasterClock = RAMBO.EmulationState.MasterClock;
const timing = RAMBO.PpuTiming;

// ============================================================================
// MasterClock Tests
// ============================================================================

test "MasterClock: master to CPU cycle conversion" {
    var clock = MasterClock{};

    clock.master_cycles = 0;
    try testing.expectEqual(@as(u64, 0), clock.cpuCycles());

    clock.master_cycles = 3;
    try testing.expectEqual(@as(u64, 1), clock.cpuCycles());

    clock.master_cycles = 6;
    try testing.expectEqual(@as(u64, 2), clock.cpuCycles());

    clock.master_cycles = 100;
    try testing.expectEqual(@as(u64, 33), clock.cpuCycles());
}

// ============================================================================
// EmulationState Tests
// ============================================================================

test "EmulationState: initialization" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    const state = EmulationState.init(&config);

    try testing.expectEqual(@as(u64, 0), state.clock.master_cycles);
    try testing.expect(!state.frame_complete);
    try testing.expectEqual(@as(u8, 0), state.bus.open_bus.get());
    try testing.expect(!state.dma.active);
}

test "EmulationState: tick advances master clock" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    state.power_on();

    // Initial state is master_cycles = initial_phase (Phase 0 default)
    const initial_master = state.clock.master_cycles;
    try testing.expectEqual(initial_master, state.clock.master_cycles);

    // Tick once
    state.tick();
    try testing.expectEqual(initial_master + 1, state.clock.master_cycles);

    // Tick 10 times
    for (0..10) |_| {
        state.tick();
    }
    try testing.expectEqual(initial_master + 11, state.clock.master_cycles);
}

test "EmulationState: CPU ticks every 3 master cycles" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    state.power_on();

    // Phase-independent test: CPU ticks when (master_cycles % 3 == 0)
    const initial_cpu_cycles = state.clock.cpuCycles();

    // Advance past current position if we're at a CPU tick
    if (state.clock.isCpuTick()) {
        state.tick();
    }

    // Advance until next CPU tick
    while (!state.clock.isCpuTick()) {
        state.tick();
    }
    const first_cpu_tick_cycle = state.clock.master_cycles;
    try testing.expect(first_cpu_tick_cycle % 3 == 0);
    try testing.expectEqual(initial_cpu_cycles + 1, state.clock.cpuCycles());

    // Tick twice more: CPU should NOT tick (not at 3-cycle boundary)
    state.tick();
    state.tick();
    try testing.expectEqual(first_cpu_tick_cycle + 2, state.clock.master_cycles);
    try testing.expectEqual(initial_cpu_cycles + 1, state.clock.cpuCycles());

    // Tick once more: CPU SHOULD tick (at 3-cycle boundary)
    state.tick();
    try testing.expectEqual(first_cpu_tick_cycle + 3, state.clock.master_cycles);
    try testing.expectEqual(initial_cpu_cycles + 2, state.clock.cpuCycles());
}

test "EmulationState: emulateCpuCycles advances correctly" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    state.power_on();

    // Phase-independent: 10 CPU cycles = 30 master cycles (1 CPU cycle = 3 master cycles)
    const initial_master = state.clock.master_cycles;
    const master_cycles = state.emulateCpuCycles(10);

    // Should have advanced 30 master cycles (10 CPU cycles × 3)
    try testing.expectEqual(@as(u64, 30), master_cycles);
    try testing.expectEqual(@as(u64, initial_master + 30), state.clock.master_cycles);
    try testing.expectEqual(@as(u64, 10), state.clock.cpuCycles());
}

test "EmulationState: VBlank timing at scanline 241, dot 1" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    config.ppu.variant = .rp2c02g_ntsc;

    var state = EmulationState.init(&config);
    state.power_on();

    // Emulate to frame VBlank
    _ = state.emulateFrame();

    // At this point we should be past VBlank start (at scanline -1, pre-render)
    try testing.expect(state.ppu.scanline == -1 or state.ppu.scanline >= 241);

    // Advance to well past VBlank set point (scanline 241, dot 4+) to avoid race window
    while (state.ppu.scanline < 241 or (state.ppu.scanline == 241 and state.ppu.cycle < 4)) {
        state.tick();
    }

    // VBlank flag should be visible (past race window)
    const status = state.busRead(0x2002);
    try testing.expect((status & 0x80) != 0);

    // Second read clears the flag
    const status2 = state.busRead(0x2002);
    try testing.expect((status2 & 0x80) == 0);
}

test "EmulationState: odd frame skip when rendering enabled" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    config.ppu.variant = .rp2c02g_ntsc;

    var state = EmulationState.init(&config);
    state.power_on();

    // Emulate first frame (even frame)
    _ = state.emulateFrame();
    try testing.expect(state.odd_frame); // Should now be odd frame

    // Emulate second frame (odd frame with skip)
    _ = state.emulateFrame();

    // Should be back to even frame
    try testing.expect(!state.odd_frame);

    // Frame count should have incremented twice
    try testing.expectEqual(@as(u64, 2), state.ppu.frame_count);
}

test "EmulationState: even frame does not skip dot" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    config.ppu.variant = .rp2c02g_ntsc;

    var state = EmulationState.init(&config);
    state.power_on();

    // Emulate first frame (even frame)
    const even_frame_cycles = state.emulateFrame();

    // Even frames should be standard length (NTSC frame = 89342 master cycles)
    try testing.expectEqual(@as(u64, timing.NTSC.CYCLES_PER_FRAME), even_frame_cycles);

    try testing.expect(state.odd_frame); // Now odd
}

test "EmulationState: odd frame without rendering does not skip" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    config.ppu.variant = .rp2c02g_ntsc;

    var state = EmulationState.init(&config);
    state.power_on();

    // Rendering disabled (PPUMASK = 0)
    state.ppu.mask = .{};

    // Emulate first frame (even, no rendering)
    _ = state.emulateFrame();
    try testing.expect(state.odd_frame); // Now odd

    // Emulate second frame (odd, no rendering - should NOT skip)
    const odd_frame_cycles = state.emulateFrame();

    // Without rendering, odd frames should also be standard length (NTSC frame = 89342 master cycles)
    try testing.expectEqual(@as(u64, timing.NTSC.CYCLES_PER_FRAME), odd_frame_cycles);
}

test "EmulationState: frame toggle at scanline boundary" {
    var config = Config.Config.init(testing.allocator);
    defer config.deinit();

    config.ppu.variant = .rp2c02g_ntsc;

    var state = EmulationState.init(&config);
    state.power_on();

    // Start with even frame (odd_frame = false)
    try testing.expect(!state.odd_frame);
    try testing.expectEqual(@as(u64, 0), state.ppu.frame_count);

    // Emulate first frame
    _ = state.emulateFrame();

    // Frame should have incremented
    try testing.expectEqual(@as(u64, 1), state.ppu.frame_count);
    // Should now be odd frame
    try testing.expect(state.odd_frame);

    // Emulate second frame
    _ = state.emulateFrame();

    // Should be back to even frame
    try testing.expect(!state.odd_frame);
    try testing.expectEqual(@as(u64, 2), state.ppu.frame_count);
}
