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

pub const CpuCoreState = StateModule.CpuCoreState;
pub const StatusFlags = StateModule.StatusFlags;
pub const OpcodeResult = StateModule.OpcodeResult;

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
    /// LXA magic constant
    /// Varies by chip: 0xEE (NMOS), 0xFF (some), 0x00 (Synertek)
    lxa_magic: u8,

    /// ANE/XAA magic constant (same as LXA for most chips)
    ane_magic: u8,

    /// Clock frequency (for reference, not used in pure functions)
    clock_hz: u32,
};

/// Get variant configuration at comptime
pub fn getVariantConfig(comptime variant: CpuVariant) VariantConfig {
    return switch (variant) {
        .rp2a03e => .{
            .lxa_magic = 0xEE,
            .ane_magic = 0xEE,
            .clock_hz = 1789773, // NTSC
        },
        .rp2a03g => .{
            .lxa_magic = 0xEE,
            .ane_magic = 0xEE,
            .clock_hz = 1789773, // NTSC
        },
        .rp2a03h => .{
            .lxa_magic = 0xFF, // Different magic constant
            .ane_magic = 0xFF,
            .clock_hz = 1789773, // NTSC
        },
        .rp2a07 => .{
            .lxa_magic = 0x00, // PAL chips often use 0x00
            .ane_magic = 0x00,
            .clock_hz = 1662607, // PAL
        },
        .dendy => .{
            .lxa_magic = 0xEE,
            .ane_magic = 0xEE,
            .clock_hz = 1773448, // Dendy timing
        },
        .clone => .{
            .lxa_magic = 0xEE,
            .ane_magic = 0xEE,
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
        pub const State = CpuCoreState;
        pub const Flags = StatusFlags;
        pub const Result = OpcodeResult;

        // ============================================================================
        // Variant-Dependent Unofficial Opcodes
        // ============================================================================
        // These opcodes use comptime variant configuration for hardware-accurate behavior

        /// LXA - Highly unstable load A and X
        /// A = X = (A | MAGIC) & operand
        /// Flags: N, Z
        ///
        /// HIGHLY UNSTABLE: Magic constant varies by chip
        /// - RP2A03G/E: 0xEE (most common NMOS)
        /// - RP2A03H: 0xFF
        /// - RP2A07: 0x00 (PAL)
        pub fn lxa(state: CpuCoreState, operand: u8) OpcodeResult {
            const magic = comptime config.lxa_magic;  // Comptime constant!
            const result = (state.a | magic) & operand;
            return .{
                .a = result,
                .x = result,
                .flags = state.p.setZN(result),
            };
        }

        /// XAA - Highly unstable AND X + AND immediate
        /// A = (A | MAGIC) & X & operand
        /// Flags: N, Z
        ///
        /// HIGHLY UNSTABLE: Magic constant varies by chip
        /// Same magic constant as LXA for most chips
        pub fn xaa(state: CpuCoreState, operand: u8) OpcodeResult {
            const magic = comptime config.ane_magic;  // Comptime constant!
            const result = (state.a | magic) & state.x & operand;
            return .{
                .a = result,
                .flags = state.p.setZN(result),
            };
        }

        // ============================================================================
        // Variant-Independent Unofficial Opcodes
        // ============================================================================
        // These opcodes work the same across all CPU variants

        /// LAX - Load Accumulator and X Register
        /// A = X = operand
        /// Flags: N, Z
        pub fn lax(state: CpuCoreState, operand: u8) OpcodeResult {
            return .{
                .a = operand,
                .x = operand,
                .flags = state.p.setZN(operand),
            };
        }

        /// SAX - Store A AND X
        /// M = A & X (no CPU state change)
        /// Flags: None
        pub fn sax(state: CpuCoreState, _: u8) OpcodeResult {
            return .{
                .bus_write = .{
                    .address = state.effective_address,
                    .value = state.a & state.x,
                },
            };
        }

        /// LAE/LAS - Load A, X, and SP with memory & SP
        /// value = operand & SP
        /// A = X = SP = value
        /// Flags: N, Z
        pub fn lae(state: CpuCoreState, operand: u8) OpcodeResult {
            const result = operand & state.sp;
            return .{
                .a = result,
                .x = result,
                .sp = result,
                .flags = state.p.setZN(result),
            };
        }

        /// ANC - AND + Copy bit 7 to Carry
        /// A = A & operand, C = bit 7 of result
        /// Flags: C (equals N), N, Z
        pub fn anc(state: CpuCoreState, operand: u8) OpcodeResult {
            const result = state.a & operand;
            return .{
                .a = result,
                .flags = state.p
                    .setCarry((result & 0x80) != 0)
                    .setZN(result),
            };
        }

        /// ALR/ASR - AND + LSR
        /// A = (A & operand) >> 1
        /// Flags: C (from LSR), N, Z
        pub fn alr(state: CpuCoreState, operand: u8) OpcodeResult {
            const anded = state.a & operand;
            const result = anded >> 1;
            return .{
                .a = result,
                .flags = state.p
                    .setCarry((anded & 0x01) != 0)
                    .setZN(result),
            };
        }

        /// ARR - AND + ROR
        /// A = (A & operand) ROR 1
        /// Flags: C (from bit 6), V (bit 6 XOR bit 5), N, Z
        pub fn arr(state: CpuCoreState, operand: u8) OpcodeResult {
            const anded = state.a & operand;
            const result = (anded >> 1) | (if (state.p.carry) @as(u8, 0x80) else 0);

            return .{
                .a = result,
                .flags = StatusFlags{
                    .carry = (result & 0x40) != 0,
                    .zero = (result == 0),
                    .interrupt = state.p.interrupt,
                    .decimal = state.p.decimal,
                    .break_flag = state.p.break_flag,
                    .unused = true,
                    .overflow = ((result & 0x40) != 0) != ((result & 0x20) != 0),
                    .negative = (result & 0x80) != 0,
                },
            };
        }

        /// AXS/SBX - (A & X) - operand → X
        /// X = (A & X) - operand (without borrow)
        /// Flags: C (from comparison), N, Z
        pub fn axs(state: CpuCoreState, operand: u8) OpcodeResult {
            const temp = state.a & state.x;
            const result = temp -% operand;
            return .{
                .x = result,
                .flags = state.p
                    .setCarry(temp >= operand)
                    .setZN(result),
            };
        }

        /// SHA/AHX - Store A & X & (H+1)
        /// M = A & X & (high_byte + 1)
        /// Flags: None
        ///
        /// UNSTABLE: High byte calculation sometimes fails on some revisions
        pub fn sha(state: CpuCoreState, _: u8) OpcodeResult {
            const high_byte = @as(u8, @truncate(state.effective_address >> 8));
            const value = state.a & state.x & (high_byte +% 1);
            return .{
                .bus_write = .{
                    .address = state.effective_address,
                    .value = value,
                },
            };
        }

        /// SHX - Store X & (H+1)
        /// M = X & (high_byte + 1)
        /// Flags: None
        ///
        /// UNSTABLE: High byte calculation sometimes fails on some revisions
        pub fn shx(state: CpuCoreState, _: u8) OpcodeResult {
            const high_byte = @as(u8, @truncate(state.effective_address >> 8));
            const value = state.x & (high_byte +% 1);
            return .{
                .bus_write = .{
                    .address = state.effective_address,
                    .value = value,
                },
            };
        }

        /// SHY - Store Y & (H+1)
        /// M = Y & (high_byte + 1)
        /// Flags: None
        ///
        /// UNSTABLE: High byte calculation sometimes fails on some revisions
        pub fn shy(state: CpuCoreState, _: u8) OpcodeResult {
            const high_byte = @as(u8, @truncate(state.effective_address >> 8));
            const value = state.y & (high_byte +% 1);
            return .{
                .bus_write = .{
                    .address = state.effective_address,
                    .value = value,
                },
            };
        }

        /// TAS/SHS - Transfer A & X to SP, then store A & X & (H+1)
        /// SP = A & X
        /// M = A & X & (high_byte + 1)
        /// Flags: None
        ///
        /// HIGHLY UNSTABLE: Behavior varies significantly between chip revisions
        pub fn tas(state: CpuCoreState, _: u8) OpcodeResult {
            const temp = state.a & state.x;
            const high_byte = @as(u8, @truncate(state.effective_address >> 8));
            const value = temp & (high_byte +% 1);
            return .{
                .sp = temp,
                .bus_write = .{
                    .address = state.effective_address,
                    .value = value,
                },
            };
        }

        /// JAM/KIL - Halt the CPU
        /// CPU enters infinite loop, only RESET recovers
        /// Flags: None
        pub fn jam(_: CpuCoreState, _: u8) OpcodeResult {
            return .{
                .halt = true,
            };
        }

        /// SLO - Shift Left + OR (ASL + ORA)
        /// M = M << 1, A |= M
        /// Flags: C (from shift), N, Z
        pub fn slo(state: CpuCoreState, operand: u8) OpcodeResult {
            const shifted = operand << 1;
            const new_a = state.a | shifted;
            return .{
                .a = new_a,
                .bus_write = .{
                    .address = state.effective_address,
                    .value = shifted,
                },
                .flags = state.p
                    .setCarry((operand & 0x80) != 0)
                    .setZN(new_a),
            };
        }

        /// RLA - Rotate Left + AND (ROL + AND)
        /// M = (M << 1) | C, A &= M
        /// Flags: C (from rotate), N, Z
        pub fn rla(state: CpuCoreState, operand: u8) OpcodeResult {
            const rotated = (operand << 1) | (if (state.p.carry) @as(u8, 1) else 0);
            const new_a = state.a & rotated;
            return .{
                .a = new_a,
                .bus_write = .{
                    .address = state.effective_address,
                    .value = rotated,
                },
                .flags = state.p
                    .setCarry((operand & 0x80) != 0)
                    .setZN(new_a),
            };
        }

        /// SRE - Shift Right + EOR (LSR + EOR)
        /// M = M >> 1, A ^= M
        /// Flags: C (from shift), N, Z
        pub fn sre(state: CpuCoreState, operand: u8) OpcodeResult {
            const shifted = operand >> 1;
            const new_a = state.a ^ shifted;
            return .{
                .a = new_a,
                .bus_write = .{
                    .address = state.effective_address,
                    .value = shifted,
                },
                .flags = state.p
                    .setCarry((operand & 0x01) != 0)
                    .setZN(new_a),
            };
        }

        /// RRA - Rotate Right + ADC (ROR + ADC)
        /// M = (M >> 1) | (C << 7), A = A + M + C_from_rotate
        /// Flags: C, V, N, Z
        pub fn rra(state: CpuCoreState, operand: u8) OpcodeResult {
            const carry_from_rotate = (operand & 0x01) != 0;
            const rotated = (operand >> 1) | (if (state.p.carry) @as(u8, 0x80) else 0);

            const a = state.a;
            const carry_in: u8 = if (carry_from_rotate) 1 else 0;
            const result16 = @as(u16, a) + @as(u16, rotated) + @as(u16, carry_in);
            const result = @as(u8, @truncate(result16));

            return .{
                .a = result,
                .bus_write = .{
                    .address = state.effective_address,
                    .value = rotated,
                },
                .flags = StatusFlags{
                    .carry = (result16 > 0xFF),
                    .zero = (result == 0),
                    .interrupt = state.p.interrupt,
                    .decimal = state.p.decimal,
                    .break_flag = state.p.break_flag,
                    .unused = true,
                    .overflow = ((a ^ result) & (rotated ^ result) & 0x80) != 0,
                    .negative = (result & 0x80) != 0,
                },
            };
        }

        /// DCP - Decrement + Compare (DEC + CMP)
        /// M = M - 1, compare A with M
        /// Flags: C, N, Z
        pub fn dcp(state: CpuCoreState, operand: u8) OpcodeResult {
            const decremented = operand -% 1;
            const comparison = state.a -% decremented;
            return .{
                .bus_write = .{
                    .address = state.effective_address,
                    .value = decremented,
                },
                .flags = StatusFlags{
                    .carry = state.a >= decremented,
                    .zero = state.a == decremented,
                    .interrupt = state.p.interrupt,
                    .decimal = state.p.decimal,
                    .break_flag = state.p.break_flag,
                    .unused = true,
                    .overflow = state.p.overflow,
                    .negative = (comparison & 0x80) != 0,
                },
            };
        }

        /// ISC/ISB - Increment + Subtract (INC + SBC)
        /// M = M + 1, A = A - M - (1 - C)
        /// Flags: C, V, N, Z
        pub fn isc(state: CpuCoreState, operand: u8) OpcodeResult {
            const incremented = operand +% 1;

            const inverted = ~incremented;
            const a = state.a;
            const carry: u8 = if (state.p.carry) 1 else 0;
            const result16 = @as(u16, a) + @as(u16, inverted) + @as(u16, carry);
            const result = @as(u8, @truncate(result16));

            return .{
                .a = result,
                .bus_write = .{
                    .address = state.effective_address,
                    .value = incremented,
                },
                .flags = StatusFlags{
                    .carry = (result16 > 0xFF),
                    .zero = (result == 0),
                    .interrupt = state.p.interrupt,
                    .decimal = state.p.decimal,
                    .break_flag = state.p.break_flag,
                    .unused = true,
                    .overflow = ((a ^ result) & (inverted ^ result) & 0x80) != 0,
                    .negative = (result & 0x80) != 0,
                },
            };
        }
    };
}

// ============================================================================
// Compile-Time Validation Tests
// ============================================================================

const testing = std.testing;

test "Cpu(variant): comptime variant dispatch" {
    const CpuG = Cpu(.rp2a03g);
    const CpuH = Cpu(.rp2a03h);

    const state = CpuCoreState{};

    // LAX should work identically across variants (not variant-dependent)
    const result_g = CpuG.lax(state, 0x42);
    const result_h = CpuH.lax(state, 0x42);

    try testing.expectEqual(@as(u8, 0x42), result_g.a.?);
    try testing.expectEqual(@as(u8, 0x42), result_g.x.?);
    try testing.expectEqual(@as(u8, 0x42), result_h.a.?);
    try testing.expectEqual(@as(u8, 0x42), result_h.x.?);
}

test "Cpu(variant): LXA variant-specific magic" {
    const CpuG = Cpu(.rp2a03g);
    const CpuH = Cpu(.rp2a03h);
    const CpuPAL = Cpu(.rp2a07);

    // Test LXA with different magic constants
    // Starting with A=0x00 makes magic constant visible
    const state = CpuCoreState{ .a = 0x00, .x = 0, .y = 0, .sp = 0xFD, .pc = 0, .p = .{}, .effective_address = 0 };

    const result_g = CpuG.lxa(state, 0xFF);
    const result_h = CpuH.lxa(state, 0xFF);
    const result_pal = CpuPAL.lxa(state, 0xFF);

    // RP2A03G uses 0xEE magic: (0x00 | 0xEE) & 0xFF = 0xEE
    try testing.expectEqual(@as(u8, 0xEE), result_g.a.?);
    try testing.expectEqual(@as(u8, 0xEE), result_g.x.?);

    // RP2A03H uses 0xFF magic: (0x00 | 0xFF) & 0xFF = 0xFF
    try testing.expectEqual(@as(u8, 0xFF), result_h.a.?);
    try testing.expectEqual(@as(u8, 0xFF), result_h.x.?);

    // RP2A07 (PAL) uses 0x00 magic: (0x00 | 0x00) & 0xFF = 0x00
    try testing.expectEqual(@as(u8, 0x00), result_pal.a.?);
    try testing.expectEqual(@as(u8, 0x00), result_pal.x.?);
}

test "Cpu(variant): XAA variant-specific magic" {
    const CpuG = Cpu(.rp2a03g);
    const CpuH = Cpu(.rp2a03h);

    const state = CpuCoreState{ .a = 0x00, .x = 0xFF, .y = 0, .sp = 0xFD, .pc = 0, .p = .{}, .effective_address = 0 };

    const result_g = CpuG.xaa(state, 0xFF);
    const result_h = CpuH.xaa(state, 0xFF);

    // RP2A03G uses 0xEE magic: (0x00 | 0xEE) & 0xFF & 0xFF = 0xEE
    try testing.expectEqual(@as(u8, 0xEE), result_g.a.?);

    // RP2A03H uses 0xFF magic: (0x00 | 0xFF) & 0xFF & 0xFF = 0xFF
    try testing.expectEqual(@as(u8, 0xFF), result_h.a.?);
}

test "Cpu(variant): variant config resolution" {
    const config_g = comptime getVariantConfig(.rp2a03g);
    const config_h = comptime getVariantConfig(.rp2a03h);
    const config_pal = comptime getVariantConfig(.rp2a07);

    try testing.expectEqual(@as(u8, 0xEE), config_g.lxa_magic);
    try testing.expectEqual(@as(u8, 0xFF), config_h.lxa_magic);
    try testing.expectEqual(@as(u8, 0x00), config_pal.lxa_magic);
}

test "Cpu(variant): zero runtime overhead" {
    // Both variants should produce specialized machine code
    // (comptime specialization, not runtime dispatch)
    const CpuG = Cpu(.rp2a03g);
    const CpuH = Cpu(.rp2a03h);

    const state = CpuCoreState{};

    _ = CpuG.lax(state, 0x42);
    _ = CpuH.lax(state, 0x42);

    // No assertion needed - this test verifies compilation succeeds
    // and type system enforces compile-time variant selection
}
