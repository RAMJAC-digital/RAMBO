// OamDmaHandler.zig
//
// Handles $4014 (OAM DMA trigger register).
// Write-only register that starts a 256-byte DMA transfer from CPU RAM to PPU OAM.
//
// Complexity: ⭐⭐ (2/5) - Write triggers DMA, read is trivial
//
// Hardware Reference:
// - nesdev.org/wiki/PPU_OAM#DMA
// - Write to $4014 starts DMA from page ($XX << 8) to OAM
// - Takes 513 or 514 CPU cycles depending on odd/even alignment

const std = @import("std");

/// Handler for $4014 (OAM DMA trigger)
///
/// Writing to $4014 triggers a 256-byte DMA transfer from CPU RAM to PPU OAM.
/// The written value specifies the source page:
/// - Write $02 to $4014 → copies $0200-$02FF to OAM
/// - Write $03 to $4014 → copies $0300-$03FF to OAM
/// - etc.
///
/// Transfer takes 513 or 514 CPU cycles depending on CPU alignment:
/// - If triggered on even cycle: 513 cycles (1 dummy + 512 transfer)
/// - If triggered on odd cycle: 514 cycles (1 alignment + 1 dummy + 512 transfer)
///
/// Pattern: Completely stateless - accesses DMA/clock via state parameter
pub const OamDmaHandler = struct {
    // NO fields - completely stateless!
    // Accesses state.dma and state.clock through parameter

    /// Read from $4014
    ///
    /// Hardware behavior: $4014 is write-only, reads return open bus
    ///
    /// Parameters:
    /// - self: Handler instance (unused - no internal state)
    /// - state: Emulation state containing bus.open_bus
    /// - address: Memory address (always $4014)
    ///
    /// Returns: Open bus value
    pub fn read(_: *const OamDmaHandler, state: anytype, _: u16) u8 {
        // Write-only register - return open bus
        return state.bus.open_bus.get();
    }

    /// Write to $4014 (trigger OAM DMA)
    ///
    /// Starts a 256-byte DMA transfer from CPU RAM to PPU OAM.
    /// The written value specifies the source page number.
    ///
    /// Side effects:
    /// - Sets state.dma.active = true
    /// - Calculates odd/even cycle alignment
    /// - Initiates DMA state machine
    ///
    /// Parameters:
    /// - self: Handler instance (unused - no internal state)
    /// - state: Emulation state containing dma and clock
    /// - address: Memory address (always $4014)
    /// - value: Source page number
    pub fn write(_: *OamDmaHandler, state: anytype, _: u16, value: u8) void {
        // Calculate whether we're on an odd CPU cycle
        // Use MasterClock's cpuCycles() method to get current CPU cycle
        const cpu_cycle = state.clock.cpuCycles();
        const on_odd_cycle = (cpu_cycle & 1) != 0;

        // Trigger DMA transfer
        state.dma.trigger(value, on_odd_cycle);
    }

    /// Peek $4014 (debugger support)
    ///
    /// Same as read() - returns open bus
    ///
    /// Parameters:
    /// - self: Handler instance (unused)
    /// - state: Emulation state containing bus.open_bus
    /// - address: Memory address (always $4014)
    ///
    /// Returns: Open bus value
    pub fn peek(_: *const OamDmaHandler, state: anytype, _: u16) u8 {
        // Same as read() - no side effects
        return state.bus.open_bus.get();
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

const testing = std.testing;

// Test state with minimal DMA/clock
const CpuOpenBus = @import("../../state/BusState.zig").BusState.OpenBus;

const TestState = struct {
    bus: struct {
        open_bus: CpuOpenBus = .{},
    } = .{},
    dma: struct {
        active: bool = false,
        source_page: u8 = 0,
        needs_alignment: bool = false,

        pub fn trigger(self: *@This(), page: u8, on_odd_cycle: bool) void {
            self.active = true;
            self.source_page = page;
            self.needs_alignment = on_odd_cycle;
        }
    } = .{},
    clock: struct {
        ppu_cycles: u64 = 0,

        pub fn cpuCycles(self: @This()) u64 {
            return self.ppu_cycles / 3;
        }
    } = .{},
};

test "OamDmaHandler: read returns open bus" {
    var state = TestState{};
    state.bus.open_bus.set(0xAB);

    var handler = OamDmaHandler{};
    try testing.expectEqual(@as(u8, 0xAB), handler.read(&state, 0x4014));
}

test "OamDmaHandler: write triggers DMA with correct page" {
    var state = TestState{};
    var handler = OamDmaHandler{};

    // Write page $03 to $4014
    handler.write(&state, 0x4014, 0x03);

    // Verify DMA was triggered with correct page
    try testing.expect(state.dma.active);
    try testing.expectEqual(@as(u8, 0x03), state.dma.source_page);
}

test "OamDmaHandler: odd cycle detection (even cycle)" {
    var state = TestState{};
    state.clock.ppu_cycles = 0; // CPU cycle 0 (even)
    var handler = OamDmaHandler{};

    handler.write(&state, 0x4014, 0x02);

    // Even cycle - no alignment needed
    try testing.expect(!state.dma.needs_alignment);
}

test "OamDmaHandler: odd cycle detection (odd cycle)" {
    var state = TestState{};
    state.clock.ppu_cycles = 3; // CPU cycle 1 (odd)
    var handler = OamDmaHandler{};

    handler.write(&state, 0x4014, 0x02);

    // Odd cycle - alignment needed
    try testing.expect(state.dma.needs_alignment);
}

test "OamDmaHandler: odd cycle detection (multiple cycles)" {
    var state = TestState{};
    var handler = OamDmaHandler{};

    // Test several cycles
    const test_cases = [_]struct { ppu_cycles: u64, expected_odd: bool }{
        .{ .ppu_cycles = 0, .expected_odd = false }, // CPU cycle 0
        .{ .ppu_cycles = 3, .expected_odd = true }, // CPU cycle 1
        .{ .ppu_cycles = 6, .expected_odd = false }, // CPU cycle 2
        .{ .ppu_cycles = 9, .expected_odd = true }, // CPU cycle 3
        .{ .ppu_cycles = 12, .expected_odd = false }, // CPU cycle 4
    };

    for (test_cases) |tc| {
        state.clock.ppu_cycles = tc.ppu_cycles;
        state.dma = .{}; // Reset DMA

        handler.write(&state, 0x4014, 0x02);

        try testing.expectEqual(tc.expected_odd, state.dma.needs_alignment);
    }
}

test "OamDmaHandler: peek same as read" {
    var state = TestState{};
    state.bus.open_bus.set(0x55);
    var handler = OamDmaHandler{};

    try testing.expectEqual(
        handler.read(&state, 0x4014),
        handler.peek(&state, 0x4014),
    );
}

test "OamDmaHandler: multiple writes update page" {
    var state = TestState{};
    var handler = OamDmaHandler{};

    // First write
    handler.write(&state, 0x4014, 0x02);
    try testing.expectEqual(@as(u8, 0x02), state.dma.source_page);

    // Second write - should update page
    handler.write(&state, 0x4014, 0x07);
    try testing.expectEqual(@as(u8, 0x07), state.dma.source_page);
}

test "OamDmaHandler: no internal state - handler is empty" {
    // Verify handler has no fields (completely stateless)
    try testing.expectEqual(@as(usize, 0), @sizeOf(OamDmaHandler));
}
