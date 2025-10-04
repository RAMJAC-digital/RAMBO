//! Bus Logic
//!
//! This module contains the pure functions that operate on the Bus state.
//! All functions are deterministic and have no side effects except state mutation.

const std = @import("std");
const BusState = @import("State.zig").BusState;

/// Initialize bus state
/// Returns a clean bus state ready for emulation
pub fn init() BusState {
    return BusState.init();
}

/// Read a byte from the bus
/// This properly handles mirroring and open bus behavior
///
/// Parameters:
///   - state: Mutable bus state
///   - cartridge: Optional cartridge for ROM/mapper access (anytype for now, Phase 3 will fix)
///   - ppu: Optional PPU for register access (anytype for now, Phase 3 will fix)
///   - address: 16-bit CPU address to read from
///
/// Returns: Byte value at address (or open bus value if unmapped)
pub fn read(state: *BusState, cartridge: anytype, ppu: anytype, address: u16) u8 {
    const value = readInternal(state, cartridge, ppu, address);

    // Most reads update the open bus (with some exceptions like $4015)
    // For now, we update on all reads - specific exceptions will be added
    state.open_bus.update(value, state.cycle);

    return value;
}

/// Internal read without open bus update
/// Used for special cases where reads shouldn't affect the bus
fn readInternal(state: *BusState, cartridge: anytype, ppu: anytype, address: u16) u8 {
    return switch (address) {
        // RAM and mirrors ($0000-$1FFF)
        // RAM is 2KB ($0000-$07FF) mirrored 4 times
        // AccuracyCoin Test: "RAM Mirroring" - 13-bit address mirrors 11-bit RAM
        0x0000...0x1FFF => state.ram[address & 0x07FF],

        // PPU Registers and mirrors ($2000-$3FFF)
        // 8 registers mirrored every 8 bytes through $3FFF
        0x2000...0x3FFF => blk: {
            // For anytype: Try to access methods if available
            // This will work with both ?*Ppu and *Ppu
            // If ppu is null, we'll return open bus
            if (@typeInfo(@TypeOf(ppu)) == .optional) {
                if (ppu) |p| {
                    break :blk p.readRegister(address);
                }
            } else if (@typeInfo(@TypeOf(ppu)) == .pointer) {
                break :blk ppu.readRegister(address);
            }
            // No PPU attached or null - return open bus
            break :blk state.open_bus.read();
        },

        // APU and I/O registers ($4000-$4017)
        // TODO: Implement APU/IO reads
        0x4000...0x4017 => blk: {
            // For now, return open bus
            break :blk state.open_bus.read();
        },

        // Cartridge space ($4020-$FFFF)
        0x4020...0xFFFF => blk: {
            // For anytype: Try to access methods if available
            // This will work with both ?*Cartridge and *Cartridge
            if (@typeInfo(@TypeOf(cartridge)) == .optional) {
                if (cartridge) |cart| {
                    break :blk cart.cpuRead(address);
                }
            } else if (@typeInfo(@TypeOf(cartridge)) == .pointer) {
                break :blk cartridge.cpuRead(address);
            }

            // No cartridge - check for test RAM
            if (state.test_ram) |test_ram| {
                // Map $8000-$FFFF to test RAM (32KB)
                if (address >= 0x8000) {
                    break :blk test_ram[address - 0x8000];
                }
            }

            // No cartridge or test RAM - return open bus
            break :blk state.open_bus.read();
        },

        // Should never reach here, but return open bus for safety
        else => state.open_bus.read(),
    };
}

/// Write a byte to the bus
/// Handles RAM mirroring and ROM write protection
///
/// Parameters:
///   - state: Mutable bus state
///   - cartridge: Optional cartridge for mapper writes
///   - ppu: Optional PPU for register writes
///   - address: 16-bit CPU address to write to
///   - value: Byte value to write
pub fn write(state: *BusState, cartridge: anytype, ppu: anytype, address: u16, value: u8) void {
    // ALL writes update the open bus (including writes to ROM)
    // AccuracyCoin Test: "Open Bus #8: Writing should always update the databus"
    state.open_bus.update(value, state.cycle);

    switch (address) {
        // RAM and mirrors ($0000-$1FFF)
        // AccuracyCoin Test: "RAM Mirroring #2: Writing to mirror writes to 11-bit address"
        0x0000...0x1FFF => {
            state.ram[address & 0x07FF] = value;
        },

        // PPU Registers and mirrors ($2000-$3FFF)
        0x2000...0x3FFF => {
            // For anytype: Try to access methods if available
            if (@typeInfo(@TypeOf(ppu)) == .optional) {
                if (ppu) |p| {
                    p.writeRegister(address, value);
                }
            } else if (@typeInfo(@TypeOf(ppu)) == .pointer) {
                ppu.writeRegister(address, value);
            }
            // No PPU attached or null - write ignored (but open bus updated above)
        },

        // APU and I/O registers ($4000-$4017)
        // TODO: Implement APU/IO writes
        0x4000...0x4017 => {
            // APU/IO write implementation goes here
        },

        // Cartridge space ($4020-$FFFF)
        // AccuracyCoin Test: "ROM is not Writable #1: Writing to ROM should not overwrite"
        0x4020...0xFFFF => {
            // For anytype: Try to access methods if available
            var handled = false;
            if (@typeInfo(@TypeOf(cartridge)) == .optional) {
                if (cartridge) |cart| {
                    cart.cpuWrite(address, value);
                    handled = true;
                }
            } else if (@typeInfo(@TypeOf(cartridge)) == .pointer) {
                cartridge.cpuWrite(address, value);
                handled = true;
            }

            // If no cartridge handled it, try test RAM
            if (!handled and state.test_ram != null) {
                if (state.test_ram) |test_ram| {
                    // Write to test RAM for unit testing
                    if (address >= 0x8000) {
                        test_ram[address - 0x8000] = value;
                    }
                }
            }
            // No cartridge or test RAM: write ignored (but open bus updated above)
        },

        else => {
            // Unmapped regions - write ignored but open bus updated (done above)
        },
    }
}

/// Read a 16-bit value (little-endian)
/// Used for reading vectors and 16-bit operands
///
/// Parameters:
///   - state: Mutable bus state
///   - cartridge: Optional cartridge
///   - ppu: Optional PPU
///   - address: 16-bit starting address
///
/// Returns: 16-bit value (low byte at address, high byte at address+1)
pub fn read16(state: *BusState, cartridge: anytype, ppu: anytype, address: u16) u16 {
    const low = read(state, cartridge, ppu, address);
    const high = read(state, cartridge, ppu, address +% 1); // Wrapping add for address $FFFF
    return (@as(u16, high) << 8) | @as(u16, low);
}

/// Read 16-bit with bug for indirect JMP
/// The 6502 has a bug where JMP ($xxFF) wraps within the page
/// e.g., JMP ($20FF) reads from $20FF and $2000, not $20FF and $2100
///
/// This bug is critical for hardware accuracy and is tested by AccuracyCoin
///
/// Parameters:
///   - state: Mutable bus state
///   - cartridge: Optional cartridge
///   - ppu: Optional PPU
///   - address: 16-bit starting address
///
/// Returns: 16-bit value (with page-wrap bug applied)
pub fn read16Bug(state: *BusState, cartridge: anytype, ppu: anytype, address: u16) u16 {
    const low_addr = address;
    // If low byte is $FF, wrap to $x00 instead of crossing page
    const high_addr = if ((address & 0x00FF) == 0x00FF)
        address & 0xFF00
    else
        address +% 1;

    const low = read(state, cartridge, ppu, low_addr);
    const high = read(state, cartridge, ppu, high_addr);
    return (@as(u16, high) << 8) | @as(u16, low);
}

/// Dummy read - performs a read that may have side effects
/// Used for cycle-accurate addressing mode emulation
///
/// AccuracyCoin Test: "Dummy read cycles" - these update the data bus
///
/// Parameters:
///   - state: Mutable bus state
///   - cartridge: Optional cartridge
///   - ppu: Optional PPU
///   - address: 16-bit address to read from
pub inline fn dummyRead(state: *BusState, cartridge: anytype, ppu: anytype, address: u16) void {
    _ = read(state, cartridge, ppu, address);
}

/// Dummy write - performs a write of the current value
/// Used for Read-Modify-Write instructions
///
/// AccuracyCoin Test: "Dummy write cycles" - RMW instructions write twice:
/// 1. Write original value back (dummy write)
/// 2. Write modified value
///
/// This is critical for hardware accuracy as memory-mapped I/O can observe both writes
///
/// Parameters:
///   - state: Mutable bus state
///   - cartridge: Optional cartridge
///   - ppu: Optional PPU
///   - address: 16-bit address to write to
pub inline fn dummyWrite(state: *BusState, cartridge: anytype, ppu: anytype, address: u16) void {
    const value = readInternal(state, cartridge, ppu, address);
    write(state, cartridge, ppu, address, value);
}

/// Increment cycle counter
/// Should be called once per PPU cycle by the emulation loop
pub inline fn tick(state: *BusState) void {
    state.cycle += 1;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

// Mock structures for testing
const MockCartridge = struct {
    pub fn cpuRead(_: *MockCartridge, address: u16) u8 {
        _ = address;
        return 0xFF; // Return dummy value
    }

    pub fn cpuWrite(_: *MockCartridge, address: u16, value: u8) void {
        _ = address;
        _ = value;
    }
};

const MockPpu = struct {
    pub fn readRegister(_: *MockPpu, address: u16) u8 {
        _ = address;
        return 0xFF; // Return dummy value
    }

    pub fn writeRegister(_: *MockPpu, address: u16, value: u8) void {
        _ = address;
        _ = value;
    }
};

test "Bus Logic: init" {
    const state = init();
    try testing.expectEqual(@as(u64, 0), state.cycle);
    try testing.expectEqual(@as(u8, 0), state.open_bus.value);
}

test "Bus Logic: RAM write and read without cartridge/ppu" {
    var state = init();
    const no_cart: ?*MockCartridge = null;
    const no_ppu: ?*MockPpu = null;

    // Write to RAM
    write(&state, no_cart, no_ppu, 0x0000, 0x42);
    try testing.expectEqual(@as(u8, 0x42), read(&state, no_cart, no_ppu, 0x0000));

    // Write to different address
    write(&state, no_cart, no_ppu, 0x0100, 0xAB);
    try testing.expectEqual(@as(u8, 0xAB), read(&state, no_cart, no_ppu, 0x0100));

    // Verify first write still intact
    try testing.expectEqual(@as(u8, 0x42), read(&state, no_cart, no_ppu, 0x0000));
}

test "Bus Logic: RAM mirroring - read" {
    var state = init();
    const no_cart: ?*MockCartridge = null;
    const no_ppu: ?*MockPpu = null;

    // Write to base RAM address
    write(&state, no_cart, no_ppu, 0x0000, 0x12);

    // AccuracyCoin Test: "RAM Mirroring #1"
    // Reading from 13-bit mirror should return same value as 11-bit address
    try testing.expectEqual(@as(u8, 0x12), read(&state, no_cart, no_ppu, 0x0800)); // First mirror
    try testing.expectEqual(@as(u8, 0x12), read(&state, no_cart, no_ppu, 0x1000)); // Second mirror
    try testing.expectEqual(@as(u8, 0x12), read(&state, no_cart, no_ppu, 0x1800)); // Third mirror

    // Test different addresses
    write(&state, no_cart, no_ppu, 0x01FF, 0x34);
    try testing.expectEqual(@as(u8, 0x34), read(&state, no_cart, no_ppu, 0x09FF));
    try testing.expectEqual(@as(u8, 0x34), read(&state, no_cart, no_ppu, 0x11FF));
    try testing.expectEqual(@as(u8, 0x34), read(&state, no_cart, no_ppu, 0x19FF));
}

test "Bus Logic: RAM mirroring - write" {
    var state = init();
    const no_cart: ?*MockCartridge = null;
    const no_ppu: ?*MockPpu = null;

    // AccuracyCoin Test: "RAM Mirroring #2"
    // Writing to mirror should write to base 11-bit address
    write(&state, no_cart, no_ppu, 0x0800, 0x56);
    try testing.expectEqual(@as(u8, 0x56), read(&state, no_cart, no_ppu, 0x0000));

    write(&state, no_cart, no_ppu, 0x1000, 0x78);
    try testing.expectEqual(@as(u8, 0x78), read(&state, no_cart, no_ppu, 0x0000));

    write(&state, no_cart, no_ppu, 0x1800, 0x9A);
    try testing.expectEqual(@as(u8, 0x9A), read(&state, no_cart, no_ppu, 0x0000));

    // Verify all mirrors see the same value
    try testing.expectEqual(@as(u8, 0x9A), read(&state, no_cart, no_ppu, 0x0800));
    try testing.expectEqual(@as(u8, 0x9A), read(&state, no_cart, no_ppu, 0x1000));
    try testing.expectEqual(@as(u8, 0x9A), read(&state, no_cart, no_ppu, 0x1800));
}

test "Bus Logic: open bus behavior - read updates bus" {
    var state = init();
    const no_cart: ?*MockCartridge = null;
    const no_ppu: ?*MockPpu = null;

    // Write a value to RAM
    write(&state, no_cart, no_ppu, 0x0010, 0xAB);

    // Read it back - should update open bus
    const value = read(&state, no_cart, no_ppu, 0x0010);
    try testing.expectEqual(@as(u8, 0xAB), value);
    try testing.expectEqual(@as(u8, 0xAB), state.open_bus.value);
}

test "Bus Logic: open bus behavior - write updates bus" {
    var state = init();
    const no_cart: ?*MockCartridge = null;
    const no_ppu: ?*MockPpu = null;

    // AccuracyCoin Test: "Open Bus #8"
    // Writing should always update the databus
    write(&state, no_cart, no_ppu, 0x0100, 0xCD);
    try testing.expectEqual(@as(u8, 0xCD), state.open_bus.value);

    // Even writes to ROM should update open bus
    write(&state, no_cart, no_ppu, 0x8000, 0xEF);
    try testing.expectEqual(@as(u8, 0xEF), state.open_bus.value);
}

test "Bus Logic: open bus behavior - unmapped regions return last value" {
    var state = init();
    const no_cart: ?*MockCartridge = null;
    const no_ppu: ?*MockPpu = null;

    // AccuracyCoin Test: "Open Bus #1"
    // Reading from open bus should not return all zeroes

    // First, put a value on the bus
    write(&state, no_cart, no_ppu, 0x0000, 0x42);
    try testing.expectEqual(@as(u8, 0x42), state.open_bus.value);

    // Now read from unmapped region (cartridge space with no cart)
    // Should return the last value on the bus
    const open_value = read(&state, no_cart, no_ppu, 0x5000);
    try testing.expectEqual(@as(u8, 0x42), open_value);
}

test "Bus Logic: read16 little-endian" {
    var state = init();
    const no_cart: ?*MockCartridge = null;
    const no_ppu: ?*MockPpu = null;

    write(&state, no_cart, no_ppu, 0x0000, 0x34); // Low byte
    write(&state, no_cart, no_ppu, 0x0001, 0x12); // High byte

    const value = read16(&state, no_cart, no_ppu, 0x0000);
    try testing.expectEqual(@as(u16, 0x1234), value);
}

test "Bus Logic: read16Bug - indirect JMP bug" {
    var state = init();
    const no_cart: ?*MockCartridge = null;
    const no_ppu: ?*MockPpu = null;

    // Test the famous 6502 bug where JMP ($xxFF) wraps within page
    state.ram[0x00FF] = 0x34; // Low byte at $00FF
    state.ram[0x0000] = 0x12; // High byte at $0000 (wraps to page start)
    state.ram[0x0100] = 0x99; // This should NOT be read by buggy version

    // Test with $08FF (which mirrors $00FF)
    const value = read16Bug(&state, no_cart, no_ppu, 0x08FF);
    try testing.expectEqual(@as(u16, 0x1234), value);

    // Verify normal read16 would cross page (incorrect behavior for JMP)
    const normal_value = read16(&state, no_cart, no_ppu, 0x08FF);
    try testing.expectEqual(@as(u16, 0x9934), normal_value);
}

test "Bus Logic: tick increments cycle counter" {
    var state = init();

    try testing.expectEqual(@as(u64, 0), state.cycle);

    tick(&state);
    try testing.expectEqual(@as(u64, 1), state.cycle);

    tick(&state);
    try testing.expectEqual(@as(u64, 2), state.cycle);
}

test "Bus Logic: test_ram support" {
    var state = init();
    var test_buffer = [_]u8{0} ** 0x8000; // 32KB for ROM space
    state.test_ram = &test_buffer;

    const no_cart: ?*MockCartridge = null;
    const no_ppu: ?*MockPpu = null;

    // Write to test RAM
    write(&state, no_cart, no_ppu, 0x8000, 0xAB);
    try testing.expectEqual(@as(u8, 0xAB), read(&state, no_cart, no_ppu, 0x8000));

    // Verify it's in the test buffer
    try testing.expectEqual(@as(u8, 0xAB), test_buffer[0]);
}
