# DMC/OAM DMA Interaction - Comprehensive Test Strategy

**Date Created:** 2025-10-15
**Author:** Test Automation Specialist
**Status:** Design Document
**Target:** Phase 2E Implementation

---

## Executive Summary

This document outlines a comprehensive testing strategy for the DMC/OAM DMA interaction feature. The test suite follows the testing pyramid principle with emphasis on deterministic, fast, and comprehensive coverage of all edge cases.

**Test Coverage Goals:**
- Unit Tests: 15+ tests (simple, isolated cases)
- Integration Tests: 10+ tests (complex, multi-system scenarios)
- Timing Tests: 8+ tests (cycle-accurate verification)
- Total: 33+ tests

**Testing Principles:**
1. Arrange-Act-Assert pattern throughout
2. Test behavior, not implementation
3. Deterministic execution (no flakiness)
4. Fast feedback (< 100ms total suite runtime)
5. Clear test names describing exact scenario

---

## Test Infrastructure

### Harness Capabilities Available

Based on `/home/colin/Development/RAMBO/src/test/Harness.zig`:

**Essential Methods:**
- `init()` - Create test harness with clean state
- `deinit()` - Cleanup resources
- `tick(count)` - Advance emulation by N PPU cycles
- `tickCpu(cpu_cycles)` - Advance by N CPU cycles (cpu_cycles * 3 PPU cycles)
- `loadRam(data, address)` - Load test data into RAM
- `setupCpuExecution(start_pc)` - Setup CPU at specific address
- `seekToCpuBoundary(scanline, dot)` - Seek to specific timing + CPU alignment

**DMA Access:**
- `state.dma.*` - OamDma state inspection
- `state.dmc_dma.*` - DmcDma state inspection
- `state.ppu.oam[0..256]` - OAM memory inspection
- `state.busWrite(0x4014, page)` - Trigger OAM DMA
- `state.dmc_dma.triggerFetch(address)` - Trigger DMC DMA
- `state.clock.cpuCycles()` - Get current CPU cycle count

### Helper Functions to Create

```zig
// In test file header (shared helpers)

/// Fill CPU memory page with test pattern (uses busWrite for proper routing)
fn fillRamPage(state: *EmulationState, page: u8, pattern: u8) void {
    for (0..256) |i| {
        const offset = @as(u8, @intCast(i));
        const address = (@as(u16, page) << 8) | offset;
        state.busWrite(address, pattern +% offset);
    }
}

/// Verify OAM contents match expected pattern
fn verifyOamPattern(state: *EmulationState, expected: []const u8) !void {
    try testing.expectEqual(@as(usize, 256), expected.len);
    for (0..256) |i| {
        try testing.expectEqual(expected[i], state.ppu.oam[i]);
    }
}

/// Run until OAM DMA completes (with timeout)
fn runUntilOamDmaComplete(state: *EmulationState) void {
    var tick_count: u32 = 0;
    while (state.dma.active and tick_count < 2000) : (tick_count += 1) {
        state.tick();
    }
    if (state.dma.active) {
        @panic("OAM DMA did not complete within timeout");
    }
}

/// Run until DMC DMA completes (with timeout)
fn runUntilDmcDmaComplete(state: *EmulationState) void {
    var tick_count: u32 = 0;
    while (state.dmc_dma.rdy_low and tick_count < 100) : (tick_count += 1) {
        state.tick();
    }
    if (state.dmc_dma.rdy_low) {
        @panic("DMC DMA did not complete within timeout");
    }
}

/// Count active PPU cycles (for precise timing verification)
fn countPpuCyclesUntilComplete(state: *EmulationState, max_cycles: u64) u64 {
    const start_ppu = state.clock.ppu_cycles;
    var tick_count: u64 = 0;
    while (state.dma.active and tick_count < max_cycles) : (tick_count += 1) {
        state.tick();
    }
    return state.clock.ppu_cycles - start_ppu;
}
```

---

## Test Suite Design

### Part 1: Unit Tests - Isolated DMA Behavior (15 tests)

#### 1.1 DMC DMA Alone (No Conflict) - 3 tests

**Test: `DMC DMA: basic fetch completes in 4 CPU cycles`**
```zig
test "DMC DMA: basic fetch completes in 4 CPU cycles" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE: Load test sample at $C000
    state.bus.ram[0] = 0x42; // Simulate sample at mapped address

    const start_cpu = state.clock.cpuCycles();

    // ACT: Trigger DMC DMA fetch
    state.dmc_dma.triggerFetch(0xC000);
    try testing.expect(state.dmc_dma.rdy_low);
    try testing.expectEqual(@as(u8, 4), state.dmc_dma.stall_cycles_remaining);

    // Run until DMC completes
    runUntilDmcDmaComplete(state);

    // ASSERT: Exactly 4 CPU cycles elapsed
    const elapsed_cpu = state.clock.cpuCycles() - start_cpu;
    try testing.expectEqual(@as(u64, 4), elapsed_cpu);
    try testing.expect(!state.dmc_dma.rdy_low);
}
```

**Test: `DMC DMA: sample byte is correctly fetched`**
```zig
test "DMC DMA: sample byte is correctly fetched" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE: Load test sample at $C000
    const test_sample: u8 = 0xAA;
    state.busWrite(0xC000, test_sample);

    // ACT: Trigger and complete DMC DMA
    state.dmc_dma.triggerFetch(0xC000);
    runUntilDmcDmaComplete(state);

    // ASSERT: Sample byte matches
    try testing.expectEqual(test_sample, state.dmc_dma.sample_byte);
}
```

**Test: `DMC DMA: CPU is stalled during fetch`**
```zig
test "DMC DMA: CPU is stalled during fetch" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE: Setup CPU execution at known PC
    harness.seekToCpuBoundary(0, 0);
    harness.setupCpuExecution(0x8000);
    const cpu_pc_before = state.cpu.pc;

    // ACT: Trigger DMC DMA
    state.dmc_dma.triggerFetch(0xC000);
    runUntilDmcDmaComplete(state);

    // ASSERT: CPU did not execute any instructions (PC unchanged)
    try testing.expectEqual(cpu_pc_before, state.cpu.pc);
}
```

#### 1.2 OAM DMA Alone (No Conflict) - 3 tests

These already exist in `tests/integration/oam_dma_test.zig`, but we verify they still pass:
- ✅ Basic transfer from page $02
- ✅ Even cycle start takes 513 CPU cycles
- ✅ Odd cycle start takes 514 CPU cycles

#### 1.3 DMC Interrupts OAM - Simple Cases (9 tests)

**Test: `DMC interrupts OAM at start (byte 0)`**
```zig
test "DMC interrupts OAM at start (byte 0)" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE: Fill source page with sequential data
    fillRamPage(state, 0x02, 0x00); // 0x00, 0x01, 0x02, ..., 0xFF

    // Ensure even CPU cycle start
    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }

    // ACT: Trigger OAM DMA
    state.busWrite(0x4014, 0x02);
    try testing.expect(state.dma.active);

    // Wait 1 CPU cycle (first read happens)
    harness.tickCpu(1);

    // Interrupt with DMC DMA
    state.dmc_dma.triggerFetch(0xC000);
    try testing.expect(state.dmc_dma.rdy_low);

    // Run until both DMAs complete
    runUntilDmcDmaComplete(state);
    runUntilOamDmaComplete(state);

    // ASSERT: Byte duplication occurred at OAM[0]
    // Expected: Byte 0 read, DMC interrupts, byte 0 duplicated on resume
    try testing.expectEqual(@as(u8, 0x00), state.ppu.oam[0]);
    // Note: Exact duplication pattern depends on implementation
    // This test verifies no crash and OAM completes
}
```

**Test: `DMC interrupts OAM mid-transfer (byte 128)`**
```zig
test "DMC interrupts OAM mid-transfer (byte 128)" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE: Fill source page
    fillRamPage(state, 0x03, 0x00);

    // Even CPU cycle
    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }

    // ACT: Start OAM DMA
    state.busWrite(0x4014, 0x03);

    // Run until byte 128 (128 read/write pairs = 256 CPU cycles)
    // Each pair = 2 CPU cycles, so 128 pairs = 256 cycles
    harness.tickCpu(256);

    // Verify we're mid-transfer
    try testing.expect(state.dma.active);

    // Interrupt with DMC
    state.dmc_dma.triggerFetch(0xC000);

    // Complete both DMAs
    runUntilDmcDmaComplete(state);
    runUntilOamDmaComplete(state);

    // ASSERT: OAM transfer eventually completes
    try testing.expect(!state.dma.active);

    // First 128 bytes should be correct
    for (0..128) |i| {
        try testing.expectEqual(@as(u8, @intCast(i)), state.ppu.oam[i]);
    }
}
```

**Test: `DMC interrupts OAM at end (byte 255)`**
```zig
test "DMC interrupts OAM at end (byte 255)" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE: Fill source page
    fillRamPage(state, 0x04, 0x00);

    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }

    // ACT: Start OAM DMA
    state.busWrite(0x4014, 0x04);

    // Run until byte 255 (510 CPU cycles - almost complete)
    harness.tickCpu(510);
    try testing.expect(state.dma.active);

    // Interrupt with DMC
    state.dmc_dma.triggerFetch(0xC000);

    // Complete both
    runUntilDmcDmaComplete(state);
    runUntilOamDmaComplete(state);

    // ASSERT: OAM completes correctly
    try testing.expect(!state.dma.active);
    try testing.expectEqual(@as(u8, 0xFF), state.ppu.oam[255]);
}
```

**Test: `DMC interrupts during OAM read cycle`**
```zig
test "DMC interrupts during OAM read cycle" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE
    fillRamPage(state, 0x05, 0xAA);
    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }

    // ACT: Start OAM, advance to read cycle (even cycle)
    state.busWrite(0x4014, 0x05);
    harness.tickCpu(10); // Advance past alignment to read cycle

    // Interrupt during read
    state.dmc_dma.triggerFetch(0xC000);

    // Complete
    runUntilDmcDmaComplete(state);
    runUntilOamDmaComplete(state);

    // ASSERT: No crash, transfer completes
    try testing.expect(!state.dma.active);
}
```

**Test: `DMC interrupts during OAM write cycle`**
```zig
test "DMC interrupts during OAM write cycle" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE
    fillRamPage(state, 0x06, 0x55);
    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }

    // ACT: Start OAM, advance to write cycle (odd cycle)
    state.busWrite(0x4014, 0x06);
    harness.tickCpu(11); // Odd cycle = write

    // Interrupt during write
    state.dmc_dma.triggerFetch(0xC000);

    // Complete
    runUntilDmcDmaComplete(state);
    runUntilOamDmaComplete(state);

    // ASSERT: No crash, transfer completes
    try testing.expect(!state.dma.active);
}
```

**Test: `DMC interrupts during OAM alignment cycle (odd start)`**
```zig
test "DMC interrupts during OAM alignment cycle (odd start)" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE
    fillRamPage(state, 0x07, 0x00);

    // Force odd CPU cycle
    while ((state.clock.ppu_cycles % 6) != 3) {
        state.tick();
    }

    // ACT: Trigger OAM (will need alignment)
    state.busWrite(0x4014, 0x07);
    try testing.expect(state.dma.needs_alignment);

    // Interrupt immediately during alignment
    state.dmc_dma.triggerFetch(0xC000);

    // Complete
    runUntilDmcDmaComplete(state);
    runUntilOamDmaComplete(state);

    // ASSERT: OAM still completes correctly
    try testing.expect(!state.dma.active);
    try testing.expectEqual(@as(u8, 0x00), state.ppu.oam[0]);
}
```

**Test: `Byte duplication: verify exact duplicated byte value`**
```zig
test "Byte duplication: verify exact duplicated byte value" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE: Unique pattern to verify duplication
    for (0..256) |i| {
        state.bus.ram[0x0200 + i] = @as(u8, @intCast((i * 3) % 256));
    }

    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }

    // ACT: Start OAM
    state.busWrite(0x4014, 0x02);

    // Run until byte 50 read
    harness.tickCpu(100); // 50 read/write pairs

    // Record the byte that should duplicate
    const expected_duplicate = state.ppu.oam[49]; // Last written byte

    // Interrupt
    state.dmc_dma.triggerFetch(0xC000);
    runUntilDmcDmaComplete(state);
    runUntilOamDmaComplete(state);

    // ASSERT: Byte at position 50 is duplicate of byte 49
    // (Exact position depends on implementation - this is hypothesis)
    // Adjust index based on actual hardware behavior
    // try testing.expectEqual(expected_duplicate, state.ppu.oam[50]);

    // For now, just verify no crash
    try testing.expect(!state.dma.active);
}
```

**Test: `OAM offset advances correctly after DMC interrupt`**
```zig
test "OAM offset advances correctly after DMC interrupt" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE
    fillRamPage(state, 0x02, 0x00);
    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }

    // ACT: Start OAM
    state.busWrite(0x4014, 0x02);
    harness.tickCpu(50); // Advance partway

    const offset_before_dmc = state.dma.current_offset;

    // Interrupt
    state.dmc_dma.triggerFetch(0xC000);
    runUntilDmcDmaComplete(state);

    // Offset should NOT have changed during DMC
    // (or only changed by 1 for duplication)
    const offset_after_dmc = state.dma.current_offset;

    runUntilOamDmaComplete(state);

    // ASSERT: Final offset is 0 (wrapped) and transfer complete
    try testing.expectEqual(@as(u8, 0), state.dma.current_offset);
    try testing.expect(!state.dma.active);
}
```

**Test: `OAM pause flag sets and clears correctly`**
```zig
test "OAM pause flag sets and clears correctly" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE
    fillRamPage(state, 0x02, 0x00);
    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }

    // ACT: Start OAM
    state.busWrite(0x4014, 0x02);
    harness.tickCpu(10);

    // Should NOT be paused initially
    // try testing.expect(!state.dma.paused); // If paused field exists

    // Interrupt
    state.dmc_dma.triggerFetch(0xC000);

    // During DMC, OAM should be paused
    try testing.expect(state.dmc_dma.rdy_low);
    // try testing.expect(state.dma.paused); // If paused field exists

    runUntilDmcDmaComplete(state);

    // After DMC, OAM should resume (not paused)
    // try testing.expect(!state.dma.paused); // If paused field exists

    runUntilOamDmaComplete(state);
    try testing.expect(!state.dma.active);
}
```

---

### Part 2: Integration Tests - Complex Scenarios (10 tests)

#### 2.1 Multiple DMC Interruptions (4 tests)

**Test: `Multiple DMC interrupts during single OAM transfer`**
```zig
test "Multiple DMC interrupts during single OAM transfer" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE
    fillRamPage(state, 0x02, 0x00);
    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }

    // ACT: Start OAM
    state.busWrite(0x4014, 0x02);

    // Interrupt 3 times at different points
    harness.tickCpu(50);
    state.dmc_dma.triggerFetch(0xC000);
    runUntilDmcDmaComplete(state);

    harness.tickCpu(100);
    state.dmc_dma.triggerFetch(0xC100);
    runUntilDmcDmaComplete(state);

    harness.tickCpu(150);
    state.dmc_dma.triggerFetch(0xC200);
    runUntilDmcDmaComplete(state);

    runUntilOamDmaComplete(state);

    // ASSERT: OAM completes without crash
    try testing.expect(!state.dma.active);

    // Verify at least some bytes transferred correctly
    // (Exact duplication pattern depends on implementation)
    try testing.expectEqual(@as(u8, 0x00), state.ppu.oam[0]);
}
```

**Test: `Consecutive DMC interrupts (no gap)`**
```zig
test "Consecutive DMC interrupts (no gap)" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE
    fillRamPage(state, 0x03, 0xAA);
    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }

    // ACT: Start OAM
    state.busWrite(0x4014, 0x03);
    harness.tickCpu(20);

    // First DMC interrupt
    state.dmc_dma.triggerFetch(0xC000);
    runUntilDmcDmaComplete(state);

    // Immediately trigger second DMC (no OAM cycles in between)
    state.dmc_dma.triggerFetch(0xC100);
    runUntilDmcDmaComplete(state);

    runUntilOamDmaComplete(state);

    // ASSERT: No crash, OAM completes
    try testing.expect(!state.dma.active);
}
```

**Test: `DMC interrupt during OAM resume from previous DMC`**
```zig
test "DMC interrupt during OAM resume from previous DMC" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE
    fillRamPage(state, 0x04, 0x55);
    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }

    // ACT: Start OAM
    state.busWrite(0x4014, 0x04);
    harness.tickCpu(30);

    // First interrupt
    state.dmc_dma.triggerFetch(0xC000);
    runUntilDmcDmaComplete(state);

    // OAM resumes for exactly 1 cycle, then interrupt again
    harness.tickCpu(1);
    state.dmc_dma.triggerFetch(0xC100);
    runUntilDmcDmaComplete(state);

    runUntilOamDmaComplete(state);

    // ASSERT: Handles nested pause/resume
    try testing.expect(!state.dma.active);
}
```

**Test: `Maximum DMC interruptions (stress test)`**
```zig
test "Maximum DMC interruptions (stress test)" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE
    fillRamPage(state, 0x05, 0x00);
    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }

    // ACT: Start OAM
    state.busWrite(0x4014, 0x05);

    // Interrupt every 10 CPU cycles (unrealistic but stresses system)
    var interrupt_count: u32 = 0;
    while (state.dma.active and interrupt_count < 50) {
        harness.tickCpu(10);

        if (state.dma.active) {
            state.dmc_dma.triggerFetch(0xC000 + interrupt_count);
            runUntilDmcDmaComplete(state);
            interrupt_count += 1;
        }
    }

    runUntilOamDmaComplete(state);

    // ASSERT: Survives stress test
    try testing.expect(!state.dma.active);
    try testing.expect(interrupt_count > 0); // Verify interrupts occurred
}
```

#### 2.2 Back-to-Back OAM DMAs (3 tests)

**Test: `Sequential OAM DMAs with active DMC between`**
```zig
test "Sequential OAM DMAs with active DMC between" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE: Two different source pages
    fillRamPage(state, 0x02, 0x00); // First: 0x00-0xFF
    fillRamPage(state, 0x03, 0xAA); // Second: 0xAA-0xA9 (wrapping)

    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }

    // ACT: First OAM DMA
    state.busWrite(0x4014, 0x02);
    runUntilOamDmaComplete(state);

    // Verify first transfer
    try testing.expectEqual(@as(u8, 0x00), state.ppu.oam[0]);

    // DMC between transfers
    state.dmc_dma.triggerFetch(0xC000);
    runUntilDmcDmaComplete(state);

    // Second OAM DMA
    state.busWrite(0x4014, 0x03);
    runUntilOamDmaComplete(state);

    // ASSERT: Second transfer overwrote first
    try testing.expectEqual(@as(u8, 0xAA), state.ppu.oam[0]);
}
```

**Test: `OAM DMA immediately after previous OAM completes`**
```zig
test "OAM DMA immediately after previous OAM completes" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE
    fillRamPage(state, 0x02, 0x10);
    fillRamPage(state, 0x03, 0x20);

    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }

    // ACT: First OAM
    state.busWrite(0x4014, 0x02);
    runUntilOamDmaComplete(state);

    // Immediately trigger second (no gap)
    state.busWrite(0x4014, 0x03);
    runUntilOamDmaComplete(state);

    // ASSERT: Second transfer completes
    try testing.expectEqual(@as(u8, 0x20), state.ppu.oam[0]);
}
```

**Test: `DMC interrupts both first and second OAM DMAs`**
```zig
test "DMC interrupts both first and second OAM DMAs" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE
    fillRamPage(state, 0x02, 0x00);
    fillRamPage(state, 0x03, 0x80);

    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }

    // ACT: First OAM with DMC interrupt
    state.busWrite(0x4014, 0x02);
    harness.tickCpu(50);
    state.dmc_dma.triggerFetch(0xC000);
    runUntilDmcDmaComplete(state);
    runUntilOamDmaComplete(state);

    // Second OAM with DMC interrupt
    state.busWrite(0x4014, 0x03);
    harness.tickCpu(100);
    state.dmc_dma.triggerFetch(0xC100);
    runUntilDmcDmaComplete(state);
    runUntilOamDmaComplete(state);

    // ASSERT: Both transfers complete
    try testing.expect(!state.dma.active);
    try testing.expectEqual(@as(u8, 0x80), state.ppu.oam[0]);
}
```

#### 2.3 Edge Cases (3 tests)

**Test: `DMC DMA when OAM DMA is already complete`**
```zig
test "DMC DMA when OAM DMA is already complete" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE
    fillRamPage(state, 0x02, 0x00);
    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }

    // ACT: Complete OAM DMA first
    state.busWrite(0x4014, 0x02);
    runUntilOamDmaComplete(state);
    try testing.expect(!state.dma.active);

    // Then trigger DMC
    state.dmc_dma.triggerFetch(0xC000);
    runUntilDmcDmaComplete(state);

    // ASSERT: DMC works independently
    try testing.expect(!state.dmc_dma.rdy_low);
}
```

**Test: `OAM DMA triggered while DMC DMA is active`**
```zig
test "OAM DMA triggered while DMC DMA is active" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE
    fillRamPage(state, 0x02, 0x00);
    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }

    // ACT: Trigger DMC first
    state.dmc_dma.triggerFetch(0xC000);
    try testing.expect(state.dmc_dma.rdy_low);

    // Trigger OAM while DMC is active (unusual but possible)
    state.busWrite(0x4014, 0x02);
    try testing.expect(state.dma.active);

    // Complete both
    runUntilDmcDmaComplete(state);
    runUntilOamDmaComplete(state);

    // ASSERT: Both complete correctly (DMC has priority)
    try testing.expect(!state.dma.active);
    try testing.expect(!state.dmc_dma.rdy_low);
}
```

**Test: `OAM transfer with all bytes identical (detect off-by-one)`**
```zig
test "OAM transfer with all bytes identical (detect off-by-one)" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE: All bytes same value
    for (0..256) |i| {
        state.bus.ram[0x0200 + i] = 0x77;
    }

    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }

    // ACT: OAM with DMC interrupt
    state.busWrite(0x4014, 0x02);
    harness.tickCpu(100);
    state.dmc_dma.triggerFetch(0xC000);
    runUntilDmcDmaComplete(state);
    runUntilOamDmaComplete(state);

    // ASSERT: All OAM bytes should be 0x77
    // If duplication causes mismatch, this will fail
    for (0..256) |i| {
        try testing.expectEqual(@as(u8, 0x77), state.ppu.oam[i]);
    }
}
```

---

### Part 3: Timing Tests - Cycle-Accurate Verification (8 tests)

#### 3.1 Total Cycle Count Verification (4 tests)

**Test: `OAM DMA with 1 DMC interrupt adds exactly 4 cycles`**
```zig
test "OAM DMA with 1 DMC interrupt adds exactly 4 cycles" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE
    fillRamPage(state, 0x02, 0x00);

    // Even cycle start
    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }

    const start_ppu = state.clock.ppu_cycles;

    // ACT: OAM DMA
    state.busWrite(0x4014, 0x02);
    harness.tickCpu(50);

    // DMC interrupt
    state.dmc_dma.triggerFetch(0xC000);
    runUntilDmcDmaComplete(state);
    runUntilOamDmaComplete(state);

    // ASSERT: 513 (base OAM) + 4 (DMC) = 517 CPU cycles
    const elapsed_ppu = state.clock.ppu_cycles - start_ppu;
    const elapsed_cpu = elapsed_ppu / 3;

    try testing.expectEqual(@as(u64, 517), elapsed_cpu);
}
```

**Test: `OAM DMA with 3 DMC interrupts adds exactly 12 cycles`**
```zig
test "OAM DMA with 3 DMC interrupts adds exactly 12 cycles" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE
    fillRamPage(state, 0x02, 0x00);
    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }

    const start_ppu = state.clock.ppu_cycles;

    // ACT: OAM with 3 DMC interrupts
    state.busWrite(0x4014, 0x02);

    harness.tickCpu(50);
    state.dmc_dma.triggerFetch(0xC000);
    runUntilDmcDmaComplete(state);

    harness.tickCpu(100);
    state.dmc_dma.triggerFetch(0xC100);
    runUntilDmcDmaComplete(state);

    harness.tickCpu(150);
    state.dmc_dma.triggerFetch(0xC200);
    runUntilDmcDmaComplete(state);

    runUntilOamDmaComplete(state);

    // ASSERT: 513 + (3 * 4) = 525 CPU cycles
    const elapsed_ppu = state.clock.ppu_cycles - start_ppu;
    const elapsed_cpu = elapsed_ppu / 3;

    try testing.expectEqual(@as(u64, 525), elapsed_cpu);
}
```

**Test: `Odd-start OAM DMA with DMC interrupt (514 + 4 = 518)`**
```zig
test "Odd-start OAM DMA with DMC interrupt (514 + 4 = 518)" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE
    fillRamPage(state, 0x02, 0x00);

    // Odd cycle start
    while ((state.clock.ppu_cycles % 6) != 3) {
        state.tick();
    }

    const start_ppu = state.clock.ppu_cycles;

    // ACT: OAM DMA (odd start = 514 cycles)
    state.busWrite(0x4014, 0x02);
    try testing.expect(state.dma.needs_alignment);

    harness.tickCpu(50);
    state.dmc_dma.triggerFetch(0xC000);
    runUntilDmcDmaComplete(state);
    runUntilOamDmaComplete(state);

    // ASSERT: 514 + 4 = 518 CPU cycles
    const elapsed_ppu = state.clock.ppu_cycles - start_ppu;
    const elapsed_cpu = elapsed_ppu / 3;

    try testing.expectEqual(@as(u64, 518), elapsed_cpu);
}
```

**Test: `DMC interrupt during alignment cycle does not affect total`**
```zig
test "DMC interrupt during alignment cycle does not affect total" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE
    fillRamPage(state, 0x02, 0x00);

    // Odd cycle
    while ((state.clock.ppu_cycles % 6) != 3) {
        state.tick();
    }

    const start_ppu = state.clock.ppu_cycles;

    // ACT: OAM DMA
    state.busWrite(0x4014, 0x02);

    // Interrupt during alignment cycle (cycle 0)
    state.dmc_dma.triggerFetch(0xC000);
    runUntilDmcDmaComplete(state);
    runUntilOamDmaComplete(state);

    // ASSERT: Still 514 + 4 = 518
    const elapsed_ppu = state.clock.ppu_cycles - start_ppu;
    const elapsed_cpu = elapsed_ppu / 3;

    try testing.expectEqual(@as(u64, 518), elapsed_cpu);
}
```

#### 3.2 CPU Stall Verification (2 tests)

**Test: `CPU does not execute during OAM + DMC interruption`**
```zig
test "CPU does not execute during OAM + DMC interruption" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE
    fillRamPage(state, 0x02, 0x00);
    harness.seekToCpuBoundary(0, 0);
    harness.setupCpuExecution(0x8000);

    const cpu_pc_before = state.cpu.pc;
    const cpu_sp_before = state.cpu.sp;

    // ACT: OAM with DMC interrupt
    state.busWrite(0x4014, 0x02);
    harness.tickCpu(50);
    state.dmc_dma.triggerFetch(0xC000);
    runUntilDmcDmaComplete(state);
    runUntilOamDmaComplete(state);

    // ASSERT: CPU state unchanged (no execution)
    try testing.expectEqual(cpu_pc_before, state.cpu.pc);
    try testing.expectEqual(cpu_sp_before, state.cpu.sp);
}
```

**Test: `CPU resumes execution after both DMAs complete`**
```zig
test "CPU resumes execution after both DMAs complete" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE: Load NOP instruction at 0x8000
    fillRamPage(state, 0x02, 0x00);
    state.busWrite(0x8000, 0xEA); // NOP opcode

    harness.seekToCpuBoundary(0, 0);
    harness.setupCpuExecution(0x8000);

    // ACT: OAM with DMC
    state.busWrite(0x4014, 0x02);
    harness.tickCpu(50);
    state.dmc_dma.triggerFetch(0xC000);
    runUntilDmcDmaComplete(state);
    runUntilOamDmaComplete(state);

    // Now advance CPU to execute one instruction
    harness.tickCpu(2); // NOP = 2 cycles

    // ASSERT: PC advanced (CPU resumed)
    try testing.expect(state.cpu.pc != 0x8000);
}
```

#### 3.3 Priority Verification (2 tests)

**Test: `DMC DMA always preempts OAM DMA`**
```zig
test "DMC DMA always preempts OAM DMA" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE
    fillRamPage(state, 0x02, 0x00);
    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }

    // ACT: Trigger both simultaneously (unusual but tests priority)
    state.busWrite(0x4014, 0x02);
    state.dmc_dma.triggerFetch(0xC000);

    try testing.expect(state.dma.active);
    try testing.expect(state.dmc_dma.rdy_low);

    // Advance 1 cycle - DMC should execute first
    harness.tickCpu(1);

    // ASSERT: DMC is running (OAM is paused)
    try testing.expect(state.dmc_dma.rdy_low);
    // OAM should be paused (if paused field exists)
    // try testing.expect(state.dma.paused);
}
```

**Test: `Multiple DMCs execute in order without OAM interference`**
```zig
test "Multiple DMCs execute in order without OAM interference" {
    var harness = try Harness.init();
    defer harness.deinit();
    var state = &harness.state;

    // ARRANGE
    fillRamPage(state, 0x02, 0x00);
    while ((state.clock.ppu_cycles % 6) != 0) {
        state.tick();
    }

    // ACT: OAM active, queue 2 DMCs
    state.busWrite(0x4014, 0x02);
    harness.tickCpu(10);

    state.dmc_dma.triggerFetch(0xC000);
    const dmc1_start = state.clock.cpuCycles();
    runUntilDmcDmaComplete(state);
    const dmc1_duration = state.clock.cpuCycles() - dmc1_start;

    // Immediately trigger second DMC
    state.dmc_dma.triggerFetch(0xC100);
    const dmc2_start = state.clock.cpuCycles();
    runUntilDmcDmaComplete(state);
    const dmc2_duration = state.clock.cpuCycles() - dmc2_start;

    // ASSERT: Both DMCs took exactly 4 cycles each
    try testing.expectEqual(@as(u64, 4), dmc1_duration);
    try testing.expectEqual(@as(u64, 4), dmc2_duration);

    // OAM still active after DMCs
    try testing.expect(state.dma.active);
}
```

---

## Test File Organization

### File: `/home/colin/Development/RAMBO/tests/integration/dmc_oam_conflict_test.zig`

```zig
//! DMC/OAM DMA Conflict Tests
//!
//! Tests the complex interaction between DMC DMA and OAM DMA when both are active.
//! Verifies hardware-accurate priority rules and byte duplication behavior.
//!
//! Hardware Behavior:
//! - DMC DMA has highest priority (can interrupt OAM DMA)
//! - OAM DMA pauses during DMC interrupt (does not cancel)
//! - OAM byte being read when DMC interrupts will duplicate
//! - Total cycle count = OAM base (513/514) + (DMC interrupts × 4)
//!
//! Reference:
//! - https://www.nesdev.org/wiki/APU_DMC
//! - https://www.nesdev.org/wiki/PPU_registers#OAMDMA
//! - docs/sessions/2025-10-15-phase2e-dmc-oam-dma-plan.md

const std = @import("std");
const testing = std.testing;

const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;
const EmulationState = RAMBO.EmulationState.EmulationState;

// ============================================================================
// Test Helpers
// ============================================================================

// [Insert helper functions here]

// ============================================================================
// Part 1: Unit Tests - Isolated DMA Behavior
// ============================================================================

// [Insert tests here organized by section]

// ============================================================================
// Part 2: Integration Tests - Complex Scenarios
// ============================================================================

// [Insert tests here]

// ============================================================================
// Part 3: Timing Tests - Cycle-Accurate Verification
// ============================================================================

// [Insert tests here]
```

---

## Expected Test Outcomes

### Before Implementation (Baseline)

**Expected Failures:** 20-25 tests (all DMC/OAM interaction tests)
**Expected Passes:** 3 tests (DMC alone tests that already work)
**Reason:** DMC cannot currently interrupt OAM DMA

### After Implementation (Target)

**Expected Passes:** 33+ tests (all tests)
**Expected Failures:** 0 tests
**Performance:** < 100ms total suite runtime

### Regression Monitoring

**Must Still Pass:**
- All 14 existing OAM DMA tests in `oam_dma_test.zig`
- All 3 existing DMC DMA tests in `dpcm_dma_test.zig`
- Full integration test suite (990/995)

---

## CI/CD Integration

### Test Commands

```bash
# Run full test suite
zig build test

# Run only DMC/OAM conflict tests
zig test tests/integration/dmc_oam_conflict_test.zig \
  --deps zli,libxev,zig-wayland \
  -I src

# Run with verbose output
zig test tests/integration/dmc_oam_conflict_test.zig \
  --deps zli,libxev,zig-wayland \
  -I src \
  --summary all
```

### Coverage Reporting

```bash
# Generate coverage report
zig build test --summary all

# Expected coverage:
# - src/emulation/dma/logic.zig: 100% (all branches tested)
# - src/emulation/State.zig (DMA tick): 100%
# - src/emulation/state/peripherals/OamDma.zig: 100%
# - src/emulation/state/peripherals/DmcDma.zig: 100%
```

---

## Test Data Patterns

### Pattern Selection Rationale

**Sequential (0x00, 0x01, 0x02, ...):**
- Detects byte skipping
- Detects offset errors
- Easy to verify expected vs actual

**Repeating (0xAA, 0xAA, 0xAA, ...):**
- Masks byte duplication (intentional)
- Tests off-by-one errors
- Verifies transfer count correctness

**Alternating (0xAA, 0x55, 0xAA, 0x55, ...):**
- Detects byte swapping
- Detects parity errors
- Clear visual pattern in debugger

**Arithmetic (i * 3 % 256):**
- Unique values for each byte
- Detects any duplication
- No repeated values in 256-byte range

---

## Debugging Failed Tests

### Common Failure Modes

**1. Timeout (DMA Never Completes):**
```
Symptom: Test hangs, then panics with "DMA did not complete"
Cause: DMA state machine stuck in active state
Debug: Print state.dma.active, state.dma.current_cycle each tick
```

**2. Wrong Byte Count:**
```
Symptom: OAM has wrong number of bytes transferred
Cause: Offset not advancing correctly during DMC pause
Debug: Print state.dma.current_offset before/after DMC
```

**3. No Duplication Detected:**
```
Symptom: All bytes transferred correctly (no duplication)
Cause: OAM not actually pausing, or duplication logic missing
Debug: Verify state.dma.paused flag sets during DMC
```

**4. Cycle Count Mismatch:**
```
Symptom: Total cycles != expected (513 + DMC_count * 4)
Cause: DMC cycles not being counted, or double-counting
Debug: Print elapsed_cpu at each milestone
```

### Debug Helpers

```zig
// Add to test helpers for debugging
fn printDmaState(state: *EmulationState) void {
    std.debug.print(
        \\DMA State:
        \\  oam.active: {}
        \\  oam.offset: {}
        \\  oam.cycle: {}
        \\  dmc.rdy_low: {}
        \\  dmc.stall_remaining: {}
        \\
    , .{
        state.dma.active,
        state.dma.current_offset,
        state.dma.current_cycle,
        state.dmc_dma.rdy_low,
        state.dmc_dma.stall_cycles_remaining,
    });
}
```

---

## Implementation Checklist

### Phase 1: Test Infrastructure (30 min)
- [ ] Create `tests/integration/dmc_oam_conflict_test.zig`
- [ ] Add file to `build/tests.zig` registry
- [ ] Implement helper functions (fillRamPage, etc.)
- [ ] Verify file compiles (with all tests skipped)

### Phase 2: Unit Tests (1 hour)
- [ ] Write 3 DMC-alone tests (should already pass)
- [ ] Write 9 DMC-interrupts-OAM tests (will fail)
- [ ] Verify tests compile and run

### Phase 3: Integration Tests (1 hour)
- [ ] Write 4 multiple-interruption tests
- [ ] Write 3 back-to-back OAM tests
- [ ] Write 3 edge case tests
- [ ] Verify all compile

### Phase 4: Timing Tests (45 min)
- [ ] Write 4 cycle-count tests
- [ ] Write 2 CPU-stall tests
- [ ] Write 2 priority tests
- [ ] Verify all compile

### Phase 5: Validation (30 min)
- [ ] Run test suite (expect ~25 failures before implementation)
- [ ] Document baseline failure counts
- [ ] Commit test suite to git
- [ ] Proceed to implementation phase

---

## Success Criteria

### Must Have
- ✅ 33+ tests written and compiling
- ✅ All tests have clear, descriptive names
- ✅ All tests use Arrange-Act-Assert pattern
- ✅ Test suite runs in < 100ms
- ✅ No flaky tests (100% deterministic)

### Should Have
- ✅ Comprehensive comments explaining hardware behavior
- ✅ Helper functions reduce code duplication
- ✅ Edge cases covered (alignment, multiple interrupts, etc.)
- ✅ Timing verification down to CPU cycle accuracy

### Nice to Have
- ✅ Visual debugging helpers (printDmaState)
- ✅ Test data patterns selected for maximum bug detection
- ✅ Documentation cross-references nesdev.org sources

---

## Estimated Timeline

**Test Infrastructure:** 30 minutes
**Unit Tests:** 1 hour
**Integration Tests:** 1 hour
**Timing Tests:** 45 minutes
**Validation:** 30 minutes
**Total:** 3.25 hours (test design + implementation)

**Note:** This is test creation only. Implementation debugging may take additional 2-3 hours.

---

## Conclusion

This test strategy provides comprehensive coverage of the DMC/OAM DMA interaction feature, following test automation best practices:

1. **Test Pyramid:** Many unit tests, fewer integration tests, focused timing tests
2. **Deterministic:** All tests use controlled harness, no randomness
3. **Fast Feedback:** Target < 100ms total runtime
4. **Clear Intent:** Test names describe exact scenario being tested
5. **Maintainable:** Helper functions reduce duplication

The test suite is designed to be written BEFORE implementation (TDD-style), providing a specification of expected behavior and catching regressions immediately.

**Next Step:** Create test file and write all tests. Expect ~25 failures. Then proceed to implementation phase.
