//! Configuration Update Mailbox
//!
//! Single-value mailbox for emulation configuration updates
//! Main thread posts config changes, emulation thread consumes them
//!
//! Configuration includes:
//! - Emulation speed (NTSC/PAL/custom Hz)
//! - Pause/Resume state
//! - Reset signal

const std = @import("std");

/// Emulation configuration update
pub const ConfigUpdate = union(enum) {
    /// Change emulation speed (Hz)
    set_speed: struct {
        ppu_hz: u64, // PPU clock frequency (NTSC: 5_369_318 Hz)
    },

    /// Pause emulation
    pause: void,

    /// Resume emulation (unpause)
    unpause: void,

    /// Reset emulator (like pressing NES reset button)
    reset: void,

    /// Power cycle (full reinitialize)
    power_cycle: void,
};

/// Single-value config mailbox
pub const ConfigMailbox = struct {
    /// Pending configuration update (optional)
    pending: ?ConfigUpdate = null,

    /// Mutex to protect pending value
    mutex: std.Thread.Mutex = .{},

    /// Initialize mailbox
    pub fn init(allocator: std.mem.Allocator) ConfigMailbox {
        _ = allocator;
        return .{};
    }

    /// Cleanup mailbox
    pub fn deinit(self: *ConfigMailbox) void {
        _ = self;
    }

    /// Post configuration update (called by main thread)
    /// Overwrites previous pending update if not yet consumed
    pub fn postUpdate(self: *ConfigMailbox, update: ConfigUpdate) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.pending = update;
    }

    /// Poll for configuration update (called by emulation thread)
    /// Returns update and clears pending state
    pub fn pollUpdate(self: *ConfigMailbox) ?ConfigUpdate {
        self.mutex.lock();
        defer self.mutex.unlock();

        const update = self.pending;
        self.pending = null;
        return update;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ConfigMailbox: basic post and poll" {
    const allocator = std.testing.allocator;

    var mailbox = ConfigMailbox.init(allocator);
    defer mailbox.deinit();

    // Post config update
    mailbox.postUpdate(.{ .set_speed = .{ .ppu_hz = 5_369_318 } });

    // Poll should return the update
    const update = mailbox.pollUpdate();
    try std.testing.expect(update != null);
    try std.testing.expectEqual(@as(u64, 5_369_318), update.?.set_speed.ppu_hz);

    // Second poll should return null
    const update2 = mailbox.pollUpdate();
    try std.testing.expect(update2 == null);
}

test "ConfigMailbox: overwrite pending" {
    const allocator = std.testing.allocator;

    var mailbox = ConfigMailbox.init(allocator);
    defer mailbox.deinit();

    // Post pause
    mailbox.postUpdate(.pause);

    // Overwrite with unpause
    mailbox.postUpdate(.unpause);

    // Should only get unpause
    const update = mailbox.pollUpdate();
    try std.testing.expect(update != null);
    try std.testing.expect(update.? == .unpause);
}
