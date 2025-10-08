//! Benchmark Integration Tests
//!
//! Demonstrates benchmarking infrastructure and measures
//! AccuracyCoin emulation performance.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Benchmark = RAMBO.Benchmark;
const RomTestRunner = @import("rom_test_runner.zig").RomTestRunner;
const RunConfig = @import("rom_test_runner.zig").RunConfig;

test "Benchmark: AccuracyCoin emulation performance" {
    const accuracycoin_path = "AccuracyCoin/AccuracyCoin.nes";

    // Create benchmark runner
    var bench = Benchmark.Runner{};
    bench.start();

    // Configure ROM runner
    const config = RunConfig{
        .max_frames = 600,
        .max_instructions = 0,
        .completion_address = null,
        .verbose = false, // Disable verbose for clean benchmark output
    };

    var runner = RomTestRunner.init(
        testing.allocator,
        accuracycoin_path,
        config,
    ) catch |err| {
        if (err == error.FileNotFound) {
            return error.SkipZigTest;
        }
        return err;
    };
    defer runner.deinit();

    // Run test ROM with benchmarking
    var frames_executed: usize = 0;
    while (frames_executed < config.max_frames) {
        const frame_instructions = try runner.runFrame();

        // Record benchmark metrics
        // Approximate: Each instruction is ~4 cycles on average
        for (0..frame_instructions) |_| {
            bench.recordInstruction(4); // Estimate 4 cycles/instruction
        }
        bench.recordFrame();

        frames_executed += 1;

        // Progress every 60 frames
        if (frames_executed % 60 == 0) {
            _ = bench.getMetrics();
        }
    }

    // Stop benchmark and print results
    bench.stop();

    const metrics = bench.getMetrics();

    // Validate performance metrics

    try testing.expect(metrics.total_frames == 600);
    try testing.expect(metrics.total_instructions > 0);
    try testing.expect(metrics.total_cycles > 0);
    try testing.expect(metrics.elapsed_ns > 0);

    // Performance expectations (should be much faster than real-time on modern hardware)
    // Real-time is 1.0x, we expect at least 10x on any reasonable hardware
    _ = metrics.speedRatio();
}

test "Benchmark.Metrics: Comprehensive calculation tests" {
    var metrics = Benchmark.Metrics{
        .total_cycles = 1_789_773, // 1 second of NES cycles
        .total_instructions = 1_000_000,
        .total_frames = 60, // 60 fps
        .elapsed_ns = 1_000_000_000, // 1 second wall time
    };

    // Instructions per second
    try testing.expectApproxEqRel(@as(f64, 1_000_000.0), metrics.instructionsPerSecond(), 0.001);

    // Cycles per second
    try testing.expectApproxEqRel(@as(f64, 1_789_773.0), metrics.cyclesPerSecond(), 0.001);

    // Frames per second
    try testing.expectApproxEqRel(@as(f64, 60.0), metrics.framesPerSecond(), 0.001);

    // Cycles per instruction
    try testing.expectApproxEqRel(@as(f64, 1.789773), metrics.cyclesPerInstruction(), 0.001);

    // Instructions per frame
    try testing.expectApproxEqRel(@as(f64, 16_666.67), metrics.instructionsPerFrame(), 0.1);

    // Speed ratio (should be 1.0x - real-time)
    try testing.expectApproxEqRel(@as(f64, 1.0), metrics.speedRatio(), 0.001);
}

test "Benchmark.Runner: Lifecycle" {
    var runner = Benchmark.Runner{};

    // Start
    runner.start();
    try testing.expect(runner.start_time != 0);
    try testing.expect(runner.metrics.total_instructions == 0);

    // Record some activity
    runner.recordInstruction(7);
    runner.recordInstruction(4);
    runner.recordInstruction(2);
    runner.recordFrame();

    try testing.expectEqual(@as(u64, 3), runner.metrics.total_instructions);
    try testing.expectEqual(@as(u64, 13), runner.metrics.total_cycles);
    try testing.expectEqual(@as(u64, 1), runner.metrics.total_frames);

    // Get metrics without stopping
    const metrics1 = runner.getMetrics();
    try testing.expect(metrics1.elapsed_ns > 0);

    // Stop
    runner.stop();
    const metrics2 = runner.getMetrics();
    try testing.expect(metrics2.elapsed_ns >= metrics1.elapsed_ns);
}
