const std = @import("std");

pub const ShaderArtifacts = struct {
    install_vertex: *std.Build.Step.InstallFile,
    install_fragment: *std.Build.Step.InstallFile,
};

pub fn setup(b: *std.Build) ShaderArtifacts {
    const compile_vert = b.addSystemCommand(&.{
        "glslc",
        "-o",
    });
    const vert_spv = compile_vert.addOutputFileArg("texture.vert.spv");
    compile_vert.addFileArg(b.path("src/video/shaders/texture.vert"));

    const compile_frag = b.addSystemCommand(&.{
        "glslc",
        "-o",
    });
    const frag_spv = compile_frag.addOutputFileArg("texture.frag.spv");
    compile_frag.addFileArg(b.path("src/video/shaders/texture.frag"));

    const install_vert = b.addInstallFile(vert_spv, "shaders/texture.vert.spv");
    const install_frag = b.addInstallFile(frag_spv, "shaders/texture.frag.spv");

    return .{
        .install_vertex = install_vert,
        .install_fragment = install_frag,
    };
}
