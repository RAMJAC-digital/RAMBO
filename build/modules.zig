const std = @import("std");
const Dependencies = @import("dependencies.zig");
const Wayland = @import("wayland.zig");
const Options = @import("options.zig");

pub const ModuleConfig = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    dependencies: Dependencies.DependencyModules,
    build_options: Options.BuildOptions,
    wayland: Wayland.WaylandArtifacts,
};

pub const ModuleArtifacts = struct {
    module: *std.Build.Module,
    executable: *std.Build.Step.Compile,
    run: *std.Build.Step.Run,
};

pub fn setup(b: *std.Build, config: ModuleConfig) ModuleArtifacts {
    const mod = b.addModule("RAMBO", .{
        .root_source_file = b.path("src/root.zig"),
        .target = config.target,
        .imports = &.{
            .{ .name = "build_options", .module = config.build_options.module },
            .{ .name = "wayland_client", .module = config.wayland.module },
            .{ .name = "xev", .module = config.dependencies.xev },
            .{ .name = "zli", .module = config.dependencies.zli },
        },
    });

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .link_libc = true,
        .link_libcpp = false,
        .imports = &.{
            .{ .name = "RAMBO", .module = mod },
            .{ .name = "xev", .module = config.dependencies.xev },
            .{ .name = "zli", .module = config.dependencies.zli },
            .{ .name = "wayland_client", .module = config.wayland.module },
            .{ .name = "build_options", .module = config.build_options.module },
        },
    });

    const exe = b.addExecutable(.{
        .name = "RAMBO",
        .root_module = root_module,
    });

    exe.linkSystemLibrary("wayland-client");
    exe.linkSystemLibrary("xkbcommon");
    exe.linkSystemLibrary("vulkan");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    return .{
        .module = mod,
        .executable = exe,
        .run = run_cmd,
    };
}
