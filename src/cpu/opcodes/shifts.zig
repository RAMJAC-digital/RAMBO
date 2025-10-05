//! Shift and Rotate Instructions
//!
//! Instructions for shifting and rotating bits with carry flag interaction.
//!
//! Instructions:
//! - ASL: Arithmetic Shift Left (accumulator and memory variants)
//! - LSR: Logical Shift Right (accumulator and memory variants)
//! - ROL: Rotate Left (accumulator and memory variants)
//! - ROR: Rotate Right (accumulator and memory variants)
//!
//! All shifts/rotates affect the carry flag and Z/N flags.
//! Accumulator variants modify register A.
//! Memory variants are RMW operations using effective_address.

const StateModule = @import("../State.zig");

pub const CpuState = StateModule.PureCpuState;
pub const StatusFlags = StateModule.StatusFlags;
pub const OpcodeResult = StateModule.OpcodeResult;

/// ASL - Arithmetic Shift Left (Accumulator)
/// A = A << 1
/// Flags: N, Z, C
pub fn aslAcc(state: CpuState, _: u8) OpcodeResult {
    const result = state.a << 1;
    return .{
        .a = result,
        .flags = state.p
            .setCarry((state.a & 0x80) != 0)
            .setZN(result),
    };
}

/// ASL - Arithmetic Shift Left (Memory)
/// M = M << 1 (RMW operation)
/// Flags: N, Z, C
pub fn aslMem(state: CpuState, operand: u8) OpcodeResult {
    const result = operand << 1;
    return .{
        .bus_write = .{
            .address = state.effective_address,
            .value = result,
        },
        .flags = state.p
            .setCarry((operand & 0x80) != 0)
            .setZN(result),
    };
}

/// LSR - Logical Shift Right (Accumulator)
/// A = A >> 1
/// Flags: N(0), Z, C
pub fn lsrAcc(state: CpuState, _: u8) OpcodeResult {
    const result = state.a >> 1;
    return .{
        .a = result,
        .flags = state.p
            .setCarry((state.a & 0x01) != 0)
            .setZN(result),
    };
}

/// LSR - Logical Shift Right (Memory)
/// M = M >> 1 (RMW operation)
/// Flags: N(0), Z, C
pub fn lsrMem(state: CpuState, operand: u8) OpcodeResult {
    const result = operand >> 1;
    return .{
        .bus_write = .{
            .address = state.effective_address,
            .value = result,
        },
        .flags = state.p
            .setCarry((operand & 0x01) != 0)
            .setZN(result),
    };
}

/// ROL - Rotate Left (Accumulator)
/// A = (A << 1) | C
/// Flags: N, Z, C
pub fn rolAcc(state: CpuState, _: u8) OpcodeResult {
    const carry_in: u8 = if (state.p.carry) 1 else 0;
    const result = (state.a << 1) | carry_in;
    return .{
        .a = result,
        .flags = state.p
            .setCarry((state.a & 0x80) != 0)
            .setZN(result),
    };
}

/// ROL - Rotate Left (Memory)
/// M = (M << 1) | C (RMW operation)
/// Flags: N, Z, C
pub fn rolMem(state: CpuState, operand: u8) OpcodeResult {
    const carry_in: u8 = if (state.p.carry) 1 else 0;
    const result = (operand << 1) | carry_in;
    return .{
        .bus_write = .{
            .address = state.effective_address,
            .value = result,
        },
        .flags = state.p
            .setCarry((operand & 0x80) != 0)
            .setZN(result),
    };
}

/// ROR - Rotate Right (Accumulator)
/// A = (A >> 1) | (C << 7)
/// Flags: N, Z, C
pub fn rorAcc(state: CpuState, _: u8) OpcodeResult {
    const carry_in: u8 = if (state.p.carry) 0x80 else 0;
    const result = (state.a >> 1) | carry_in;
    return .{
        .a = result,
        .flags = state.p
            .setCarry((state.a & 0x01) != 0)
            .setZN(result),
    };
}

/// ROR - Rotate Right (Memory)
/// M = (M >> 1) | (C << 7) (RMW operation)
/// Flags: N, Z, C
pub fn rorMem(state: CpuState, operand: u8) OpcodeResult {
    const carry_in: u8 = if (state.p.carry) 0x80 else 0;
    const result = (operand >> 1) | carry_in;
    return .{
        .bus_write = .{
            .address = state.effective_address,
            .value = result,
        },
        .flags = state.p
            .setCarry((operand & 0x01) != 0)
            .setZN(result),
    };
}
