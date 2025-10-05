const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    const mod = b.addModule("RAMBO", .{
        // The root source file is the "entry point" of this module. Users of
        // this module will only be able to access public declarations contained
        // in this file, which means that if you have declarations that you
        // intend to expose to consumers that were defined in other files part
        // of this module, you will have to make sure to re-export them from
        // the root file.
        .root_source_file = b.path("src/root.zig"),
        // Later on we'll use this module as the root module of a test executable
        // which requires us to specify a target.
        .target = target,
    });

    // Here we define an executable. An executable needs to have a root module
    // which needs to expose a `main` function. While we could add a main function
    // to the module defined above, it's sometimes preferable to split business
    // business logic and the CLI into two separate modules.
    //
    // If your goal is to create a Zig library for others to use, consider if
    // it might benefit from also exposing a CLI tool. A parser library for a
    // data serialization format could also bundle a CLI syntax checker, for example.
    //
    // If instead your goal is to create an executable, consider if users might
    // be interested in also being able to embed the core functionality of your
    // program in their own executable in order to avoid the overhead involved in
    // subprocessing your CLI tool.
    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.
    // Add libxev dependency
    const xev_dep = b.dependency("libxev", .{
        .target = target,
        .optimize = optimize,
    });

    // ========================================================================
    // Wayland Client Bindings (for Linux window creation)
    // ========================================================================

    // Wayland XML paths (standard Linux locations)
    const wayland_xml = "/usr/share/wayland/wayland.xml";
    const wayland_protocols = "/usr/share/wayland-protocols";

    // Get wayland dependency and create scanner
    const wayland_dep = b.lazyDependency("wayland", .{}) orelse return;
    const wayland_scanner_mod = b.createModule(.{
        .root_source_file = wayland_dep.path("src/scanner.zig"),
        .target = b.graph.host,
    });
    const wayland_scanner = b.addExecutable(.{
        .name = "zig-wayland-scanner",
        .root_module = wayland_scanner_mod,
    });

    // Run scanner to generate Wayland client bindings
    const wayland_scanner_run = b.addRunArtifact(wayland_scanner);
    wayland_scanner_run.addArg("-o");
    const wayland_zig = wayland_scanner_run.addOutputFileArg("wayland.zig");

    // Add protocol XML files
    wayland_scanner_run.addArg("-i");
    wayland_scanner_run.addArg(wayland_xml);
    wayland_scanner_run.addArg("-i");
    wayland_scanner_run.addArg(b.fmt("{s}/stable/xdg-shell/xdg-shell.xml", .{wayland_protocols}));
    wayland_scanner_run.addArg("-i");
    wayland_scanner_run.addArg(b.fmt("{s}/unstable/xdg-decoration/xdg-decoration-unstable-v1.xml", .{wayland_protocols}));

    // Generate interface code for common Wayland globals
    inline for (.{
        .{ "xdg_wm_base", "2" },
        .{ "wl_compositor", "4" },
        .{ "wl_output", "4" },
        .{ "wl_seat", "5" },
        .{ "wl_shm", "1" },
        .{ "zxdg_decoration_manager_v1", "1" },
    }) |pair| {
        wayland_scanner_run.addArg("-g");
        wayland_scanner_run.addArg(pair[0]);
        wayland_scanner_run.addArg(pair[1]);
    }

    // Create module from generated Wayland bindings
    const wayland_client_mod = b.addModule("wayland_client", .{
        .root_source_file = wayland_zig,
    });

    const exe = b.addExecutable(.{
        .name = "RAMBO",
        .root_module = b.createModule(.{
            // b.createModule defines a new module just like b.addModule but,
            // unlike b.addModule, it does not expose the module to consumers of
            // this package, which is why in this case we don't have to give it a name.
            .root_source_file = b.path("src/main.zig"),
            // Target and optimization levels must be explicitly wired in when
            // defining an executable or library (in the root module), and you
            // can also hardcode a specific target for an executable or library
            // definition if desireable (e.g. firmware for embedded devices).
            .target = target,
            .optimize = optimize,
            // List of modules available for import in source files part of the
            // root module.
            .imports = &.{
                // Here "RAMBO" is the name you will use in your source code to
                // import this module (e.g. `@import("RAMBO")`). The name is
                // repeated because you are allowed to rename your imports, which
                // can be extremely useful in case of collisions (which can happen
                // importing modules from different packages).
                .{ .name = "RAMBO", .module = mod },
                // libxev for event loop and thread pooling
                .{ .name = "xev", .module = xev_dep.module("xev") },
                // Wayland client bindings (generated from protocol XMLs)
                .{ .name = "wayland_client", .module = wayland_client_mod },
            },
        }),
    });

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // ========================================================================
    // Unit Tests (embedded in modules)
    // ========================================================================

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    mod_tests.root_module.addImport("xev", xev_dep.module("xev"));

    const run_mod_tests = b.addRunArtifact(mod_tests);

    // ========================================================================
    // Integration Tests (in tests/ directory)
    // ========================================================================

    // Simple NOP debug test
    const simple_nop_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cpu/simple_nop_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_simple_nop_test = b.addRunArtifact(simple_nop_test);

    // CPU instruction tests
    const cpu_integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cpu/instructions_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_cpu_integration_tests = b.addRunArtifact(cpu_integration_tests);

    // CPU opcode unit tests - arithmetic
    const arithmetic_opcode_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cpu/opcodes/arithmetic_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_arithmetic_opcode_tests = b.addRunArtifact(arithmetic_opcode_tests);

    // CPU opcode unit tests - loadstore
    const loadstore_opcode_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cpu/opcodes/loadstore_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_loadstore_opcode_tests = b.addRunArtifact(loadstore_opcode_tests);

    // CPU opcode unit tests - logical
    const logical_opcode_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cpu/opcodes/logical_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });
    const run_logical_opcode_tests = b.addRunArtifact(logical_opcode_tests);

    // CPU opcode unit tests - compare
    const compare_opcode_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cpu/opcodes/compare_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });
    const run_compare_opcode_tests = b.addRunArtifact(compare_opcode_tests);

    // CPU opcode unit tests - transfer
    const transfer_opcode_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cpu/opcodes/transfer_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });
    const run_transfer_opcode_tests = b.addRunArtifact(transfer_opcode_tests);

    // CPU opcode unit tests - incdec
    const incdec_opcode_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cpu/opcodes/incdec_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });
    const run_incdec_opcode_tests = b.addRunArtifact(incdec_opcode_tests);

    // CPU opcode unit tests - stack
    const stack_opcode_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cpu/opcodes/stack_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });
    const run_stack_opcode_tests = b.addRunArtifact(stack_opcode_tests);

    // CPU opcode unit tests - shifts
    const shifts_opcode_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cpu/opcodes/shifts_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });
    const run_shifts_opcode_tests = b.addRunArtifact(shifts_opcode_tests);

    // CPU opcode unit tests - branch
    const branch_opcode_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cpu/opcodes/branch_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });
    const run_branch_opcode_tests = b.addRunArtifact(branch_opcode_tests);

    // CPU opcode unit tests - jumps
    const jumps_opcode_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cpu/opcodes/jumps_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });
    const run_jumps_opcode_tests = b.addRunArtifact(jumps_opcode_tests);

    // CPU opcode unit tests - unofficial
    const unofficial_opcode_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cpu/opcodes/unofficial_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });
    const run_unofficial_opcode_tests = b.addRunArtifact(unofficial_opcode_tests);

    // RMW instruction tests
    const rmw_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cpu/rmw_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_rmw_tests = b.addRunArtifact(rmw_tests);

    // Bus integration tests
    const bus_integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/bus/bus_integration_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_bus_integration_tests = b.addRunArtifact(bus_integration_tests);

    // CPU-PPU integration tests
    const cpu_ppu_integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/cpu_ppu_integration_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_cpu_ppu_integration_tests = b.addRunArtifact(cpu_ppu_integration_tests);

    // Cartridge tests (AccuracyCoin.nes integration)
    const cartridge_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cartridge/accuracycoin_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_cartridge_tests = b.addRunArtifact(cartridge_tests);

    // PPU CHR integration tests
    const chr_integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/ppu/chr_integration_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_chr_integration_tests = b.addRunArtifact(chr_integration_tests);

    // PPU sprite evaluation tests
    const sprite_evaluation_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/ppu/sprite_evaluation_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_sprite_evaluation_tests = b.addRunArtifact(sprite_evaluation_tests);

    // PPU sprite rendering tests
    const sprite_rendering_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/ppu/sprite_rendering_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_sprite_rendering_tests = b.addRunArtifact(sprite_rendering_tests);

    // PPU sprite edge cases tests
    const sprite_edge_cases_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/ppu/sprite_edge_cases_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_sprite_edge_cases_tests = b.addRunArtifact(sprite_edge_cases_tests);

    // Snapshot integration tests
    const snapshot_integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/snapshot/snapshot_integration_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_snapshot_integration_tests = b.addRunArtifact(snapshot_integration_tests);

    // Debugger integration tests
    const debugger_integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/debugger/debugger_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_debugger_integration_tests = b.addRunArtifact(debugger_integration_tests);

    // ========================================================================
    // Test Step Configuration
    // ========================================================================

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_cpu_integration_tests.step);
    test_step.dependOn(&run_arithmetic_opcode_tests.step);
    test_step.dependOn(&run_loadstore_opcode_tests.step);
    test_step.dependOn(&run_logical_opcode_tests.step);
    test_step.dependOn(&run_compare_opcode_tests.step);
    test_step.dependOn(&run_transfer_opcode_tests.step);
    test_step.dependOn(&run_incdec_opcode_tests.step);
    test_step.dependOn(&run_stack_opcode_tests.step);
    test_step.dependOn(&run_shifts_opcode_tests.step);
    test_step.dependOn(&run_branch_opcode_tests.step);
    test_step.dependOn(&run_jumps_opcode_tests.step);
    test_step.dependOn(&run_unofficial_opcode_tests.step);
    test_step.dependOn(&run_rmw_tests.step);
    test_step.dependOn(&run_bus_integration_tests.step);
    test_step.dependOn(&run_cpu_ppu_integration_tests.step);
    test_step.dependOn(&run_cartridge_tests.step);
    test_step.dependOn(&run_chr_integration_tests.step);
    test_step.dependOn(&run_sprite_evaluation_tests.step);
    test_step.dependOn(&run_sprite_rendering_tests.step);
    test_step.dependOn(&run_sprite_edge_cases_tests.step);
    test_step.dependOn(&run_snapshot_integration_tests.step);
    test_step.dependOn(&run_debugger_integration_tests.step);

    // Separate step for just unit tests
    const unit_test_step = b.step("test-unit", "Run unit tests only");
    unit_test_step.dependOn(&run_mod_tests.step);

    // Separate step for just integration tests
    const integration_test_step = b.step("test-integration", "Run integration tests only");
    integration_test_step.dependOn(&run_cpu_integration_tests.step);
    integration_test_step.dependOn(&run_rmw_tests.step);
    integration_test_step.dependOn(&run_bus_integration_tests.step);
    integration_test_step.dependOn(&run_cpu_ppu_integration_tests.step);
    integration_test_step.dependOn(&run_cartridge_tests.step);
    integration_test_step.dependOn(&run_chr_integration_tests.step);
    integration_test_step.dependOn(&run_sprite_evaluation_tests.step);
    integration_test_step.dependOn(&run_sprite_rendering_tests.step);
    integration_test_step.dependOn(&run_sprite_edge_cases_tests.step);
    integration_test_step.dependOn(&run_snapshot_integration_tests.step);
    integration_test_step.dependOn(&run_debugger_integration_tests.step);

    // Cycle trace test
    const cycle_trace_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cpu/cycle_trace_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_cycle_trace_test = b.addRunArtifact(cycle_trace_test);

    // RMW debug trace test
    const rmw_debug_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cpu/rmw_debug_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_rmw_debug_test = b.addRunArtifact(rmw_debug_test);

    // Debug test step
    const debug_test_step = b.step("test-debug", "Run debug test");
    debug_test_step.dependOn(&run_simple_nop_test.step);

    // Cycle trace test step
    const trace_test_step = b.step("test-trace", "Run cycle trace tests");
    trace_test_step.dependOn(&run_cycle_trace_test.step);

    // RMW debug trace test step
    const rmw_debug_step = b.step("test-rmw-debug", "Run RMW debug trace test");
    rmw_debug_step.dependOn(&run_rmw_debug_test.step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
