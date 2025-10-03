//! Frame Timer using libxev for precise V-sync timing
//!
//! Provides accurate frame pacing for NTSC (60.0988 Hz) and PAL (50.0070 Hz)
//! using libxev's high-resolution timer API.
//!
//! Critical for:
//! - Smooth video output
//! - Accurate light gun timing
//! - Proper audio/video sync
//! - Real-time emulation speed

const std = @import("std");
const xev = @import("xev");
const Config = @import("../config/Config.zig");
const timing = @import("../ppu/timing.zig");

/// Frame timing statistics
pub const FrameStats = struct {
    frame_count: u64 = 0,
    total_time_ns: u64 = 0,
    last_frame_ns: u64 = 0,
    avg_fps: f64 = 0.0,

    /// Update statistics with new frame timing
    pub fn update(self: *FrameStats, frame_time_ns: u64) void {
        self.frame_count += 1;
        self.total_time_ns += frame_time_ns;
        self.last_frame_ns = frame_time_ns;

        if (self.total_time_ns > 0) {
            const seconds = @as(f64, @floatFromInt(self.total_time_ns)) / 1_000_000_000.0;
            self.avg_fps = @as(f64, @floatFromInt(self.frame_count)) / seconds;
        }
    }

    /// Reset statistics
    pub fn reset(self: *FrameStats) void {
        self.* = .{};
    }
};

/// Frame timer using libxev event loop
pub const FrameTimer = struct {
    /// Target frame duration in nanoseconds
    frame_duration_ns: u64,

    /// Last frame timestamp
    last_frame_time: i128 = 0,

    /// Frame statistics
    stats: FrameStats = .{},

    /// V-sync enabled
    vsync: bool = true,

    /// Initialize frame timer with configuration
    pub fn init(config: Config.PpuConfig, vsync: bool) FrameTimer {
        const frame_ns = switch (config.variant) {
            .rp2c02g_ntsc => timing.NTSC.FRAME_DURATION_NS,
            .rp2c07_pal => timing.PAL.FRAME_DURATION_NS,
        };

        return .{
            .frame_duration_ns = frame_ns,
            .vsync = vsync,
        };
    }

    /// Wait for next frame (blocks until frame time elapsed)
    pub fn waitForNextFrame(self: *FrameTimer) void {
        if (!self.vsync) {
            // No V-sync: immediate return
            return;
        }

        const now = std.time.nanoTimestamp();

        if (self.last_frame_time == 0) {
            // First frame: just record timestamp
            self.last_frame_time = now;
            return;
        }

        const elapsed = @as(u64, @intCast(now - self.last_frame_time));

        if (elapsed < self.frame_duration_ns) {
            // Sleep for remaining time
            const sleep_ns = self.frame_duration_ns - elapsed;
            std.Thread.sleep(sleep_ns);
        }

        // Update timestamp
        const frame_end = std.time.nanoTimestamp();
        const actual_frame_time = @as(u64, @intCast(frame_end - self.last_frame_time));
        self.stats.update(actual_frame_time);
        self.last_frame_time = frame_end;
    }

    /// Get current FPS
    pub fn getCurrentFps(self: *const FrameTimer) f64 {
        return self.stats.avg_fps;
    }

    /// Get frame count
    pub fn getFrameCount(self: *const FrameTimer) u64 {
        return self.stats.frame_count;
    }

    /// Reset timer
    pub fn reset(self: *FrameTimer) void {
        self.last_frame_time = 0;
        self.stats.reset();
    }
};

/// Callback-based frame timer using libxev (for async operation)
pub const AsyncFrameTimer = struct {
    /// libxev loop reference
    loop: *xev.Loop,

    /// Timer handle
    timer: xev.Timer,

    /// Frame duration in nanoseconds
    frame_duration_ns: u64,

    /// Frame callback
    callback: *const fn (userdata: ?*anyopaque) void,
    userdata: ?*anyopaque,

    /// Statistics
    stats: FrameStats = .{},

    /// Initialize async frame timer
    pub fn init(
        loop: *xev.Loop,
        config: Config.PpuConfig,
        callback: *const fn (userdata: ?*anyopaque) void,
        userdata: ?*anyopaque,
    ) !AsyncFrameTimer {
        const frame_ns = switch (config.variant) {
            .rp2c02g_ntsc => timing.NTSC.FRAME_DURATION_NS,
            .rp2c07_pal => timing.PAL.FRAME_DURATION_NS,
        };

        return .{
            .loop = loop,
            .timer = try xev.Timer.init(),
            .frame_duration_ns = frame_ns,
            .callback = callback,
            .userdata = userdata,
        };
    }

    /// Start periodic frame timer
    pub fn start(self: *AsyncFrameTimer) !void {
        const ns_per_ms = 1_000_000;
        const timeout_ms = self.frame_duration_ns / ns_per_ms;

        var completion: xev.Completion = undefined;
        self.timer.run(self.loop, &completion, timeout_ms, AsyncFrameTimer, self, timerCallback);
    }

    /// Timer callback (called by libxev)
    fn timerCallback(
        userdata: ?*AsyncFrameTimer,
        loop: *xev.Loop,
        completion: *xev.Completion,
        result: xev.Timer.RunError!void,
    ) xev.CallbackAction {
        _ = result catch |err| {
            std.log.err("Frame timer error: {}", .{err});
            return .disarm;
        };

        const self = userdata orelse return .disarm;

        // Call frame callback
        self.callback(self.userdata);
        self.stats.frame_count += 1;

        // Rearm timer for next frame
        const ns_per_ms = 1_000_000;
        const timeout_ms = self.frame_duration_ns / ns_per_ms;
        self.timer.run(loop, completion, timeout_ms, AsyncFrameTimer, self, timerCallback);

        return .rearm;
    }

    /// Stop timer
    pub fn stop(self: *AsyncFrameTimer) void {
        self.timer.deinit();
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "FrameTimer: NTSC initialization" {
    const config = Config.PpuConfig{
        .variant = .rp2c02g_ntsc,
        .region = .ntsc,
    };

    const timer = FrameTimer.init(config, true);
    try testing.expectEqual(timing.NTSC.FRAME_DURATION_NS, timer.frame_duration_ns);
    try testing.expect(timer.vsync);
}

test "FrameTimer: PAL initialization" {
    const config = Config.PpuConfig{
        .variant = .rp2c07_pal,
        .region = .pal,
    };

    const timer = FrameTimer.init(config, true);
    try testing.expectEqual(timing.PAL.FRAME_DURATION_NS, timer.frame_duration_ns);
}

test "FrameTimer: statistics update" {
    var stats = FrameStats{};

    stats.update(16_639_267); // One NTSC frame
    try testing.expectEqual(@as(u64, 1), stats.frame_count);
    try testing.expectEqual(@as(u64, 16_639_267), stats.last_frame_ns);

    stats.update(16_639_267); // Another frame
    try testing.expectEqual(@as(u64, 2), stats.frame_count);
    try testing.expectApproxEqAbs(@as(f64, 60.0), stats.avg_fps, 1.0);
}

test "FrameTimer: no vsync returns immediately" {
    const config = Config.PpuConfig{
        .variant = .rp2c02g_ntsc,
        .region = .ntsc,
    };

    var timer = FrameTimer.init(config, false);

    const start = std.time.nanoTimestamp();
    timer.waitForNextFrame();
    const elapsed = std.time.nanoTimestamp() - start;

    // Should return almost immediately
    try testing.expect(elapsed < 1_000_000); // Less than 1ms
}
