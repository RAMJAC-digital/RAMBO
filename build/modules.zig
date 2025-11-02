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
    // Build imports list conditionally including movy if available
    const base_imports = [_]std.Build.Module.Import{
        .{ .name = "build_options", .module = config.build_options.module },
        .{ .name = "wayland_client", .module = config.wayland.module },
        .{ .name = "xev", .module = config.dependencies.xev },
        .{ .name = "zli", .module = config.dependencies.zli },
    };

    const imports = if (config.dependencies.movy) |movy_module|
        &(base_imports ++ [_]std.Build.Module.Import{
            .{ .name = "movy", .module = movy_module },
        })
    else
        &base_imports;

    const mod = b.addModule("RAMBO", .{
        .root_source_file = b.path("src/root.zig"),
        .target = config.target,
        .imports = imports,
    });

    // Build root module imports conditionally including movy
    const base_root_imports = [_]std.Build.Module.Import{
        .{ .name = "RAMBO", .module = mod },
        .{ .name = "xev", .module = config.dependencies.xev },
        .{ .name = "zli", .module = config.dependencies.zli },
        .{ .name = "wayland_client", .module = config.wayland.module },
        .{ .name = "build_options", .module = config.build_options.module },
    };

    const root_imports = if (config.dependencies.movy) |movy_module|
        &(base_root_imports ++ [_]std.Build.Module.Import{
            .{ .name = "movy", .module = movy_module },
        })
    else
        &base_root_imports;

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .link_libc = true,
        .link_libcpp = false,
        .imports = root_imports,
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
