//! Benchmarking Infrastructure
//!
//! Measures emulation performance metrics:
//! - Instructions per second (IPS)
//! - Frames per second (FPS)
//! - Cycle accuracy
//! - CPU/PPU timing overhead

const std = @import("std");

/// Performance metrics collected during benchmark
pub const Metrics = struct {
    /// Total CPU cycles executed
    total_cycles: u64 = 0,

    /// Total CPU instructions executed
    total_instructions: u64 = 0,

    /// Total PPU frames rendered
    total_frames: u64 = 0,

    /// Total wall-clock time (nanoseconds)
    elapsed_ns: u64 = 0,

    /// Calculate instructions per second
    pub fn instructionsPerSecond(self: *const Metrics) f64 {
        if (self.elapsed_ns == 0) return 0.0;
        const seconds = @as(f64, @floatFromInt(self.elapsed_ns)) / 1_000_000_000.0;
        return @as(f64, @floatFromInt(self.total_instructions)) / seconds;
    }

    /// Calculate cycles per second
    pub fn cyclesPerSecond(self: *const Metrics) f64 {
        if (self.elapsed_ns == 0) return 0.0;
        const seconds = @as(f64, @floatFromInt(self.elapsed_ns)) / 1_000_000_000.0;
        return @as(f64, @floatFromInt(self.total_cycles)) / seconds;
    }

    /// Calculate frames per second
    pub fn framesPerSecond(self: *const Metrics) f64 {
        if (self.elapsed_ns == 0) return 0.0;
        const seconds = @as(f64, @floatFromInt(self.elapsed_ns)) / 1_000_000_000.0;
        return @as(f64, @floatFromInt(self.total_frames)) / seconds;
    }

    /// Calculate average cycles per instruction
    pub fn cyclesPerInstruction(self: *const Metrics) f64 {
        if (self.total_instructions == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_cycles)) / @as(f64, @floatFromInt(self.total_instructions));
    }

    /// Calculate average instructions per frame
    pub fn instructionsPerFrame(self: *const Metrics) f64 {
        if (self.total_frames == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_instructions)) / @as(f64, @floatFromInt(self.total_frames));
    }

    /// Calculate NES vs real-time speed ratio
    /// NES runs at 1.789773 MHz (NTSC), so 1,789,773 cycles/second
    /// Target: 60 FPS, 29780 cycles/frame (perfect accuracy)
    pub fn speedRatio(self: *const Metrics) f64 {
        const nes_cycles_per_second = 1_789_773.0; // NTSC CPU frequency
        const actual_cps = self.cyclesPerSecond();
        return actual_cps / nes_cycles_per_second;
    }

    /// Calculate timing accuracy (cycles per frame vs expected)
    /// Expected: 29780 cycles/frame for NTSC
    pub fn timingAccuracy(self: *const Metrics) f64 {
        if (self.total_frames == 0) return 0.0;
        const expected_cycles_per_frame = 29780.0; // NTSC frame timing
        const actual_cycles_per_frame = @as(f64, @floatFromInt(self.total_cycles)) / @as(f64, @floatFromInt(self.total_frames));
        return (actual_cycles_per_frame / expected_cycles_per_frame) * 100.0;
    }

    /// Print formatted metrics
    pub fn print(self: *const Metrics, writer: anytype) !void {
        try writer.print("=== Benchmark Results ===\n", .{});
        try writer.print("Total Cycles:       {d}\n", .{self.total_cycles});
        try writer.print("Total Instructions: {d}\n", .{self.total_instructions});
        try writer.print("Total Frames:       {d}\n", .{self.total_frames});
        try writer.print("Elapsed Time:       {d:.3}s\n", .{@as(f64, @floatFromInt(self.elapsed_ns)) / 1_000_000_000.0});
        try writer.print("\n=== Performance ===\n", .{});
        try writer.print("Instructions/sec:   {d:.2}\n", .{self.instructionsPerSecond()});
        try writer.print("Cycles/sec:         {d:.2}\n", .{self.cyclesPerSecond()});
        try writer.print("Frames/sec:         {d:.2}\n", .{self.framesPerSecond()});
        try writer.print("Cycles/instruction: {d:.2}\n", .{self.cyclesPerInstruction()});
        try writer.print("Instructions/frame: {d:.2}\n", .{self.instructionsPerFrame()});
        try writer.print("\n=== Accuracy ===\n", .{});
        try writer.print("Speed Ratio:        {d:.2}x real-time\n", .{self.speedRatio()});
        try writer.print("Timing Accuracy:    {d:.2}% of ideal\n", .{self.timingAccuracy()});
    }
};

/// Benchmark runner
pub const Runner = struct {
    start_time: i128 = 0,
    metrics: Metrics = .{},

    /// Start the benchmark timer
    pub fn start(self: *Runner) void {
        self.start_time = std.time.nanoTimestamp();
        self.metrics = .{};
    }

    /// Stop the benchmark timer and finalize metrics
    pub fn stop(self: *Runner) void {
        const end_time = std.time.nanoTimestamp();
        self.metrics.elapsed_ns = @intCast(end_time - self.start_time);
    }

    /// Record a CPU instruction
    pub inline fn recordInstruction(self: *Runner, cycles: u64) void {
        self.metrics.total_instructions += 1;
        self.metrics.total_cycles += cycles;
    }

    /// Record a PPU frame
    pub inline fn recordFrame(self: *Runner) void {
        self.metrics.total_frames += 1;
    }

    /// Get current metrics (without stopping)
    pub fn getMetrics(self: *const Runner) Metrics {
        var metrics = self.metrics;
        const current_time = std.time.nanoTimestamp();
        metrics.elapsed_ns = @intCast(current_time - self.start_time);
        return metrics;
    }

    /// Print current metrics
    pub fn printMetrics(self: *const Runner, writer: anytype) !void {
        const metrics = self.getMetrics();
        try metrics.print(writer);
    }
};

/// Benchmarking configuration
pub const Config = struct {
    /// Target number of frames to execute
    target_frames: u64 = 600,

    /// Target number of instructions (0 = unlimited)
    target_instructions: u64 = 0,

    /// Print progress every N frames (0 = no progress)
    progress_interval: u64 = 60,

    /// Enable detailed cycle-level metrics
    detailed_metrics: bool = false,
};

test "Metrics: Instructions per second calculation" {
    var metrics = Metrics{
        .total_instructions = 10_000_000,
        .elapsed_ns = 1_000_000_000, // 1 second
    };

    const ips = metrics.instructionsPerSecond();
    try std.testing.expectEqual(@as(f64, 10_000_000.0), ips);
}

test "Metrics: Cycles per second calculation" {
    var metrics = Metrics{
        .total_cycles = 20_000_000,
        .elapsed_ns = 1_000_000_000, // 1 second
    };

    const cps = metrics.cyclesPerSecond();
    try std.testing.expectEqual(@as(f64, 20_000_000.0), cps);
}

test "Metrics: Frames per second calculation" {
    var metrics = Metrics{
        .total_frames = 60,
        .elapsed_ns = 1_000_000_000, // 1 second
    };

    const fps = metrics.framesPerSecond();
    try std.testing.expectEqual(@as(f64, 60.0), fps);
}

test "Metrics: Speed ratio (real-time)" {
    var metrics = Metrics{
        .total_cycles = 1_789_773,
        .elapsed_ns = 1_000_000_000, // 1 second
    };

    const ratio = metrics.speedRatio();
    try std.testing.expectApproxEqRel(@as(f64, 1.0), ratio, 0.001);
}

test "Metrics: Speed ratio (2x real-time)" {
    var metrics = Metrics{
        .total_cycles = 3_579_546,
        .elapsed_ns = 1_000_000_000, // 1 second
    };

    const ratio = metrics.speedRatio();
    try std.testing.expectApproxEqRel(@as(f64, 2.0), ratio, 0.001);
}

test "Metrics: Timing accuracy (perfect)" {
    var metrics = Metrics{
        .total_cycles = 29780 * 60, // 60 frames
        .total_frames = 60,
    };

    const accuracy = metrics.timingAccuracy();
    try std.testing.expectApproxEqRel(@as(f64, 100.0), accuracy, 0.001);
}

test "Runner: Basic workflow" {
    var runner = Runner{};

    runner.start();

    // Simulate some work
    runner.recordInstruction(7); // LDA takes 7 cycles
    runner.recordInstruction(4); // STA takes 4 cycles
    runner.recordFrame();

    runner.stop();

    const metrics = runner.getMetrics();
    try std.testing.expectEqual(@as(u64, 2), metrics.total_instructions);
    try std.testing.expectEqual(@as(u64, 11), metrics.total_cycles);
    try std.testing.expectEqual(@as(u64, 1), metrics.total_frames);
    try std.testing.expect(metrics.elapsed_ns > 0);
}

test "Runner: Get metrics without stopping" {
    var runner = Runner{};

    runner.start();
    runner.recordInstruction(5);

    const metrics1 = runner.getMetrics();
    try std.testing.expectEqual(@as(u64, 1), metrics1.total_instructions);

    runner.recordInstruction(3);

    const metrics2 = runner.getMetrics();
    try std.testing.expectEqual(@as(u64, 2), metrics2.total_instructions);

    // Runner should still be running
    try std.testing.expect(metrics2.elapsed_ns >= metrics1.elapsed_ns);
}
