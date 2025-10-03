//! Common helper functions for CPU instruction implementation
//!
//! This module provides reusable utilities that eliminate code duplication
//! across instruction implementations. All helpers are inline for zero-cost
//! abstraction.

const Cpu = @import("Cpu.zig");
const Bus = @import("../bus/Bus.zig").Bus;
const constants = @import("constants.zig");

const State = Cpu.State.State; // CPU State type, not module

// ============================================================================
// Memory Access Helpers
// ============================================================================

/// Read value handling page crossing for indexed addressing modes
///
/// This helper implements the 6502 hardware behavior for indexed reads:
/// - No page cross: Use temp_value from dummy read (4 cycles total)
/// - Page cross: Perform actual read from effective_address (5 cycles total)
///
/// Applies to: absolute,X / absolute,Y / indirect,Y
pub inline fn readWithPageCrossing(state: *State, bus: *Bus) u8 {
    if ((state.address_mode == .absolute_x or
        state.address_mode == .absolute_y or
        state.address_mode == .indirect_indexed) and
        state.page_crossed)
    {
        return bus.read(state.effective_address);
    }
    return state.temp_value;
}

/// Read operand value for all read instruction addressing modes
///
/// This is the canonical way to read operands in instruction implementations.
/// Handles immediate mode and all memory addressing modes correctly.
///
/// Usage:
/// ```zig
/// pub fn lda(state: *State, bus: *Bus) bool {
///     state.a = helpers.readOperand(state, bus);
///     state.p.updateZN(state.a);
///     return true;
/// }
/// ```
pub inline fn readOperand(state: *State, bus: *Bus) u8 {
    return switch (state.address_mode) {
        .immediate => blk: {
            // Immediate mode: fetch operand from PC (part of execute cycle)
            const value = bus.read(state.pc);
            state.pc +%= 1;
            break :blk value;
        },
        .zero_page => bus.read(@as(u16, state.operand_low)),
        .zero_page_x, .zero_page_y => bus.read(state.effective_address),
        .absolute => blk: {
            const addr = (@as(u16, state.operand_high) << 8) | state.operand_low;
            break :blk bus.read(addr);
        },
        .absolute_x, .absolute_y, .indirect_indexed => readWithPageCrossing(state, bus),
        .indexed_indirect => bus.read(state.effective_address),
        else => unreachable,
    };
}

/// Write value to memory for all write instruction addressing modes
///
/// This is the canonical way to write values in store instructions.
/// Handles all memory addressing modes (no immediate mode for writes).
///
/// Usage:
/// ```zig
/// pub fn sta(state: *State, bus: *Bus) bool {
///     helpers.writeOperand(state, bus, state.a);
///     return true;
/// }
/// ```
pub inline fn writeOperand(state: *State, bus: *Bus, value: u8) void {
    switch (state.address_mode) {
        .zero_page => bus.write(@as(u16, state.operand_low), value),
        .zero_page_x, .zero_page_y => bus.write(state.effective_address, value),
        .absolute => {
            const addr = (@as(u16, state.operand_high) << 8) | state.operand_low;
            bus.write(addr, value);
        },
        .absolute_x, .absolute_y => bus.write(state.effective_address, value),
        .indexed_indirect, .indirect_indexed => bus.write(state.effective_address, value),
        else => unreachable,
    }
}

// ============================================================================
// Address Calculation Helpers
// ============================================================================

/// Check if two addresses are on different pages
///
/// A page boundary is crossed when the high bytes differ.
/// This is used for cycle-accurate timing of indexed addressing modes.
pub inline fn pagesDiffer(addr1: u16, addr2: u16) bool {
    return (addr1 & constants.PAGE_MASK) != (addr2 & constants.PAGE_MASK);
}

/// Calculate absolute address from high and low bytes
pub inline fn makeAddress(high: u8, low: u8) u16 {
    return (@as(u16, high) << 8) | @as(u16, low);
}

/// Get high byte of 16-bit address
pub inline fn getHighByte(addr: u16) u8 {
    return @as(u8, @truncate(addr >> 8));
}

/// Get low byte of 16-bit address
pub inline fn getLowByte(addr: u16) u8 {
    return @as(u8, @truncate(addr));
}

// ============================================================================
// Tests
// ============================================================================

const std = @import("std");
const testing = std.testing;

test "pagesDiffer: same page" {
    try testing.expect(!pagesDiffer(0x1000, 0x10FF));
    try testing.expect(!pagesDiffer(0x0000, 0x00FF));
    try testing.expect(!pagesDiffer(0xFF00, 0xFFFF));
}

test "pagesDiffer: different pages" {
    try testing.expect(pagesDiffer(0x10FF, 0x1100));
    try testing.expect(pagesDiffer(0x00FF, 0x0100));
    try testing.expect(pagesDiffer(0x1234, 0x5678));
}

test "makeAddress" {
    try testing.expectEqual(@as(u16, 0x0000), makeAddress(0x00, 0x00));
    try testing.expectEqual(@as(u16, 0x1234), makeAddress(0x12, 0x34));
    try testing.expectEqual(@as(u16, 0xFFFF), makeAddress(0xFF, 0xFF));
}

test "getHighByte and getLowByte" {
    const addr: u16 = 0x1234;
    try testing.expectEqual(@as(u8, 0x12), getHighByte(addr));
    try testing.expectEqual(@as(u8, 0x34), getLowByte(addr));

    // Round trip
    const reconstructed = makeAddress(getHighByte(addr), getLowByte(addr));
    try testing.expectEqual(addr, reconstructed);
}

test "address helpers edge cases" {
    // Zero
    try testing.expectEqual(@as(u8, 0x00), getHighByte(0x0000));
    try testing.expectEqual(@as(u8, 0x00), getLowByte(0x0000));

    // Max
    try testing.expectEqual(@as(u8, 0xFF), getHighByte(0xFFFF));
    try testing.expectEqual(@as(u8, 0xFF), getLowByte(0xFFFF));

    // Page boundaries
    try testing.expectEqual(@as(u8, 0x01), getHighByte(0x0100));
    try testing.expectEqual(@as(u8, 0x00), getLowByte(0x0100));
}
