//! Branch Instructions
//!
//! Conditional branch instructions based on processor status flags.
//!
//! Instructions:
//! - BCC: Branch if Carry Clear (C = 0)
//! - BCS: Branch if Carry Set (C = 1)
//! - BEQ: Branch if Equal (Z = 1)
//! - BNE: Branch if Not Equal (Z = 0)
//! - BMI: Branch if Minus (N = 1)
//! - BPL: Branch if Plus (N = 0)
//! - BVC: Branch if Overflow Clear (V = 0)
//! - BVS: Branch if Overflow Set (V = 1)
//!
//! All branches use signed 8-bit offsets relative to PC.
//! Taken branches return .pc with the new address.
//! Not-taken branches return empty OpcodeResult.

const StateModule = @import("../State.zig");

pub const CpuState = StateModule.PureCpuState;
pub const StatusFlags = StateModule.StatusFlags;
pub const OpcodeResult = StateModule.OpcodeResult;

/// BCC - Branch if Carry Clear
/// Branch if C = 0
pub fn bcc(state: CpuState, offset: u8) OpcodeResult {
    if (state.p.carry) {
        return .{}; // Not taken (2 cycles)
    }
    return branchTaken(state.pc, offset);
}

/// BCS - Branch if Carry Set
/// Branch if C = 1
pub fn bcs(state: CpuState, offset: u8) OpcodeResult {
    if (!state.p.carry) {
        return .{}; // Not taken
    }
    return branchTaken(state.pc, offset);
}

/// BEQ - Branch if Equal
/// Branch if Z = 1
pub fn beq(state: CpuState, offset: u8) OpcodeResult {
    if (!state.p.zero) {
        return .{}; // Not taken
    }
    return branchTaken(state.pc, offset);
}

/// BNE - Branch if Not Equal
/// Branch if Z = 0
pub fn bne(state: CpuState, offset: u8) OpcodeResult {
    if (state.p.zero) {
        return .{}; // Not taken
    }
    return branchTaken(state.pc, offset);
}

/// BMI - Branch if Minus
/// Branch if N = 1
pub fn bmi(state: CpuState, offset: u8) OpcodeResult {
    if (!state.p.negative) {
        return .{}; // Not taken
    }
    return branchTaken(state.pc, offset);
}

/// BPL - Branch if Plus
/// Branch if N = 0
pub fn bpl(state: CpuState, offset: u8) OpcodeResult {
    if (state.p.negative) {
        return .{}; // Not taken
    }
    return branchTaken(state.pc, offset);
}

/// BVC - Branch if Overflow Clear
/// Branch if V = 0
pub fn bvc(state: CpuState, offset: u8) OpcodeResult {
    if (state.p.overflow) {
        return .{}; // Not taken
    }
    return branchTaken(state.pc, offset);
}

/// BVS - Branch if Overflow Set
/// Branch if V = 1
pub fn bvs(state: CpuState, offset: u8) OpcodeResult {
    if (!state.p.overflow) {
        return .{}; // Not taken
    }
    return branchTaken(state.pc, offset);
}

/// Helper: Calculate new PC for taken branch
/// Private helper used by all branch instructions
fn branchTaken(pc: u16, offset: u8) OpcodeResult {
    const signed_offset = @as(i8, @bitCast(offset));
    const new_pc = @as(u16, @bitCast(@as(i16, @bitCast(pc)) +% signed_offset));
    return .{
        .pc = new_pc,
    };
}
