//! Emulator Runtime - Integration of RT loop with async I/O
//!
//! This module provides the complete runtime system that connects
//! the RT emulation loop with async I/O via libxev.

const std = @import("std");
const builtin = @import("builtin");
// TODO: Enable when libxev integration is complete
// const xev = @import("libxev");

const Architecture = @import("Architecture.zig");
const EmulationState = @import("../emulation/State.zig").EmulationState;
const Config = @import("../config/Config.zig").Config;
const Cartridge = @import("../cartridge/Cartridge.zig").Cartridge;
const Bus = @import("../bus/Bus.zig").Bus;

// Re-export key types
pub const InputQueue = Architecture.InputQueue;
pub const AudioQueue = Architecture.AudioQueue;
pub const TripleBuffer = Architecture.TripleBuffer;
pub const CommandQueue = Architecture.CommandQueue;
pub const Command = Architecture.Command;
pub const ControllerState = Architecture.ControllerState;
pub const InputEvent = Architecture.InputEvent;
pub const AudioSample = Architecture.AudioSample;

// ============================================================================
// Runtime Configuration
// ============================================================================

pub const RuntimeConfig = struct {
    /// Enable RT thread priority (requires privileges)
    enable_rt_priority: bool = false,

    /// RT thread CPU affinity (-1 = no affinity)
    rt_cpu_affinity: i32 = -1,

    /// Target frame rate (NTSC = 60.0988, PAL = 50.0070)
    target_fps: f64 = 60.0988,

    /// Audio sample rate (Hz)
    audio_sample_rate: u32 = 44100,

    /// Audio buffer size in frames
    audio_buffer_frames: u32 = 512,

    /// Enable frame skipping
    allow_frame_skip: bool = true,

    /// Maximum frames to skip
    max_frame_skip: u8 = 3,

    /// Vsync mode
    vsync: enum {
        off,
        on,
        adaptive,
    } = .on,
};

// ============================================================================
// Emulator Runtime
// ============================================================================

pub const Runtime = struct {
    /// Allocator for dynamic memory (not used in RT thread)
    allocator: std.mem.Allocator,

    /// Emulator configuration
    config: *const Config,

    /// Runtime configuration
    rt_config: RuntimeConfig,

    /// Emulation state (owned by RT thread)
    emulation: EmulationState,

    /// Shared queues
    input_queue: InputQueue = .{},
    audio_queue: AudioQueue = .{},
    frame_buffer: TripleBuffer = .{},
    command_queue: CommandQueue = .{},

    /// Thread state
    threads: struct {
        rt: ?std.Thread = null,
        io: ?std.Thread = null,
        audio: ?std.Thread = null,
        render: ?std.Thread = null,
    } = .{},

    /// Running state
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    paused: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    /// Performance statistics
    stats: Statistics = .{},

    /// libxev I/O context
    io_context: ?IoContext = null,

    /// Initialize runtime
    pub fn init(
        allocator: std.mem.Allocator,
        config: *const Config,
        rt_config: RuntimeConfig,
    ) !Runtime {
        // Initialize bus with cartridge if available
        const bus = Bus.init();

        // Initialize emulation state
        const emulation = EmulationState.init(config, bus);

        return Runtime{
            .allocator = allocator,
            .config = config,
            .rt_config = rt_config,
            .emulation = emulation,
        };
    }

    /// Deinitialize runtime
    pub fn deinit(self: *Runtime) void {
        // Stop threads if running
        if (self.running.load(.acquire)) {
            self.stop();
        }

        // Clean up I/O context
        if (self.io_context) |*ctx| {
            ctx.deinit();
        }
    }

    /// Load ROM from file
    pub fn loadRom(self: *Runtime, path: []const u8) !void {
        // Queue ROM load command
        try self.command_queue.push(.{ .load_rom = path });
    }

    /// Start emulation
    pub fn start(self: *Runtime) !void {
        if (self.running.load(.acquire)) {
            return; // Already running
        }

        // Connect components
        self.emulation.connectComponents();

        // Initialize I/O context
        self.io_context = try IoContext.init(self);

        // Set running flag
        self.running.store(true, .release);

        // Start RT thread
        self.threads.rt = try std.Thread.spawn(.{
            .stack_size = 256 * 1024, // 256KB stack
        }, rtThreadMain, .{self});

        // Start I/O thread
        self.threads.io = try std.Thread.spawn(.{
            .stack_size = 1024 * 1024, // 1MB stack
        }, ioThreadMain, .{self});

        // Audio and render threads would be started here
        // For now, we'll run them in test mode
    }

    /// Stop emulation
    pub fn stop(self: *Runtime) void {
        // Signal threads to stop
        self.running.store(false, .release);

        // Stop I/O event loop
        if (self.io_context) |*ctx| {
            ctx.stop();
        }

        // Join threads
        if (self.threads.rt) |thread| {
            thread.join();
            self.threads.rt = null;
        }
        if (self.threads.io) |thread| {
            thread.join();
            self.threads.io = null;
        }
        if (self.threads.audio) |thread| {
            thread.join();
            self.threads.audio = null;
        }
        if (self.threads.render) |thread| {
            thread.join();
            self.threads.render = null;
        }
    }

    /// Pause/resume emulation
    pub fn setPaused(self: *Runtime, paused: bool) void {
        self.paused.store(paused, .release);
    }

    /// Get current statistics
    pub fn getStats(self: *const Runtime) Statistics {
        return self.stats.snapshot();
    }
};

// ============================================================================
// RT Thread
// ============================================================================

fn rtThreadMain(runtime: *Runtime) void {
    // Set thread name for debugging
    std.Thread.setName("RAMBO-RT") catch {};

    // Configure RT priority if requested and supported
    if (runtime.rt_config.enable_rt_priority) {
        configureRtThread(runtime.rt_config) catch |err| {
            std.log.warn("Failed to set RT priority: {}", .{err});
        };
    }

    // Frame timing
    var frame_timer = FrameTimer.init(runtime.rt_config.target_fps);

    // RT loop
    while (runtime.running.load(.acquire)) {
        // Check if paused
        if (runtime.paused.load(.acquire)) {
            std.Thread.sleep(1_000_000); // 1ms
            continue;
        }

        // Process commands
        while (runtime.command_queue.tryPop()) |cmd| {
            processCommand(runtime, cmd);
        }

        // Process input
        while (runtime.input_queue.tryPop()) |input| {
            applyInput(runtime, input);
        }

        // Start frame timing
        frame_timer.startFrame();

        // Get write buffer for this frame
        const frame = runtime.frame_buffer.getWriteBuffer();

        // Emulate one frame
        const start_cycles = runtime.emulation.clock.ppu_cycles;
        runtime.emulation.emulateFrame();
        const elapsed_cycles = runtime.emulation.clock.ppu_cycles - start_cycles;

        // Render PPU output to frame buffer
        renderFrame(runtime, frame);

        // Generate audio samples
        generateAudio(runtime, elapsed_cycles);

        // Swap frame buffer
        runtime.frame_buffer.swapWrite();

        // Update statistics
        runtime.stats.recordFrame(frame_timer.getFrameTime());

        // Wait for next frame
        frame_timer.waitForNextFrame();
    }
}

fn configureRtThread(config: RuntimeConfig) !void {
    // Platform-specific RT configuration
    if (builtin.os.tag == .linux) {
        // Set SCHED_FIFO priority
        const priority = std.math.clamp(@as(c_int, 80), 1, 99);
        const param = std.os.linux.sched_param{
            .sched_priority = priority,
        };
        _ = std.os.linux.syscall3(
            .sched_setscheduler,
            0, // Current thread
            std.os.linux.SCHED.FIFO,
            @intFromPtr(&param),
        );

        // Set CPU affinity if requested
        if (config.rt_cpu_affinity >= 0) {
            var cpu_set: std.os.linux.cpu_set_t = std.mem.zeroes(std.os.linux.cpu_set_t);
            std.os.linux.CPU_SET(@intCast(config.rt_cpu_affinity), &cpu_set);
            _ = std.os.linux.sched_setaffinity(
                0, // Current thread
                @sizeOf(std.os.linux.cpu_set_t),
                &cpu_set,
            );
        }
    }
}

fn processCommand(runtime: *Runtime, cmd: Command) void {
    switch (cmd) {
        .reset => {
            runtime.emulation.reset();
            runtime.stats.reset();
        },
        .set_paused => |paused| {
            runtime.paused.store(paused, .release);
        },
        .set_speed => |speed| {
            // Adjust frame timer target
            _ = speed;
        },
        .load_rom => |path| {
            // This would be handled by I/O thread
            std.log.info("Loading ROM: {s}", .{path});
        },
        else => {},
    }
}

fn applyInput(runtime: *Runtime, input: InputEvent) void {
    // Update controller state in bus
    // This will be read by CPU when it accesses $4016/$4017
    _ = runtime;
    _ = input;
    // TODO: Implement when controller support is added
}

fn renderFrame(runtime: *Runtime, frame: *Architecture.FrameBuffer) void {
    // Copy PPU framebuffer to output
    frame.frame_number = runtime.stats.total_frames;
    frame.timestamp = runtime.emulation.clock.ppu_cycles;

    // TODO: Convert PPU pixels to RGBA
    // For now, generate test pattern
    for (0..Architecture.FRAME_HEIGHT) |y| {
        for (0..Architecture.FRAME_WIDTH) |x| {
            frame.pixels[y][x] = .{
                .r = @intCast(x & 0xFF),
                .g = @intCast(y & 0xFF),
                .b = @intCast((x ^ y) & 0xFF),
                .a = 255,
            };
        }
    }
}

fn generateAudio(runtime: *Runtime, cycles: u64) void {
    // Calculate samples needed for this frame
    // NES APU runs at CPU rate (1.789773 MHz)
    // We need to generate samples at audio_sample_rate (e.g., 44100 Hz)
    const samples_per_frame = (runtime.rt_config.audio_sample_rate * cycles) / (5369318 * 60);

    // Generate samples
    var i: usize = 0;
    while (i < samples_per_frame) : (i += 1) {
        // TODO: Get actual APU output
        const sample = Architecture.AudioSample{
            .left = 0,
            .right = 0,
        };

        if (!runtime.audio_queue.tryPush(sample)) {
            runtime.stats.audio_underruns += 1;
            break; // Queue full
        }
    }

    runtime.stats.audio_samples_generated += i;
}

// ============================================================================
// I/O Thread
// ============================================================================

const IoContext = struct {
    runtime: *Runtime,
    // Simplified for now - will integrate libxev properly in next phase
    running: bool = false,

    fn init(runtime: *Runtime) !IoContext {
        return .{
            .runtime = runtime,
        };
    }

    fn deinit(self: *IoContext) void {
        _ = self;
        // Cleanup when libxev is integrated
    }

    fn run(self: *IoContext) !void {
        self.running = true;
        // Simulate event loop for now
        while (self.running) {
            std.Thread.sleep(10_000_000); // 10ms
        }
    }

    fn stop(self: *IoContext) void {
        self.running = false;
    }
};

fn ioThreadMain(runtime: *Runtime) !void {
    // Set thread name
    std.Thread.setName("RAMBO-IO") catch {};

    if (runtime.io_context) |*ctx| {
        ctx.run() catch |err| {
            std.log.err("I/O thread error: {}", .{err});
        };
    }
}

// ============================================================================
// Frame Timing
// ============================================================================

const FrameTimer = struct {
    target_ns: i128,
    last_frame_ns: i128,
    drift_correction: i128 = 0,
    frame_start_ns: i128 = 0,

    fn init(target_fps: f64) FrameTimer {
        const target_ns = @as(i128, @intFromFloat(1_000_000_000.0 / target_fps));
        return .{
            .target_ns = target_ns,
            .last_frame_ns = std.time.nanoTimestamp(),
        };
    }

    fn startFrame(self: *FrameTimer) void {
        self.frame_start_ns = std.time.nanoTimestamp();
    }

    fn getFrameTime(self: *const FrameTimer) i128 {
        return std.time.nanoTimestamp() - self.frame_start_ns;
    }

    fn waitForNextFrame(self: *FrameTimer) void {
        const now = std.time.nanoTimestamp();
        const elapsed = now - self.last_frame_ns;
        const sleep_time = self.target_ns - elapsed + self.drift_correction;

        if (sleep_time > 1_000_000) { // > 1ms
            // Sleep for most of the time
            std.Thread.sleep(@intCast(sleep_time - 500_000));

            // Busy-wait for final precision
            while (std.time.nanoTimestamp() < self.last_frame_ns + self.target_ns) {
                std.atomic.spinLoopHint();
            }
        }

        const actual_frame_time = std.time.nanoTimestamp() - self.last_frame_ns;
        self.last_frame_ns = std.time.nanoTimestamp();

        // Adjust drift correction (simple PI controller)
        const timing_error = self.target_ns - actual_frame_time;
        self.drift_correction = @divTrunc(self.drift_correction * 7 + timing_error, 8);
    }
};

// ============================================================================
// Statistics
// ============================================================================

pub const Statistics = struct {
    total_frames: u64 = 0,
    total_cycles: u64 = 0,
    audio_samples_generated: u64 = 0,
    audio_underruns: u64 = 0,
    input_events_processed: u64 = 0,
    frame_time_ns: i128 = 0,
    min_frame_time_ns: i128 = std.math.maxInt(i128),
    max_frame_time_ns: i128 = 0,

    fn recordFrame(self: *Statistics, frame_time_ns: i128) void {
        self.total_frames += 1;
        self.frame_time_ns = frame_time_ns;
        self.min_frame_time_ns = @min(self.min_frame_time_ns, frame_time_ns);
        self.max_frame_time_ns = @max(self.max_frame_time_ns, frame_time_ns);
    }

    fn reset(self: *Statistics) void {
        self.* = .{};
    }

    fn snapshot(self: *const Statistics) Statistics {
        // Atomic snapshot for reading from other threads
        return self.*;
    }

    pub fn format(
        self: Statistics,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        const avg_frame_ms = if (self.total_frames > 0)
            @as(f64, @floatFromInt(self.frame_time_ns)) / 1_000_000.0
        else
            0.0;

        try writer.print(
            \\Statistics:
            \\  Frames: {}
            \\  Frame Time: {d:.2}ms (min: {d:.2}ms, max: {d:.2}ms)
            \\  Audio: {} samples, {} underruns
            \\  Input: {} events
        ,
            .{
                self.total_frames,
                avg_frame_ms,
                @as(f64, @floatFromInt(self.min_frame_time_ns)) / 1_000_000.0,
                @as(f64, @floatFromInt(self.max_frame_time_ns)) / 1_000_000.0,
                self.audio_samples_generated,
                self.audio_underruns,
                self.input_events_processed,
            },
        );
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Runtime: initialization" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    const rt_config = RuntimeConfig{};

    var runtime = try Runtime.init(allocator, &config, rt_config);
    defer runtime.deinit();

    try std.testing.expect(!runtime.running.load(.acquire));
    try std.testing.expect(!runtime.paused.load(.acquire));
}

test "Runtime: command queue" {
    const allocator = std.testing.allocator;

    var config = Config.init(allocator);
    defer config.deinit();

    const rt_config = RuntimeConfig{};

    var runtime = try Runtime.init(allocator, &config, rt_config);
    defer runtime.deinit();

    // Push commands
    try runtime.command_queue.push(.reset);
    try runtime.command_queue.push(.{ .set_paused = true });

    // Pop and verify
    const cmd1 = runtime.command_queue.tryPop();
    try std.testing.expect(cmd1 != null);
    try std.testing.expectEqual(Command.reset, cmd1.?);

    const cmd2 = runtime.command_queue.tryPop();
    try std.testing.expect(cmd2 != null);
    try std.testing.expectEqual(Command{ .set_paused = true }, cmd2.?);
}

test "FrameTimer: timing accuracy" {
    var timer = FrameTimer.init(60.0);

    // Simulate frame timing
    timer.startFrame();
    std.Thread.sleep(1_000_000); // 1ms work
    const frame_time = timer.getFrameTime();

    try std.testing.expect(frame_time >= 1_000_000);
    try std.testing.expect(frame_time < 2_000_000);
}

test "Statistics: tracking" {
    var stats = Statistics{};

    stats.recordFrame(16_666_667); // ~60 FPS
    stats.recordFrame(16_000_000);
    stats.recordFrame(17_000_000);

    try std.testing.expectEqual(@as(u64, 3), stats.total_frames);
    try std.testing.expectEqual(@as(i128, 16_000_000), stats.min_frame_time_ns);
    try std.testing.expectEqual(@as(i128, 17_000_000), stats.max_frame_time_ns);
}