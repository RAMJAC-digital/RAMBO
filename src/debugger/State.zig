//! Debugger state structure
//! Holds all debugger data (breakpoints, watchpoints, history, etc.)

const std = @import("std");
const types = @import("types.zig");
const Config = @import("../config/Config.zig").Config;

pub const DebuggerState = struct {
    const magic_value: u64 = 0xDEB6_6170_5055_4247; // 'DEBlaPPUBG' sentinel

    allocator: std.mem.Allocator,
    config: *const Config,
    magic: u64 = magic_value,

    /// Current debug mode
    mode: types.DebugMode = .running,

    /// Breakpoints (up to 256, RT-safe fixed array)
    breakpoints: [256]?types.Breakpoint = [_]?types.Breakpoint{null} ** 256,
    breakpoint_count: usize = 0,
    memory_breakpoint_enabled_count: usize = 0,

    /// Watchpoints (up to 256, RT-safe fixed array)
    watchpoints: [256]?types.Watchpoint = [_]?types.Watchpoint{null} ** 256,
    watchpoint_count: usize = 0,
    watchpoint_enabled_count: usize = 0,

    /// Step execution state
    step_state: types.StepState = .{},

    /// Execution history (circular buffer)
    history: std.ArrayList(types.HistoryEntry),
    history_max_size: usize = 100,

    /// State modification history (circular buffer)
    modifications: std.ArrayList(types.StateModification),
    modifications_max_size: usize = 1000,

    /// Debug statistics
    stats: types.DebugStats = .{},

    /// Pre-allocated buffer for break reasons (RT-safe, no heap allocation)
    /// Used by shouldBreak() and checkMemoryAccess() to avoid allocPrint()
    break_reason_buffer: [256]u8 = undefined,
    break_reason_len: usize = 0,

    /// User-defined callbacks (RT-safe, fixed-size array)
    /// Maximum 8 callbacks can be registered
    /// Callbacks are called in registration order
    callbacks: [8]?types.DebugCallback = [_]?types.DebugCallback{null} ** 8,
    callback_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator, config: *const Config) DebuggerState {
        return .{
            .allocator = allocator,
            .config = config,
            // breakpoints/watchpoints auto-initialize from struct defaults
            .history = std.ArrayList(types.HistoryEntry){},
            .modifications = std.ArrayList(types.StateModification){},
        };
    }

    pub fn deinit(self: *DebuggerState) void {
        // Note: breakpoints/watchpoints are fixed arrays (no cleanup needed)

        // Free history snapshots
        for (self.history.items) |entry| {
            self.allocator.free(entry.snapshot);
        }
        self.history.deinit(self.allocator);

        // Free modifications
        self.modifications.deinit(self.allocator);

        // Note: break_reason_buffer is a fixed array (no cleanup needed)
    }
};
