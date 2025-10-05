//! Stack Push/Pull Instructions
//!
//! Instructions for stack operations.
//!
//! Instructions:
//! - PHA, PHP: Push Accumulator/Processor status to stack
//! - PLA, PLP: Pull from stack to Accumulator/Processor status
//!
//! Push operations return .push descriptor (execution engine handles SP decrement).
//! Pull operations receive value from temp_value (execution engine handles SP increment).

const StateModule = @import("../State.zig");

pub const CpuState = StateModule.PureCpuState;
pub const StatusFlags = StateModule.StatusFlags;
pub const OpcodeResult = StateModule.OpcodeResult;

/// PHA - Push Accumulator
/// Push A onto stack
/// Flags: None
pub fn pha(state: CpuState, _: u8) OpcodeResult {
    return .{
        .push = state.a,
    };
}

/// PHP - Push Processor Status
/// Push P onto stack (with B flag set)
/// Flags: None
pub fn php(state: CpuState, _: u8) OpcodeResult {
    // Push P with B flag set (hardware behavior)
    const status_byte = state.p.toByte() | 0x30; // Set B and unused flags
    return .{
        .push = status_byte,
    };
}

/// PLA - Pull Accumulator
/// Pull from stack to A
/// Flags: N, Z
///
/// Note: operand contains pulled value (from execution engine)
pub fn pla(_: CpuState, operand: u8) OpcodeResult {
    // operand is the value pulled from stack (via temp_value)
    const flags = StatusFlags{};
    return .{
        .a = operand,
        .flags = flags.setZN(operand),
    };
}

/// PLP - Pull Processor Status
/// Pull from stack to P
/// Flags: All (entire P register replaced)
///
/// Note: operand contains pulled value (from execution engine)
pub fn plp(_: CpuState, operand: u8) OpcodeResult {
    // operand is the value pulled from stack (via temp_value)
    // Restore all flags from pulled byte (B flag is ignored on pull)
    return .{
        .flags = StatusFlags.fromByte(operand),
    };
}
