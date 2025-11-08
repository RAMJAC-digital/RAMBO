//! Performance Analysis Tool
//! Profiles the RAMBO emulator to identify bottlenecks and optimization opportunities

const std = @import("std");
const RAMBO = @import("RAMBO");
const Config = RAMBO.Config;
const EmulationState = RAMBO.EmulationState;
const Benchmark = RAMBO.Benchmark;
const InesModule = RAMBO.InesModule;
const RegistryModule = @import("../src/cartridge/mappers/registry.zig");

const ProfileSection = struct {
    name: []const u8,
    cycles: u64,
    calls: u64,
    start_time: ?i128,

    fn start(self: *ProfileSection) void {
        self.start_time = std.time.nanoTimestamp();
    }

    fn stop(self: *ProfileSection) void {
        if (self.start_time) |start| {
            const elapsed = std.time.nanoTimestamp() - start;
            self.cycles += @intCast(elapsed);
            self.calls += 1;
            self.start_time = null;
        }
    }

    fn report(self: *const ProfileSection, writer: anytype, total_ns: u64) !void {
        if (self.calls == 0) return;

        const avg_ns = self.cycles / self.calls;
        const percent = (@as(f64, @floatFromInt(self.cycles)) / @as(f64, @floatFromInt(total_ns))) * 100.0;

        try writer.print("{s:30} {d:10} calls  {d:8.2} ms total  {d:6} ns/call  {d:5.1}%\n", .{
            self.name,
            self.calls,
            @as(f64, @floatFromInt(self.cycles)) / 1_000_000.0,
            avg_ns,
            percent,
        });
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: perf_analysis <rom_file>\n", .{});
        return;
    }

    const rom_path = args[1];

    // Load ROM
    const rom_bytes = try std.fs.cwd().readFileAlloc(allocator, rom_path, 10 * 1024 * 1024);
    defer allocator.free(rom_bytes);

    const rom = try InesModule.parseRom(allocator, rom_bytes);
    defer rom.deinit(allocator);

    // Create cartridge
    var any_cart = try RegistryModule.createCartridge(allocator, rom);
    defer any_cart.deinit();

    // Initialize emulation
    var config = Config.Config{
        .cpu = .{},
        .ppu = .{},
        .apu = .{},
    };

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.loadCartridge(any_cart);
    state.reset();

    // Profile sections
    var tick_section = ProfileSection{ .name = "EmulationState.tick", .cycles = 0, .calls = 0, .start_time = null };
    var ppu_section = ProfileSection{ .name = "PPU.tick", .cycles = 0, .calls = 0, .start_time = null };
    var cpu_section = ProfileSection{ .name = "CPU.executeCycle", .cycles = 0, .calls = 0, .start_time = null };
    var bus_read_section = ProfileSection{ .name = "busRead", .cycles = 0, .calls = 0, .start_time = null };
    var bus_write_section = ProfileSection{ .name = "busWrite", .cycles = 0, .calls = 0, .start_time = null };

    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== Performance Analysis: {s} ===\n\n", .{rom_path});

    // Warmup phase (1 second of emulation)
    try stdout.print("Warming up...\n", .{});
    const warmup_frames = 60;
    for (0..warmup_frames) |_| {
        state.frame_complete = false;
        while (!state.frame_complete) {
            state.tick();
        }
    }

    // Profile phase
    try stdout.print("Profiling 600 frames...\n\n", .{});

    const profile_frames = 600;
    const start_time = std.time.nanoTimestamp();

    var total_ticks: u64 = 0;
    var total_cpu_ticks: u64 = 0;
    var total_ppu_ticks: u64 = 0;

    // Custom tick function with profiling
    for (0..profile_frames) |frame_num| {
        state.frame_complete = false;

        while (!state.frame_complete) {
            tick_section.start();

            // Inline the critical path to profile components
            if (!state.debuggerShouldHalt()) {
                const step = state.nextTimingStep();

                // Profile PPU
                ppu_section.start();
                const PpuLogic = @import("RAMBO").PpuLogic;
                PpuLogic.advanceClock(&state.ppu);
                const cart_ptr = if (state.cart) |*cart| cart else null;
                PpuLogic.tick(&state.ppu, state.clock.master_cycles, cart_ptr);
                state.cpu.nmi_line = state.ppu.nmi_line;
                ppu_section.stop();
                total_ppu_ticks += 1;

                // Profile APU
                if (step.apu_tick) {
                    const apu_result = state.stepApuCycle();
                    _ = apu_result;
                }

                // Profile CPU
                if (step.cpu_tick) {
                    cpu_section.start();
                    const cpu_result = state.stepCpuCycle();
                    if (cpu_result.mapper_irq) {
                        state.cpu.irq_line = true;
                    }
                    cpu_section.stop();
                    total_cpu_ticks += 1;
                }
            }

            tick_section.stop();
            total_ticks += 1;
        }

        // Progress report
        if ((frame_num + 1) % 60 == 0) {
            try stdout.print("Frame {d}/600\r", .{frame_num + 1});
        }
    }

    const end_time = std.time.nanoTimestamp();
    const total_ns: u64 = @intCast(end_time - start_time);

    // Calculate metrics
    const seconds = @as(f64, @floatFromInt(total_ns)) / 1_000_000_000.0;
    const fps = @as(f64, profile_frames) / seconds;
    const ticks_per_second = @as(f64, @floatFromInt(total_ticks)) / seconds;

    // NES timing constants
    const nes_cpu_hz = 1_789_773.0; // NTSC
    const nes_ppu_hz = nes_cpu_hz * 3.0;
    const target_fps = 60.0;

    const speed_ratio = ticks_per_second / nes_ppu_hz;

    try stdout.print("\n\n=== Performance Results ===\n", .{});
    try stdout.print("Total Time:          {d:.3} seconds\n", .{seconds});
    try stdout.print("Frames Rendered:     {d}\n", .{profile_frames});
    try stdout.print("Frames Per Second:   {d:.2} FPS\n", .{fps});
    try stdout.print("Total Ticks:         {d}\n", .{total_ticks});
    try stdout.print("Ticks Per Second:    {d:.0}\n", .{ticks_per_second});
    try stdout.print("Speed Ratio:         {d:.2}x real-time\n", .{speed_ratio});
    try stdout.print("Target FPS Delta:    {d:+.2} FPS\n\n", .{fps - target_fps});

    try stdout.print("=== Component Breakdown ===\n", .{});
    try stdout.print("{s:30} {s:10} {s:15} {s:12} {s:7}\n", .{
        "Component", "Calls", "Total Time", "Avg Time", "Percent"
    });
    try stdout.print("{s:->85}\n", .{""});

    try tick_section.report(stdout, total_ns);
    try ppu_section.report(stdout, total_ns);
    try cpu_section.report(stdout, total_ns);
    try bus_read_section.report(stdout, total_ns);
    try bus_write_section.report(stdout, total_ns);

    try stdout.print("\n=== Tick Statistics ===\n", .{});
    try stdout.print("PPU Ticks:           {d} ({d:.1}% of total)\n", .{
        total_ppu_ticks,
        (@as(f64, @floatFromInt(total_ppu_ticks)) / @as(f64, @floatFromInt(total_ticks))) * 100.0
    });
    try stdout.print("CPU Ticks:           {d} ({d:.1}% of total)\n", .{
        total_cpu_ticks,
        (@as(f64, @floatFromInt(total_cpu_ticks)) / @as(f64, @floatFromInt(total_ticks))) * 100.0
    });

    const cpu_ppu_ratio = @as(f64, @floatFromInt(total_cpu_ticks)) / @as(f64, @floatFromInt(total_ppu_ticks));
    try stdout.print("CPU/PPU Ratio:       1:{d:.2} (expected 1:3)\n", .{1.0 / cpu_ppu_ratio});

    // Performance assessment
    try stdout.print("\n=== Performance Assessment ===\n", .{});

    if (speed_ratio > 100) {
        try stdout.print("✅ EXCELLENT: Running at {d:.0}x real-time speed\n", .{speed_ratio});
    } else if (speed_ratio > 10) {
        try stdout.print("✅ GOOD: Running at {d:.1}x real-time speed\n", .{speed_ratio});
    } else if (speed_ratio > 1) {
        try stdout.print("⚠️  MARGINAL: Running at {d:.1}x real-time speed\n", .{speed_ratio});
    } else {
        try stdout.print("❌ POOR: Running below real-time ({d:.1}x)\n", .{speed_ratio});
    }

    if (fps >= 60) {
        try stdout.print("✅ Frame rate target achieved ({d:.1} FPS)\n", .{fps});
    } else {
        try stdout.print("❌ Below target frame rate ({d:.1} FPS < 60 FPS)\n", .{fps});
    }

    // Bottleneck identification
    try stdout.print("\n=== Bottleneck Analysis ===\n", .{});

    const ppu_percent = (@as(f64, @floatFromInt(ppu_section.cycles)) / @as(f64, @floatFromInt(total_ns))) * 100.0;
    const cpu_percent = (@as(f64, @floatFromInt(cpu_section.cycles)) / @as(f64, @floatFromInt(total_ns))) * 100.0;

    if (ppu_percent > 50) {
        try stdout.print("🔥 PPU is the primary bottleneck ({d:.1}% of runtime)\n", .{ppu_percent});
        try stdout.print("   Consider:\n");
        try stdout.print("   - Optimizing sprite evaluation\n");
        try stdout.print("   - Improving tile fetch caching\n");
        try stdout.print("   - Reducing VRAM access overhead\n");
    } else if (cpu_percent > 30) {
        try stdout.print("🔥 CPU is a significant bottleneck ({d:.1}% of runtime)\n", .{cpu_percent});
        try stdout.print("   Consider:\n");
        try stdout.print("   - Optimizing instruction dispatch\n");
        try stdout.print("   - Improving addressing mode calculations\n");
        try stdout.print("   - Caching frequently accessed memory\n");
    } else {
        try stdout.print("✅ No single component dominates runtime\n");
    }
}