const std = @import("std");

pub const DiagnosticConfig = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    rambo_module: *std.Build.Module,
};

pub const DiagnosticArtifacts = struct {
    executable: *std.Build.Step.Compile,
    run: *std.Build.Step.Run,
};

pub fn setupSmbDiagnostic(b: *std.Build, config: DiagnosticConfig) DiagnosticArtifacts {
    const root_module = b.createModule(.{
        .root_source_file = b.path("tests/unit/smb_diagnostic.zig"),
        .target = config.target,
        .optimize = config.optimize,
        .imports = &.{
            .{ .name = "RAMBO", .module = config.rambo_module },
        },
    });

    const exe = b.addExecutable(.{
        .name = "smb_diagnostic",
        .root_module = root_module,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    return .{
        .executable = exe,
        .run = run_cmd,
    };
}
