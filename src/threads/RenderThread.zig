//! Render Thread Module
//!
//! Wayland window management + Vulkan rendering on dedicated thread
//! Communicates with main/emulation threads via lock-free mailboxes
//!
//! Architecture:
//! - Wayland window with XDG shell protocol
//! - Polls frame mailbox for new frames (SPSC consumer)
//! - Posts window/input events to main thread (SPSC producer)
//! - Vulkan rendering (Phase 2)
//!
//! Status: Phase 1 - Wayland Window ✅

const std = @import("std");
const xev = @import("xev");
const Mailboxes = @import("../mailboxes/Mailboxes.zig").Mailboxes;
const WaylandLogic = @import("../video/WaylandLogic.zig");

/// Context passed to render loop
pub const RenderContext = struct {
    /// Mailbox container for thread communication
    mailboxes: *Mailboxes,

    /// Atomic running flag (shared with main thread)
    running: *std.atomic.Value(bool),

    /// Frame counter for diagnostics
    frame_count: u64 = 0,

    /// Last time we reported FPS
    last_report_time: i128 = 0,

    /// Whether we've printed shutdown message
    shutdown_printed: bool = false,
};

/// Thread configuration
pub const ThreadConfig = struct {
    /// Window title
    title: []const u8 = "RAMBO NES Emulator",

    /// Initial window width (will resize to maintain 8:7 aspect ratio)
    width: u32 = 512,

    /// Initial window height
    height: u32 = 480,

    /// Enable vsync
    vsync: bool = true,

    /// Enable verbose logging
    verbose: bool = false,
};

/// Render thread entry point
/// Phase 1: Wayland window creation and event handling
/// Phase 2+: Vulkan rendering (TBD)
pub fn threadMain(
    mailboxes: *Mailboxes,
    running: *std.atomic.Value(bool),
    config: ThreadConfig,
) void {
    _ = config;

    std.debug.print("[Render] Thread started (TID: {d})\n", .{std.Thread.getCurrentId()});

    // Initialize Wayland window with mailbox dependency injection
    var wayland = WaylandLogic.init(std.heap.c_allocator, &mailboxes.xdg_window_event, &mailboxes.xdg_input_event) catch |err| {
        std.debug.print("[Render] Failed to initialize Wayland: {}\n", .{err});
        std.debug.print("[Render] Make sure Wayland compositor is running ($WAYLAND_DISPLAY)\n", .{});
        return;
    };
    defer WaylandLogic.deinit(&wayland);

    std.debug.print("[Render] Wayland window created successfully\n", .{});

    var ctx = RenderContext{
        .mailboxes = mailboxes,
        .running = running,
    };

    // Render loop
    while (!wayland.closed and running.load(.acquire)) {
        // 1. Dispatch Wayland events (non-blocking)
        _ = WaylandLogic.dispatchOnce(&wayland);

        // 2. Check for new frame from emulation thread
        if (mailboxes.frame.hasNewFrame()) {
            mailboxes.frame.consumeFrameFlag();
            ctx.frame_count += 1;

            // TODO Phase 2: Upload to Vulkan texture and render
            // try VulkanLogic.uploadTexture(&vulkan, pixels.?);
            // try VulkanLogic.renderFrame(&vulkan);
        }

        // 3. Small sleep to avoid busy-wait (will be removed in Phase 2 with vsync)
        std.Thread.sleep(1_000_000); // 1ms
    }

    std.debug.print("[Render] Thread stopping (window_closed={} running={})\n", .{
        wayland.closed,
        running.load(.acquire),
    });
}

/// Spawn render thread
/// Returns thread handle for joining later
pub fn spawn(
    mailboxes: *Mailboxes,
    running: *std.atomic.Value(bool),
    config: ThreadConfig,
) !std.Thread {
    return try std.Thread.spawn(.{}, threadMain, .{ mailboxes, running, config });
}

// ============================================================================
// Tests
// ============================================================================

test "RenderThread: context initialization" {
    const allocator = std.testing.allocator;

    var mailboxes = try Mailboxes.init(allocator);
    defer mailboxes.deinit();

    var running = std.atomic.Value(bool).init(true);

    var ctx = RenderContext{
        .mailboxes = &mailboxes,
        .running = &running,
    };

    try std.testing.expect(ctx.frame_count == 0);
    try std.testing.expect(ctx.running.load(.acquire) == true);
}

test "RenderThread: config defaults" {
    const config = ThreadConfig{};

    try std.testing.expectEqualStrings("RAMBO NES Emulator", config.title);
    try std.testing.expectEqual(@as(u32, 512), config.width);
    try std.testing.expectEqual(@as(u32, 480), config.height);
    try std.testing.expect(config.vsync == true);
}
