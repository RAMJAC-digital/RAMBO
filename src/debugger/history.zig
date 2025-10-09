//! Execution history management logic
//! Pure functions operating on DebuggerState

const std = @import("std");
const Snapshot = @import("../snapshot/Snapshot.zig");
const EmulationState = @import("../emulation/State.zig").EmulationState;
const Config = @import("../config/Config.zig").Config;
const AnyCartridge = @import("../cartridge/mappers/registry.zig").AnyCartridge;
const types = @import("types.zig");
const HistoryEntry = types.HistoryEntry;

/// Capture current state to history
pub fn capture(
    state: anytype,
    allocator: std.mem.Allocator,
    emu_state: *const EmulationState,
    config: *const Config,
) !void {
    // Create snapshot
    const snapshot = try Snapshot.saveBinary(
        allocator,
        emu_state,
        config,
        .reference,
        false,
        null,
    );
    errdefer allocator.free(snapshot);

    const entry = HistoryEntry{
        .snapshot = snapshot,
        .pc = emu_state.cpu.pc,
        .scanline = emu_state.clock.scanline(),
        .frame = emu_state.clock.frame(),
        .timestamp = std.time.timestamp(),
    };

    // Add to history
    try state.history.append(allocator, entry);
    state.stats.snapshots_captured += 1;

    // Remove oldest if exceeding max size
    if (state.history.items.len > state.history_max_size) {
        const oldest = state.history.orderedRemove(0);
        allocator.free(oldest.snapshot);
    }
}

/// Restore state from history
pub fn restore(
    state: anytype,
    allocator: std.mem.Allocator,
    config: *const Config,
    index: usize,
    cartridge: ?AnyCartridge,
) !EmulationState {
    if (index >= state.history.items.len) return error.InvalidHistoryIndex;

    const entry = state.history.items[index];
    return try Snapshot.loadBinary(
        allocator,
        entry.snapshot,
        config,
        cartridge,
    );
}

/// Clear history
pub fn clear(state: anytype, allocator: std.mem.Allocator) void {
    for (state.history.items) |entry| {
        allocator.free(entry.snapshot);
    }
    state.history.clearRetainingCapacity();
}
