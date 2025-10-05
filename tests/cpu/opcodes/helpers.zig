//! Test Helpers for Pure Functional Opcode Tests
//!
//! This module provides utilities for testing CPU opcodes using the pure functional API.
//! All helpers work with PureCpuState and OpcodeResult, not mutable state.

const std = @import("std");
const testing = std.testing;

// Import from RAMBO module
const RAMBO = @import("RAMBO");
const StateModule = RAMBO.Cpu.State;

// Re-export types for convenience
pub const PureCpuState = StateModule.PureCpuState;
pub const OpcodeResult = StateModule.OpcodeResult;
pub const StatusFlags = StateModule.StatusFlags;

// ============================================================================
// State Builders
// ============================================================================

/// Create a minimal CPU state for testing
/// Most tests only care about A, flags, and operand
pub fn makeState(a: u8, x: u8, y: u8, flags: StatusFlags) PureCpuState {
    return .{
        .a = a,
        .x = x,
        .y = y,
        .sp = 0xFD, // Standard initial SP
        .pc = 0,
        .p = flags,
        .effective_address = 0,
    };
}

/// Create a state with specific effective_address (for stores/RMW)
pub fn makeStateWithAddress(a: u8, x: u8, y: u8, flags: StatusFlags, address: u16) PureCpuState {
    return .{
        .a = a,
        .x = x,
        .y = y,
        .sp = 0xFD,
        .pc = 0,
        .p = flags,
        .effective_address = address,
    };
}

// ============================================================================
// Flag Builders
// ============================================================================

/// Create flags with all explicit settings
pub fn makeFlags(z: bool, n: bool, c: bool, v: bool) StatusFlags {
    return .{
        .zero = z,
        .negative = n,
        .carry = c,
        .overflow = v,
        .interrupt = false,
        .decimal = false,
        .break_flag = false,
        .unused = true,
    };
}

/// Create flags with everything false (common initial state)
pub fn clearFlags() StatusFlags {
    return makeFlags(false, false, false, false);
}

/// Create flags with only carry set (common for ADC/SBC tests)
pub fn flagsWithCarry() StatusFlags {
    return makeFlags(false, false, true, false);
}

// ============================================================================
// Result Verifiers
// ============================================================================

/// Verify a register changed to expected value
/// Fails if register is null (unchanged) or has wrong value
pub fn expectRegister(result: OpcodeResult, comptime field: []const u8, expected: u8) !void {
    const value = @field(result, field);
    if (value == null) {
        std.debug.print("Expected register '{s}' to change, but it was null (unchanged)\n", .{field});
        return error.TestExpectedEqual;
    }
    try testing.expectEqual(expected, value.?);
}

/// Verify a register did NOT change (is null)
pub fn expectRegisterUnchanged(result: OpcodeResult, comptime field: []const u8) !void {
    const value = @field(result, field);
    if (value != null) {
        std.debug.print("Expected register '{s}' to be unchanged, but it was set to {}\n", .{ field, value.? });
        return error.TestUnexpectedValue;
    }
}

/// Verify flags match expected values
/// Fails if flags are null or any flag doesn't match
pub fn expectFlags(result: OpcodeResult, expected: StatusFlags) !void {
    if (result.flags == null) {
        std.debug.print("Expected flags to be set, but they were null (unchanged)\n", .{});
        return error.TestExpectedEqual;
    }

    const flags = result.flags.?;

    // Check each flag individually for better error messages
    if (flags.zero != expected.zero) {
        std.debug.print("Zero flag mismatch: expected {}, got {}\n", .{ expected.zero, flags.zero });
        return error.TestExpectedEqual;
    }
    if (flags.negative != expected.negative) {
        std.debug.print("Negative flag mismatch: expected {}, got {}\n", .{ expected.negative, flags.negative });
        return error.TestExpectedEqual;
    }
    if (flags.carry != expected.carry) {
        std.debug.print("Carry flag mismatch: expected {}, got {}\n", .{ expected.carry, flags.carry });
        return error.TestExpectedEqual;
    }
    if (flags.overflow != expected.overflow) {
        std.debug.print("Overflow flag mismatch: expected {}, got {}\n", .{ expected.overflow, flags.overflow });
        return error.TestExpectedEqual;
    }
}

/// Verify only N and Z flags (common for load/store/transfer)
/// Carry and overflow should be unchanged (null or preserved)
pub fn expectZN(result: OpcodeResult, zero: bool, negative: bool) !void {
    if (result.flags == null) {
        std.debug.print("Expected flags to be set, but they were null\n", .{});
        return error.TestExpectedEqual;
    }

    const flags = result.flags.?;
    if (flags.zero != zero) {
        std.debug.print("Zero flag mismatch: expected {}, got {}\n", .{ zero, flags.zero });
        return error.TestExpectedEqual;
    }
    if (flags.negative != negative) {
        std.debug.print("Negative flag mismatch: expected {}, got {}\n", .{ negative, flags.negative });
        return error.TestExpectedEqual;
    }
}

/// Verify bus write occurred with expected address and value
pub fn expectBusWrite(result: OpcodeResult, address: u16, value: u8) !void {
    if (result.bus_write == null) {
        std.debug.print("Expected bus write, but bus_write was null\n", .{});
        return error.TestExpectedEqual;
    }

    const write = result.bus_write.?;
    try testing.expectEqual(address, write.address);
    try testing.expectEqual(value, write.value);
}

/// Verify no bus write occurred
pub fn expectNoBusWrite(result: OpcodeResult) !void {
    if (result.bus_write != null) {
        const write = result.bus_write.?;
        std.debug.print("Expected no bus write, but got write to ${X:0>4} = ${X:0>2}\n", .{ write.address, write.value });
        return error.TestUnexpectedValue;
    }
}

/// Verify push operation with expected value
pub fn expectPush(result: OpcodeResult, value: u8) !void {
    if (result.push == null) {
        std.debug.print("Expected push, but push was null\n", .{});
        return error.TestExpectedEqual;
    }
    try testing.expectEqual(value, result.push.?);
}

/// Verify pull operation occurred
pub fn expectPull(result: OpcodeResult) !void {
    try testing.expect(result.pull);
}

// ============================================================================
// Common Test Patterns
// ============================================================================

/// Test pattern: Load instruction (LDA, LDX, LDY)
/// Expects: Register set to operand, Z and N flags updated
pub fn testLoad(
    opcodeFn: anytype,
    state: PureCpuState,
    operand: u8,
    comptime register: []const u8,
    expected_z: bool,
    expected_n: bool,
) !void {
    const result = opcodeFn(state, operand);

    try expectRegister(result, register, operand);
    try expectZN(result, expected_z, expected_n);
    try expectNoBusWrite(result);
}

/// Test pattern: Store instruction (STA, STX, STY)
/// Expects: Bus write to effective_address, no flag changes
pub fn testStore(
    opcodeFn: anytype,
    state: PureCpuState,
    operand: u8,
    expected_value: u8,
) !void {
    const result = opcodeFn(state, operand);

    try expectBusWrite(result, state.effective_address, expected_value);
    if (result.flags != null) {
        std.debug.print("Store instruction should not change flags\n", .{});
        return error.TestUnexpectedValue;
    }
}
