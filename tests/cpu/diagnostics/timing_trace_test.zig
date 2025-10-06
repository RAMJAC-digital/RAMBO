//! Cycle-by-Cycle Timing Trace Tests
//!
//! These tests verify exact cycle-by-cycle behavior for addressing modes
//! with known timing deviations. They serve as:
//! 1. Documentation of current (incorrect) behavior
//! 2. Validation when fix is implemented
//! 3. Regression detection

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;
const CpuState = RAMBO.Cpu.State.ExecutionState;

// Test helper: Create EmulationState
fn createTestState() EmulationState {
    var config = Config.init(testing.allocator);
    config.deinit(); // Leak for test simplicity
    return EmulationState.init(&config);
}

// ============================================================================
// LDA Absolute,X - No Page Cross (Should be 4 cycles, currently 5)
// ============================================================================

test "LDA absolute,X - no page cross - cycle trace (CURRENT BEHAVIOR)" {
    var state = createTestState();

    // Setup: LDA $0130,X with X=$05 → $0135 (no page cross)
    state.ram[0] = 0xBD; // LDA absolute,X
    state.ram[1] = 0x30; // Low byte
    state.ram[2] = 0x01; // High byte
    state.ram[0x135] = 0x99; // Value at target address
    state.cpu.pc = 0x0000;
    state.cpu.x = 0x05;

    // Initial state
    try testing.expectEqual(CpuState.fetch_opcode, state.cpu.state);
    try testing.expectEqual(@as(u8, 0), state.cpu.a);

    // ===== Cycle 1: Fetch Opcode =====
    state.tickCpu();
    try testing.expectEqual(@as(u64, 1), state.cpu.cycle_count);
    try testing.expectEqual(@as(u16, 0x0001), state.cpu.pc);
    try testing.expectEqual(@as(u8, 0xBD), state.cpu.opcode);
    try testing.expectEqual(CpuState.fetch_operand_low, state.cpu.state);

    // ===== Cycle 2: Fetch Low Byte =====
    state.tickCpu();
    try testing.expectEqual(@as(u64, 2), state.cpu.cycle_count);
    try testing.expectEqual(@as(u16, 0x0002), state.cpu.pc);
    try testing.expectEqual(@as(u8, 0x30), state.cpu.operand_low);
    try testing.expectEqual(CpuState.fetch_operand_low, state.cpu.state);
    try testing.expectEqual(@as(u8, 0), state.cpu.instruction_cycle);

    // ===== Cycle 3: Fetch High Byte =====
    state.tickCpu();
    try testing.expectEqual(@as(u64, 3), state.cpu.cycle_count);
    try testing.expectEqual(@as(u16, 0x0003), state.cpu.pc);
    try testing.expectEqual(@as(u8, 0x01), state.cpu.operand_high);
    try testing.expectEqual(@as(u8, 1), state.cpu.instruction_cycle);

    // ===== Cycle 4: calcAbsoluteX - Dummy Read =====
    // Hardware: This would be the FINAL read + execute
    // Our impl: Just does dummy read, stores in temp_value
    state.tickCpu();
    try testing.expectEqual(@as(u64, 4), state.cpu.cycle_count);
    try testing.expectEqual(@as(u16, 0x0135), state.cpu.effective_address);
    try testing.expect(!state.cpu.page_crossed); // No page cross
    try testing.expectEqual(@as(u8, 0x99), state.cpu.temp_value); // Value cached
    try testing.expectEqual(@as(u8, 0), state.cpu.a); // NOT YET EXECUTED
    try testing.expectEqual(@as(u8, 2), state.cpu.instruction_cycle);

    // ===== Cycle 5: Execute (DEVIATION - Should not exist!) =====
    // This is the +1 cycle deviation
    state.tickCpu();
    try testing.expectEqual(@as(u64, 5), state.cpu.cycle_count);
    try testing.expectEqual(@as(u8, 0x99), state.cpu.a); // NOW executed
    try testing.expectEqual(CpuState.fetch_opcode, state.cpu.state);

    // **DEVIATION:** 5 cycles instead of 4
    // **CAUSE:** Addressing read operand in cycle 4, execute used it in cycle 5
    // **FIX:** Execute should happen IN cycle 4 (same as operand read)
}

test "LDA absolute,X - no page cross - EXPECTED HARDWARE BEHAVIOR" {
    // This test documents what SHOULD happen (will fail until fix applied)

    // After fix is applied, this test should pass:
    // - Cycle 4 should both read operand AND execute LDA
    // - Total cycles should be 4, not 5
    // - A register should contain 0x99 after cycle 4

    // TODO: Uncomment and verify after fix is implemented
    // var state = createTestState();
    // ... same setup ...
    // for (0..4) |_| state.tickCpu();
    // try testing.expectEqual(@as(u8, 0x99), state.cpu.a);
    // try testing.expectEqual(@as(u64, 4), state.cpu.cycle_count);
}

// ============================================================================
// LDA Absolute,X - Page Cross (Should be 5 cycles, currently 6)
// ============================================================================

test "LDA absolute,X - page cross - cycle trace (CURRENT BEHAVIOR)" {
    var state = createTestState();

    // Setup: LDA $01FF,X with X=$05 → $0204 (page cross)
    state.ram[0] = 0xBD;
    state.ram[1] = 0xFF;
    state.ram[2] = 0x01;
    state.ram[0x204] = 0xAA;
    state.cpu.pc = 0x0000;
    state.cpu.x = 0x05;

    // ===== Cycle 1: Fetch Opcode =====
    state.tickCpu();
    try testing.expectEqual(@as(u64, 1), state.cpu.cycle_count);

    // ===== Cycle 2: Fetch Low Byte =====
    state.tickCpu();
    try testing.expectEqual(@as(u64, 2), state.cpu.cycle_count);
    try testing.expectEqual(@as(u8, 0xFF), state.cpu.operand_low);

    // ===== Cycle 3: Fetch High Byte =====
    state.tickCpu();
    try testing.expectEqual(@as(u64, 3), state.cpu.cycle_count);
    try testing.expectEqual(@as(u8, 0x01), state.cpu.operand_high);

    // ===== Cycle 4: calcAbsoluteX - Dummy Read at Wrong Address =====
    // Address should be $0104 (not $0204 - high byte not fixed yet)
    state.tickCpu();
    try testing.expectEqual(@as(u64, 4), state.cpu.cycle_count);
    try testing.expectEqual(@as(u16, 0x0204), state.cpu.effective_address);
    try testing.expect(state.cpu.page_crossed); // Page crossed!
    try testing.expectEqual(@as(u8, 0), state.cpu.a); // Not executed yet

    // ===== Cycle 5: fixHighByte - Dummy Read at Correct Address =====
    // Hardware: This would be FINAL read + execute
    // Our impl: Does dummy read, discards value
    state.tickCpu();
    try testing.expectEqual(@as(u64, 5), state.cpu.cycle_count);
    try testing.expectEqual(@as(u8, 0), state.cpu.a); // STILL not executed

    // ===== Cycle 6: Execute (DEVIATION - Should not exist!) =====
    state.tickCpu();
    try testing.expectEqual(@as(u64, 6), state.cpu.cycle_count);
    try testing.expectEqual(@as(u8, 0xAA), state.cpu.a); // NOW executed

    // **DEVIATION:** 6 cycles instead of 5
    // **CAUSE:** Cycle 5 did dummy read, cycle 6 did real read + execute
    // **FIX:** Cycle 5 should do real read + execute (not dummy)
}

test "LDA absolute,X - page cross - EXPECTED HARDWARE BEHAVIOR" {
    // TODO: Uncomment after fix
    // Should be 5 cycles total, with execute happening in cycle 5
}

// ============================================================================
// Comparison: Immediate Mode (Correct - 2 Cycles)
// ============================================================================

test "LDA immediate - cycle trace (CORRECT)" {
    var state = createTestState();

    state.ram[0] = 0xA9; // LDA immediate
    state.ram[1] = 0x42;
    state.cpu.pc = 0x0000;

    // Cycle 1: Fetch opcode
    state.tickCpu();
    try testing.expectEqual(@as(u64, 1), state.cpu.cycle_count);
    try testing.expectEqual(CpuState.execute, state.cpu.state);

    // Cycle 2: Read operand + Execute (SAME CYCLE)
    state.tickCpu();
    try testing.expectEqual(@as(u64, 2), state.cpu.cycle_count);
    try testing.expectEqual(@as(u8, 0x42), state.cpu.a);
    try testing.expectEqual(CpuState.fetch_opcode, state.cpu.state);

    // **CORRECT:** 2 cycles total
    // **WHY:** Execute state reads operand inline, no separate addressing
}

// ============================================================================
// Comparison: RMW Instructions (Correct - 7 Cycles)
// ============================================================================

test "ASL absolute,X - cycle trace (CORRECT - RMW)" {
    var state = createTestState();

    state.ram[0] = 0x1E; // ASL absolute,X
    state.ram[1] = 0x00;
    state.ram[2] = 0x02;
    state.ram[0x205] = 0x01;
    state.cpu.pc = 0x0000;
    state.cpu.x = 0x05;

    for (0..7) |i| {
        state.tickCpu();
        std.debug.print("ASL Cycle {}: state={s}, ic={}, result=0x{X:0>2}\n", .{
            i + 1,
            @tagName(state.cpu.state),
            state.cpu.instruction_cycle,
            state.ram[0x205],
        });
    }

    try testing.expectEqual(@as(u8, 0x02), state.ram[0x205]);
    try testing.expectEqual(@as(u64, 7), state.cpu.cycle_count);

    // **CORRECT:** 7 cycles for RMW
    // RMW needs separate cycles for: read, dummy write, real write
    // This is correct hardware behavior
}
