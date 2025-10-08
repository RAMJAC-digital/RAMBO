const std = @import("std");
const RAMBO = @import("RAMBO");
const xev = @import("xev");
const zli = @import("zli");
const EmulationThread = RAMBO.EmulationThread;
const RenderThread = RAMBO.RenderThread;

/// Debug configuration flags from CLI
const DebugFlags = struct {
    trace: bool = false,
    trace_file: ?[]const u8 = null,
    break_at: ?[]const u16 = null,
    watch: ?[]const u16 = null,
    cycles: ?u64 = null,
    frames: ?u64 = null,
    inspect: bool = false,
    verbose: bool = false,

    pub fn deinit(self: *DebugFlags, allocator: std.mem.Allocator) void {
        if (self.break_at) |addrs| allocator.free(addrs);
        if (self.watch) |addrs| allocator.free(addrs);
    }
};

/// Print CPU state snapshot for debugging
fn printCpuSnapshot(snapshot: RAMBO.Mailboxes.CpuSnapshot) void {
    std.debug.print("\n[Main] CPU State:\n", .{});
    std.debug.print("  A:  ${X:0>2}  X:  ${X:0>2}  Y:  ${X:0>2}\n", .{ snapshot.a, snapshot.x, snapshot.y });
    std.debug.print("  SP: ${X:0>2}  PC: ${X:0>4}\n", .{ snapshot.sp, snapshot.pc });
    std.debug.print("  P:  ${X:0>2}  [", .{snapshot.p});

    // Decode status flags
    const N = (snapshot.p & 0x80) != 0;
    const V = (snapshot.p & 0x40) != 0;
    const D = (snapshot.p & 0x08) != 0;
    const I = (snapshot.p & 0x04) != 0;
    const Z = (snapshot.p & 0x02) != 0;
    const C = (snapshot.p & 0x01) != 0;

    std.debug.print("{s}{s}{s}{s}{s}{s}]\n", .{
        if (N) "N" else "-",
        if (V) "V" else "-",
        if (D) "D" else "-",
        if (I) "I" else "-",
        if (Z) "Z" else "-",
        if (C) "C" else "-",
    });

    std.debug.print("  Cycle: {d}  Frame: {d}\n\n", .{ snapshot.cycle, snapshot.frame });
}

/// Parse comma-separated hex addresses (e.g., "0x8000,0xFFFA")
fn parseHexArray(allocator: std.mem.Allocator, input: ?[]const u8) !?[]const u16 {
    const str = input orelse return null;
    if (str.len == 0) return null;

    var list: std.ArrayList(u16) = .empty;
    errdefer list.deinit(allocator);

    var iter = std.mem.splitSequence(u8, str, ",");
    while (iter.next()) |addr_str| {
        const trimmed = std.mem.trim(u8, addr_str, " \t");
        if (trimmed.len == 0) continue;

        // Parse hex (with or without 0x prefix)
        const hex_str = if (std.mem.startsWith(u8, trimmed, "0x") or std.mem.startsWith(u8, trimmed, "0X"))
            trimmed[2..]
        else
            trimmed;

        const addr = std.fmt.parseInt(u16, hex_str, 16) catch |err| {
            std.debug.print("Error: Invalid hex address '{s}': {}\n", .{ trimmed, err });
            return error.InvalidHexAddress;
        };

        try list.append(allocator, addr);
    }

    return if (list.items.len > 0) try list.toOwnedSlice(allocator) else null;
}

/// Main execution function - called by zli after parsing args
fn mainExec(ctx: zli.CommandContext) !void {
    const allocator = ctx.allocator;

    // ========================================================================
    // 0. Extract CLI Arguments from zli CommandContext
    // ========================================================================

    // Get ROM path from positional argument
    const rom_path = ctx.getArg("rom") orelse {
        try ctx.writer.print("Error: No ROM file specified\n", .{});
        return error.NoRomFile;
    };

    // Extract debug flags
    const trace_file_str = ctx.flag("trace-file", []const u8);
    const break_at_str = ctx.flag("break-at", []const u8);
    const watch_str = ctx.flag("watch", []const u8);
    const cycles_int = ctx.flag("cycles", i32);
    const frames_int = ctx.flag("frames", i32);

    var debug_flags = DebugFlags{
        .trace = ctx.flag("trace", bool),
        .trace_file = if (trace_file_str.len > 0) trace_file_str else null,
        .break_at = try parseHexArray(allocator, if (break_at_str.len > 0) break_at_str else null),
        .watch = try parseHexArray(allocator, if (watch_str.len > 0) watch_str else null),
        .cycles = if (cycles_int > 0) @as(u64, @intCast(cycles_int)) else null,
        .frames = if (frames_int > 0) @as(u64, @intCast(frames_int)) else null,
        .inspect = ctx.flag("inspect", bool),
        .verbose = ctx.flag("verbose", bool),
    };
    defer debug_flags.deinit(allocator);

    // Print header
    std.debug.print("RAMBO NES Emulator v0.1.0\n", .{});
    std.debug.print("================================================\n", .{});
    if (debug_flags.trace or debug_flags.break_at != null or debug_flags.watch != null) {
        std.debug.print("DEBUG MODE ENABLED\n", .{});
        std.debug.print("================================================\n", .{});
    }
    std.debug.print("Main Thread:      Coordinator (TID: {d})\n", .{std.Thread.getCurrentId()});
    std.debug.print("Emulation Thread: Timer-driven execution (spawning...)\n", .{});
    std.debug.print("Render Thread:    Wayland + Vulkan\n\n", .{});

    // ========================================================================
    // 1. Initialize Mailboxes (dependency injection container)
    // ========================================================================

    std.debug.print("[Main] Initializing mailboxes...\n", .{});
    var mailboxes = RAMBO.Mailboxes.Mailboxes.init(allocator);
    defer mailboxes.deinit();

    // ========================================================================
    // 2. Initialize Emulation State
    // ========================================================================

    std.debug.print("[Main] Initializing emulation state...\n", .{});

    // Create default configuration (NTSC AccuracyCoin target)
    var config = RAMBO.Config.Config.init(allocator);
    defer config.deinit();

    // Initialize emulation state (bus is now flattened into EmulationState)
    var emu_state = RAMBO.EmulationState.EmulationState.init(&config);

    // Load ROM from command line
    std.debug.print("[Main] Loading ROM: {s}\n", .{rom_path});

    const file = try std.fs.cwd().openFile(rom_path, .{});
    defer file.close();
    const rom_data = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(rom_data);

    const nrom_cart = try RAMBO.CartridgeType.loadFromData(allocator, rom_data);
    const any_cart = RAMBO.AnyCartridge{ .nrom = nrom_cart };
    emu_state.loadCartridge(any_cart);

    // Reset CPU to load reset vector and initialize state
    emu_state.reset();

    std.debug.print("[Main] ROM loaded successfully\n", .{});
    std.debug.print("[Main] Reset vector loaded: PC=0x{x:0>4}\n", .{emu_state.cpu.pc});

    // ========================================================================
    // 2.5. Initialize Debugger (if debug flags enabled)
    // ========================================================================

    if (debug_flags.trace or
        debug_flags.break_at != null or
        debug_flags.watch != null or
        debug_flags.inspect)
    {
        std.debug.print("[Main] Initializing debugger...\n", .{});
        emu_state.debugger = RAMBO.Debugger.Debugger.init(allocator, &config);

        // Configure breakpoints from CLI
        if (debug_flags.break_at) |addrs| {
            for (addrs) |addr| {
                emu_state.debugger.?.addBreakpoint(addr, .execute) catch |err| {
                    std.debug.print("[Main] Failed to add breakpoint at ${X:0>4}: {}\n", .{ addr, err });
                    continue;
                };
                std.debug.print("[Main] Breakpoint added at ${X:0>4}\n", .{addr});
            }
        }

        // Configure watchpoints from CLI
        if (debug_flags.watch) |addrs| {
            for (addrs) |addr| {
                emu_state.debugger.?.addWatchpoint(addr, 1, .write) catch |err| {
                    std.debug.print("[Main] Failed to add watchpoint at ${X:0>4}: {}\n", .{ addr, err });
                    continue;
                };
                std.debug.print("[Main] Watchpoint added at ${X:0>4}\n", .{addr});
            }
        }

        std.debug.print("[Main] Debugger initialized (RT-safe)\n", .{});
    }

    // Cleanup debugger on exit
    defer if (emu_state.debugger) |*d| d.deinit();

    // Print debug configuration if enabled
    if (debug_flags.verbose) {
        std.debug.print("\n[Debug] Configuration:\n", .{});
        std.debug.print("  Trace:     {}\n", .{debug_flags.trace});
        if (debug_flags.trace_file) |path| {
            std.debug.print("  Trace file: {s}\n", .{path});
        }
        if (debug_flags.break_at) |addrs| {
            std.debug.print("  Breakpoints: ", .{});
            for (addrs, 0..) |addr, i| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("${x:0>4}", .{addr});
            }
            std.debug.print("\n", .{});
        }
        if (debug_flags.watch) |addrs| {
            std.debug.print("  Watchpoints: ", .{});
            for (addrs, 0..) |addr, i| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("${x:0>4}", .{addr});
            }
            std.debug.print("\n", .{});
        }
        if (debug_flags.cycles) |c| std.debug.print("  Cycle limit: {d}\n", .{c});
        if (debug_flags.frames) |f| std.debug.print("  Frame limit: {d}\n", .{f});
        std.debug.print("  Inspect:    {}\n\n", .{debug_flags.inspect});
    }

    // ========================================================================
    // 3. Initialize libxev Loop (Main Thread Coordinator)
    // ========================================================================

    std.debug.print("[Main] Initializing libxev event loop...\n", .{});
    var loop = try xev.Loop.init(.{});
    defer loop.deinit();

    // ========================================================================
    // 4. Spawn Threads
    // ========================================================================

    std.debug.print("[Main] Spawning threads...\n", .{});

    // Shared running flag (atomic for thread-safe coordination)
    var running = std.atomic.Value(bool).init(true);

    // Spawn emulation thread (timer-driven, RT-safe)
    const emulation_thread = try EmulationThread.spawn(&emu_state, &mailboxes, &running);

    // Spawn render thread (Wayland + Vulkan stub)
    const render_thread = try RenderThread.spawn(&mailboxes, &running, .{});

    // ========================================================================
    // 5. Main Coordination Loop
    // ========================================================================

    // Initialize keyboard mapper (converts Wayland keycodes to NES buttons)
    var keyboard_mapper = RAMBO.KeyboardMapper{};

    // Run for 60 seconds to check for delayed initialization
    const start_time = std.time.nanoTimestamp();
    const duration_ns: i128 = 60_000_000_000; // 60 seconds

    while (std.time.nanoTimestamp() - start_time < duration_ns and running.load(.acquire)) {
        // Process window events (from render thread)
        var window_events: [16]RAMBO.Mailboxes.XdgWindowEvent = undefined;
        const window_count = mailboxes.xdg_window_event.drainEvents(&window_events);
        _ = window_count; // Discard for now

        // Process input events (from render thread)
        var input_events: [32]RAMBO.Mailboxes.XdgInputEvent = undefined;
        const input_count = mailboxes.xdg_input_event.drainEvents(&input_events);

        // Process keyboard events through KeyboardMapper
        for (input_events[0..input_count]) |event| {
            switch (event) {
                .key_press => |key| {
                    keyboard_mapper.keyPress(key.keycode);
                },
                .key_release => |key| {
                    keyboard_mapper.keyRelease(key.keycode);
                },
                else => {}, // Ignore mouse events for now
            }
        }

        // Post button state EVERY frame (not just when events occur)
        // This ensures emulation always has current state, including button holds
        const button_state = keyboard_mapper.getState();
        mailboxes.controller_input.postController1(button_state);

        // Process debug events (from emulation thread)
        if (emu_state.debugger != null) {
            var debug_events: [16]RAMBO.Mailboxes.DebugEvent = undefined;
            const debug_count = mailboxes.debug_event.drainEvents(&debug_events);

            for (debug_events[0..debug_count]) |event| {
                switch (event) {
                    .breakpoint_hit => |bp| {
                        const reason = bp.reason[0..bp.reason_len];
                        std.debug.print("\n[Main] === BREAKPOINT HIT ===\n", .{});
                        std.debug.print("[Main] Reason: {s}\n", .{reason});

                        if (debug_flags.inspect) {
                            printCpuSnapshot(bp.snapshot);
                        }
                    },
                    .watchpoint_hit => |wp| {
                        const reason = wp.reason[0..wp.reason_len];
                        std.debug.print("\n[Main] === WATCHPOINT HIT ===\n", .{});
                        std.debug.print("[Main] Reason: {s}\n", .{reason});

                        if (debug_flags.inspect) {
                            printCpuSnapshot(wp.snapshot);
                        }
                    },
                    .inspect_response => |resp| {
                        std.debug.print("\n[Main] === STATE INSPECTION ===\n", .{});
                        printCpuSnapshot(resp.snapshot);
                    },
                    .paused => |p| {
                        std.debug.print("\n[Main] === EMULATION PAUSED ===\n", .{});
                        if (debug_flags.inspect) {
                            printCpuSnapshot(p.snapshot);
                        }
                    },
                    .resumed => {
                        std.debug.print("\n[Main] === EMULATION RESUMED ===\n", .{});
                    },
                    .breakpoint_added => |bp| {
                        std.debug.print("[Main] Breakpoint added at ${X:0>4}\n", .{bp.address});
                    },
                    .breakpoint_removed => |bp| {
                        std.debug.print("[Main] Breakpoint removed at ${X:0>4}\n", .{bp.address});
                    },
                    .error_occurred => |err| {
                        const msg = err.message[0..err.message_len];
                        std.debug.print("[Main] DEBUG ERROR: {s}\n", .{msg});
                    },
                }
            }
        }

        // Process config updates (legacy)
        const config_update = mailboxes.config.pollUpdate();
        _ = config_update; // Discard for now

        // Run libxev loop (no_wait for polling)
        try loop.run(.no_wait);

        // Small sleep to avoid busy-waiting (main thread is just coordinating)
        std.Thread.sleep(100_000_000); // 100ms
    }

    const elapsed_sec = @as(f64, @floatFromInt(std.time.nanoTimestamp() - start_time)) / 1_000_000_000.0;
    const total_frames = mailboxes.frame.getFrameCount();
    const avg_fps = @as(f64, @floatFromInt(total_frames)) / elapsed_sec;

    std.debug.print("\n[Main] === Emulation Statistics ===\n", .{});
    std.debug.print("[Main] Duration:     {d:.2}s\n", .{elapsed_sec});
    std.debug.print("[Main] Total frames: {d}\n", .{total_frames});
    std.debug.print("[Main] Average FPS:  {d:.2}\n", .{avg_fps});
    std.debug.print("[Main] Target FPS:   60.10 (NTSC)\n", .{});

    // ========================================================================
    // 6. Shutdown
    // ========================================================================

    std.debug.print("\n[Main] Shutting down...\n", .{});
    running.store(false, .release);

    std.debug.print("[Main] Waiting for threads to stop...\n", .{});
    emulation_thread.join();
    render_thread.join();

    std.debug.print("[Main] All threads stopped. Cleanup complete.\n", .{});
    std.debug.print("[Main] Goodbye!\n", .{});
}

/// Main entry point - sets up zli Command and executes
pub fn main() !void {
    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Setup stdout writer with buffer for zli
    const stdout_file = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
    var buffer: [4096]u8 = undefined;
    var file_writer = stdout_file.writer(&buffer);

    // Create root command
    const app = try zli.Command.init(&file_writer.interface, allocator, .{
        .name = "rambo",
        .version = std.SemanticVersion{ .major = 0, .minor = 1, .patch = 0 },
        .description = "RAMBO NES Emulator - Multi-Threaded Architecture with Debugging",
    }, mainExec);
    defer app.deinit();

    // Add positional ROM argument
    try app.addPositionalArg(.{
        .name = "rom",
        .description = "Path to NES ROM file (.nes)",
        .required = true,
    });

    // Add debug flags
    try app.addFlag(.{
        .name = "trace",
        .shortcut = "t",
        .description = "Enable execution tracing",
        .type = .Bool,
        .default_value = .{ .Bool = false },
    });
    try app.addFlag(.{
        .name = "trace-file",
        .description = "Trace output file (default: stdout)",
        .type = .String,
        .default_value = .{ .String = "" },
    });
    try app.addFlag(.{
        .name = "break-at",
        .shortcut = "b",
        .description = "Breakpoint addresses (hex, comma-separated, e.g., 0x8000,0xFFFA)",
        .type = .String,
        .default_value = .{ .String = "" },
    });
    try app.addFlag(.{
        .name = "watch",
        .shortcut = "w",
        .description = "Watch memory addresses (hex, comma-separated)",
        .type = .String,
        .default_value = .{ .String = "" },
    });
    try app.addFlag(.{
        .name = "cycles",
        .shortcut = "c",
        .description = "Stop after N CPU cycles (0 = unlimited)",
        .type = .Int,
        .default_value = .{ .Int = 0 },
    });
    try app.addFlag(.{
        .name = "frames",
        .shortcut = "f",
        .description = "Stop after N frames (0 = unlimited)",
        .type = .Int,
        .default_value = .{ .Int = 0 },
    });
    try app.addFlag(.{
        .name = "inspect",
        .shortcut = "i",
        .description = "Print state on exit or breakpoint",
        .type = .Bool,
        .default_value = .{ .Bool = false },
    });
    try app.addFlag(.{
        .name = "verbose",
        .shortcut = "v",
        .description = "Verbose debug output",
        .type = .Bool,
        .default_value = .{ .Bool = false },
    });

    // Execute command (parses args and calls mainExec)
    try app.execute(.{});

    // Flush any buffered output (help text, errors, etc.)
    try file_writer.interface.flush();
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
