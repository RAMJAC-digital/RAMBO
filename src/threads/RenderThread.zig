//! Render Thread Module
//!
//! Generic rendering backend thread using comptime polymorphism
//! Communicates with main/emulation threads via lock-free mailboxes
//!
//! Architecture:
//! - Comptime backend selection (Vulkan/Wayland or Movy/Terminal)
//! - Polls frame mailbox for new frames (SPSC consumer)
//! - Posts input events to main thread via mailboxes
//! - Zero-cost abstraction (comptime dispatch, no VTable)
//!
//! Status: Refactored for backend abstraction

const std = @import("std");
const Mailboxes = @import("../mailboxes/Mailboxes.zig").Mailboxes;
const Backend = @import("../video/Backend.zig").Backend;
const BackendConfig = @import("../video/Backend.zig").BackendConfig;

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

/// Generic render thread entry point using comptime backend selection
pub fn threadMain(
    comptime BackendImpl: type,
    mailboxes: *Mailboxes,
    running: *std.atomic.Value(bool),
    config: ThreadConfig,
) void {
    // Convert ThreadConfig to BackendConfig
    const backend_config = BackendConfig{
        .title = config.title,
        .width = config.width,
        .height = config.height,
        .verbose = config.verbose,
    };

    // Initialize backend (Vulkan/Wayland or Movy/Terminal)
    var backend = BackendImpl.init(std.heap.c_allocator, backend_config, mailboxes) catch {
        // Backend may not be available (e.g., Wayland in test environments)
        return;
    };
    defer backend.deinit();

    var ctx = RenderContext{
        .mailboxes = mailboxes,
        .running = running,
    };

    // Render loop
    var last_fps_report: i128 = std.time.nanoTimestamp();
    while (!backend.shouldClose() and running.load(.acquire)) {
        // 1. Poll backend for input events (non-blocking)
        backend.pollInput() catch {};

        // 2. Check for new frame from emulation thread
        if (mailboxes.frame.hasNewFrame()) {
            const frame_buffer = mailboxes.frame.getReadBuffer();

            // Render frame using backend
            // CRITICAL: consumeFrame() must be called AFTER renderFrame() succeeds
            // to prevent race condition where emulation thread reuses buffer during @memcpy
            backend.renderFrame(frame_buffer) catch {
                // On error, don't consume frame - will retry next iteration
                // This prevents frame loss when rendering operations fail transiently
                continue;
            };

            // Only consume frame after successful render (buffer no longer needed)
            mailboxes.frame.consumeFrame();
            ctx.frame_count += 1;

            // Report rendering FPS every second
            const now = std.time.nanoTimestamp();
            if (now - last_fps_report >= 1_000_000_000) {
                last_fps_report = now;
                ctx.frame_count = 0;
            }
        }

        // 3. Small sleep to avoid busy-wait
        std.Thread.sleep(1_000_000); // 1ms
    }
}

/// Spawn render thread with specified backend
/// Returns thread handle for joining later
pub fn spawn(
    comptime BackendImpl: type,
    mailboxes: *Mailboxes,
    running: *std.atomic.Value(bool),
    config: ThreadConfig,
) !std.Thread {
    // Create wrapper function with captured BackendImpl
    const Wrapper = struct {
        fn run(mboxes: *Mailboxes, run_flag: *std.atomic.Value(bool), cfg: ThreadConfig) void {
            threadMain(BackendImpl, mboxes, run_flag, cfg);
        }
    };

    return try std.Thread.spawn(.{}, Wrapper.run, .{ mailboxes, running, config });
}

// ============================================================================
// Tests
// ============================================================================

test "RenderThread: context initialization" {
    const allocator = std.testing.allocator;

    var mailboxes = try allocator.create(Mailboxes);
    mailboxes.* = Mailboxes.init(allocator);
    defer {
        mailboxes.deinit();
        allocator.destroy(mailboxes);
    }

    var running = std.atomic.Value(bool).init(true);

    var ctx = RenderContext{
        .mailboxes = mailboxes,
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
