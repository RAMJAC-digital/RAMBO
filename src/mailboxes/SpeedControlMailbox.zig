//! Speed Control Mailbox
//!
//! Atomic mailbox for emulation speed and timing configuration
//! Main thread posts speed updates, emulation thread polls for changes
//!
//! Supports: realtime, fast-forward, slow-motion, paused, stepping modes
//! Timing variants: NTSC (60.0988 Hz), PAL (50.007 Hz)

const std = @import("std");

/// Speed control modes
pub const SpeedMode = enum {
    realtime,      // Normal speed (1.0×)
    fast_forward,  // Accelerated (2×, 4×, unlimited)
    slow_motion,   // Decelerated (0.5×, 0.25×)
    paused,        // Emulation halted
    stepping,      // Single-step execution (frame/instruction/scanline)
};

/// Timing variant (PAL vs NTSC)
pub const TimingVariant = enum {
    ntsc,  // 60.0988 Hz (1.789773 MHz CPU, 5.369318 MHz PPU)
    pal,   // 50.007 Hz (1.662607 MHz CPU, 5.320214 MHz PPU)
};

/// Speed control configuration
pub const SpeedControlConfig = struct {
    mode: SpeedMode = .realtime,
    timing: TimingVariant = .ntsc,
    speed_multiplier: f64 = 1.0,  // 1.0 = realtime, 2.0 = 2×, etc.
    hard_sync: bool = true,       // Sync to wall clock
};

/// Atomic speed control mailbox with lock-free flag
pub const SpeedControlMailbox = struct {
    /// Pending configuration (write-only by main thread)
    pending: SpeedControlConfig,

    /// Active configuration (read-only by emulation thread)
    active: SpeedControlConfig,

    /// Mutex to protect config updates
    mutex: std.Thread.Mutex = .{},

    /// Atomic flag indicating update is pending
    has_update: std.atomic.Value(bool) = .{ .raw = false },

    /// Initialize mailbox with default configuration
    pub fn init(allocator: std.mem.Allocator) SpeedControlMailbox {
        _ = allocator;
        return .{
            .pending = .{},
            .active = .{},
        };
    }

    /// Cleanup mailbox
    pub fn deinit(self: *SpeedControlMailbox) void {
        _ = self;
    }

    /// Post speed configuration update (called by main thread)
    pub fn postUpdate(self: *SpeedControlMailbox, config: SpeedControlConfig) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.pending = config;
        self.has_update.store(true, .release);
    }

    /// Poll for configuration updates (called by emulation thread)
    /// Returns updated config if available, null otherwise
    pub fn pollUpdate(self: *SpeedControlMailbox) ?SpeedControlConfig {
        if (!self.has_update.load(.acquire)) {
            return null;
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        self.has_update.store(false, .release);
        self.active = self.pending;
        return self.active;
    }

    /// Get current active configuration (non-blocking read)
    pub fn getActiveConfig(self: *SpeedControlMailbox) SpeedControlConfig {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.active;
    }

    /// Check if update is pending (lock-free)
    pub fn hasUpdate(self: *const SpeedControlMailbox) bool {
        return self.has_update.load(.acquire);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "SpeedControlMailbox: basic post and poll" {
    const allocator = std.testing.allocator;

    var mailbox = SpeedControlMailbox.init(allocator);
    defer mailbox.deinit();

    // Should start with no update
    try std.testing.expect(mailbox.pollUpdate() == null);
    try std.testing.expect(!mailbox.hasUpdate());

    // Post an update
    mailbox.postUpdate(.{
        .mode = .fast_forward,
        .speed_multiplier = 2.0,
        .timing = .ntsc,
        .hard_sync = true,
    });

    // Should have update flag set
    try std.testing.expect(mailbox.hasUpdate());

    // Poll should return the update
    const config = mailbox.pollUpdate();
    try std.testing.expect(config != null);
    try std.testing.expectEqual(SpeedMode.fast_forward, config.?.mode);
    try std.testing.expectEqual(@as(f64, 2.0), config.?.speed_multiplier);

    // Update should be consumed
    try std.testing.expect(!mailbox.hasUpdate());
    try std.testing.expect(mailbox.pollUpdate() == null);
}

test "SpeedControlMailbox: latest value wins" {
    const allocator = std.testing.allocator;

    var mailbox = SpeedControlMailbox.init(allocator);
    defer mailbox.deinit();

    // Post multiple updates
    mailbox.postUpdate(.{ .mode = .realtime, .speed_multiplier = 1.0, .timing = .ntsc, .hard_sync = true });
    mailbox.postUpdate(.{ .mode = .fast_forward, .speed_multiplier = 4.0, .timing = .ntsc, .hard_sync = false });

    // Should get only the latest
    const config = mailbox.pollUpdate();
    try std.testing.expect(config != null);
    try std.testing.expectEqual(SpeedMode.fast_forward, config.?.mode);
    try std.testing.expectEqual(@as(f64, 4.0), config.?.speed_multiplier);
}

test "SpeedControlMailbox: all speed modes" {
    const allocator = std.testing.allocator;

    var mailbox = SpeedControlMailbox.init(allocator);
    defer mailbox.deinit();

    const modes = [_]SpeedMode{
        .realtime,
        .fast_forward,
        .slow_motion,
        .paused,
        .stepping,
    };

    for (modes) |mode| {
        mailbox.postUpdate(.{ .mode = mode, .timing = .ntsc, .speed_multiplier = 1.0, .hard_sync = true });
        const config = mailbox.pollUpdate();
        try std.testing.expect(config != null);
        try std.testing.expectEqual(mode, config.?.mode);
    }
}

test "SpeedControlMailbox: PAL vs NTSC" {
    const allocator = std.testing.allocator;

    var mailbox = SpeedControlMailbox.init(allocator);
    defer mailbox.deinit();

    // NTSC
    mailbox.postUpdate(.{ .mode = .realtime, .timing = .ntsc, .speed_multiplier = 1.0, .hard_sync = true });
    var config = mailbox.pollUpdate();
    try std.testing.expectEqual(TimingVariant.ntsc, config.?.timing);

    // PAL
    mailbox.postUpdate(.{ .mode = .realtime, .timing = .pal, .speed_multiplier = 1.0, .hard_sync = true });
    config = mailbox.pollUpdate();
    try std.testing.expectEqual(TimingVariant.pal, config.?.timing);
}

test "SpeedControlMailbox: hard sync control" {
    const allocator = std.testing.allocator;

    var mailbox = SpeedControlMailbox.init(allocator);
    defer mailbox.deinit();

    // Hard sync enabled
    mailbox.postUpdate(.{ .mode = .realtime, .timing = .ntsc, .speed_multiplier = 1.0, .hard_sync = true });
    var config = mailbox.pollUpdate();
    try std.testing.expect(config.?.hard_sync == true);

    // Hard sync disabled
    mailbox.postUpdate(.{ .mode = .fast_forward, .timing = .ntsc, .speed_multiplier = 2.0, .hard_sync = false });
    config = mailbox.pollUpdate();
    try std.testing.expect(config.?.hard_sync == false);
}

test "SpeedControlMailbox: getActiveConfig" {
    const allocator = std.testing.allocator;

    var mailbox = SpeedControlMailbox.init(allocator);
    defer mailbox.deinit();

    // Default config
    var active = mailbox.getActiveConfig();
    try std.testing.expectEqual(SpeedMode.realtime, active.mode);

    // Post and poll update
    mailbox.postUpdate(.{ .mode = .fast_forward, .timing = .ntsc, .speed_multiplier = 4.0, .hard_sync = true });
    _ = mailbox.pollUpdate();

    // Active config should be updated
    active = mailbox.getActiveConfig();
    try std.testing.expectEqual(SpeedMode.fast_forward, active.mode);
    try std.testing.expectEqual(@as(f64, 4.0), active.speed_multiplier);
}
