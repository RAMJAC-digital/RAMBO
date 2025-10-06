//! Arithmetic Instructions
//!
//! Binary arithmetic operations with carry and overflow handling.
//!
//! Instructions:
//! - ADC: Add with Carry
//! - SBC: Subtract with Carry
//!
//! Both operations update A, N, Z, C, and V flags.
//! Overflow is calculated using signed arithmetic rules.
//! NES CPU ignores decimal mode (unlike other 6502 variants).

const StateModule = @import("../State.zig");

pub const CpuState = StateModule.CpuCoreState;
pub const StatusFlags = StateModule.StatusFlags;
pub const OpcodeResult = StateModule.OpcodeResult;

/// ADC - Add with Carry
/// A = A + operand + C
/// Flags: N, Z, C, V
pub fn adc(state: CpuState, operand: u8) OpcodeResult {
    const a = @as(u16, state.a);
    const m = @as(u16, operand);
    const c: u16 = if (state.p.carry) 1 else 0;

    const result16 = a + m + c;
    const result = @as(u8, @truncate(result16));

    // Overflow: (A and M have same sign) AND (result has different sign)
    const overflow = ((state.a ^ result) & (operand ^ result) & 0x80) != 0;

    return .{
        .a = result,
        .flags = state.p
            .setZN(result)
            .setCarry(result16 > 0xFF)
            .setOverflow(overflow),
    };
}

/// SBC - Subtract with Carry
/// A = A - operand - (1 - C)
/// Flags: N, Z, C, V
pub fn sbc(state: CpuState, operand: u8) OpcodeResult {
    // Implemented as A + ~M + C, which is how the 6502 hardware works.
    // This correctly handles the borrow flag (carry = no borrow).
    const inverted_operand = ~operand;
    const a = @as(u16, state.a);
    const m = @as(u16, inverted_operand);
    const c: u16 = if (state.p.carry) 1 else 0;

    const result16 = a + m + c;
    const result = @as(u8, @truncate(result16));

    // Overflow: (A and ~M have same sign) AND (result has different sign)
    const overflow = ((state.a ^ result) & (inverted_operand ^ result) & 0x80) != 0;

    return .{
        .a = result,
        .flags = state.p
            .setZN(result)
            .setCarry(result16 > 0xFF) // Carry is set if no borrow was needed
            .setOverflow(overflow),
    };
}
