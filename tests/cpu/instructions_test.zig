const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Cpu = RAMBO.Cpu;
const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;

// Test helper: Create EmulationState for CPU instruction testing
fn createTestState() EmulationState {
    var config = Config.init(testing.allocator);
    config.deinit(); // We'll leak this for test simplicity - tests are short-lived

    const state = EmulationState.init(&config);
    return state;
}

// Helper: Allocate test RAM for tests that need ROM space access
fn allocTestRam(state: *EmulationState) []u8 {
    const test_ram = testing.allocator.alloc(u8, 0x8000) catch unreachable;
    @memset(test_ram, 0);
    state.bus.test_ram = test_ram;
    return test_ram;
}

// ============================================================================
// NOP Instruction Tests
// ============================================================================

test "NOP implied - 2 cycles" {
    var state = createTestState();

    // Setup: NOP at $8000
    state.bus.ram[0] = 0xEA; // NOP opcode
    state.cpu.pc = 0x0000;

    const initial_a = state.cpu.a;
    const initial_x = state.cpu.x;
    const initial_y = state.cpu.y;
    const initial_p = state.cpu.p;

    // Cycle 1: Fetch opcode
    state.tickCpu();
    try testing.expectEqual(@as(u16, 0x0001), state.cpu.pc);
    try testing.expectEqual(@as(u64, 1), state.cpu.cycle_count);

    // Cycle 2: Execute NOP (does nothing)
    state.tickCpu();
    try testing.expectEqual(@as(u64, 2), state.cpu.cycle_count);

    // Verify no registers changed
    try testing.expectEqual(initial_a, state.cpu.a);
    try testing.expectEqual(initial_x, state.cpu.x);
    try testing.expectEqual(initial_y, state.cpu.y);
    try testing.expectEqual(initial_p.toByte(), state.cpu.p.toByte());
}

test "NOP immediate (unofficial) - 2 cycles" {
    var state = createTestState();

    // Setup: NOP #$42 at $8000
    state.bus.ram[0] = 0x80; // Unofficial NOP immediate
    state.bus.ram[1] = 0x42; // Operand (ignored)
    state.cpu.pc = 0x0000;

    // Cycle 1: Fetch opcode
    state.tickCpu();

    // Cycle 2: Execute (fetch operand and discard)
    state.tickCpu();

    try testing.expectEqual(@as(u16, 0x0002), state.cpu.pc); // PC advanced past operand
    try testing.expectEqual(@as(u64, 2), state.cpu.cycle_count);
}

// ============================================================================
// LDA Instruction Tests
// ============================================================================

test "LDA immediate - 2 cycles" {
    var state = createTestState();

    // Setup: LDA #$42
    state.bus.ram[0] = 0xA9; // LDA immediate
    state.bus.ram[1] = 0x42; // Operand
    state.cpu.pc = 0x0000;

    // Cycle 1: Fetch opcode
    state.tickCpu();

    // Cycle 2: Execute (fetch operand and load)
    state.tickCpu();

    try testing.expectEqual(@as(u8, 0x42), state.cpu.a);
    try testing.expect(!state.cpu.p.zero);
    try testing.expect(!state.cpu.p.negative);
}

test "LDA immediate - zero flag" {
    var state = createTestState();

    // Setup: LDA #$00
    state.bus.ram[0] = 0xA9;
    state.bus.ram[1] = 0x00;
    state.cpu.pc = 0x0000;

    // Execute instruction (2 cycles)
    _ = state.tickCpu(); // Fetch
    state.tickCpu(); // Execute
    try testing.expectEqual(@as(u8, 0x00), state.cpu.a);
    try testing.expect(state.cpu.p.zero);
    try testing.expect(!state.cpu.p.negative);
}

test "LDA immediate - negative flag" {
    var state = createTestState();

    // Setup: LDA #$80
    state.bus.ram[0] = 0xA9;
    state.bus.ram[1] = 0x80;
    state.cpu.pc = 0x0000;

    // Execute instruction (2 cycles)
    _ = state.tickCpu();
    state.tickCpu();
    try testing.expectEqual(@as(u8, 0x80), state.cpu.a);
    try testing.expect(!state.cpu.p.zero);
    try testing.expect(state.cpu.p.negative);
}

test "LDA zero page - 3 cycles" {
    var state = createTestState();

    // Setup: LDA $10
    state.bus.ram[0] = 0xA5; // LDA zero page
    state.bus.ram[1] = 0x10; // ZP address
    state.bus.ram[0x10] = 0x55; // Value at $0010
    state.cpu.pc = 0x0000;

    // Cycle 1: Fetch opcode
    state.tickCpu();
    try testing.expectEqual(@as(u64, 1), state.cpu.cycle_count);

    // Cycle 2: Fetch ZP address
    state.tickCpu();
    try testing.expectEqual(@as(u64, 2), state.cpu.cycle_count);

    // Cycle 3: Execute (read from ZP)
    state.tickCpu();
    try testing.expectEqual(@as(u64, 3), state.cpu.cycle_count);
    try testing.expectEqual(@as(u8, 0x55), state.cpu.a);
}

test "LDA zero page,X - 4 cycles" {
    var state = createTestState();

    // Setup: LDA $10,X with X=$05
    state.bus.ram[0] = 0xB5; // LDA zero page,X
    state.bus.ram[1] = 0x10; // Base address
    state.bus.ram[0x15] = 0x66; // Value at $0010 + $05 = $0015
    state.cpu.pc = 0x0000;
    state.cpu.x = 0x05;

    // Execute all 4 cycles
    for (0..4) |_| {
        state.tickCpu();
    }

    try testing.expectEqual(@as(u8, 0x66), state.cpu.a);
    try testing.expectEqual(@as(u64, 4), state.cpu.cycle_count);
}

test "LDA zero page,X - wrapping" {
    var state = createTestState();

    // Setup: LDA $FF,X with X=$05 -> wraps to $04
    state.bus.ram[0] = 0xB5;
    state.bus.ram[1] = 0xFF;
    state.bus.ram[0x04] = 0x77; // $FF + $05 = $104, wraps to $04
    state.cpu.pc = 0x0000;
    state.cpu.x = 0x05;

    for (0..4) |_| {
        _ = state.tickCpu();
    }

    try testing.expectEqual(@as(u8, 0x77), state.cpu.a);
    try testing.expectEqual(@as(u16, 0x0004), state.cpu.effective_address);
}

test "LDA absolute - 4 cycles" {
    var state = createTestState();

    // Setup: LDA $0234 (keep in RAM range)
    state.bus.ram[0] = 0xAD; // LDA absolute
    state.bus.ram[1] = 0x34; // Low byte
    state.bus.ram[2] = 0x02; // High byte (0x0234 is in RAM)
    state.bus.ram[0x234] = 0x88;
    state.cpu.pc = 0x0000;

    for (0..4) |_| {
        _ = state.tickCpu();
    }

    try testing.expectEqual(@as(u8, 0x88), state.cpu.a);
    try testing.expectEqual(@as(u64, 4), state.cpu.cycle_count);
}

test "LDA absolute,X - no page crossing" {
    var state = createTestState();

    // Setup: LDA $0130,X with X=$05 -> $0135 (no page cross, in RAM)
    state.bus.ram[0] = 0xBD; // LDA absolute,X
    state.bus.ram[1] = 0x30; // Low
    state.bus.ram[2] = 0x01; // High
    state.bus.ram[0x135] = 0x99;
    state.cpu.pc = 0x0000;
    state.cpu.x = 0x05;

    // Hardware: 4 cycles (we will match this after fix)
    for (0..4) |_| {
        state.tickCpu();
    }

    try testing.expectEqual(@as(u8, 0x99), state.cpu.a);
    try testing.expect(!state.cpu.page_crossed);
    try testing.expectEqual(@as(u64, 4), state.cpu.cycle_count);
}

test "LDA absolute,X - page crossing (5 cycles)" {
    var state = createTestState();

    // Setup: LDA $01FF,X with X=$05 -> $0204 (page cross, in RAM)
    state.bus.ram[0] = 0xBD;
    state.bus.ram[1] = 0xFF;
    state.bus.ram[2] = 0x01;
    state.bus.ram[0x204] = 0xAA;
    state.cpu.pc = 0x0000;
    state.cpu.x = 0x05;

    // Hardware: 5 cycles (we will match this after fix)
    for (0..5) |_| {
        state.tickCpu();
    }

    try testing.expectEqual(@as(u8, 0xAA), state.cpu.a);
    try testing.expect(state.cpu.page_crossed);
    try testing.expectEqual(@as(u64, 5), state.cpu.cycle_count);
}

// ============================================================================
// STA Instruction Tests
// ============================================================================

test "STA zero page - 3 cycles" {
    var state = createTestState();

    // Setup: STA $20
    state.bus.ram[0] = 0x85; // STA zero page
    state.bus.ram[1] = 0x20; // ZP address
    state.cpu.pc = 0x0000;
    state.cpu.a = 0x42;

    for (0..3) |_| {
        _ = state.tickCpu();
    }

    try testing.expectEqual(@as(u8, 0x42), state.bus.ram[0x20]);
    try testing.expectEqual(@as(u64, 3), state.cpu.cycle_count);
}

test "STA absolute,X - always 5+ cycles (write instruction)" {
    var state = createTestState();

    // Setup: STA $0200,X with X=$05 (no page cross, in RAM)
    state.bus.ram[0] = 0x9D; // STA absolute,X
    state.bus.ram[1] = 0x00;
    state.bus.ram[2] = 0x02;
    state.cpu.pc = 0x0000;
    state.cpu.x = 0x05;
    state.cpu.a = 0x77;

    // Hardware: 5 cycles (write always has dummy read, then write)
    for (0..5) |_| {
        state.tickCpu();
    }

    try testing.expectEqual(@as(u8, 0x77), state.bus.ram[0x205]);
    try testing.expectEqual(@as(u64, 5), state.cpu.cycle_count);
}

// ============================================================================
// NOP Variant Tests (Unofficial Opcodes)
// ============================================================================

test "NOP: 1-byte implied variants - 2 cycles" {
    var state = createTestState();

    const opcodes_to_test = [_]u8{ 0x1A, 0x3A, 0x5A, 0x7A, 0xDA, 0xFA };

    for (opcodes_to_test) |opcode| {
        state = createTestState();

        // Setup: NOP at $0000
        state.bus.ram[0] = opcode;
        state.cpu.pc = 0x0000;

        const initial_a = state.cpu.a;
        const initial_x = state.cpu.x;
        const initial_y = state.cpu.y;
        const initial_p = state.cpu.p.toByte();

        // Cycle 1: Fetch opcode
        state.tickCpu();
        try testing.expectEqual(@as(u16, 0x0001), state.cpu.pc);

        // Cycle 2: Execute NOP (does nothing)
        state.tickCpu();
        try testing.expectEqual(@as(u64, 2), state.cpu.cycle_count);

        // Verify no registers changed
        try testing.expectEqual(initial_a, state.cpu.a);
        try testing.expectEqual(initial_x, state.cpu.x);
        try testing.expectEqual(initial_y, state.cpu.y);
        try testing.expectEqual(initial_p, state.cpu.p.toByte());
        try testing.expectEqual(@as(u16, 0x0001), state.cpu.pc);
    }
}

test "NOP: 2-byte zero page variants - 3 cycles" {
    var state = createTestState();

    const opcodes_to_test = [_]u8{ 0x04, 0x44, 0x64 };

    for (opcodes_to_test) |opcode| {
        state = createTestState();

        // Setup: NOP $42 at $0000
        state.bus.ram[0] = opcode;
        state.bus.ram[1] = 0x42; // Zero page address
        state.bus.ram[0x42] = 0xFF; // Value at address (should be read but discarded)
        state.cpu.pc = 0x0000;

        const initial_a = state.cpu.a;
        const initial_x = state.cpu.x;
        const initial_y = state.cpu.y;
        const initial_p = state.cpu.p.toByte();

        // Execute through all cycles
        for (0..3) |_| {
            _ = state.tickCpu();
        }

        // PC should advance by 2 (opcode + operand)
        try testing.expectEqual(@as(u16, 0x0002), state.cpu.pc);
        try testing.expectEqual(@as(u64, 3), state.cpu.cycle_count);

        // Verify no registers changed
        try testing.expectEqual(initial_a, state.cpu.a);
        try testing.expectEqual(initial_x, state.cpu.x);
        try testing.expectEqual(initial_y, state.cpu.y);
        try testing.expectEqual(initial_p, state.cpu.p.toByte());
    }
}

test "NOP: 2-byte zero page,X variants - 4 cycles" {
    var state = createTestState();

    const opcodes_to_test = [_]u8{ 0x14, 0x34, 0x54, 0x74, 0xD4, 0xF4 };

    for (opcodes_to_test) |opcode| {
        state = createTestState();

        // Setup: NOP $42,X at $0000 with X=$05
        state.bus.ram[0] = opcode;
        state.bus.ram[1] = 0x42; // Zero page base address
        state.cpu.pc = 0x0000;
        state.cpu.x = 0x05; // Index
        state.bus.ram[0x47] = 0xFF; // Value at $42+$05 (should be read but discarded)

        const initial_a = state.cpu.a;
        const initial_x = state.cpu.x;
        const initial_y = state.cpu.y;
        const initial_p = state.cpu.p.toByte();

        // Execute through all cycles
        for (0..4) |_| {
            _ = state.tickCpu();
        }

        // PC should advance by 2 (opcode + operand)
        try testing.expectEqual(@as(u16, 0x0002), state.cpu.pc);
        try testing.expectEqual(@as(u64, 4), state.cpu.cycle_count);

        // Verify no registers changed (including X)
        try testing.expectEqual(initial_a, state.cpu.a);
        try testing.expectEqual(initial_x, state.cpu.x);
        try testing.expectEqual(initial_y, state.cpu.y);
        try testing.expectEqual(initial_p, state.cpu.p.toByte());
    }
}

test "NOP: 2-byte zero page,X with wrapping" {
    var state = createTestState();

    // Setup: NOP $FF,X with X=$10 -> wraps to $0F
    state.bus.ram[0] = 0x14; // NOP zero page,X
    state.bus.ram[1] = 0xFF;
    state.cpu.pc = 0x0000;
    state.cpu.x = 0x10;
    state.bus.ram[0x0F] = 0xAA; // Value at wrapped address

    for (0..4) |_| {
        _ = state.tickCpu();
    }

    try testing.expectEqual(@as(u16, 0x0002), state.cpu.pc);
    try testing.expectEqual(@as(u64, 4), state.cpu.cycle_count);
}

test "NOP: 3-byte absolute - 4 cycles" {
    var state = createTestState();

    // Setup: NOP $1234 at $0000
    state.bus.ram[0] = 0x0C; // NOP absolute
    state.bus.ram[1] = 0x34; // Low byte
    state.bus.ram[2] = 0x12; // High byte
    state.cpu.pc = 0x0000;
    state.bus.ram[0x234] = 0xFF; // Value at $1234 (should be read but discarded)

    const initial_a = state.cpu.a;
    const initial_p = state.cpu.p.toByte();

    // Execute through all cycles
    for (0..4) |_| {
        _ = state.tickCpu();
    }

    // PC should advance by 3 (opcode + 2 operand bytes)
    try testing.expectEqual(@as(u16, 0x0003), state.cpu.pc);
    try testing.expectEqual(@as(u64, 4), state.cpu.cycle_count);

    // Verify no registers changed
    try testing.expectEqual(initial_a, state.cpu.a);
    try testing.expectEqual(initial_p, state.cpu.p.toByte());
}

test "NOP: 3-byte absolute,X variants without page crossing - 4 cycles" {
    var state = createTestState();

    const opcodes_to_test = [_]u8{ 0x1C, 0x3C, 0x5C, 0x7C, 0xDC, 0xFC };

    for (opcodes_to_test) |opcode| {
        state = createTestState();

        // Setup: NOP $1000,X with X=$10 (no page cross)
        state.bus.ram[0] = opcode;
        state.bus.ram[1] = 0x00; // Low byte
        state.bus.ram[2] = 0x10; // High byte
        state.cpu.pc = 0x0000;
        state.cpu.x = 0x10;
        state.bus.ram[0x010] = 0xFF; // Value at $1010

        const initial_p = state.cpu.p.toByte();

        // Execute through all cycles (no page cross = 4 cycles)
        for (0..4) |_| {
            _ = state.tickCpu();
        }

        try testing.expectEqual(@as(u16, 0x0003), state.cpu.pc);
        try testing.expectEqual(@as(u64, 4), state.cpu.cycle_count);
        try testing.expectEqual(initial_p, state.cpu.p.toByte());
    }
}

test "NOP: 3-byte absolute,X with page crossing - 5 cycles" {
    var state = createTestState();

    const opcodes_to_test = [_]u8{ 0x1C, 0x3C, 0x5C, 0x7C, 0xDC, 0xFC };

    for (opcodes_to_test) |opcode| {
        state = createTestState();

        // Setup: NOP $10F0,X with X=$20 -> $1110 (page cross)
        state.bus.ram[0] = opcode;
        state.bus.ram[1] = 0xF0; // Low byte
        state.bus.ram[2] = 0x10; // High byte
        state.cpu.pc = 0x0000;
        state.cpu.x = 0x20; // This will cause page crossing
        state.bus.ram[0x110] = 0xFF; // Value at $1110

        const initial_p = state.cpu.p.toByte();

        // Execute through all cycles (page cross = 5 cycles)
        for (0..5) |_| {
            _ = state.tickCpu();
        }

        try testing.expectEqual(@as(u16, 0x0003), state.cpu.pc);
        try testing.expectEqual(@as(u64, 5), state.cpu.cycle_count);
        try testing.expectEqual(initial_p, state.cpu.p.toByte());
    }
}

test "NOP variants: memory reads actually occur" {
    var state = createTestState();

    // Setup: NOP $42 (zero page)
    state.bus.ram[0] = 0x04; // NOP zero page
    state.bus.ram[1] = 0x42;
    state.bus.ram[0x42] = 0x99;
    state.cpu.pc = 0x0000;

    // Execute
    for (0..3) |_| {
        _ = state.tickCpu();
    }

    // The read should have updated open bus
    // (This verifies the read actually happens, important for hardware accuracy)
    try testing.expectEqual(@as(u8, 0x99), state.bus.open_bus);
}

// ============================================================================
// Power-On and Reset Tests
// ============================================================================

test "CPU power-on state - AccuracyCoin requirements" {
    const state = createTestState();

    // AccuracyCoin requirement: A/X/Y = $00 at power-on
    try testing.expectEqual(@as(u8, 0x00), state.cpu.a);
    try testing.expectEqual(@as(u8, 0x00), state.cpu.x);
    try testing.expectEqual(@as(u8, 0x00), state.cpu.y);

    // AccuracyCoin requirement: SP = $FD at power-on
    try testing.expectEqual(@as(u8, 0xFD), state.cpu.sp);

    // AccuracyCoin requirement: I flag set (interrupt disable)
    try testing.expect(state.cpu.p.interrupt);

    // Other flags should be clear at power-on (except unused which is always 1)
    try testing.expect(!state.cpu.p.carry);
    try testing.expect(!state.cpu.p.zero);
    try testing.expect(!state.cpu.p.overflow);
    try testing.expect(!state.cpu.p.negative);
    try testing.expect(!state.cpu.p.decimal);
    try testing.expect(state.cpu.p.unused); // Always 1

    // State should be fetch_opcode
    try testing.expectEqual(RAMBO.Cpu.ExecutionState.fetch_opcode, state.cpu.state);
}

test "RESET: loads PC from vector at $FFFC-$FFFD" {
    var state = createTestState();
    const test_ram = allocTestRam(&state);
    defer testing.allocator.free(test_ram);

    // Set reset vector to $8000
    state.busWrite(0xFFFC, 0x00); // Low byte
    state.busWrite(0xFFFD, 0x80); // High byte

    state.reset();

    // PC should be loaded from vector
    try testing.expectEqual(@as(u16, 0x8000), state.cpu.pc);
}

test "RESET: sets SP to $FD" {
    var state = createTestState();

    // Set SP to different value
    state.cpu.sp = 0x00;

    // Set reset vector (required for reset)
    state.busWrite(0xFFFC, 0x00);
    state.busWrite(0xFFFD, 0x80);

    state.reset();

    // SP should be set to $FD (standard reset value)
    try testing.expectEqual(@as(u8, 0xFD), state.cpu.sp);
}

test "RESET: sets interrupt disable flag" {
    var state = createTestState();

    // Clear I flag
    state.cpu.p.interrupt = false;

    // Set reset vector
    state.busWrite(0xFFFC, 0x00);
    state.busWrite(0xFFFD, 0x80);

    state.reset();

    // I flag should be set
    try testing.expect(state.cpu.p.interrupt);
}

test "RESET: preserves A/X/Y registers" {
    var state = createTestState();

    // Set registers to known values
    state.cpu.a = 0x42;
    state.cpu.x = 0x55;
    state.cpu.y = 0xAA;

    // Set reset vector
    state.busWrite(0xFFFC, 0x00);
    state.busWrite(0xFFFD, 0x80);

    state.reset();

    // A/X/Y should be unchanged (reset doesn't modify registers)
    try testing.expectEqual(@as(u8, 0x42), state.cpu.a);
    try testing.expectEqual(@as(u8, 0x55), state.cpu.x);
    try testing.expectEqual(@as(u8, 0xAA), state.cpu.y);
}

test "RESET: loads PC from reset vector" {
    var state = createTestState();
    const test_ram = allocTestRam(&state);
    defer testing.allocator.free(test_ram);

    // Set PC to some value
    state.cpu.pc = 0x1234;

    // Set reset vector to $8000
    state.busWrite(0xFFFC, 0x00);
    state.busWrite(0xFFFD, 0x80);

    state.reset();

    // PC should be loaded from reset vector
    try testing.expectEqual(@as(u16, 0x8000), state.cpu.pc);

    // Note: EmulationState.reset() doesn't modify state machine fields
    // (halted, state, instruction_cycle) - those are managed by CPU execution
}

test "Power-on vs RESET: SP always set to $FD" {
    var state = createTestState();

    // Init sets SP to $FD
    try testing.expectEqual(@as(u8, 0xFD), state.cpu.sp);

    // Set SP to different value
    state.cpu.sp = 0x00;

    // Set reset vector and reset
    state.busWrite(0xFFFC, 0x00);
    state.busWrite(0xFFFD, 0x80);

    state.reset();

    // Reset also sets SP to $FD (same as power-on)
    try testing.expectEqual(@as(u8, 0xFD), state.cpu.sp);
}

test "RESET: disables interrupts via I flag" {
    var state = createTestState();

    // Clear interrupt disable flag
    state.cpu.p.interrupt = false;

    // Set reset vector and reset
    state.busWrite(0xFFFC, 0x00);
    state.busWrite(0xFFFD, 0x80);

    state.reset();

    // Interrupt disable flag should be set
    try testing.expect(state.cpu.p.interrupt);

    // Note: EmulationState.reset() sets I flag but doesn't clear pending_interrupt
    // The CPU handles pending interrupts during execution
}

// ============================================================================
// Open Bus Tests
// ============================================================================

test "Instructions update open bus correctly" {
    var state = createTestState();

    // LDA immediate updates bus with operand
    state.bus.ram[0] = 0xA9;
    state.bus.ram[1] = 0x42;
    state.cpu.pc = 0x0000;

    _ = state.tickCpu(); // Fetch opcode
    _ = state.tickCpu(); // Execute (fetch operand) - should update bus

    // Open bus should have the operand value
    try testing.expectEqual(@as(u8, 0x42), state.bus.open_bus);
}
