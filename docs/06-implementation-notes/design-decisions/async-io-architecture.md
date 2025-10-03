# Async I/O Architecture Design

## Executive Summary

This document describes the comprehensive async I/O architecture for RAMBO NES emulator, maintaining strict RT-safety for the emulation loop while using libxev for efficient I/O operations.

## Architecture Overview

### Thread Model

```
┌─────────────────────────────────────────────────────────┐
│ RT Thread (SCHED_FIFO priority 80)                      │
│ - EmulationState tick() loop @ 5.37 MHz PPU             │
│ - Zero allocations, deterministic timing                │
│ - Communicates via lock-free SPSC queues                │
└─────────────────────────────────────────────────────────┘
                            ║
     ═══════════════════════╬══════════════════════════
                            ║
┌─────────────────────────────────────────────────────────┐
│ I/O Thread (priority 50)                                │
│ - libxev event loop with io_uring                       │
│ - ROM loading, save states, network I/O                 │
│ - Frame timer for pacing                                │
└─────────────────────────────────────────────────────────┘
                            ║
┌─────────────────────────────────────────────────────────┐
│ Render Thread (priority 40)                             │
│ - OpenGL/Vulkan context ownership                       │
│ - Shader compilation, texture uploads                   │
│ - Vsync presentation                                    │
└─────────────────────────────────────────────────────────┘
                            ║
┌─────────────────────────────────────────────────────────┐
│ Audio Thread (priority 70)                              │
│ - PipeWire/ALSA callback context                        │
│ - Resampling from NES rate to system rate               │
│ - Low-latency buffering                                 │
└─────────────────────────────────────────────────────────┘
```

## Lock-Free Data Structures

### 1. Input Queue (SPSC Ring Buffer)
- **Size**: 256 entries × 8 bytes = 2KB
- **Producer**: I/O thread (keyboard/gamepad events)
- **Consumer**: RT thread (applies to emulation)
- **Latency**: < 1 frame (16.7ms)
- **Memory Order**: Acquire-release semantics
- **Cache Line**: 64-byte aligned to prevent false sharing

### 2. Audio Queue (SPSC Ring Buffer)
- **Size**: 2048 samples × 4 bytes = 8KB
- **Producer**: RT thread (APU output)
- **Consumer**: Audio thread (system output)
- **Latency**: ~46ms buffer at 44.1kHz
- **Underrun Handling**: Track in stats, insert silence

### 3. Frame Buffer (Triple Buffering)
- **Size**: 3 × 256×240×4 bytes = ~720KB
- **Producer**: RT thread (PPU rendering)
- **Consumer**: Render thread (GPU upload)
- **Tearing**: Eliminated via triple buffering
- **Frame Drops**: Tracked but gracefully handled

### 4. Command Queue (MPSC with Mutex)
- **Size**: 64 commands max
- **Producers**: UI thread, network thread
- **Consumer**: RT thread
- **Mutex Justified**: Commands are infrequent (< 10/sec)
- **Operations**: Load ROM, save/load state, config changes

## Memory Management Strategy

### RT Thread (Zero Allocations)
```zig
// All buffers pre-allocated at startup
const RtMemory = struct {
    // Emulation state (~100KB)
    cpu_ram: [2048]u8,          // 2KB
    ppu_ram: [2048]u8,          // 2KB
    oam: [256]u8,               // 256B
    palette: [32]u8,            // 32B

    // Working buffers
    scanline_buffer: [256]u32,  // 1KB
    sprite_buffer: [64]Sprite,  // 2KB

    // No dynamic allocation allowed!
};
```

### I/O Thread (Can Allocate)
```zig
// Uses libxev allocator for dynamic needs
const IoMemory = struct {
    // ROM loading buffer (up to 1MB)
    rom_buffer: []u8,

    // Save state compression buffer
    compression_buffer: []u8,

    // Network packet buffers
    packet_pool: []NetworkPacket,
};
```

## libxev Integration

### Event Loop Setup
```zig
const IoThread = struct {
    loop: xev.Loop,

    // Timers
    frame_timer: xev.Timer,      // 60 FPS pacing
    autosave_timer: xev.Timer,   // Periodic saves

    // File I/O (io_uring on Linux)
    rom_file: xev.File,
    save_file: xev.File,

    // Network (future)
    netplay_socket: xev.TCP,

    fn init() !IoThread {
        var self: IoThread = undefined;
        self.loop = try xev.Loop.init(.{});

        // Setup frame timer (16.67ms)
        self.frame_timer = try xev.Timer.init();
        try self.startFrameTimer();

        return self;
    }

    fn startFrameTimer(self: *IoThread) !void {
        self.frame_timer.run(
            &self.loop,
            16_666_667, // nanoseconds
            onFrameTimer,
        );
    }
};
```

### Async ROM Loading
```zig
fn loadRomAsync(path: []const u8) !void {
    const file = try xev.File.open(loop, path, .{});

    // Get file size via io_uring statx
    var stat_completion: xev.Completion = undefined;
    file.stat(&loop, &stat_completion, onStatComplete);

    // Chain operations: stat -> read -> parse -> notify RT
}

fn onStatComplete(c: *Completion, f: File, stat: Stat) void {
    // Allocate buffer based on file size
    const buffer = allocator.alloc(u8, stat.size);

    // Start async read
    var read_completion: xev.Completion = undefined;
    f.read(&loop, &read_completion, buffer, onReadComplete);
}

fn onReadComplete(c: *Completion, f: File, buf: []u8) void {
    // Parse ROM header
    const rom = parseINES(buf);

    // Send to RT thread via command queue
    command_queue.push(.{ .load_rom = rom });
}
```

## RT Loop Integration

### Modified EmulationState
```zig
pub const EmulationState = struct {
    // Existing fields...
    clock: MasterClock,
    cpu: Cpu,
    ppu: Ppu,
    bus: Bus,

    // New I/O integration
    input: InputState,           // Latest controller state
    audio_buffer: AudioBuffer,   // Ring buffer for samples
    frame_ready: bool,           // Signal frame completion

    pub fn tick(self: *EmulationState) void {
        // Poll input (non-blocking)
        if (input_queue.tryPop()) |event| {
            self.input.update(event);
        }

        // Run emulation tick
        self.tickPpu();
        if (self.clock.ppu_cycles % 3 == 0) {
            self.tickCpu();
            self.tickApu();
        }

        // Generate audio sample
        if (self.clock.ppu_cycles % 121 == 0) { // ~44.1kHz
            const sample = self.apu.getSample();
            _ = audio_queue.tryPush(sample);
        }

        // Check frame boundary
        if (self.ppu.frame_complete) {
            frame_buffer.swapWrite();
            self.frame_ready = true;
        }
    }
};
```

## Threading Implementation

### RT Thread Setup (Linux)
```zig
fn setupRtThread() !void {
    // Set SCHED_FIFO with priority 80
    const params = std.os.linux.sched_param{
        .sched_priority = 80,
    };
    try std.os.linux.sched_setscheduler(
        0, // Current thread
        std.os.linux.SCHED_FIFO,
        &params,
    );

    // Pin to CPU core 0
    var cpu_set: std.os.linux.cpu_set_t = undefined;
    std.os.linux.CPU_ZERO(&cpu_set);
    std.os.linux.CPU_SET(0, &cpu_set);
    try std.os.linux.sched_setaffinity(0, @sizeOf(@TypeOf(cpu_set)), &cpu_set);

    // Lock memory to prevent page faults
    try std.os.linux.mlockall(std.os.linux.MCL_CURRENT | std.os.linux.MCL_FUTURE);
}
```

### Frame Pacing Strategy
```zig
const FramePacer = struct {
    target_time: i128,        // Nanoseconds
    last_frame: i128,
    drift_correction: i128,

    fn waitForNextFrame(self: *FramePacer) void {
        const now = std.time.nanoTimestamp();
        const elapsed = now - self.last_frame;
        const sleep_time = self.target_time - elapsed + self.drift_correction;

        if (sleep_time > 1_000_000) { // > 1ms
            // Sleep for most of the time
            std.time.sleep(@intCast(sleep_time - 500_000));

            // Busy-wait for precision
            while (std.time.nanoTimestamp() < self.target_time) {
                std.atomic.spinLoopHint();
            }
        }

        self.last_frame = std.time.nanoTimestamp();

        // Adjust drift correction
        const actual = self.last_frame - now;
        self.drift_correction += (self.target_time - actual) / 8;
    }
};
```

## Performance Considerations

### Cache Optimization
- All hot data structures are cache-line aligned (64 bytes)
- SPSC queues use separate cache lines for head/tail
- Frame buffer uses 32-byte aligned scanlines for SIMD

### Memory Barriers
- Minimal use of acquire-release semantics
- No full memory barriers in hot path
- Relaxed ordering where possible (stats counters)

### Latency Budget
```
Input → Display Latency:
- Input sampling: 0.5ms (USB polling)
- Input queue: < 0.1ms
- Emulation: 16.7ms (1 frame)
- Frame buffer swap: < 0.1ms
- GPU upload: 1-2ms
- Display scan-out: 8.3ms (120Hz display)
Total: ~27ms (< 2 frames)
```

## Integration Plan

### Phase 1: Core Infrastructure (2 days)
1. Implement lock-free ring buffers
2. Set up triple buffering
3. Create command queue
4. Add to build.zig

### Phase 2: libxev Integration (1 day)
1. Create IoContext with event loop
2. Implement frame timer
3. Add async ROM loading
4. Test with existing cartridge loader

### Phase 3: RT Thread (1 day)
1. Create RT thread with priority
2. Connect to EmulationState
3. Implement frame pacing
4. Test timing accuracy

### Phase 4: Audio Thread (1 day)
1. Implement audio ring buffer
2. Create audio thread
3. Add PipeWire/ALSA backend
4. Test latency and underruns

### Phase 5: Render Thread (2 days)
1. Create OpenGL/Vulkan context
2. Implement frame presentation
3. Add shader pipeline
4. Test vsync and tearing

### Phase 6: Input System (1 day)
1. Add keyboard input via libxev
2. Implement gamepad support
3. Create input replay system
4. Test input latency

### Phase 7: Testing & Optimization (2 days)
1. Profile with perf/tracy
2. Optimize cache usage
3. Test RT deadline misses
4. Validate with AccuracyCoin

## Testing Strategy

### Unit Tests
```zig
test "ring buffer: concurrent access" {
    // Spawn producer/consumer threads
    // Verify no data loss
    // Check memory ordering
}

test "triple buffer: no tearing" {
    // Simulate frame production/consumption
    // Verify frames never torn
    // Check frame drops handled
}
```

### Integration Tests
```zig
test "RT thread: meets deadlines" {
    // Run 1000 frames
    // Measure frame times
    // Assert 99.9% < 16.7ms
}

test "audio: no underruns" {
    // Generate 60 seconds of audio
    // Track underrun count
    // Assert < 0.1% underrun rate
}
```

### Performance Benchmarks
- Frame time histogram (target: 99.9% < 16.7ms)
- Input latency (target: < 30ms)
- Audio latency (target: < 20ms)
- Memory usage (target: < 50MB total)
- CPU usage (target: < 25% single core)

## Platform-Specific Notes

### Linux
- Uses io_uring for file I/O (5.1+ kernel)
- SCHED_FIFO requires CAP_SYS_NICE or root
- Consider cgroups for CPU isolation

### Windows
- Use IOCP instead of io_uring
- SetThreadPriority for RT thread
- WASAPI for audio

### macOS
- Use kqueue for I/O
- pthread_setschedparam for priority
- CoreAudio for audio

## Future Extensions

1. **Network Play**
   - GGPO-style rollback netcode
   - State synchronization via libxev TCP
   - < 4 frame input delay

2. **Recording/Streaming**
   - H.264 encoding in separate thread
   - Audio/video muxing
   - Live streaming support

3. **Advanced Graphics**
   - CRT shader effects
   - Resolution scaling
   - HDR output support

## References

- libxev documentation: https://github.com/mitchellh/libxev
- io_uring guide: https://kernel.dk/io_uring.pdf
- Real-time Linux: https://rt.wiki.kernel.org
- Lock-free programming: "The Art of Multiprocessor Programming"
- NES timing: https://www.nesdev.org/wiki/PPU_frame_timing