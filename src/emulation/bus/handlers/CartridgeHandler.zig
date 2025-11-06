// CartridgeHandler.zig
//
// Handles $4020-$FFFF (expansion area + cartridge space).
// Delegates to cartridge mapper or test RAM (for harness), falls back to open bus.
//
// Complexity: ⭐⭐ (2/5) - Delegation, fallback logic
//
// Hardware Reference:
// - nesdev.org/wiki/CPU_memory_map#Cartridge
// - $4020-$5FFF: Expansion area (usually open bus)
// - $6000-$7FFF: PRG RAM (cartridge-dependent)
// - $8000-$FFFF: PRG ROM (cartridge-dependent)

const std = @import("std");
const CpuOpenBus = @import("../../state/BusState.zig").BusState.OpenBus;

/// Handler for $4020-$FFFF (expansion + cartridge space)
///
/// Address ranges:
/// - $4020-$5FFF: Expansion area (open bus on stock NES)
/// - $6000-$7FFF: PRG RAM (battery-backed save RAM on some games)
/// - $8000-$FFFF: PRG ROM (game code + data)
///
/// Behavior:
/// 1. If cartridge present: Delegate to mapper
/// 2. Else if test RAM present: Allow harness testing
/// 3. Else: Open bus / no-op
///
/// Pattern: Completely stateless - accesses cart/test_ram via state parameter
pub const CartridgeHandler = struct {
    // NO fields - completely stateless!
    // Accesses state.cart, state.bus.test_ram, state.bus.open_bus through parameter

    /// Read from cartridge space
    ///
    /// Priority order:
    /// 1. Cartridge mapper (if present)
    /// 2. Test RAM (if present, for test harness)
    /// 3. Open bus (fallback)
    ///
    /// Test RAM layout:
    /// - $8000-$FFFF: test_ram[0..32KB] (PRG ROM area)
    /// - $6000-$7FFF: test_ram[16384..24KB] (PRG RAM area, if length allows)
    ///
    /// Parameters:
    /// - self: Handler instance (unused - no internal state)
    /// - state: Emulation state containing cart, bus.test_ram, bus.open_bus
    /// - address: Memory address ($4020-$FFFF)
    ///
    /// Returns: Byte from cartridge, test RAM, or open bus
    pub fn read(_: *const CartridgeHandler, state: anytype, address: u16) u8 {
        // Priority 1: Cartridge mapper
        if (state.cart) |*cart| {
            return cart.cpuRead(address);
        }

        // Priority 2: Test RAM (for harness)
        if (state.bus.test_ram) |test_ram| {
            if (address >= 0x8000) {
                // PRG ROM area: $8000-$FFFF maps to test_ram[0..]
                return test_ram[address - 0x8000];
            } else if (address >= 0x6000) {
                // PRG RAM area: $6000-$7FFF maps to test_ram[16384..]
                const prg_ram_offset = @as(usize, @intCast(address - 0x6000));
                const base_offset = 16384;
                if (test_ram.len > base_offset + prg_ram_offset) {
                    return test_ram[base_offset + prg_ram_offset];
                }
            }
        }

        // Priority 3: Open bus (no cartridge or test RAM)
        return state.bus.open_bus.get();
    }

    /// Write to cartridge space
    ///
    /// Priority order:
    /// 1. Cartridge mapper (if present)
    /// 2. Test RAM (if present, for test harness)
    /// 3. No-op (fallback)
    ///
    /// Test RAM layout (same as read):
    /// - $8000-$FFFF: test_ram[0..32KB] (PRG ROM area)
    /// - $6000-$7FFF: test_ram[16384..24KB] (PRG RAM area, if length allows)
    ///
    /// Parameters:
    /// - self: Handler instance (unused - no internal state)
    /// - state: Emulation state containing cart, bus.test_ram
    /// - address: Memory address ($4020-$FFFF)
    /// - value: Byte to write
    pub fn write(_: *CartridgeHandler, state: anytype, address: u16, value: u8) void {
        // Priority 1: Cartridge mapper
        if (state.cart) |*cart| {
            cart.cpuWrite(address, value);
            return;
        }

        // Priority 2: Test RAM (for harness)
        if (state.bus.test_ram) |test_ram| {
            if (address >= 0x8000) {
                // PRG ROM area: Allow writes for testing
                test_ram[address - 0x8000] = value;
            } else if (address >= 0x6000 and address < 0x8000) {
                // PRG RAM area: $6000-$7FFF maps to test_ram[16384..]
                const prg_ram_offset = address - 0x6000;
                if (test_ram.len > 16384 + prg_ram_offset) {
                    test_ram[16384 + prg_ram_offset] = value;
                }
            }
            return;
        }

        // Priority 3: No-op (no cartridge or test RAM)
    }

    /// Peek cartridge space (debugger support)
    ///
    /// Same as read() - cartridge reads have no side effects
    ///
    /// Parameters:
    /// - self: Handler instance (unused)
    /// - state: Emulation state containing cart, bus.test_ram, bus.open_bus
    /// - address: Memory address ($4020-$FFFF)
    ///
    /// Returns: Byte from cartridge, test RAM, or open bus
    pub fn peek(_: *const CartridgeHandler, state: anytype, address: u16) u8 {
        // Cartridge reads have no side effects, so peek = read
        return read(undefined, state, address);
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

const testing = std.testing;

// Mock cartridge for testing
const MockCart = struct {
    read_value: u8 = 0,
    last_write_addr: u16 = 0,
    last_write_value: u8 = 0,

    pub fn cpuRead(self: *const @This(), _: u16) u8 {
        return self.read_value;
    }

    pub fn cpuWrite(self: *@This(), address: u16, value: u8) void {
        self.last_write_addr = address;
        self.last_write_value = value;
    }
};

// Test state with cartridge/test_ram
const TestState = struct {
    bus: struct {
        open_bus: CpuOpenBus = .{},
        test_ram: ?[]u8 = null,
    } = .{},
    cart: ?MockCart = null,

    pub fn init() TestState {
        return .{};
    }
};

test "CartridgeHandler: read from cartridge (priority 1)" {
    const mock_cart = MockCart{ .read_value = 0x42 };
    var state = TestState.init();
    state.cart = mock_cart;

    var handler = CartridgeHandler{};
    const value = handler.read(&state, 0x8000);

    try testing.expectEqual(@as(u8, 0x42), value);
}

test "CartridgeHandler: write to cartridge (priority 1)" {
    const mock_cart = MockCart{};
    var state = TestState.init();
    state.cart = mock_cart;

    var handler = CartridgeHandler{};
    handler.write(&state, 0xC000, 0x55);

    // Verify mutations happened to state's copy
    try testing.expectEqual(@as(u16, 0xC000), state.cart.?.last_write_addr);
    try testing.expectEqual(@as(u8, 0x55), state.cart.?.last_write_value);
}

test "CartridgeHandler: read from test RAM PRG ROM (priority 2)" {
    var test_ram = [_]u8{0} ** 32768;
    test_ram[0] = 0xAB; // $8000
    test_ram[100] = 0xCD; // $8064

    var state = TestState.init();
    state.bus.test_ram = &test_ram;

    var handler = CartridgeHandler{};

    // Read from $8000 (test_ram[0])
    try testing.expectEqual(@as(u8, 0xAB), handler.read(&state, 0x8000));

    // Read from $8064 (test_ram[100])
    try testing.expectEqual(@as(u8, 0xCD), handler.read(&state, 0x8064));
}

test "CartridgeHandler: read from test RAM PRG RAM (priority 2)" {
    var test_ram = [_]u8{0} ** 24576; // 32KB PRG ROM + 8KB PRG RAM
    test_ram[16384] = 0x11; // $6000
    test_ram[16384 + 100] = 0x22; // $6064

    var state = TestState.init();
    state.bus.test_ram = &test_ram;

    var handler = CartridgeHandler{};

    // Read from $6000 (test_ram[16384])
    try testing.expectEqual(@as(u8, 0x11), handler.read(&state, 0x6000));

    // Read from $6064 (test_ram[16484])
    try testing.expectEqual(@as(u8, 0x22), handler.read(&state, 0x6064));
}

test "CartridgeHandler: write to test RAM PRG ROM" {
    var test_ram = [_]u8{0} ** 32768;
    var state = TestState.init();
    state.bus.test_ram = &test_ram;

    var handler = CartridgeHandler{};
    handler.write(&state, 0x8000, 0x33);

    try testing.expectEqual(@as(u8, 0x33), test_ram[0]);
}

test "CartridgeHandler: write to test RAM PRG RAM" {
    var test_ram = [_]u8{0} ** 24576;
    var state = TestState.init();
    state.bus.test_ram = &test_ram;

    var handler = CartridgeHandler{};
    handler.write(&state, 0x6000, 0x44);

    try testing.expectEqual(@as(u8, 0x44), test_ram[16384]);
}

test "CartridgeHandler: read open bus (priority 3)" {
    var state = TestState.init();
    state.bus.open_bus.set(0xEE);

    var handler = CartridgeHandler{};
    const value = handler.read(&state, 0x8000);

    try testing.expectEqual(@as(u8, 0xEE), value);
}

test "CartridgeHandler: write no-op (priority 3)" {
    var state = TestState.init();
    var handler = CartridgeHandler{};

    // Should not crash
    handler.write(&state, 0x8000, 0xFF);

    // No assertions - just verify it doesn't crash
}

test "CartridgeHandler: expansion area returns open bus" {
    var state = TestState.init();
    state.bus.open_bus.set(0x77);

    var handler = CartridgeHandler{};

    // $4020-$5FFF expansion area
    try testing.expectEqual(@as(u8, 0x77), handler.read(&state, 0x4020));
    try testing.expectEqual(@as(u8, 0x77), handler.read(&state, 0x5000));
    try testing.expectEqual(@as(u8, 0x77), handler.read(&state, 0x5FFF));
}

test "CartridgeHandler: peek same as read" {
    const mock_cart = MockCart{ .read_value = 0x99 };
    var state = TestState.init();
    state.cart = mock_cart;

    var handler = CartridgeHandler{};

    try testing.expectEqual(
        handler.read(&state, 0xC000),
        handler.peek(&state, 0xC000),
    );
}

test "CartridgeHandler: no internal state - handler is empty" {
    // Verify handler has no fields (completely stateless)
    try testing.expectEqual(@as(usize, 0), @sizeOf(CartridgeHandler));
}
