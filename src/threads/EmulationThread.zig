//! Emulation Thread Module
//!
//! Timer-driven RT-safe emulation loop running on dedicated thread
//! Communicates with main thread via lock-free mailboxes
//!
//! Architecture:
//! - Own libxev event loop for timer scheduling
//! - Frame-based timer (60.0988 Hz NTSC, 50 Hz PAL)
//! - Polls command/input mailboxes (SPSC consumer)
//! - Posts frames and status updates (SPSC producer)
//! - Fully deterministic, reproducible execution

const std = @import("std");
const xev = @import("xev");
const EmulationState = @import("../emulation/State.zig").EmulationState;
const Mailboxes = @import("../mailboxes/Mailboxes.zig").Mailboxes;
const EmulationCommand = @import("../mailboxes/EmulationCommandMailbox.zig").EmulationCommand;

/// Context passed to timer callback
/// Contains all state needed for emulation loop
pub const EmulationContext = struct {
    /// Emulation state (CPU, PPU, APU, Bus, Cartridge)
    state: *EmulationState,

    /// Mailbox container for thread communication
    mailboxes: *Mailboxes,

    /// Atomic running flag (shared with main thread)
    running: *std.atomic.Value(bool),

    /// Frame counter for FPS reporting
    frame_count: u64 = 0,

    /// Total cycles executed (for diagnostics)
    total_cycles: u64 = 0,

    /// Last time we reported FPS (nanoseconds)
    last_report_time: i128 = 0,

    /// Whether we've printed the shutdown message
    shutdown_printed: bool = false,
};

/// Thread configuration
pub const ThreadConfig = struct {
    /// Frame duration in nanoseconds (NTSC: 16,639,267 ns)
    frame_duration_ns: u64 = 16_639_267,

    /// FPS reporting interval in nanoseconds (default: 1 second)
    report_interval_ns: i128 = 1_000_000_000,

    /// Enable verbose logging
    verbose: bool = false,
};

/// Timer callback for frame-based emulation
/// Executes one frame of emulation and rearms timer
fn timerCallback(
    userdata: ?*EmulationContext,
    loop: *xev.Loop,
    completion: *xev.Completion,
    result: xev.Timer.RunError!void,
) xev.CallbackAction {
    _ = result catch |err| {
        std.debug.print("[Emulation] Timer error: {}\n", .{err});
        return .disarm;
    };

    const ctx = userdata orelse return .disarm;

    // Check for shutdown signal
    if (!ctx.running.load(.acquire)) {
        if (!ctx.shutdown_printed) {
            std.debug.print("[Emulation] Shutdown signal received (frames: {d}, cycles: {d})\n", .{
                ctx.frame_count,
                ctx.total_cycles,
            });
            ctx.shutdown_printed = true;
        }
        return .disarm;
    }

    // Process emulation commands (non-blocking poll)
    while (ctx.mailboxes.emulation_command.pollCommand()) |command| {
        handleCommand(ctx, command);
    }

    // TODO: Poll controller input mailbox and update state

    // TODO: Poll speed control mailbox for speed changes

    // Emulate one frame (cycle-accurate execution)
    const cycles = ctx.state.emulateFrame();
    ctx.total_cycles += cycles;
    ctx.frame_count += 1;

    // Post completed frame to render thread
    ctx.mailboxes.frame.swapBuffers();

    // TODO: Post emulation status updates (if state changed)

    // FPS reporting (periodic diagnostics)
    reportProgress(ctx);

    // Rearm timer for next frame
    const frame_duration_ms: u64 = 16_639_267 / 1_000_000; // ~16.6ms
    var timer = xev.Timer{};
    timer.run(loop, completion, frame_duration_ms, EmulationContext, ctx, timerCallback);

    return .rearm;
}

/// Handle emulation lifecycle commands
fn handleCommand(ctx: *EmulationContext, command: EmulationCommand) void {
    switch (command) {
        .power_on => {
            std.debug.print("[Emulation] Command: Power On\n", .{});
            // Reset state to power-on defaults
            ctx.state.reset();
            ctx.frame_count = 0;
            ctx.total_cycles = 0;
        },
        .reset => {
            std.debug.print("[Emulation] Command: Reset\n", .{});
            // Warm reset (like pressing reset button)
            ctx.state.reset();
        },
        .pause_emulation => {
            std.debug.print("[Emulation] Command: Pause (not yet implemented)\n", .{});
            // TODO: Set paused flag, stop timer
        },
        .resume_emulation => {
            std.debug.print("[Emulation] Command: Resume (not yet implemented)\n", .{});
            // TODO: Clear paused flag, restart timer
        },
        .save_state => {
            std.debug.print("[Emulation] Command: Save State (not yet implemented)\n", .{});
            // TODO: Serialize state to snapshot
        },
        .load_state => {
            std.debug.print("[Emulation] Command: Load State (not yet implemented)\n", .{});
            // TODO: Deserialize state from snapshot
        },
        .shutdown => {
            std.debug.print("[Emulation] Command: Shutdown\n", .{});
            ctx.running.store(false, .release);
        },
    }
}

/// Report emulation progress (FPS, cycles)
fn reportProgress(ctx: *EmulationContext) void {
    const now = std.time.nanoTimestamp();

    if (ctx.last_report_time == 0) {
        ctx.last_report_time = now;
        return;
    }

    const elapsed_ns = now - ctx.last_report_time;
    if (elapsed_ns >= 1_000_000_000) { // Report every 1 second
        const elapsed_sec = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
        const fps = @as(f64, @floatFromInt(ctx.frame_count)) / elapsed_sec;
        const total_frames = ctx.mailboxes.frame.getFrameCount();

        std.debug.print("[Emulation] FPS: {d:.2} | Frames: {d} | Cycles: {d}\n", .{
            fps,
            total_frames,
            ctx.total_cycles,
        });

        ctx.frame_count = 0;
        ctx.last_report_time = now;
    }
}

/// Emulation thread entry point
/// Runs on dedicated thread with own libxev event loop
pub fn threadMain(
    state: *EmulationState,
    mailboxes: *Mailboxes,
    running: *std.atomic.Value(bool),
) void {
    std.debug.print("[Emulation] Thread started (TID: {d})\n", .{std.Thread.getCurrentId()});

    // Create event loop for this thread
    var loop = xev.Loop.init(.{}) catch |err| {
        std.debug.print("[Emulation] Failed to init event loop: {}\n", .{err});
        return;
    };
    defer loop.deinit();

    // Create timer for frame pacing
    var timer = xev.Timer.init() catch |err| {
        std.debug.print("[Emulation] Failed to init timer: {}\n", .{err});
        return;
    };
    defer timer.deinit();

    // Setup emulation context
    var ctx = EmulationContext{
        .state = state,
        .mailboxes = mailboxes,
        .running = running,
    };

    // Start timer-driven emulation
    // NTSC: 60.0988 Hz = 16,639,267 ns per frame ≈ 16.6 ms
    const frame_duration_ms: u64 = 16_639_267 / 1_000_000;
    std.debug.print("[Emulation] Starting timer at {d}ms per frame (60.10 Hz NTSC)\n", .{frame_duration_ms});

    var completion: xev.Completion = undefined;
    timer.run(&loop, &completion, frame_duration_ms, EmulationContext, &ctx, timerCallback);

    // Run event loop until timer disarms (shutdown signal)
    loop.run(.until_done) catch |err| {
        std.debug.print("[Emulation] Event loop error: {}\n", .{err});
    };

    std.debug.print("[Emulation] Thread stopping (total cycles: {d})\n", .{ctx.total_cycles});
}

/// Spawn emulation thread
/// Returns thread handle for joining later
pub fn spawn(
    state: *EmulationState,
    mailboxes: *Mailboxes,
    running: *std.atomic.Value(bool),
) !std.Thread {
    return try std.Thread.spawn(.{}, threadMain, .{ state, mailboxes, running });
}

// ============================================================================
// Tests
// ============================================================================

test "EmulationThread: context initialization" {
    const allocator = std.testing.allocator;

    var config = @import("../config/Config.zig").Config.init(allocator);
    defer config.deinit();

    var emu_state = EmulationState.init(&config);
    var mailboxes = try Mailboxes.init(allocator);
    defer mailboxes.deinit();

    var running = std.atomic.Value(bool).init(true);

    var ctx = EmulationContext{
        .state = &emu_state,
        .mailboxes = &mailboxes,
        .running = &running,
    };

    try std.testing.expect(ctx.frame_count == 0);
    try std.testing.expect(ctx.total_cycles == 0);
    try std.testing.expect(ctx.running.load(.acquire) == true);
}

test "EmulationThread: command handling" {
    const allocator = std.testing.allocator;

    var config = @import("../config/Config.zig").Config.init(allocator);
    defer config.deinit();

    var emu_state = EmulationState.init(&config);
    var mailboxes = try Mailboxes.init(allocator);
    defer mailboxes.deinit();

    var running = std.atomic.Value(bool).init(true);

    var ctx = EmulationContext{
        .state = &emu_state,
        .mailboxes = &mailboxes,
        .running = &running,
    };

    // Test power_on command
    handleCommand(&ctx, .power_on);
    try std.testing.expect(ctx.frame_count == 0);
    try std.testing.expect(ctx.total_cycles == 0);

    // Test shutdown command
    handleCommand(&ctx, .shutdown);
    try std.testing.expect(ctx.running.load(.acquire) == false);
}

test "EmulationThread: mailbox command polling" {
    const allocator = std.testing.allocator;

    var config = @import("../config/Config.zig").Config.init(allocator);
    defer config.deinit();

    var emu_state = EmulationState.init(&config);
    var mailboxes = try Mailboxes.init(allocator);
    defer mailboxes.deinit();

    var running = std.atomic.Value(bool).init(true);

    var ctx = EmulationContext{
        .state = &emu_state,
        .mailboxes = &mailboxes,
        .running = &running,
    };

    // Post commands to mailbox
    try mailboxes.emulation_command.postCommand(.power_on);
    try mailboxes.emulation_command.postCommand(.reset);

    // Poll and handle commands
    var command_count: usize = 0;
    while (mailboxes.emulation_command.pollCommand()) |command| {
        handleCommand(&ctx, command);
        command_count += 1;
    }

    try std.testing.expectEqual(@as(usize, 2), command_count);
}
