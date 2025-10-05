//! Comparison and Bit Test Instructions
//!
//! Instructions that compare registers or test bits without storing results.
//!
//! Instructions:
//! - CMP: Compare Accumulator with memory
//! - CPX: Compare X Register with memory
//! - CPY: Compare Y Register with memory
//! - BIT: Test Bits (Z = A & M, copy bits 6/7 to V/N)
//!
//! Comparison sets C if register >= memory, Z if equal, N based on subtraction result.
//! BIT is unique: copies memory bits 6 and 7 to V and N flags.

const StateModule = @import("../State.zig");

pub const CpuState = StateModule.PureCpuState;
pub const StatusFlags = StateModule.StatusFlags;
pub const OpcodeResult = StateModule.OpcodeResult;

/// CMP - Compare Accumulator
/// A - operand (result discarded, only flags set)
/// Flags: N, Z, C
pub fn cmp(state: CpuState, operand: u8) OpcodeResult {
    const result = state.a -% operand;
    return .{
        .flags = StatusFlags{
            .carry = state.a >= operand,
            .zero = state.a == operand,
            .interrupt = state.p.interrupt,
            .decimal = state.p.decimal,
            .break_flag = state.p.break_flag,
            .unused = true,
            .overflow = state.p.overflow,
            .negative = (result & 0x80) != 0,
        },
    };
}

/// CPX - Compare X Register
/// X - operand
/// Flags: N, Z, C
pub fn cpx(state: CpuState, operand: u8) OpcodeResult {
    const result = state.x -% operand;
    return .{
        .flags = StatusFlags{
            .carry = state.x >= operand,
            .zero = state.x == operand,
            .interrupt = state.p.interrupt,
            .decimal = state.p.decimal,
            .break_flag = state.p.break_flag,
            .unused = true,
            .overflow = state.p.overflow,
            .negative = (result & 0x80) != 0,
        },
    };
}

/// CPY - Compare Y Register
/// Y - operand
/// Flags: N, Z, C
pub fn cpy(state: CpuState, operand: u8) OpcodeResult {
    const result = state.y -% operand;
    return .{
        .flags = StatusFlags{
            .carry = state.y >= operand,
            .zero = state.y == operand,
            .interrupt = state.p.interrupt,
            .decimal = state.p.decimal,
            .break_flag = state.p.break_flag,
            .unused = true,
            .overflow = state.p.overflow,
            .negative = (result & 0x80) != 0,
        },
    };
}

/// BIT - Bit Test
/// Z = (A & M == 0), V = M[6], N = M[7]
/// Flags: Z, V, N
///
/// Special behavior: Copies bits 6 and 7 from memory to V and N flags.
/// Zero flag set if A & M == 0.
pub fn bit(state: CpuState, operand: u8) OpcodeResult {
    const result = state.a & operand;
    return .{
        .flags = StatusFlags{
            .carry = state.p.carry,
            .zero = (result == 0),
            .interrupt = state.p.interrupt,
            .decimal = state.p.decimal,
            .break_flag = state.p.break_flag,
            .unused = true,
            .overflow = (operand & 0x40) != 0, // Copy bit 6
            .negative = (operand & 0x80) != 0, // Copy bit 7
        },
    };
}
