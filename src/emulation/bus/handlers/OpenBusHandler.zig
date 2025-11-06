// OpenBusHandler.zig
//
// Handles reads/writes to unmapped memory regions (open bus behavior).
// Returns the last value present on the data bus with optional decay.
//
// Complexity: ⭐ (1/5) - No side effects, just state storage
//
// Hardware Reference:
// - Mesen2: Core/NES/OpenBusHandler.h
// - nesdev.org: Reading unmapped regions returns last bus value

const std = @import("std");

/// Handler for unmapped memory regions (open bus behavior)
///
/// The NES data bus retains the last value transferred across it.
/// When reading from unmapped regions, this value is returned.
///
/// Pattern: Completely stateless - accesses bus.open_bus via state parameter
pub const OpenBusHandler = struct {
    // NO fields - completely stateless!
    // Accesses state.bus.open_bus through parameter

    /// Read from open bus (unmapped region)
    ///
    /// Parameters:
    /// - self: Handler instance (unused - no internal state)
    /// - state: Emulation state containing bus.open_bus
    /// - address: Memory address (unused - all unmapped regions behave same)
    ///
    /// Returns: Current open bus value
    pub fn read(_: *const OpenBusHandler, state: anytype, _: u16) u8 {
        return state.bus.open_bus.get();
    }

    /// Write to open bus (unmapped region)
    ///
    /// Hardware behavior: Writes to unmapped regions are ignored
    /// (but the value still appears on the bus and gets captured by bus layer)
    ///
    /// Parameters:
    /// - self: Handler instance (unused)
    /// - state: Emulation state (unused)
    /// - address: Memory address (unused)
    /// - value: Value written (unused - bus layer handles bus capture)
    pub fn write(_: *OpenBusHandler, _: anytype, _: u16, _: u8) void {
        // Hardware behavior: Writes to unmapped regions are ignored
        // The bus layer captures the bus value in state.bus.open_bus
    }

    /// Peek open bus value (debugger support)
    ///
    /// Same as read() - no side effects anyway
    ///
    /// Parameters:
    /// - self: Handler instance (unused)
    /// - state: Emulation state containing bus.open_bus
    /// - address: Memory address (unused)
    ///
    /// Returns: Current open bus value
    pub fn peek(_: *const OpenBusHandler, state: anytype, _: u16) u8 {
        return state.bus.open_bus.get();
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

const testing = std.testing;
const CpuOpenBus = @import("../../state/BusState.zig").BusState.OpenBus;

// Test state with minimal bus
const TestState = struct {
    bus: struct {
        open_bus: CpuOpenBus = .{},
    } = .{},
};

test "OpenBusHandler: initial value is zero" {
    var state = TestState{};
    var handler = OpenBusHandler{};
    try testing.expectEqual(@as(u8, 0), handler.read(&state, 0x0000));
}

test "OpenBusHandler: reads current open bus value" {
    var state = TestState{};
    var handler = OpenBusHandler{};

    // Set bus value
    state.bus.open_bus.set(0x42);
    try testing.expectEqual(@as(u8, 0x42), handler.read(&state, 0x0000));

    // Change bus value
    state.bus.open_bus.set(0xFF);
    try testing.expectEqual(@as(u8, 0xFF), handler.read(&state, 0x0000));
}

test "OpenBusHandler: read() returns same value for all addresses" {
    var state = TestState{};
    var handler = OpenBusHandler{};
    state.bus.open_bus.set(0xAA);

    // Open bus behavior is address-independent
    try testing.expectEqual(@as(u8, 0xAA), handler.read(&state, 0x0000));
    try testing.expectEqual(@as(u8, 0xAA), handler.read(&state, 0x5000));
    try testing.expectEqual(@as(u8, 0xAA), handler.read(&state, 0xFFFF));
}

test "OpenBusHandler: peek() same as read()" {
    var state = TestState{};
    var handler = OpenBusHandler{};
    state.bus.open_bus.set(0x55);

    try testing.expectEqual(
        handler.read(&state, 0x1234),
        handler.peek(&state, 0x1234),
    );
}

test "OpenBusHandler: write() is no-op" {
    var state = TestState{};
    var handler = OpenBusHandler{};
    state.bus.open_bus.set(0x42);

    // Write should not change bus value (bus layer handles that)
    handler.write(&state, 0x1000, 0xFF);
    try testing.expectEqual(@as(u8, 0x42), state.bus.open_bus.get());
}

test "OpenBusHandler: no internal state - handler is empty" {
    // Verify handler has no fields (completely stateless)
    try testing.expectEqual(@as(usize, 0), @sizeOf(OpenBusHandler));
}
