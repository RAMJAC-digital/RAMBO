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
    // Build options MUST be created before modules that depend on them
    const build_options = b.addOptions();
    build_options.addOption(bool, "with_wayland", true); // Always enabled on Linux
    const build_options_mod = build_options.createModule();

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

    const zli_dep = b.dependency("zli", .{ .target = target, .optimize = optimize });

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

    // ========================================================================
    // Shader Compilation (Vulkan SPIR-V)
    // ========================================================================

    // Compile vertex shader
    const compile_vert = b.addSystemCommand(&.{
        "glslc",
        "-o",
    });
    const vert_spv = compile_vert.addOutputFileArg("texture.vert.spv");
    compile_vert.addFileArg(b.path("src/video/shaders/texture.vert"));

    // Compile fragment shader
    const compile_frag = b.addSystemCommand(&.{
        "glslc",
        "-o",
    });
    const frag_spv = compile_frag.addOutputFileArg("texture.frag.spv");
    compile_frag.addFileArg(b.path("src/video/shaders/texture.frag"));

    // Install shaders to output directory
    const install_vert = b.addInstallFile(vert_spv, "shaders/texture.vert.spv");
    const install_frag = b.addInstallFile(frag_spv, "shaders/texture.frag.spv");

    // Create RAMBO module (after dependencies are defined)
    const mod = b.addModule("RAMBO", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "build_options", .module = build_options_mod },
            .{ .name = "wayland_client", .module = wayland_client_mod },
        },
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
            // Link libc and Wayland
            .link_libc = true,
            .link_libcpp = false,
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
                .{ .name = "zli", .module = zli_dep.module("zli") },
                // Wayland client bindings (generated from protocol XMLs)
                .{ .name = "wayland_client", .module = wayland_client_mod },
                // Build options (feature flags)
                .{ .name = "build_options", .module = build_options_mod },
            },
        }),
    });

    // Link Wayland client library
    exe.linkSystemLibrary("wayland-client");

    // Link Vulkan library
    exe.linkSystemLibrary("vulkan");

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // Install shaders as part of default build
    b.getInstallStep().dependOn(&install_vert.step);
    b.getInstallStep().dependOn(&install_frag.step);

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

    // CPU control flow integration tests (JSR, RTS, RTI, BRK)
    const control_flow_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cpu/opcodes/control_flow_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });
    const run_control_flow_tests = b.addRunArtifact(control_flow_tests);

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

    // Page crossing behavior tests
    const page_crossing_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cpu/page_crossing_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_page_crossing_tests = b.addRunArtifact(page_crossing_tests);

    // CPU interrupt logic tests (pure functions)
    const cpu_interrupt_logic_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cpu/interrupt_logic_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_cpu_interrupt_logic_tests = b.addRunArtifact(cpu_interrupt_logic_tests);

    // Interrupt execution integration tests
    const interrupt_execution_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/interrupt_execution_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_interrupt_execution_tests = b.addRunArtifact(interrupt_execution_tests);

    const nmi_sequence_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/nmi_sequence_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_nmi_sequence_tests = b.addRunArtifact(nmi_sequence_tests);

    // Bus integration tests
    const bus_integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cpu/bus_integration_test.zig"),
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

    // OAM DMA integration tests
    const oam_dma_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/oam_dma_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_oam_dma_tests = b.addRunArtifact(oam_dma_tests);

    // Controller integration tests ($4016/$4017)
    const controller_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/controller_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_controller_tests = b.addRunArtifact(controller_tests);

    // VBlank wait loop integration tests (CPU-PPU timing)
    const vblank_wait_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/vblank_wait_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_vblank_wait_tests = b.addRunArtifact(vblank_wait_tests);

    // BIT $2002 instruction tests (isolated)
    const bit_ppustatus_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/bit_ppustatus_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_bit_ppustatus_tests = b.addRunArtifact(bit_ppustatus_tests);

    // PPU register absolute addressing tests
    const ppu_register_absolute_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/ppu_register_absolute_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_ppu_register_absolute_tests = b.addRunArtifact(ppu_register_absolute_tests);

    // ROM test runner framework
    const rom_test_runner_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/rom_test_runner.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_rom_test_runner_tests = b.addRunArtifact(rom_test_runner_tests);

    // AccuracyCoin execution test (runs ROM and extracts test results)
    const accuracycoin_execution_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/accuracycoin_execution_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_accuracycoin_execution_tests = b.addRunArtifact(accuracycoin_execution_tests);

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

    // Cartridge PRG RAM tests
    const prg_ram_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cartridge/prg_ram_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_prg_ram_tests = b.addRunArtifact(prg_ram_tests);

    // AccuracyCoin PRG RAM integration tests
    const accuracycoin_prg_ram_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/accuracycoin_prg_ram_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_accuracycoin_prg_ram_tests = b.addRunArtifact(accuracycoin_prg_ram_tests);

    // Framebuffer validation helper tests
    const framebuffer_validator_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/helpers/FramebufferValidator.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_framebuffer_validator_tests = b.addRunArtifact(framebuffer_validator_tests);

    // Commercial ROM integration tests
    const commercial_rom_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/commercial_rom_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_commercial_rom_tests = b.addRunArtifact(commercial_rom_tests);

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

    // PPU VBlank NMI timing tests (fix for race condition)
    const vblank_nmi_timing_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/ppu/vblank_nmi_timing_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_vblank_nmi_timing_tests = b.addRunArtifact(vblank_nmi_timing_tests);

    // PPUSTATUS polling tests
    const ppustatus_polling_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/ppu/ppustatus_polling_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_ppustatus_polling_tests = b.addRunArtifact(ppustatus_polling_tests);

    // VBlank polling simple tests
    const vblank_polling_simple_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/ppu/vblank_polling_simple_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_vblank_polling_simple_tests = b.addRunArtifact(vblank_polling_simple_tests);

    // Seek behavior tests
    const seek_behavior_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/ppu/seek_behavior_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_seek_behavior_tests = b.addRunArtifact(seek_behavior_tests);

    // VBlank persistence tests
    const vblank_persistence_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/ppu/vblank_persistence_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_vblank_persistence_tests = b.addRunArtifact(vblank_persistence_tests);

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

    // APU unit tests
    const apu_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/apu/apu_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_apu_tests = b.addRunArtifact(apu_tests);

    // APU length counter tests (Phase 1.5)
    const apu_length_counter_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/apu/length_counter_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_apu_length_counter_tests = b.addRunArtifact(apu_length_counter_tests);

    // APU DMC tests (Milestone 1)
    const apu_dmc_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/apu/dmc_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_apu_dmc_tests = b.addRunArtifact(apu_dmc_tests);

    // APU Envelope tests (Milestone 2)
    const apu_envelope_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/apu/envelope_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_apu_envelope_tests = b.addRunArtifact(apu_envelope_tests);

    // APU Linear Counter tests (Milestone 3)
    const apu_linear_counter_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/apu/linear_counter_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_apu_linear_counter_tests = b.addRunArtifact(apu_linear_counter_tests);

    // APU Sweep tests (Milestone 4)
    const apu_sweep_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/apu/sweep_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_apu_sweep_tests = b.addRunArtifact(apu_sweep_tests);

    // APU Frame IRQ Edge Case tests (Milestone 5)
    const apu_frame_irq_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/apu/frame_irq_edge_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_apu_frame_irq_tests = b.addRunArtifact(apu_frame_irq_tests);

    // APU Open Bus tests (Milestone 6)
    const apu_open_bus_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/apu/open_bus_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_apu_open_bus_tests = b.addRunArtifact(apu_open_bus_tests);

    // DPCM DMA integration tests
    const dpcm_dma_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/dpcm_dma_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_dpcm_dma_tests = b.addRunArtifact(dpcm_dma_tests);

    // Benchmark integration tests
    const benchmark_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/benchmark_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_benchmark_tests = b.addRunArtifact(benchmark_tests);

    // Release build benchmark (production settings)
    const benchmark_release_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/benchmark_test.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_benchmark_release_tests = b.addRunArtifact(benchmark_release_tests);

    // iNES ROM parser tests
    const ines_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/ines/ines_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ines", .module = b.addModule("ines", .{
                    .root_source_file = b.path("src/cartridge/ines/mod.zig"),
                    .target = target,
                }) },
            },
        }),
    });

    const run_ines_tests = b.addRunArtifact(ines_tests);

    // Threading system tests
    const threading_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/threads/threading_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true, // Required for c_allocator in Wayland code
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
                .{ .name = "xev", .module = xev_dep.module("xev") },
                .{ .name = "build_options", .module = build_options_mod },
                .{ .name = "wayland_client", .module = wayland_client_mod },
            },
        }),
    });
    threading_tests.linkSystemLibrary("wayland-client");
    threading_tests.linkSystemLibrary("vulkan");

    const run_threading_tests = b.addRunArtifact(threading_tests);

    // ========================================================================
    // Input System Tests
    // ========================================================================

    // ButtonState unit tests
    const button_state_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/input/button_state_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_button_state_tests = b.addRunArtifact(button_state_tests);

    // KeyboardMapper unit tests
    const keyboard_mapper_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/input/keyboard_mapper_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "RAMBO", .module = mod },
            },
        }),
    });

    const run_keyboard_mapper_tests = b.addRunArtifact(keyboard_mapper_tests);

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
    test_step.dependOn(&run_control_flow_tests.step);
    test_step.dependOn(&run_rmw_tests.step);
    test_step.dependOn(&run_page_crossing_tests.step);
    test_step.dependOn(&run_cpu_interrupt_logic_tests.step);
    test_step.dependOn(&run_interrupt_execution_tests.step);
    test_step.dependOn(&run_nmi_sequence_tests.step);
    test_step.dependOn(&run_bus_integration_tests.step);
    test_step.dependOn(&run_cpu_ppu_integration_tests.step);
    test_step.dependOn(&run_oam_dma_tests.step);
    test_step.dependOn(&run_controller_tests.step);
    test_step.dependOn(&run_vblank_wait_tests.step);
    test_step.dependOn(&run_bit_ppustatus_tests.step);
    test_step.dependOn(&run_ppu_register_absolute_tests.step);
    test_step.dependOn(&run_rom_test_runner_tests.step);
    test_step.dependOn(&run_accuracycoin_execution_tests.step);
    test_step.dependOn(&run_cartridge_tests.step);
    test_step.dependOn(&run_prg_ram_tests.step);
    test_step.dependOn(&run_accuracycoin_prg_ram_tests.step);
    test_step.dependOn(&run_framebuffer_validator_tests.step);
    test_step.dependOn(&run_commercial_rom_tests.step);
    test_step.dependOn(&run_chr_integration_tests.step);
    test_step.dependOn(&run_sprite_evaluation_tests.step);
    test_step.dependOn(&run_sprite_rendering_tests.step);
    test_step.dependOn(&run_sprite_edge_cases_tests.step);
    test_step.dependOn(&run_vblank_nmi_timing_tests.step);
    test_step.dependOn(&run_ppustatus_polling_tests.step);
    test_step.dependOn(&run_vblank_polling_simple_tests.step);
    test_step.dependOn(&run_seek_behavior_tests.step);
    test_step.dependOn(&run_vblank_persistence_tests.step);
    test_step.dependOn(&run_snapshot_integration_tests.step);
    test_step.dependOn(&run_debugger_integration_tests.step);
    test_step.dependOn(&run_apu_tests.step);
    test_step.dependOn(&run_apu_length_counter_tests.step);
    test_step.dependOn(&run_apu_dmc_tests.step);
    test_step.dependOn(&run_apu_envelope_tests.step);
    test_step.dependOn(&run_apu_linear_counter_tests.step);
    test_step.dependOn(&run_apu_sweep_tests.step);
    test_step.dependOn(&run_apu_frame_irq_tests.step);
    test_step.dependOn(&run_apu_open_bus_tests.step);
    test_step.dependOn(&run_dpcm_dma_tests.step);
    test_step.dependOn(&run_benchmark_tests.step);
    test_step.dependOn(&run_ines_tests.step);
    test_step.dependOn(&run_threading_tests.step);
    test_step.dependOn(&run_button_state_tests.step);
    test_step.dependOn(&run_keyboard_mapper_tests.step);

    // Separate step for just unit tests
    const unit_test_step = b.step("test-unit", "Run unit tests only");
    unit_test_step.dependOn(&run_mod_tests.step);
    unit_test_step.dependOn(&run_apu_tests.step);
    unit_test_step.dependOn(&run_apu_length_counter_tests.step);
    unit_test_step.dependOn(&run_apu_dmc_tests.step);
    unit_test_step.dependOn(&run_apu_envelope_tests.step);
    unit_test_step.dependOn(&run_apu_linear_counter_tests.step);
    unit_test_step.dependOn(&run_apu_sweep_tests.step);
    unit_test_step.dependOn(&run_apu_frame_irq_tests.step);
    unit_test_step.dependOn(&run_apu_open_bus_tests.step);
    unit_test_step.dependOn(&run_ines_tests.step);
    unit_test_step.dependOn(&run_button_state_tests.step);
    unit_test_step.dependOn(&run_keyboard_mapper_tests.step);

    // Separate step for just integration tests
    const integration_test_step = b.step("test-integration", "Run integration tests only");
    integration_test_step.dependOn(&run_cpu_integration_tests.step);
    integration_test_step.dependOn(&run_rmw_tests.step);
    integration_test_step.dependOn(&run_page_crossing_tests.step);
    integration_test_step.dependOn(&run_bus_integration_tests.step);
    integration_test_step.dependOn(&run_interrupt_execution_tests.step);
    integration_test_step.dependOn(&run_nmi_sequence_tests.step);
    integration_test_step.dependOn(&run_cpu_ppu_integration_tests.step);
    integration_test_step.dependOn(&run_oam_dma_tests.step);
    integration_test_step.dependOn(&run_controller_tests.step);
    integration_test_step.dependOn(&run_vblank_wait_tests.step);
    integration_test_step.dependOn(&run_rom_test_runner_tests.step);
    integration_test_step.dependOn(&run_accuracycoin_execution_tests.step);
    integration_test_step.dependOn(&run_cartridge_tests.step);
    integration_test_step.dependOn(&run_prg_ram_tests.step);
    integration_test_step.dependOn(&run_accuracycoin_prg_ram_tests.step);
    integration_test_step.dependOn(&run_framebuffer_validator_tests.step);
    integration_test_step.dependOn(&run_commercial_rom_tests.step);
    integration_test_step.dependOn(&run_chr_integration_tests.step);
    integration_test_step.dependOn(&run_sprite_evaluation_tests.step);
    integration_test_step.dependOn(&run_sprite_rendering_tests.step);
    integration_test_step.dependOn(&run_sprite_edge_cases_tests.step);
    integration_test_step.dependOn(&run_vblank_nmi_timing_tests.step);
    integration_test_step.dependOn(&run_snapshot_integration_tests.step);
    integration_test_step.dependOn(&run_debugger_integration_tests.step);
    integration_test_step.dependOn(&run_dpcm_dma_tests.step);
    integration_test_step.dependOn(&run_benchmark_tests.step);
    integration_test_step.dependOn(&run_threading_tests.step);

    const benchmark_release_step = b.step("bench-release", "Run release-optimized benchmark suite");
    benchmark_release_step.dependOn(&run_benchmark_release_tests.step);

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
