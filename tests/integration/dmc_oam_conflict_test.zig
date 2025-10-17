//! DMC/OAM DMA Conflict Tests
//!
//! Tests the hardware-accurate interaction between DMC DMA and OAM DMA.
//! When DMC DMA interrupts OAM DMA, OAM continues executing during DMC's dummy/alignment
//! cycles, then requires an additional alignment cycle before resuming normal operation.
//!
//! Hardware Specifications (from nesdev.org wiki):
//! - DMC DMA has highest priority (can interrupt OAM DMA)
//! - OAM DMA continues during DMC dummy/alignment cycles (time-sharing)
//! - No byte duplication - OAM reads sequential addresses
//! - Extra alignment cycle required after DMC completes
//! - Total overhead: typically +2 cycles, but can be +1 or +3 depending on timing
//!
//! Reference: nesdev.org/wiki/APU_DMC#Conflict_with_controller_and_PPU_read

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
fn runUntilOamDmaComplete(harness: *Harness) void {
    var tick_count: u32 = 0;
    while (harness.state.dma.active and tick_count < 1000) : (tick_count += 1) {
        harness.tickCpu(1);
    }
}

/// Run until DMC DMA completes (with timeout protection)
fn runUntilDmcDmaComplete(harness: *Harness) void {
    var tick_count: u32 = 0;
    while (harness.state.dmc_dma.rdy_low and tick_count < 100) : (tick_count += 1) {
        harness.tickCpu(1);
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
    state.busWrite(0x4014, 0x03);
    try testing.expect(state.dma.active);

    // Trigger DMC immediately
    state.dmc_dma.triggerFetch(0xC000);
    try testing.expect(state.dmc_dma.rdy_low);

    // Tick once - OAM should pause
    harness.tickCpu(1);
    try testing.expect(isDmaPaused(state));

    // Run DMC to completion
    runUntilDmcDmaComplete(&harness);
    try testing.expectEqual(false, state.dmc_dma.rdy_low);

    // OAM should resume and complete
    runUntilOamDmaComplete(&harness);
    try testing.expectEqual(false, state.dma.active);
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
    runUntilDmcDmaComplete(&harness);
    try testing.expect(!state.dmc_dma.rdy_low);

    // Run OAM to completion
    runUntilOamDmaComplete(&harness);
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
    runUntilDmcDmaComplete(&harness);

    // Run OAM to completion
    runUntilOamDmaComplete(&harness);
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
    runUntilDmcDmaComplete(&harness);
    runUntilOamDmaComplete(&harness);

    // Verify transfer completed
    try testing.expect(!state.dma.active);
    try testing.expect(state.ppu.oam[254] == 254);
    try testing.expect(state.ppu.oam[255] == 255);
}

// ============================================================================
// Integration Tests - Byte Duplication Verification
// ============================================================================

test "OAM resumes correctly after DMC interrupt" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Initialize DMC
    state.apu.dmc_bytes_remaining = 10;
    state.apu.dmc_active = true;

    // Fill page with sequential pattern for verification
    for (0..256) |i| {
        const value = @as(u8, @intCast(i));
        state.bus.ram[0x0600 + i] = value;
    }

    // Start OAM DMA from page $06
    state.busWrite(0x4014, 0x06);

    // Run to byte 100 (200 cycles)
    harness.tickCpu(200);
    try testing.expect(state.dma.current_offset == 100);

    // Trigger DMC interrupt
    state.dmc_dma.triggerFetch(0xC000);

    // Run to completion
    runUntilDmcDmaComplete(&harness);
    runUntilOamDmaComplete(&harness);

    // Verify NO duplication - OAM should contain sequential bytes 0-255
    // Hardware behavior: OAM just pauses and resumes, no byte corruption
    // Reference: nesdev.org forums - Disch's hardware testing
    for (0..256) |i| {
        const expected = @as(u8, @intCast(i));
        try testing.expectEqual(expected, state.ppu.oam[i]);
    }
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
    runUntilDmcDmaComplete(&harness);

    // Interrupt at byte 150
    harness.tickCpu(100);
    state.dmc_dma.triggerFetch(0xC100);
    runUntilDmcDmaComplete(&harness);

    // Interrupt at byte 250
    harness.tickCpu(100);
    state.dmc_dma.triggerFetch(0xC200);
    runUntilDmcDmaComplete(&harness);

    // Complete OAM transfer
    runUntilOamDmaComplete(&harness);

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
    runUntilDmcDmaComplete(&harness);

    // Second DMC interrupt immediately after
    state.dmc_dma.triggerFetch(0xC100);
    runUntilDmcDmaComplete(&harness);

    // Complete OAM
    runUntilOamDmaComplete(&harness);

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

    // Ensure even CPU cycle start (aligned to CPU boundary)
    while ((state.clock.ppu_cycles % 3) != 0) {
        harness.tick(1);  // Single PPU cycle to align
    }
    const start_ppu = state.clock.ppu_cycles;

    // Start OAM DMA
    state.busWrite(0x4014, 0x09);
    try testing.expect(!state.dma.needs_alignment); // Even start

    // Run to byte 64, then interrupt with DMC
    harness.tickCpu(128);
    state.dmc_dma.triggerFetch(0xC000);

    // Run to completion
    runUntilDmcDmaComplete(&harness);
    runUntilOamDmaComplete(&harness);

    // Calculate elapsed CPU cycles
    const elapsed_ppu = state.clock.ppu_cycles - start_ppu;
    const elapsed_cpu = elapsed_ppu / 3;

    // Expected: 512 (OAM transfer) + 2 (DMC paused cycles) + 1 (alignment) = 515 CPU cycles
    // Wiki mentions "taking 2 cycles" overhead which can vary by 1-3 cycles depending on timing
    try testing.expect(elapsed_cpu >= 515);
    try testing.expect(elapsed_cpu <= 517);
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
    runUntilOamDmaComplete(&harness);

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
    runUntilDmcDmaComplete(&harness);

    // Verify DMC completed
    try testing.expect(!state.dmc_dma.rdy_low);
}

// ============================================================================
// Hardware Validation Tests - Cycle-by-Cycle Behavior
// ============================================================================

test "HARDWARE VALIDATION: OAM continues during DMC dummy/alignment (time-sharing)" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Initialize DMC
    state.apu.dmc_bytes_remaining = 10;
    state.apu.dmc_active = true;

    // Fill RAM with sequential pattern for tracking
    for (0..256) |i| {
        const value = @as(u8, @intCast(i));
        state.bus.ram[0x0300 + i] = value;
    }

    // Start OAM DMA from page $03
    state.busWrite(0x4014, 0x03);
    try testing.expect(state.dma.active);

    // Run to byte 50 (100 CPU cycles = 50 read/write pairs)
    harness.tickCpu(100);
    try testing.expectEqual(@as(u8, 50), state.dma.current_offset);
    try testing.expectEqual(@as(u8, 49), state.ppu.oam[49]); // Byte 49 written

    // Record OAM state before DMC interrupt
    const offset_before = state.dma.current_offset;
    const oam_addr_before = state.ppu.oam_addr;

    // Trigger DMC interrupt at byte 50
    state.dmc_dma.triggerFetch(0xC000);
    try testing.expect(state.dmc_dma.rdy_low);

    // According to wiki spec, during DMC's 4-cycle stall:
    // - Cycle 1: DMC halt + alignment
    // - Cycle 2: DMC dummy (OAM continues here!)
    // - Cycle 3: DMC alignment (OAM continues here!)
    // - Cycle 4: DMC read
    //
    // OAM should advance by 1 complete read/write pair during cycles 2-3

    // Run DMC to completion (4 CPU cycles)
    runUntilDmcDmaComplete(&harness);
    try testing.expectEqual(false, state.dmc_dma.rdy_low);

    // CRITICAL: Verify OAM advanced during DMC
    // OAM should have moved forward (time-sharing, not complete pause)
    const offset_after = state.dma.current_offset;
    const oam_addr_after = state.ppu.oam_addr;

    // This test will FAIL with current implementation (complete pause)
    // and PASS with correct implementation (time-sharing)
    //
    // Expected: OAM advanced by 1-2 bytes during DMC
    // Current (WRONG): OAM didn't advance at all
    try testing.expect(offset_after > offset_before);
    try testing.expect(oam_addr_after > oam_addr_before);

    // Complete OAM transfer
    runUntilOamDmaComplete(&harness);

    // Verify NO duplication - sequential values
    for (0..256) |i| {
        const expected = @as(u8, @intCast(i));
        try testing.expectEqual(expected, state.ppu.oam[i]);
    }
}

test "HARDWARE VALIDATION: Exact cycle count overhead from DMC interrupt" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Initialize DMC
    state.apu.dmc_bytes_remaining = 10;
    state.apu.dmc_active = true;

    // Fill RAM
    fillRamPage(state, 0x02, 0x00);

    // Baseline: OAM without interruption takes 513 or 514 CPU cycles
    // (depends on write cycle alignment)

    // Start OAM DMA
    state.busWrite(0x4014, 0x02);
    const start_cycles = state.clock.ppu_cycles;

    // Run to byte 100
    harness.tickCpu(200);

    // Trigger DMC
    state.dmc_dma.triggerFetch(0xC000);

    // Complete both DMAs
    runUntilDmcDmaComplete(&harness);
    runUntilOamDmaComplete(&harness);

    const end_cycles = state.clock.ppu_cycles;
    const total_cpu_cycles = (end_cycles - start_cycles) / 3;

    // According to wiki: "taking 2 cycles" overhead (typical case)
    // DMC takes 4 cycles:
    //   - Cycle 1 (stall=4): Halt - OAM pauses
    //   - Cycle 2 (stall=3): Dummy - OAM continues (time-sharing)
    //   - Cycle 3 (stall=2): Alignment - OAM continues (time-sharing)
    //   - Cycle 4 (stall=1): Read - OAM pauses
    // Plus 1 post-DMC alignment cycle
    // Net overhead: 2 (paused) + 1 (alignment) = 3 cycles
    //
    // Expected: 512 (baseline, even start) + 3 (overhead) = 515 total

    // This test verifies correct time-sharing and alignment behavior
    try testing.expect(total_cpu_cycles >= 515);
    try testing.expect(total_cpu_cycles <= 517);
}
