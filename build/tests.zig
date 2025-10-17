const std = @import("std");

pub const Area = enum {
    core,
    cpu,
    cpu_opcode,
    cpu_interrupt,
    cpu_microstep,
    cpu_bus,
    integration,
    ppu,
    ppu_sprite,
    ppu_timing,
    ppu_vblank,
    cartridge,
    rom,
    snapshot,
    emulation,
    debugger,
    apu,
    input,
    threading,
    benchmark,
    helper,
    tooling,
};

pub const Kind = enum {
    zig_test,
    executable,
};

pub const ImportKind = enum {
    xev,
    zli,
    wayland_client,
    build_options,
};

pub const LinkKind = enum {
    wayland_client,
    xkbcommon,
    vulkan,
};

pub const Membership = struct {
    default: bool = true,
    unit: bool = false,
    integration: bool = false,
    bench_release: bool = false,
};

pub const TestSpec = struct {
    name: []const u8,
    area: Area,
    path: []const u8,
    kind: Kind = .zig_test,
    optimize: ?std.builtin.OptimizeMode = null,
    include_rambo: bool = true,
    extra_imports: []const ImportKind = &.{},
    link_libc: bool = false,
    links: []const LinkKind = &.{},
    membership: Membership = .{},
};

pub const ModuleRefs = struct {
    rambo: *std.Build.Module,
    xev: *std.Build.Module,
    zli: *std.Build.Module,
    wayland_client: *std.Build.Module,
    build_options: *std.Build.Module,
};

pub const Config = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    modules: ModuleRefs,
};

pub const Collection = struct {
    all: []const *std.Build.Step,
    unit: []const *std.Build.Step,
    integration: []const *std.Build.Step,
    bench: []const *std.Build.Step,
    bench_release: []const *std.Build.Step,
    tooling: []const *std.Build.Step,
};

pub fn register(b: *std.Build, config: Config) !Collection {
    const allocator = b.allocator;
    var all_steps = std.ArrayListUnmanaged(*std.Build.Step){};
    defer all_steps.deinit(allocator);

    var unit_steps = std.ArrayListUnmanaged(*std.Build.Step){};
    defer unit_steps.deinit(allocator);

    var integration_steps = std.ArrayListUnmanaged(*std.Build.Step){};
    defer integration_steps.deinit(allocator);

    var bench_steps = std.ArrayListUnmanaged(*std.Build.Step){};
    defer bench_steps.deinit(allocator);

    var bench_release_steps = std.ArrayListUnmanaged(*std.Build.Step){};
    defer bench_release_steps.deinit(allocator);

    var tooling_steps = std.ArrayListUnmanaged(*std.Build.Step){};
    defer tooling_steps.deinit(allocator);

    inline for (specs) |spec| {
        const run_step = try instantiateSpec(b, config, &spec);
        if (spec.membership.default) try all_steps.append(allocator, &run_step.step);
        if (spec.membership.unit) try unit_steps.append(allocator, &run_step.step);
        if (spec.membership.integration) try integration_steps.append(allocator, &run_step.step);
        if (spec.membership.bench_release) try bench_release_steps.append(allocator, &run_step.step);
        if (spec.area == .tooling or spec.area == .helper) try tooling_steps.append(allocator, &run_step.step);
        if (spec.area == .benchmark) try bench_steps.append(allocator, &run_step.step);
    }

    return .{
        .all = try all_steps.toOwnedSlice(allocator),
        .unit = try unit_steps.toOwnedSlice(allocator),
        .integration = try integration_steps.toOwnedSlice(allocator),
        .bench = try bench_steps.toOwnedSlice(allocator),
        .bench_release = try bench_release_steps.toOwnedSlice(allocator),
        .tooling = try tooling_steps.toOwnedSlice(allocator),
    };
}

fn instantiateSpec(
    b: *std.Build,
    config: Config,
    spec: *const TestSpec,
) !*std.Build.Step.Run {
    const optimize = spec.optimize orelse config.optimize;

    const imports = try buildImports(b, config.modules, spec);

    const root_module = b.createModule(.{
        .root_source_file = b.path(spec.path),
        .target = config.target,
        .optimize = optimize,
        .link_libc = spec.link_libc,
        .imports = imports,
    });

    const run = switch (spec.kind) {
        .zig_test => blk: {
            const test_compile = b.addTest(.{ .root_module = root_module });
            applyLinks(test_compile, spec.links);
            break :blk b.addRunArtifact(test_compile);
        },
        .executable => blk: {
            const exe = b.addExecutable(.{ .name = spec.name, .root_module = root_module });
            if (spec.link_libc) exe.linkLibC();
            applyLinks(exe, spec.links);
            break :blk b.addRunArtifact(exe);
        },
    };

    return run;
}

fn applyLinks(step: anytype, links: []const LinkKind) void {
    for (links) |link| {
        switch (link) {
            .wayland_client => step.linkSystemLibrary("wayland-client"),
            .xkbcommon => step.linkSystemLibrary("xkbcommon"),
            .vulkan => step.linkSystemLibrary("vulkan"),
        }
    }
}

fn buildImports(
    b: *std.Build,
    modules: ModuleRefs,
    spec: *const TestSpec,
) ![]std.Build.Module.Import {
    const base_len: usize = if (spec.include_rambo) 1 else 0;
    const total = base_len + spec.extra_imports.len;
    if (total == 0) return &.{};

    const imports = try b.allocator.alloc(std.Build.Module.Import, total);
    var index: usize = 0;

    if (spec.include_rambo) {
        imports[index] = .{ .name = "RAMBO", .module = modules.rambo };
        index += 1;
    }

    for (spec.extra_imports) |kind| {
        imports[index] = switch (kind) {
            .xev => .{ .name = "xev", .module = modules.xev },
            .zli => .{ .name = "zli", .module = modules.zli },
            .wayland_client => .{ .name = "wayland_client", .module = modules.wayland_client },
            .build_options => .{ .name = "build_options", .module = modules.build_options },
        };
        index += 1;
    }

    return imports;
}

pub const specs = [_]TestSpec{
    .{
        .name = "module-tests",
        .area = .core,
        .path = "src/root.zig",
        .include_rambo = false,
        .extra_imports = &.{ .build_options, .wayland_client, .xev },
        .membership = .{ .unit = true },
    },
    .{
        .name = "cpu-instruction-tests",
        .area = .cpu,
        .path = "tests/cpu/instructions_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "cpu-opcode-arithmetic",
        .area = .cpu_opcode,
        .path = "tests/cpu/opcodes/arithmetic_test.zig",
    },
    .{
        .name = "cpu-opcode-loadstore",
        .area = .cpu_opcode,
        .path = "tests/cpu/opcodes/loadstore_test.zig",
    },
    .{
        .name = "cpu-opcode-logical",
        .area = .cpu_opcode,
        .path = "tests/cpu/opcodes/logical_test.zig",
    },
    .{
        .name = "cpu-opcode-compare",
        .area = .cpu_opcode,
        .path = "tests/cpu/opcodes/compare_test.zig",
    },
    .{
        .name = "cpu-opcode-transfer",
        .area = .cpu_opcode,
        .path = "tests/cpu/opcodes/transfer_test.zig",
    },
    .{
        .name = "cpu-opcode-incdec",
        .area = .cpu_opcode,
        .path = "tests/cpu/opcodes/incdec_test.zig",
    },
    .{
        .name = "cpu-opcode-stack",
        .area = .cpu_opcode,
        .path = "tests/cpu/opcodes/stack_test.zig",
    },
    .{
        .name = "cpu-opcode-shifts",
        .area = .cpu_opcode,
        .path = "tests/cpu/opcodes/shifts_test.zig",
    },
    .{
        .name = "cpu-opcode-branch",
        .area = .cpu_opcode,
        .path = "tests/cpu/opcodes/branch_test.zig",
    },
    .{
        .name = "cpu-opcode-jumps",
        .area = .cpu_opcode,
        .path = "tests/cpu/opcodes/jumps_test.zig",
    },
    .{
        .name = "cpu-opcode-unofficial",
        .area = .cpu_opcode,
        .path = "tests/cpu/opcodes/unofficial_test.zig",
    },
    .{
        .name = "cpu-control-flow",
        .area = .cpu,
        .path = "tests/cpu/opcodes/control_flow_test.zig",
    },
    .{
        .name = "cpu-rmw",
        .area = .cpu,
        .path = "tests/cpu/rmw_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "cpu-page-crossing",
        .area = .cpu,
        .path = "tests/cpu/page_crossing_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "cpu-microstep-jmp-indirect",
        .area = .cpu_microstep,
        .path = "tests/cpu/microsteps/jmp_indirect_test.zig",
        .extra_imports = &.{.xev},
        .membership = .{ .unit = true },
    },
    .{
        .name = "cpu-interrupt-logic",
        .area = .cpu_interrupt,
        .path = "tests/cpu/interrupt_logic_test.zig",
    },
    .{
        .name = "interrupt-execution",
        .area = .cpu_interrupt,
        .path = "tests/integration/interrupt_execution_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "nmi-sequence",
        .area = .ppu_vblank,
        .path = "tests/integration/nmi_sequence_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "cpu-bus-integration",
        .area = .cpu_bus,
        .path = "tests/cpu/bus_integration_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "cpu-ppu-integration",
        .area = .integration,
        .path = "tests/integration/cpu_ppu_integration_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "oam-dma",
        .area = .ppu,
        .path = "tests/integration/oam_dma_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "controller-integration",
        .area = .input,
        .path = "tests/integration/controller_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "vblank-wait",
        .area = .ppu_vblank,
        .path = "tests/integration/vblank_wait_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "bit-ppustatus",
        .area = .ppu_vblank,
        .path = "tests/integration/bit_ppustatus_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "ppu-register-absolute",
        .area = .ppu,
        .path = "tests/integration/ppu_register_absolute_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "rom-test-runner",
        .area = .rom,
        .path = "tests/integration/rom_test_runner.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "accuracycoin-execution",
        .area = .rom,
        .path = "tests/integration/accuracycoin_execution_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "cartridge-accuracycoin",
        .area = .cartridge,
        .path = "tests/cartridge/accuracycoin_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "cartridge-prg-ram",
        .area = .cartridge,
        .path = "tests/cartridge/prg_ram_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "accuracycoin-prg-ram",
        .area = .rom,
        .path = "tests/integration/accuracycoin_prg_ram_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "framebuffer-validator",
        .area = .helper,
        .path = "tests/helpers/FramebufferValidator.zig",
        .include_rambo = false,
    },
    .{
        .name = "commercial-roms",
        .area = .rom,
        .path = "tests/integration/commercial_rom_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "castlevania",
        .area = .rom,
        .path = "tests/integration/castlevania_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "smb-ram",
        .area = .integration,
        .path = "tests/integration/smb_ram_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "smb-sprite-palette-diagnostic",
        .area = .integration,
        .path = "tests/integration/smb_sprite_palette_diagnostic.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "ppu-register-trace",
        .area = .ppu,
        .path = "tests/integration/ppu_register_trace_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "ppu-chr-integration",
        .area = .ppu,
        .path = "tests/ppu/chr_integration_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "ppu-sprite-evaluation",
        .area = .ppu_sprite,
        .path = "tests/ppu/sprite_evaluation_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "ppu-background-fetch-timing",
        .area = .ppu_timing,
        .path = "tests/ppu/background_fetch_timing_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "ppu-oamaddr-reset",
        .area = .ppu,
        .path = "tests/ppu/oamaddr_reset_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "ppu-sprite0-hit-clipping",
        .area = .ppu_sprite,
        .path = "tests/ppu/sprite0_hit_clipping_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "ppu-ppuctrl-mid-scanline",
        .area = .ppu,
        .path = "tests/ppu/ppuctrl_mid_scanline_test.zig",
        .membership = .{ .unit = true },
    },
    .{
        .name = "ppu-ppumask-delay",
        .area = .ppu,
        .path = "tests/ppu/ppumask_delay_test.zig",
        .membership = .{ .unit = true },
    },
    .{
        .name = "nmi-edge-trigger",
        .area = .ppu_vblank,
        .path = "tests/integration/nmi_edge_trigger_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "ppu-sprite-rendering",
        .area = .ppu_sprite,
        .path = "tests/ppu/sprite_rendering_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "ppu-sprite-edge-cases",
        .area = .ppu_sprite,
        .path = "tests/ppu/sprite_edge_cases_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "ppu-vblank-nmi-timing",
        .area = .ppu_vblank,
        .path = "tests/ppu/vblank_nmi_timing_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "ppustatus-polling",
        .area = .ppu_vblank,
        .path = "tests/ppu/ppustatus_polling_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "ppu-seek-behavior",
        .area = .ppu,
        .path = "tests/ppu/seek_behavior_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "ppu-vblank-behavior",
        .area = .ppu_vblank,
        .path = "tests/ppu/vblank_behavior_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "snapshot-integration",
        .area = .snapshot,
        .path = "tests/snapshot/snapshot_integration_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "emulation-state",
        .area = .emulation,
        .path = "tests/emulation/state_test.zig",
        .extra_imports = &.{.xev},
        .membership = .{ .unit = true },
    },
    .{
        .name = "controller-state",
        .area = .emulation,
        .path = "tests/emulation/state/peripherals/controller_state_test.zig",
        .extra_imports = &.{.xev},
        .membership = .{ .unit = true },
    },
    .{
        .name = "vblank-ledger",
        .area = .ppu_vblank,
        .path = "tests/emulation/state/vblank_ledger_test.zig",
        .extra_imports = &.{.xev},
        .membership = .{ .unit = true },
    },
    .{
        .name = "debugger-isolation",
        .area = .debugger,
        .path = "tests/debugger/isolation_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "debugger-callbacks",
        .area = .debugger,
        .path = "tests/debugger/callbacks_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "debugger-integration",
        .area = .debugger,
        .path = "tests/debugger/integration_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "debugger-breakpoints",
        .area = .debugger,
        .path = "tests/debugger/breakpoints_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "debugger-watchpoints",
        .area = .debugger,
        .path = "tests/debugger/watchpoints_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "debugger-step",
        .area = .debugger,
        .path = "tests/debugger/step_execution_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "debugger-state",
        .area = .debugger,
        .path = "tests/debugger/state_manipulation_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "apu-core",
        .area = .apu,
        .path = "tests/apu/apu_test.zig",
        .membership = .{ .unit = true },
    },
    .{
        .name = "apu-length-counter",
        .area = .apu,
        .path = "tests/apu/length_counter_test.zig",
        .membership = .{ .unit = true },
    },
    .{
        .name = "apu-dmc",
        .area = .apu,
        .path = "tests/apu/dmc_test.zig",
        .membership = .{ .unit = true },
    },
    .{
        .name = "apu-envelope",
        .area = .apu,
        .path = "tests/apu/envelope_test.zig",
        .membership = .{ .unit = true },
    },
    .{
        .name = "apu-linear-counter",
        .area = .apu,
        .path = "tests/apu/linear_counter_test.zig",
        .membership = .{ .unit = true },
    },
    .{
        .name = "apu-sweep",
        .area = .apu,
        .path = "tests/apu/sweep_test.zig",
        .membership = .{ .unit = true },
    },
    .{
        .name = "apu-frame-irq",
        .area = .apu,
        .path = "tests/apu/frame_irq_edge_test.zig",
        .membership = .{ .unit = true },
    },
    .{
        .name = "apu-open-bus",
        .area = .apu,
        .path = "tests/apu/open_bus_test.zig",
        .membership = .{ .unit = true },
    },
    .{
        .name = "dpcm-dma",
        .area = .apu,
        .path = "tests/integration/dpcm_dma_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "dmc-oam-conflict",
        .area = .integration,
        .path = "tests/integration/dmc_oam_conflict_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "benchmark",
        .area = .benchmark,
        .path = "tests/integration/benchmark_test.zig",
        .membership = .{ .integration = true },
    },
    .{
        .name = "benchmark-release",
        .area = .benchmark,
        .path = "tests/integration/benchmark_test.zig",
        .optimize = std.builtin.OptimizeMode.ReleaseFast,
        .membership = .{ .default = false, .bench_release = true },
    },
    .{
        .name = "threading",
        .area = .threading,
        .path = "tests/threads/threading_test.zig",
        .link_libc = true,
        .extra_imports = &.{ .xev, .build_options, .wayland_client },
        .links = &.{ .wayland_client, .xkbcommon, .vulkan },
        .membership = .{ .integration = true },
    },
    .{
        .name = "button-state",
        .area = .input,
        .path = "tests/input/button_state_test.zig",
        .membership = .{ .unit = true },
    },
    .{
        .name = "keyboard-mapper",
        .area = .input,
        .path = "tests/input/keyboard_mapper_test.zig",
        .membership = .{ .unit = true },
    },
    .{
        .name = "keyboard-controller-mailbox",
        .area = .input,
        .path = "tests/input/controller_mailbox_keyboard_test.zig",
        .membership = .{ .unit = true },
    },
    .{
        .name = "ppumask-warmup",
        .area = .ppu_vblank,
        .path = "tests/unit/ppumask_warmup_test.zig",
        .membership = .{ .unit = true },
    },
    .{
        .name = "smb-ram-runner",
        .area = .tooling,
        .path = "scripts/test_smb_ram.zig",
        .kind = .executable,
        .link_libc = true,
        .membership = .{ .integration = true },
    },
};
