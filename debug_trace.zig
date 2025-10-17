const std = @import("std");
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

/// Detailed trace of DMC/OAM interaction
pub fn main() !void {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Initialize DMC
    state.apu.dmc_bytes_remaining = 10;
    state.apu.dmc_active = true;

    // Fill RAM with pattern
    for (0..256) |i| {
        const offset = @as(u8, @intCast(i));
        const address = (@as(u16, 0x03) << 8) | offset;
        state.busWrite(address, offset);
    }

    // Start OAM DMA
    std.debug.print("=== STARTING OAM DMA ===\n", .{});
    std.debug.print("Before: dma.active={}, dma.phase={}\n", .{state.dma.active, state.dma.phase});
    state.busWrite(0x4014, 0x03);
    std.debug.print("After: dma.active={}, dma.phase={}\n", .{state.dma.active, state.dma.phase});

    // Trigger DMC immediately
    std.debug.print("\n=== TRIGGERING DMC ===\n", .{});
    std.debug.print("Before: dmc_dma.rdy_low={}\n", .{state.dmc_dma.rdy_low});
    state.dmc_dma.triggerFetch(0xC000);
    std.debug.print("After: dmc_dma.rdy_low={}\n", .{state.dmc_dma.rdy_low});
    std.debug.print("Ledger: {}\n", .{state.dma_interaction_ledger});

    // Tick once - OAM should pause
    std.debug.print("\n=== TICK 1: OAM SHOULD PAUSE ===\n", .{});
    std.debug.print("BEFORE tick:\n", .{});
    std.debug.print("  dma.active={}, dma.phase={}, dma.current_cycle={}\n", .{state.dma.active, state.dma.phase, state.dma.current_cycle});
    std.debug.print("  dmc_dma.rdy_low={}\n", .{state.dmc_dma.rdy_low});
    std.debug.print("  Ledger: {}\n", .{state.dma_interaction_ledger});

    harness.tickCpu(1);

    std.debug.print("AFTER tick:\n", .{});
    std.debug.print("  dma.active={}, dma.phase={}, dma.current_cycle={}\n", .{state.dma.active, state.dma.phase, state.dma.current_cycle});
    std.debug.print("  dmc_dma.rdy_low={}, stall_cycles={}\n", .{state.dmc_dma.rdy_low, state.dmc_dma.stall_cycles_remaining});
    std.debug.print("  Ledger: {}\n", .{state.dma_interaction_ledger});

    const paused = state.dma.phase == .paused_during_read or state.dma.phase == .paused_during_write;
    std.debug.print("  PAUSED: {}\n", .{paused});

    // Run DMC to completion
    std.debug.print("\n=== RUNNING DMC TO COMPLETION ===\n", .{});
    var tick_count: u32 = 0;
    while (state.dmc_dma.rdy_low and tick_count < 10) : (tick_count += 1) {
        std.debug.print("DMC tick {}: stall_cycles={}\n", .{tick_count, state.dmc_dma.stall_cycles_remaining});
        state.tick();
    }
    std.debug.print("DMC completed after {} ticks\n", .{tick_count});
    std.debug.print("  dmc_dma.rdy_low={}\n", .{state.dmc_dma.rdy_low});
    std.debug.print("  Ledger: {}\n", .{state.dma_interaction_ledger});

    // Try to resume OAM
    std.debug.print("\n=== ATTEMPTING OAM RESUME ===\n", .{});
    tick_count = 0;
    while (state.dma.active and tick_count < 20) : (tick_count += 1) {
        std.debug.print("OAM tick {}: phase={}, cycle={}, offset={}\n", .{
            tick_count, state.dma.phase, state.dma.current_cycle, state.dma.current_offset
        });
        state.tick();
    }

    if (state.dma.active) {
        std.debug.print("\nERROR: OAM still active after {} ticks!\n", .{tick_count});
        std.debug.print("Final state:\n", .{});
        std.debug.print("  dma.active={}, dma.phase={}, dma.current_cycle={}\n", .{state.dma.active, state.dma.phase, state.dma.current_cycle});
        std.debug.print("  Ledger: {}\n", .{state.dma_interaction_ledger});
    } else {
        std.debug.print("\nSUCCESS: OAM completed!\n", .{});
        std.debug.print("  OAM[0] = 0x{x:0>2} (expected 0x00)\n", .{state.ppu.oam[0]});
    }
}
