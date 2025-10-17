//! DMC/OAM DMA Conflict Tests
//!
//! Tests the hardware-accurate interaction between DMC DMA and OAM DMA.
//! When DMC DMA interrupts OAM DMA, OAM pauses and resumes with byte duplication.
//!
//! Hardware Specifications:
//! - DMC DMA has highest priority (can interrupt OAM DMA)
//! - OAM DMA pauses during DMC interrupt (does not cancel)
//! - Byte being read when interrupted duplicates on resume
//! - Total cycles = OAM base (513/514) + (DMC_count × 4)
//!
//! Reference: nesdev.org/wiki/APU_DMC#DMA_conflict

const std = @import("std");
const testing = std.testing;

const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;
const EmulationState = RAMBO.EmulationState.EmulationState;

// ============================================================================
// Test Helpers
// ============================================================================

/// Check if OAM DMA is paused (based on functional timestamp comparison)
fn isDmaPaused(state: *const EmulationState) bool {
    const dmc_is_active = state.dma_interaction_ledger.last_dmc_active_cycle >
        state.dma_interaction_ledger.last_dmc_inactive_cycle;
    const was_paused = state.dma_interaction_ledger.oam_pause_cycle >
        state.dma_interaction_ledger.oam_resume_cycle;
    return dmc_is_active and was_paused;
}

/// Fill CPU memory page with sequential pattern (uses busWrite for proper routing)
fn fillRamPage(state: *EmulationState, page: u8, pattern: u8) void {
    for (0..256) |i| {
        const offset = @as(u8, @intCast(i));
        const address = (@as(u16, page) << 8) | offset;
        state.busWrite(address, pattern +% offset);
    }
}

/// Run until OAM DMA completes (with timeout protection)
fn runUntilOamDmaComplete(state: *EmulationState) void {
    var tick_count: u32 = 0;
    while (state.dma.active and tick_count < 3000) : (tick_count += 1) {
        state.tick();
    }
}

/// Run until DMC DMA completes (with timeout protection)
fn runUntilDmcDmaComplete(state: *EmulationState) void {
    var tick_count: u32 = 0;
    while (state.dmc_dma.rdy_low and tick_count < 100) : (tick_count += 1) {
        state.tick();
    }
}

// ============================================================================
// Debug Tests - Verify Basic Mechanism
// ============================================================================

test "MINIMAL: DMC pauses OAM (debug with proper harness)" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Setup DMC channel
    state.apu.dmc_bytes_remaining = 10;
    state.apu.dmc_active = true;

    // Trigger OAM DMA
    state.busWrite(0x4014, 0x0A);

    // Trigger DMC DMA (this should cause pause when we tick)
    state.dmc_dma.triggerFetch(0xC000);

    // Tick once CPU cycle - OAM should pause
    harness.tickCpu(1);

    // Verify pause happened
    try testing.expect(isDmaPaused(state));
}

test "DEBUG: Trace complete DMC/OAM interaction" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Initialize DMC
    state.apu.dmc_bytes_remaining = 10;
    state.apu.dmc_active = true;

    // Fill RAM with pattern
    fillRamPage(state, 0x03, 0x00);

    // Start OAM DMA
    std.debug.print("\n=== STARTING OAM DMA ===\n", .{});
    std.debug.print("Before: dma.active={}\n", .{state.dma.active});
    state.busWrite(0x4014, 0x03);
    std.debug.print("After: dma.active={}\n", .{state.dma.active});

    // Trigger DMC immediately
    std.debug.print("\n=== TRIGGERING DMC ===\n", .{});
    state.dmc_dma.triggerFetch(0xC000);
    std.debug.print("  dmc_dma.rdy_low={}\n", .{state.dmc_dma.rdy_low});
    std.debug.print("  Ledger before pause: last_dmc_active={d}, last_dmc_inactive={d}\n", .{
        state.dma_interaction_ledger.last_dmc_active_cycle,
        state.dma_interaction_ledger.last_dmc_inactive_cycle,
    });

    // Tick once - OAM should pause
    std.debug.print("\n=== TICK 1: OAM SHOULD PAUSE ===\n", .{});
    std.debug.print("BEFORE tick 1:\n", .{});
    std.debug.print("  dma: active={}, cycle={}\n", .{state.dma.active, state.dma.current_cycle});
    std.debug.print("  ppu_cycles={}\n", .{state.clock.ppu_cycles});

    harness.tickCpu(1);

    std.debug.print("AFTER tick 1:\n", .{});
    std.debug.print("  dma: active={}, cycle={}\n", .{state.dma.active, state.dma.current_cycle});
    std.debug.print("  dmc_dma.rdy_low={}, stall={}\n", .{state.dmc_dma.rdy_low, state.dmc_dma.stall_cycles_remaining});
    std.debug.print("  ppu_cycles={}\n", .{state.clock.ppu_cycles});
    std.debug.print("  Ledger: pause={d}, last_dmc_active={d}, last_dmc_inactive={d}\n", .{
        state.dma_interaction_ledger.oam_pause_cycle,
        state.dma_interaction_ledger.last_dmc_active_cycle,
        state.dma_interaction_ledger.last_dmc_inactive_cycle,
    });
    std.debug.print("  Paused: was_reading={}, offset={d}, byte=0x{x:0>2}, oam_addr={d}\n", .{
        state.dma_interaction_ledger.paused_during_read,
        state.dma_interaction_ledger.paused_at_offset,
        state.dma_interaction_ledger.paused_byte_value,
        state.dma_interaction_ledger.paused_oam_addr,
    });

    try testing.expect(isDmaPaused(state));

    // Run DMC to completion (4 cycles total)
    std.debug.print("\n=== RUNNING DMC TO COMPLETION ===\n", .{});
    var dmc_ticks: u32 = 0;
    while (state.dmc_dma.rdy_low and dmc_ticks < 10) : (dmc_ticks += 1) {
        std.debug.print("DMC tick {}: stall={}, ppu_cycles={}\n", .{
            dmc_ticks, state.dmc_dma.stall_cycles_remaining, state.clock.ppu_cycles
        });
        state.tick();
    }
    std.debug.print("DMC completed after {} ticks\n", .{dmc_ticks});
    std.debug.print("  dmc_dma.rdy_low={}\n", .{state.dmc_dma.rdy_low});
    std.debug.print("  ppu_cycles={}\n", .{state.clock.ppu_cycles});
    std.debug.print("  Ledger: pause={d}, resume={d}, last_dmc_inactive={d}\n", .{
        state.dma_interaction_ledger.oam_pause_cycle,
        state.dma_interaction_ledger.oam_resume_cycle,
        state.dma_interaction_ledger.last_dmc_inactive_cycle,
    });

    // Try to resume OAM
    std.debug.print("\n=== ATTEMPTING OAM RESUME ===\n", .{});
    var oam_ticks: u32 = 0;
    while (state.dma.active and oam_ticks < 20) : (oam_ticks += 1) {
        std.debug.print("OAM tick {}: cycle={}, offset={}, ppu_cycles={}\n", .{
            oam_ticks, state.dma.current_cycle, state.dma.current_offset, state.clock.ppu_cycles
        });

        const before_cycle = state.dma.current_cycle;
        state.tick();
        const after_cycle = state.dma.current_cycle;

        if (before_cycle != after_cycle) {
            std.debug.print("  *** CYCLE ADVANCE: {} -> {}\n", .{before_cycle, after_cycle});
            std.debug.print("  Ledger: resume={d}\n", .{state.dma_interaction_ledger.oam_resume_cycle});
        }
    }

    if (state.dma.active) {
        std.debug.print("\nERROR: OAM STUCK - still active after {} ticks!\n", .{oam_ticks});
        std.debug.print("Final state:\n", .{});
        std.debug.print("  dma: active={}, cycle={}\n", .{state.dma.active, state.dma.current_cycle});
        std.debug.print("  Ledger: pause={d}, resume={d}\n", .{
            state.dma_interaction_ledger.oam_pause_cycle,
            state.dma_interaction_ledger.oam_resume_cycle,
        });
        return error.OamNeverResumed;
    }

    std.debug.print("\nSUCCESS: OAM completed!\n", .{});
}

// ============================================================================
// Unit Tests - DMC Interrupts OAM
// ============================================================================

test "DMC interrupts OAM at byte 0 (start of transfer)" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Initialize DMC to avoid underflow
    state.apu.dmc_bytes_remaining = 10;
    state.apu.dmc_active = true;

    // Fill source page with sequential data (0x00, 0x01, 0x02, ...)
    fillRamPage(state, 0x03, 0x00);

    // Start OAM DMA from page $03
    state.busWrite(0x4014, 0x03);
    try testing.expect(state.dma.active);
    try testing.expect(!isDmaPaused(state));

    // Immediately trigger DMC DMA (interrupt at byte 0)
    state.dmc_dma.triggerFetch(0xC000);
    try testing.expect(state.dmc_dma.rdy_low);

    // Tick once CPU cycle - OAM should pause
    harness.tickCpu(1);
    try testing.expect(isDmaPaused(state)); // OAM paused by DMC

    // Run DMC to completion
    runUntilDmcDmaComplete(state);
    try testing.expect(!state.dmc_dma.rdy_low);

    // Run OAM to completion
    runUntilOamDmaComplete(state);
    try testing.expect(!state.dma.active);

    // Verify OAM data transferred correctly
    // Byte 0 should be in OAM[0] (duplication causes it to also appear in OAM[1])
    try testing.expect(state.ppu.oam[0] == 0x00);
}

test "DMC interrupts OAM at byte 128 (mid-transfer)" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Initialize DMC
    state.apu.dmc_bytes_remaining = 10;
    state.apu.dmc_active = true;

    // Fill source page with sequential data
    fillRamPage(state, 0x04, 0x00);

    // Start OAM DMA
    state.busWrite(0x4014, 0x04);

    // Run OAM for 256 CPU cycles to reach byte 128
    // Each byte = 2 cycles (read + write), so byte 128 = 256 cycles
    harness.tickCpu(256);

    // Verify we're at byte 128
    try testing.expect(state.dma.current_offset == 128);

    // Trigger DMC DMA (interrupt at byte 128)
    state.dmc_dma.triggerFetch(0xC000);

    // Tick one CPU cycle - OAM should pause
    harness.tickCpu(1);
    try testing.expect(isDmaPaused(state));

    // Run DMC to completion
    runUntilDmcDmaComplete(state);

    // Run OAM to completion
    runUntilOamDmaComplete(state);
    try testing.expect(!state.dma.active);

    // Verify OAM data transferred correctly
    try testing.expect(state.ppu.oam[127] == 127); // Before interrupt
    try testing.expect(state.ppu.oam[128] == 128); // At interrupt (may duplicate)
}

test "DMC interrupts OAM at byte 255 (end of transfer)" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Initialize DMC
    state.apu.dmc_bytes_remaining = 10;
    state.apu.dmc_active = true;

    // Fill source page
    fillRamPage(state, 0x05, 0x00);

    // Start OAM DMA
    state.busWrite(0x4014, 0x05);

    // Run OAM for 510 CPU cycles to reach byte 255
    harness.tickCpu(510);

    // Verify we're at byte 255
    try testing.expect(state.dma.current_offset == 255);

    // Trigger DMC DMA (interrupt at last byte)
    state.dmc_dma.triggerFetch(0xC000);

    // Tick one CPU cycle to trigger pause, then run to completion
    harness.tickCpu(1);
    try testing.expect(isDmaPaused(state)); // Verify pause happened
    runUntilDmcDmaComplete(state);
    runUntilOamDmaComplete(state);

    // Verify transfer completed
    try testing.expect(!state.dma.active);
    try testing.expect(state.ppu.oam[254] == 254);
    try testing.expect(state.ppu.oam[255] == 255);
}

// ============================================================================
// Integration Tests - Byte Duplication Verification
// ============================================================================

test "Byte duplication: Interrupted during read cycle" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Initialize DMC
    state.apu.dmc_bytes_remaining = 10;
    state.apu.dmc_active = true;

    // Fill page with unique arithmetic pattern: (i * 3) % 256
    // This ensures every byte is unique and detects duplication
    for (0..256) |i| {
        const value = @as(u8, @intCast((i * 3) % 256));
        state.bus.ram[0x0600 + i] = value;
    }

    // Start OAM DMA from page $06
    state.busWrite(0x4014, 0x06);

    // Run to byte 100 (200 cycles)
    harness.tickCpu(200);
    try testing.expect(state.dma.current_offset == 100);

    // Calculate effective cycle to ensure we interrupt during read (even cycle)
    const effective_cycle = if (state.dma.needs_alignment)
        state.dma.current_cycle - 1
    else
        state.dma.current_cycle;

    // Ensure we're on even cycle (read phase)
    if (effective_cycle % 2 != 0) {
        // If odd, tick once more to get to next read
        state.tick();
    }

    // Trigger DMC interrupt during read
    state.dmc_dma.triggerFetch(0xC000);

    // Run to completion
    runUntilDmcDmaComplete(state);
    runUntilOamDmaComplete(state);

    // Verify byte duplication occurred
    // The byte being read when interrupted should duplicate
    // Check pattern integrity (some byte should appear twice)
    var duplicate_found = false;
    for (0..255) |i| {
        if (state.ppu.oam[i] == state.ppu.oam[i + 1]) {
            duplicate_found = true;
            break;
        }
    }
    try testing.expect(duplicate_found); // Hardware bug: duplication should occur
}

// ============================================================================
// Integration Tests - Multiple DMC Interrupts
// ============================================================================

test "Multiple DMC interrupts during single OAM transfer" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Initialize DMC
    state.apu.dmc_bytes_remaining = 30;
    state.apu.dmc_active = true;

    // Fill source page
    fillRamPage(state, 0x07, 0x00);

    // Start OAM DMA
    state.busWrite(0x4014, 0x07);

    // Interrupt at byte 50
    harness.tickCpu(100);
    state.dmc_dma.triggerFetch(0xC000);
    runUntilDmcDmaComplete(state);

    // Interrupt at byte 150
    harness.tickCpu(100);
    state.dmc_dma.triggerFetch(0xC100);
    runUntilDmcDmaComplete(state);

    // Interrupt at byte 250
    harness.tickCpu(100);
    state.dmc_dma.triggerFetch(0xC200);
    runUntilDmcDmaComplete(state);

    // Complete OAM transfer
    runUntilOamDmaComplete(state);

    // Verify transfer completed despite multiple interrupts
    try testing.expect(!state.dma.active);
    try testing.expect(state.ppu.oam[0] == 0);
    try testing.expect(state.ppu.oam[255] == 255);
}

test "Consecutive DMC interrupts (no gap)" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Initialize DMC
    state.apu.dmc_bytes_remaining = 20;
    state.apu.dmc_active = true;

    // Fill source page
    fillRamPage(state, 0x08, 0xAA);

    // Start OAM DMA
    state.busWrite(0x4014, 0x08);

    // Run to byte 64
    harness.tickCpu(128);

    // First DMC interrupt
    state.dmc_dma.triggerFetch(0xC000);
    runUntilDmcDmaComplete(state);

    // Second DMC interrupt immediately after
    state.dmc_dma.triggerFetch(0xC100);
    runUntilDmcDmaComplete(state);

    // Complete OAM
    runUntilOamDmaComplete(state);

    // Verify completion
    try testing.expect(!state.dma.active);
}

// ============================================================================
// Timing Tests
// ============================================================================

test "Cycle count: OAM 513 + DMC 4 = 517 total" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Initialize DMC
    state.apu.dmc_bytes_remaining = 10;
    state.apu.dmc_active = true;

    // Fill source page
    fillRamPage(state, 0x09, 0x00);

    // Ensure even CPU cycle start
    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }
    const start_ppu = state.clock.ppu_cycles;

    // Start OAM DMA
    state.busWrite(0x4014, 0x09);
    try testing.expect(!state.dma.needs_alignment); // Even start

    // Run to byte 64, then interrupt with DMC
    harness.tickCpu(128);
    state.dmc_dma.triggerFetch(0xC000);

    // Run to completion
    runUntilDmcDmaComplete(state);
    runUntilOamDmaComplete(state);

    // Calculate elapsed CPU cycles
    const elapsed_ppu = state.clock.ppu_cycles - start_ppu;
    const elapsed_cpu = elapsed_ppu / 3;

    // Should be 513 (OAM base) + 4 (DMC) = 517 CPU cycles
    try testing.expectEqual(@as(u64, 517), elapsed_cpu);
}

test "DMC priority verification" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Initialize DMC
    state.apu.dmc_bytes_remaining = 10;
    state.apu.dmc_active = true;

    // Fill source page
    fillRamPage(state, 0x0A, 0x00);

    // Trigger both DMAs simultaneously
    state.busWrite(0x4014, 0x0A); // OAM DMA
    state.dmc_dma.triggerFetch(0xC000); // DMC DMA

    // DMC should execute first (higher priority)
    try testing.expect(state.dmc_dma.rdy_low);
    try testing.expect(state.dma.active);

    // Tick one CPU cycle - DMC should tick, OAM should pause
    harness.tickCpu(1);
    try testing.expect(isDmaPaused(state)); // OAM paused by DMC

    // DMC should still be active
    try testing.expect(state.dmc_dma.rdy_low);
}

// ============================================================================
// Regression Tests
// ============================================================================

test "OAM DMA: Still works correctly without DMC interrupt" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Fill source page
    fillRamPage(state, 0x02, 0x00);

    // Start OAM DMA (no DMC activity)
    state.busWrite(0x4014, 0x02);

    // Run to completion
    runUntilOamDmaComplete(state);

    // Verify all 256 bytes transferred correctly
    for (0..256) |i| {
        const expected = @as(u8, @intCast(i));
        try testing.expectEqual(expected, state.ppu.oam[i]);
    }
}

test "DMC DMA: Still works correctly without OAM active" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Initialize DMC
    state.apu.dmc_bytes_remaining = 10;
    state.apu.dmc_active = true;

    // Trigger DMC DMA (no OAM activity)
    state.dmc_dma.triggerFetch(0xC000);
    try testing.expect(state.dmc_dma.rdy_low);

    // Run to completion
    runUntilDmcDmaComplete(state);

    // Verify DMC completed
    try testing.expect(!state.dmc_dma.rdy_low);
}
