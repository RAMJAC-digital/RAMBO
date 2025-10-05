//! Flag Set/Clear Instructions
//!
//! Instructions that manipulate individual processor status flags.
//!
//! Instructions:
//! - CLC, SEC: Clear/Set Carry flag
//! - CLD, SED: Clear/Set Decimal mode (ignored on NES)
//! - CLI, SEI: Clear/Set Interrupt disable
//! - CLV: Clear Overflow flag (no SET equivalent)
//!
//! These are single-flag operations - only one flag changes per instruction.

const StateModule = @import("../State.zig");

pub const CpuState = StateModule.PureCpuState;
pub const StatusFlags = StateModule.StatusFlags;
pub const OpcodeResult = StateModule.OpcodeResult;

/// CLC - Clear Carry Flag
/// C = 0
pub fn clc(state: CpuState, _: u8) OpcodeResult {
    return .{
        .flags = state.p.setCarry(false),
    };
}

/// CLD - Clear Decimal Mode
/// D = 0
/// Note: NES CPU ignores decimal mode, but the flag still exists
pub fn cld(state: CpuState, _: u8) OpcodeResult {
    var flags = state.p;
    flags.decimal = false;
    return .{
        .flags = flags,
    };
}

/// CLI - Clear Interrupt Disable
/// I = 0
pub fn cli(state: CpuState, _: u8) OpcodeResult {
    var flags = state.p;
    flags.interrupt = false;
    return .{
        .flags = flags,
    };
}

/// CLV - Clear Overflow Flag
/// V = 0
pub fn clv(state: CpuState, _: u8) OpcodeResult {
    return .{
        .flags = state.p.setOverflow(false),
    };
}

/// SEC - Set Carry Flag
/// C = 1
pub fn sec(state: CpuState, _: u8) OpcodeResult {
    return .{
        .flags = state.p.setCarry(true),
    };
}

/// SED - Set Decimal Mode
/// D = 1
/// Note: NES CPU ignores decimal mode, but the flag still exists
pub fn sed(state: CpuState, _: u8) OpcodeResult {
    var flags = state.p;
    flags.decimal = true;
    return .{
        .flags = flags,
    };
}

/// SEI - Set Interrupt Disable
/// I = 1
pub fn sei(state: CpuState, _: u8) OpcodeResult {
    var flags = state.p;
    flags.interrupt = true;
    return .{
        .flags = flags,
    };
}
