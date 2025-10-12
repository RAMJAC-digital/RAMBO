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
// Power-On and Reset Tests
// ============================================================================
// NOTE: NOP, LDA, STA tests removed - they duplicate tests in opcodes/*.zig
// This file now focuses on unique tests: power-on state, reset behavior, open bus

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

    _ = state.tickCpuWithClock(); // Fetch opcode
    _ = state.tickCpuWithClock(); // Execute (fetch operand) - should update bus

    // Open bus should have the operand value
    try testing.expectEqual(@as(u8, 0x42), state.bus.open_bus);
}
