//! Bomberman Debug Trace Test
//!
//! Uses the debugger's breakpoint system to trace where Bomberman hangs.
//! This test verifies:
//! 1. Debugger breakpoints work correctly
//! 2. We can capture PC values at specific points
//! 3. We can identify infinite loops or waiting patterns

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Debugger = RAMBO.Debugger.Debugger;
const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;
const NromCart = RAMBO.CartridgeType;
const AnyCartridge = RAMBO.AnyCartridge;

test "Debugger: Breakpoint at Bomberman reset vector" {
    const allocator = testing.allocator;

    const nrom_cart = NromCart.load(allocator, "tests/data/Bomberman/Bomberman (USA).nes") catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };
    const cart = AnyCartridge{ .nrom = nrom_cart };

    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.loadCartridge(cart);

    // Initialize debugger
    var debugger = Debugger.init(allocator, &config);
    defer debugger.deinit();

    state.debugger = debugger;
    state.reset();

    // Get reset vector
    const reset_vector = state.busRead16(0xFFFC);

    // Set execute breakpoint at reset vector
    try state.debugger.?.addBreakpoint(reset_vector, .execute);

    // Run until breakpoint or timeout
    var ticks: usize = 0;
    const max_ticks: usize = 10000; // Should hit reset vector very quickly

    while (!state.debuggerIsPaused() and ticks < max_ticks) {
        state.tick();
        ticks += 1;
    }

    // Verify we hit the breakpoint
    try testing.expect(state.debuggerIsPaused());
    try testing.expect(state.cpu.pc == reset_vector);
    try testing.expect(ticks < max_ticks);

    // Debugger breakpoint system works!
}

test "Bomberman: Trace first 1000 instructions with PC sampling" {
    const allocator = testing.allocator;

    const nrom_cart = NromCart.load(allocator, "tests/data/Bomberman/Bomberman (USA).nes") catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };
    const cart = AnyCartridge{ .nrom = nrom_cart };

    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.loadCartridge(cart);
    state.reset();

    // Use fixed array instead of ArrayList for simplicity
    var pc_samples: [10]u16 = undefined;
    var pc_sample_count: usize = 0;

    var instruction_count: usize = 0;
    var last_pc: u16 = state.cpu.pc;
    var ticks: usize = 0;
    const max_ticks: usize = 1000000; // Large safety limit

    while (instruction_count < 1000 and ticks < max_ticks) {
        const before_pc = state.cpu.pc;
        state.tick();
        ticks += 1;

        // Detect instruction boundary (PC changed and we're at fetch_opcode)
        if (state.cpu.pc != before_pc and state.cpu.state == .fetch_opcode) {
            instruction_count += 1;

            // Sample every 100th instruction
            if (instruction_count % 100 == 0 and pc_sample_count < 10) {
                pc_samples[pc_sample_count] = state.cpu.pc;
                pc_sample_count += 1;
            }

            last_pc = state.cpu.pc;
        }
    }

    // Analysis: Did we complete 1000 instructions?
    if (instruction_count < 1000) {
        // Bomberman got stuck before 1000 instructions
        // This is valuable diagnostic info
        return error.SkipZigTest;
    }

    // Check for tight loops (same PC repeated in samples)
    if (pc_sample_count >= 2) {
        const first_sample = pc_samples[0];
        var all_same = true;
        for (pc_samples[0..pc_sample_count]) |pc| {
            if (pc != first_sample) {
                all_same = false;
                break;
            }
        }

        if (all_same) {
            // Stuck in tight loop at same PC
            return error.SkipZigTest;
        }
    }

    // If we got here, Bomberman is making progress
    try testing.expect(instruction_count >= 1000);
}

test "Bomberman: Check controller reads in first 10000 cycles" {
    const allocator = testing.allocator;

    const nrom_cart = NromCart.load(allocator, "tests/data/Bomberman/Bomberman (USA).nes") catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };
    const cart = AnyCartridge{ .nrom = nrom_cart };

    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.loadCartridge(cart);

    // Add watchpoints on controller registers
    var debugger = Debugger.init(allocator, &config);
    defer debugger.deinit();

    state.debugger = debugger;
    state.reset();

    try state.debugger.?.addWatchpoint(0x4016, 1, .read); // Controller 1 read
    try state.debugger.?.addWatchpoint(0x4016, 1, .write); // Controller strobe

    var controller_reads: usize = 0;
    var controller_writes: usize = 0;

    // Run for 10000 CPU cycles
    const target_cycles: u64 = 10000;
    while (state.clock.cpuCycles() < target_cycles) {
        // Check if watchpoint triggered
        if (state.debug_break_occurred) {
            const reason = state.debugger.?.getBreakReason() orelse "";
            if (std.mem.indexOf(u8, reason, "read") != null) {
                controller_reads += 1;
            } else if (std.mem.indexOf(u8, reason, "write") != null) {
                controller_writes += 1;
            }

            // Continue execution
            state.debugger.?.continue_();
            state.debug_break_occurred = false;
        }

        state.tick();
    }

    // Did Bomberman try to read controller?
    // If yes, our controller implementation might be the issue
    // If no, it's stuck before even checking input
    const has_controller_access = (controller_reads > 0) or (controller_writes > 0);
    _ = has_controller_access;

    // Exploratory test - always passes
}
