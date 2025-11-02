const std = @import("std");

pub const DependencyModules = struct {
    xev: *std.Build.Module,
    zli: *std.Build.Module,
    movy: ?*std.Build.Module,
};

pub fn resolve(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    with_movy: bool,
) DependencyModules {
    const xev_dep = b.dependency("libxev", .{
        .target = target,
        .optimize = optimize,
    });
    const zli_dep = b.dependency("zli", .{
        .target = target,
        .optimize = optimize,
    });

    const movy_module: ?*std.Build.Module = if (with_movy) blk: {
        const movy_dep = b.dependency("movy", .{
            .target = target,
            // Note: movy hard-codes optimize mode internally, don't pass it
        });
        break :blk movy_dep.module("movy");
    } else null;

    return .{
        .xev = xev_dep.module("xev"),
        .zli = zli_dep.module("zli"),
        .movy = movy_module,
    };
}
