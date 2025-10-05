//! Register Transfer Instructions
//!
//! Instructions that copy values between registers.
//!
//! Instructions:
//! - TAX, TAY: Transfer A to X/Y (sets Z/N flags)
//! - TXA, TYA: Transfer X/Y to A (sets Z/N flags)
//! - TSX: Transfer SP to X (sets Z/N flags)
//! - TXS: Transfer X to SP (no flags affected)
//!
//! All transfers except TXS update Z and N flags based on transferred value.

const StateModule = @import("../State.zig");

pub const CpuState = StateModule.PureCpuState;
pub const StatusFlags = StateModule.StatusFlags;
pub const OpcodeResult = StateModule.OpcodeResult;

/// TAX - Transfer Accumulator to X
/// X = A
/// Flags: N, Z
pub fn tax(state: CpuState, _: u8) OpcodeResult {
    return .{
        .x = state.a,
        .flags = state.p.setZN(state.a),
    };
}

/// TAY - Transfer Accumulator to Y
/// Y = A
/// Flags: N, Z
pub fn tay(state: CpuState, _: u8) OpcodeResult {
    return .{
        .y = state.a,
        .flags = state.p.setZN(state.a),
    };
}

/// TXA - Transfer X to Accumulator
/// A = X
/// Flags: N, Z
pub fn txa(state: CpuState, _: u8) OpcodeResult {
    return .{
        .a = state.x,
        .flags = state.p.setZN(state.x),
    };
}

/// TYA - Transfer Y to Accumulator
/// A = Y
/// Flags: N, Z
pub fn tya(state: CpuState, _: u8) OpcodeResult {
    return .{
        .a = state.y,
        .flags = state.p.setZN(state.y),
    };
}

/// TSX - Transfer Stack Pointer to X
/// X = SP
/// Flags: N, Z
pub fn tsx(state: CpuState, _: u8) OpcodeResult {
    return .{
        .x = state.sp,
        .flags = state.p.setZN(state.sp),
    };
}

/// TXS - Transfer X to Stack Pointer
/// SP = X
/// Flags: None (unique among transfer instructions)
pub fn txs(state: CpuState, _: u8) OpcodeResult {
    return .{
        .sp = state.x,
    };
}
