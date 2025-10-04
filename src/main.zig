const std = @import("std");
const RAMBO = @import("RAMBO");
const xev = @import("xev");

/// Main thread: Coordinator only (minimal work)
/// - Initialize resources
/// - Spawn threads
/// - Coordinate via libxev loop
/// - Wait for cleanup
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("RAMBO NES Emulator - Phase 1: Thread Architecture Demo\n", .{});
    std.debug.print("========================================================\n\n", .{});

    // ========================================================================
    // 1. Initialize Mailboxes (dependency injection container)
    // ========================================================================

    std.debug.print("[Main] Initializing mailboxes...\n", .{});
    var mailboxes = try RAMBO.Mailboxes.Mailboxes.init(allocator);
    defer mailboxes.deinit();

    // ========================================================================
    // 2. Initialize Emulation State
    // ========================================================================

    std.debug.print("[Main] Initializing emulation state...\n", .{});

    // Create default configuration (NTSC AccuracyCoin target)
    var config = RAMBO.Config.Config.init(allocator);
    defer config.deinit();

    // Initialize bus
    const bus_state = RAMBO.Bus.State.BusState.init();

    // Initialize emulation state
    var emu_state = RAMBO.EmulationState.EmulationState.init(&config, bus_state);

    // ========================================================================
    // 3. Initialize libxev Loop (Main Thread Coordinator)
    // ========================================================================

    std.debug.print("[Main] Initializing libxev event loop...\n", .{});
    var loop = try xev.Loop.init(.{});
    defer loop.deinit();

    // ========================================================================
    // 4. Spawn Threads
    // ========================================================================

    // Shared running flag (atomic for thread-safe coordination)
    var running = std.atomic.Value(bool).init(true);

    // TODO: Spawn Wayland thread (Phase 1.1)
    // const wayland_thread = try std.Thread.spawn(.{}, waylandThreadFn, .{ &mailboxes, &running });

    std.debug.print("[Main] Spawning emulation thread...\n", .{});
    const emulation_thread = try std.Thread.spawn(.{}, emulationThreadFn, .{ &emu_state, &mailboxes, &running });

    // ========================================================================
    // 5. Main Coordination Loop
    // ========================================================================

    std.debug.print("[Main] Entering coordination loop...\n", .{});
    std.debug.print("[Main] Running timer-driven emulation for 10 seconds...\n", .{});
    std.debug.print("[Main] Watch for FPS reports from emulation thread\n\n", .{});

    // Run for 10 seconds to see accurate FPS reporting
    const start_time = std.time.nanoTimestamp();
    const duration_ns: i128 = 10_000_000_000; // 10 seconds

    while (std.time.nanoTimestamp() - start_time < duration_ns and running.load(.acquire)) {
        // Process mailbox events
        const config_update = mailboxes.config.pollUpdate();
        if (config_update) |update| {
            std.debug.print("[Main] Received config update: {any}\n", .{update});
        }

        // Run libxev loop (no_wait for polling)
        try loop.run(.no_wait);

        // Small sleep to avoid busy-waiting (main thread is just coordinating)
        std.Thread.sleep(100_000_000); // 100ms
    }

    const elapsed_sec = @as(f64, @floatFromInt(std.time.nanoTimestamp() - start_time)) / 1_000_000_000.0;
    const total_frames = mailboxes.frame.getFrameCount();
    const avg_fps = @as(f64, @floatFromInt(total_frames)) / elapsed_sec;

    std.debug.print("\n[Main] === Emulation Statistics ===\n", .{});
    std.debug.print("[Main] Duration: {d:.2}s\n", .{elapsed_sec});
    std.debug.print("[Main] Total frames: {d}\n", .{total_frames});
    std.debug.print("[Main] Average FPS: {d:.2}\n", .{avg_fps});
    std.debug.print("[Main] Target FPS: 60.10 (NTSC)\n", .{});

    // ========================================================================
    // 6. Shutdown
    // ========================================================================

    std.debug.print("\n[Main] Shutting down...\n", .{});
    running.store(false, .release);

    std.debug.print("[Main] Waiting for emulation thread...\n", .{});
    emulation_thread.join();

    // TODO: Join Wayland thread when implemented

    std.debug.print("[Main] Cleanup complete. Goodbye!\n", .{});
}

/// Context for emulation timer callback
const EmulationContext = struct {
    state: *RAMBO.EmulationState.EmulationState,
    mailboxes: *RAMBO.Mailboxes.Mailboxes,
    running: *std.atomic.Value(bool),
    frame_count: u64 = 0,
    total_cycles: u64 = 0,
    last_report_time: i128 = 0,
};

/// Timer callback for frame-based emulation
/// Fires every ~16.6ms (60 Hz NTSC) to emulate one frame
fn emulationTimerCallback(
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

    // Check if we should stop (only print once)
    if (!ctx.running.load(.acquire)) {
        if (ctx.frame_count > 0 or ctx.total_cycles > 0) {
            std.debug.print("[Emulation] Shutdown signal received\n", .{});
            ctx.frame_count = 0;
            ctx.total_cycles = 0;
        }
        return .disarm;
    }

    // Check for config updates
    if (ctx.mailboxes.config.pollUpdate()) |update| {
        std.debug.print("[Emulation] Config update: {any}\n", .{update});
        // TODO: Apply config (speed change, pause, reset, etc.)
    }

    // Emulate one frame (cycle-accurate)
    const cycles = ctx.state.emulateFrame();
    ctx.total_cycles += cycles;
    ctx.frame_count += 1;

    // Post completed frame
    ctx.mailboxes.frame.swapBuffers();

    // Progress reporting (every second)
    const now = std.time.nanoTimestamp();
    if (ctx.last_report_time == 0) {
        ctx.last_report_time = now;
    } else if (now - ctx.last_report_time >= 1_000_000_000) {
        const elapsed_sec = @as(f64, @floatFromInt(now - ctx.last_report_time)) / 1_000_000_000.0;
        const fps = @as(f64, @floatFromInt(ctx.frame_count)) / elapsed_sec;
        std.debug.print("[Emulation] FPS: {d:.2} | Total frames: {d} | Total cycles: {d}\n", .{ fps, ctx.frame_count, ctx.total_cycles });
        ctx.frame_count = 0;
        ctx.last_report_time = now;
    }

    // Rearm timer for next frame
    // NTSC: 60.0988 Hz = 16,639,267 ns per frame
    const frame_duration_ns: u64 = 16_639_267;
    const frame_duration_ms: u64 = frame_duration_ns / 1_000_000;

    var timer = xev.Timer{};
    timer.run(loop, completion, frame_duration_ms, EmulationContext, ctx, emulationTimerCallback);

    return .rearm;
}

/// Emulation Thread: Runs emulation with libxev timer for pacing
/// - Own libxev loop for timer-driven ticking
/// - Frame-based timer (60 Hz NTSC)
/// - Posts completed frames to mailbox
fn emulationThreadFn(
    state: *RAMBO.EmulationState.EmulationState,
    mailboxes: *RAMBO.Mailboxes.Mailboxes,
    running: *std.atomic.Value(bool),
) void {
    std.debug.print("[Emulation] Thread started\n", .{});

    // Create event loop for this thread
    var loop = xev.Loop.init(.{}) catch |err| {
        std.debug.print("[Emulation] Failed to init loop: {}\n", .{err});
        return;
    };
    defer loop.deinit();

    // Create timer
    var timer = xev.Timer.init() catch |err| {
        std.debug.print("[Emulation] Failed to init timer: {}\n", .{err});
        return;
    };
    defer timer.deinit();

    // Setup context
    var ctx = EmulationContext{
        .state = state,
        .mailboxes = mailboxes,
        .running = running,
    };

    // Start timer (NTSC frame rate: ~16.6ms)
    const frame_duration_ns: u64 = 16_639_267;
    const frame_duration_ms: u64 = frame_duration_ns / 1_000_000;

    std.debug.print("[Emulation] Starting timer-driven emulation at {d}ms per frame\n", .{frame_duration_ms});

    var completion: xev.Completion = undefined;
    timer.run(&loop, &completion, frame_duration_ms, EmulationContext, &ctx, emulationTimerCallback);

    // Run event loop until timer disarms
    loop.run(.until_done) catch |err| {
        std.debug.print("[Emulation] Loop error: {}\n", .{err});
    };

    std.debug.print("[Emulation] Thread stopping (total cycles: {d})\n", .{ctx.total_cycles});
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
