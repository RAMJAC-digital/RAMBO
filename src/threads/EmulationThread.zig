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
const FrameMailbox = @import("../mailboxes/FrameMailbox.zig");
const EmulationCommand = @import("../mailboxes/EmulationCommandMailbox.zig").EmulationCommand;
const DebugCommand = @import("../mailboxes/DebugCommandMailbox.zig").DebugCommand;
const CpuSnapshot = @import("../mailboxes/DebugEventMailbox.zig").CpuSnapshot;

/// Context passed to timer callback
/// Contains all state needed for emulation loop
pub const EmulationContext = struct {
    /// Emulation state (CPU, PPU, APU, Bus, Cartridge)
    state: *EmulationState,

    /// Mailbox container for thread communication
    mailboxes: *Mailboxes,

    /// Atomic running flag (shared with main thread)
    running: *std.atomic.Value(bool),

    /// Frame counter for FPS reporting (resets every second)
    frame_count: u64 = 0,

    /// Total frames executed (never resets)
    total_frames: u64 = 0,

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
    _ = result catch {
        return .disarm;
    };

    const ctx = userdata orelse return .disarm;

    // Check for shutdown signal
    if (!ctx.running.load(.acquire)) {
        if (!ctx.shutdown_printed) {
            ctx.shutdown_printed = true;
        }
        return .disarm;
    }

    // Process emulation commands (non-blocking poll)
    while (ctx.mailboxes.emulation_command.pollCommand()) |command| {
        handleCommand(ctx, command);
    }

    // Process debug commands (non-blocking poll)
    while (ctx.mailboxes.debug_command.pollCommand()) |command| {
        handleDebugCommand(ctx, command);
    }

    // Poll controller input mailbox and update controller state
    const input = ctx.mailboxes.controller_input.getInput();
    ctx.state.controller.updateButtons(input.controller1.toByte(), input.controller2.toByte());

    // Get write buffer for PPU frame output (may be null if buffer full)
    const write_buffer = ctx.mailboxes.frame.getWriteBuffer();

    // Helper: validate cartridge presence and ROM data
    const has_cart = hasValidCartridge(ctx.state);

    if (write_buffer) |buffer| {
        // Buffer available - render frame directly into mailbox buffer
        ctx.state.framebuffer = buffer;

        if (has_cart) {
            // Emulate one frame (cycle-accurate execution)
            const cycles = ctx.state.emulateFrame();
            ctx.total_cycles += cycles;
            ctx.frame_count += 1;
            ctx.total_frames += 1;

            // Check if debug break occurred during frame execution
            if (ctx.state.debug_break_occurred) {
                ctx.state.debug_break_occurred = false; // Clear flag

                if (ctx.state.debugger) |*debugger| {
                    const reason = debugger.getBreakReason() orelse "Unknown break";
                    const snapshot = captureSnapshot(ctx);

                    // Copy reason string to event buffer
                    var reason_buf: [128]u8 = undefined;
                    const reason_len = @min(reason.len, 128);
                    @memcpy(reason_buf[0..reason_len], reason[0..reason_len]);

                    // Post breakpoint hit event
                    _ = ctx.mailboxes.debug_event.postEvent(.{ .breakpoint_hit = .{
                        .reason = reason_buf,
                        .reason_len = reason_len,
                        .snapshot = snapshot,
                    } });
                }
            }

            // Post completed frame to render thread (only when we rendered game content)
            ctx.mailboxes.frame.swapBuffers();
        } else {
            // No cartridge loaded: fill buffer with black but don't swap
            // Don't increment frame counter when no game is running
            @memset(buffer, 0);
        }

        // Clear framebuffer reference
        ctx.state.framebuffer = null;
    } else {
        // Buffer full - still emulate but don't render
        // Game logic continues (CPU/PPU cycles advance) but no framebuffer output
        // This prevents game from freezing when render thread falls behind
        ctx.state.framebuffer = null;
        if (has_cart) {
            const cycles = ctx.state.emulateFrame();
            ctx.total_cycles += cycles;
        }
        // Don't call swapBuffers() - no frame was rendered
        _ = ctx.mailboxes.frame.getFramesDropped(); // Increment drop counter
    }

    // FPS reporting (periodic diagnostics)
    reportProgress(ctx);

    // Rearm timer for next frame
    // NTSC: 60.0988 Hz = 16,639,267 ns/frame (NESdev wiki: Cycle reference chart)
    // Convert to milliseconds with proper rounding to preserve precision
    const frame_duration_ns: u64 = 16_639_267;
    const frame_duration_ms: u64 = (frame_duration_ns + 500_000) / 1_000_000; // Round to 17ms
    var timer = xev.Timer{};
    timer.run(loop, completion, frame_duration_ms, EmulationContext, ctx, timerCallback);

    return .rearm;
}

/// Determine if a valid cartridge with ROM data is present
fn hasValidCartridge(state: *EmulationState) bool {
    if (state.cart) |*cart| {
        return cart.getPrgRom().len > 0;
    }
    return false;
}

/// Handle emulation lifecycle commands
fn handleCommand(ctx: *EmulationContext, command: EmulationCommand) void {
    switch (command) {
        .power_on => {
            // Reset state to power-on defaults
            ctx.state.power_on();
            ctx.frame_count = 0;
            ctx.total_frames = 0;
            ctx.total_cycles = 0;
        },
        .reset => {
            // Warm reset (like pressing reset button)
            ctx.state.reset();
        },
        .pause_emulation => {
            // TODO: Set paused flag, stop timer
        },
        .resume_emulation => {
            // TODO: Clear paused flag, restart timer
        },
        .save_state => {
            // TODO: Serialize state to snapshot
        },
        .load_state => {
            // TODO: Deserialize state from snapshot
        },
        .shutdown => {
            ctx.running.store(false, .release);
        },
    }
}

/// Handle debug commands (modify debugger state)
fn handleDebugCommand(ctx: *EmulationContext, command: DebugCommand) void {
    if (ctx.state.debugger == null) {
        // No debugger active - post error event
        var err_msg: [128]u8 = undefined;
        const msg = "Debugger not initialized";
        @memcpy(err_msg[0..msg.len], msg);
        _ = ctx.mailboxes.debug_event.postEvent(.{ .error_occurred = .{
            .message = err_msg,
            .message_len = msg.len,
        } });
        return;
    }

    var debugger = &ctx.state.debugger.?;

    switch (command) {
        .add_breakpoint => |bp| {
            debugger.addBreakpoint(bp.address, bp.bp_type) catch {
                // Post error event on failure
                var err_msg: [128]u8 = undefined;
                const msg = "Failed to add breakpoint";
                @memcpy(err_msg[0..msg.len], msg);
                _ = ctx.mailboxes.debug_event.postEvent(.{ .error_occurred = .{
                    .message = err_msg,
                    .message_len = msg.len,
                } });
                return;
            };
            _ = ctx.mailboxes.debug_event.postEvent(.{ .breakpoint_added = .{ .address = bp.address } });
        },
        .remove_breakpoint => |bp| {
            const removed = debugger.removeBreakpoint(bp.address, bp.bp_type);
            if (removed) {
                _ = ctx.mailboxes.debug_event.postEvent(.{ .breakpoint_removed = .{ .address = bp.address } });
            }
        },
        .add_watchpoint => |wp| {
            debugger.addWatchpoint(wp.address, wp.size, wp.watch_type) catch {
                // Post error event on failure
                var err_msg: [128]u8 = undefined;
                const msg = "Failed to add watchpoint";
                @memcpy(err_msg[0..msg.len], msg);
                _ = ctx.mailboxes.debug_event.postEvent(.{ .error_occurred = .{
                    .message = err_msg,
                    .message_len = msg.len,
                } });
                return;
            };
        },
        .remove_watchpoint => |wp| {
            _ = debugger.removeWatchpoint(wp.address, wp.watch_type);
        },
        .pause => {
            debugger.pause();
            const snapshot = captureSnapshot(ctx);
            _ = ctx.mailboxes.debug_event.postEvent(.{ .paused = .{ .snapshot = snapshot } });
        },
        .resume_execution => {
            debugger.continue_();
            _ = ctx.mailboxes.debug_event.postEvent(.resumed);
        },
        .step_instruction => {
            debugger.stepInstruction();
        },
        .step_frame => {
            debugger.stepFrame(ctx.state);
        },
        .inspect => {
            const snapshot = captureSnapshot(ctx);
            _ = ctx.mailboxes.debug_event.postEvent(.{ .inspect_response = .{ .snapshot = snapshot } });
        },
        .clear_breakpoints => {
            debugger.clearBreakpoints();
        },
        .clear_watchpoints => {
            debugger.clearWatchpoints();
        },
        .set_breakpoint_enabled => |bp| {
            _ = debugger.setBreakpointEnabled(bp.address, bp.bp_type, bp.enabled);
        },
    }
}

/// Capture CPU state snapshot for debugging
fn captureSnapshot(ctx: *EmulationContext) CpuSnapshot {
    return .{
        .a = ctx.state.cpu.a,
        .x = ctx.state.cpu.x,
        .y = ctx.state.cpu.y,
        .sp = ctx.state.cpu.sp,
        .pc = ctx.state.cpu.pc,
        .p = ctx.state.cpu.p.toByte(),
        .cycle = ctx.state.clock.cpuCycles(),
        .frame = ctx.state.ppu.frame_count,
    };
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

    // Create event loop for this thread
    var loop = xev.Loop.init(.{}) catch {
        return;
    };
    defer loop.deinit();

    // Create timer for frame pacing
    var timer = xev.Timer.init() catch {
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
    // NTSC: 60.0988 Hz = 16,639,267 ns/frame (NESdev wiki: Cycle reference chart)
    // Convert to milliseconds with proper rounding to preserve precision
    const frame_duration_ns: u64 = 16_639_267;
    const frame_duration_ms: u64 = (frame_duration_ns + 500_000) / 1_000_000; // Round to 17ms

    var completion: xev.Completion = undefined;
    timer.run(&loop, &completion, frame_duration_ms, EmulationContext, &ctx, timerCallback);

    // Run event loop until timer disarms (shutdown signal)
    loop.run(.until_done) catch {};
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
    var mailboxes = try allocator.create(Mailboxes);
    mailboxes.* = Mailboxes.init(allocator);
    defer {
        mailboxes.deinit();
        allocator.destroy(mailboxes);
    }

    var running = std.atomic.Value(bool).init(true);

    var ctx = EmulationContext{
        .state = &emu_state,
        .mailboxes = mailboxes,
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
    var mailboxes = try allocator.create(Mailboxes);
    mailboxes.* = Mailboxes.init(allocator);
    defer {
        mailboxes.deinit();
        allocator.destroy(mailboxes);
    }

    var running = std.atomic.Value(bool).init(true);

    var ctx = EmulationContext{
        .state = &emu_state,
        .mailboxes = mailboxes,
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
    var mailboxes = try allocator.create(Mailboxes);
    mailboxes.* = Mailboxes.init(allocator);
    defer {
        mailboxes.deinit();
        allocator.destroy(mailboxes);
    }

    var running = std.atomic.Value(bool).init(true);

    var ctx = EmulationContext{
        .state = &emu_state,
        .mailboxes = mailboxes,
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
