//! Breakpoint management logic
//! Pure functions operating on DebuggerState

const types = @import("types.zig");
const BreakpointType = types.BreakpointType;
const Breakpoint = types.Breakpoint;

/// Add breakpoint to debugger state
/// Returns error.BreakpointLimitReached if 256 breakpoints already exist
pub fn add(state: anytype, address: u16, bp_type: BreakpointType) !void {
    // Check if breakpoint already exists (update and re-enable)
    for (state.breakpoints[0..256]) |*maybe_bp| {
        if (maybe_bp.*) |*bp| {
            if (bp.address == address and bp.type == bp_type) {
                if (!bp.enabled) {
                    bp.enabled = true;
                    if (isMemoryBreakpointType(bp_type)) {
                        state.memory_breakpoint_enabled_count += 1;
                    }
                }
                return;
            }
        }
    }

    // Check capacity
    if (state.breakpoint_count >= 256) {
        return error.BreakpointLimitReached;
    }

    // Find first null slot (linear search)
    var slot_index: ?usize = null;
    for (state.breakpoints[0..256], 0..) |maybe_bp, i| {
        if (maybe_bp == null) {
            slot_index = i;
            break;
        }
    }

    // Add breakpoint at first available slot
    const index = slot_index.?; // Guaranteed to exist (checked capacity)
    state.breakpoints[index] = .{
        .address = address,
        .type = bp_type,
    };
    state.breakpoint_count += 1;
    if (isMemoryBreakpointType(bp_type)) {
        state.memory_breakpoint_enabled_count += 1;
    }
}

/// Remove breakpoint from debugger state
pub fn remove(state: anytype, address: u16, bp_type: BreakpointType) bool {
    for (state.breakpoints[0..256], 0..) |*maybe_bp, i| {
        if (maybe_bp.*) |bp| {
            if (bp.address == address and bp.type == bp_type) {
                if (bp.enabled and isMemoryBreakpointType(bp_type)) {
                    state.memory_breakpoint_enabled_count -= 1;
                }
                state.breakpoints[i] = null;
                state.breakpoint_count -= 1;
                return true;
            }
        }
    }
    return false;
}

/// Enable/disable breakpoint
pub fn setEnabled(state: anytype, address: u16, bp_type: BreakpointType, enabled: bool) bool {
    for (state.breakpoints[0..256]) |*maybe_bp| {
        if (maybe_bp.*) |*bp| {
            if (bp.address == address and bp.type == bp_type) {
                if (bp.enabled == enabled) {
                    return true;
                }

                const is_memory = isMemoryBreakpointType(bp.type);
                if (is_memory) {
                    if (enabled) {
                        state.memory_breakpoint_enabled_count += 1;
                    } else {
                        state.memory_breakpoint_enabled_count -= 1;
                    }
                }

                bp.enabled = enabled;
                return true;
            }
        }
    }
    return false;
}

/// Clear all breakpoints
pub fn clear(state: anytype) void {
    for (state.breakpoints[0..256]) |*maybe_bp| {
        maybe_bp.* = null;
    }
    state.breakpoint_count = 0;
    state.memory_breakpoint_enabled_count = 0;
}

inline fn isMemoryBreakpointType(bp_type: BreakpointType) bool {
    return switch (bp_type) {
        .execute => false,
        .read, .write, .access => true,
    };
}
