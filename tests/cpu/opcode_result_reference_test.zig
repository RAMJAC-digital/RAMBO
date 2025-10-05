//! Reference Implementation Test - OpcodeResult Pattern
//!
//! This file demonstrates the complete pure functional opcode pattern:
//! 1. Pure opcode function returns OpcodeResult (delta)
//! 2. applyOpcodeResult() applies delta to CPU state
//! 3. No bus mocking required for testing pure functions
//!
//! This proves the pattern works before migrating all opcodes.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Opcodes = @import("../../src/cpu/opcodes.zig");
const StateModule = @import("../../src/cpu/State.zig");
const Logic = @import("../../src/cpu/Logic.zig");

const CpuState = StateModule.PureCpuState;
const OpcodeResult = StateModule.OpcodeResult;
const StatusFlags = StateModule.StatusFlags;
const BusState = RAMBO.BusState;

// ============================================================================
// Pure Function Tests (No Bus Required)
// ============================================================================

test "OpcodeResult Pattern: LDA pure function" {
    const cpu_state = CpuState{
        .a = 0x00,
        .x = 0x11,
        .y = 0x22,
        .sp = 0xFD,
        .pc = 0x8000,
        .p = .{},
    };

    // Call pure function
    const result = Opcodes.lda(cpu_state, 0x42);

    // Verify delta contains only what changed
    try testing.expectEqual(@as(?u8, 0x42), result.a);
    try testing.expect(result.x == null); // Unchanged
    try testing.expect(result.y == null); // Unchanged
    try testing.expect(result.sp == null); // Unchanged
    try testing.expect(result.pc == null); // Unchanged
    try testing.expect(result.flags != null); // Flags updated

    // Verify flags are correct
    const flags = result.flags.?;
    try testing.expect(!flags.zero);
    try testing.expect(!flags.negative);
}

test "OpcodeResult Pattern: LDA with zero value" {
    const cpu_state = CpuState.init();
    const result = Opcodes.lda(cpu_state, 0x00);

    try testing.expectEqual(@as(?u8, 0x00), result.a);
    try testing.expect(result.flags.?.zero);
    try testing.expect(!result.flags.?.negative);
}

test "OpcodeResult Pattern: LDA with negative value" {
    const cpu_state = CpuState.init();
    const result = Opcodes.lda(cpu_state, 0x80);

    try testing.expectEqual(@as(?u8, 0x80), result.a);
    try testing.expect(!result.flags.?.zero);
    try testing.expect(result.flags.?.negative);
}

// ============================================================================
// Integration Tests (Pure Function + applyOpcodeResult)
// ============================================================================

test "Integration: LDA applied to CPU state" {
    var cpu_state = CpuState{
        .a = 0xFF,
        .x = 0x11,
        .y = 0x22,
        .sp = 0xFD,
        .pc = 0x8000,
        .p = .{ .carry = true },
    };

    var bus = BusState.init(testing.allocator);
    defer bus.deinit();

    // Execute pure function
    const result = Opcodes.lda(cpu_state, 0x42);

    // Apply result
    Logic.applyOpcodeResult(&cpu_state, &bus, result);

    // Verify CPU state updated correctly
    try testing.expectEqual(@as(u8, 0x42), cpu_state.a);
    try testing.expectEqual(@as(u8, 0x11), cpu_state.x); // Unchanged
    try testing.expectEqual(@as(u8, 0x22), cpu_state.y); // Unchanged
    try testing.expectEqual(@as(u8, 0xFD), cpu_state.sp); // Unchanged
    try testing.expectEqual(@as(u16, 0x8000), cpu_state.pc); // Unchanged

    // Verify flags
    try testing.expect(!cpu_state.p.zero);
    try testing.expect(!cpu_state.p.negative);
    try testing.expect(cpu_state.p.carry); // Carry preserved (not changed by LDA)
}

test "Integration: LDA preserves unrelated flags" {
    var cpu_state = CpuState{
        .a = 0x00,
        .p = .{
            .carry = true,
            .interrupt = true,
            .decimal = true,
            .overflow = true,
        },
    };

    var bus = BusState.init(testing.allocator);
    defer bus.deinit();

    const result = Opcodes.lda(cpu_state, 0x00);
    Logic.applyOpcodeResult(&cpu_state, &bus, result);

    // LDA only updates N and Z flags
    try testing.expect(cpu_state.p.zero); // Updated
    try testing.expect(!cpu_state.p.negative); // Updated
    try testing.expect(cpu_state.p.carry); // Preserved
    try testing.expect(cpu_state.p.interrupt); // Preserved
    try testing.expect(cpu_state.p.decimal); // Preserved
    try testing.expect(cpu_state.p.overflow); // Preserved
}

// ============================================================================
// Property-Based Tests
// ============================================================================

test "Property: LDA correctness for all byte values" {
    var bus = BusState.init(testing.allocator);
    defer bus.deinit();

    var value: u8 = 0;
    while (true) {
        var cpu_state = CpuState.init();

        const result = Opcodes.lda(cpu_state, value);
        Logic.applyOpcodeResult(&cpu_state, &bus, result);

        // Verify accumulator matches input
        try testing.expectEqual(value, cpu_state.a);

        // Verify flags
        if (value == 0) {
            try testing.expect(cpu_state.p.zero);
        } else {
            try testing.expect(!cpu_state.p.zero);
        }

        if ((value & 0x80) != 0) {
            try testing.expect(cpu_state.p.negative);
        } else {
            try testing.expect(!cpu_state.p.negative);
        }

        if (value == 255) break;
        value += 1;
    }
}

// ============================================================================
// Benefits Demonstration
// ============================================================================

test "Benefit: Pure function testable without bus" {
    // No BusState needed!
    const cpu_state = CpuState.init();

    // Test opcode logic in complete isolation
    const result = Opcodes.lda(cpu_state, 0x42);

    // Verify behavior without any system dependencies
    try testing.expectEqual(@as(?u8, 0x42), result.a);
    try testing.expect(result.flags.?.negative == false);
}

test "Benefit: Composable transformations" {
    const cpu_state = CpuState.init();

    // Chain operations conceptually (not yet integrated with dispatch)
    const r1 = Opcodes.lda(cpu_state, 0xFF);
    // Could apply r1, then do next operation, etc.

    // For now, just verify first operation
    try testing.expectEqual(@as(?u8, 0xFF), r1.a);
}
