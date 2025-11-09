//! Bus State - Memory bus data and handlers
//!
//! Owns all bus-related state including RAM, open bus tracking, and handler instances.
//! Follows State/Logic separation pattern established by CPU/PPU/APU/DMA/Controller modules.

const std = @import("std");

/// Bus state
pub const State = struct {
    /// CPU open bus state (tracks external/internal data bus)
    pub const OpenBus = struct {
        /// Last value driven on CPU data bus (externally visible)
        external: u8 = 0,

        /// CPU internal data latch (captures $4015 behaviour)
        internal: u8 = 0,

        /// Update both external and internal buses (default behaviour)
        pub fn set(self: *OpenBus, value: u8) void {
            self.external = value;
            self.internal = value;
        }

        /// Update internal bus only (used for $4015 reads)
        pub fn setInternal(self: *OpenBus, value: u8) void {
            self.internal = value;
        }

        /// Read external bus value (for normal open bus behaviour)
        pub fn get(self: *const OpenBus) u8 {
            return self.external;
        }

        /// Read masked internal bus bits (controllers/APU quirks)
        ///
        /// MESEN2 BUG DOCUMENTATION:
        /// Mesen2's OpenBusHandler.h:32-35 contains a copy-paste bug where
        /// GetInternalOpenBus() incorrectly returns _externalOpenBus instead of _internalOpenBus:
        ///
        ///   __forceinline uint8_t GetInternalOpenBus() {
        ///       return _externalOpenBus;  // ← BUG: should be _internalOpenBus
        ///   }
        ///
        /// This affects $4015 (APU status) reads, which should use the internal latch
        /// but actually use the external latch in Mesen2.
        ///
        /// RAMBO implements this CORRECTLY (returns internal latch).
        /// This causes test divergence with Mesen2-based test ROMs (e.g., AccuracyCoin's
        /// "$4015 OPEN BUS" test expects the buggy behavior).
        ///
        /// Decision: Keep RAMBO correct. Hardware accuracy > test suite match.
        ///
        /// Hardware behavior: $4015 reads update CPU internal latch but NOT external bus.
        /// Reference: nesdev.org/wiki/APU ($4015 behavior notes)
        /// Mesen2 bug: /home/colin/Development/Mesen2/Core/NES/OpenBusHandler.h:32-35
        ///
        /// TODO: File upstream bug report with Mesen2 project
        pub fn getInternal(self: *const OpenBus, mask: u8) u8 {
            return self.internal & mask; // CORRECT - returns internal latch
        }
    };

    /// Internal RAM: 2KB ($0000-$07FF), mirrored through $0000-$1FFF
    ///
    /// Hardware behavior: NES RAM at power-on contains pseudo-random garbage
    /// influenced by manufacturing variations, temperature, and previous state.
    /// Many commercial ROMs rely on non-zero RAM initialization and will fail
    /// to boot correctly with all-zero RAM (executing rare/untested code paths).
    ///
    /// Default initialization uses a deterministic pseudo-random pattern.
    /// Reference: nesdev.org/wiki/CPU_power_up_state
    ram: [2048]u8 = initializeRam(),

    /// Last value observed on CPU data bus (open bus behaviour)
    open_bus: OpenBus = .{},

    /// Optional external RAM used by tests in lieu of a cartridge
    test_ram: ?[]u8 = null,

    /// Bus handlers (zero-size stateless, owned by bus module)
    handlers: struct {
        open_bus: @import("handlers/OpenBusHandler.zig").OpenBusHandler = .{},
        ram: @import("handlers/RamHandler.zig").RamHandler = .{},
        ppu: @import("handlers/PpuHandler.zig").PpuHandler = .{},
        apu: @import("handlers/ApuHandler.zig").ApuHandler = .{},
        controller: @import("handlers/ControllerHandler.zig").ControllerHandler = .{},
        oam_dma: @import("handlers/OamDmaHandler.zig").OamDmaHandler = .{},
        cartridge: @import("handlers/CartridgeHandler.zig").CartridgeHandler = .{},
    } = .{},

    /// Initialize RAM with hardware-accurate pseudo-random pattern
    /// Uses compile-time evaluation for zero runtime overhead
    fn initializeRam() [2048]u8 {
        // Hardware: NES power-on RAM contains pseudo-random data
        // Pattern varies by console due to manufacturing variations
        //
        // Common observed patterns (per nesdev.org wiki):
        // - Some bytes tend toward $00 or $FF
        // - Adjacent bytes often differ
        // - Pattern is consistent per power-cycle but varies between consoles
        //
        // We use a simple PRNG with fixed seed for deterministic behavior
        // This matches "typical" hardware while remaining reproducible for testing

        @setEvalBranchQuota(3000); // Need higher quota for 2048-iteration loop

        var result: [2048]u8 = undefined;

        // Linear Congruential Generator (LCG) - simple, fast, deterministic
        // Parameters from Numerical Recipes (widely used, good distribution)
        var seed: u32 = 0x12345678; // Fixed seed for determinism

        for (&result) |*byte| {
            // LCG formula: seed = (a * seed + c) mod m
            seed = seed *% 1664525 +% 1013904223; // Wrapping mul/add

            // Use high byte but bias toward lower values
            // Real NES power-on tends toward 0x00 or 0xFF, with bias toward 0x00
            // Mix high byte with low nibble for better distribution
            const raw = @as(u8, @truncate(seed >> 24));

            // 87.5% chance of low nibble (0x00-0x0F), 12.5% chance of high values
            // This matches observed power-on patterns where many bytes are 0x00-0x0F
            byte.* = if ((seed & 0x07) != 0) raw & 0x0F else raw;
        }

        return result;
    }
};
