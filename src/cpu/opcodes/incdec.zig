//! Increment/Decrement Instructions
//!
//! Instructions for incrementing and decrementing memory and registers.
//!
//! Instructions:
//! - INC, DEC: Memory increment/decrement (RMW operations)
//! - INX, INY: Increment X/Y registers
//! - DEX, DEY: Decrement X/Y registers
//!
//! Memory operations use the effective_address from CpuState.
//! Register operations update the register directly.

const StateModule = @import("../State.zig");

pub const CpuState = StateModule.CpuCoreState;
pub const StatusFlags = StateModule.StatusFlags;
pub const OpcodeResult = StateModule.OpcodeResult;

/// INC - Increment Memory
/// M = M + 1 (RMW operation)
/// Flags: N, Z
pub fn inc(state: CpuState, operand: u8) OpcodeResult {
    const result = operand +% 1;
    return .{
        .bus_write = .{
            .address = state.effective_address,
            .value = result,
        },
        .flags = state.p.setZN(result),
    };
}

/// DEC - Decrement Memory
/// M = M - 1 (RMW operation)
/// Flags: N, Z
pub fn dec(state: CpuState, operand: u8) OpcodeResult {
    const result = operand -% 1;
    return .{
        .bus_write = .{
            .address = state.effective_address,
            .value = result,
        },
        .flags = state.p.setZN(result),
    };
}

/// INX - Increment X
/// Flags: N, Z
pub fn inx(state: CpuState, _: u8) OpcodeResult {
    const result = state.x +% 1;
    return .{
        .x = result,
        .flags = state.p.setZN(result),
    };
}

/// INY - Increment Y
/// Flags: N, Z
pub fn iny(state: CpuState, _: u8) OpcodeResult {
    const result = state.y +% 1;
    return .{
        .y = result,
        .flags = state.p.setZN(result),
    };
}

/// DEX - Decrement X
/// Flags: N, Z
pub fn dex(state: CpuState, _: u8) OpcodeResult {
    const result = state.x -% 1;
    return .{
        .x = result,
        .flags = state.p.setZN(result),
    };
}

/// DEY - Decrement Y
/// Flags: N, Z
pub fn dey(state: CpuState, _: u8) OpcodeResult {
    const result = state.y -% 1;
    return .{
        .y = result,
        .flags = state.p.setZN(result),
    };
}
