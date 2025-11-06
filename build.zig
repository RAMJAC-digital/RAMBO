const std = @import("std");
const Options = @import("build/options.zig");
const Dependencies = @import("build/dependencies.zig");
const Wayland = @import("build/wayland.zig");
const Graphics = @import("build/graphics.zig");
const Modules = @import("build/modules.zig");
const Diagnostics = @import("build/diagnostics.zig");
const Tests = @import("build/tests.zig");
const Wasm = @import("build/wasm.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const with_movy = b.option(bool, "with_movy", "Enable movy terminal rendering backend") orelse false;

    const build_options = Options.create(b, .{
        .with_wayland = true,
        .with_movy = with_movy,
        .single_thread = false,
    });
    const deps = Dependencies.resolve(b, target, optimize, with_movy);

    const wayland = Wayland.generate(b) catch return;
    const shaders = Graphics.setup(b);

    const modules = Modules.setup(b, .{
        .target = target,
        .optimize = optimize,
        .dependencies = deps,
        .build_options = build_options,
        .wayland = wayland,
        .with_wayland = true,
        .single_thread = false,
    });

    b.getInstallStep().dependOn(&shaders.install_vertex.step);
    b.getInstallStep().dependOn(&shaders.install_fragment.step);

    const run_cmd = modules.run;
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const tests = Tests.register(b, .{
        .target = target,
        .optimize = optimize,
        .modules = .{
            .rambo = modules.module,
            .xev = deps.xev,
            .zli = deps.zli,
            .wayland_client = wayland.module,
            .build_options = build_options.module,
        },
    }) catch unreachable;

    const test_step = b.step("test", "Run all tests");
    for (tests.all) |step| test_step.dependOn(step);

    const unit_test_step = b.step("test-unit", "Run unit tests only");
    for (tests.unit) |step| unit_test_step.dependOn(step);

    const integration_test_step = b.step("test-integration", "Run integration tests only");
    for (tests.integration) |step| integration_test_step.dependOn(step);

    const bench_release_step = b.step("bench-release", "Run release-optimized benchmark suite");
    for (tests.bench_release) |step| bench_release_step.dependOn(step);

    const tooling_step = b.step("test-tooling", "Run helper/tooling diagnostics");
    for (tests.tooling) |step| tooling_step.dependOn(step);

    // ---------------------------------------------------------------------
    // WebAssembly single-threaded build target
    // ---------------------------------------------------------------------

    const wasm_build_options = Options.create(b, .{
        .with_wayland = false,
        .with_movy = false,
        .single_thread = true,
    });

    const wasm = Wasm.setup(b, .{
        .optimize = optimize,
        .build_options = wasm_build_options,
    });

    const wasm_step = b.step("wasm", "Build the WebAssembly module");
    wasm_step.dependOn(&wasm.install.step);
}
