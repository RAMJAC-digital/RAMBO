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
fn handleCpuSnapshot(snapshot: RAMBO.Mailboxes.CpuSnapshot) void {
    std.debug.print("\n=== CPU Snapshot ===\n", .{});
    std.debug.print("  PC: ${X:0>4}  A: ${X:0>2}  X: ${X:0>2}  Y: ${X:0>2}\n", .{ snapshot.pc, snapshot.a, snapshot.x, snapshot.y });
    std.debug.print("  SP: ${X:0>2}   P: ${X:0>2}  ", .{ snapshot.sp, snapshot.p });

    // Decode status flags
    const n = (snapshot.p & 0x80) != 0;
    const v = (snapshot.p & 0x40) != 0;
    const d = (snapshot.p & 0x08) != 0;
    const i = (snapshot.p & 0x04) != 0;
    const z = (snapshot.p & 0x02) != 0;
    const c = (snapshot.p & 0x01) != 0;
    std.debug.print("[{s}{s}--{s}{s}{s}{s}]\n", .{
        if (n) "N" else "-",
        if (v) "V" else "-",
        if (d) "D" else "-",
        if (i) "I" else "-",
        if (z) "Z" else "-",
        if (c) "C" else "-",
    });
    std.debug.print("  Cycle: {}  Frame: {}\n", .{ snapshot.cycle, snapshot.frame });
    std.debug.print("====================\n\n", .{});
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

        const addr = std.fmt.parseInt(u16, hex_str, 16) catch return error.InvalidHexAddress;

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

    // ========================================================================
    // 1. Initialize Mailboxes (dependency injection container)
    // ========================================================================

    var mailboxes = RAMBO.Mailboxes.Mailboxes.init(allocator);
    defer mailboxes.deinit();

    // ========================================================================
    // 2. Initialize Emulation State
    // ========================================================================

    // Create default configuration (NTSC AccuracyCoin target)
    var config = RAMBO.Config.Config.init(allocator);
    defer config.deinit();

    // Initialize emulation state (bus is now flattened into EmulationState)
    var emu_state = RAMBO.EmulationState.EmulationState.init(&config);
    defer emu_state.deinit();

    // Load ROM from command line
    const nrom_cart = try RAMBO.Cartridge.NromCart.load(allocator, rom_path);
    const any_cart = RAMBO.AnyCartridge{ .nrom = nrom_cart };
    emu_state.loadCartridge(any_cart);

    // Reset CPU to load reset vector and initialize state
    emu_state.power_on();

    // ========================================================================
    // 2.5. Initialize Debugger (if debug flags enabled)
    // ========================================================================

    if (debug_flags.trace or
        debug_flags.break_at != null or
        debug_flags.watch != null or
        debug_flags.inspect)
    {
        emu_state.debugger = RAMBO.Debugger.Debugger.init(allocator, &config);

        // Configure breakpoints from CLI
        if (debug_flags.break_at) |addrs| {
            for (addrs) |addr| {
                emu_state.debugger.?.addBreakpoint(addr, .execute) catch {
                    continue;
                };
            }
        }

        // Configure watchpoints from CLI
        // TEMP: Disabled for diagnostic logging run
        _ = debug_flags.watch;
        // if (debug_flags.watch) |addrs| {
        //     for (addrs) |addr| {
        //         // TEMP: Watch reads for $2002 diagnostics
        //         const watch_type: RAMBO.Debugger.Watchpoint.WatchType = if (addr == 0x2002) .read else .write;
        //         emu_state.debugger.?.addWatchpoint(addr, 1, watch_type) catch {
        //             continue;
        //         };
        //     }
        // }
    }

    // Cleanup debugger on exit
    defer if (emu_state.debugger) |*d| d.deinit();

    // ========================================================================
    // 3. Initialize libxev Loop (Main Thread Coordinator)
    // ========================================================================

    var loop = try xev.Loop.init(.{});
    defer loop.deinit();

    // ========================================================================
    // 4. Spawn Threads
    // ========================================================================

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
                        std.debug.print("\n=== BREAKPOINT HIT ===\n", .{});
                        std.debug.print("Reason: {s}\n", .{reason});

                        if (debug_flags.inspect) {
                            handleCpuSnapshot(bp.snapshot);
                        }
                    },
                    .watchpoint_hit => |wp| {
                        const reason = wp.reason[0..wp.reason_len];
                        std.debug.print("\n=== WATCHPOINT HIT ===\n", .{});
                        std.debug.print("Reason: {s}\n", .{reason});

                        if (debug_flags.inspect) {
                            handleCpuSnapshot(wp.snapshot);
                        }
                    },
                    .inspect_response => |resp| {
                        handleCpuSnapshot(resp.snapshot);
                    },
                    .paused => |p| {
                        if (debug_flags.inspect) {
                            handleCpuSnapshot(p.snapshot);
                        }
                    },
                    .resumed => {},
                    .breakpoint_added => |_| {},
                    .breakpoint_removed => |_| {},
                    .error_occurred => |err| {
                        // TODO: Display error in GUI/TUI
                        _ = err.message;
                        _ = err.message_len;
                    },
                }
            }
        }

        // Run libxev loop (no_wait for polling)
        try loop.run(.no_wait);

        // Small sleep to avoid busy-waiting (main thread is just coordinating)
        std.Thread.sleep(100_000_000); // 100ms
    }

    // ========================================================================
    // 6. Shutdown
    // ========================================================================

    running.store(false, .release);

    emulation_thread.join();
    render_thread.join();
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
