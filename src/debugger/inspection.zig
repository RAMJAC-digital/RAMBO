//! State inspection logic
//! Pure read-only functions operating on DebuggerState and EmulationState

const std = @import("std");
const EmulationState = @import("../emulation/State.zig").EmulationState;
const types = @import("types.zig");
const StateModification = types.StateModification;

/// Read memory for inspection WITHOUT side effects
/// Does NOT update open bus - safe for debugger inspection
/// Uses EmulationState.peekMemory() to avoid side effects
pub fn readMemory(
    state: anytype,
    emu_state: *const EmulationState,
    address: u16,
) u8 {
    _ = state;
    // Use peekMemory() which does NOT update open_bus
    return emu_state.peekMemory(address);
}

/// Read memory range for inspection WITHOUT side effects
/// Does not update open bus - safe for debugger inspection
pub fn readMemoryRange(
    state: anytype,
    allocator: std.mem.Allocator,
    emu_state: *const EmulationState,
    start_address: u16,
    length: u16,
) ![]u8 {
    _ = state;
    const buffer = try allocator.alloc(u8, length);
    // Use peekMemory() which does NOT update open_bus
    for (0..length) |i| {
        buffer[i] = emu_state.peekMemory(start_address +% @as(u16, @intCast(i)));
    }
    return buffer;
}

/// Get current break reason (returns slice into static buffer)
pub fn getBreakReason(state: anytype) ?[]const u8 {
    if (state.break_reason_len == 0) return null;
    return state.break_reason_buffer[0..state.break_reason_len];
}

/// Check if debugger is currently paused
pub fn isPaused(state: anytype) bool {
    return state.mode == .paused;
}

/// Fast check for any active memory breakpoints or watchpoints
pub fn hasMemoryTriggers(state: anytype) bool {
    return state.memory_breakpoint_enabled_count > 0 or state.watchpoint_enabled_count > 0;
}

/// Get modification history
pub fn getModifications(state: anytype) []const StateModification {
    return state.modifications.items;
}
