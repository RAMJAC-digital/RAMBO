const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Cpu = RAMBO.Cpu;
const Bus = RAMBO.Bus;

// ============================================================================
// NOP Instruction Tests
// ============================================================================

test "NOP implied - 2 cycles" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    // Setup: NOP at $8000
    bus.ram[0] = 0xEA; // NOP opcode
    state.pc = 0x0000;

    const initial_a = state.a;
    const initial_x = state.x;
    const initial_y = state.y;
    const initial_p = state.p;

    // Cycle 1: Fetch opcode
    var complete = Cpu.Logic.tick(&state, &bus);
    try testing.expect(!complete);
    try testing.expectEqual(@as(u16, 0x0001), state.pc);
    try testing.expectEqual(@as(u64, 1), state.cycle_count);

    // Cycle 2: Execute NOP (does nothing)
    complete = Cpu.Logic.tick(&state, &bus);
    try testing.expect(complete);
    try testing.expectEqual(@as(u64, 2), state.cycle_count);

    // Verify no registers changed
    try testing.expectEqual(initial_a, state.a);
    try testing.expectEqual(initial_x, state.x);
    try testing.expectEqual(initial_y, state.y);
    try testing.expectEqual(initial_p.toByte(), state.p.toByte());
}

test "NOP immediate (unofficial) - 2 cycles" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    // Setup: NOP #$42 at $8000
    bus.ram[0] = 0x80; // Unofficial NOP immediate
    bus.ram[1] = 0x42; // Operand (ignored)
    state.pc = 0x0000;

    // Cycle 1: Fetch opcode
    var complete = Cpu.Logic.tick(&state, &bus);
    try testing.expect(!complete);

    // Cycle 2: Execute (fetch operand and discard)
    complete = Cpu.Logic.tick(&state, &bus);
    try testing.expect(complete);

    try testing.expectEqual(@as(u16, 0x0002), state.pc); // PC advanced past operand
    try testing.expectEqual(@as(u64, 2), state.cycle_count);
}

// ============================================================================
// LDA Instruction Tests
// ============================================================================

test "LDA immediate - 2 cycles" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    // Setup: LDA #$42
    bus.ram[0] = 0xA9; // LDA immediate
    bus.ram[1] = 0x42; // Operand
    state.pc = 0x0000;

    // Cycle 1: Fetch opcode
    var complete = Cpu.Logic.tick(&state, &bus);
    try testing.expect(!complete);

    // Cycle 2: Execute (fetch operand and load)
    complete = Cpu.Logic.tick(&state, &bus);
    try testing.expect(complete);

    try testing.expectEqual(@as(u8, 0x42), state.a);
    try testing.expect(!state.p.zero);
    try testing.expect(!state.p.negative);
}

test "LDA immediate - zero flag" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    // Setup: LDA #$00
    bus.ram[0] = 0xA9;
    bus.ram[1] = 0x00;
    state.pc = 0x0000;

    // Execute instruction (2 cycles)
    _ = Cpu.Logic.tick(&state, &bus); // Fetch
    const complete = Cpu.Logic.tick(&state, &bus); // Execute

    try testing.expect(complete);
    try testing.expectEqual(@as(u8, 0x00), state.a);
    try testing.expect(state.p.zero);
    try testing.expect(!state.p.negative);
}

test "LDA immediate - negative flag" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    // Setup: LDA #$80
    bus.ram[0] = 0xA9;
    bus.ram[1] = 0x80;
    state.pc = 0x0000;

    // Execute instruction (2 cycles)
    _ = Cpu.Logic.tick(&state, &bus);
    const complete = Cpu.Logic.tick(&state, &bus);

    try testing.expect(complete);
    try testing.expectEqual(@as(u8, 0x80), state.a);
    try testing.expect(!state.p.zero);
    try testing.expect(state.p.negative);
}

test "LDA zero page - 3 cycles" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    // Setup: LDA $10
    bus.ram[0] = 0xA5; // LDA zero page
    bus.ram[1] = 0x10; // ZP address
    bus.ram[0x10] = 0x55; // Value at $0010
    state.pc = 0x0000;

    // Cycle 1: Fetch opcode
    var complete = Cpu.Logic.tick(&state, &bus);
    try testing.expect(!complete);
    try testing.expectEqual(@as(u64, 1), state.cycle_count);

    // Cycle 2: Fetch ZP address
    complete = Cpu.Logic.tick(&state, &bus);
    try testing.expect(!complete);
    try testing.expectEqual(@as(u64, 2), state.cycle_count);

    // Cycle 3: Execute (read from ZP)
    complete = Cpu.Logic.tick(&state, &bus);
    try testing.expect(complete);
    try testing.expectEqual(@as(u64, 3), state.cycle_count);
    try testing.expectEqual(@as(u8, 0x55), state.a);
}

test "LDA zero page,X - 4 cycles" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    // Setup: LDA $10,X with X=$05
    bus.ram[0] = 0xB5; // LDA zero page,X
    bus.ram[1] = 0x10; // Base address
    bus.ram[0x15] = 0x66; // Value at $0010 + $05 = $0015
    state.pc = 0x0000;
    state.x = 0x05;

    // Execute all 4 cycles
    for (0..4) |i| {
        const c = Cpu.Logic.tick(&state, &bus);
        if (i == 3) {
            try testing.expect(c);
        } else {
            try testing.expect(!c);
        }
    }

    try testing.expectEqual(@as(u8, 0x66), state.a);
    try testing.expectEqual(@as(u64, 4), state.cycle_count);
}

test "LDA zero page,X - wrapping" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    // Setup: LDA $FF,X with X=$05 -> wraps to $04
    bus.ram[0] = 0xB5;
    bus.ram[1] = 0xFF;
    bus.ram[0x04] = 0x77; // $FF + $05 = $104, wraps to $04
    state.pc = 0x0000;
    state.x = 0x05;

    for (0..4) |_| {
        _ = Cpu.Logic.tick(&state, &bus);
    }

    try testing.expectEqual(@as(u8, 0x77), state.a);
    try testing.expectEqual(@as(u16, 0x0004), state.effective_address);
}

test "LDA absolute - 4 cycles" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    // Setup: LDA $0234 (keep in RAM range)
    bus.ram[0] = 0xAD; // LDA absolute
    bus.ram[1] = 0x34; // Low byte
    bus.ram[2] = 0x02; // High byte (0x0234 is in RAM)
    bus.ram[0x234] = 0x88;
    state.pc = 0x0000;

    for (0..4) |_| {
        _ = Cpu.Logic.tick(&state, &bus);
    }

    try testing.expectEqual(@as(u8, 0x88), state.a);
    try testing.expectEqual(@as(u64, 4), state.cycle_count);
}

test "LDA absolute,X - no page crossing" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    // Setup: LDA $0130,X with X=$05 -> $0135 (no page cross, in RAM)
    bus.ram[0] = 0xBD; // LDA absolute,X
    bus.ram[1] = 0x30; // Low
    bus.ram[2] = 0x01; // High
    bus.ram[0x135] = 0x99;
    state.pc = 0x0000;
    state.x = 0x05;

    // NOTE: Hardware does this in 4 cycles (dummy read IS the actual read)
    // Our current architecture takes 5 cycles but functionally correct
    // TODO: Optimize to 4 cycles when state machine supports in-cycle execution
    for (0..5) |_| {
        _ = Cpu.Logic.tick(&state, &bus);
    }

    try testing.expectEqual(@as(u8, 0x99), state.a);
    try testing.expect(!state.page_crossed);
    // Hardware: 4 cycles, Our impl: 5 cycles (known timing deviation)
    try testing.expectEqual(@as(u64, 5), state.cycle_count);
}

test "LDA absolute,X - page crossing (5 cycles)" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    // Setup: LDA $01FF,X with X=$05 -> $0204 (page cross, in RAM)
    bus.ram[0] = 0xBD;
    bus.ram[1] = 0xFF;
    bus.ram[2] = 0x01;
    bus.ram[0x204] = 0xAA;
    state.pc = 0x0000;
    state.x = 0x05;

    for (0..5) |i| {
        const c = Cpu.Logic.tick(&state, &bus);
        if (i == 4) {
            try testing.expect(c);
        } else {
            try testing.expect(!c);
        }
    }

    try testing.expectEqual(@as(u8, 0xAA), state.a);
    try testing.expect(state.page_crossed);
    try testing.expectEqual(@as(u64, 5), state.cycle_count);
}

// ============================================================================
// STA Instruction Tests
// ============================================================================

test "STA zero page - 3 cycles" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    // Setup: STA $20
    bus.ram[0] = 0x85; // STA zero page
    bus.ram[1] = 0x20; // ZP address
    state.pc = 0x0000;
    state.a = 0x42;

    for (0..3) |_| {
        _ = Cpu.Logic.tick(&state, &bus);
    }

    try testing.expectEqual(@as(u8, 0x42), bus.ram[0x20]);
    try testing.expectEqual(@as(u64, 3), state.cycle_count);
}

test "STA absolute,X - always 5+ cycles (write instruction)" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    // Setup: STA $0200,X with X=$05 (no page cross, in RAM)
    bus.ram[0] = 0x9D; // STA absolute,X
    bus.ram[1] = 0x00;
    bus.ram[2] = 0x02;
    state.pc = 0x0000;
    state.x = 0x05;
    state.a = 0x77;

    // Hardware: 5 cycles (write always has dummy read, then write)
    // Our impl: 6 cycles (addressing + execute state)
    for (0..6) |_| {
        _ = Cpu.Logic.tick(&state, &bus);
    }

    try testing.expectEqual(@as(u8, 0x77), bus.ram[0x205]);
    try testing.expectEqual(@as(u64, 6), state.cycle_count);
}

// ============================================================================
// NOP Variant Tests (Unofficial Opcodes)
// ============================================================================

test "NOP: 1-byte implied variants - 2 cycles" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    const opcodes_to_test = [_]u8{ 0x1A, 0x3A, 0x5A, 0x7A, 0xDA, 0xFA };

    for (opcodes_to_test) |opcode| {
        state = Cpu.Logic.init();
        bus = Bus.init();

        // Setup: NOP at $0000
        bus.ram[0] = opcode;
        state.pc = 0x0000;

        const initial_a = state.a;
        const initial_x = state.x;
        const initial_y = state.y;
        const initial_p = state.p.toByte();

        // Cycle 1: Fetch opcode
        var complete = Cpu.Logic.tick(&state, &bus);
        try testing.expect(!complete);
        try testing.expectEqual(@as(u16, 0x0001), state.pc);

        // Cycle 2: Execute NOP (does nothing)
        complete = Cpu.Logic.tick(&state, &bus);
        try testing.expect(complete);
        try testing.expectEqual(@as(u64, 2), state.cycle_count);

        // Verify no registers changed
        try testing.expectEqual(initial_a, state.a);
        try testing.expectEqual(initial_x, state.x);
        try testing.expectEqual(initial_y, state.y);
        try testing.expectEqual(initial_p, state.p.toByte());
        try testing.expectEqual(@as(u16, 0x0001), state.pc);
    }
}

test "NOP: 2-byte zero page variants - 3 cycles" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    const opcodes_to_test = [_]u8{ 0x04, 0x44, 0x64 };

    for (opcodes_to_test) |opcode| {
        state = Cpu.Logic.init();
        bus = Bus.init();

        // Setup: NOP $42 at $0000
        bus.ram[0] = opcode;
        bus.ram[1] = 0x42; // Zero page address
        bus.ram[0x42] = 0xFF; // Value at address (should be read but discarded)
        state.pc = 0x0000;

        const initial_a = state.a;
        const initial_x = state.x;
        const initial_y = state.y;
        const initial_p = state.p.toByte();

        // Execute through all cycles
        for (0..3) |_| {
            _ = Cpu.Logic.tick(&state, &bus);
        }

        // PC should advance by 2 (opcode + operand)
        try testing.expectEqual(@as(u16, 0x0002), state.pc);
        try testing.expectEqual(@as(u64, 3), state.cycle_count);

        // Verify no registers changed
        try testing.expectEqual(initial_a, state.a);
        try testing.expectEqual(initial_x, state.x);
        try testing.expectEqual(initial_y, state.y);
        try testing.expectEqual(initial_p, state.p.toByte());
    }
}

test "NOP: 2-byte zero page,X variants - 4 cycles" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    const opcodes_to_test = [_]u8{ 0x14, 0x34, 0x54, 0x74, 0xD4, 0xF4 };

    for (opcodes_to_test) |opcode| {
        state = Cpu.Logic.init();
        bus = Bus.init();

        // Setup: NOP $42,X at $0000 with X=$05
        bus.ram[0] = opcode;
        bus.ram[1] = 0x42; // Zero page base address
        state.pc = 0x0000;
        state.x = 0x05; // Index
        bus.ram[0x47] = 0xFF; // Value at $42+$05 (should be read but discarded)

        const initial_a = state.a;
        const initial_x = state.x;
        const initial_y = state.y;
        const initial_p = state.p.toByte();

        // Execute through all cycles
        for (0..4) |_| {
            _ = Cpu.Logic.tick(&state, &bus);
        }

        // PC should advance by 2 (opcode + operand)
        try testing.expectEqual(@as(u16, 0x0002), state.pc);
        try testing.expectEqual(@as(u64, 4), state.cycle_count);

        // Verify no registers changed (including X)
        try testing.expectEqual(initial_a, state.a);
        try testing.expectEqual(initial_x, state.x);
        try testing.expectEqual(initial_y, state.y);
        try testing.expectEqual(initial_p, state.p.toByte());
    }
}

test "NOP: 2-byte zero page,X with wrapping" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    // Setup: NOP $FF,X with X=$10 -> wraps to $0F
    bus.ram[0] = 0x14; // NOP zero page,X
    bus.ram[1] = 0xFF;
    state.pc = 0x0000;
    state.x = 0x10;
    bus.ram[0x0F] = 0xAA; // Value at wrapped address

    for (0..4) |_| {
        _ = Cpu.Logic.tick(&state, &bus);
    }

    try testing.expectEqual(@as(u16, 0x0002), state.pc);
    try testing.expectEqual(@as(u64, 4), state.cycle_count);
}

test "NOP: 3-byte absolute - 4 cycles" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    // Setup: NOP $1234 at $0000
    bus.ram[0] = 0x0C; // NOP absolute
    bus.ram[1] = 0x34; // Low byte
    bus.ram[2] = 0x12; // High byte
    state.pc = 0x0000;
    bus.ram[0x234] = 0xFF; // Value at $1234 (should be read but discarded)

    const initial_a = state.a;
    const initial_p = state.p.toByte();

    // Execute through all cycles
    for (0..4) |_| {
        _ = Cpu.Logic.tick(&state, &bus);
    }

    // PC should advance by 3 (opcode + 2 operand bytes)
    try testing.expectEqual(@as(u16, 0x0003), state.pc);
    try testing.expectEqual(@as(u64, 4), state.cycle_count);

    // Verify no registers changed
    try testing.expectEqual(initial_a, state.a);
    try testing.expectEqual(initial_p, state.p.toByte());
}

test "NOP: 3-byte absolute,X variants without page crossing - 4 cycles" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    const opcodes_to_test = [_]u8{ 0x1C, 0x3C, 0x5C, 0x7C, 0xDC, 0xFC };

    for (opcodes_to_test) |opcode| {
        state = Cpu.Logic.init();
        bus = Bus.init();

        // Setup: NOP $1000,X with X=$10 (no page cross)
        bus.ram[0] = opcode;
        bus.ram[1] = 0x00; // Low byte
        bus.ram[2] = 0x10; // High byte
        state.pc = 0x0000;
        state.x = 0x10;
        bus.ram[0x010] = 0xFF; // Value at $1010

        const initial_p = state.p.toByte();

        // Execute through all cycles (no page cross = 4 cycles)
        for (0..4) |_| {
            _ = Cpu.Logic.tick(&state, &bus);
        }

        try testing.expectEqual(@as(u16, 0x0003), state.pc);
        try testing.expectEqual(@as(u64, 4), state.cycle_count);
        try testing.expectEqual(initial_p, state.p.toByte());
    }
}

test "NOP: 3-byte absolute,X with page crossing - 5 cycles" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    const opcodes_to_test = [_]u8{ 0x1C, 0x3C, 0x5C, 0x7C, 0xDC, 0xFC };

    for (opcodes_to_test) |opcode| {
        state = Cpu.Logic.init();
        bus = Bus.init();

        // Setup: NOP $10F0,X with X=$20 -> $1110 (page cross)
        bus.ram[0] = opcode;
        bus.ram[1] = 0xF0; // Low byte
        bus.ram[2] = 0x10; // High byte
        state.pc = 0x0000;
        state.x = 0x20; // This will cause page crossing
        bus.ram[0x110] = 0xFF; // Value at $1110

        const initial_p = state.p.toByte();

        // Execute through all cycles (page cross = 5 cycles)
        for (0..5) |_| {
            _ = Cpu.Logic.tick(&state, &bus);
        }

        try testing.expectEqual(@as(u16, 0x0003), state.pc);
        try testing.expectEqual(@as(u64, 5), state.cycle_count);
        try testing.expectEqual(initial_p, state.p.toByte());
    }
}

test "NOP variants: memory reads actually occur" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    // Setup: NOP $42 (zero page)
    bus.ram[0] = 0x04; // NOP zero page
    bus.ram[1] = 0x42;
    bus.ram[0x42] = 0x99;
    state.pc = 0x0000;

    // Execute
    for (0..3) |_| {
        _ = Cpu.Logic.tick(&state, &bus);
    }

    // The read should have updated open bus
    // (This verifies the read actually happens, important for hardware accuracy)
    try testing.expectEqual(@as(u8, 0x99), bus.open_bus.value);
}

// ============================================================================
// Power-On and Reset Tests
// ============================================================================

test "CPU power-on state - AccuracyCoin requirements" {
    const state = Cpu.Logic.init();

    // AccuracyCoin requirement: A/X/Y = $00 at power-on
    try testing.expectEqual(@as(u8, 0x00), state.a);
    try testing.expectEqual(@as(u8, 0x00), state.x);
    try testing.expectEqual(@as(u8, 0x00), state.y);

    // AccuracyCoin requirement: SP = $FD at power-on
    try testing.expectEqual(@as(u8, 0xFD), state.sp);

    // AccuracyCoin requirement: I flag set (interrupt disable)
    try testing.expect(state.p.interrupt);

    // Other flags should be clear at power-on (except unused which is always 1)
    try testing.expect(!state.p.carry);
    try testing.expect(!state.p.zero);
    try testing.expect(!state.p.overflow);
    try testing.expect(!state.p.negative);
    try testing.expect(!state.p.decimal);
    try testing.expect(state.p.unused); // Always 1

    // State should be fetch_opcode
    try testing.expectEqual(RAMBO.Cpu.ExecutionState.fetch_opcode, state.state);
}

test "RESET: loads PC from vector at $FFFC-$FFFD" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    // Allocate test RAM for reset vector
    var test_ram = [_]u8{0} ** 32768;
    bus.test_ram = &test_ram;

    // Set reset vector to $8000
    bus.write(0xFFFC, 0x00); // Low byte
    bus.write(0xFFFD, 0x80); // High byte

    Cpu.Logic.reset(&state, &bus);

    // PC should be loaded from vector
    try testing.expectEqual(@as(u16, 0x8000), state.pc);
}

test "RESET: decrements SP by 3" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    var test_ram = [_]u8{0} ** 32768;
    bus.test_ram = &test_ram;

    // Set SP to known value
    state.sp = 0xFF;

    // Set reset vector (required for reset)
    bus.write(0xFFFC, 0x00);
    bus.write(0xFFFD, 0x80);

    Cpu.Logic.reset(&state, &bus);

    // SP should be decremented by 3
    try testing.expectEqual(@as(u8, 0xFC), state.sp);
}

test "RESET: sets interrupt disable flag" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    var test_ram = [_]u8{0} ** 32768;
    bus.test_ram = &test_ram;

    // Clear I flag
    state.p.interrupt = false;

    bus.write(0xFFFC, 0x00);
    bus.write(0xFFFD, 0x80);

    Cpu.Logic.reset(&state, &bus);

    // I flag should be set
    try testing.expect(state.p.interrupt);
}

test "RESET: preserves A/X/Y registers" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    var test_ram = [_]u8{0} ** 32768;
    bus.test_ram = &test_ram;

    // Set registers to known values
    state.a = 0x42;
    state.x = 0x55;
    state.y = 0xAA;

    bus.write(0xFFFC, 0x00);
    bus.write(0xFFFD, 0x80);

    Cpu.Logic.reset(&state, &bus);

    // A/X/Y should be unchanged
    try testing.expectEqual(@as(u8, 0x42), state.a);
    try testing.expectEqual(@as(u8, 0x55), state.x);
    try testing.expectEqual(@as(u8, 0xAA), state.y);
}

test "RESET: resets CPU state machine" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    var test_ram = [_]u8{0} ** 32768;
    bus.test_ram = &test_ram;

    // Put CPU in different state
    state.state = .calc_address_low;
    state.instruction_cycle = 5;
    state.halted = true;

    bus.write(0xFFFC, 0x00);
    bus.write(0xFFFD, 0x80);

    Cpu.Logic.reset(&state, &bus);

    // State should be reset
    try testing.expectEqual(RAMBO.Cpu.ExecutionState.fetch_opcode, state.state);
    try testing.expectEqual(@as(u8, 0), state.instruction_cycle);
    try testing.expect(!state.halted);
}

test "Power-on vs RESET: different SP values" {
    const state_power_on = Cpu.Logic.init();
    var state_reset = Cpu.Logic.init();
    var bus = Bus{};

    var test_ram = [_]u8{0} ** 32768;
    bus.test_ram = &test_ram;

    // Set reset SP to 0xFF before reset
    state_reset.sp = 0xFF;

    bus.write(0xFFFC, 0x00);
    bus.write(0xFFFD, 0x80);

    Cpu.Logic.reset(&state_reset, &bus);

    // Power-on: SP = $FD
    try testing.expectEqual(@as(u8, 0xFD), state_power_on.sp);

    // Reset: SP = original - 3 = $FC
    try testing.expectEqual(@as(u8, 0xFC), state_reset.sp);
}

test "RESET: clears pending interrupts" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    var test_ram = [_]u8{0} ** 32768;
    bus.test_ram = &test_ram;

    // Set pending interrupt
    state.pending_interrupt = .nmi;

    bus.write(0xFFFC, 0x00);
    bus.write(0xFFFD, 0x80);

    Cpu.Logic.reset(&state, &bus);

    // Pending interrupt should be cleared
    try testing.expectEqual(RAMBO.Cpu.InterruptType.none, state.pending_interrupt);
}

// ============================================================================
// Open Bus Tests
// ============================================================================

test "Instructions update open bus correctly" {
    var state = Cpu.Logic.init();
    var bus = Bus{};

    // LDA immediate updates bus with operand
    bus.ram[0] = 0xA9;
    bus.ram[1] = 0x42;
    state.pc = 0x0000;

    _ = Cpu.Logic.tick(&state, &bus); // Fetch opcode
    _ = Cpu.Logic.tick(&state, &bus); // Execute (fetch operand) - should update bus

    // Open bus should have the operand value
    try testing.expectEqual(@as(u8, 0x42), bus.open_bus.value);
}
