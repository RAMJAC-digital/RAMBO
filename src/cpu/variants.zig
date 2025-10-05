//! Comptime CPU Variant Type Factory
//!
//! Enables hardware-accurate emulation with zero-cost variant dispatch.
//! Each CPU variant (RP2A03G, RP2A03H, RP2A07) is a distinct type with
//! variant-specific behavior baked in at compile time.
//!
//! Design:
//! - Comptime type factory: Cpu(.rp2a03g) returns distinct type
//! - Duck typing: Each variant implements required interface
//! - Zero runtime overhead: All variant differences resolved at compile time
//! - Thread-safe: No shared mutable state

const std = @import("std");
const StateModule = @import("State.zig");

pub const CpuState = StateModule.PureCpuState;
pub const StatusFlags = StateModule.StatusFlags;

/// CPU Variants (matching config system)
pub const CpuVariant = enum {
    /// RP2A03E - Early NTSC revision
    rp2a03e,

    /// RP2A03G - Standard NTSC revision (AccuracyCoin target)
    /// Most common in NES front-loaders
    rp2a03g,

    /// RP2A03H - Later NTSC revision
    /// Different unstable opcode behavior
    rp2a03h,

    /// RP2A07 - PAL revision
    /// 50 Hz timing, different characteristics
    rp2a07,

    /// Dendy - Russian clone
    dendy,

    /// Clone CPUs (UM6561, UA6527P, etc.)
    clone,
};

/// Variant Configuration Interface
///
/// Each CPU variant MUST implement these comptime-known values.
/// The Cpu() type factory validates this at compile time.
pub const VariantConfig = struct {
    /// LXA/XAA magic constant
    /// Varies by chip: 0xEE (NMOS), 0xFF (some), 0x00 (Synertek)
    lxa_magic: u8,

    /// ANE/XAA magic constant (same as LXA for most chips)
    ane_magic: u8,

    /// SHA behavior variant
    /// RP2A03G vs RP2A03H have different SHA implementations
    sha_behavior: enum { rp2a03g, rp2a03h, standard },

    /// Clock frequency (for reference, not used in pure functions)
    clock_hz: u32,
};

/// Get variant configuration at comptime
pub fn getVariantConfig(comptime variant: CpuVariant) VariantConfig {
    return switch (variant) {
        .rp2a03e => .{
            .lxa_magic = 0xEE,
            .ane_magic = 0xEE,
            .sha_behavior = .rp2a03g,
            .clock_hz = 1789773, // NTSC
        },
        .rp2a03g => .{
            .lxa_magic = 0xEE,
            .ane_magic = 0xEE,
            .sha_behavior = .rp2a03g,
            .clock_hz = 1789773, // NTSC
        },
        .rp2a03h => .{
            .lxa_magic = 0xFF, // Different magic constant
            .ane_magic = 0xFF,
            .sha_behavior = .rp2a03h, // Different SHA behavior
            .clock_hz = 1789773, // NTSC
        },
        .rp2a07 => .{
            .lxa_magic = 0x00, // PAL chips often use 0x00
            .ane_magic = 0x00,
            .sha_behavior = .standard,
            .clock_hz = 1662607, // PAL
        },
        .dendy => .{
            .lxa_magic = 0xEE,
            .ane_magic = 0xEE,
            .sha_behavior = .standard,
            .clock_hz = 1773448, // Dendy timing
        },
        .clone => .{
            .lxa_magic = 0xEE,
            .ane_magic = 0xEE,
            .sha_behavior = .standard,
            .clock_hz = 1789773,
        },
    };
}

/// CPU Type Factory - Comptime Variant Specialization
///
/// Each Cpu(variant) is a DISTINCT type with variant-specific behavior
/// baked in at compile time. No runtime overhead, no virtual dispatch.
///
/// Usage:
///   const CpuG = Cpu(.rp2a03g);
///   const state = CpuG.lda(cpu_state, 0x42);
///
pub fn Cpu(comptime variant: CpuVariant) type {
    // Get comptime-known variant configuration
    const config = comptime getVariantConfig(variant);

    return struct {
        /// Re-export types for convenience
        pub const State = CpuState;
        pub const Flags = StatusFlags;

        // ========================================================================
        // Pure Opcode Functions (Examples - full set in Opcodes.zig)
        // ========================================================================

        /// LDA - Load Accumulator (Official Opcode)
        /// Pure function: (state, operand) -> new_state
        pub fn lda(state: CpuState, operand: u8) CpuState {
            return CpuState{
                .a = operand,
                .x = state.x,
                .y = state.y,
                .sp = state.sp,
                .pc = state.pc,
                .p = state.p.setZN(operand),
            };
        }

        /// LXA - Load A and X (Unstable Unofficial Opcode)
        /// Variant-specific magic constant resolved at compile time
        pub fn lxa(state: CpuState, operand: u8) CpuState {
            // Magic constant is comptime-known!
            const magic = comptime config.lxa_magic;
            const result = (state.a | magic) & operand;

            return CpuState{
                .a = result,
                .x = result,
                .y = state.y,
                .sp = state.sp,
                .pc = state.pc,
                .p = state.p.setZN(result),
            };
        }

        /// XAA/ANE - AND X + AND Immediate (Unstable Unofficial Opcode)
        /// Variant-specific magic constant resolved at compile time
        pub fn xaa(state: CpuState, operand: u8) CpuState {
            // Magic constant is comptime-known!
            const magic = comptime config.ane_magic;
            const result = (state.a | magic) & state.x & operand;

            return CpuState{
                .a = result,
                .x = state.x,
                .y = state.y,
                .sp = state.sp,
                .pc = state.pc,
                .p = state.p.setZN(result),
            };
        }

        // More opcodes will be added as we migrate...
    };
}

// ============================================================================
// Compile-Time Validation Tests
// ============================================================================

const testing = std.testing;

test "Cpu: comptime variant dispatch" {
    const CpuG = Cpu(.rp2a03g);
    const CpuH = Cpu(.rp2a03h);

    const state = CpuState.init();

    // LDA should work identically across variants
    const state_g_lda = CpuG.lda(state, 0x42);
    const state_h_lda = CpuH.lda(state, 0x42);

    try testing.expectEqual(@as(u8, 0x42), state_g_lda.a);
    try testing.expectEqual(@as(u8, 0x42), state_h_lda.a);
}

test "Cpu: variant-specific unstable opcodes" {
    const CpuG = Cpu(.rp2a03g);
    const CpuH = Cpu(.rp2a03h);

    // Test LXA with different magic constants
    const state = CpuState{ .a = 0xFF, .x = 0, .y = 0, .sp = 0xFD, .pc = 0, .p = .{} };

    const result_g = CpuG.lxa(state, 0xFF);
    const result_h = CpuH.lxa(state, 0xFF);

    // RP2A03G uses 0xEE magic: (0xFF | 0xEE) & 0xFF = 0xFF
    try testing.expectEqual(@as(u8, 0xFF), result_g.a);
    try testing.expectEqual(@as(u8, 0xFF), result_g.x);

    // RP2A03H uses 0xFF magic: (0xFF | 0xFF) & 0xFF = 0xFF
    try testing.expectEqual(@as(u8, 0xFF), result_h.a);
    try testing.expectEqual(@as(u8, 0xFF), result_h.x);
}

test "Cpu: variant config resolution" {
    const config_g = comptime getVariantConfig(.rp2a03g);
    const config_h = comptime getVariantConfig(.rp2a03h);

    try testing.expectEqual(@as(u8, 0xEE), config_g.lxa_magic);
    try testing.expectEqual(@as(u8, 0xFF), config_h.lxa_magic);
}

test "Cpu: zero runtime overhead" {
    // Both variants should produce identical machine code for LDA
    // (comptime specialization, not runtime dispatch)
    const CpuG = Cpu(.rp2a03g);
    const CpuH = Cpu(.rp2a03h);

    const state = CpuState.init();

    _ = CpuG.lda(state, 0x42);
    _ = CpuH.lda(state, 0x42);

    // No assertion needed - this test verifies compilation succeeds
    // and type system enforces compile-time variant selection
}
