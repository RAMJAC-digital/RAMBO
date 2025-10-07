//! Emulation Command Mailbox
//!
//! Lock-free SPSC command queue for emulation lifecycle control
//! Main thread (producer) posts commands, emulation thread (consumer) polls
//!
//! Commands: power_on, reset, pause, resume, save_state, load_state, shutdown

const std = @import("std");
const SpscRingBuffer = @import("SpscRingBuffer.zig").SpscRingBuffer;

/// Emulation lifecycle commands
pub const EmulationCommand = enum {
    power_on,         // Cold boot
    reset,            // Warm reset (NES reset button)
    pause_emulation,  // Pause emulation
    resume_emulation, // Resume emulation
    save_state,       // Trigger snapshot save
    load_state,       // Trigger snapshot load
    shutdown,         // Clean shutdown
};

/// Lock-free SPSC command mailbox
pub const EmulationCommandMailbox = struct {
    /// Lock-free ring buffer (16 commands max)
    buffer: SpscRingBuffer(EmulationCommand, 16),

    /// Initialize mailbox
    pub fn init(allocator: std.mem.Allocator) EmulationCommandMailbox {
        _ = allocator;
        return .{
            .buffer = SpscRingBuffer(EmulationCommand, 16).init(),
        };
    }

    /// Cleanup mailbox
    pub fn deinit(self: *EmulationCommandMailbox) void {
        _ = self;
    }

    /// Post command to queue (called by main thread - producer)
    /// Returns error if buffer is full
    pub fn postCommand(self: *EmulationCommandMailbox, command: EmulationCommand) !void {
        if (!self.buffer.push(command)) {
            return error.BufferFull;
        }
    }

    /// Poll next command from queue (called by emulation thread - consumer)
    /// Returns null if queue is empty
    pub fn pollCommand(self: *EmulationCommandMailbox) ?EmulationCommand {
        return self.buffer.pop();
    }

    /// Check if queue has pending commands (lock-free)
    pub fn hasPendingCommands(self: *const EmulationCommandMailbox) bool {
        return !self.buffer.isEmpty();
    }

    /// Get count of pending commands (approximate for concurrent use)
    pub fn pendingCount(self: *const EmulationCommandMailbox) usize {
        return self.buffer.len();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "EmulationCommandMailbox: basic post and poll" {
    const allocator = std.testing.allocator;

    var mailbox = EmulationCommandMailbox.init(allocator);
    defer mailbox.deinit();

    // Queue should start empty
    try std.testing.expect(mailbox.pollCommand() == null);

    // Post a command
    try mailbox.postCommand(.reset);

    // Poll should return the command
    const cmd = mailbox.pollCommand();
    try std.testing.expect(cmd != null);
    try std.testing.expectEqual(EmulationCommand.reset, cmd.?);

    // Queue should be empty again
    try std.testing.expect(mailbox.pollCommand() == null);
}

test "EmulationCommandMailbox: FIFO ordering" {
    const allocator = std.testing.allocator;

    var mailbox = EmulationCommandMailbox.init(allocator);
    defer mailbox.deinit();

    // Post multiple commands
    try mailbox.postCommand(.power_on);
    try mailbox.postCommand(.pause_emulation);
    try mailbox.postCommand(.resume_emulation);

    // Should return in FIFO order
    try std.testing.expectEqual(EmulationCommand.power_on, mailbox.pollCommand().?);
    try std.testing.expectEqual(EmulationCommand.pause_emulation, mailbox.pollCommand().?);
    try std.testing.expectEqual(EmulationCommand.resume_emulation, mailbox.pollCommand().?);
    try std.testing.expect(mailbox.pollCommand() == null);
}

test "EmulationCommandMailbox: hasPendingCommands" {
    const allocator = std.testing.allocator;

    var mailbox = EmulationCommandMailbox.init(allocator);
    defer mailbox.deinit();

    // Should start with no pending commands
    try std.testing.expect(!mailbox.hasPendingCommands());

    // Post command
    try mailbox.postCommand(.save_state);
    try std.testing.expect(mailbox.hasPendingCommands());

    // Poll command
    _ = mailbox.pollCommand();
    try std.testing.expect(!mailbox.hasPendingCommands());
}

test "EmulationCommandMailbox: all command types" {
    const allocator = std.testing.allocator;

    var mailbox = EmulationCommandMailbox.init(allocator);
    defer mailbox.deinit();

    // Test all command types
    const commands = [_]EmulationCommand{
        .power_on,
        .reset,
        .pause_emulation,
        .resume_emulation,
        .save_state,
        .load_state,
        .shutdown,
    };

    for (commands) |cmd| {
        try mailbox.postCommand(cmd);
    }

    for (commands) |expected_cmd| {
        const polled = mailbox.pollCommand();
        try std.testing.expect(polled != null);
        try std.testing.expectEqual(expected_cmd, polled.?);
    }
}

test "EmulationCommandMailbox: multiple post and poll cycles" {
    const allocator = std.testing.allocator;

    var mailbox = EmulationCommandMailbox.init(allocator);
    defer mailbox.deinit();

    // Cycle 1
    try mailbox.postCommand(.power_on);
    try std.testing.expectEqual(EmulationCommand.power_on, mailbox.pollCommand().?);

    // Cycle 2
    try mailbox.postCommand(.reset);
    try mailbox.postCommand(.pause_emulation);
    try std.testing.expectEqual(EmulationCommand.reset, mailbox.pollCommand().?);
    try std.testing.expectEqual(EmulationCommand.pause_emulation, mailbox.pollCommand().?);

    // Queue should be empty
    try std.testing.expect(mailbox.pollCommand() == null);
}
