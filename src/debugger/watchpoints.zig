//! Watchpoint management logic
//! Pure functions operating on DebuggerState

const types = @import("types.zig");
const WatchType = types.Watchpoint.WatchType;
const Watchpoint = types.Watchpoint;

/// Add watchpoint to debugger state
/// Returns error.WatchpointLimitReached if 256 watchpoints already exist
pub fn add(state: anytype, address: u16, size: u16, watch_type: WatchType) !void {
    // Check if watchpoint already exists (update and re-enable)
    for (state.watchpoints[0..256]) |*maybe_wp| {
        if (maybe_wp.*) |*wp| {
            if (wp.address == address and wp.type == watch_type) {
                if (!wp.enabled) {
                    wp.enabled = true;
                    state.watchpoint_enabled_count += 1;
                }
                wp.size = size;
                return;
            }
        }
    }

    // Check capacity
    if (state.watchpoint_count >= 256) {
        return error.WatchpointLimitReached;
    }

    // Find first null slot (linear search)
    var slot_index: ?usize = null;
    for (state.watchpoints[0..256], 0..) |maybe_wp, i| {
        if (maybe_wp == null) {
            slot_index = i;
            break;
        }
    }

    // Add watchpoint at first available slot
    const index = slot_index.?; // Guaranteed to exist (checked capacity)
    state.watchpoints[index] = .{
        .address = address,
        .size = size,
        .type = watch_type,
    };
    state.watchpoint_count += 1;
    state.watchpoint_enabled_count += 1;
}

/// Remove watchpoint from debugger state
pub fn remove(state: anytype, address: u16, watch_type: WatchType) bool {
    for (state.watchpoints[0..256], 0..) |*maybe_wp, i| {
        if (maybe_wp.*) |wp| {
            if (wp.address == address and wp.type == watch_type) {
                if (wp.enabled) {
                    state.watchpoint_enabled_count -= 1;
                }
                state.watchpoints[i] = null;
                state.watchpoint_count -= 1;
                return true;
            }
        }
    }
    return false;
}

/// Clear all watchpoints
pub fn clear(state: anytype) void {
    for (state.watchpoints[0..256]) |*maybe_wp| {
        maybe_wp.* = null;
    }
    state.watchpoint_count = 0;
    state.watchpoint_enabled_count = 0;
}
