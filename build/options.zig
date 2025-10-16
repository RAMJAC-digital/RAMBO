const std = @import("std");

pub const BuildOptions = struct {
    step: *std.Build.Step.Options,
    module: *std.Build.Module,
};

pub fn create(b: *std.Build) BuildOptions {
    const options = b.addOptions();
    options.addOption(bool, "with_wayland", true);
    return .{
        .step = options,
        .module = options.createModule(),
    };
}
