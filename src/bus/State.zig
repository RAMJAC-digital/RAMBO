//! Bus State
//!
//! This module defines the pure data structures for the NES memory bus state.
//! Following the hybrid architecture pattern: State contains only data, Logic contains functions.

const std = @import("std");

/// Open bus state tracking
/// The NES data bus is not driven during reads from unmapped regions,
/// so it retains the last value that was on the bus
pub const OpenBus = struct {
    /// Last value on the data bus
    /// This value persists when reading from unmapped memory regions
    value: u8 = 0,

    /// Cycle when the value was last updated
    /// Tracked for potential decay simulation (though NES doesn't decay quickly)
    last_update_cycle: u64 = 0,

    /// Update the open bus value
    /// Called on every read and write operation
    pub inline fn update(self: *OpenBus, value: u8, cycle: u64) void {
        self.value = value;
        self.last_update_cycle = cycle;
    }

    /// Read the current open bus value
    /// Returns the last value that was on the data bus
    pub inline fn read(self: *const OpenBus) u8 {
        return self.value;
    }
};

/// Complete NES Memory Bus State
/// This is a pure data structure with no hidden state or pointers to other components.
/// All component references (Cartridge, PPU) are passed to Logic functions as parameters.
pub const State = struct {
    // ===== Owned Memory Regions =====

    /// Internal RAM: 2KB ($0000-$07FF)
    /// Mirrored through $0000-$1FFF (4 times total)
    /// AccuracyCoin Test: "RAM Mirroring" - 13-bit address space mirrors 11-bit RAM
    ram: [2048]u8 = std.mem.zeroes([2048]u8),

    /// Cycle counter for timing-sensitive operations
    /// Incremented by Logic.tick() function
    /// Used for open bus decay tracking and debugging
    cycle: u64 = 0,

    /// Open bus state tracking
    /// Maintains the last value on the data bus for unmapped reads
    /// Critical for hardware accuracy
    open_bus: OpenBus = .{},

    /// Test RAM for unit testing ($8000-$FFFF)
    /// Only used when no cartridge is loaded
    /// Allows tests to write interrupt vectors and test code without a full ROM
    /// This is a slice to allow flexibility in test setup
    test_ram: ?[]u8 = null,

    // Note: Cartridge and PPU are NOT part of State
    // They are passed as parameters to Logic functions
    // This maintains zero coupling and clean separation of concerns

    /// Initialize bus state with zeroed RAM
    /// Returns a clean bus state ready for emulation
    pub fn init() State {
        return .{
            .ram = std.mem.zeroes([2048]u8),
            .cycle = 0,
            .open_bus = .{},
            .test_ram = null,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "Bus State: initialization" {
    const state = State.init();

    // RAM should be zeroed
    for (state.ram) |byte| {
        try testing.expectEqual(@as(u8, 0), byte);
    }

    // Cycle counter should be zero
    try testing.expectEqual(@as(u64, 0), state.cycle);

    // Open bus should start at 0
    try testing.expectEqual(@as(u8, 0), state.open_bus.value);

    // Test RAM should be null
    try testing.expect(state.test_ram == null);
}

test "OpenBus: update and read" {
    var open_bus = OpenBus{};

    // Initial state
    try testing.expectEqual(@as(u8, 0), open_bus.read());

    // Update with value
    open_bus.update(0x42, 100);
    try testing.expectEqual(@as(u8, 0x42), open_bus.read());
    try testing.expectEqual(@as(u64, 100), open_bus.last_update_cycle);

    // Update again
    open_bus.update(0xFF, 200);
    try testing.expectEqual(@as(u8, 0xFF), open_bus.read());
    try testing.expectEqual(@as(u64, 200), open_bus.last_update_cycle);
}

test "Bus State: default initialization with struct literal" {
    const state = State{};

    // Should have default values
    try testing.expectEqual(@as(u64, 0), state.cycle);
    try testing.expectEqual(@as(u8, 0), state.open_bus.value);
    try testing.expect(state.test_ram == null);
}

test "Bus State: RAM is writable" {
    var state = State.init();

    // Write to RAM directly (Logic functions will do this)
    state.ram[0] = 0x42;
    try testing.expectEqual(@as(u8, 0x42), state.ram[0]);

    // Write to different address
    state.ram[0x07FF] = 0xFF;
    try testing.expectEqual(@as(u8, 0xFF), state.ram[0x07FF]);
}

test "Bus State: cycle counter is mutable" {
    var state = State.init();

    state.cycle = 1000;
    try testing.expectEqual(@as(u64, 1000), state.cycle);

    state.cycle += 1;
    try testing.expectEqual(@as(u64, 1001), state.cycle);
}

test "Bus State: test_ram can be set" {
    var state = State.init();
    var test_buffer = [_]u8{0} ** 0x8000; // 32KB for ROM space

    state.test_ram = &test_buffer;
    try testing.expect(state.test_ram != null);

    // Can write through slice
    if (state.test_ram) |ram| {
        ram[0] = 0xAB;
        try testing.expectEqual(@as(u8, 0xAB), ram[0]);
    }
}
