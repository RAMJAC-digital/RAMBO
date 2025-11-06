const std = @import("std");
const Options = @import("options.zig");

/// Centralized list of WebAssembly export symbols.
/// Add new export functions here to ensure they appear in the WASM export table.
pub const EXPORT_SYMBOLS = [_][]const u8{
    "rambo_get_error",
    "rambo_init",
    "rambo_shutdown",
    "rambo_reset",
    "rambo_set_controller_state",
    "rambo_step_frame",
    "rambo_framebuffer_ptr",
    "rambo_framebuffer_size",
    "rambo_frame_dimensions",
    "rambo_alloc",
    "rambo_free",
    "rambo_heap_size_bytes",
    "rambo_last_alloc_ptr",
    "rambo_last_alloc_size",
};

pub const WasmArtifacts = struct {
    install: *std.Build.Step.InstallFile,
};

pub const WasmConfig = struct {
    optimize: std.builtin.OptimizeMode,
    build_options: Options.BuildOptions,
};

pub fn setup(b: *std.Build, config: WasmConfig) WasmArtifacts {
    // Create WASM target (wasm32-freestanding)
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    // Create RAMBO module for WASM (with build_options)
    const wasm_rambo_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = wasm_target,
        .optimize = config.optimize,
        .imports = &.{
            .{ .name = "build_options", .module = config.build_options.module },
        },
    });

    // Create wasm.zig root module (imports RAMBO + build_options)
    const wasm_root_module = b.createModule(.{
        .root_source_file = b.path("src/wasm.zig"),
        .target = wasm_target,
        .optimize = config.optimize,
        .imports = &.{
            .{ .name = "RAMBO", .module = wasm_rambo_module },
            .{ .name = "build_options", .module = config.build_options.module },
        },
    });

    wasm_root_module.export_symbol_names = &EXPORT_SYMBOLS;

    const wasm_exe = b.addExecutable(.{
        .name = "rambo",
        .root_module = wasm_root_module,
    });
    wasm_exe.entry = .disabled;
    wasm_exe.export_table = true;

    // Import memory from JavaScript instead of exporting it
    // This allows JavaScript to create WebAssembly.Memory with proper configuration
    // and avoids Zig linker issues with __heap_base placement
    wasm_exe.import_memory = true;
    wasm_exe.max_memory = 256 * 1024 * 1024; // 256MB max (JavaScript will set initial)

    b.installArtifact(wasm_exe);

    const wasm_output = wasm_exe.getEmittedBin();
    const install = b.addInstallFile(wasm_output, "bin/rambo.wasm");

    return .{
        .install = install,
    };
}
