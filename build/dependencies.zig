const std = @import("std");

pub const DependencyModules = struct {
    xev: *std.Build.Module,
    zli: *std.Build.Module,
};

pub fn resolve(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) DependencyModules {
    const xev_dep = b.dependency("libxev", .{
        .target = target,
        .optimize = optimize,
    });
    const zli_dep = b.dependency("zli", .{
        .target = target,
        .optimize = optimize,
    });

    return .{
        .xev = xev_dep.module("xev"),
        .zli = zli_dep.module("zli"),
    };
}
