//! Async I/O Architecture for RAMBO NES Emulator
//!
//! This module defines the RT/OS boundary architecture using libxev for
//! async I/O operations while maintaining cycle-accurate emulation timing.
//!
//! Architecture Overview:
//! ======================
//!
//! ```
//!     ┌─────────────────────────────────────────────────────────────┐
//!     │                        RT THREAD                            │
//!     │  ┌──────────────────────────────────────────────────────┐  │
//!     │  │ EmulationState (pure state machine)                  │  │
//!     │  │ - CPU: tick() @ 1.79 MHz                             │  │
//!     │  │ - PPU: tick() @ 5.37 MHz                             │  │
//!     │  │ - APU: tick() @ 1.79 MHz                             │  │
//!     │  └──────────────────────────────────────────────────────┘  │
//!     │                           ▲ ▼                               │
//!     │  ┌──────────────────────────────────────────────────────┐  │
//!     │  │ Lock-free Ring Buffers (SPSC)                        │  │
//!     │  │ - Controller input (8 bytes × 256 entries)           │  │
//!     │  │ - Audio samples (4 bytes × 2048 entries)             │  │
//!     │  │ - Frame buffer (256×240×4 bytes, triple-buffered)    │  │
//!     │  └──────────────────────────────────────────────────────┘  │
//!     └─────────────────────────────────────────────────────────────┘
//!                                    ║
//!     ═══════════════════════════════════════════════════════════════
//!                                    ║
//!     ┌─────────────────────────────────────────────────────────────┐
//!     │                        I/O THREAD                           │
//!     │  ┌──────────────────────────────────────────────────────┐  │
//!     │  │ libxev Event Loop                                    │  │
//!     │  │ - File I/O (io_uring on Linux)                       │  │
//!     │  │ - Timers (frame pacing)                              │  │
//!     │  │ - Network (future: netplay)                          │  │
//!     │  └──────────────────────────────────────────────────────┘  │
//!     │  ┌──────────────────────────────────────────────────────┐  │
//!     │  │ Command Queue (MPSC)                                 │  │
//!     │  │ - Load ROM, Save state, Config changes               │  │
//!     │  └──────────────────────────────────────────────────────┘  │
//!     └─────────────────────────────────────────────────────────────┘
//!                                    ║
//!     ┌─────────────────────────────────────────────────────────────┐
//!     │                     RENDER THREAD                           │
//!     │  OpenGL/Vulkan context, vsync, shader compilation           │
//!     └─────────────────────────────────────────────────────────────┘
//!                                    ║
//!     ┌─────────────────────────────────────────────────────────────┐
//!     │                      AUDIO THREAD                           │
//!     │  PipeWire/ALSA callback, resampling, buffering              │
//!     └─────────────────────────────────────────────────────────────┘
//! ```

const std = @import("std");
// TODO: Enable when libxev integration is complete
// const xev = @import("libxev");

// ============================================================================
// Lock-free SPSC Ring Buffer
// ============================================================================

/// Single Producer, Single Consumer ring buffer with cache-line padding
/// Uses acquire-release memory ordering for minimal overhead
pub fn RingBuffer(comptime T: type, comptime capacity: usize) type {
    // Ensure power of 2 for fast modulo
    comptime {
        if (!std.math.isPowerOfTwo(capacity)) {
            @compileError("RingBuffer capacity must be power of 2");
        }
    }

    return struct {
        const Self = @This();
        const CACHE_LINE = 64; // Typical cache line size

        // Separate cache lines to avoid false sharing
        head: std.atomic.Value(usize) align(CACHE_LINE) = std.atomic.Value(usize).init(0),
        _pad1: [CACHE_LINE - @sizeOf(usize)]u8 = undefined,

        tail: std.atomic.Value(usize) align(CACHE_LINE) = std.atomic.Value(usize).init(0),
        _pad2: [CACHE_LINE - @sizeOf(usize)]u8 = undefined,

        buffer: [capacity]T align(CACHE_LINE) = undefined,

        /// Producer: Try to push item, returns false if full
        pub fn tryPush(self: *Self, item: T) bool {
            const current_tail = self.tail.load(.monotonic);
            const next_tail = (current_tail + 1) & (capacity - 1);

            // Check if full
            if (next_tail == self.head.load(.acquire)) {
                return false;
            }

            self.buffer[current_tail] = item;
            self.tail.store(next_tail, .release);
            return true;
        }

        /// Consumer: Try to pop item, returns null if empty
        pub fn tryPop(self: *Self) ?T {
            const current_head = self.head.load(.monotonic);
            const current_tail = self.tail.load(.acquire);

            // Check if empty
            if (current_head == current_tail) {
                return null;
            }

            const item = self.buffer[current_head];
            const next_head = (current_head + 1) & (capacity - 1);
            self.head.store(next_head, .release);
            return item;
        }

        /// Get number of items in buffer (approximate, may be stale)
        pub fn size(self: *const Self) usize {
            const tail = self.tail.load(.acquire);
            const head = self.head.load(.acquire);
            return (tail -% head) & (capacity - 1);
        }

        /// Check if buffer is empty (consumer side)
        pub fn isEmpty(self: *const Self) bool {
            return self.head.load(.monotonic) == self.tail.load(.acquire);
        }

        /// Check if buffer is full (producer side)
        pub fn isFull(self: *const Self) bool {
            const current_tail = self.tail.load(.monotonic);
            const next_tail = (current_tail + 1) & (capacity - 1);
            return next_tail == self.head.load(.acquire);
        }
    };
}

// ============================================================================
// Controller Input
// ============================================================================

/// NES controller state (8 buttons)
pub const ControllerState = packed struct {
    a: bool = false,
    b: bool = false,
    select: bool = false,
    start: bool = false,
    up: bool = false,
    down: bool = false,
    left: bool = false,
    right: bool = false,
};

/// Timestamped controller input for frame-perfect replay
pub const InputEvent = struct {
    /// PPU cycle when input was sampled
    timestamp: u64,
    /// Controller states (up to 4 controllers)
    controllers: [4]ControllerState,
};

/// Input ring buffer (256 entries = ~4 frames of input at 60Hz)
pub const InputQueue = RingBuffer(InputEvent, 256);

// ============================================================================
// Audio Output
// ============================================================================

/// Stereo audio sample (16-bit signed PCM)
pub const AudioSample = struct {
    left: i16,
    right: i16,
};

/// Audio ring buffer (2048 samples = ~46ms at 44.1kHz)
/// Size chosen to be larger than typical audio callback period (5-20ms)
pub const AudioQueue = RingBuffer(AudioSample, 2048);

// ============================================================================
// Video Output (Triple Buffering)
// ============================================================================

/// NES frame dimensions
pub const FRAME_WIDTH = 256;
pub const FRAME_HEIGHT = 240;

/// RGBA8888 pixel format for modern GPUs
pub const Pixel = packed struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

/// Frame buffer for one complete frame
pub const FrameBuffer = struct {
    /// Pixel data (256×240 RGBA)
    pixels: [FRAME_HEIGHT][FRAME_WIDTH]Pixel = undefined,
    /// Frame number for synchronization
    frame_number: u64 = 0,
    /// Timestamp when frame was completed (PPU cycles)
    timestamp: u64 = 0,
};

/// Triple buffering state for tear-free rendering
pub const TripleBuffer = struct {
    /// Three frame buffers
    buffers: [3]FrameBuffer align(64) = .{.{}, .{}, .{}},

    /// Index of buffer being written by RT thread (0-2)
    write_index: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),

    /// Index of buffer ready for display (0-2 or 255 if none)
    ready_index: std.atomic.Value(u8) = std.atomic.Value(u8).init(255),

    /// Index of buffer being displayed (0-2 or 255 if none)
    display_index: std.atomic.Value(u8) = std.atomic.Value(u8).init(255),

    /// RT thread: Get writable buffer (always succeeds)
    pub fn getWriteBuffer(self: *TripleBuffer) *FrameBuffer {
        const idx = self.write_index.load(.monotonic);
        return &self.buffers[idx];
    }

    /// RT thread: Swap write buffer to ready
    pub fn swapWrite(self: *TripleBuffer) void {
        const write_idx = self.write_index.load(.monotonic);
        const next_write = (write_idx + 1) % 3;

        // Make current write buffer ready
        self.ready_index.store(write_idx, .release);

        // Move to next write buffer
        self.write_index.store(next_write, .release);
    }

    /// Render thread: Get buffer for display (may return null)
    pub fn getDisplayBuffer(self: *TripleBuffer) ?*FrameBuffer {
        const ready_idx = self.ready_index.swap(255, .acquire);
        if (ready_idx == 255) return null;

        // Release previous display buffer if any
        const prev_display = self.display_index.swap(ready_idx, .release);
        if (prev_display != 255) {
            // Previous buffer becomes available for writing
            // (handled implicitly by triple buffer rotation)
        }

        return &self.buffers[ready_idx];
    }
};

// ============================================================================
// Command Queue (MPSC for configuration changes)
// ============================================================================

/// Commands sent from UI/network to RT thread
pub const Command = union(enum) {
    /// Load a new ROM
    load_rom: []const u8, // Path to ROM file

    /// Save emulation state
    save_state: u8, // Slot number (0-9)

    /// Load emulation state
    load_state: u8, // Slot number (0-9)

    /// Reset emulation
    reset: void,

    /// Pause/resume emulation
    set_paused: bool,

    /// Set emulation speed (1.0 = normal)
    set_speed: f32,

    /// Configure video filter
    set_filter: VideoFilter,

    /// Configure audio sample rate
    set_sample_rate: u32,
};

pub const VideoFilter = enum {
    nearest,
    bilinear,
    crt_shader,
    xbrz_2x,
    xbrz_4x,
};

/// MPSC command queue using mutex (commands are infrequent)
pub const CommandQueue = struct {
    const MAX_COMMANDS = 64;

    mutex: std.Thread.Mutex = .{},
    commands: [MAX_COMMANDS]Command = undefined,
    head: usize = 0,
    tail: usize = 0,

    /// Producer: Push command (may block briefly)
    pub fn push(self: *CommandQueue, cmd: Command) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const next_tail = (self.tail + 1) % MAX_COMMANDS;
        if (next_tail == self.head) {
            return error.QueueFull;
        }

        self.commands[self.tail] = cmd;
        self.tail = next_tail;
    }

    /// Consumer: Try to pop command (non-blocking)
    pub fn tryPop(self: *CommandQueue) ?Command {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.head == self.tail) {
            return null;
        }

        const cmd = self.commands[self.head];
        self.head = (self.head + 1) % MAX_COMMANDS;
        return cmd;
    }
};

// ============================================================================
// I/O Context (libxev integration)
// ============================================================================

/// I/O thread context with libxev event loop
/// TODO: Enable when libxev integration is complete
pub const IoContext = struct {
    /// Placeholder for libxev integration
    placeholder: bool = true,

    /// Initialize I/O context
    pub fn init(allocator: std.mem.Allocator) !IoContext {
        _ = allocator; // Will be used for buffer allocation
        return .{};
    }

    /// Deinitialize I/O context
    pub fn deinit(self: *IoContext) void {
        _ = self;
        // Cleanup will happen when libxev is properly integrated
    }

    // TODO: Implement these methods when libxev is integrated
    // loadRomAsync()
    // startFrameTimer()
    // run()
    // stop()
};

// ============================================================================
// RT Thread Context
// ============================================================================

/// Real-time emulation thread context
pub const RtContext = struct {
    /// Emulation state machine
    state: *EmulationState,

    /// Input queue (consumer)
    input_queue: *InputQueue,

    /// Audio queue (producer)
    audio_queue: *AudioQueue,

    /// Frame buffer (producer)
    frame_buffer: *TripleBuffer,

    /// Command queue (consumer)
    command_queue: *CommandQueue,

    /// Performance counters
    stats: struct {
        frames_rendered: u64 = 0,
        audio_underruns: u64 = 0,
        input_drops: u64 = 0,
        cycles_executed: u64 = 0,
    } = .{},

    /// Process one frame of emulation
    pub fn emulateFrame(self: *RtContext) void {
        // Process commands (configuration changes, ROM loads, etc.)
        while (self.command_queue.tryPop()) |cmd| {
            self.processCommand(cmd);
        }

        // Process input events
        while (self.input_queue.tryPop()) |input| {
            self.applyInput(input);
        }

        // Get writable frame buffer
        const frame = self.frame_buffer.getWriteBuffer();

        // Run emulation until frame complete
        const start_cycles = self.state.clock.ppu_cycles;
        self.state.emulateFrame();
        const elapsed_cycles = self.state.clock.ppu_cycles - start_cycles;

        // Copy PPU output to frame buffer
        self.copyPpuOutput(frame);

        // Generate audio samples for this frame
        self.generateAudioSamples(elapsed_cycles);

        // Swap frame buffer to ready
        self.frame_buffer.swapWrite();

        // Update stats
        self.stats.frames_rendered += 1;
        self.stats.cycles_executed += elapsed_cycles;
    }

    fn processCommand(self: *RtContext, cmd: Command) void {
        switch (cmd) {
            .reset => self.state.reset(),
            .set_paused => |paused| {
                // Handle pause state
                _ = paused;
            },
            // ... handle other commands
            else => {},
        }
    }

    fn applyInput(self: *RtContext, input: InputEvent) void {
        // Apply controller state to emulation
        // This would update controller registers in the bus
        _ = self;
        _ = input;
    }

    fn copyPpuOutput(self: *RtContext, frame: *FrameBuffer) void {
        // Copy PPU framebuffer to output
        // This is where PPU pixels would be converted to RGBA
        frame.frame_number = self.stats.frames_rendered;
        frame.timestamp = self.state.clock.ppu_cycles;
    }

    fn generateAudioSamples(self: *RtContext, cycles: u64) void {
        // Generate audio samples based on APU state
        // ~735 samples per frame at 44.1kHz
        const samples_needed = (cycles * 44100) / 5369318; // PPU cycles to samples

        var i: usize = 0;
        while (i < samples_needed) : (i += 1) {
            const sample = AudioSample{
                .left = 0,  // TODO: APU output
                .right = 0, // TODO: APU output
            };

            if (!self.audio_queue.tryPush(sample)) {
                self.stats.audio_underruns += 1;
                break;
            }
        }
    }
};

// ============================================================================
// Thread Configuration
// ============================================================================

/// Thread priorities and CPU affinity
pub const ThreadConfig = struct {
    /// RT thread configuration
    rt: struct {
        /// Scheduler priority (1-99 for SCHED_FIFO on Linux)
        priority: u8 = 80,
        /// CPU core affinity (-1 for no affinity)
        cpu_affinity: i8 = -1,
        /// Stack size in bytes
        stack_size: usize = 256 * 1024, // 256 KB
    } = .{},

    /// I/O thread configuration
    io: struct {
        priority: u8 = 50,
        cpu_affinity: i8 = -1,
        stack_size: usize = 1024 * 1024, // 1 MB
    } = .{},

    /// Render thread configuration
    render: struct {
        priority: u8 = 40,
        cpu_affinity: i8 = -1,
        stack_size: usize = 2 * 1024 * 1024, // 2 MB
    } = .{},

    /// Audio thread configuration
    audio: struct {
        priority: u8 = 70, // High priority for low latency
        cpu_affinity: i8 = -1,
        stack_size: usize = 256 * 1024, // 256 KB
    } = .{},
};

// ============================================================================
// Memory Management Strategy
// ============================================================================

/// RT-safe allocator with pre-allocated pools
pub const RtAllocator = struct {
    /// No allocations allowed in RT context!
    /// All memory must be pre-allocated during initialization

    /// Pre-allocated save state buffers (10 slots)
    save_states: [10][64 * 1024]u8 = undefined, // 64KB per state

    /// Pre-allocated ROM buffer (max 1MB)
    rom_buffer: [1024 * 1024]u8 = undefined,

    /// Scratch buffer for temporary operations
    scratch: [4096]u8 = undefined,
};

// ============================================================================
// Integration Example
// ============================================================================

const EmulationState = @import("../emulation/State.zig").EmulationState;

/// Complete emulator runtime with all threads
pub const EmulatorRuntime = struct {
    /// Shared data structures
    input_queue: InputQueue = .{},
    audio_queue: AudioQueue = .{},
    frame_buffer: TripleBuffer = .{},
    command_queue: CommandQueue = .{},

    /// Thread contexts
    rt_context: RtContext,
    io_context: IoContext,

    /// Thread handles
    rt_thread: ?std.Thread = null,
    io_thread: ?std.Thread = null,
    render_thread: ?std.Thread = null,
    audio_thread: ?std.Thread = null,

    /// Running state
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn init(
        allocator: std.mem.Allocator,
        state: *EmulationState,
    ) !EmulatorRuntime {
        return .{
            .rt_context = .{
                .state = state,
                .input_queue = undefined, // Set after init
                .audio_queue = undefined,
                .frame_buffer = undefined,
                .command_queue = undefined,
            },
            .io_context = try IoContext.init(allocator),
        };
    }

    pub fn start(self: *EmulatorRuntime) !void {
        // Connect contexts to shared queues
        self.rt_context.input_queue = &self.input_queue;
        self.rt_context.audio_queue = &self.audio_queue;
        self.rt_context.frame_buffer = &self.frame_buffer;
        self.rt_context.command_queue = &self.command_queue;

        self.running.store(true, .release);

        // Start threads
        self.rt_thread = try std.Thread.spawn(.{
            .stack_size = 256 * 1024,
        }, rtThreadMain, .{self});

        self.io_thread = try std.Thread.spawn(.{
            .stack_size = 1024 * 1024,
        }, ioThreadMain, .{self});

        // Render and audio threads would be started here
    }

    pub fn stop(self: *EmulatorRuntime) void {
        self.running.store(false, .release);
        self.io_context.stop();

        if (self.rt_thread) |thread| thread.join();
        if (self.io_thread) |thread| thread.join();
        if (self.render_thread) |thread| thread.join();
        if (self.audio_thread) |thread| thread.join();
    }

    fn rtThreadMain(runtime: *EmulatorRuntime) void {
        // Set thread priority (platform-specific)
        // setThreadPriority(80);

        while (runtime.running.load(.acquire)) {
            runtime.rt_context.emulateFrame();

            // Frame pacing (could use busy-wait for lower latency)
            std.time.sleep(16_666_667); // ~60 FPS
        }
    }

    fn ioThreadMain(runtime: *EmulatorRuntime) !void {
        try runtime.io_context.run();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "RingBuffer: basic push/pop" {
    var ring = RingBuffer(u32, 16){};

    // Push some items
    try std.testing.expect(ring.tryPush(42));
    try std.testing.expect(ring.tryPush(43));
    try std.testing.expect(ring.tryPush(44));

    // Pop them back
    try std.testing.expectEqual(@as(u32, 42), ring.tryPop().?);
    try std.testing.expectEqual(@as(u32, 43), ring.tryPop().?);
    try std.testing.expectEqual(@as(u32, 44), ring.tryPop().?);

    // Should be empty
    try std.testing.expect(ring.isEmpty());
    try std.testing.expectEqual(@as(?u32, null), ring.tryPop());
}

test "RingBuffer: full condition" {
    var ring = RingBuffer(u8, 4){}; // Small buffer for testing

    // Fill buffer (capacity - 1 items)
    try std.testing.expect(ring.tryPush(1));
    try std.testing.expect(ring.tryPush(2));
    try std.testing.expect(ring.tryPush(3));

    // Should be full now
    try std.testing.expect(ring.isFull());
    try std.testing.expect(!ring.tryPush(4));

    // Pop one item
    _ = ring.tryPop();

    // Should be able to push again
    try std.testing.expect(ring.tryPush(4));
}

test "TripleBuffer: write and display" {
    var triple = TripleBuffer{};

    // Get write buffer
    const write_buf = triple.getWriteBuffer();
    write_buf.frame_number = 1;

    // Initially no buffer ready for display
    try std.testing.expectEqual(@as(?*FrameBuffer, null), triple.getDisplayBuffer());

    // Swap write buffer to ready
    triple.swapWrite();

    // Now should have buffer for display
    const display_buf = triple.getDisplayBuffer();
    try std.testing.expect(display_buf != null);
    try std.testing.expectEqual(@as(u64, 1), display_buf.?.frame_number);
}

test "CommandQueue: push and pop" {
    var queue = CommandQueue{};

    // Push commands
    try queue.push(.reset);
    try queue.push(.{ .set_paused = true });
    try queue.push(.{ .save_state = 0 });

    // Pop them back
    try std.testing.expectEqual(Command.reset, queue.tryPop().?);
    try std.testing.expectEqual(Command{ .set_paused = true }, queue.tryPop().?);
    try std.testing.expectEqual(Command{ .save_state = 0 }, queue.tryPop().?);

    // Should be empty
    try std.testing.expectEqual(@as(?Command, null), queue.tryPop());
}