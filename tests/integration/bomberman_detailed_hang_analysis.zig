//! Bomberman Detailed Hang Analysis
//!
//! Now that we know Bomberman hangs at PC $C00D reading $2002 (PPUSTATUS),
//! this test investigates WHY the emulator never reaches scanline 241.
//!
//! Hypothesis: Something is preventing the PPU from advancing through scanlines.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;
const NromCart = RAMBO.CartridgeType;
const AnyCartridge = RAMBO.AnyCartridge;

test "Bomberman: Trace scanline progression" {
    const allocator = testing.allocator;

    const nrom_cart = NromCart.load(allocator, "tests/data/Bomberman/Bomberman (USA).nes") catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };
    const cart = AnyCartridge{ .nrom = nrom_cart };

    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.loadCartridge(cart);
    state.reset();

    // Track scanline progression
    var max_scanline_reached: u16 = 0;
    var scanline_241_count: usize = 0;
    var total_ticks: usize = 0;
    const max_ticks: usize = 1_000_000; // 1M ticks should be enough for multiple frames

    var last_scanline: u16 = 0;
    var scanline_stuck_count: usize = 0;

    while (total_ticks < max_ticks) {
        const scanline = state.clock.scanline();
        const dot = state.clock.dot();

        // Track maximum scanline reached
        if (scanline > max_scanline_reached) {
            max_scanline_reached = scanline;
        }

        // Count how many times we hit scanline 241
        if (scanline == 241 and last_scanline != 241) {
            scanline_241_count += 1;
        }

        // Detect if stuck on same scanline
        if (scanline == last_scanline) {
            scanline_stuck_count += 1;
            if (scanline_stuck_count > 100000) {
                // Stuck on same scanline for 100k+ ticks!
                const ppu_cycles = state.clock.ppu_cycles;
                const cpu_cycles = state.clock.cpuCycles();
                // Reveal where we're stuck
                try testing.expectEqual(@as(u16, 999), scanline); // Will show stuck scanline
                try testing.expectEqual(@as(u16, 999), dot); // Will show stuck dot
                try testing.expectEqual(@as(u16, 999), max_scanline_reached); // Max we reached
                try testing.expectEqual(@as(usize, 0), total_ticks);
                try testing.expectEqual(@as(u64, 999999), ppu_cycles);
                try testing.expectEqual(@as(u64, 999999), cpu_cycles);
                return;
            }
        } else {
            scanline_stuck_count = 0;
        }

        last_scanline = scanline;
        state.tick();
        total_ticks += 1;
    }

    // If we got here, check what scanlines we reached
    try testing.expectEqual(@as(u16, 999), max_scanline_reached); // Show max scanline
    try testing.expectEqual(@as(usize, 999), scanline_241_count); // Show 241 count
    try testing.expectEqual(@as(usize, 0), total_ticks);
}

test "Bomberman: Check if PPU is enabled" {
    const allocator = testing.allocator;

    const nrom_cart = NromCart.load(allocator, "tests/data/Bomberman/Bomberman (USA).nes") catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };
    const cart = AnyCartridge{ .nrom = nrom_cart };

    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.loadCartridge(cart);
    state.reset();

    // Run until we hit the hang location (PC $C00D)
    const hang_pc: u16 = 0xC00D;
    var reached_hang = false;
    var ticks: usize = 0;
    const max_ticks: usize = 500000;

    while (!reached_hang and ticks < max_ticks) {
        if (state.cpu.pc == hang_pc and state.cpu.state == .fetch_opcode) {
            reached_hang = true;
            break;
        }
        state.tick();
        ticks += 1;
    }

    if (!reached_hang) {
        return error.SkipZigTest; // Didn't reach hang location
    }

    // At hang location - check PPU state
    const ppuctrl = @as(u8, @bitCast(state.ppu.ctrl));
    const ppumask = @as(u8, @bitCast(state.ppu.mask));
    const ppustatus = @as(u8, @bitCast(state.ppu.status));
    const scanline = state.clock.scanline();
    const dot = state.clock.dot();
    const ppu_cycles = state.clock.ppu_cycles;

    // Reveal PPU state at hang
    try testing.expectEqual(@as(u8, 0xFF), ppuctrl);
    try testing.expectEqual(@as(u8, 0xFF), ppumask);
    try testing.expectEqual(@as(u8, 0xFF), ppustatus);
    try testing.expectEqual(@as(u16, 999), scanline);
    try testing.expectEqual(@as(u16, 999), dot);
    try testing.expectEqual(@as(u64, 999999), ppu_cycles);
}

test "Bomberman: Check CPU/PPU cycle ratio" {
    const allocator = testing.allocator;

    const nrom_cart = NromCart.load(allocator, "tests/data/Bomberman/Bomberman (USA).nes") catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };
    const cart = AnyCartridge{ .nrom = nrom_cart };

    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.loadCartridge(cart);
    state.reset();

    const initial_cpu_cycles = state.clock.cpuCycles();
    const initial_ppu_cycles = state.clock.ppu_cycles;

    // Run 100k ticks
    var ticks: usize = 0;
    while (ticks < 100000) : (ticks += 1) {
        state.tick();
    }

    const final_cpu_cycles = state.clock.cpuCycles();
    const final_ppu_cycles = state.clock.ppu_cycles;

    const cpu_delta = final_cpu_cycles - initial_cpu_cycles;
    const ppu_delta = final_ppu_cycles - initial_ppu_cycles;

    // PPU should run 3x faster than CPU
    // Reveal actual ratio
    const ratio = if (cpu_delta > 0) ppu_delta / cpu_delta else 0;

    try testing.expectEqual(@as(u64, 3), ratio); // Should be 3:1
    try testing.expectEqual(@as(u64, 999999), cpu_delta);
    try testing.expectEqual(@as(u64, 999999), ppu_delta);
}
