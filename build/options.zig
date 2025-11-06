const std = @import("std");

pub const BuildOptions = struct {
    step: *std.Build.Step.Options,
    module: *std.Build.Module,
};

pub const CreateParams = struct {
    with_wayland: bool = true,
    with_movy: bool = false,
    single_thread: bool = false,
};

pub fn create(b: *std.Build, params: CreateParams) BuildOptions {
    const options = b.addOptions();
    options.addOption(bool, "with_wayland", params.with_wayland);
    options.addOption(bool, "with_movy", params.with_movy);
    options.addOption(bool, "single_thread", params.single_thread);
    return .{
        .step = options,
        .module = options.createModule(),
    };
}
