const std = @import("std");

pub const WaylandArtifacts = struct {
    module: *std.Build.Module,
    generator: *std.Build.Step.Run,
};

pub const WaylandError = error{
    MissingDependency,
};

pub fn generate(b: *std.Build) WaylandError!WaylandArtifacts {
    const wayland_dep = b.lazyDependency("wayland", .{}) orelse return WaylandError.MissingDependency;

    const wayland_scanner_mod = b.createModule(.{
        .root_source_file = wayland_dep.path("src/scanner.zig"),
        .target = b.graph.host,
    });

    const wayland_scanner = b.addExecutable(.{
        .name = "zig-wayland-scanner",
        .root_module = wayland_scanner_mod,
    });

    const scanner_run = b.addRunArtifact(wayland_scanner);
    scanner_run.addArg("-o");
    const wayland_zig = scanner_run.addOutputFileArg("wayland.zig");

    const wayland_xml = "/usr/share/wayland/wayland.xml";
    const wayland_protocols = "/usr/share/wayland-protocols";

    scanner_run.addArg("-i");
    scanner_run.addArg(wayland_xml);
    scanner_run.addArg("-i");
    scanner_run.addArg(b.fmt("{s}/stable/xdg-shell/xdg-shell.xml", .{wayland_protocols}));
    scanner_run.addArg("-i");
    scanner_run.addArg(b.fmt(
        "{s}/unstable/xdg-decoration/xdg-decoration-unstable-v1.xml",
        .{wayland_protocols},
    ));

    inline for (.{
        .{ "xdg_wm_base", "2" },
        .{ "wl_compositor", "4" },
        .{ "wl_output", "4" },
        .{ "wl_seat", "5" },
        .{ "wl_shm", "1" },
        .{ "zxdg_decoration_manager_v1", "1" },
    }) |pair| {
        scanner_run.addArg("-g");
        scanner_run.addArg(pair[0]);
        scanner_run.addArg(pair[1]);
    }

    const wayland_client_mod = b.addModule("wayland_client", .{
        .root_source_file = wayland_zig,
    });

    return .{ .module = wayland_client_mod, .generator = scanner_run };
}
