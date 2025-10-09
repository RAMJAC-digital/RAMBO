//! Bomberman Hang Investigation
//!
//! Systematically traces execution to find the exact point where Bomberman hangs.
//! Uses debugger breakpoints and PC tracking to identify infinite loops.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Debugger = RAMBO.Debugger.Debugger;
const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;
const NromCart = RAMBO.CartridgeType;
const AnyCartridge = RAMBO.AnyCartridge;

test "Bomberman: Find exact hang location with PC tracking" {
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

    const reset_vector = state.busRead16(0xFFFC);
    const nmi_vector = state.busRead16(0xFFFA);

    // Track PC history to detect loops
    var pc_history: [1000]u16 = undefined;
    var pc_count: usize = 0;

    var last_pc: u16 = state.cpu.pc;
    var instruction_count: usize = 0;
    var same_pc_count: usize = 0;
    var loop_detected_at: ?u16 = null;

    // Run until we detect a tight loop
    const max_ticks: usize = 100000;
    var ticks: usize = 0;

    while (ticks < max_ticks and loop_detected_at == null) {
        const before_pc = state.cpu.pc;
        state.tick();
        ticks += 1;

        // Detect instruction completion
        if (state.cpu.state == .fetch_opcode and state.cpu.pc != before_pc) {
            instruction_count += 1;

            // Track PC
            if (pc_count < 1000) {
                pc_history[pc_count] = state.cpu.pc;
                pc_count += 1;
            }

            // Detect tight loop (same PC executing repeatedly)
            if (state.cpu.pc == last_pc) {
                same_pc_count += 1;
                if (same_pc_count > 10) {
                    // Found infinite loop!
                    loop_detected_at = state.cpu.pc;
                }
            } else {
                same_pc_count = 0;
            }

            last_pc = state.cpu.pc;
        }
    }

    // Did we find the hang point?
    if (loop_detected_at) |hang_pc| {
        // Read the opcode at the hang location
        const hang_opcode = state.busRead(hang_pc);

        // Get CPU state at hang
        const a_reg = state.cpu.a;
        const x_reg = state.cpu.x;
        const y_reg = state.cpu.y;
        const sp_reg = state.cpu.sp;
        const p_reg = state.cpu.p.toByte();

        // Force test to fail with diagnostic info visible in error output
        // These assertions will fail and reveal the actual values
        try testing.expectEqual(@as(u16, 0xFFFF), hang_pc); // Will show actual hang PC
        try testing.expectEqual(@as(u8, 0xFF), hang_opcode); // Will show actual opcode
        try testing.expectEqual(@as(u8, 0xFF), a_reg); // Will show A register
        try testing.expectEqual(@as(u8, 0xFF), x_reg); // Will show X register
        try testing.expectEqual(@as(u8, 0xFF), y_reg); // Will show Y register
        try testing.expectEqual(@as(u8, 0xFF), sp_reg); // Will show SP
        try testing.expectEqual(@as(u8, 0xFF), p_reg); // Will show status flags
        try testing.expectEqual(@as(u16, 0xFFFF), reset_vector);
        try testing.expectEqual(@as(u16, 0xFFFF), nmi_vector);
        try testing.expectEqual(@as(usize, 0), instruction_count); // Show how many instructions ran
    } else {
        // Didn't find obvious infinite loop
        // Maybe it's a longer loop or waiting pattern
        return error.SkipZigTest;
    }
}

test "Bomberman: Detect what instruction causes hang" {
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

    // Track last 100 PCs to find loop patterns
    var recent_pcs: [100]u16 = undefined;
    var pc_index: usize = 0;
    var instruction_count: usize = 0;

    const max_instructions: usize = 10000;

    while (instruction_count < max_instructions) {
        const before_pc = state.cpu.pc;
        const before_state = state.cpu.state;

        state.tick();

        // Instruction completed
        if (state.cpu.state == .fetch_opcode and before_state != .fetch_opcode) {
            recent_pcs[pc_index] = before_pc;
            pc_index = (pc_index + 1) % 100;
            instruction_count += 1;

            // Check for repeating patterns every 1000 instructions
            if (instruction_count % 1000 == 0) {
                // Look for patterns in recent PCs
                // If we see the same 2-3 PC sequence repeating, it's a loop
                const check_len = @min(pc_index, 20);
                if (check_len >= 4) {
                    const idx = if (pc_index >= check_len) pc_index - check_len else 100 - (check_len - pc_index);
                    const pc1 = recent_pcs[idx % 100];
                    const pc2 = recent_pcs[(idx + 1) % 100];

                    // Check if this pattern repeats
                    var pattern_count: usize = 0;
                    var i: usize = 0;
                    while (i + 1 < check_len) : (i += 2) {
                        const check_idx = (idx + i) % 100;
                        if (recent_pcs[check_idx] == pc1 and recent_pcs[(check_idx + 1) % 100] == pc2) {
                            pattern_count += 1;
                        }
                    }

                    if (pattern_count >= 3) {
                        // Found repeating 2-instruction loop - fail test to show the PCs
                        try testing.expectEqual(@as(u16, 0xFFFF), pc1); // Will show first PC in loop
                        try testing.expectEqual(@as(u16, 0xFFFF), pc2); // Will show second PC in loop
                        try testing.expectEqual(@as(usize, 0), instruction_count); // Show how many instructions
                        return;
                    }
                }
            }
        }
    }

    // Completed 10000 instructions without obvious loop
    // Bomberman might actually be running normally
    try testing.expect(instruction_count >= 10000);
}

test "Bomberman: Check for specific wait patterns" {
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

    // Common wait patterns in NES games:
    // 1. Loop waiting for VBlank ($2002 bit 7)
    // 2. Loop waiting for controller ($4016 reads)
    // 3. Loop waiting for APU ($4015 reads)

    var ppustatus_reads: usize = 0;
    var controller_reads: usize = 0;
    var apu_reads: usize = 0;
    var last_read_addr: u16 = 0;
    var consecutive_same_reads: usize = 0;

    var instruction_count: usize = 0;
    const max_instructions: usize = 5000;

    while (instruction_count < max_instructions) {
        const before_state = state.cpu.state;

        // Track memory reads during execute state
        if (state.cpu.state == .execute or state.cpu.state == .fetch_operand_low) {
            const addr = state.cpu.effective_address;
            if (addr == 0x2002) ppustatus_reads += 1;
            if (addr == 0x4016 or addr == 0x4017) controller_reads += 1;
            if (addr == 0x4015) apu_reads += 1;

            if (addr == last_read_addr) {
                consecutive_same_reads += 1;
                if (consecutive_same_reads > 100) {
                    // Stuck reading same address repeatedly - reveal it!
                    try testing.expectEqual(@as(u16, 0xFFFF), addr); // Will show stuck address
                    try testing.expectEqual(@as(usize, 0), ppustatus_reads);
                    try testing.expectEqual(@as(usize, 0), controller_reads);
                    try testing.expectEqual(@as(usize, 0), apu_reads);
                    try testing.expectEqual(@as(usize, 0), instruction_count);
                    return;
                }
            } else {
                consecutive_same_reads = 0;
                last_read_addr = addr;
            }
        }

        state.tick();

        if (state.cpu.state == .fetch_opcode and before_state != .fetch_opcode) {
            instruction_count += 1;
        }
    }

    // Check what Bomberman was trying to read
    const waiting_on_vblank = ppustatus_reads > 100;
    const waiting_on_controller = controller_reads > 100;
    const waiting_on_apu = apu_reads > 100;

    _ = waiting_on_vblank;
    _ = waiting_on_controller;
    _ = waiting_on_apu;

    // Exploratory test
}
