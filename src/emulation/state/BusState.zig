//! Memory bus state owned by emulation runtime
//! Stores all data required to service CPU/PPU bus accesses

const std = @import("std");

/// Memory bus state
pub const BusState = struct {
    /// Internal RAM: 2KB ($0000-$07FF), mirrored through $0000-$1FFF
    ram: [2048]u8 = std.mem.zeroes([2048]u8),

    /// Last value observed on CPU data bus (open bus behaviour)
    open_bus: u8 = 0,

    /// Optional external RAM used by tests in lieu of a cartridge
    test_ram: ?[]u8 = null,
};
