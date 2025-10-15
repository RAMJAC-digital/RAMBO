//! Debugger System
//!
//! External wrapper for EmulationState providing debugging capabilities.
//! Uses external wrapper pattern - does not modify EmulationState internals.
//!
//! Features:
//! - Breakpoints (address, read, write)
//! - Watchpoints (memory read/write)
//! - Step execution (instruction, scanline, frame)
//! - Execution history (snapshot-based)
//! - State inspection and manipulation
//! - User-defined callbacks (RT-safe, async-compatible)

const std = @import("std");
const Snapshot = @import("../snapshot/Snapshot.zig");
const EmulationState = @import("../emulation/State.zig").EmulationState;
const Config = @import("../config/Config.zig").Config;
const AnyCartridge = @import("../cartridge/mappers/registry.zig").AnyCartridge;

// Logic modules
const DebuggerState = @import("State.zig").DebuggerState;
const breakpoints = @import("breakpoints.zig");
const watchpoints = @import("watchpoints.zig");
const stepping = @import("stepping.zig");
const history = @import("history.zig");
pub const inspection = @import("inspection.zig");
const modification = @import("modification.zig");

// Re-export all types (preserves existing API)
pub const DebugCallback = @import("types.zig").DebugCallback;
pub const DebugMode = @import("types.zig").DebugMode;
pub const BreakpointType = @import("types.zig").BreakpointType;
pub const Breakpoint = @import("types.zig").Breakpoint;
pub const Watchpoint = @import("types.zig").Watchpoint;
const StepState = @import("types.zig").StepState;
pub const HistoryEntry = @import("types.zig").HistoryEntry;
pub const DebugStats = @import("types.zig").DebugStats;
pub const StatusFlag = @import("types.zig").StatusFlag;
pub const StateModification = @import("types.zig").StateModification;

/// Main debugger facade - wraps DebuggerState with inline delegation
pub const Debugger = struct {
    state: DebuggerState,

    pub fn init(allocator: std.mem.Allocator, config: *const Config) Debugger {
        return .{
            .state = DebuggerState.init(allocator, config),
        };
    }

    pub fn deinit(self: *Debugger) void {
        self.state.deinit();
    }

    // ========================================================================
    // Breakpoint Management (delegate to breakpoints.zig)
    // ========================================================================

    /// Add breakpoint
    pub inline fn addBreakpoint(self: *Debugger, address: u16, bp_type: BreakpointType) !void {
        return breakpoints.add(&self.state, address, bp_type);
    }

    /// Remove breakpoint
    pub inline fn removeBreakpoint(self: *Debugger, address: u16, bp_type: BreakpointType) bool {
        return breakpoints.remove(&self.state, address, bp_type);
    }

    /// Enable/disable breakpoint
    pub inline fn setBreakpointEnabled(self: *Debugger, address: u16, bp_type: BreakpointType, enabled: bool) bool {
        return breakpoints.setEnabled(&self.state, address, bp_type, enabled);
    }

    /// Clear all breakpoints
    pub inline fn clearBreakpoints(self: *Debugger) void {
        breakpoints.clear(&self.state);
    }

    // ========================================================================
    // Watchpoint Management (delegate to watchpoints.zig)
    // ========================================================================

    /// Add watchpoint
    pub inline fn addWatchpoint(self: *Debugger, address: u16, size: u16, watch_type: Watchpoint.WatchType) !void {
        return watchpoints.add(&self.state, address, size, watch_type);
    }

    /// Remove watchpoint
    pub inline fn removeWatchpoint(self: *Debugger, address: u16, watch_type: Watchpoint.WatchType) bool {
        return watchpoints.remove(&self.state, address, watch_type);
    }

    /// Clear all watchpoints
    pub inline fn clearWatchpoints(self: *Debugger) void {
        watchpoints.clear(&self.state);
    }

    // ========================================================================
    // Execution Control (delegate to stepping.zig)
    // ========================================================================

    /// Continue execution
    pub inline fn continue_(self: *Debugger) void {
        stepping.continue_(&self.state);
    }

    /// Pause execution
    pub inline fn pause(self: *Debugger) void {
        stepping.pause(&self.state);
    }

    /// Step one instruction
    pub inline fn stepInstruction(self: *Debugger) void {
        stepping.stepInstruction(&self.state);
    }

    /// Step over (skip subroutines)
    pub inline fn stepOver(self: *Debugger, state: *const EmulationState) void {
        stepping.stepOver(&self.state, state);
    }

    /// Step out (return from subroutine)
    pub inline fn stepOut(self: *Debugger, state: *const EmulationState) void {
        stepping.stepOut(&self.state, state);
    }

    /// Step one scanline
    pub inline fn stepScanline(self: *Debugger, state: *const EmulationState) void {
        stepping.stepScanline(&self.state, state);
    }

    /// Step one frame
    pub inline fn stepFrame(self: *Debugger, state: *const EmulationState) void {
        stepping.stepFrame(&self.state, state);
    }

    // ========================================================================
    // Callback Management (User-Defined Hooks)
    // ========================================================================

    /// Register a user-defined callback
    /// Maximum 8 callbacks can be registered
    pub fn registerCallback(self: *Debugger, callback: DebugCallback) !void {
        if (self.state.callback_count >= 8) return error.TooManyCallbacks;

        self.state.callbacks[self.state.callback_count] = callback;
        self.state.callback_count += 1;
    }

    /// Unregister a callback by userdata pointer
    pub fn unregisterCallback(self: *Debugger, userdata: *anyopaque) bool {
        for (self.state.callbacks[0..self.state.callback_count], 0..) |maybe_callback, i| {
            if (maybe_callback) |cb| {
                if (cb.userdata == userdata) {
                    // Shift remaining callbacks down
                    var j = i;
                    while (j < self.state.callback_count - 1) : (j += 1) {
                        self.state.callbacks[j] = self.state.callbacks[j + 1];
                    }
                    self.state.callbacks[self.state.callback_count - 1] = null;
                    self.state.callback_count -= 1;
                    return true;
                }
            }
        }
        return false;
    }

    /// Clear all registered callbacks
    pub fn clearCallbacks(self: *Debugger) void {
        for (self.state.callbacks[0..self.state.callback_count]) |*cb| {
            cb.* = null;
        }
        self.state.callback_count = 0;
    }

    // ========================================================================
    // Execution Hook (called before each instruction)
    // ========================================================================

    /// Check if should break before executing instruction
    /// Returns true if execution should pause
    pub fn shouldBreak(self: *Debugger, state: *const EmulationState) !bool {
        // Update stats
        self.state.stats.instructions_executed += 1;

        if (self.state.breakpoint_count > self.state.breakpoints.len or
            self.state.watchpoint_count > self.state.watchpoints.len or
            self.state.callback_count > self.state.callbacks.len)
        {
            return false;
        }

        // Check step modes
        switch (self.state.mode) {
            .running => {},
            .paused => return true,
            .step_instruction => {
                self.state.mode = .paused;
                try self.setBreakReason("Step instruction");
                return true;
            },
            .step_over => {
                // Mark that we've executed at least one instruction
                const first_check = !self.state.step_state.has_stepped;
                self.state.step_state.has_stepped = true;

                // Don't break on first check - wait for SP to change first
                if (first_check) return false;

                // Check if we've returned to same or higher stack level
                if (state.cpu.sp >= self.state.step_state.initial_sp) {
                    self.state.mode = .paused;
                    try self.setBreakReason("Step over complete");
                    return true;
                }
            },
            .step_out => {
                // Check if stack pointer increased (returned from function)
                if (state.cpu.sp > self.state.step_state.initial_sp) {
                    self.state.mode = .paused;
                    try self.setBreakReason("Step out complete");
                    return true;
                }
            },
            .step_scanline => {
                if (self.state.step_state.target_scanline) |target| {
                    if (state.clock.scanline() == target) {
                        self.state.mode = .paused;
                        try self.setBreakReason("Scanline step complete");
                        return true;
                    }
                }
            },
            .step_frame => {
                if (self.state.step_state.target_frame) |target| {
                    if (state.clock.frame() >= target) {
                        self.state.mode = .paused;
                        try self.setBreakReason("Frame step complete");
                        return true;
                    }
                }
            },
        }

        // Check execute breakpoints
        for (self.state.breakpoints[0..256]) |*maybe_bp| {
            if (maybe_bp.*) |*bp| {
                if (!bp.enabled) continue;
                if (bp.type != .execute) continue;
                if (bp.address != state.cpu.pc) continue;

                // Check condition if present
                if (bp.condition) |condition| {
                    if (!checkBreakCondition(condition, state)) continue;
                }

                bp.hit_count += 1;
                self.state.stats.breakpoints_hit += 1;
                self.state.mode = .paused;

                // Format into stack buffer (no heap allocation)
                var buf: [128]u8 = undefined;
                const reason = std.fmt.bufPrint(
                    &buf,
                    "Breakpoint at ${X:0>4} (hit count: {})",
                    .{ bp.address, bp.hit_count },
                ) catch "Breakpoint hit"; // Fallback if buffer too small

                try self.setBreakReason(reason);

                return true;
            }
        }

        // Check user-defined callbacks
        const callback_limit = @min(self.state.callback_count, self.state.callbacks.len);
        for (self.state.callbacks[0..callback_limit]) |maybe_callback| {
            if (maybe_callback) |callback| {
                if (callback.onBeforeInstruction) |func| {
                    if (func(callback.userdata, state)) {
                        self.state.mode = .paused;
                        try self.setBreakReason("User callback break");
                        return true;
                    }
                }
            }
        }

        return false;
    }

    /// Check memory access (read/write)
    pub fn checkMemoryAccess(
        self: *Debugger,
        _: *const EmulationState,
        address: u16,
        value: u8,
        is_write: bool,
    ) !bool {
        const breakpoint_limit = @min(self.state.breakpoint_count, self.state.breakpoints.len);

        // Check read/write breakpoints
        for (self.state.breakpoints[0..breakpoint_limit]) |*maybe_bp| {
            if (maybe_bp.*) |*bp| {
                if (!bp.enabled) continue;

                const matches = switch (bp.type) {
                    .read => !is_write and bp.address == address,
                    .write => is_write and bp.address == address,
                    .access => bp.address == address,
                    .execute => false,
                };

                if (matches) {
                    bp.hit_count += 1;
                    self.state.stats.breakpoints_hit += 1;
                    self.state.mode = .paused;

                    // Format into stack buffer (no heap allocation)
                    var buf: [128]u8 = undefined;
                    const reason = std.fmt.bufPrint(
                        &buf,
                        "Breakpoint: {s} ${X:0>4} = ${X:0>2}",
                        .{ if (is_write) "Write" else "Read", address, value },
                    ) catch "Memory breakpoint hit";

                    try self.setBreakReason(reason);

                    return true;
                }
            }
        }

        // Check watchpoints
        const watchpoint_limit = @min(self.state.watchpoint_count, self.state.watchpoints.len);
        for (self.state.watchpoints[0..watchpoint_limit]) |*maybe_wp| {
            if (maybe_wp.*) |*wp| {
                if (!wp.enabled) continue;
                if (address < wp.address or address >= wp.address + wp.size) continue;

                const should_break = switch (wp.type) {
                    .read => !is_write,
                    .write => is_write,
                    .change => blk: {
                        if (!is_write) break :blk false;
                        if (wp.old_value) |old| {
                            break :blk old != value;
                        }
                        break :blk true;
                    },
                };

                if (should_break) {
                    wp.old_value = value;
                    wp.hit_count += 1;
                    self.state.stats.watchpoints_hit += 1;
                    self.state.mode = .paused;

                    // Format into stack buffer (no heap allocation)
                    var buf: [128]u8 = undefined;
                    const reason = std.fmt.bufPrint(
                        &buf,
                        "Watchpoint: {s} ${X:0>4} = ${X:0>2}",
                        .{ @tagName(wp.type), address, value },
                    ) catch "Watchpoint hit";

                    try self.setBreakReason(reason);

                    return true;
                }
            }
        }

        // Check user-defined callbacks
        const callback_limit = @min(self.state.callback_count, self.state.callbacks.len);
        for (self.state.callbacks[0..callback_limit]) |maybe_callback| {
            if (maybe_callback) |callback| {
                if (callback.onMemoryAccess) |func| {
                    if (func(callback.userdata, address, value, is_write)) {
                        self.state.mode = .paused;
                        // Format into stack buffer
                        var buf: [128]u8 = undefined;
                        const access_type: []const u8 = if (is_write) "write" else "read";
                        const reason = std.fmt.bufPrint(
                            &buf,
                            "Memory callback: {s} ${X:0>4}",
                            .{ access_type, address },
                        ) catch "Memory callback";
                        try self.setBreakReason(reason);
                        return true;
                    }
                }
            }
        }

        return false;
    }

    // ========================================================================
    // Execution History (delegate to history.zig)
    // ========================================================================

    /// Capture current state to history
    pub inline fn captureHistory(self: *Debugger, state: *const EmulationState) !void {
        return history.capture(&self.state, self.state.allocator, state, self.state.config);
    }

    /// Restore state from history
    pub inline fn restoreFromHistory(
        self: *Debugger,
        index: usize,
        cartridge: ?AnyCartridge,
    ) !EmulationState {
        return history.restore(&self.state, self.state.allocator, self.state.config, index, cartridge);
    }

    /// Clear history
    pub inline fn clearHistory(self: *Debugger) void {
        history.clear(&self.state, self.state.allocator);
    }

    // ========================================================================
    // State Manipulation - CPU Registers (delegate to modification.zig)
    // ========================================================================

    /// Set accumulator register
    pub inline fn setRegisterA(self: *Debugger, state: *EmulationState, value: u8) void {
        modification.setRegisterA(&self.state, state, value);
    }

    /// Set X index register
    pub inline fn setRegisterX(self: *Debugger, state: *EmulationState, value: u8) void {
        modification.setRegisterX(&self.state, state, value);
    }

    /// Set Y index register
    pub inline fn setRegisterY(self: *Debugger, state: *EmulationState, value: u8) void {
        modification.setRegisterY(&self.state, state, value);
    }

    /// Set stack pointer
    pub inline fn setStackPointer(self: *Debugger, state: *EmulationState, value: u8) void {
        modification.setStackPointer(&self.state, state, value);
    }

    /// Set program counter
    pub inline fn setProgramCounter(self: *Debugger, state: *EmulationState, value: u16) void {
        modification.setProgramCounter(&self.state, state, value);
    }

    /// Set individual status flag
    pub inline fn setStatusFlag(
        self: *Debugger,
        state: *EmulationState,
        flag: StatusFlag,
        value: bool,
    ) void {
        modification.setStatusFlag(&self.state, state, flag, value);
    }

    /// Set complete status register from byte
    pub inline fn setStatusRegister(self: *Debugger, state: *EmulationState, value: u8) void {
        modification.setStatusRegister(&self.state, state, value);
    }

    // ========================================================================
    // State Manipulation - Memory (delegate to modification.zig)
    // ========================================================================

    /// Write single byte to memory
    pub inline fn writeMemory(
        self: *Debugger,
        state: *EmulationState,
        address: u16,
        value: u8,
    ) void {
        modification.writeMemory(&self.state, state, address, value);
    }

    /// Write byte range to memory
    pub inline fn writeMemoryRange(
        self: *Debugger,
        state: *EmulationState,
        start_address: u16,
        data: []const u8,
    ) void {
        modification.writeMemoryRange(&self.state, state, start_address, data);
    }

    /// Read memory for inspection WITHOUT side effects
    pub inline fn readMemory(
        self: *Debugger,
        state: *const EmulationState,
        address: u16,
    ) u8 {
        return inspection.readMemory(&self.state, state, address);
    }

    /// Read memory range for inspection WITHOUT side effects
    pub inline fn readMemoryRange(
        self: *Debugger,
        allocator: std.mem.Allocator,
        state: *const EmulationState,
        start_address: u16,
        length: u16,
    ) ![]u8 {
        return inspection.readMemoryRange(&self.state, allocator, state, start_address, length);
    }

    // ========================================================================
    // State Manipulation - PPU (delegate to modification.zig)
    // ========================================================================

    /// Set PPU scanline
    pub inline fn setPpuScanline(self: *Debugger, state: *EmulationState, scanline: u16) void {
        modification.setPpuScanline(&self.state, state, scanline);
    }

    /// Set PPU frame counter
    pub inline fn setPpuFrame(self: *Debugger, state: *EmulationState, frame: u64) void {
        modification.setPpuFrame(&self.state, state, frame);
    }

    // ========================================================================
    // Modification History (delegate to inspection/modification.zig)
    // ========================================================================

    /// Get modification history
    pub inline fn getModifications(self: *const Debugger) []const StateModification {
        return inspection.getModifications(&self.state);
    }

    /// Clear modification history
    pub inline fn clearModifications(self: *Debugger) void {
        modification.clearModifications(&self.state);
    }

    // ========================================================================
    // Helper Functions (delegate to inspection.zig)
    // ========================================================================

    /// Get current break reason
    pub inline fn getBreakReason(self: *const Debugger) ?[]const u8 {
        return inspection.getBreakReason(&self.state);
    }

    /// Check if debugger is currently paused
    pub inline fn isPaused(self: *const Debugger) bool {
        return inspection.isPaused(&self.state);
    }

    /// Fast check for any active memory breakpoints or watchpoints
    pub inline fn hasMemoryTriggers(self: *const Debugger) bool {
        return inspection.hasMemoryTriggers(&self.state);
    }

    /// Fast check for any registered callbacks
    pub inline fn hasCallbacks(self: *const Debugger) bool {
        return inspection.hasCallbacks(&self.state);
    }

    // ========================================================================
    // Internal Helper Functions
    // ========================================================================

    fn checkBreakCondition(condition: Breakpoint.BreakCondition, state: *const EmulationState) bool {
        return switch (condition) {
            .a_equals => |val| state.cpu.a == val,
            .x_equals => |val| state.cpu.x == val,
            .y_equals => |val| state.cpu.y == val,
            .hit_count => |_| true, // Always break, hit count checked externally
        };
    }

    /// Set break reason using pre-allocated buffer (RT-safe)
    fn setBreakReason(self: *Debugger, reason: []const u8) !void {
        const len = @min(reason.len, self.state.break_reason_buffer.len);
        @memcpy(self.state.break_reason_buffer[0..len], reason[0..len]);
        self.state.break_reason_len = len;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "Debugger: init and deinit" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    try testing.expectEqual(DebugMode.running, debugger.state.mode);
    try testing.expectEqual(@as(usize, 0), debugger.state.breakpoint_count);
    try testing.expectEqual(@as(usize, 0), debugger.state.watchpoint_count);
}

test "Debugger: breakpoint management" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    // Add breakpoint
    try debugger.addBreakpoint(0x8000, .execute);
    try testing.expectEqual(@as(usize, 1), debugger.state.breakpoint_count);
    // Find and verify the breakpoint
    var found_bp: ?Breakpoint = null;
    for (debugger.state.breakpoints[0..256]) |maybe_bp| {
        if (maybe_bp) |bp| {
            found_bp = bp;
            break;
        }
    }
    try testing.expect(found_bp != null);
    try testing.expectEqual(@as(u16, 0x8000), found_bp.?.address);
    try testing.expectEqual(BreakpointType.execute, found_bp.?.type);

    // Remove breakpoint
    try testing.expect(debugger.removeBreakpoint(0x8000, .execute));
    try testing.expectEqual(@as(usize, 0), debugger.state.breakpoint_count);
}

test "Debugger: watchpoint management" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    // Add watchpoint
    try debugger.addWatchpoint(0x2000, 8, .write);
    try testing.expectEqual(@as(usize, 1), debugger.state.watchpoint_count);

    // Remove watchpoint
    try testing.expect(debugger.removeWatchpoint(0x2000, .write));
    try testing.expectEqual(@as(usize, 0), debugger.state.watchpoint_count);
}

test "Debugger: execution control" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    // Initial state is running
    try testing.expectEqual(DebugMode.running, debugger.state.mode);

    // Pause
    debugger.pause();
    try testing.expectEqual(DebugMode.paused, debugger.state.mode);

    // Continue
    debugger.continue_();
    try testing.expectEqual(DebugMode.running, debugger.state.mode);

    // Step instruction
    debugger.stepInstruction();
    try testing.expectEqual(DebugMode.step_instruction, debugger.state.mode);
}
