//! Memory bus state owned by emulation runtime
//! Stores all data required to service CPU/PPU bus accesses

const std = @import("std");

/// Memory bus state
pub const BusState = struct {
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
    open_bus: u8 = 0,

    /// Optional external RAM used by tests in lieu of a cartridge
    test_ram: ?[]u8 = null,

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

            // Use high byte for better distribution
            byte.* = @truncate(seed >> 24);
        }

        return result;
    }
};
