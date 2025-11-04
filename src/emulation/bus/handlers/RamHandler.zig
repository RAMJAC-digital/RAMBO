// RamHandler.zig
//
// Handles reads/writes to internal RAM ($0000-$1FFF).
// Implements 2KB RAM mirrored 4 times.
//
// Complexity: ⭐ (1/5) - Simple mirroring, no side effects
//
// Hardware Reference:
// - nesdev.org/wiki/CPU_memory_map#RAM
// - 2KB internal RAM at $0000-$07FF, mirrored to $1FFF

const std = @import("std");

/// Handler for internal RAM ($0000-$1FFF)
///
/// NES has 2KB of internal RAM at $0000-$07FF, mirrored 4 times:
/// - $0000-$07FF: RAM
/// - $0800-$0FFF: Mirror of $0000-$07FF
/// - $1000-$17FF: Mirror of $0000-$07FF
/// - $1800-$1FFF: Mirror of $0000-$07FF
///
/// Pattern: Completely stateless - accesses RAM via state parameter
pub const RamHandler = struct {
    // NO fields - completely stateless!
    // All RAM access happens through state parameter

    /// Read from internal RAM
    ///
    /// Applies mirroring: address & 0x7FF maps all ranges to 2KB space
    ///
    /// Parameters:
    /// - self: Handler instance (unused - no internal state)
    /// - state: Emulation state containing bus.ram
    /// - address: Memory address ($0000-$1FFF)
    ///
    /// Returns: Byte from RAM at mirrored address
    pub fn read(_: *const RamHandler, state: anytype, address: u16) u8 {
        const ram_addr = address & 0x7FF; // Mirror to 2KB
        return state.bus.ram[ram_addr];
    }

    /// Write to internal RAM
    ///
    /// Applies mirroring: address & 0x7FF maps all ranges to 2KB space
    ///
    /// Parameters:
    /// - self: Handler instance (unused - no internal state)
    /// - state: Emulation state containing bus.ram
    /// - address: Memory address ($0000-$1FFF)
    /// - value: Byte to write
    pub fn write(_: *RamHandler, state: anytype, address: u16, value: u8) void {
        const ram_addr = address & 0x7FF; // Mirror to 2KB
        state.bus.ram[ram_addr] = value;
    }

    /// Peek RAM (debugger support)
    ///
    /// Same as read() - RAM reads have no side effects
    ///
    /// Parameters:
    /// - self: Handler instance (unused)
    /// - state: Emulation state containing bus.ram
    /// - address: Memory address ($0000-$1FFF)
    ///
    /// Returns: Byte from RAM at mirrored address
    pub fn peek(_: *const RamHandler, state: anytype, address: u16) u8 {
        // Call read() directly - no side effects to avoid
        // Note: Can't use undefined for self since we need to pass the right type
        const ram_addr = address & 0x7FF;
        return state.bus.ram[ram_addr];
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

const testing = std.testing;

// Test state containing RAM buffer
const TestState = struct {
    bus: struct {
        ram: [2048]u8,
    },
};

test "RamHandler: read/write basic operation" {
    var state = TestState{
        .bus = .{ .ram = [_]u8{0} ** 2048 },
    };
    var handler = RamHandler{};

    // Write to RAM
    handler.write(&state, 0x0100, 0x42);
    try testing.expectEqual(@as(u8, 0x42), handler.read(&state, 0x0100));
}

test "RamHandler: mirroring at $0000" {
    var state = TestState{
        .bus = .{ .ram = [_]u8{0} ** 2048 },
    };
    var handler = RamHandler{};

    // Write to $0000
    handler.write(&state, 0x0000, 0xAA);

    // Read from all mirrors
    try testing.expectEqual(@as(u8, 0xAA), handler.read(&state, 0x0000)); // Base
    try testing.expectEqual(@as(u8, 0xAA), handler.read(&state, 0x0800)); // Mirror 1
    try testing.expectEqual(@as(u8, 0xAA), handler.read(&state, 0x1000)); // Mirror 2
    try testing.expectEqual(@as(u8, 0xAA), handler.read(&state, 0x1800)); // Mirror 3
}

test "RamHandler: mirroring at $07FF" {
    var state = TestState{
        .bus = .{ .ram = [_]u8{0} ** 2048 },
    };
    var handler = RamHandler{};

    // Write to $07FF (last byte of base RAM)
    handler.write(&state, 0x07FF, 0x55);

    // Read from all mirrors
    try testing.expectEqual(@as(u8, 0x55), handler.read(&state, 0x07FF)); // Base
    try testing.expectEqual(@as(u8, 0x55), handler.read(&state, 0x0FFF)); // Mirror 1
    try testing.expectEqual(@as(u8, 0x55), handler.read(&state, 0x17FF)); // Mirror 2
    try testing.expectEqual(@as(u8, 0x55), handler.read(&state, 0x1FFF)); // Mirror 3
}

test "RamHandler: write to mirror affects base" {
    var state = TestState{
        .bus = .{ .ram = [_]u8{0} ** 2048 },
    };
    var handler = RamHandler{};

    // Write to mirror
    handler.write(&state, 0x0800, 0x33);

    // Read from base - should see same value
    try testing.expectEqual(@as(u8, 0x33), handler.read(&state, 0x0000));
}

test "RamHandler: all 2KB addresses accessible" {
    var state = TestState{
        .bus = .{ .ram = [_]u8{0} ** 2048 },
    };
    var handler = RamHandler{};

    // Write unique value to each byte in base RAM
    for (0..2048) |i| {
        const value = @as(u8, @intCast(i & 0xFF));
        handler.write(&state, @intCast(i), value);
    }

    // Verify all bytes readable
    for (0..2048) |i| {
        const expected = @as(u8, @intCast(i & 0xFF));
        try testing.expectEqual(expected, handler.read(&state, @intCast(i)));
    }
}

test "RamHandler: peek() same as read()" {
    var state = TestState{
        .bus = .{ .ram = [_]u8{0} ** 2048 },
    };
    var handler = RamHandler{};

    handler.write(&state, 0x0200, 0x77);

    // Peek should return same value as read
    try testing.expectEqual(
        handler.read(&state, 0x0200),
        handler.peek(&state, 0x0200),
    );

    // Verify mirroring works with peek
    try testing.expectEqual(
        handler.read(&state, 0x0A00), // Mirror of 0x0200
        handler.peek(&state, 0x0A00),
    );
}

test "RamHandler: no internal state - handler is empty" {
    // Verify handler has no fields (completely stateless)
    try testing.expectEqual(@as(usize, 0), @sizeOf(RamHandler));
}
