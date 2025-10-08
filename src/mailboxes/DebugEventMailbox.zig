//! Debug Event Mailbox - Emulation Thread → Main Thread
//!
//! Allows emulation thread to send debug events to the main thread.
//! Uses ring buffer for lock-free SPSC communication.

const std = @import("std");

/// CPU state snapshot for inspection
pub const CpuSnapshot = struct {
    a: u8,
    x: u8,
    y: u8,
    sp: u8,
    pc: u16,
    p: u8, // Status register as byte
    cycle: u64,
    frame: u64,
};

/// Debug events sent from emulation thread
pub const DebugEvent = union(enum) {
    /// Breakpoint was hit
    breakpoint_hit: struct {
        reason: [128]u8, // Break reason string (stack buffer from debugger)
        reason_len: usize,
        snapshot: CpuSnapshot,
    },

    /// Watchpoint was hit
    watchpoint_hit: struct {
        reason: [128]u8,
        reason_len: usize,
        snapshot: CpuSnapshot,
    },

    /// State inspection response
    inspect_response: struct {
        snapshot: CpuSnapshot,
    },

    /// Emulation paused
    paused: struct {
        snapshot: CpuSnapshot,
    },

    /// Emulation resumed
    resumed,

    /// Breakpoint added successfully
    breakpoint_added: struct {
        address: u16,
    },

    /// Breakpoint removed successfully
    breakpoint_removed: struct {
        address: u16,
    },

    /// Error occurred
    error_occurred: struct {
        message: [128]u8,
        message_len: usize,
    },
};

/// Ring buffer for debug events
pub const DebugEventMailbox = struct {
    /// Ring buffer storage (32 events max)
    buffer: [32]?DebugEvent = [_]?DebugEvent{null} ** 32,

    /// Write position (producer - emulation thread)
    write_pos: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

    /// Read position (consumer - main thread)
    read_pos: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

    pub fn init() DebugEventMailbox {
        return .{};
    }

    /// Post event to mailbox (emulation thread - producer)
    /// Returns false if buffer is full
    pub fn postEvent(self: *DebugEventMailbox, event: DebugEvent) bool {
        const write = self.write_pos.load(.acquire);
        const read = self.read_pos.load(.acquire);

        // Check if buffer is full
        const next_write = (write + 1) % 32;
        if (next_write == read) {
            return false; // Buffer full
        }

        // Write event
        self.buffer[write] = event;

        // Update write position
        self.write_pos.store(next_write, .release);

        return true;
    }

    /// Poll event from mailbox (main thread - consumer)
    /// Returns null if no events available
    pub fn pollEvent(self: *DebugEventMailbox) ?DebugEvent {
        const read = self.read_pos.load(.acquire);
        const write = self.write_pos.load(.acquire);

        // Check if buffer is empty
        if (read == write) {
            return null;
        }

        // Read event
        const event = self.buffer[read];

        // Clear slot
        self.buffer[read] = null;

        // Update read position
        self.read_pos.store((read + 1) % 32, .release);

        return event;
    }

    /// Check if events are available without consuming
    pub fn hasEvents(self: *const DebugEventMailbox) bool {
        const read = self.read_pos.load(.acquire);
        const write = self.write_pos.load(.acquire);
        return read != write;
    }

    /// Drain all events into a buffer (for batch processing)
    /// Returns number of events drained
    pub fn drainEvents(self: *DebugEventMailbox, out_buffer: []DebugEvent) usize {
        var count: usize = 0;
        while (count < out_buffer.len) {
            const event = self.pollEvent() orelse break;
            out_buffer[count] = event;
            count += 1;
        }
        return count;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "DebugEventMailbox: init" {
    var mailbox = DebugEventMailbox.init();
    try testing.expect(!mailbox.hasEvents());
}

test "DebugEventMailbox: post and poll event" {
    var mailbox = DebugEventMailbox.init();

    const snapshot = CpuSnapshot{
        .a = 0x42,
        .x = 0x10,
        .y = 0x20,
        .sp = 0xFD,
        .pc = 0x8000,
        .p = 0x24,
        .cycle = 1000,
        .frame = 10,
    };

    // Post event
    const posted = mailbox.postEvent(.{ .inspect_response = .{ .snapshot = snapshot } });
    try testing.expect(posted);
    try testing.expect(mailbox.hasEvents());

    // Poll event
    const event = mailbox.pollEvent();
    try testing.expect(event != null);
    try testing.expect(event.? == .inspect_response);
    try testing.expectEqual(@as(u8, 0x42), event.?.inspect_response.snapshot.a);
    try testing.expect(!mailbox.hasEvents());
}

test "DebugEventMailbox: drain events" {
    var mailbox = DebugEventMailbox.init();

    const snapshot = CpuSnapshot{
        .a = 0,
        .x = 0,
        .y = 0,
        .sp = 0xFD,
        .pc = 0x8000,
        .p = 0,
        .cycle = 0,
        .frame = 0,
    };

    // Post multiple events
    _ = mailbox.postEvent(.resumed);
    _ = mailbox.postEvent(.{ .inspect_response = .{ .snapshot = snapshot } });
    _ = mailbox.postEvent(.{ .paused = .{ .snapshot = snapshot } });

    // Drain all events
    var buffer: [32]DebugEvent = undefined;
    const count = mailbox.drainEvents(&buffer);

    try testing.expectEqual(@as(usize, 3), count);
    try testing.expect(buffer[0] == .resumed);
    try testing.expect(buffer[1] == .inspect_response);
    try testing.expect(buffer[2] == .paused);
    try testing.expect(!mailbox.hasEvents());
}

test "DebugEventMailbox: buffer full" {
    var mailbox = DebugEventMailbox.init();

    // Fill buffer (31 events max, one slot reserved)
    var i: usize = 0;
    while (i < 31) : (i += 1) {
        const posted = mailbox.postEvent(.resumed);
        try testing.expect(posted);
    }

    // 32nd event should fail
    const posted = mailbox.postEvent(.resumed);
    try testing.expect(!posted);
}
