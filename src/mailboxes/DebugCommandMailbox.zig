//! Debug Command Mailbox - Main Thread → Emulation Thread
//!
//! Allows main thread to send debugging commands to the emulation thread.
//! Uses ring buffer for lock-free SPSC communication.

const std = @import("std");
const DebuggerMod = @import("../debugger/Debugger.zig");

/// Debug commands that can be sent to the emulation thread
pub const DebugCommand = union(enum) {
    /// Add execute breakpoint at address
    add_breakpoint: struct {
        address: u16,
        bp_type: DebuggerMod.BreakpointType,
    },

    /// Remove breakpoint at address
    remove_breakpoint: struct {
        address: u16,
        bp_type: DebuggerMod.BreakpointType,
    },

    /// Add memory watchpoint
    add_watchpoint: struct {
        address: u16,
        size: u16,
        watch_type: DebuggerMod.Watchpoint.WatchType,
    },

    /// Remove watchpoint at address
    remove_watchpoint: struct {
        address: u16,
        watch_type: DebuggerMod.Watchpoint.WatchType,
    },

    /// Pause emulation
    pause,

    /// Resume emulation (continue execution)
    resume_execution,

    /// Step one instruction (single-step)
    step_instruction,

    /// Step one frame
    step_frame,

    /// Request state inspection (triggers InspectResponse event)
    inspect,

    /// Clear all breakpoints
    clear_breakpoints,

    /// Clear all watchpoints
    clear_watchpoints,

    /// Enable/disable breakpoint
    set_breakpoint_enabled: struct {
        address: u16,
        bp_type: DebuggerMod.BreakpointType,
        enabled: bool,
    },
};

/// Ring buffer for debug commands
pub const DebugCommandMailbox = struct {
    /// Ring buffer storage (64 commands max)
    buffer: [64]?DebugCommand = [_]?DebugCommand{null} ** 64,

    /// Write position (producer)
    write_pos: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

    /// Read position (consumer)
    read_pos: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

    pub fn init() DebugCommandMailbox {
        return .{};
    }

    /// Post command to mailbox (main thread - producer)
    /// Returns false if buffer is full
    pub fn postCommand(self: *DebugCommandMailbox, command: DebugCommand) bool {
        const write = self.write_pos.load(.acquire);
        const read = self.read_pos.load(.acquire);

        // Check if buffer is full
        const next_write = (write + 1) % 64;
        if (next_write == read) {
            return false; // Buffer full
        }

        // Write command
        self.buffer[write] = command;

        // Update write position
        self.write_pos.store(next_write, .release);

        return true;
    }

    /// Poll command from mailbox (emulation thread - consumer)
    /// Returns null if no commands available
    pub fn pollCommand(self: *DebugCommandMailbox) ?DebugCommand {
        const read = self.read_pos.load(.acquire);
        const write = self.write_pos.load(.acquire);

        // Check if buffer is empty
        if (read == write) {
            return null;
        }

        // Read command
        const command = self.buffer[read];

        // Clear slot
        self.buffer[read] = null;

        // Update read position
        self.read_pos.store((read + 1) % 64, .release);

        return command;
    }

    /// Check if commands are available without consuming
    pub fn hasCommands(self: *const DebugCommandMailbox) bool {
        const read = self.read_pos.load(.acquire);
        const write = self.write_pos.load(.acquire);
        return read != write;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "DebugCommandMailbox: init" {
    var mailbox = DebugCommandMailbox.init();
    try testing.expect(!mailbox.hasCommands());
}

test "DebugCommandMailbox: post and poll command" {
    var mailbox = DebugCommandMailbox.init();

    // Post command
    const posted = mailbox.postCommand(.{ .add_breakpoint = .{ .address = 0x8000, .bp_type = .execute } });
    try testing.expect(posted);
    try testing.expect(mailbox.hasCommands());

    // Poll command
    const cmd = mailbox.pollCommand();
    try testing.expect(cmd != null);
    try testing.expect(cmd.?.add_breakpoint.address == 0x8000);
    try testing.expect(!mailbox.hasCommands());
}

test "DebugCommandMailbox: multiple commands" {
    var mailbox = DebugCommandMailbox.init();

    // Post multiple commands
    _ = mailbox.postCommand(.pause);
    _ = mailbox.postCommand(.{ .add_breakpoint = .{ .address = 0x8000, .bp_type = .execute } });
    _ = mailbox.postCommand(.resume_execution);

    // Poll in order
    const cmd1 = mailbox.pollCommand();
    try testing.expect(cmd1 != null);
    try testing.expect(cmd1.? == .pause);

    const cmd2 = mailbox.pollCommand();
    try testing.expect(cmd2 != null);
    try testing.expect(cmd2.?.add_breakpoint.address == 0x8000);

    const cmd3 = mailbox.pollCommand();
    try testing.expect(cmd3 != null);
    try testing.expect(cmd3.? == .resume_execution);

    try testing.expect(!mailbox.hasCommands());
}

test "DebugCommandMailbox: buffer full" {
    var mailbox = DebugCommandMailbox.init();

    // Fill buffer (63 commands max, one slot reserved)
    var i: usize = 0;
    while (i < 63) : (i += 1) {
        const posted = mailbox.postCommand(.pause);
        try testing.expect(posted);
    }

    // 64th command should fail
    const posted = mailbox.postCommand(.pause);
    try testing.expect(!posted);
}
