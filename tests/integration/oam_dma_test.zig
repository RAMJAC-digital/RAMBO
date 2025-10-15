//! OAM DMA Integration Tests
//!
//! Tests the cycle-accurate OAM DMA transfer from CPU RAM to PPU OAM.
//! Verifies hardware-accurate timing and behavior.
//!
//! Hardware Specifications:
//! - DMA triggered by write to $4014
//! - Copies 256 bytes from CPU RAM ($XX00-$XXFF) to PPU OAM
//! - Takes 513 cycles (even start) or 514 cycles (odd start)
//! - CPU is stalled during transfer
//! - PPU continues running during transfer
//!
//! Reference: https://www.nesdev.org/wiki/PPU_registers#OAMDMA

const std = @import("std");
const testing = std.testing;

const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;
const EmulationState = RAMBO.EmulationState.EmulationState;

// ============================================================================
// Test Helpers
// ============================================================================

/// Fill CPU memory page with test pattern (uses busWrite for proper routing)
fn fillRamPage(state: *EmulationState, page: u8, pattern: u8) void {
    for (0..256) |i| {
        const offset = @as(u8, @intCast(i));
        const address = (@as(u16, page) << 8) | offset;
        state.busWrite(address, pattern +% offset);
    }
}

// ============================================================================
// Basic DMA Tests
// ============================================================================

test "OAM DMA: basic transfer from page $02" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Fill source page with test data (0x00, 0x01, 0x02, ..., 0xFF)
    fillRamPage(state, 0x02, 0x00);

    // Verify OAM is initially zero
    for (state.ppu.oam) |byte| {
        try testing.expectEqual(@as(u8, 0), byte);
    }

    // Trigger DMA from page $02
    state.busWrite(0x4014, 0x02);
    try testing.expect(state.dma.active);

    // Run DMA to completion
    var tick_count: u32 = 0;
    while (state.dma.active and tick_count < 2000) : (tick_count += 1) {
        state.tick(); // Tick emulation (PPU + CPU/DMA)
    }

    // Verify all 256 bytes transferred correctly
    for (0..256) |i| {
        const expected = @as(u8, @intCast(i));
        try testing.expectEqual(expected, state.ppu.oam[i]);
    }
}

test "OAM DMA: transfer from page $00 (zero page)" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Fill zero page with test pattern
    fillRamPage(state, 0x00, 0xAA);

    // Trigger DMA from zero page
    state.busWrite(0x4014, 0x00);

    // Run DMA to completion
    var tick_count: u32 = 0;
    while (state.dma.active and tick_count < 2000) : (tick_count += 1) {
        state.tick();
    }

    // Verify data transferred
    for (0..256) |i| {
        const expected = 0xAA +% @as(u8, @intCast(i));
        try testing.expectEqual(expected, state.ppu.oam[i]);
    }
}

test "OAM DMA: transfer from page $07 (stack page)" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Fill stack region with test pattern
    fillRamPage(state, 0x07, 0x55);

    // Trigger DMA from stack page
    state.busWrite(0x4014, 0x07);

    // Run DMA to completion
    var tick_count: u32 = 0;
    while (state.dma.active and tick_count < 2000) : (tick_count += 1) {
        state.tick();
    }
    try testing.expect(!state.dma.active); // Ensure DMA completed

    // Verify data transferred
    for (0..256) |i| {
        const expected = 0x55 +% @as(u8, @intCast(i));
        try testing.expectEqual(expected, state.ppu.oam[i]);
    }
}

// ============================================================================
// Timing Tests
// ============================================================================

test "OAM DMA: even cycle start takes exactly 513 CPU cycles" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Prepare source data
    fillRamPage(state, 0x03, 0x00);

    // Ensure we're on an even CPU cycle (PPU cycle divisible by 6)
    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }
    const start_ppu_cycles = state.clock.ppu_cycles;

    // Trigger DMA
    state.busWrite(0x4014, 0x03);
    try testing.expect(state.dma.active);
    try testing.expect(!state.dma.needs_alignment); // Even start

    // Run DMA to completion
    var tick_count: u32 = 0;
    while (state.dma.active and tick_count < 2000) : (tick_count += 1) {
        state.tick();
    }
    try testing.expect(!state.dma.active); // Ensure DMA completed

    // Calculate elapsed CPU cycles (3 PPU cycles = 1 CPU cycle)
    const elapsed_ppu = state.clock.ppu_cycles - start_ppu_cycles;
    const elapsed_cpu = elapsed_ppu / 3;

    // Should be exactly 513 CPU cycles
    try testing.expectEqual(@as(u64, 513), elapsed_cpu);
}

test "OAM DMA: odd cycle start takes exactly 514 CPU cycles" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Prepare source data
    fillRamPage(state, 0x04, 0x00);

    // Ensure we're on an odd CPU cycle (PPU cycle = 3 mod 6)
    while ((state.clock.ppu_cycles % 6) != 3) {
        state.tick();
    }
    const start_ppu_cycles = state.clock.ppu_cycles;

    // Trigger DMA
    state.busWrite(0x4014, 0x04);
    try testing.expect(state.dma.active);
    try testing.expect(state.dma.needs_alignment); // Odd start

    // Run DMA to completion
    var tick_count: u32 = 0;
    while (state.dma.active and tick_count < 2000) : (tick_count += 1) {
        state.tick();
    }
    try testing.expect(!state.dma.active); // Ensure DMA completed

    // Calculate elapsed CPU cycles
    const elapsed_ppu = state.clock.ppu_cycles - start_ppu_cycles;
    const elapsed_cpu = elapsed_ppu / 3;

    // Should be exactly 514 CPU cycles (513 + 1 alignment)
    try testing.expectEqual(@as(u64, 514), elapsed_cpu);
}

test "OAM DMA: CPU is stalled during transfer" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Prepare source data
    fillRamPage(state, 0x05, 0x00);

    // Set CPU to known state
    const cpu_pc_before = state.cpu.pc;
    const cpu_cycle_before = state.clock.cpuCycles();

    // Trigger DMA
    state.busWrite(0x4014, 0x05);

    // Run DMA to completion
    var tick_count: u32 = 0;
    while (state.dma.active and tick_count < 2000) : (tick_count += 1) {
        state.tick();
    }
    try testing.expect(!state.dma.active); // Ensure DMA completed

    // CPU should not have executed any instructions
    // PC should be unchanged (CPU was stalled)
    try testing.expectEqual(cpu_pc_before, state.cpu.pc);

    // CPU cycle count should have increased (time passed)
    // but no instructions were executed
    try testing.expect(state.clock.cpuCycles() > cpu_cycle_before);
}

test "OAM DMA: PPU continues running during transfer" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Prepare source data
    fillRamPage(state, 0x06, 0x00);

    // Record PPU state before DMA
    const scanline_before = state.clock.scanline();
    const dot_before = state.clock.dot();

    // Trigger DMA
    state.busWrite(0x4014, 0x06);

    // Run DMA for 100 PPU cycles
    for (0..100) |_| {
        state.tick();
    }

    // PPU timing should have advanced
    const timing_changed = (state.clock.scanline() != scanline_before) or
        (state.clock.dot() != dot_before);
    try testing.expect(timing_changed);
}

// ============================================================================
// Edge Case Tests
// ============================================================================

test "OAM DMA: transfer during VBlank" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Prepare source data before seeking (to avoid timeout)
    fillRamPage(state, 0x01, 0xBB);

    // Use harness helper to seek to VBlank at CPU boundary
    // CRITICAL: Must be at CPU boundary for busWrite to work correctly
    harness.seekToCpuBoundary(241, 0);

    // Clear halted flag (may have been set by illegal opcodes during seek)
    // Without a cartridge, CPU executes from open bus during seek
    state.cpu.halted = false;

    // Trigger DMA during VBlank
    state.busWrite(0x4014, 0x01);

    // Run DMA to completion (DMA = 513-514 CPU cycles = ~1540-1542 PPU cycles)
    var tick_count: u32 = 0;
    while (state.dma.active and tick_count < 2000) : (tick_count += 1) {
        state.tick();
    }
    try testing.expect(!state.dma.active); // Ensure DMA completed

    // Verify transfer completed correctly
    for (0..256) |i| {
        const expected = 0xBB +% @as(u8, @intCast(i));
        try testing.expectEqual(expected, state.ppu.oam[i]);
    }
}

test "OAM DMA: multiple sequential transfers" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // First transfer from page $02
    fillRamPage(state, 0x02, 0x10);
    state.busWrite(0x4014, 0x02);
    while (state.dma.active) {
        state.tick();
    }

    // Verify first transfer
    try testing.expectEqual(@as(u8, 0x10), state.ppu.oam[0]);

    // Second transfer from page $03
    fillRamPage(state, 0x03, 0x20);
    state.busWrite(0x4014, 0x03);
    while (state.dma.active) {
        state.tick();
    }

    // Verify second transfer overwrote OAM
    try testing.expectEqual(@as(u8, 0x20), state.ppu.oam[0]);
}

test "OAM DMA: offset wraps correctly within page" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Test that all 256 bytes transfer correctly (offset wraps from 0xFF to 0x00)
    // Use page $06 (valid RAM region)
    fillRamPage(state, 0x06, 0xCC);
    state.busWrite(0x4014, 0x06);

    while (state.dma.active) {
        state.tick();
    }

    // Verify all 256 bytes transferred (offset wrapped correctly)
    for (0..256) |i| {
        const expected = 0xCC +% @as(u8, @intCast(i));
        try testing.expectEqual(expected, state.ppu.oam[i]);
    }
}

test "OAM DMA: DMA state resets after completion" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Prepare source data
    fillRamPage(state, 0x02, 0x00);

    // Trigger DMA
    state.busWrite(0x4014, 0x02);
    try testing.expect(state.dma.active);

    // Run to completion
    while (state.dma.active) {
        state.tick();
    }

    // Verify DMA state is fully reset
    try testing.expect(!state.dma.active);
    try testing.expectEqual(@as(u8, 0), state.dma.current_offset);
    try testing.expectEqual(@as(u16, 0), state.dma.current_cycle);
    try testing.expect(!state.dma.needs_alignment);
}

test "OAM DMA: transfer integrity with alternating pattern" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Fill with alternating 0xAA/0x55 pattern
    for (0..256) |i| {
        const value: u8 = if (i % 2 == 0) 0xAA else 0x55;
        state.bus.ram[0x0200 + i] = value;
    }

    // Trigger DMA from page $02
    state.busWrite(0x4014, 0x02);

    while (state.dma.active) {
        state.tick();
    }

    // Verify pattern transferred correctly
    for (0..256) |i| {
        const expected: u8 = if (i % 2 == 0) 0xAA else 0x55;
        try testing.expectEqual(expected, state.ppu.oam[i]);
    }
}

// ============================================================================
// Regression Tests
// ============================================================================

test "OAM DMA: reading $4014 returns open bus" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Set open bus value
    state.bus.open_bus = 0x42;

    // Reading $4014 should return open bus (write-only register)
    const value = state.busRead(0x4014);
    try testing.expectEqual(@as(u8, 0x42), value);
}

test "OAM DMA: DMA not triggered on read from $4014" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // Read from $4014 (should not trigger DMA)
    _ = state.busRead(0x4014);

    // DMA should not be active
    try testing.expect(!state.dma.active);
}
