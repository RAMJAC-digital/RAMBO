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
    with_wayland: bool,
    single_thread: bool,
};

pub const ModuleArtifacts = struct {
    module: *std.Build.Module,
    executable: *std.Build.Step.Compile,
    run: *std.Build.Step.Run,
};

pub fn setup(b: *std.Build, config: ModuleConfig) ModuleArtifacts {
    // Build imports list conditionally including platform modules
    var module_imports: [5]std.Build.Module.Import = undefined;
    var module_import_count: usize = 0;

    module_imports[module_import_count] = .{ .name = "build_options", .module = config.build_options.module };
    module_import_count += 1;

    if (config.with_wayland) {
        module_imports[module_import_count] = .{ .name = "wayland_client", .module = config.wayland.module };
        module_import_count += 1;
    }

    if (!config.single_thread) {
        module_imports[module_import_count] = .{ .name = "xev", .module = config.dependencies.xev };
        module_import_count += 1;

        module_imports[module_import_count] = .{ .name = "zli", .module = config.dependencies.zli };
        module_import_count += 1;
    }

    if (config.dependencies.movy) |movy_module| {
        module_imports[module_import_count] = .{ .name = "movy", .module = movy_module };
        module_import_count += 1;
    }

    const imports = module_imports[0..module_import_count];

    const mod = b.addModule("RAMBO", .{
        .root_source_file = b.path("src/root.zig"),
        .target = config.target,
        .imports = imports,
    });

    // Build root module imports conditionally including movy
    var root_imports_buf: [6]std.Build.Module.Import = undefined;
    var root_import_count: usize = 0;

    root_imports_buf[root_import_count] = .{ .name = "RAMBO", .module = mod };
    root_import_count += 1;

    if (!config.single_thread) {
        root_imports_buf[root_import_count] = .{ .name = "xev", .module = config.dependencies.xev };
        root_import_count += 1;

        root_imports_buf[root_import_count] = .{ .name = "zli", .module = config.dependencies.zli };
        root_import_count += 1;
    }

    if (config.with_wayland) {
        root_imports_buf[root_import_count] = .{ .name = "wayland_client", .module = config.wayland.module };
        root_import_count += 1;
    }

    root_imports_buf[root_import_count] = .{ .name = "build_options", .module = config.build_options.module };
    root_import_count += 1;

    if (config.dependencies.movy) |movy_module| {
        root_imports_buf[root_import_count] = .{ .name = "movy", .module = movy_module };
        root_import_count += 1;
    }

    const root_imports = root_imports_buf[0..root_import_count];

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

    if (config.with_wayland) {
        exe.linkSystemLibrary("wayland-client");
        exe.linkSystemLibrary("xkbcommon");
        exe.linkSystemLibrary("vulkan");
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    return .{
        .module = mod,
        .executable = exe,
        .run = run_cmd,
    };
}
