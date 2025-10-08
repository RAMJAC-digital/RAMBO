//! Control Flow Opcode Integration Tests
//! Tests for JSR, RTS, RTI, BRK opcodes

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Cpu = RAMBO.Cpu;
const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;

// Test helper: Create EmulationState for control flow testing
fn createTestState() EmulationState {
    var config = Config.init(testing.allocator);
    config.deinit(); // Leak for test simplicity
    return EmulationState.init(&config);
}

// Test helper: Allocate test RAM for interrupt vector tests
fn allocTestRam(state: *EmulationState) []u8 {
    const test_ram = testing.allocator.alloc(u8, 0x8000) catch unreachable;
    @memset(test_ram, 0);
    state.bus.test_ram = test_ram;
    return test_ram;
}

// ============================================================================
// JSR Tests (Jump to Subroutine)
// ============================================================================

test "JSR: jumps to target address" {
    var state = createTestState();

    // JSR $0100 at address $0000
    state.cpu.pc = 0x0000;
    state.cpu.sp = 0xFF;

    state.bus.ram[0] = 0x20; // JSR
    state.bus.ram[1] = 0x00; // Low byte of target
    state.bus.ram[2] = 0x01; // High byte ($0100)

    // Execute 6 cycles
    for (0..6) |_| _ = state.tickCpuWithClock();

    try testing.expectEqual(@as(u16, 0x0100), state.cpu.pc);
}

test "JSR: pushes return address to stack" {
    var state = createTestState();

    state.cpu.pc = 0x0000;
    state.cpu.sp = 0xFF;

    state.bus.ram[0] = 0x20; // JSR
    state.bus.ram[1] = 0x00;
    state.bus.ram[2] = 0x01;

    for (0..6) |_| _ = state.tickCpuWithClock();

    // Return address ($0002) should be on stack
    const stack_low = state.busRead(0x01FE);
    const stack_high = state.busRead(0x01FF);
    const return_addr = (@as(u16, stack_high) << 8) | stack_low;

    try testing.expectEqual(@as(u16, 0x0002), return_addr);
    try testing.expectEqual(@as(u8, 0xFD), state.cpu.sp);
}

test "JSR: takes 6 cycles" {
    var state = createTestState();

    state.cpu.pc = 0x0000;
    state.cpu.sp = 0xFF;

    state.bus.ram[0] = 0x20;
    state.bus.ram[1] = 0x00;
    state.bus.ram[2] = 0x01;

    const start_cycles = state.clock.cpuCycles();

    for (0..6) |_| _ = state.tickCpuWithClock();

    try testing.expectEqual(@as(u64, start_cycles + 6), state.clock.cpuCycles());
}

// ============================================================================
// RTS Tests (Return from Subroutine)
// ============================================================================

test "RTS: returns to correct address" {
    var state = createTestState();

    // Setup stack with return address $0002
    state.cpu.sp = 0xFD;
    state.bus.ram[0x01FE] = 0x02; // Return low
    state.bus.ram[0x01FF] = 0x00; // Return high

    state.cpu.pc = 0x0100;
    state.bus.ram[0x100] = 0x60; // RTS

    for (0..6) |_| _ = state.tickCpuWithClock();

    try testing.expectEqual(@as(u16, 0x0003), state.cpu.pc); // $0002 + 1
}

test "RTS: restores stack pointer" {
    var state = createTestState();

    state.cpu.sp = 0xFD;
    state.bus.ram[0x01FE] = 0x02;
    state.bus.ram[0x01FF] = 0x00;

    state.cpu.pc = 0x0100;
    state.bus.ram[0x100] = 0x60;

    for (0..6) |_| _ = state.tickCpuWithClock();

    try testing.expectEqual(@as(u8, 0xFF), state.cpu.sp);
}

test "RTS: takes 6 cycles" {
    var state = createTestState();

    state.cpu.sp = 0xFD;
    state.bus.ram[0x01FE] = 0x02;
    state.bus.ram[0x01FF] = 0x00;

    state.cpu.pc = 0x0100;
    state.bus.ram[0x100] = 0x60;

    const start_cycles = state.clock.cpuCycles();

    for (0..6) |_| _ = state.tickCpuWithClock();

    try testing.expectEqual(@as(u64, start_cycles + 6), state.clock.cpuCycles());
}

// ============================================================================
// JSR + RTS Round Trip
// ============================================================================

test "JSR + RTS: complete round trip" {
    var state = createTestState();

    state.cpu.pc = 0x0000;
    state.cpu.sp = 0xFF;

    // JSR $0100 at $0000
    state.bus.ram[0] = 0x20;
    state.bus.ram[1] = 0x00;
    state.bus.ram[2] = 0x01;

    // RTS at $0100
    state.bus.ram[0x100] = 0x60;

    // Execute JSR
    for (0..6) |_| _ = state.tickCpuWithClock();
    try testing.expectEqual(@as(u16, 0x0100), state.cpu.pc);

    // Execute RTS
    for (0..6) |_| _ = state.tickCpuWithClock();
    try testing.expectEqual(@as(u16, 0x0003), state.cpu.pc);
    try testing.expectEqual(@as(u8, 0xFF), state.cpu.sp);
}

// ============================================================================
// RTI Tests (Return from Interrupt)
// ============================================================================

test "RTI: restores status and PC" {
    var state = createTestState();
    const test_ram = allocTestRam(&state);
    defer testing.allocator.free(test_ram);

    // Setup stack: status, PC low, PC high
    state.cpu.sp = 0xFC;
    state.bus.ram[0x01FD] = 0b11000011; // Status (N=1, V=1, Z=1, C=1)
    state.bus.ram[0x01FE] = 0x00; // PC low
    state.bus.ram[0x01FF] = 0x02; // PC high ($0200)

    state.cpu.pc = 0x0100;
    state.bus.ram[0x100] = 0x40; // RTI

    for (0..6) |_| _ = state.tickCpuWithClock();

    try testing.expect(state.cpu.p.negative);
    try testing.expect(state.cpu.p.overflow);
    try testing.expect(state.cpu.p.zero);
    try testing.expect(state.cpu.p.carry);
    try testing.expectEqual(@as(u16, 0x0200), state.cpu.pc);
}

test "RTI: takes 6 cycles" {
    var state = createTestState();
    const test_ram = allocTestRam(&state);
    defer testing.allocator.free(test_ram);

    state.cpu.sp = 0xFC;
    state.bus.ram[0x01FD] = 0x00;
    state.bus.ram[0x01FE] = 0x00;
    state.bus.ram[0x01FF] = 0x02;

    state.cpu.pc = 0x0100;
    state.bus.ram[0x100] = 0x40;

    const start_cycles = state.clock.cpuCycles();

    for (0..6) |_| _ = state.tickCpuWithClock();

    try testing.expectEqual(@as(u64, start_cycles + 6), state.clock.cpuCycles());
}

// ============================================================================
// BRK Tests (Software Interrupt)
// ============================================================================

test "BRK: pushes PC and status to stack" {
    var state = createTestState();
    const test_ram = allocTestRam(&state);
    defer testing.allocator.free(test_ram);

    state.cpu.pc = 0x0000;
    state.cpu.sp = 0xFF;
    state.cpu.p.carry = true;
    state.cpu.p.zero = true;

    state.bus.ram[0] = 0x00; // BRK

    // Setup IRQ vector at $FFFE/$FFFF using state.busWrite()
    state.busWrite(0xFFFE, 0x00); // IRQ vector low
    state.busWrite(0xFFFF, 0x03); // IRQ vector high ($0300)

    for (0..7) |_| _ = state.tickCpuWithClock();

    // Check PC on stack (PC+2 = $0002)
    const pc_high = state.busRead(0x01FF);
    const pc_low = state.busRead(0x01FE);
    try testing.expectEqual(@as(u8, 0x00), pc_high);
    try testing.expectEqual(@as(u8, 0x02), pc_low);

    // Check status on stack (B flag should be set)
    const status = state.busRead(0x01FD);
    try testing.expectEqual(@as(u8, 1), (status >> 4) & 1); // B flag

    // Check I flag set
    try testing.expect(state.cpu.p.interrupt);

    // Check jumped to vector
    try testing.expectEqual(@as(u16, 0x0300), state.cpu.pc);
}

test "BRK: takes 7 cycles" {
    var state = createTestState();
    const test_ram = allocTestRam(&state);
    defer testing.allocator.free(test_ram);

    state.cpu.pc = 0x0000;
    state.cpu.sp = 0xFF;

    state.bus.ram[0] = 0x00;
    state.busWrite(0xFFFE, 0x00);
    state.busWrite(0xFFFF, 0x03);

    const start_cycles = state.clock.cpuCycles();

    for (0..7) |_| _ = state.tickCpuWithClock();

    try testing.expectEqual(@as(u64, start_cycles + 7), state.clock.cpuCycles());
}

// ============================================================================
// BRK + RTI Round Trip
// ============================================================================

test "BRK + RTI: interrupt round trip" {
    var state = createTestState();
    const test_ram = allocTestRam(&state);
    defer testing.allocator.free(test_ram);

    state.cpu.pc = 0x0000;
    state.cpu.sp = 0xFF;
    state.cpu.p.carry = true;

    // BRK at $0000
    state.bus.ram[0] = 0x00;
    state.busWrite(0xFFFE, 0x00);
    state.busWrite(0xFFFF, 0x03);

    // RTI at $0300
    state.bus.ram[0x300] = 0x40;

    // Execute BRK
    for (0..7) |_| _ = state.tickCpuWithClock();
    try testing.expectEqual(@as(u16, 0x0300), state.cpu.pc);
    try testing.expect(state.cpu.p.interrupt);

    // Execute RTI
    for (0..6) |_| _ = state.tickCpuWithClock();
    try testing.expectEqual(@as(u16, 0x0002), state.cpu.pc);
    try testing.expect(state.cpu.p.carry); // Original carry restored
}
