//! Control Flow Instructions
//!
//! Unconditional control flow operations.
//!
//! Instructions:
//! - JMP: Jump to address (absolute or indirect)
//! - NOP: No operation
//!
//! JMP uses the effective_address set by addressing microsteps.
//! NOP returns an empty OpcodeResult (no state changes).

const StateModule = @import("../State.zig");

pub const CpuState = StateModule.PureCpuState;
pub const StatusFlags = StateModule.StatusFlags;
pub const OpcodeResult = StateModule.OpcodeResult;

/// JMP - Jump to Address
/// Supports both absolute and indirect addressing
/// For absolute: effective_address is set by fetchAbsLow/High
/// For indirect: effective_address is set by jmpIndirectFetchHigh (after reading through pointer)
pub fn jmp(state: CpuState, _: u8) OpcodeResult {
    return .{
        .pc = state.effective_address,
    };
}

/// NOP - No Operation
pub fn nop(_: CpuState, _: u8) OpcodeResult {
    return .{}; // No changes to CPU state
}
