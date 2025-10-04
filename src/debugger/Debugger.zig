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

const std = @import("std");
const Snapshot = @import("../snapshot/Snapshot.zig");
const EmulationState = @import("../emulation/State.zig").EmulationState;
const Config = @import("../config/Config.zig").Config;

/// Debugger execution mode
pub const DebugMode = enum {
    /// Running normally (no debugging)
    running,
    /// Paused at breakpoint
    paused,
    /// Single-step mode (step one instruction)
    step_instruction,
    /// Step over (skip subroutines)
    step_over,
    /// Step out (return from subroutine)
    step_out,
    /// Step one scanline
    step_scanline,
    /// Step one frame
    step_frame,
};

/// Breakpoint types
pub const BreakpointType = enum {
    /// Break on instruction execution at address
    execute,
    /// Break on memory read at address
    read,
    /// Break on memory write at address
    write,
    /// Break on any memory access at address
    access,
};

/// Breakpoint definition
pub const Breakpoint = struct {
    address: u16,
    type: BreakpointType,
    enabled: bool = true,
    hit_count: u64 = 0,
    condition: ?BreakCondition = null,

    pub const BreakCondition = union(enum) {
        /// Break if A register equals value
        a_equals: u8,
        /// Break if X register equals value
        x_equals: u8,
        /// Break if Y register equals value
        y_equals: u8,
        /// Break after N hits
        hit_count: u64,
    };
};

/// Watchpoint definition
pub const Watchpoint = struct {
    address: u16,
    size: u16 = 1,
    type: WatchType,
    enabled: bool = true,
    hit_count: u64 = 0,
    old_value: ?u8 = null,

    pub const WatchType = enum {
        read,
        write,
        change, // Value changed
    };
};

/// Step execution state
const StepState = struct {
    target_pc: ?u16 = null,
    target_sp: ?u8 = null,
    target_scanline: ?u16 = null,
    target_frame: ?u64 = null,
    initial_sp: u8 = 0,
    has_stepped: bool = false,
};

/// Execution history entry
pub const HistoryEntry = struct {
    snapshot: []u8,
    pc: u16,
    scanline: u16,
    frame: u64,
    timestamp: i64,
};

/// Debugger statistics
pub const DebugStats = struct {
    instructions_executed: u64 = 0,
    breakpoints_hit: u64 = 0,
    watchpoints_hit: u64 = 0,
    snapshots_captured: u64 = 0,
};

/// CPU status flags for manipulation
pub const StatusFlag = enum {
    carry,
    zero,
    interrupt,
    decimal,
    overflow,
    negative,
};

/// State modification record for debugging history
pub const StateModification = union(enum) {
    register_a: u8,
    register_x: u8,
    register_y: u8,
    stack_pointer: u8,
    program_counter: u16,
    status_flag: struct { flag: StatusFlag, value: bool },
    status_register: u8,
    memory_write: struct { address: u16, value: u8 },
    memory_range: struct { start: u16, length: u16 },
    ppu_ctrl: u8,
    ppu_mask: u8,
    ppu_scroll: struct { x: u8, y: u8 },
    ppu_addr: u16,
    ppu_vram: struct { address: u16, value: u8 },
    ppu_scanline: u16,
    ppu_frame: u64,
};

/// Main debugger structure
pub const Debugger = struct {
    allocator: std.mem.Allocator,
    config: *const Config,

    /// Current debug mode
    mode: DebugMode = .running,

    /// Breakpoints (up to 256)
    breakpoints: std.ArrayList(Breakpoint),

    /// Watchpoints (up to 256)
    watchpoints: std.ArrayList(Watchpoint),

    /// Step execution state
    step_state: StepState = .{},

    /// Execution history (circular buffer)
    history: std.ArrayList(HistoryEntry),
    history_max_size: usize = 100,

    /// State modification history (circular buffer)
    modifications: std.ArrayList(StateModification),
    modifications_max_size: usize = 1000,

    /// Debug statistics
    stats: DebugStats = .{},

    /// Pre-allocated buffer for break reasons (RT-safe, no heap allocation)
    /// Used by shouldBreak() and checkMemoryAccess() to avoid allocPrint()
    break_reason_buffer: [256]u8 = undefined,
    break_reason_len: usize = 0,

    pub fn init(allocator: std.mem.Allocator, config: *const Config) Debugger {
        return .{
            .allocator = allocator,
            .config = config,
            .breakpoints = std.ArrayList(Breakpoint){},
            .watchpoints = std.ArrayList(Watchpoint){},
            .history = std.ArrayList(HistoryEntry){},
            .modifications = std.ArrayList(StateModification){},
        };
    }

    pub fn deinit(self: *Debugger) void {
        // Free breakpoints
        self.breakpoints.deinit(self.allocator);

        // Free watchpoints
        self.watchpoints.deinit(self.allocator);

        // Free history snapshots
        for (self.history.items) |entry| {
            self.allocator.free(entry.snapshot);
        }
        self.history.deinit(self.allocator);

        // Free modifications
        self.modifications.deinit(self.allocator);

        // Note: break_reason_buffer is a fixed array (no cleanup needed)
    }

    // ========================================================================
    // Breakpoint Management
    // ========================================================================

    /// Add breakpoint
    pub fn addBreakpoint(self: *Debugger, address: u16, bp_type: BreakpointType) !void {
        // Check if breakpoint already exists
        for (self.breakpoints.items) |*bp| {
            if (bp.address == address and bp.type == bp_type) {
                bp.enabled = true;
                return;
            }
        }

        try self.breakpoints.append(self.allocator, .{
            .address = address,
            .type = bp_type,
        });
    }

    /// Remove breakpoint
    pub fn removeBreakpoint(self: *Debugger, address: u16, bp_type: BreakpointType) bool {
        for (self.breakpoints.items, 0..) |bp, i| {
            if (bp.address == address and bp.type == bp_type) {
                _ = self.breakpoints.swapRemove(i);
                return true;
            }
        }
        return false;
    }

    /// Enable/disable breakpoint
    pub fn setBreakpointEnabled(self: *Debugger, address: u16, bp_type: BreakpointType, enabled: bool) bool {
        for (self.breakpoints.items) |*bp| {
            if (bp.address == address and bp.type == bp_type) {
                bp.enabled = enabled;
                return true;
            }
        }
        return false;
    }

    /// Clear all breakpoints
    pub fn clearBreakpoints(self: *Debugger) void {
        self.breakpoints.clearRetainingCapacity();
    }

    // ========================================================================
    // Watchpoint Management
    // ========================================================================

    /// Add watchpoint
    pub fn addWatchpoint(self: *Debugger, address: u16, size: u16, watch_type: Watchpoint.WatchType) !void {
        // Check if watchpoint already exists
        for (self.watchpoints.items) |*wp| {
            if (wp.address == address and wp.type == watch_type) {
                wp.enabled = true;
                wp.size = size;
                return;
            }
        }

        try self.watchpoints.append(self.allocator, .{
            .address = address,
            .size = size,
            .type = watch_type,
        });
    }

    /// Remove watchpoint
    pub fn removeWatchpoint(self: *Debugger, address: u16, watch_type: Watchpoint.WatchType) bool {
        for (self.watchpoints.items, 0..) |wp, i| {
            if (wp.address == address and wp.type == watch_type) {
                _ = self.watchpoints.swapRemove(i);
                return true;
            }
        }
        return false;
    }

    /// Clear all watchpoints
    pub fn clearWatchpoints(self: *Debugger) void {
        self.watchpoints.clearRetainingCapacity();
    }

    // ========================================================================
    // Execution Control
    // ========================================================================

    /// Continue execution
    pub fn continue_(self: *Debugger) void {
        self.mode = .running;
        self.step_state = .{};
    }

    /// Pause execution
    pub fn pause(self: *Debugger) void {
        self.mode = .paused;
    }

    /// Step one instruction
    pub fn stepInstruction(self: *Debugger) void {
        self.mode = .step_instruction;
        self.step_state = .{};
    }

    /// Step over (skip subroutines)
    pub fn stepOver(self: *Debugger, state: *const EmulationState) void {
        self.mode = .step_over;
        self.step_state = .{
            .target_pc = null,
            .initial_sp = state.cpu.sp,
        };
    }

    /// Step out (return from subroutine)
    pub fn stepOut(self: *Debugger, state: *const EmulationState) void {
        self.mode = .step_out;
        self.step_state = .{
            .initial_sp = state.cpu.sp,
        };
    }

    /// Step one scanline
    pub fn stepScanline(self: *Debugger, state: *const EmulationState) void {
        self.mode = .step_scanline;
        self.step_state = .{
            .target_scanline = (state.ppu.scanline + 1) % 262,
        };
    }

    /// Step one frame
    pub fn stepFrame(self: *Debugger, state: *const EmulationState) void {
        self.mode = .step_frame;
        self.step_state = .{
            .target_frame = state.ppu.frame + 1,
        };
    }

    // ========================================================================
    // Execution Hook (called before each instruction)
    // ========================================================================

    /// Check if should break before executing instruction
    /// Returns true if execution should pause
    pub fn shouldBreak(self: *Debugger, state: *const EmulationState) !bool {
        // Update stats
        self.stats.instructions_executed += 1;

        // Check step modes
        switch (self.mode) {
            .running => {},
            .paused => return true,
            .step_instruction => {
                self.mode = .paused;
                try self.setBreakReason("Step instruction");
                return true;
            },
            .step_over => {
                // Mark that we've executed at least one instruction
                const first_check = !self.step_state.has_stepped;
                self.step_state.has_stepped = true;

                // Don't break on first check - wait for SP to change first
                if (first_check) return false;

                // Check if we've returned to same or higher stack level
                if (state.cpu.sp >= self.step_state.initial_sp) {
                    self.mode = .paused;
                    try self.setBreakReason("Step over complete");
                    return true;
                }
            },
            .step_out => {
                // Check if stack pointer increased (returned from function)
                if (state.cpu.sp > self.step_state.initial_sp) {
                    self.mode = .paused;
                    try self.setBreakReason("Step out complete");
                    return true;
                }
            },
            .step_scanline => {
                if (self.step_state.target_scanline) |target| {
                    if (state.ppu.scanline == target) {
                        self.mode = .paused;
                        try self.setBreakReason("Scanline step complete");
                        return true;
                    }
                }
            },
            .step_frame => {
                if (self.step_state.target_frame) |target| {
                    if (state.ppu.frame >= target) {
                        self.mode = .paused;
                        try self.setBreakReason("Frame step complete");
                        return true;
                    }
                }
            },
        }

        // Check execute breakpoints
        for (self.breakpoints.items) |*bp| {
            if (!bp.enabled) continue;
            if (bp.type != .execute) continue;
            if (bp.address != state.cpu.pc) continue;

            // Check condition if present
            if (bp.condition) |condition| {
                if (!checkBreakCondition(condition, state)) continue;
            }

            bp.hit_count += 1;
            self.stats.breakpoints_hit += 1;
            self.mode = .paused;

            // ✅ Format into stack buffer (no heap allocation)
            var buf: [128]u8 = undefined;
            const reason = std.fmt.bufPrint(
                &buf,
                "Breakpoint at ${X:0>4} (hit count: {})",
                .{ bp.address, bp.hit_count },
            ) catch "Breakpoint hit";  // Fallback if buffer too small

            try self.setBreakReason(reason);

            return true;
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
        // Check read/write breakpoints
        for (self.breakpoints.items) |*bp| {
            if (!bp.enabled) continue;

            const matches = switch (bp.type) {
                .read => !is_write and bp.address == address,
                .write => is_write and bp.address == address,
                .access => bp.address == address,
                .execute => false,
            };

            if (matches) {
                bp.hit_count += 1;
                self.stats.breakpoints_hit += 1;
                self.mode = .paused;

                // ✅ Format into stack buffer (no heap allocation)
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

        // Check watchpoints
        for (self.watchpoints.items) |*wp| {
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
                self.stats.watchpoints_hit += 1;
                self.mode = .paused;

                // ✅ Format into stack buffer (no heap allocation)
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

        return false;
    }

    // ========================================================================
    // Execution History
    // ========================================================================

    /// Capture current state to history
    pub fn captureHistory(self: *Debugger, state: *const EmulationState) !void {
        // Create snapshot
        const snapshot = try Snapshot.saveBinary(
            self.allocator,
            state,
            self.config,
            .reference,
            false,
            null,
        );
        errdefer self.allocator.free(snapshot);

        const entry = HistoryEntry{
            .snapshot = snapshot,
            .pc = state.cpu.pc,
            .scanline = state.ppu.scanline,
            .frame = state.ppu.frame,
            .timestamp = std.time.timestamp(),
        };

        // Add to history
        try self.history.append(self.allocator, entry);
        self.stats.snapshots_captured += 1;

        // Remove oldest if exceeding max size
        if (self.history.items.len > self.history_max_size) {
            const oldest = self.history.orderedRemove(0);
            self.allocator.free(oldest.snapshot);
        }
    }

    /// Restore state from history
    pub fn restoreFromHistory(
        self: *Debugger,
        index: usize,
        cartridge: anytype,
    ) !EmulationState {
        if (index >= self.history.items.len) return error.InvalidHistoryIndex;

        const entry = self.history.items[index];
        return try Snapshot.loadBinary(
            self.allocator,
            entry.snapshot,
            self.config,
            cartridge,
        );
    }

    /// Clear history
    pub fn clearHistory(self: *Debugger) void {
        for (self.history.items) |entry| {
            self.allocator.free(entry.snapshot);
        }
        self.history.clearRetainingCapacity();
    }

    // ========================================================================
    // State Manipulation - CPU Registers
    // ========================================================================

    /// Set accumulator register
    pub fn setRegisterA(self: *Debugger, state: *EmulationState, value: u8) void {
        state.cpu.a = value;
        self.logModification(.{ .register_a = value });
    }

    /// Set X index register
    pub fn setRegisterX(self: *Debugger, state: *EmulationState, value: u8) void {
        state.cpu.x = value;
        self.logModification(.{ .register_x = value });
    }

    /// Set Y index register
    pub fn setRegisterY(self: *Debugger, state: *EmulationState, value: u8) void {
        state.cpu.y = value;
        self.logModification(.{ .register_y = value });
    }

    /// Set stack pointer
    pub fn setStackPointer(self: *Debugger, state: *EmulationState, value: u8) void {
        state.cpu.sp = value;
        self.logModification(.{ .stack_pointer = value });
    }

    /// Set program counter
    pub fn setProgramCounter(self: *Debugger, state: *EmulationState, value: u16) void {
        state.cpu.pc = value;
        self.logModification(.{ .program_counter = value });
    }

    /// Set individual status flag
    pub fn setStatusFlag(
        self: *Debugger,
        state: *EmulationState,
        flag: StatusFlag,
        value: bool,
    ) void {
        switch (flag) {
            .carry => state.cpu.p.carry = value,
            .zero => state.cpu.p.zero = value,
            .interrupt => state.cpu.p.interrupt = value,
            .decimal => state.cpu.p.decimal = value,
            .overflow => state.cpu.p.overflow = value,
            .negative => state.cpu.p.negative = value,
        }
        self.logModification(.{ .status_flag = .{ .flag = flag, .value = value } });
    }

    /// Set complete status register from byte
    pub fn setStatusRegister(self: *Debugger, state: *EmulationState, value: u8) void {
        state.cpu.p.carry = (value & 0x01) != 0;
        state.cpu.p.zero = (value & 0x02) != 0;
        state.cpu.p.interrupt = (value & 0x04) != 0;
        state.cpu.p.decimal = (value & 0x08) != 0;
        state.cpu.p.overflow = (value & 0x40) != 0;
        state.cpu.p.negative = (value & 0x80) != 0;
        self.logModification(.{ .status_register = value });
    }

    // ========================================================================
    // State Manipulation - Memory
    // ========================================================================

    /// Write single byte to memory (via bus)
    pub fn writeMemory(
        self: *Debugger,
        state: *EmulationState,
        address: u16,
        value: u8,
    ) void {
        state.bus.write(address, value);
        self.logModification(.{ .memory_write = .{
            .address = address,
            .value = value,
        }});
    }

    /// Write byte range to memory
    pub fn writeMemoryRange(
        self: *Debugger,
        state: *EmulationState,
        start_address: u16,
        data: []const u8,
    ) void {
        for (data, 0..) |byte, offset| {
            const addr = start_address +% @as(u16, @intCast(offset));
            state.bus.write(addr, byte);
        }
        self.logModification(.{ .memory_range = .{
            .start = start_address,
            .length = @intCast(data.len),
        }});
    }

    /// Read memory for inspection WITHOUT side effects
    /// Does not update open bus - safe for debugger inspection
    ///
    /// This uses Logic.peekMemory() which reads memory without triggering
    /// hardware side effects. This is critical for time-travel debugging:
    /// inspection reads must not corrupt the state being inspected.
    pub fn readMemory(
        self: *Debugger,
        state: *const EmulationState,
        address: u16,
    ) u8 {
        _ = self;
        const Logic = @import("../bus/Logic.zig");
        return Logic.peekMemory(&state.bus, state.bus.cartridge, state.bus.ppu, address);
    }

    /// Read memory range for inspection WITHOUT side effects
    /// Does not update open bus - safe for debugger inspection
    pub fn readMemoryRange(
        self: *Debugger,
        allocator: std.mem.Allocator,
        state: *const EmulationState,
        start_address: u16,
        length: u16,
    ) ![]u8 {
        _ = self;
        const Logic = @import("../bus/Logic.zig");
        const buffer = try allocator.alloc(u8, length);
        for (0..length) |i| {
            buffer[i] = Logic.peekMemory(
                &state.bus,
                state.bus.cartridge,
                state.bus.ppu,
                start_address +% @as(u16, @intCast(i))
            );
        }
        return buffer;
    }

    // ========================================================================
    // State Manipulation - PPU
    // ========================================================================

    /// Set PPU scanline (for testing)
    pub fn setPpuScanline(self: *Debugger, state: *EmulationState, scanline: u16) void {
        state.ppu.scanline = scanline;
        self.logModification(.{ .ppu_scanline = scanline });
    }

    /// Set PPU frame counter
    pub fn setPpuFrame(self: *Debugger, state: *EmulationState, frame: u64) void {
        state.ppu.frame = frame;
        self.logModification(.{ .ppu_frame = frame });
    }

    // ========================================================================
    // Modification Logging
    // ========================================================================

    /// Log state modification for debugging history (bounded circular buffer)
    /// Automatically removes oldest entry when max size reached
    fn logModification(self: *Debugger, modification: StateModification) void {
        // ✅ Implement circular buffer - remove oldest when full
        if (self.modifications.items.len >= self.modifications_max_size) {
            _ = self.modifications.orderedRemove(0);
        }

        self.modifications.append(self.allocator, modification) catch |err| {
            // Log error but don't fail - modification already applied
            std.debug.print("Failed to log modification: {}\n", .{err});
        };
    }

    /// Get modification history
    pub fn getModifications(self: *const Debugger) []const StateModification {
        return self.modifications.items;
    }

    /// Clear modification history
    pub fn clearModifications(self: *Debugger) void {
        self.modifications.clearRetainingCapacity();
    }

    // ========================================================================
    // Helper Functions
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
    /// No heap allocation - copies to static buffer
    fn setBreakReason(self: *Debugger, reason: []const u8) !void {
        // Copy to pre-allocated buffer instead of heap allocation
        const len = @min(reason.len, self.break_reason_buffer.len);
        @memcpy(self.break_reason_buffer[0..len], reason[0..len]);
        self.break_reason_len = len;
    }

    /// Get current break reason (returns slice into static buffer)
    pub fn getBreakReason(self: *const Debugger) ?[]const u8 {
        if (self.break_reason_len == 0) return null;
        return self.break_reason_buffer[0..self.break_reason_len];
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

    try testing.expectEqual(DebugMode.running, debugger.mode);
    try testing.expectEqual(@as(usize, 0), debugger.breakpoints.items.len);
    try testing.expectEqual(@as(usize, 0), debugger.watchpoints.items.len);
}

test "Debugger: breakpoint management" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    // Add breakpoint
    try debugger.addBreakpoint(0x8000, .execute);
    try testing.expectEqual(@as(usize, 1), debugger.breakpoints.items.len);
    try testing.expectEqual(@as(u16, 0x8000), debugger.breakpoints.items[0].address);
    try testing.expect(debugger.breakpoints.items[0].enabled);

    // Add duplicate (should not create new entry)
    try debugger.addBreakpoint(0x8000, .execute);
    try testing.expectEqual(@as(usize, 1), debugger.breakpoints.items.len);

    // Disable breakpoint
    try testing.expect(debugger.setBreakpointEnabled(0x8000, .execute, false));
    try testing.expect(!debugger.breakpoints.items[0].enabled);

    // Remove breakpoint
    try testing.expect(debugger.removeBreakpoint(0x8000, .execute));
    try testing.expectEqual(@as(usize, 0), debugger.breakpoints.items.len);

    // Remove non-existent
    try testing.expect(!debugger.removeBreakpoint(0x8000, .execute));
}

test "Debugger: watchpoint management" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    // Add watchpoint
    try debugger.addWatchpoint(0x0000, 1, .write);
    try testing.expectEqual(@as(usize, 1), debugger.watchpoints.items.len);
    try testing.expectEqual(@as(u16, 0x0000), debugger.watchpoints.items[0].address);

    // Remove watchpoint
    try testing.expect(debugger.removeWatchpoint(0x0000, .write));
    try testing.expectEqual(@as(usize, 0), debugger.watchpoints.items.len);
}

test "Debugger: execution modes" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var debugger = Debugger.init(testing.allocator, &config);
    defer debugger.deinit();

    // Initial mode
    try testing.expectEqual(DebugMode.running, debugger.mode);

    // Pause
    debugger.pause();
    try testing.expectEqual(DebugMode.paused, debugger.mode);

    // Continue
    debugger.continue_();
    try testing.expectEqual(DebugMode.running, debugger.mode);

    // Step instruction
    debugger.stepInstruction();
    try testing.expectEqual(DebugMode.step_instruction, debugger.mode);
}
