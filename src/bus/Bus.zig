//! NES Memory Bus Implementation
//!
//! This module implements the complete NES memory bus with:
//! - Accurate RAM mirroring ($0000-$1FFF mirrors $0000-$07FF)
//! - Open bus behavior (data bus retains last value)
//! - ROM write protection
//! - PPU/APU register mirroring
//! - Cartridge mapper support
//!
//! AccuracyCoin Test Requirements:
//! - RAM Mirroring: 13-bit address space mirrors 11-bit RAM
//! - Open Bus: Returns last value on data bus, not zeros
//! - ROM Protection: Writes to ROM are ignored
//! - Dummy reads/writes update the data bus

const std = @import("std");
const CartridgeMod = @import("../cartridge/Cartridge.zig");
const PpuMod = @import("../ppu/Ppu.zig");

const Cartridge = CartridgeMod.Cartridge;
const Ppu = PpuMod.Ppu;

/// Open bus state tracking
/// The NES data bus is not driven during reads from unmapped regions,
/// so it retains the last value that was on the bus
pub const OpenBus = struct {
    /// Last value on the data bus
    value: u8 = 0,

    /// Cycle when the value was last updated
    /// (for potential decay simulation, though NES doesn't decay quickly)
    last_update_cycle: u64 = 0,

    /// Update the open bus value
    pub inline fn update(self: *OpenBus, value: u8, cycle: u64) void {
        self.value = value;
        self.last_update_cycle = cycle;
    }

    /// Read the current open bus value
    pub inline fn read(self: *const OpenBus) u8 {
        return self.value;
    }
};

/// Memory Bus
/// This is the central hub for all memory access in the NES
pub const Bus = struct {
    const Self = @This();

    // ===== Memory Regions =====
    /// Internal RAM: 2KB ($0000-$07FF)
    /// Mirrored through $0000-$1FFF
    ram: [2048]u8,

    /// Cycle counter for timing-sensitive operations
    cycle: u64 = 0,

    /// Open bus state
    open_bus: OpenBus = .{},

    /// Loaded cartridge (optional - can run without cartridge)
    cartridge: ?*Cartridge = null,

    /// PPU (Picture Processing Unit)
    /// Non-owning pointer - managed by EmulationState
    ppu: ?*Ppu = null,

    /// Test RAM for unit testing ($8000-$FFFF)
    /// Only used when no cartridge is loaded
    /// Allows tests to write interrupt vectors and test code
    test_ram: ?[]u8 = null,

    // TODO: Add APU interface once implemented
    // apu: *Apu,

    /// Initialize bus with zeroed RAM
    pub fn init() Self {
        return .{
            .ram = std.mem.zeroes([2048]u8),
        };
    }

    /// Load a cartridge into the bus
    /// Takes ownership of the cartridge pointer (caller must not free)
    pub fn loadCartridge(self: *Self, cart: *Cartridge) void {
        self.cartridge = cart;
    }

    /// Unload the current cartridge
    /// Returns the cartridge pointer so caller can clean it up
    pub fn unloadCartridge(self: *Self) ?*Cartridge {
        const cart = self.cartridge;
        self.cartridge = null;
        return cart;
    }

    /// Read a byte from the bus
    /// This properly handles mirroring and open bus behavior
    pub fn read(self: *Self, address: u16) u8 {
        const value = self.readInternal(address);

        // Most reads update the open bus (with some exceptions like $4015)
        // For now, we update on all reads - specific exceptions will be added
        self.open_bus.update(value, self.cycle);

        return value;
    }

    /// Internal read without open bus update
    /// Used for special cases where reads shouldn't affect the bus
    fn readInternal(self: *Self, address: u16) u8 {
        return switch (address) {
            // RAM and mirrors ($0000-$1FFF)
            // RAM is 2KB ($0000-$07FF) mirrored 4 times
            // Test: "RAM Mirroring" - 13-bit address mirrors 11-bit RAM
            0x0000...0x1FFF => self.ram[address & 0x07FF],

            // PPU Registers and mirrors ($2000-$3FFF)
            // 8 registers mirrored every 8 bytes through $3FFF
            0x2000...0x3FFF => blk: {
                if (self.ppu) |ppu| {
                    break :blk ppu.readRegister(address);
                }
                // No PPU attached - return open bus
                break :blk self.open_bus.read();
            },

            // APU and I/O registers ($4000-$4017)
            // TODO: Implement APU/IO reads
            0x4000...0x4017 => blk: {
                // For now, return open bus
                break :blk self.open_bus.read();
            },

            // Cartridge space ($4020-$FFFF)
            0x4020...0xFFFF => blk: {
                if (self.cartridge) |cart| {
                    break :blk cart.cpuRead(address);
                }
                // No cartridge - check for test RAM
                if (self.test_ram) |test_ram| {
                    // Map $8000-$FFFF to test RAM (32KB)
                    if (address >= 0x8000) {
                        break :blk test_ram[address - 0x8000];
                    }
                }
                // No cartridge or test RAM - return open bus
                break :blk self.open_bus.read();
            },

            // Open bus (shouldn't reach here, but be safe)
            else => self.open_bus.read(),
        };
    }

    /// Write a byte to the bus
    /// Handles RAM mirroring and ROM write protection
    pub fn write(self: *Self, address: u16, value: u8) void {
        // ALL writes update the open bus (including writes to ROM)
        // Test: "Open Bus #8: Writing should always update the databus"
        self.open_bus.update(value, self.cycle);

        switch (address) {
            // RAM and mirrors ($0000-$1FFF)
            // Test: "RAM Mirroring #2: Writing to mirror writes to 11-bit address"
            0x0000...0x1FFF => {
                self.ram[address & 0x07FF] = value;
            },

            // PPU Registers and mirrors ($2000-$3FFF)
            0x2000...0x3FFF => {
                if (self.ppu) |ppu| {
                    ppu.writeRegister(address, value);
                }
                // No PPU attached - write ignored (but open bus updated)
            },

            // APU and I/O registers ($4000-$4017)
            // TODO: Implement APU/IO writes
            0x4000...0x4017 => {
                // APU/IO write implementation goes here
            },

            // Cartridge space ($4020-$FFFF)
            // Test: "ROM is not Writable #1: Writing to ROM should not overwrite"
            0x4020...0xFFFF => {
                if (self.cartridge) |cart| {
                    cart.cpuWrite(address, value);
                } else if (self.test_ram) |test_ram| {
                    // Write to test RAM for unit testing
                    if (address >= 0x8000) {
                        test_ram[address - 0x8000] = value;
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
    pub fn read16(self: *Self, address: u16) u16 {
        const low = self.read(address);
        const high = self.read(address +% 1); // Wrapping add for address $FFFF
        return (@as(u16, high) << 8) | @as(u16, low);
    }

    /// Read 16-bit with bug for indirect JMP
    /// The 6502 has a bug where JMP ($xxFF) wraps within the page
    /// e.g., JMP ($20FF) reads from $20FF and $2000, not $20FF and $2100
    pub fn read16Bug(self: *Self, address: u16) u16 {
        const low_addr = address;
        // If low byte is $FF, wrap to $x00 instead of crossing page
        const high_addr = if ((address & 0x00FF) == 0x00FF)
            address & 0xFF00
        else
            address +% 1;

        const low = self.read(low_addr);
        const high = self.read(high_addr);
        return (@as(u16, high) << 8) | @as(u16, low);
    }

    /// Dummy read - performs a read that may have side effects
    /// Used for cycle-accurate addressing mode emulation
    /// Test: "Dummy read cycles" - these update the data bus
    pub inline fn dummyRead(self: *Self, address: u16) void {
        _ = self.read(address);
    }

    /// Dummy write - performs a write of the current value
    /// Used for Read-Modify-Write instructions
    /// Test: "Dummy write cycles" - RMW instructions write twice
    pub inline fn dummyWrite(self: *Self, address: u16) void {
        const value = self.readInternal(address);
        self.write(address, value);
    }

    /// Increment cycle counter
    pub inline fn tick(self: *Self) void {
        self.cycle += 1;
    }
};

// ===== Unit Tests =====

test "Bus: initialization" {
    const bus = Bus.init();

    // RAM should be zeroed
    for (bus.ram) |byte| {
        try std.testing.expectEqual(@as(u8, 0), byte);
    }

    // Open bus should start at 0
    try std.testing.expectEqual(@as(u8, 0), bus.open_bus.value);
}

test "Bus: RAM write and read" {
    var bus = Bus.init();

    // Write to RAM
    bus.write(0x0000, 0x42);
    try std.testing.expectEqual(@as(u8, 0x42), bus.read(0x0000));

    // Write to different address
    bus.write(0x0100, 0xAB);
    try std.testing.expectEqual(@as(u8, 0xAB), bus.read(0x0100));

    // Verify first write still intact
    try std.testing.expectEqual(@as(u8, 0x42), bus.read(0x0000));
}

test "Bus: RAM mirroring - read" {
    var bus = Bus.init();

    // Write to base RAM address
    bus.write(0x0000, 0x12);

    // AccuracyCoin Test: "RAM Mirroring #1"
    // Reading from 13-bit mirror should return same value as 11-bit address
    try std.testing.expectEqual(@as(u8, 0x12), bus.read(0x0800)); // First mirror
    try std.testing.expectEqual(@as(u8, 0x12), bus.read(0x1000)); // Second mirror
    try std.testing.expectEqual(@as(u8, 0x12), bus.read(0x1800)); // Third mirror

    // Test different addresses
    bus.write(0x01FF, 0x34);
    try std.testing.expectEqual(@as(u8, 0x34), bus.read(0x09FF));
    try std.testing.expectEqual(@as(u8, 0x34), bus.read(0x11FF));
    try std.testing.expectEqual(@as(u8, 0x34), bus.read(0x19FF));
}

test "Bus: RAM mirroring - write" {
    var bus = Bus.init();

    // AccuracyCoin Test: "RAM Mirroring #2"
    // Writing to mirror should write to base 11-bit address
    bus.write(0x0800, 0x56);
    try std.testing.expectEqual(@as(u8, 0x56), bus.read(0x0000));

    bus.write(0x1000, 0x78);
    try std.testing.expectEqual(@as(u8, 0x78), bus.read(0x0000));

    bus.write(0x1800, 0x9A);
    try std.testing.expectEqual(@as(u8, 0x9A), bus.read(0x0000));

    // Verify all mirrors see the same value
    try std.testing.expectEqual(@as(u8, 0x9A), bus.read(0x0800));
    try std.testing.expectEqual(@as(u8, 0x9A), bus.read(0x1000));
    try std.testing.expectEqual(@as(u8, 0x9A), bus.read(0x1800));
}

test "Bus: RAM mirroring - comprehensive" {
    var bus = Bus.init();

    // Test all 2KB addresses mirror correctly
    var i: u16 = 0;
    while (i < 0x0800) : (i += 1) {
        const value = @as(u8, @truncate(i)); // Use address as value
        bus.write(i, value);

        // Verify all mirrors
        try std.testing.expectEqual(value, bus.read(i));
        try std.testing.expectEqual(value, bus.read(i | 0x0800));
        try std.testing.expectEqual(value, bus.read(i | 0x1000));
        try std.testing.expectEqual(value, bus.read(i | 0x1800));
    }
}

test "Bus: open bus behavior - read updates bus" {
    var bus = Bus.init();

    // Write a value to RAM
    bus.write(0x0010, 0xAB);

    // Read it back - should update open bus
    const value = bus.read(0x0010);
    try std.testing.expectEqual(@as(u8, 0xAB), value);
    try std.testing.expectEqual(@as(u8, 0xAB), bus.open_bus.value);
}

test "Bus: open bus behavior - write updates bus" {
    var bus = Bus.init();

    // AccuracyCoin Test: "Open Bus #8"
    // Writing should always update the databus
    bus.write(0x0100, 0xCD);
    try std.testing.expectEqual(@as(u8, 0xCD), bus.open_bus.value);

    // Even writes to ROM should update open bus
    bus.write(0x8000, 0xEF);
    try std.testing.expectEqual(@as(u8, 0xEF), bus.open_bus.value);
}

test "Bus: open bus behavior - unmapped regions return last value" {
    var bus = Bus.init();

    // AccuracyCoin Test: "Open Bus #1"
    // Reading from open bus should not return all zeroes

    // First, put a value on the bus
    bus.write(0x0000, 0x42);
    try std.testing.expectEqual(@as(u8, 0x42), bus.open_bus.value);

    // Now read from unmapped region (cartridge space with no cart)
    // Should return the last value on the bus
    const open_value = bus.read(0x5000);
    try std.testing.expectEqual(@as(u8, 0x42), open_value);
}

test "Bus: ROM write protection" {
    var bus = Bus.init();

    // AccuracyCoin Test: "ROM is not Writable #1"
    // Writing to ROM should not overwrite the byte

    // Put a value on the open bus
    bus.write(0x0000, 0x11);

    // Try to write to ROM space - should be ignored
    bus.write(0x8000, 0x22);

    // Open bus should be updated to the write value
    try std.testing.expectEqual(@as(u8, 0x22), bus.open_bus.value);

    // But reading from ROM should still return open bus
    // (once we have a real cart, this would return the ROM value)
    const rom_value = bus.read(0x8000);
    try std.testing.expectEqual(@as(u8, 0x22), rom_value); // Currently returns open bus
}

test "Bus: read16 little-endian" {
    var bus = Bus.init();

    bus.write(0x0000, 0x34); // Low byte
    bus.write(0x0001, 0x12); // High byte

    const value = bus.read16(0x0000);
    try std.testing.expectEqual(@as(u16, 0x1234), value);
}

test "Bus: read16 with address wraparound" {
    var bus = Bus.init();

    // Test address wraparound at $FFFF boundary
    // $FFFF is unmapped (returns open bus), so use RAM mirror at $1FFF
    bus.ram[0x07FF] = 0xCD; // Maps to $07FF, $0FFF, $17FF, $1FFF
    bus.ram[0x0000] = 0xAB; // Maps to $0000, $0800, $1000, $1800

    // Reading from $07FF, then $0800 (which wraps in address space)
    // $0800 mirrors $0000, so we get 0xAB
    const value = bus.read16(0x07FF);
    try std.testing.expectEqual(@as(u16, 0xABCD), value);
}

test "Bus: read16Bug - indirect JMP bug" {
    var bus = Bus.init();

    // Test the famous 6502 bug where JMP ($xxFF) wraps within page
    // Use RAM addresses to avoid open bus issues
    bus.ram[0x00FF] = 0x34; // Low byte at $00FF (also at $08FF, $10FF, $18FF)
    bus.ram[0x0000] = 0x12; // High byte at $0000 (wraps to page start)
    bus.ram[0x0100] = 0x99; // This should NOT be read by buggy version

    // Test with $08FF (which mirrors $00FF)
    const value = bus.read16Bug(0x08FF);
    try std.testing.expectEqual(@as(u16, 0x1234), value);

    // Verify normal read16 would cross page (incorrect behavior for JMP)
    const normal_value = bus.read16(0x08FF);
    try std.testing.expectEqual(@as(u16, 0x9934), normal_value);
}

test "Bus: read16Bug - normal case no wraparound" {
    var bus = Bus.init();

    // When not at page boundary, should behave normally
    bus.ram[0x0050] = 0x78;
    bus.ram[0x0051] = 0x56;

    const value = bus.read16Bug(0x0050);
    try std.testing.expectEqual(@as(u16, 0x5678), value);
}

test "Bus: dummyRead updates open bus" {
    var bus = Bus.init();

    // AccuracyCoin Test: "Open Bus #5"
    // Dummy reads should update the data bus

    bus.write(0x0100, 0xAA);
    try std.testing.expectEqual(@as(u8, 0xAA), bus.open_bus.value);

    // Dummy read from different address
    bus.write(0x0200, 0xBB);
    bus.dummyRead(0x0200);

    // Open bus should now have the dummy read value
    try std.testing.expectEqual(@as(u8, 0xBB), bus.open_bus.value);
}

test "Bus: cycle counter" {
    var bus = Bus.init();

    try std.testing.expectEqual(@as(u64, 0), bus.cycle);

    bus.tick();
    try std.testing.expectEqual(@as(u64, 1), bus.cycle);

    bus.tick();
    try std.testing.expectEqual(@as(u64, 2), bus.cycle);
}

test "Bus: comprehensive open bus scenario" {
    var bus = Bus.init();

    // Simulate a sequence of operations
    bus.write(0x0000, 0x01);
    try std.testing.expectEqual(@as(u8, 0x01), bus.open_bus.value);

    _ = bus.read(0x0000);
    try std.testing.expectEqual(@as(u8, 0x01), bus.open_bus.value);

    bus.write(0x0100, 0x02);
    try std.testing.expectEqual(@as(u8, 0x02), bus.open_bus.value);

    _ = bus.read(0x0100);
    try std.testing.expectEqual(@as(u8, 0x02), bus.open_bus.value);

    // Read from unmapped - should return last value
    const unmapped = bus.read(0x6000);
    try std.testing.expectEqual(@as(u8, 0x02), unmapped);
}
