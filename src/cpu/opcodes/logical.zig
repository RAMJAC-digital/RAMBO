//! Logical Instructions
//!
//! Bitwise logical operations on the accumulator.
//!
//! Instructions:
//! - AND: Bitwise AND (A = A & operand)
//! - OR: Bitwise OR (A = A | operand)
//! - EOR: Bitwise XOR (A = A ^ operand)
//!
//! All operations update A and set Z/N flags.

const StateModule = @import("../State.zig");

pub const CpuState = StateModule.PureCpuState;
pub const StatusFlags = StateModule.StatusFlags;
pub const OpcodeResult = StateModule.OpcodeResult;

/// AND - Logical AND
/// A = A & operand
/// Flags: N, Z
pub fn logicalAnd(state: CpuState, operand: u8) OpcodeResult {
    const result = state.a & operand;
    return .{
        .a = result,
        .flags = state.p.setZN(result),
    };
}

/// ORA - Logical OR
/// A = A | operand
/// Flags: N, Z
pub fn logicalOr(state: CpuState, operand: u8) OpcodeResult {
    const result = state.a | operand;
    return .{
        .a = result,
        .flags = state.p.setZN(result),
    };
}

/// EOR - Logical XOR
/// A = A ^ operand
/// Flags: N, Z
pub fn logicalXor(state: CpuState, operand: u8) OpcodeResult {
    const result = state.a ^ operand;
    return .{
        .a = result,
        .flags = state.p.setZN(result),
    };
}
