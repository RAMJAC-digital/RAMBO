# Video Subsystem Testing & Profiling Plan

**Date:** 2025-10-04
**Author:** Performance Engineering Agent
**Purpose:** Comprehensive testing strategy for RAMBO video subsystem

## 1. Performance Testing Framework

### 1.1 Test Harness Setup

```zig
// tests/video/performance_test.zig

const std = @import("std");
const testing = std.testing;
const VideoSubsystem = @import("../../src/video/VideoSubsystem.zig");
const FrameBuffer = @import("../../src/video/FrameBuffer.zig");

pub const PerformanceTest = struct {
    allocator: std.mem.Allocator,
    timer: std.time.Timer,
    metrics: TestMetrics,

    const TestMetrics = struct {
        samples: std.ArrayList(u64),
        min: u64 = std.math.maxInt(u64),
        max: u64 = 0,
        sum: u64 = 0,
        count: u64 = 0,

        fn record(self: *TestMetrics, value: u64) !void {
            try self.samples.append(value);
            self.min = @min(self.min, value);
            self.max = @max(self.max, value);
            self.sum += value;
            self.count += 1;
        }

        fn percentile(self: TestMetrics, p: f64) u64 {
            if (self.samples.items.len == 0) return 0;

            var sorted = try self.samples.clone();
            defer sorted.deinit();
            std.sort.heap(u64, sorted.items, {}, std.sort.asc(u64));

            const index = @as(usize, @intFromFloat(
                @as(f64, @floatFromInt(sorted.items.len - 1)) * p / 100.0
            ));
            return sorted.items[index];
        }

        fn report(self: TestMetrics, name: []const u8) void {
            const avg = if (self.count > 0) self.sum / self.count else 0;

            std.debug.print("\n{s} Performance:\n", .{name});
            std.debug.print("  Samples: {}\n", .{self.count});
            std.debug.print("  Min: {:.3}ms\n", .{@as(f64, @floatFromInt(self.min)) / 1_000_000});
            std.debug.print("  Max: {:.3}ms\n", .{@as(f64, @floatFromInt(self.max)) / 1_000_000});
            std.debug.print("  Avg: {:.3}ms\n", .{@as(f64, @floatFromInt(avg)) / 1_000_000});
            std.debug.print("  P50: {:.3}ms\n", .{@as(f64, @floatFromInt(self.percentile(50))) / 1_000_000});
            std.debug.print("  P95: {:.3}ms\n", .{@as(f64, @floatFromInt(self.percentile(95))) / 1_000_000});
            std.debug.print("  P99: {:.3}ms\n", .{@as(f64, @floatFromInt(self.percentile(99))) / 1_000_000});
        }
    };

    pub fn init(allocator: std.mem.Allocator) !PerformanceTest {
        return .{
            .allocator = allocator,
            .timer = try std.time.Timer.start(),
            .metrics = .{
                .samples = std.ArrayList(u64).init(allocator),
            },
        };
    }

    pub fn deinit(self: *PerformanceTest) void {
        self.metrics.samples.deinit();
    }

    pub fn measureNanos(self: *PerformanceTest, comptime func: anytype, args: anytype) !u64 {
        const start = self.timer.read();
        _ = try @call(.auto, func, args);
        return self.timer.read() - start;
    }
};
```

### 1.2 Atomic Performance Tests

```zig
test "FrameBuffer: atomic operation throughput" {
    var buffer = FrameBuffer.init();
    var perf = try PerformanceTest.init(testing.allocator);
    defer perf.deinit();

    // Warm up
    for (0..1000) |_| {
        _ = buffer.swapWrite();
        _ = buffer.getPresentBuffer();
        buffer.swapDisplay();
    }

    // Measure
    const iterations = 100_000;
    for (0..iterations) |_| {
        const elapsed = try perf.measureNanos(testAtomicCycle, .{&buffer});
        try perf.metrics.record(elapsed);
    }

    perf.metrics.report("Atomic Operations");

    // Verify performance requirements
    const avg_ns = perf.metrics.sum / perf.metrics.count;
    try testing.expect(avg_ns < 100); // <100ns per atomic cycle
}

fn testAtomicCycle(buffer: *FrameBuffer) !void {
    _ = buffer.swapWrite();
    _ = buffer.getPresentBuffer();
    buffer.swapDisplay();
}
```

### 1.3 Frame Buffer Contention Tests

```zig
test "FrameBuffer: multi-thread contention" {
    var buffer = FrameBuffer.init();
    var perf = try PerformanceTest.init(testing.allocator);
    defer perf.deinit();

    const Context = struct {
        buffer: *FrameBuffer,
        metrics: *TestMetrics,
        running: *std.atomic.Value(bool),
    };

    var writer_metrics = TestMetrics{
        .samples = std.ArrayList(u64).init(testing.allocator),
    };
    defer writer_metrics.samples.deinit();

    var reader_metrics = TestMetrics{
        .samples = std.ArrayList(u64).init(testing.allocator),
    };
    defer reader_metrics.samples.deinit();

    var running = std.atomic.Value(bool).init(true);

    // Writer thread (simulates PPU)
    const writer = try std.Thread.spawn(.{}, struct {
        fn run(ctx: Context) !void {
            var timer = try std.time.Timer.start();
            while (ctx.running.load(.acquire)) {
                const start = timer.read();

                // Simulate frame rendering (write pixels)
                const write_buf = ctx.buffer.getWriteBuffer();
                for (write_buf) |*pixel| {
                    pixel.* = 0xDEADBEEF;
                }

                // Swap at vblank
                _ = ctx.buffer.swapWrite();

                const elapsed = timer.read() - start;
                try ctx.metrics.record(elapsed);

                // 60 FPS timing
                std.time.sleep(16_666_667); // 16.67ms
            }
        }
    }.run, .{ .buffer = &buffer, .metrics = &writer_metrics, .running = &running });

    // Reader thread (simulates render thread)
    const reader = try std.Thread.spawn(.{}, struct {
        fn run(ctx: Context) !void {
            var timer = try std.time.Timer.start();
            while (ctx.running.load(.acquire)) {
                const start = timer.read();

                if (ctx.buffer.getPresentBuffer()) |frame| {
                    // Simulate texture upload
                    var sum: u64 = 0;
                    for (frame.buffer) |pixel| {
                        sum +%= pixel;
                    }
                    std.mem.doNotOptimizeAway(sum);

                    // Swap display
                    ctx.buffer.swapDisplay();
                }

                const elapsed = timer.read() - start;
                try ctx.metrics.record(elapsed);

                std.time.sleep(1_000_000); // 1ms poll rate
            }
        }
    }.run, .{ .buffer = &buffer, .metrics = &reader_metrics, .running = &running });

    // Run for 1 second
    std.time.sleep(1_000_000_000);
    running.store(false, .release);

    writer.join();
    reader.join();

    writer_metrics.report("Writer Thread");
    reader_metrics.report("Reader Thread");

    // Verify no excessive contention
    const writer_p99 = writer_metrics.percentile(99);
    const reader_p99 = reader_metrics.percentile(99);

    try testing.expect(writer_p99 < 1_000_000); // <1ms P99
    try testing.expect(reader_p99 < 1_000_000); // <1ms P99
}
```

## 2. OpenGL Performance Tests

### 2.1 Texture Upload Benchmarks

```zig
test "OpenGL: texture upload performance" {
    var perf = try PerformanceTest.init(testing.allocator);
    defer perf.deinit();

    // Initialize OpenGL context
    var backend = try OpenGL.init(testing.allocator);
    defer backend.deinit();

    // Test data (256×240 RGBA)
    var pixels: [256 * 240]u32 = undefined;
    for (&pixels, 0..) |*pixel, i| {
        pixel.* = @truncate(i * 0x010101);
    }

    // Test 1: glTexImage2D (baseline)
    std.debug.print("\nTesting glTexImage2D...\n", .{});
    for (0..100) |_| {
        const elapsed = try perf.measureNanos(backend.uploadTextureImage, .{&pixels});
        try perf.metrics.record(elapsed);
    }
    perf.metrics.report("glTexImage2D");

    // Test 2: glTexSubImage2D (optimized)
    var perf2 = try PerformanceTest.init(testing.allocator);
    defer perf2.deinit();

    std.debug.print("\nTesting glTexSubImage2D...\n", .{});
    for (0..100) |_| {
        const elapsed = try perf2.measureNanos(backend.uploadTextureSubImage, .{&pixels});
        try perf2.metrics.record(elapsed);
    }
    perf2.metrics.report("glTexSubImage2D");

    // Test 3: PBO upload (if available)
    if (backend.supportsPBO()) {
        var perf3 = try PerformanceTest.init(testing.allocator);
        defer perf3.deinit();

        std.debug.print("\nTesting PBO upload...\n", .{});
        for (0..100) |_| {
            const elapsed = try perf3.measureNanos(backend.uploadTexturePBO, .{&pixels});
            try perf3.metrics.record(elapsed);
        }
        perf3.metrics.report("PBO Upload");
    }

    // Verify performance requirements
    const avg_upload = perf2.metrics.sum / perf2.metrics.count;
    try testing.expect(avg_upload < 1_000_000); // <1ms average
}
```

### 2.2 GPU Render Performance

```zig
test "OpenGL: frame render performance" {
    var perf = try PerformanceTest.init(testing.allocator);
    defer perf.deinit();

    var backend = try OpenGL.init(testing.allocator);
    defer backend.deinit();

    // Upload initial texture
    var pixels: [256 * 240]u32 = undefined;
    for (&pixels) |*pixel| {
        pixel.* = 0xFF00FF00; // Green
    }
    try backend.uploadTexture(&pixels);

    // Measure render performance
    for (0..1000) |_| {
        const elapsed = try perf.measureNanos(backend.drawFrame, .{});
        try perf.metrics.record(elapsed);
    }

    perf.metrics.report("GPU Render");

    // Verify <1ms render time
    const p95 = perf.metrics.percentile(95);
    try testing.expect(p95 < 1_000_000);
}
```

## 3. End-to-End Integration Tests

### 3.1 Full Frame Pipeline Test

```zig
test "Integration: complete frame pipeline" {
    const allocator = testing.allocator;
    var perf = try PerformanceTest.init(allocator);
    defer perf.deinit();

    // Initialize subsystem
    var loop = try xev.Loop.init(.{});
    defer loop.deinit();

    var config = Config.default();
    config.video.backend = .opengl;

    var video = try VideoSubsystem.init(
        allocator,
        &loop,
        &config.video,
        &config.ppu
    );
    defer video.deinit();

    // Simulate PPU writing frames
    const Frame = struct {
        fn render(subsystem: *VideoSubsystem, frame_num: u32) !void {
            const fb = subsystem.getFrameBuffer();

            // Generate test pattern
            for (fb, 0..) |*pixel, i| {
                const x = i % 256;
                const y = i / 256;
                pixel.* = (@as(u32, @truncate(x)) << 16) |
                         (@as(u32, @truncate(y)) << 8) |
                         (@as(u32, @truncate(frame_num)) & 0xFF);
            }

            subsystem.signalFrameComplete();
        }
    };

    // Measure 60 frames
    for (0..60) |frame_num| {
        const start = perf.timer.read();

        // Render frame
        try Frame.render(&video, @truncate(frame_num));

        // Wait for vsync (simulate 60fps)
        const target = start + 16_666_667; // 16.67ms
        while (perf.timer.read() < target) {
            std.atomic.spinLoopHint();
        }

        const elapsed = perf.timer.read() - start;
        try perf.metrics.record(elapsed);
    }

    perf.metrics.report("Full Pipeline");

    // Verify 60fps achieved
    const avg_frame_time = perf.metrics.sum / perf.metrics.count;
    try testing.expect(avg_frame_time < 17_000_000); // <17ms
}
```

### 3.2 Stress Test

```zig
test "Stress: sustained 60fps for 10 seconds" {
    const allocator = testing.allocator;

    var video = try VideoSubsystem.init(
        allocator,
        &loop,
        &config.video,
        &config.ppu
    );
    defer video.deinit();

    var frame_count: u32 = 0;
    var dropped_frames: u32 = 0;
    var timer = try std.time.Timer.start();

    const start_time = timer.read();
    const test_duration = 10_000_000_000; // 10 seconds

    while (timer.read() - start_time < test_duration) {
        const frame_start = timer.read();

        // Render frame
        const fb = video.getFrameBuffer();
        @memset(fb, 0xFF0000FF); // Blue
        video.signalFrameComplete();

        // Check if we made deadline
        const frame_time = timer.read() - frame_start;
        if (frame_time > 16_666_667) {
            dropped_frames += 1;
        }

        frame_count += 1;

        // Wait for next frame
        const next_frame = frame_start + 16_666_667;
        while (timer.read() < next_frame) {
            std.atomic.spinLoopHint();
        }
    }

    const actual_duration = timer.read() - start_time;
    const fps = @as(f64, @floatFromInt(frame_count)) * 1_000_000_000.0 /
                @as(f64, @floatFromInt(actual_duration));

    std.debug.print("\nStress Test Results:\n", .{});
    std.debug.print("  Duration: {:.2}s\n", .{@as(f64, @floatFromInt(actual_duration)) / 1_000_000_000});
    std.debug.print("  Frames: {}\n", .{frame_count});
    std.debug.print("  FPS: {:.2}\n", .{fps});
    std.debug.print("  Dropped: {} ({:.2}%)\n", .{
        dropped_frames,
        @as(f64, @floatFromInt(dropped_frames * 100)) / @as(f64, @floatFromInt(frame_count))
    });

    // Require <1% frame drops
    try testing.expect(dropped_frames * 100 < frame_count);
    try testing.expect(fps > 59.0);
}
```

## 4. Memory & Resource Tests

### 4.1 Memory Leak Detection

```zig
test "Memory: no leaks in frame buffer" {
    const allocator = testing.allocator;

    // Create and destroy multiple times
    for (0..100) |_| {
        var buffer = FrameBuffer.init();

        // Use all buffers
        _ = buffer.getWriteBuffer();
        _ = buffer.swapWrite();
        _ = buffer.getPresentBuffer();
        buffer.swapDisplay();

        // No explicit deinit needed (stack allocated)
    }

    // Allocator will detect leaks on test exit
}

test "Memory: video subsystem cleanup" {
    const allocator = testing.allocator;

    for (0..10) |_| {
        var loop = try xev.Loop.init(.{});
        defer loop.deinit();

        var config = Config.default();
        var video = try VideoSubsystem.init(
            allocator,
            &loop,
            &config.video,
            &config.ppu
        );

        // Use it
        const fb = video.getFrameBuffer();
        @memset(fb, 0);
        video.signalFrameComplete();

        // Clean shutdown
        video.deinit();
    }
}
```

### 4.2 Cache Line Verification

```zig
test "Memory: cache line alignment" {
    var buffer = FrameBuffer.init();

    // Verify 128-byte alignment
    const write_addr = @intFromPtr(&buffer.write_index);
    const present_addr = @intFromPtr(&buffer.present_index);
    const display_addr = @intFromPtr(&buffer.display_index);
    const buffers_addr = @intFromPtr(&buffer.buffers);

    try testing.expect(write_addr % 128 == 0);
    try testing.expect(present_addr % 128 == 0);
    try testing.expect(display_addr % 128 == 0);
    try testing.expect(buffers_addr % 128 == 0);

    // Verify no overlap
    try testing.expect(present_addr - write_addr >= 128);
    try testing.expect(display_addr - present_addr >= 128);
    try testing.expect(buffers_addr - display_addr >= 128);
}
```

## 5. Profiling Tools Integration

### 5.1 Tracy Integration

```zig
// src/video/profiling.zig

const tracy = @import("tracy");

pub inline fn zone(comptime name: []const u8) tracy.ZoneCtx {
    return tracy.zone(name);
}

pub inline fn frameMark() void {
    tracy.frameMark();
}

// Usage in VideoSubsystem
pub fn signalFrameComplete(self: *VideoSubsystem) void {
    const z = zone("VBlank");
    defer z.end();

    _ = self.frame_buffer.swapWrite();
    frameMark(); // Tracy frame marker
}
```

### 5.2 Custom Profiler

```zig
pub const Profiler = struct {
    zones: [16]Zone = undefined,
    zone_count: usize = 0,

    const Zone = struct {
        name: []const u8,
        start_ns: u64,
        total_ns: u64 = 0,
        count: u64 = 0,
    };

    pub fn beginZone(self: *Profiler, comptime name: []const u8) ZoneHandle {
        const index = self.zone_count;
        self.zone_count += 1;

        self.zones[index] = .{
            .name = name,
            .start_ns = std.time.nanoTimestamp(),
        };

        return .{ .profiler = self, .index = index };
    }

    pub const ZoneHandle = struct {
        profiler: *Profiler,
        index: usize,

        pub fn end(self: ZoneHandle) void {
            const zone = &self.profiler.zones[self.index];
            const elapsed = std.time.nanoTimestamp() - zone.start_ns;
            zone.total_ns += elapsed;
            zone.count += 1;
        }
    };

    pub fn report(self: Profiler) void {
        std.debug.print("\n=== Profile Report ===\n", .{});
        for (self.zones[0..self.zone_count]) |zone| {
            const avg_ms = @as(f64, @floatFromInt(zone.total_ns / zone.count)) / 1_000_000;
            std.debug.print("{s}: {:.3}ms ({}x)\n", .{ zone.name, avg_ms, zone.count });
        }
    }
};
```

## 6. Automated Performance Regression Tests

### 6.1 CI Integration

```yaml
# .github/workflows/perf-test.yml
name: Performance Tests

on:
  push:
    paths:
      - 'src/video/**'
      - 'tests/video/**'

jobs:
  benchmark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Zig
        uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.15.1

      - name: Install deps
        run: |
          sudo apt-get update
          sudo apt-get install -y libglfw3-dev libgl1-mesa-dev

      - name: Run benchmarks
        run: |
          zig build test-video-perf --summary all > perf-results.txt

      - name: Check regression
        run: |
          python3 scripts/check-perf-regression.py perf-results.txt
```

### 6.2 Regression Detection Script

```python
#!/usr/bin/env python3
# scripts/check-perf-regression.py

import sys
import re

# Performance thresholds
THRESHOLDS = {
    "FrameBuffer.swap": 0.001,      # 1ms
    "OpenGL.upload": 1.0,            # 1ms
    "OpenGL.render": 1.0,            # 1ms
    "Pipeline.frame": 5.0,           # 5ms
}

def parse_results(filename):
    """Parse performance test output."""
    results = {}
    with open(filename) as f:
        content = f.read()

        # Extract timing results
        pattern = r"(\w+) Performance:.*?Avg: ([\d.]+)ms"
        matches = re.findall(pattern, content, re.DOTALL)

        for name, time_ms in matches:
            results[name] = float(time_ms)

    return results

def check_thresholds(results):
    """Check if any metrics exceed thresholds."""
    failures = []

    for test, threshold in THRESHOLDS.items():
        if test in results:
            if results[test] > threshold:
                failures.append(f"{test}: {results[test]:.3f}ms > {threshold}ms")

    return failures

def main():
    if len(sys.argv) != 2:
        print("Usage: check-perf-regression.py <results-file>")
        sys.exit(1)

    results = parse_results(sys.argv[1])
    failures = check_thresholds(results)

    if failures:
        print("Performance regression detected!")
        for failure in failures:
            print(f"  ✗ {failure}")
        sys.exit(1)
    else:
        print("All performance tests passed!")
        for test, time in results.items():
            print(f"  ✓ {test}: {time:.3f}ms")

if __name__ == "__main__":
    main()
```

## 7. Load Testing Scenarios

### 7.1 Worst-Case Rendering

```zig
test "Load: maximum pixel changes per frame" {
    // Test with maximum entropy (every pixel different each frame)
    var video = try VideoSubsystem.init(...);
    defer video.deinit();

    var rng = std.rand.DefaultPrng.init(0);
    const random = rng.random();

    var perf = try PerformanceTest.init(testing.allocator);
    defer perf.deinit();

    for (0..100) |_| {
        const start = perf.timer.read();

        const fb = video.getFrameBuffer();
        for (fb) |*pixel| {
            pixel.* = random.int(u32);
        }
        video.signalFrameComplete();

        const elapsed = perf.timer.read() - start;
        try perf.metrics.record(elapsed);
    }

    perf.metrics.report("Worst Case");

    // Should still achieve 60fps
    const p99 = perf.metrics.percentile(99);
    try testing.expect(p99 < 16_666_667);
}
```

### 7.2 Latency Testing

```zig
test "Latency: input to display" {
    // Measure time from frame generation to display
    var video = try VideoSubsystem.init(...);
    defer video.deinit();

    const start = std.time.nanoTimestamp();

    // Generate unique frame
    const fb = video.getFrameBuffer();
    fb[0] = 0xDEADBEEF;
    video.signalFrameComplete();

    // Wait for frame to appear
    while (true) {
        if (video.frame_buffer.display_index.load(.acquire) ==
            video.frame_buffer.write_index.load(.acquire)) {
            break;
        }
        std.atomic.spinLoopHint();
    }

    const latency = std.time.nanoTimestamp() - start;

    std.debug.print("Input-to-display latency: {:.3}ms\n",
                    .{@as(f64, @floatFromInt(latency)) / 1_000_000});

    // Should be <2 frames (33ms)
    try testing.expect(latency < 33_333_333);
}
```

## 8. Test Execution Guide

### 8.1 Running Tests

```bash
# Run all video tests
zig build test-video

# Run performance tests only
zig build test-video-perf

# Run with profiling
zig build test-video-perf -Denable-profiling

# Run stress tests
zig build test-video-stress

# Generate benchmark report
zig build test-video-perf | tee benchmark-$(date +%Y%m%d).txt
```

### 8.2 Interpreting Results

**Good Performance Indicators:**
- Frame buffer swaps: <0.01ms
- Texture upload: <1ms
- GPU render: <1ms
- Full pipeline: <5ms
- 60fps sustained: >99% frames

**Warning Signs:**
- P99 latency >10ms
- Frame drops >1%
- Memory usage growing
- CPU usage >50%

**Critical Issues:**
- Any test timeout
- Frame time >16.67ms
- Consistent frame drops
- Memory leaks detected

## Conclusion

This comprehensive testing plan ensures the RAMBO video subsystem meets performance requirements. Focus on the integration tests first, then optimize based on profiling results. The automated regression tests will catch any performance degradation early in development.