//! Control Flow Opcode Integration Tests
//! Tests for JSR, RTS, RTI, BRK opcodes

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Cpu = RAMBO.Cpu;
const Bus = RAMBO.Bus;

// ============================================================================
// JSR Tests (Jump to Subroutine)
// ============================================================================

test "JSR: jumps to target address" {
    var cpu = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    // JSR $0100 at address $0000
    cpu.pc = 0x0000;
    cpu.sp = 0xFF;

    bus.ram[0] = 0x20; // JSR
    bus.ram[1] = 0x00; // Low byte of target
    bus.ram[2] = 0x01; // High byte ($0100)

    // Execute 6 cycles
    for (0..6) |_| _ = Cpu.Logic.tick(&cpu, &bus);

    try testing.expectEqual(@as(u16, 0x0100), cpu.pc);
}

test "JSR: pushes return address to stack" {
    var cpu = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    cpu.pc = 0x0000;
    cpu.sp = 0xFF;

    bus.ram[0] = 0x20; // JSR
    bus.ram[1] = 0x00;
    bus.ram[2] = 0x01;

    for (0..6) |_| _ = Cpu.Logic.tick(&cpu, &bus);

    // Return address ($0002) should be on stack
    const stack_low = bus.read(0x01FE);
    const stack_high = bus.read(0x01FF);
    const return_addr = (@as(u16, stack_high) << 8) | stack_low;

    try testing.expectEqual(@as(u16, 0x0002), return_addr);
    try testing.expectEqual(@as(u8, 0xFD), cpu.sp);
}

test "JSR: takes 6 cycles" {
    var cpu = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    cpu.pc = 0x0000;
    cpu.sp = 0xFF;

    bus.ram[0] = 0x20;
    bus.ram[1] = 0x00;
    bus.ram[2] = 0x01;

    const start_cycles = cpu.cycle_count;

    for (0..6) |_| _ = Cpu.Logic.tick(&cpu, &bus);

    try testing.expectEqual(@as(u64, start_cycles + 6), cpu.cycle_count);
}

// ============================================================================
// RTS Tests (Return from Subroutine)
// ============================================================================

test "RTS: returns to correct address" {
    var cpu = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    // Setup stack with return address $0002
    cpu.sp = 0xFD;
    bus.ram[0x01FE] = 0x02; // Return low
    bus.ram[0x01FF] = 0x00; // Return high

    cpu.pc = 0x0100;
    bus.ram[0x100] = 0x60; // RTS

    for (0..6) |_| _ = Cpu.Logic.tick(&cpu, &bus);

    try testing.expectEqual(@as(u16, 0x0003), cpu.pc); // $0002 + 1
}

test "RTS: restores stack pointer" {
    var cpu = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    cpu.sp = 0xFD;
    bus.ram[0x01FE] = 0x02;
    bus.ram[0x01FF] = 0x00;

    cpu.pc = 0x0100;
    bus.ram[0x100] = 0x60;

    for (0..6) |_| _ = Cpu.Logic.tick(&cpu, &bus);

    try testing.expectEqual(@as(u8, 0xFF), cpu.sp);
}

test "RTS: takes 6 cycles" {
    var cpu = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    cpu.sp = 0xFD;
    bus.ram[0x01FE] = 0x02;
    bus.ram[0x01FF] = 0x00;

    cpu.pc = 0x0100;
    bus.ram[0x100] = 0x60;

    const start_cycles = cpu.cycle_count;

    for (0..6) |_| _ = Cpu.Logic.tick(&cpu, &bus);

    try testing.expectEqual(@as(u64, start_cycles + 6), cpu.cycle_count);
}

// ============================================================================
// JSR + RTS Round Trip
// ============================================================================

test "JSR + RTS: complete round trip" {
    var cpu = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    cpu.pc = 0x0000;
    cpu.sp = 0xFF;

    // JSR $0100 at $0000
    bus.ram[0] = 0x20;
    bus.ram[1] = 0x00;
    bus.ram[2] = 0x01;

    // RTS at $0100
    bus.ram[0x100] = 0x60;

    // Execute JSR
    for (0..6) |_| _ = Cpu.Logic.tick(&cpu, &bus);
    try testing.expectEqual(@as(u16, 0x0100), cpu.pc);

    // Execute RTS
    for (0..6) |_| _ = Cpu.Logic.tick(&cpu, &bus);
    try testing.expectEqual(@as(u16, 0x0003), cpu.pc);
    try testing.expectEqual(@as(u8, 0xFF), cpu.sp);
}

// ============================================================================
// RTI Tests (Return from Interrupt)
// ============================================================================

test "RTI: restores status and PC" {
    var cpu = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    // Setup stack: status, PC low, PC high
    cpu.sp = 0xFC;
    bus.ram[0x01FD] = 0b11000011; // Status (N=1, V=1, Z=1, C=1)
    bus.ram[0x01FE] = 0x00;       // PC low
    bus.ram[0x01FF] = 0x02;       // PC high ($0200)

    cpu.pc = 0x0100;
    bus.ram[0x100] = 0x40; // RTI

    for (0..6) |_| _ = Cpu.Logic.tick(&cpu, &bus);

    try testing.expect(cpu.p.negative);
    try testing.expect(cpu.p.overflow);
    try testing.expect(cpu.p.zero);
    try testing.expect(cpu.p.carry);
    try testing.expectEqual(@as(u16, 0x0200), cpu.pc);
}

test "RTI: takes 6 cycles" {
    var cpu = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    cpu.sp = 0xFC;
    bus.ram[0x01FD] = 0x00;
    bus.ram[0x01FE] = 0x00;
    bus.ram[0x01FF] = 0x02;

    cpu.pc = 0x0100;
    bus.ram[0x100] = 0x40;

    const start_cycles = cpu.cycle_count;

    for (0..6) |_| _ = Cpu.Logic.tick(&cpu, &bus);

    try testing.expectEqual(@as(u64, start_cycles + 6), cpu.cycle_count);
}

// ============================================================================
// BRK Tests (Software Interrupt)
// ============================================================================

test "BRK: pushes PC and status to stack" {
    var cpu = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    // Setup test RAM for ROM space (32KB to cover $8000-$FFFF)
    var test_ram = [_]u8{0} ** 32768;
    bus.test_ram = &test_ram;

    cpu.pc = 0x0000;
    cpu.sp = 0xFF;
    cpu.p.carry = true;
    cpu.p.zero = true;

    bus.ram[0] = 0x00; // BRK

    // Setup IRQ vector at $FFFE/$FFFF using bus.write()
    bus.write(0xFFFE, 0x00); // IRQ vector low
    bus.write(0xFFFF, 0x03); // IRQ vector high ($0300)

    for (0..7) |_| _ = Cpu.Logic.tick(&cpu, &bus);

    // Check PC on stack (PC+2 = $0002)
    const pc_high = bus.read(0x01FF);
    const pc_low = bus.read(0x01FE);
    try testing.expectEqual(@as(u8, 0x00), pc_high);
    try testing.expectEqual(@as(u8, 0x02), pc_low);

    // Check status on stack (B flag should be set)
    const status = bus.read(0x01FD);
    try testing.expectEqual(@as(u8, 1), (status >> 4) & 1); // B flag

    // Check I flag set
    try testing.expect(cpu.p.interrupt);

    // Check jumped to vector
    try testing.expectEqual(@as(u16, 0x0300), cpu.pc);
}

test "BRK: takes 7 cycles" {
    var cpu = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    // Setup test RAM for ROM space
    var test_ram = [_]u8{0} ** 32768;
    bus.test_ram = &test_ram;

    cpu.pc = 0x0000;
    cpu.sp = 0xFF;

    bus.ram[0] = 0x00;
    bus.write(0xFFFE, 0x00);
    bus.write(0xFFFF, 0x03);

    const start_cycles = cpu.cycle_count;

    for (0..7) |_| _ = Cpu.Logic.tick(&cpu, &bus);

    try testing.expectEqual(@as(u64, start_cycles + 7), cpu.cycle_count);
}

// ============================================================================
// BRK + RTI Round Trip
// ============================================================================

test "BRK + RTI: interrupt round trip" {
    var cpu = Cpu.Logic.init();
    var bus = Bus.Logic.init();

    // Setup test RAM for ROM space
    var test_ram = [_]u8{0} ** 32768;
    bus.test_ram = &test_ram;

    cpu.pc = 0x0000;
    cpu.sp = 0xFF;
    cpu.p.carry = true;

    // BRK at $0000
    bus.ram[0] = 0x00;
    bus.write(0xFFFE, 0x00);
    bus.write(0xFFFF, 0x03);

    // RTI at $0300
    bus.ram[0x300] = 0x40;

    // Execute BRK
    for (0..7) |_| _ = Cpu.Logic.tick(&cpu, &bus);
    try testing.expectEqual(@as(u16, 0x0300), cpu.pc);
    try testing.expect(cpu.p.interrupt);

    // Execute RTI
    for (0..6) |_| _ = Cpu.Logic.tick(&cpu, &bus);
    try testing.expectEqual(@as(u16, 0x0002), cpu.pc);
    try testing.expect(cpu.p.carry); // Original carry restored
}
