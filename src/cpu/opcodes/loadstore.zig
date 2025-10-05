//! Load and Store Instructions
//!
//! This module implements the 6502 load and store instructions as pure functions.
//! Load operations update a register and set Z/N flags.
//! Store operations return a bus_write descriptor (no register changes).
//!
//! Instructions:
//! - LDA: Load Accumulator
//! - LDX: Load X Register
//! - LDY: Load Y Register
//! - STA: Store Accumulator
//! - STX: Store X Register
//! - STY: Store Y Register
//!
//! Pure functional API - see mod.zig for architecture details.

const StateModule = @import("../State.zig");

pub const CpuState = StateModule.PureCpuState;
pub const StatusFlags = StateModule.StatusFlags;
pub const OpcodeResult = StateModule.OpcodeResult;

// ============================================================================
// Load Instructions (Update register + N, Z flags)
// ============================================================================

/// LDA - Load Accumulator (REFERENCE IMPLEMENTATION - OpcodeResult Pattern)
/// A = operand
/// Flags: N, Z
///
/// This is a reference implementation demonstrating the OpcodeResult pattern.
/// Pure function returns delta describing state changes.
/// Execution engine applies delta via applyOpcodeResult().
pub fn lda(state: CpuState, operand: u8) OpcodeResult {
    return .{
        .a = operand,
        .flags = state.p.setZN(operand),
    };
}

/// LDX - Load X Register
/// X = operand
/// Flags: N, Z
pub fn ldx(state: CpuState, operand: u8) OpcodeResult {
    return .{
        .x = operand,
        .flags = state.p.setZN(operand),
    };
}

/// LDY - Load Y Register
/// Y = operand
/// Flags: N, Z
pub fn ldy(state: CpuState, operand: u8) OpcodeResult {
    return .{
        .y = operand,
        .flags = state.p.setZN(operand),
    };
}

// ============================================================================
// Store Instructions (No CPU state change - bus write handled by engine)
// ============================================================================

/// STA - Store Accumulator
/// M = A (no CPU state change)
/// Flags: None
pub fn sta(state: CpuState, _: u8) OpcodeResult {
    return .{
        .bus_write = .{
            .address = state.effective_address,
            .value = state.a,
        },
    };
}

/// STX - Store X Register
/// M = X (no CPU state change)
/// Flags: None
pub fn stx(state: CpuState, _: u8) OpcodeResult {
    return .{
        .bus_write = .{
            .address = state.effective_address,
            .value = state.x,
        },
    };
}

/// STY - Store Y Register
/// M = Y (no CPU state change)
/// Flags: None
pub fn sty(state: CpuState, _: u8) OpcodeResult {
    return .{
        .bus_write = .{
            .address = state.effective_address,
            .value = state.y,
        },
    };
}
