//! CHR Memory Provider Interface
//!
//! This module defines a trait-based interface for providing CHR ROM/RAM data
//! to the PPU. This abstraction decouples the PPU from cartridge implementation
//! details, enabling proper dependency injection and testability.
//!
//! Design Rationale:
//! - PPU should not know about Cartridge concrete type
//! - Enables mocking for unit tests
//! - Supports future extensions (network CHR, compression, etc.)
//! - Zero-cost abstraction using Zig's vtable pattern
//! - RT-safe: No allocations, deterministic execution

const std = @import("std");

/// CHR Memory Provider Interface
///
/// Provides read/write access to CHR ROM/RAM (pattern tables) at $0000-$1FFF
/// in PPU address space. Implementers handle the actual storage mechanism
/// (cartridge CHR ROM, CHR RAM, etc.).
///
/// Usage:
/// ```zig
/// var provider = cartridge.chrProvider();
/// const pattern_byte = provider.read(0x0000);
/// provider.write(0x1000, 0x42);  // CHR RAM only
/// ```
pub const ChrProvider = struct {
    /// Opaque pointer to the implementation
    ptr: *anyopaque,

    /// Virtual function table for polymorphism
    vtable: *const VTable,

    /// Virtual function table definition
    pub const VTable = struct {
        /// Read a byte from CHR memory
        ///
        /// Parameters:
        /// - ptr: Opaque pointer to implementation (cast back to concrete type)
        /// - address: PPU address ($0000-$1FFF, will be masked by implementation)
        ///
        /// Returns: Byte value at address (or open bus value if unavailable)
        read: *const fn (ptr: *anyopaque, address: u16) u8,

        /// Write a byte to CHR memory
        ///
        /// Parameters:
        /// - ptr: Opaque pointer to implementation
        /// - address: PPU address ($0000-$1FFF, will be masked by implementation)
        /// - value: Byte to write
        ///
        /// Notes:
        /// - CHR ROM implementations ignore writes
        /// - CHR RAM implementations perform the write
        /// - No error signaling (silent failure for ROM writes is correct)
        write: *const fn (ptr: *anyopaque, address: u16, value: u8) void,
    };

    /// Read a byte from CHR memory
    ///
    /// Address range: $0000-$1FFF (pattern tables)
    /// Addresses outside this range will be masked by implementation
    pub inline fn read(self: ChrProvider, address: u16) u8 {
        return self.vtable.read(self.ptr, address);
    }

    /// Write a byte to CHR memory
    ///
    /// CHR ROM: Write is silently ignored (correct NES behavior)
    /// CHR RAM: Write updates memory
    pub inline fn write(self: ChrProvider, address: u16, value: u8) void {
        self.vtable.write(self.ptr, address, value);
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

/// Test CHR provider implementation for unit testing
const TestChrProvider = struct {
    /// Test data buffer (8KB CHR)
    data: [8192]u8,

    /// Create CHR provider interface from test implementation
    pub fn chrProvider(self: *TestChrProvider) ChrProvider {
        return .{
            .ptr = self,
            .vtable = &.{
                .read = read,
                .write = write,
            },
        };
    }

    /// Read implementation
    fn read(ptr: *anyopaque, address: u16) u8 {
        const self: *TestChrProvider = @ptrCast(@alignCast(ptr));
        return self.data[address & 0x1FFF];
    }

    /// Write implementation
    fn write(ptr: *anyopaque, address: u16, value: u8) void {
        const self: *TestChrProvider = @ptrCast(@alignCast(ptr));
        self.data[address & 0x1FFF] = value;
    }
};

test "ChrProvider: basic read/write" {
    var test_chr = TestChrProvider{
        .data = std.mem.zeroes([8192]u8),
    };

    const provider = test_chr.chrProvider();

    // Write and read back
    provider.write(0x0000, 0x42);
    try testing.expectEqual(@as(u8, 0x42), provider.read(0x0000));

    // Different address
    provider.write(0x1FFF, 0x99);
    try testing.expectEqual(@as(u8, 0x99), provider.read(0x1FFF));

    // Verify isolation
    try testing.expectEqual(@as(u8, 0x42), provider.read(0x0000));
}

test "ChrProvider: address masking" {
    var test_chr = TestChrProvider{
        .data = std.mem.zeroes([8192]u8),
    };

    const provider = test_chr.chrProvider();

    // Write to pattern table
    provider.write(0x1234, 0xAB);

    // Read from mirrored address (address should be masked to $0000-$1FFF)
    try testing.expectEqual(@as(u8, 0xAB), provider.read(0x1234));

    // Verify masking at boundaries
    provider.write(0x2000, 0xCD);  // Should wrap to $0000
    try testing.expectEqual(@as(u8, 0xCD), provider.read(0x0000));
}

test "ChrProvider: pattern table separation" {
    var test_chr = TestChrProvider{
        .data = std.mem.zeroes([8192]u8),
    };

    const provider = test_chr.chrProvider();

    // Pattern table 0 ($0000-$0FFF)
    provider.write(0x0000, 0x11);
    provider.write(0x0FFF, 0x22);

    // Pattern table 1 ($1000-$1FFF)
    provider.write(0x1000, 0x33);
    provider.write(0x1FFF, 0x44);

    // Verify all values
    try testing.expectEqual(@as(u8, 0x11), provider.read(0x0000));
    try testing.expectEqual(@as(u8, 0x22), provider.read(0x0FFF));
    try testing.expectEqual(@as(u8, 0x33), provider.read(0x1000));
    try testing.expectEqual(@as(u8, 0x44), provider.read(0x1FFF));
}
