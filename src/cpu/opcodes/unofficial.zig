//! Unofficial/Undocumented 6502 Instructions
//!
//! These instructions are not officially documented but work reliably on all
//! 6502/2A03 hardware. They are tested by AccuracyCoin and used by some games.
//!
//! Reference: https://www.nesdev.org/wiki/CPU_unofficial_opcodes
//!
//! Categories:
//! - Load/Store Combos: LAX, SAX, LAE
//! - Immediate Logic/Math: ANC, ALR, ARR, AXS
//! - Unstable Store Operations: SHA, SHX, SHY, TAS
//! - Highly Unstable: XAA, LXA (magic constant varies by chip)
//! - CPU Halt: JAM/KIL
//! - Read-Modify-Write Combos: SLO, RLA, SRE, RRA, DCP, ISC
//!
//! NOTE: Highly unstable opcodes (XAA, LXA) with variant-specific magic
//! constants are implemented using $EE (most common NMOS behavior).

const StateModule = @import("../State.zig");

pub const CpuState = StateModule.CpuCoreState;
pub const StatusFlags = StateModule.StatusFlags;
pub const OpcodeResult = StateModule.OpcodeResult;

// ============================================================================
// Load/Store Combos
// ============================================================================

/// LAX - Load Accumulator and X Register
/// A = X = operand
/// Flags: N, Z
///
/// Combines LDA and TAX into a single instruction.
pub fn lax(state: CpuState, operand: u8) OpcodeResult {
    return .{
        .a = operand,
        .x = operand,
        .flags = state.p.setZN(operand),
    };
}

/// SAX - Store A AND X
/// M = A & X (no CPU state change)
/// Flags: None
pub fn sax(state: CpuState, _: u8) OpcodeResult {
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
///
/// Relatively stable compared to other unstable opcodes.
pub fn lae(state: CpuState, operand: u8) OpcodeResult {
    const result = operand & state.sp;
    return .{
        .a = result,
        .x = result,
        .sp = result,
        .flags = state.p.setZN(result),
    };
}

// ============================================================================
// Immediate Logic/Math Operations
// ============================================================================

/// ANC - AND + Copy bit 7 to Carry
/// A = A & operand, C = bit 7 of result
/// Flags: C (equals N), N, Z
///
/// Immediate mode only.
pub fn anc(state: CpuState, operand: u8) OpcodeResult {
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
///
/// Immediate mode only.
pub fn alr(state: CpuState, operand: u8) OpcodeResult {
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
///
/// Immediate mode only. Complex flag behavior.
pub fn arr(state: CpuState, operand: u8) OpcodeResult {
    const anded = state.a & operand;
    const result = (anded >> 1) | (if (state.p.carry) @as(u8, 0x80) else 0);

    return .{
        .a = result,
        .flags = StatusFlags{
            .carry = (result & 0x40) != 0, // From bit 6
            .zero = (result == 0),
            .interrupt = state.p.interrupt,
            .decimal = state.p.decimal,
            .break_flag = state.p.break_flag,
            .unused = true,
            .overflow = ((result & 0x40) != 0) != ((result & 0x20) != 0), // Bit 6 XOR bit 5
            .negative = (result & 0x80) != 0,
        },
    };
}

/// AXS/SBX - (A & X) - operand → X
/// X = (A & X) - operand (without borrow)
/// Flags: C (from comparison), N, Z
///
/// Immediate mode only.
pub fn axs(state: CpuState, operand: u8) OpcodeResult {
    const temp = state.a & state.x;
    const result = temp -% operand;
    return .{
        .x = result,
        .flags = state.p
            .setCarry(temp >= operand)
            .setZN(result),
    };
}

// ============================================================================
// Unstable Store Operations (Hardware-Dependent)
// ============================================================================
//
// WARNING: These opcodes have unstable behavior that varies between
// different 6502 chip revisions. The high byte calculation may fail,
// especially when page boundaries are NOT crossed.

/// SHA/AHX - Store A & X & (H+1)
/// M = A & X & (high_byte + 1)
/// Flags: None
///
/// UNSTABLE: High byte calculation sometimes fails on some revisions.
pub fn sha(state: CpuState, _: u8) OpcodeResult {
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
/// UNSTABLE: High byte calculation sometimes fails on some revisions.
pub fn shx(state: CpuState, _: u8) OpcodeResult {
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
/// UNSTABLE: High byte calculation sometimes fails on some revisions.
pub fn shy(state: CpuState, _: u8) OpcodeResult {
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
/// HIGHLY UNSTABLE: Behavior varies significantly between chip revisions.
pub fn tas(state: CpuState, _: u8) OpcodeResult {
    const temp = state.a & state.x;
    const high_byte = @as(u8, @truncate(state.effective_address >> 8));
    const value = temp & (high_byte +% 1);
    return .{
        .sp = temp, // SP = A & X
        .bus_write = .{
            .address = state.effective_address,
            .value = value,
        },
    };
}

/// XAA - Highly unstable AND X + AND immediate
/// A = (A | MAGIC) & X & operand
/// Flags: N, Z
///
/// HIGHLY UNSTABLE: Magic constant varies by chip ($00, $EE, $FF, others)
/// This implementation uses $EE (most common NMOS behavior)
/// Addressing mode: immediate ($8B)
pub fn xaa(state: CpuState, operand: u8) OpcodeResult {
    const magic: u8 = 0xEE; // Most common NMOS 6502 magic constant
    const result = (state.a | magic) & state.x & operand;
    return .{
        .a = result,
        .flags = state.p.setZN(result),
    };
}

/// LXA - Highly unstable load A and X
/// A = X = (A | MAGIC) & operand
/// Flags: N, Z
///
/// HIGHLY UNSTABLE: Magic constant varies by chip ($00, $EE, $FF, others)
/// This implementation uses $EE (most common NMOS behavior)
/// Addressing mode: immediate ($AB)
pub fn lxa(state: CpuState, operand: u8) OpcodeResult {
    const magic: u8 = 0xEE; // Most common NMOS 6502 magic constant
    const result = (state.a | magic) & operand;
    return .{
        .a = result,
        .x = result,
        .flags = state.p.setZN(result),
    };
}

// ============================================================================
// JAM/KIL - CPU Halt Instructions
// ============================================================================

/// JAM/KIL - Halt the CPU
/// CPU enters infinite loop, only RESET recovers
/// Flags: None
///
/// There are 12 JAM opcodes: $02, $12, $22, $32, $42, $52, $62, $72,
///                           $92, $B2, $D2, $F2
pub fn jam(_: CpuState, _: u8) OpcodeResult {
    return .{
        .halt = true,
    };
}

// ============================================================================
// Read-Modify-Write Combo Instructions
// ============================================================================
//
// These are complex unofficial opcodes that combine a memory modification
// with an accumulator operation.
//
// Pattern: Read value → Modify it → Write back → Update A and flags

/// SLO - Shift Left + OR (ASL + ORA)
/// M = M << 1, A |= M
/// Flags: C (from shift), N, Z
///
/// Memory modification: value << 1
/// CPU update: A |= modified_value
pub fn slo(state: CpuState, operand: u8) OpcodeResult {
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
///
/// Memory modification: (value << 1) | carry_in
/// CPU update: A &= modified_value
pub fn rla(state: CpuState, operand: u8) OpcodeResult {
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
///
/// Memory modification: value >> 1
/// CPU update: A ^= modified_value
pub fn sre(state: CpuState, operand: u8) OpcodeResult {
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
///
/// Memory modification: (value >> 1) | (carry_in << 7)
/// CPU update: A = A + modified_value + carry_from_rotate
///
/// CRITICAL: The rotate sets a NEW carry, which is then used by ADC.
pub fn rra(state: CpuState, operand: u8) OpcodeResult {
    // Rotate right through carry
    const carry_from_rotate = (operand & 0x01) != 0;
    const rotated = (operand >> 1) | (if (state.p.carry) @as(u8, 0x80) else 0);

    // ADC with the NEW carry from rotate
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
///
/// Memory modification: value - 1
/// CPU update: Compare A with modified_value
pub fn dcp(state: CpuState, operand: u8) OpcodeResult {
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
///
/// Memory modification: value + 1
/// CPU update: A = A - modified_value - (1 - carry)
pub fn isc(state: CpuState, operand: u8) OpcodeResult {
    const incremented = operand +% 1;

    // SBC: A - M - (1 - C) = A + (~M) + C
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
