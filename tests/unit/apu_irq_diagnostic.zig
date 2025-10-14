//! APU IRQ Diagnostic Test
//!
//! Verifies that APU frame counter IRQs behave correctly:
//! - IRQs disabled by default (irq_inhibit = true)
//! - IRQs only fire when explicitly enabled via $4017
//! - Frame counter timing is correct

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;

test "APU: IRQ inhibit is TRUE at power-on" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.power_on();

    // APU should have IRQ inhibit enabled by default
    try testing.expect(state.apu.irq_inhibit);
    try testing.expect(!state.apu.frame_irq_flag);
    try testing.expect(!state.apu.dmc_irq_flag);
    try testing.expect(!state.cpu.irq_line);
}

test "APU: Frame counter IRQ does NOT fire with inhibit enabled (default)" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.power_on();

    // Emulate for 30,000 CPU cycles (past first IRQ point at 29,829)
    const cpu_cycles = 30_000;
    _ = state.emulateCpuCycles(cpu_cycles);

    // IRQ flag should NOT be set because irq_inhibit is TRUE by default
    try testing.expect(!state.apu.frame_irq_flag);
    try testing.expect(!state.cpu.irq_line);
}

test "APU: Frame counter IRQ DOES fire when inhibit disabled" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.power_on();

    // Write to $4017 to disable IRQ inhibit (4-step mode, IRQ enabled)
    // Bit 7 = 0 (4-step mode)
    // Bit 6 = 0 (IRQ NOT inhibited)
    state.busWrite(0x4017, 0x00);

    std.debug.print("\n[TEST] After $4017 write:\n", .{});
    std.debug.print("  irq_inhibit: {}\n", .{state.apu.irq_inhibit});
    std.debug.print("  frame_counter_mode: {}\n", .{state.apu.frame_counter_mode});

    try testing.expect(!state.apu.irq_inhibit); // Should be FALSE now
    try testing.expect(!state.apu.frame_counter_mode); // Should be 4-step mode

    // Emulate past first IRQ point (29,829 CPU cycles)
    const cpu_cycles = 30_000;
    _ = state.emulateCpuCycles(cpu_cycles);

    std.debug.print("\n[TEST] After {d} CPU cycles:\n", .{cpu_cycles});
    std.debug.print("  frame_irq_flag: {}\n", .{state.apu.frame_irq_flag});
    std.debug.print("  frame_counter_cycles: {}\n", .{state.apu.frame_counter_cycles});

    // IRQ flag SHOULD be set now because inhibit was disabled
    try testing.expect(state.apu.frame_irq_flag);
}

test "APU: 5-step mode never generates IRQs" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.power_on();

    // Write to $4017 to enable 5-step mode
    // Bit 7 = 1 (5-step mode)
    // Bit 6 = 0 (IRQ not inhibited, but shouldn't matter in 5-step mode)
    state.busWrite(0x4017, 0x80);

    try testing.expect(state.apu.frame_counter_mode); // Should be 5-step mode

    // Emulate for full 5-step frame (37,281 cycles) and beyond
    const cpu_cycles = 40_000;
    _ = state.emulateCpuCycles(cpu_cycles);

    // IRQ flag should NEVER be set in 5-step mode, even if inhibit is disabled
    try testing.expect(!state.apu.frame_irq_flag);
}

test "APU: DMC IRQ disabled by default" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.power_on();

    // DMC IRQ should be disabled at power-on
    try testing.expect(!state.apu.dmc_irq_flag);
    try testing.expect(!state.apu.dmc_irq_enabled);
    try testing.expect(!state.apu.dmc_enabled);
}

test "APU: Diagnose commercial ROM initialization" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    // Simulate what a ROM might do during initialization
    state.power_on();

    std.debug.print("\n[DIAG] Initial APU state after power_on():\n", .{});
    std.debug.print("  irq_inhibit: {}\n", .{state.apu.irq_inhibit});
    std.debug.print("  frame_counter_mode: {}\n", .{state.apu.frame_counter_mode});
    std.debug.print("  frame_irq_flag: {}\n", .{state.apu.frame_irq_flag});
    std.debug.print("  dmc_irq_flag: {}\n", .{state.apu.dmc_irq_flag});
    std.debug.print("  cpu.irq_line: {}\n", .{state.cpu.irq_line});

    // Most commercial ROMs write to $4017 during init to set up frame counter
    // Let's simulate what Super Mario Bros might do:

    // Hypothesis 1: ROM writes $00 to $4017 (clears IRQ inhibit!)
    std.debug.print("\n[DIAG] Simulating ROM write: $4017 = $00\n", .{});
    state.busWrite(0x4017, 0x00);

    std.debug.print("  irq_inhibit after write: {}\n", .{state.apu.irq_inhibit});

    if (!state.apu.irq_inhibit) {
        std.debug.print("  WARNING: IRQ inhibit is now FALSE - IRQs will fire!\n", .{});
    }

    // Run for 4 frames worth of cycles (approximately)
    const cycles_per_frame = 29_830; // 4-step mode
    const total_cycles = cycles_per_frame * 4;

    var irq_count: usize = 0;
    var last_pc = state.cpu.pc;

    // Track if we see IRQ interrupt sequence
    const start_cycle = state.clock.cpuCycles();
    _ = state.emulateCpuCycles(total_cycles);
    const end_cycle = state.clock.cpuCycles();

    std.debug.print("\n[DIAG] After {d} CPU cycles ({d} → {d}):\n", .{ total_cycles, start_cycle, end_cycle });
    std.debug.print("  frame_counter_cycles: {}\n", .{state.apu.frame_counter_cycles});
    std.debug.print("  frame_irq_flag: {}\n", .{state.apu.frame_irq_flag});
    std.debug.print("  cpu.irq_line: {}\n", .{state.cpu.irq_line});
    std.debug.print("  cpu.pending_interrupt: {}\n", .{state.cpu.pending_interrupt});
    std.debug.print("  cpu.pc: ${X:0>4}\n", .{state.cpu.pc});

    if (state.apu.frame_irq_flag) {
        std.debug.print("\n  ⚠️  Frame IRQ flag is SET - ROM would attempt to service IRQ!\n", .{});
    }

    // This test always passes - it's for diagnostics only
    try testing.expect(true);
}
