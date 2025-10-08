const std = @import("std");
const RAMBO = @import("RAMBO");
const xev = @import("xev");
const EmulationThread = RAMBO.EmulationThread;
const RenderThread = RAMBO.RenderThread;

/// Main thread: Coordinator only (minimal work)
/// - Initialize resources
/// - Spawn threads
/// - Coordinate via libxev loop
/// - Wait for cleanup
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("RAMBO NES Emulator - Multi-Threaded Architecture\n", .{});
    std.debug.print("================================================\n", .{});
    std.debug.print("Main Thread:      Coordinator (TID: {d})\n", .{std.Thread.getCurrentId()});
    std.debug.print("Emulation Thread: Timer-driven execution (spawning...)\n", .{});
    std.debug.print("Render Thread:    Wayland + Vulkan (stub)\n\n", .{});

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

    // Load ROM if provided on command line
    var args_iter = try std.process.argsWithAllocator(allocator);
    defer args_iter.deinit();
    _ = args_iter.skip(); // Skip program name
    if (args_iter.next()) |rom_path| {
        std.debug.print("[Main] Loading ROM: {s}\n", .{rom_path});

        // Simple ROM loading (NROM/Mapper 0 only for now)
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
