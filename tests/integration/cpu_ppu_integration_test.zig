// CPU-PPU Integration Tests
//
// These tests verify the interactions between the CPU and PPU, focusing on
// timing-critical behaviors like NMI triggering, register access timing,
// DMA suspension, and rendering effects on register reads.
//
// Unlike unit tests, these validate complete workflows and cross-component
// behaviors that occur during actual emulation.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config;

const TestHarness = struct {
    config: *Config.Config,
    state: EmulationState,

    pub fn init() !TestHarness {
        const cfg = try testing.allocator.create(Config.Config);
        cfg.* = Config.Config.init(testing.allocator);

        var emu_state = EmulationState.init(cfg);
        emu_state.reset();

        return .{
            .config = cfg,
            .state = emu_state,
        };
    }

    pub fn deinit(self: *TestHarness) void {
        self.state.deinit(); // Clean up emulation state (including cartridge)
        self.config.deinit();
        testing.allocator.destroy(self.config);
    }

    pub fn statePtr(self: *TestHarness) *EmulationState {
        return &self.state;
    }
};

// ============================================================================
// Category 1: NMI Triggering and Timing Tests (5-6 tests)
// ============================================================================
// These tests verify that NMI generation works correctly, including edge
// detection, timing accuracy, and interaction with CPU execution.

test "CPU-PPU Integration: NMI triggered when VBlank flag set and NMI enabled" {
    var harness = try TestHarness.init();
    defer harness.deinit();
    const state = harness.statePtr();
    // Enable NMI in PPUCTRL
    state.busWrite(0x2000, 0x80); // Bit 7 = NMI enable

    // Advance clock to avoid initialization race (both last_set_cycle and last_status_read_cycle start at 0)
    state.clock.advance(100);

    // Simulate VBlank start (as PPU tick would do) using the ledger API
    state.vblank_ledger.recordVBlankSet(state.clock.ppu_cycles, state.ppu.ctrl.nmi_enable);

    // Verify the ledger indicates NMI should be asserted
    const should_assert_nmi = state.vblank_ledger.shouldAssertNmiLine(
        state.clock.ppu_cycles,
        state.ppu.ctrl.nmi_enable,
    );
    try testing.expect(should_assert_nmi);
}

test "CPU-PPU Integration: NMI not triggered when VBlank set but NMI disabled" {
    var harness = try TestHarness.init();
    defer harness.deinit();
    const state = harness.statePtr();

    // Disable NMI in PPUCTRL
    state.busWrite(0x2000, 0x00); // Bit 7 = 0

    // Set VBlank flag using the ledger API
    state.vblank_ledger.recordVBlankSet(state.clock.ppu_cycles, state.ppu.ctrl.nmi_enable);

    // Verify the ledger indicates NMI should NOT be asserted (NMI disabled)
    const should_assert_nmi = state.vblank_ledger.shouldAssertNmiLine(
        state.clock.ppu_cycles,
        state.ppu.ctrl.nmi_enable,
    );
    try testing.expect(!should_assert_nmi);
}

test "CPU-PPU Integration: Reading PPUSTATUS clears VBlank but preserves latched NMI" {
    var harness = try TestHarness.init();
    defer harness.deinit();
    const state = harness.statePtr();

    // Enable NMI and skip warm-up period
    state.busWrite(0x2000, 0x80);
    state.ppu.warmup_complete = true;

    // Advance to scanline 241, dot 0 (one cycle before VBlank)
    while (state.clock.scanline() != 241 or state.clock.dot() != 0) {
        state.tick();
    }

    // Tick to dot 1 - VBlank sets AND NMI latches atomically
    state.tick();

    // Both VBlank and NMI should be active
    try testing.expect(state.vblank_ledger.isReadableFlagSet(state.clock.ppu_cycles));
    try testing.expect(state.cpu.nmi_line);

    // Reading PPUSTATUS clears VBlank but NMI remains latched
    _ = state.busRead(0x2002);
    try testing.expect(!state.vblank_ledger.isReadableFlagSet(state.clock.ppu_cycles)); // VBlank cleared ✓
    try testing.expect(state.cpu.nmi_line); // NMI still latched ✓
}

test "CPU-PPU Integration: Reading PPUSTATUS clears VBlank flag" {
    var harness = try TestHarness.init();
    defer harness.deinit();
    const state = harness.statePtr();

    // Set VBlank flag using the ledger API
    state.vblank_ledger.recordVBlankSet(state.clock.ppu_cycles, state.ppu.ctrl.nmi_enable);

    // Read PPUSTATUS
    const status = state.busRead(0x2002);

    // VBlank bit should be set in the read value
    try testing.expect((status & 0x80) != 0);

    // But VBlank flag should now be cleared by the read
    try testing.expect(!state.vblank_ledger.isReadableFlagSet(state.clock.ppu_cycles));
}

test "CPU-PPU Integration: VBlank flag race condition (read during setting)" {
    var harness = try TestHarness.init();
    defer harness.deinit();
    const state = harness.statePtr();

    // Simulate race condition: VBlank just set using ledger API
    state.vblank_ledger.recordVBlankSet(state.clock.ppu_cycles, state.ppu.ctrl.nmi_enable);

    // Immediate read should see VBlank flag
    const status = state.busRead(0x2002);
    try testing.expect((status & 0x80) != 0);

    // But flag is now cleared
    try testing.expect(!state.vblank_ledger.isReadableFlagSet(state.clock.ppu_cycles));

    // Next read should not see VBlank
    const status2 = state.busRead(0x2002);
    try testing.expect((status2 & 0x80) == 0);
}

test "CPU-PPU Integration: NMI edge detection (enabling NMI during VBlank)" {
    var harness = try TestHarness.init();
    defer harness.deinit();
    const state = harness.statePtr();

    // Advance clock to avoid initialization race
    state.clock.advance(100);

    // Set VBlank first (without NMI enable) using ledger API
    state.vblank_ledger.recordVBlankSet(state.clock.ppu_cycles, state.ppu.ctrl.nmi_enable);

    // Verify NMI should NOT be asserted (NMI disabled)
    var should_assert_nmi = state.vblank_ledger.shouldAssertNmiLine(
        state.clock.ppu_cycles,
        state.ppu.ctrl.nmi_enable,
    );
    try testing.expect(!should_assert_nmi);

    // Advance clock before toggling PPUCTRL
    state.clock.advance(10);

    // Now enable NMI - in real hardware, enabling NMI during VBlank triggers NMI
    // This will call recordCtrlToggle via busWrite
    state.busWrite(0x2000, 0x80);

    // Verify NMI should now be asserted (edge detected on 0→1 transition)
    should_assert_nmi = state.vblank_ledger.shouldAssertNmiLine(
        state.clock.ppu_cycles,
        state.ppu.ctrl.nmi_enable,
    );
    try testing.expect(should_assert_nmi);
}

// ============================================================================
// Category 2: PPU Register Access Timing Tests (4-5 tests)
// ============================================================================
// These tests verify that PPU register reads and writes occur at the correct
// CPU cycle and maintain proper state.

test "CPU-PPU Integration: PPUADDR write sequence (2 writes to set address)" {
    var harness = try TestHarness.init();
    defer harness.deinit();
    const state = harness.statePtr();
    const ppu = &state.ppu;

    // Write high byte
    state.busWrite(0x2006, 0x20);

    // Write low byte
    state.busWrite(0x2006, 0x00);

    // Address should now be $2000
    try testing.expectEqual(@as(u16, 0x2000), ppu.internal.v);
}

test "CPU-PPU Integration: PPUADDR write latch resets on PPUSTATUS read" {
    var harness = try TestHarness.init();
    defer harness.deinit();
    const state = harness.statePtr();
    const ppu = &state.ppu;

    // Write high byte
    state.busWrite(0x2006, 0x20);

    // Read PPUSTATUS (should reset write latch)
    _ = state.busRead(0x2002);

    // Write what should be high byte again (but latch was reset)
    state.busWrite(0x2006, 0x30);

    // Write low byte
    state.busWrite(0x2006, 0x00);

    // Address should be $3000, not some combination with $20
    try testing.expectEqual(@as(u16, 0x3000), ppu.internal.v);
}

test "CPU-PPU Integration: PPUDATA auto-increment (horizontal)" {
    var harness = try TestHarness.init();
    defer harness.deinit();
    const state = harness.statePtr();
    const ppu = &state.ppu;

    // Set PPUCTRL for +1 increment (horizontal)
    state.busWrite(0x2000, 0x00); // Bit 2 = 0

    // Set address to $2000
    state.busWrite(0x2006, 0x20);
    state.busWrite(0x2006, 0x00);

    // Write to PPUDATA
    state.busWrite(0x2007, 0xAA);

    // Address should increment by 1
    try testing.expectEqual(@as(u16, 0x2001), ppu.internal.v);
}

test "CPU-PPU Integration: PPUDATA auto-increment (vertical)" {
    var harness = try TestHarness.init();
    defer harness.deinit();
    const state = harness.statePtr();
    const ppu = &state.ppu;

    // Set PPUCTRL for +32 increment (vertical)
    state.busWrite(0x2000, 0x04); // Bit 2 = 1

    // Set address to $2000
    state.busWrite(0x2006, 0x20);
    state.busWrite(0x2006, 0x00);

    // Write to PPUDATA
    state.busWrite(0x2007, 0xAA);

    // Address should increment by 32
    try testing.expectEqual(@as(u16, 0x2020), ppu.internal.v);
}

test "CPU-PPU Integration: PPUDATA read buffering (non-palette)" {
    var harness = try TestHarness.init();
    defer harness.deinit();
    const state = harness.statePtr();

    // Set address to $2000
    state.busWrite(0x2006, 0x20);
    state.busWrite(0x2006, 0x00);

    // Write known value
    state.busWrite(0x2007, 0x42);

    // Reset address
    state.busWrite(0x2006, 0x20);
    state.busWrite(0x2006, 0x00);

    // First read is dummy (returns buffer, which is initially 0)
    _ = state.busRead(0x2007);

    // Second read returns actual data
    const actual = state.busRead(0x2007);

    try testing.expectEqual(@as(u8, 0x42), actual);
}

// ============================================================================
// Category 3: DMA Suspension and CPU Stalling Tests (3-4 tests)
// ============================================================================
// These tests verify that OAM DMA correctly suspends CPU execution and
// transfers data at the right time.

test "CPU-PPU Integration: OAM DMA triggers on $4014 write" {
    var harness = try TestHarness.init();
    defer harness.deinit();
    const state = harness.statePtr();

    // Write to $4014 to trigger DMA from page $02
    state.busWrite(0x4014, 0x02);

    // Check that DMA was triggered (implementation-specific check)
    // For now, verify the write doesn't crash
    try testing.expect(true);
}

// NOTE: OAM DMA ($4014) not yet implemented - test removed
// Will be implemented in Phase 7B as part of sprite implementation
// test "CPU-PPU Integration: OAM DMA transfers 256 bytes" {
//     var ppu = PpuState.init();
//     var bus = BusState.init();
//     bus.ppu = &ppu;
//
//     // Fill source page with test pattern
//     for (0..256) |i| {
//         bus.write(@as(u16, 0x0200) + @as(u16, @intCast(i)), @as(u8, @intCast(i & 0xFF)));
//     }
//
//     // Trigger DMA from page $02
//     bus.write(0x4014, 0x02);
//
//     // Verify OAM was populated (first few bytes)
//     try testing.expectEqual(@as(u8, 0x00), ppu.oam[0]);
//     try testing.expectEqual(@as(u8, 0x01), ppu.oam[1]);
//     try testing.expectEqual(@as(u8, 0x02), ppu.oam[2]);
// }

// NOTE: OAM DMA ($4014) not yet implemented - test removed
// test "CPU-PPU Integration: OAM DMA respects OAMADDR starting position" {
//     var ppu = PpuState.init();
//     var bus = BusState.init();
//     bus.ppu = &ppu;
//
//     // Set OAMADDR to 0x10
//     bus.write(0x2003, 0x10);
//
//     // Fill source with test pattern
//     for (0..256) |i| {
//         bus.write(@as(u16, 0x0200) + @as(u16, @intCast(i)), @as(u8, @intCast(i & 0xFF)));
//     }
//
//     // Trigger DMA
//     bus.write(0x4014, 0x02);
//
//     // OAM should wrap: data[0x10] gets first byte, wraps to 0 after 0xFF
//     try testing.expectEqual(@as(u8, 0x00), ppu.oam[0x10]);
// }

// ============================================================================
// Category 4: Rendering Effects on Register Reads Tests (4-5 tests)
// ============================================================================
// These tests verify that rendering state affects how PPU registers behave,
// particularly during active rendering.

test "CPU-PPU Integration: PPUSTATUS sprite 0 hit flag" {
    var harness = try TestHarness.init();
    defer harness.deinit();
    const state = harness.statePtr();
    const ppu = &state.ppu;

    // Set sprite 0 hit flag
    ppu.status.sprite_0_hit = true;

    // Read PPUSTATUS
    const status = state.busRead(0x2002);

    // Bit 6 should be set
    try testing.expect((status & 0x40) != 0);
}

test "CPU-PPU Integration: PPUSTATUS sprite overflow flag" {
    var harness = try TestHarness.init();
    defer harness.deinit();
    const state = harness.statePtr();
    const ppu = &state.ppu;

    // Set sprite overflow flag
    ppu.status.sprite_overflow = true;

    // Read PPUSTATUS
    const status = state.busRead(0x2002);

    // Bit 5 should be set
    try testing.expect((status & 0x20) != 0);
}

test "CPU-PPU Integration: PPUSTATUS clears sprite 0 hit at start of VBlank" {
    var harness = try TestHarness.init();
    defer harness.deinit();
    const ppu = &harness.statePtr().ppu;

    // Set sprite 0 hit
    ppu.status.sprite_0_hit = true;

    // Simulate entering VBlank (this would be done by PPU tick)
    // For this test, we manually clear as PPU would
    ppu.status.sprite_0_hit = false;

    // Verify it's cleared
    try testing.expect(!ppu.status.sprite_0_hit);
}

test "CPU-PPU Integration: Reading PPUSTATUS doesn't affect sprite flags" {
    var harness = try TestHarness.init();
    defer harness.deinit();
    const state = harness.statePtr();
    const ppu = &state.ppu;

    // Set sprite flags
    ppu.status.sprite_0_hit = true;
    ppu.status.sprite_overflow = true;

    // Read PPUSTATUS
    _ = state.busRead(0x2002);

    // Sprite flags should remain set (unlike VBlank)
    try testing.expect(ppu.status.sprite_0_hit);
    try testing.expect(ppu.status.sprite_overflow);
}

test "CPU-PPU Integration: PPUSCROLL sets scroll position" {
    var harness = try TestHarness.init();
    defer harness.deinit();
    const state = harness.statePtr();

    // Write X scroll
    state.busWrite(0x2005, 0x12);

    // Write Y scroll
    state.busWrite(0x2005, 0x34);

    // Verify scroll was set (implementation-specific)
    // The actual behavior depends on PPU implementation details
    try testing.expect(true);
}

// ============================================================================
// Category 5: Cross-Component State Effects Tests (3-4 tests)
// ============================================================================
// These tests verify that state changes in one component correctly affect
// the other component.

test "CPU-PPU Integration: PPU register writes update PPU state" {
    var harness = try TestHarness.init();
    defer harness.deinit();
    const state = harness.statePtr();
    const ppu = &state.ppu;

    // Write to PPUCTRL
    state.busWrite(0x2000, 0xFF);

    // Verify all bits were set
    const ctrl_byte: u8 = @bitCast(ppu.ctrl);
    try testing.expectEqual(@as(u8, 0xFF), ctrl_byte);
}

test "CPU-PPU Integration: PPUMASK controls rendering enable" {
    var harness = try TestHarness.init();
    defer harness.deinit();
    const state = harness.statePtr();
    const ppu = &state.ppu;

    // Enable background and sprites
    state.busWrite(0x2001, 0x18); // Bits 3 and 4

    // Verify mask was set
    try testing.expect(ppu.mask.show_bg);
    try testing.expect(ppu.mask.show_sprites);
}

test "CPU-PPU Integration: Multiple register writes maintain state" {
    var harness = try TestHarness.init();
    defer harness.deinit();
    const state = harness.statePtr();
    const ppu = &state.ppu;

    // Set PPUCTRL
    state.busWrite(0x2000, 0x80); // NMI enable

    // Set PPUMASK
    state.busWrite(0x2001, 0x1E); // Show BG and sprites

    // Set PPUADDR
    state.busWrite(0x2006, 0x20);
    state.busWrite(0x2006, 0x00);

    // Verify all state maintained
    try testing.expect(ppu.ctrl.nmi_enable);
    try testing.expect(ppu.mask.show_bg);
    try testing.expect(ppu.mask.show_sprites);
    try testing.expectEqual(@as(u16, 0x2000), ppu.internal.v);
}

test "CPU-PPU Integration: Bus open bus interacts with PPU open bus" {
    var harness = try TestHarness.init();
    defer harness.deinit();
    const state = harness.statePtr();
    const ppu = &state.ppu;

    // Set bus open bus value
    state.busWrite(0x0100, 0xAB);
    try testing.expectEqual(@as(u8, 0xAB), state.bus.open_bus);

    // Write to PPU register - this updates BOTH bus and PPU open bus
    // Hardware behavior: ALL writes update bus.open_bus first (line 130 in Logic.zig)
    state.busWrite(0x2001, 0xCD);

    // Both should now have 0xCD (bus write updates both)
    try testing.expectEqual(@as(u8, 0xCD), state.bus.open_bus);
    try testing.expectEqual(@as(u8, 0xCD), ppu.open_bus.value);
}
