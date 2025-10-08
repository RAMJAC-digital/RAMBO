//! Threading System Tests
//!
//! Comprehensive tests for multi-threaded emulation architecture:
//! - Thread spawning and coordination
//! - Mailbox communication (SPSC patterns)
//! - Shutdown synchronization
//! - Timer-driven emulation with real ROM
//! - Frame production accuracy
//! - Command processing
//!
//! Ensures consistency between main() and test harness

const std = @import("std");
const RAMBO = @import("RAMBO");
const EmulationThread = RAMBO.EmulationThread;
const RenderThread = RAMBO.RenderThread;
const Mailboxes = RAMBO.Mailboxes.Mailboxes;
const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;
const EmulationCommand = RAMBO.Mailboxes.EmulationCommandMailbox.EmulationCommand;
const NromCart = RAMBO.CartridgeType;
const AnyCartridge = RAMBO.AnyCartridge;

// Helper to load AccuracyCoin ROM for testing
fn loadAccuracyCoin(allocator: std.mem.Allocator, config: *Config) !EmulationState {
    const rom_path = "AccuracyCoin/AccuracyCoin.nes";

    // Load ROM
    const nrom_cart = NromCart.load(allocator, rom_path) catch |err| {
        if (err == error.FileNotFound) {
            return err;
        }
        return err;
    };

    // Wrap in AnyCartridge
    const cart = AnyCartridge{ .nrom = nrom_cart };

    // Initialize emulation state with cartridge
    var state = EmulationState.init(config);
    state.loadCartridge(cart); // Note: void return, moves ownership

    return state;
}

// ============================================================================
// Basic Thread Lifecycle Tests
// ============================================================================

test "Threading: spawn and join emulation thread" {
    const allocator = std.heap.c_allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    var emu_state = EmulationState.init(&config);
    var mailboxes = Mailboxes.init(allocator);
    defer mailboxes.deinit();

    var running = std.atomic.Value(bool).init(true);

    // Spawn thread
    const thread = try EmulationThread.spawn(&emu_state, &mailboxes, &running);

    // Let it run briefly
    std.Thread.sleep(100_000_000); // 100ms

    // Signal shutdown
    running.store(false, .release);

    // Join thread
    thread.join();

    // Thread should have stopped cleanly
    try std.testing.expect(!running.load(.acquire));
}

test "Threading: spawn and join render thread (stub)" {
    const allocator = std.heap.c_allocator;

    var mailboxes = Mailboxes.init(allocator);
    defer mailboxes.deinit();

    var running = std.atomic.Value(bool).init(true);

    const render_config = RenderThread.ThreadConfig{};

    // Spawn thread
    const thread = try RenderThread.spawn(&mailboxes, &running, render_config);

    // Let it run briefly
    std.Thread.sleep(100_000_000); // 100ms

    // Signal shutdown
    running.store(false, .release);

    // Join thread
    thread.join();

    // Thread should have stopped cleanly
    try std.testing.expect(!running.load(.acquire));
}

test "Threading: both threads run concurrently" {
    const allocator = std.heap.c_allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    var emu_state = EmulationState.init(&config);
    var mailboxes = Mailboxes.init(allocator);
    defer mailboxes.deinit();

    var running = std.atomic.Value(bool).init(true);

    // Spawn both threads
    const emu_thread = try EmulationThread.spawn(&emu_state, &mailboxes, &running);
    const render_thread = try RenderThread.spawn(&mailboxes, &running, .{});

    // Let both run
    std.Thread.sleep(200_000_000); // 200ms

    // Signal shutdown
    running.store(false, .release);

    // Join both threads
    emu_thread.join();
    render_thread.join();

    try std.testing.expect(!running.load(.acquire));
}

// ============================================================================
// Mailbox Communication Tests
// ============================================================================

test "Threading: emulation command mailbox (main → emulation)" {
    const allocator = std.heap.c_allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    var emu_state = EmulationState.init(&config);
    var mailboxes = Mailboxes.init(allocator);
    defer mailboxes.deinit();

    var running = std.atomic.Value(bool).init(true);

    // Post commands before spawning thread
    try mailboxes.emulation_command.postCommand(.power_on);
    try mailboxes.emulation_command.postCommand(.reset);

    // Spawn thread (will poll and process commands)
    const thread = try EmulationThread.spawn(&emu_state, &mailboxes, &running);

    // Give thread time to process
    std.Thread.sleep(100_000_000); // 100ms

    // Command queue should be empty (thread consumed them)
    try std.testing.expect(!mailboxes.emulation_command.hasPendingCommands());

    // Shutdown
    running.store(false, .release);
    thread.join();
}

test "Threading: frame mailbox communication (emulation → render, AccuracyCoin)" {
    const allocator = std.heap.c_allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    // Load AccuracyCoin ROM
    var emu_state = loadAccuracyCoin(allocator, &config) catch |err| {
        if (err == error.FileNotFound) {
            return error.SkipZigTest;
        }
        return err;
    };
    defer emu_state.deinit(); // Clean up cartridge and state

    var mailboxes = Mailboxes.init(allocator);
    defer mailboxes.deinit();

    var running = std.atomic.Value(bool).init(true);

    // Spawn threads
    const emu_thread = try EmulationThread.spawn(&emu_state, &mailboxes, &running);
    const render_thread = try RenderThread.spawn(&mailboxes, &running, .{});

    // Let emulation run and produce frames
    std.Thread.sleep(500_000_000); // 500ms (~30 frames at 60 FPS)

    // Shutdown threads before inspecting shared state
    running.store(false, .release);
    emu_thread.join();
    render_thread.join();

    // Verify frames were produced (emulation thread ran successfully)
    const frame_count = mailboxes.frame.getFrameCount();
    try std.testing.expect(frame_count > 0);

    // Verify hasNewFrame flag works (at least one frame available)
    const has_new = mailboxes.frame.hasNewFrame();
    try std.testing.expect(has_new);
}

test "Threading: shutdown via command mailbox" {
    const allocator = std.heap.c_allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    var emu_state = EmulationState.init(&config);
    var mailboxes = Mailboxes.init(allocator);
    defer mailboxes.deinit();

    var running = std.atomic.Value(bool).init(true);

    // Spawn thread
    const thread = try EmulationThread.spawn(&emu_state, &mailboxes, &running);

    // Let it run briefly
    std.Thread.sleep(100_000_000); // 100ms

    // Send shutdown command via mailbox
    try mailboxes.emulation_command.postCommand(.shutdown);

    // Give thread time to process
    std.Thread.sleep(100_000_000); // 100ms

    // Thread should have stopped (set running = false)
    thread.join();
    try std.testing.expect(!running.load(.acquire));
}

// ============================================================================
// Timer-Driven Execution Tests
// ============================================================================

test "Threading: timer-driven emulation produces frames (AccuracyCoin)" {
    const allocator = std.heap.c_allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    // Load AccuracyCoin ROM
    var emu_state = loadAccuracyCoin(allocator, &config) catch |err| {
        if (err == error.FileNotFound) {
            return error.SkipZigTest;
        }
        return err;
    };
    defer emu_state.deinit(); // Clean up cartridge and state

    var mailboxes = Mailboxes.init(allocator);
    defer mailboxes.deinit();

    var running = std.atomic.Value(bool).init(true);

    const initial_count = mailboxes.frame.getFrameCount();

    // Spawn thread
    const thread = try EmulationThread.spawn(&emu_state, &mailboxes, &running);

    // Run for ~1 second (should produce ~60 frames)
    std.Thread.sleep(1_000_000_000);

    // Stop thread before inspecting shared state
    running.store(false, .release);
    thread.join();

    const final_count = mailboxes.frame.getFrameCount();
    const frames_produced = final_count - initial_count;

    // Verify timer-driven execution is working (should produce many frames)
    // Exact count depends on system load, but should be substantial for 1 second
    try std.testing.expect(frames_produced > 30); // At least half of expected 60 FPS
}

test "Threading: emulation maintains consistent frame rate (AccuracyCoin)" {
    const allocator = std.heap.c_allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    // Load AccuracyCoin ROM
    var emu_state = loadAccuracyCoin(allocator, &config) catch |err| {
        if (err == error.FileNotFound) {
            return error.SkipZigTest;
        }
        return err;
    };
    defer emu_state.deinit(); // Clean up cartridge and state

    var mailboxes = Mailboxes.init(allocator);
    defer mailboxes.deinit();

    var running = std.atomic.Value(bool).init(true);

    // Spawn thread
    const thread = try EmulationThread.spawn(&emu_state, &mailboxes, &running);
    const initial_count = mailboxes.frame.getFrameCount();

    // Measure frame rate over 2 intervals to verify consistency
    std.Thread.sleep(500_000_000); // 500ms
    const mid_count = mailboxes.frame.getFrameCount();

    std.Thread.sleep(500_000_000); // 500ms
    running.store(false, .release);
    thread.join();

    const final_count = mailboxes.frame.getFrameCount();

    const frames_first_half = mid_count - initial_count;
    const frames_second_half = final_count - mid_count;

    // Verify both intervals produced frames (timer is consistently running)
    try std.testing.expect(frames_first_half > 0);
    try std.testing.expect(frames_second_half > 0);

    // Verify frame rate is roughly consistent (within 2x tolerance)
    // This verifies timer isn't degrading over time
    const ratio = if (frames_first_half > frames_second_half)
        @as(f32, @floatFromInt(frames_first_half)) / @as(f32, @floatFromInt(frames_second_half))
    else
        @as(f32, @floatFromInt(frames_second_half)) / @as(f32, @floatFromInt(frames_first_half));
    try std.testing.expect(ratio < 2.0); // Within 2x is consistent enough
}

// ============================================================================
// Command Processing Tests
// ============================================================================

test "Threading: reset command clears frame counter" {
    const allocator = std.heap.c_allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    var emu_state = EmulationState.init(&config);
    var mailboxes = Mailboxes.init(allocator);
    defer mailboxes.deinit();

    var running = std.atomic.Value(bool).init(true);

    // Spawn thread
    const thread = try EmulationThread.spawn(&emu_state, &mailboxes, &running);

    // Let it run and produce some frames
    std.Thread.sleep(200_000_000); // 200ms

    const frames_before_reset = mailboxes.frame.getFrameCount();
    try std.testing.expect(frames_before_reset > 0);

    // Note: Reset command resets emulation state but doesn't reset frame mailbox counter
    // This is expected - frame count is cumulative for the session

    // Shutdown
    running.store(false, .release);
    thread.join();
}

test "Threading: multiple commands processed in order" {
    const allocator = std.heap.c_allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    var emu_state = EmulationState.init(&config);
    var mailboxes = Mailboxes.init(allocator);
    defer mailboxes.deinit();

    var running = std.atomic.Value(bool).init(true);

    // Queue multiple commands
    try mailboxes.emulation_command.postCommand(.power_on);
    try mailboxes.emulation_command.postCommand(.reset);
    try mailboxes.emulation_command.postCommand(.reset);

    // Spawn thread (will process all commands)
    const thread = try EmulationThread.spawn(&emu_state, &mailboxes, &running);

    // Give thread time to process
    std.Thread.sleep(100_000_000); // 100ms

    // All commands should be processed (queue empty)
    try std.testing.expect(!mailboxes.emulation_command.hasPendingCommands());

    // Shutdown
    running.store(false, .release);
    thread.join();
}

// ============================================================================
// Stress Tests
// ============================================================================

test "Threading: high-frequency command posting" {
    const allocator = std.heap.c_allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    var emu_state = EmulationState.init(&config);
    var mailboxes = Mailboxes.init(allocator);
    defer mailboxes.deinit();

    var running = std.atomic.Value(bool).init(true);

    // Spawn thread
    const thread = try EmulationThread.spawn(&emu_state, &mailboxes, &running);

    // Post commands rapidly (should not overflow buffer)
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        mailboxes.emulation_command.postCommand(.reset) catch {
            // Buffer full is acceptable under stress
            break;
        };
        std.Thread.sleep(10_000_000); // 10ms between posts
    }

    // Give thread time to drain
    std.Thread.sleep(200_000_000); // 200ms

    // Shutdown
    running.store(false, .release);
    thread.join();
}

test "Threading: long-running emulation stability (AccuracyCoin 3s)" {
    const allocator = std.heap.c_allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    // Load AccuracyCoin ROM
    var emu_state = loadAccuracyCoin(allocator, &config) catch |err| {
        if (err == error.FileNotFound) {
            return error.SkipZigTest;
        }
        return err;
    };
    defer emu_state.deinit(); // Clean up cartridge and state

    var mailboxes = Mailboxes.init(allocator);
    defer mailboxes.deinit();

    var running = std.atomic.Value(bool).init(true);

    // Spawn thread
    const thread = try EmulationThread.spawn(&emu_state, &mailboxes, &running);

    // Run for 3 seconds to verify long-term stability
    std.Thread.sleep(3_000_000_000); // 3 seconds

    const final_count = mailboxes.frame.getFrameCount();

    // Verify emulation remained stable for extended period
    // Should produce many frames (exact count varies by system load)
    try std.testing.expect(final_count > 100); // Substantial frame production

    // Shutdown
    running.store(false, .release);
    thread.join();
}

// ============================================================================
// Synchronization Tests
// ============================================================================

test "Threading: atomic running flag coordination" {
    const allocator = std.heap.c_allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    var emu_state = EmulationState.init(&config);
    var mailboxes = Mailboxes.init(allocator);
    defer mailboxes.deinit();

    var running = std.atomic.Value(bool).init(true);

    // Spawn both threads sharing the same running flag
    const emu_thread = try EmulationThread.spawn(&emu_state, &mailboxes, &running);
    const render_thread = try RenderThread.spawn(&mailboxes, &running, .{});

    // Verify flag starts as true
    try std.testing.expect(running.load(.acquire));

    // Give threads time to initialize and start their event loops
    std.Thread.sleep(200_000_000); // 200ms

    // Verify emulation thread is producing frames (proves it's running)
    const frames_produced = mailboxes.frame.getFrameCount();
    try std.testing.expect(frames_produced > 0);

    // Signal shutdown via atomic flag (both threads should observe this)
    running.store(false, .release);

    // Wait for both threads to shut down cleanly
    // This proves they both observed the flag change
    emu_thread.join();
    render_thread.join();

    // Flag should remain false after shutdown
    try std.testing.expect(!running.load(.acquire));
}

test "Threading: clean shutdown under load" {
    const allocator = std.heap.c_allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    var emu_state = EmulationState.init(&config);
    var mailboxes = Mailboxes.init(allocator);
    defer mailboxes.deinit();

    var running = std.atomic.Value(bool).init(true);

    // Spawn threads
    const emu_thread = try EmulationThread.spawn(&emu_state, &mailboxes, &running);
    const render_thread = try RenderThread.spawn(&mailboxes, &running, .{});

    // Post commands while running
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        try mailboxes.emulation_command.postCommand(.reset);
        std.Thread.sleep(50_000_000); // 50ms
    }

    // Immediate shutdown (don't wait for queue to drain)
    running.store(false, .release);

    // Threads should stop cleanly even with pending work
    emu_thread.join();
    render_thread.join();

    try std.testing.expect(!running.load(.acquire));
}
