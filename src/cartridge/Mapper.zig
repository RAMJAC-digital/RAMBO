//! Mapper Interface for NES Cartridges
//!
//! This module defines the polymorphic interface for NES mappers (Memory Management Controllers).
//! Different cartridges use different mappers to extend the NES's limited address space through
//! bank switching and other techniques.
//!
//! See: https://www.nesdev.org/wiki/Mapper

const std = @import("std");

// Forward declaration - actual Cartridge type imported by implementations
pub const Cartridge = @import("Cartridge.zig").Cartridge;

/// Mapper interface using vtable pattern for polymorphism
/// Each mapper implementation creates its own vtable instance
pub const Mapper = struct {
    /// Pointer to implementation-specific vtable
    vtable: *const VTable,

    /// Virtual function table for mapper operations
    pub const VTable = struct {
        /// Read from CPU address space ($4020-$FFFF)
        /// Returns the value at the mapped address, or undefined for unmapped regions
        cpuRead: *const fn (mapper: *Mapper, cart: *const Cartridge, address: u16) u8,

        /// Write to CPU address space ($4020-$FFFF)
        /// May trigger mapper register writes or PRG RAM writes
        cpuWrite: *const fn (mapper: *Mapper, cart: *Cartridge, address: u16, value: u8) void,

        /// Read from PPU address space ($0000-$1FFF for CHR)
        /// Returns CHR ROM/RAM data
        ppuRead: *const fn (mapper: *Mapper, cart: *const Cartridge, address: u16) u8,

        /// Write to PPU address space ($0000-$1FFF for CHR)
        /// Only valid for CHR RAM (writes to CHR ROM are ignored)
        ppuWrite: *const fn (mapper: *Mapper, cart: *Cartridge, address: u16, value: u8) void,

        /// Reset mapper state
        /// Called when CPU reset occurs - initializes mapper registers
        reset: *const fn (mapper: *Mapper, cart: *Cartridge) void,
    };

    /// Read from CPU address space
    pub inline fn cpuRead(self: *Mapper, cart: *const Cartridge, address: u16) u8 {
        return self.vtable.cpuRead(self, cart, address);
    }

    /// Write to CPU address space
    pub inline fn cpuWrite(self: *Mapper, cart: *Cartridge, address: u16, value: u8) void {
        self.vtable.cpuWrite(self, cart, address, value);
    }

    /// Read from PPU address space
    pub inline fn ppuRead(self: *Mapper, cart: *const Cartridge, address: u16) u8 {
        return self.vtable.ppuRead(self, cart, address);
    }

    /// Write to PPU address space
    pub inline fn ppuWrite(self: *Mapper, cart: *Cartridge, address: u16, value: u8) void {
        self.vtable.ppuWrite(self, cart, address, value);
    }

    /// Reset mapper to power-on state
    pub inline fn reset(self: *Mapper, cart: *Cartridge) void {
        self.vtable.reset(self, cart);
    }
};
