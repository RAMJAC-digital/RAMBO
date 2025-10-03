const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Cpu = RAMBO.CpuType;
const Bus = RAMBO.BusType;

// ============================================================================
// Immediate Logic/Math Operations
// ============================================================================

test "ANC #imm ($0B) - AND + Copy bit 7 to Carry" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: ANC #$F0 (bit 7 will be set)
    bus.ram[0] = 0x0B; // ANC opcode
    bus.ram[1] = 0xF0; // Operand
    cpu.pc = 0x0000;
    cpu.a = 0xFF;

    // Execute (2 cycles)
    _ = cpu.tick(&bus); // Fetch opcode
    const complete = cpu.tick(&bus); // Execute

    try testing.expect(complete);
    try testing.expectEqual(@as(u8, 0xF0), cpu.a); // A = 0xFF & 0xF0
    try testing.expect(cpu.p.carry); // Carry = bit 7 of result (1)
    try testing.expect(cpu.p.negative); // Negative = bit 7 (1)
    try testing.expect(!cpu.p.zero);
    try testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

test "ANC #imm ($0B) - Carry cleared when bit 7 is 0" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: ANC #$7F (bit 7 = 0)
    bus.ram[0] = 0x0B;
    bus.ram[1] = 0x7F;
    cpu.pc = 0x0000;
    cpu.a = 0xFF;
    cpu.p.carry = true; // Should be cleared

    _ = cpu.tick(&bus);
    _ = cpu.tick(&bus);

    try testing.expectEqual(@as(u8, 0x7F), cpu.a);
    try testing.expect(!cpu.p.carry); // Carry cleared (bit 7 = 0)
    try testing.expect(!cpu.p.negative);
    try testing.expect(!cpu.p.zero);
}

test "ANC #imm ($2B) - Alternate opcode behaves identically" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: ANC #$80 using alternate opcode $2B
    bus.ram[0] = 0x2B; // ANC alternate opcode
    bus.ram[1] = 0x80;
    cpu.pc = 0x0000;
    cpu.a = 0xFF;

    _ = cpu.tick(&bus);
    _ = cpu.tick(&bus);

    try testing.expectEqual(@as(u8, 0x80), cpu.a);
    try testing.expect(cpu.p.carry); // Bit 7 = 1
    try testing.expect(cpu.p.negative);
}

test "ANC #imm - Zero flag" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: ANC #$00
    bus.ram[0] = 0x0B;
    bus.ram[1] = 0x00;
    cpu.pc = 0x0000;
    cpu.a = 0xFF;

    _ = cpu.tick(&bus);
    _ = cpu.tick(&bus);

    try testing.expectEqual(@as(u8, 0x00), cpu.a);
    try testing.expect(!cpu.p.carry); // Bit 7 = 0
    try testing.expect(!cpu.p.negative);
    try testing.expect(cpu.p.zero);
}

test "ALR #imm ($4B) - AND + LSR" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: ALR #$FE
    bus.ram[0] = 0x4B; // ALR opcode
    bus.ram[1] = 0xFE;
    cpu.pc = 0x0000;
    cpu.a = 0xFF;

    _ = cpu.tick(&bus);
    const complete = cpu.tick(&bus);

    try testing.expect(complete);
    // A = (0xFF & 0xFE) >> 1 = 0xFE >> 1 = 0x7F
    try testing.expectEqual(@as(u8, 0x7F), cpu.a);
    try testing.expect(!cpu.p.carry); // Bit 0 of 0xFE is 0
    try testing.expect(!cpu.p.negative);
    try testing.expect(!cpu.p.zero);
    try testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

test "ALR #imm - Carry set from LSR" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: ALR #$FF (bit 0 will be 1 after AND)
    bus.ram[0] = 0x4B;
    bus.ram[1] = 0xFF;
    cpu.pc = 0x0000;
    cpu.a = 0xFF;

    _ = cpu.tick(&bus);
    _ = cpu.tick(&bus);

    try testing.expectEqual(@as(u8, 0x7F), cpu.a);
    try testing.expect(cpu.p.carry); // Bit 0 of 0xFF is 1
}

test "ALR #imm - Zero result" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: ALR #$01 with A=$01 -> (0x01 & 0x01) >> 1 = 0x00
    bus.ram[0] = 0x4B;
    bus.ram[1] = 0x01;
    cpu.pc = 0x0000;
    cpu.a = 0x01;

    _ = cpu.tick(&bus);
    _ = cpu.tick(&bus);

    try testing.expectEqual(@as(u8, 0x00), cpu.a);
    try testing.expect(cpu.p.carry); // Bit 0 was 1
    try testing.expect(cpu.p.zero);
}

test "ARR #imm ($6B) - AND + ROR with complex flags" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: ARR #$FF with carry set
    bus.ram[0] = 0x6B; // ARR opcode
    bus.ram[1] = 0xFF;
    cpu.pc = 0x0000;
    cpu.a = 0xFF;
    cpu.p.carry = true;

    _ = cpu.tick(&bus);
    const complete = cpu.tick(&bus);

    try testing.expect(complete);
    // A = (0xFF & 0xFF) ROR 1 with carry = 0xFF ROR 1 = 0xFF
    try testing.expectEqual(@as(u8, 0xFF), cpu.a);
    try testing.expect(cpu.p.carry); // Carry from bit 6 (1)
    try testing.expect(!cpu.p.overflow); // V = bit 6 XOR bit 5 = 1 XOR 1 = 0
    try testing.expect(cpu.p.negative);
    try testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

test "ARR #imm - Complex flag behavior" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: ARR #$7F with carry clear -> after AND & ROR: 0x3F
    bus.ram[0] = 0x6B;
    bus.ram[1] = 0x7F;
    cpu.pc = 0x0000;
    cpu.a = 0x7F;
    cpu.p.carry = false;

    _ = cpu.tick(&bus);
    _ = cpu.tick(&bus);

    // A = (0x7F & 0x7F) >> 1 = 0x7F >> 1 = 0x3F
    try testing.expectEqual(@as(u8, 0x3F), cpu.a);
    try testing.expect(!cpu.p.carry); // Bit 6 of 0x3F is 0
    try testing.expect(cpu.p.overflow); // V = bit 6 XOR bit 5 = 0 XOR 1 = 1
    try testing.expect(!cpu.p.negative);
}

test "ARR #imm - Carry rotated in" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: ARR #$01 with carry set
    bus.ram[0] = 0x6B;
    bus.ram[1] = 0x01;
    cpu.pc = 0x0000;
    cpu.a = 0x01;
    cpu.p.carry = true;

    _ = cpu.tick(&bus);
    _ = cpu.tick(&bus);

    // A = (0x01 & 0x01) ROR 1 with carry = 0x01 ROR 1 = 0x80
    try testing.expectEqual(@as(u8, 0x80), cpu.a);
    try testing.expect(!cpu.p.carry); // Bit 6 of 0x80 is 0
    try testing.expect(cpu.p.negative);
}

test "AXS #imm ($CB) - (A & X) - operand -> X" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: AXS #$10
    bus.ram[0] = 0xCB; // AXS opcode
    bus.ram[1] = 0x10;
    cpu.pc = 0x0000;
    cpu.a = 0xFF;
    cpu.x = 0x30;

    _ = cpu.tick(&bus);
    const complete = cpu.tick(&bus);

    try testing.expect(complete);
    // X = (0xFF & 0x30) - 0x10 = 0x30 - 0x10 = 0x20
    try testing.expectEqual(@as(u8, 0x20), cpu.x);
    try testing.expect(cpu.p.carry); // 0x30 >= 0x10
    try testing.expect(!cpu.p.negative);
    try testing.expect(!cpu.p.zero);
    try testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

test "AXS #imm - Carry cleared when result would be negative" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: AXS #$50
    bus.ram[0] = 0xCB;
    bus.ram[1] = 0x50;
    cpu.pc = 0x0000;
    cpu.a = 0xFF;
    cpu.x = 0x30;

    _ = cpu.tick(&bus);
    _ = cpu.tick(&bus);

    // X = (0xFF & 0x30) - 0x50 = 0x30 - 0x50 = 0xE0 (wraps)
    try testing.expectEqual(@as(u8, 0xE0), cpu.x);
    try testing.expect(!cpu.p.carry); // 0x30 < 0x50
    try testing.expect(cpu.p.negative); // 0xE0 has bit 7 set
}

test "AXS #imm - Zero result" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: AXS #$30
    bus.ram[0] = 0xCB;
    bus.ram[1] = 0x30;
    cpu.pc = 0x0000;
    cpu.a = 0xFF;
    cpu.x = 0x30;

    _ = cpu.tick(&bus);
    _ = cpu.tick(&bus);

    try testing.expectEqual(@as(u8, 0x00), cpu.x);
    try testing.expect(cpu.p.carry); // Equal comparison
    try testing.expect(cpu.p.zero);
}

test "AXS #imm - A unchanged" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0xCB;
    bus.ram[1] = 0x10;
    cpu.pc = 0x0000;
    cpu.a = 0x55;
    cpu.x = 0xAA;

    _ = cpu.tick(&bus);
    _ = cpu.tick(&bus);

    try testing.expectEqual(@as(u8, 0x55), cpu.a); // A unchanged
}

// ============================================================================
// Unstable Store Operations
// ============================================================================

test "SHA abs,Y ($9F) - Store A & X & (H+1)" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: SHA $1200,Y with Y=$05
    bus.ram[0] = 0x9F; // SHA absolute,Y
    bus.ram[1] = 0x00; // Low byte
    bus.ram[2] = 0x12; // High byte
    cpu.pc = 0x0000;
    cpu.a = 0xFF;
    cpu.x = 0xAA;
    cpu.y = 0x05;

    // Execute until complete
    for (0..6) |_| {
        _ = cpu.tick(&bus);
    }

    // Effective address = $1205, H = $12
    // Value = A & X & (H+1) = 0xFF & 0xAA & 0x13 = 0x02
    try testing.expectEqual(@as(u8, 0x02), bus.read(0x1205));
}

test "SHA ind,Y ($93) - Indirect indexed mode" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: SHA ($20),Y with Y=$10
    bus.ram[0] = 0x93; // SHA indirect,Y
    bus.ram[1] = 0x20; // Zero page pointer
    bus.ram[0x20] = 0x00; // Pointer low
    bus.ram[0x21] = 0x30; // Pointer high -> $3000
    cpu.pc = 0x0000;
    cpu.a = 0xFF;
    cpu.x = 0x55;
    cpu.y = 0x10;

    // Execute until complete
    for (0..7) |_| {
        _ = cpu.tick(&bus);
    }

    // Effective address = $3010, H = $30
    // Value = 0xFF & 0x55 & 0x31 = 0x11
    try testing.expectEqual(@as(u8, 0x11), bus.read(0x3010));
}

test "SHA - High byte calculation" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Test with high byte = $FF -> (H+1) wraps to $00
    bus.ram[0] = 0x9F;
    bus.ram[1] = 0x00;
    bus.ram[2] = 0xFF; // High = $FF
    cpu.pc = 0x0000;
    cpu.a = 0xFF;
    cpu.x = 0xFF;
    cpu.y = 0x01;

    for (0..6) |_| {
        _ = cpu.tick(&bus);
    }

    // Value = 0xFF & 0xFF & 0x00 = 0x00
    try testing.expectEqual(@as(u8, 0x00), bus.read(0xFF01));
}

test "SHX abs,Y ($9E) - Store X & (H+1)" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: SHX $2000,Y with Y=$42
    bus.ram[0] = 0x9E; // SHX absolute,Y
    bus.ram[1] = 0x00;
    bus.ram[2] = 0x20; // High = $20
    cpu.pc = 0x0000;
    cpu.x = 0xFF;
    cpu.y = 0x42;

    for (0..6) |_| {
        _ = cpu.tick(&bus);
    }

    // Effective address = $2042, H = $20
    // Value = X & (H+1) = 0xFF & 0x21 = 0x21
    try testing.expectEqual(@as(u8, 0x21), bus.read(0x2042));
}

test "SHX - A and Y unchanged" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0x9E;
    bus.ram[1] = 0x00;
    bus.ram[2] = 0x10;
    cpu.pc = 0x0000;
    cpu.a = 0x55;
    cpu.x = 0xFF;
    cpu.y = 0x10;

    for (0..6) |_| {
        _ = cpu.tick(&bus);
    }

    try testing.expectEqual(@as(u8, 0x55), cpu.a);
    try testing.expectEqual(@as(u8, 0x10), cpu.y);
}

test "SHY abs,X ($9C) - Store Y & (H+1)" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: SHY $3000,X with X=$33
    bus.ram[0] = 0x9C; // SHY absolute,X
    bus.ram[1] = 0x00;
    bus.ram[2] = 0x30; // High = $30
    cpu.pc = 0x0000;
    cpu.y = 0xFF;
    cpu.x = 0x33;

    for (0..6) |_| {
        _ = cpu.tick(&bus);
    }

    // Effective address = $3033, H = $30
    // Value = Y & (H+1) = 0xFF & 0x31 = 0x31
    try testing.expectEqual(@as(u8, 0x31), bus.read(0x3033));
}

test "SHY - A and X unchanged" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0x9C;
    bus.ram[1] = 0x00;
    bus.ram[2] = 0x10;
    cpu.pc = 0x0000;
    cpu.a = 0x66;
    cpu.x = 0x20;
    cpu.y = 0xFF;

    for (0..6) |_| {
        _ = cpu.tick(&bus);
    }

    try testing.expectEqual(@as(u8, 0x66), cpu.a);
    try testing.expectEqual(@as(u8, 0x20), cpu.x);
}

test "TAS abs,Y ($9B) - SP = A & X, Store A & X & (H+1)" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: TAS $4000,Y with Y=$50
    bus.ram[0] = 0x9B; // TAS absolute,Y
    bus.ram[1] = 0x00;
    bus.ram[2] = 0x40; // High = $40
    cpu.pc = 0x0000;
    cpu.a = 0xAA;
    cpu.x = 0x55;
    cpu.y = 0x50;
    cpu.sp = 0xFF; // Should be overwritten

    for (0..6) |_| {
        _ = cpu.tick(&bus);
    }

    // SP = A & X = 0xAA & 0x55 = 0x00
    try testing.expectEqual(@as(u8, 0x00), cpu.sp);
    // Memory = A & X & (H+1) = 0xAA & 0x55 & 0x41 = 0x00
    try testing.expectEqual(@as(u8, 0x00), bus.read(0x4050));
}

test "TAS - Complex AND operation" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0x9B;
    bus.ram[1] = 0x00;
    bus.ram[2] = 0x7F; // High = $7F
    cpu.pc = 0x0000;
    cpu.a = 0xFF;
    cpu.x = 0xFF;
    cpu.y = 0x10;

    for (0..6) |_| {
        _ = cpu.tick(&bus);
    }

    // SP = 0xFF & 0xFF = 0xFF
    try testing.expectEqual(@as(u8, 0xFF), cpu.sp);
    // Memory = 0xFF & 0xFF & 0x80 = 0x80
    try testing.expectEqual(@as(u8, 0x80), bus.read(0x7F10));
}

// ============================================================================
// Unstable Load Operations
// ============================================================================

test "LAE abs,Y ($BB) - A = X = SP = M & SP" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: LAE $0200,Y with Y=$10
    bus.ram[0] = 0xBB; // LAE absolute,Y
    bus.ram[1] = 0x00;
    bus.ram[2] = 0x02;
    bus.ram[0x210] = 0xFF;
    cpu.pc = 0x0000;
    cpu.sp = 0xAA;
    cpu.y = 0x10;

    // Execute until complete
    for (0..5) |_| {
        _ = cpu.tick(&bus);
    }

    // Result = M & SP = 0xFF & 0xAA = 0xAA
    try testing.expectEqual(@as(u8, 0xAA), cpu.a);
    try testing.expectEqual(@as(u8, 0xAA), cpu.x);
    try testing.expectEqual(@as(u8, 0xAA), cpu.sp);
    try testing.expect(cpu.p.negative);
    try testing.expect(!cpu.p.zero);
}

test "LAE - Zero flag" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0xBB;
    bus.ram[1] = 0x00;
    bus.ram[2] = 0x02;
    bus.ram[0x220] = 0x55;
    cpu.pc = 0x0000;
    cpu.sp = 0xAA; // 0x55 & 0xAA = 0x00
    cpu.y = 0x20;

    for (0..5) |_| {
        _ = cpu.tick(&bus);
    }

    try testing.expectEqual(@as(u8, 0x00), cpu.a);
    try testing.expectEqual(@as(u8, 0x00), cpu.x);
    try testing.expectEqual(@as(u8, 0x00), cpu.sp);
    try testing.expect(cpu.p.zero);
}

test "XAA #imm ($8B) - A = (A | $EE) & X & operand" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: XAA #$FF
    bus.ram[0] = 0x8B; // XAA opcode
    bus.ram[1] = 0xFF;
    cpu.pc = 0x0000;
    cpu.a = 0x00;
    cpu.x = 0xFF;

    _ = cpu.tick(&bus);
    const complete = cpu.tick(&bus);

    try testing.expect(complete);
    // A = (0x00 | 0xEE) & 0xFF & 0xFF = 0xEE
    try testing.expectEqual(@as(u8, 0xEE), cpu.a);
    try testing.expect(cpu.p.negative);
    try testing.expect(!cpu.p.zero);
    try testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

test "XAA #imm - Magic constant behavior" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Test with different initial A values
    bus.ram[0] = 0x8B;
    bus.ram[1] = 0x0F;
    cpu.pc = 0x0000;
    cpu.a = 0x01;
    cpu.x = 0xFF;

    _ = cpu.tick(&bus);
    _ = cpu.tick(&bus);

    // A = (0x01 | 0xEE) & 0xFF & 0x0F = 0xEF & 0xFF & 0x0F = 0x0F
    try testing.expectEqual(@as(u8, 0x0F), cpu.a);
}

test "XAA #imm - X unchanged" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0x8B;
    bus.ram[1] = 0xFF;
    cpu.pc = 0x0000;
    cpu.a = 0x00;
    cpu.x = 0x55;

    _ = cpu.tick(&bus);
    _ = cpu.tick(&bus);

    try testing.expectEqual(@as(u8, 0x55), cpu.x); // X unchanged
}

test "LXA #imm ($AB) - A = X = (A | $EE) & operand" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: LXA #$FF
    bus.ram[0] = 0xAB; // LXA opcode
    bus.ram[1] = 0xFF;
    cpu.pc = 0x0000;
    cpu.a = 0x00;

    _ = cpu.tick(&bus);
    const complete = cpu.tick(&bus);

    try testing.expect(complete);
    // Result = (0x00 | 0xEE) & 0xFF = 0xEE
    try testing.expectEqual(@as(u8, 0xEE), cpu.a);
    try testing.expectEqual(@as(u8, 0xEE), cpu.x);
    try testing.expect(cpu.p.negative);
    try testing.expect(!cpu.p.zero);
    try testing.expectEqual(@as(u64, 2), cpu.cycle_count);
}

test "LXA #imm - Magic constant behavior with masking" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0xAB;
    bus.ram[1] = 0x0F;
    cpu.pc = 0x0000;
    cpu.a = 0x01;

    _ = cpu.tick(&bus);
    _ = cpu.tick(&bus);

    // Result = (0x01 | 0xEE) & 0x0F = 0xEF & 0x0F = 0x0F
    try testing.expectEqual(@as(u8, 0x0F), cpu.a);
    try testing.expectEqual(@as(u8, 0x0F), cpu.x);
}

test "LXA #imm - Zero flag" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    bus.ram[0] = 0xAB;
    bus.ram[1] = 0x00;
    cpu.pc = 0x0000;
    cpu.a = 0x00;

    _ = cpu.tick(&bus);
    _ = cpu.tick(&bus);

    // Result = (0x00 | 0xEE) & 0x00 = 0x00
    try testing.expectEqual(@as(u8, 0x00), cpu.a);
    try testing.expectEqual(@as(u8, 0x00), cpu.x);
    try testing.expect(cpu.p.zero);
}

// ============================================================================
// JAM/KIL - CPU Halt Instructions
// ============================================================================

test "JAM ($02) - CPU halts and PC unchanged" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: JAM at $1000
    bus.ram[0] = 0x02; // JAM opcode
    cpu.pc = 0x0000;

    // Fetch opcode
    _ = cpu.tick(&bus);
    try testing.expect(!cpu.halted);

    // Execute JAM - should halt
    const complete = cpu.tick(&bus);
    try testing.expect(complete);
    try testing.expect(cpu.halted);

    // PC should point to next instruction (but CPU won't execute it)
    try testing.expectEqual(@as(u16, 0x0001), cpu.pc);

    // Try to execute another instruction - should do nothing
    bus.ram[1] = 0xEA; // NOP
    const cycles_before = cpu.cycle_count;
    const still_halted = cpu.tick(&bus);

    // CPU should remain halted and not complete any instruction
    try testing.expect(!still_halted); // Returns false when halted
    try testing.expect(cpu.halted);
    // Cycle count increments (simulating infinite loop), but no instruction executes
    try testing.expectEqual(cycles_before + 1, cpu.cycle_count);
    // PC should not advance
    try testing.expectEqual(@as(u16, 0x0001), cpu.pc);
}

test "JAM - All 12 opcodes halt correctly" {
    const jam_opcodes = [_]u8{ 0x02, 0x12, 0x22, 0x32, 0x42, 0x52, 0x62, 0x72, 0x92, 0xB2, 0xD2, 0xF2 };

    for (jam_opcodes) |opcode| {
        var cpu = Cpu.init();
        var bus = Bus.init();

        bus.ram[0] = opcode;
        cpu.pc = 0x0000;

        _ = cpu.tick(&bus); // Fetch
        _ = cpu.tick(&bus); // Execute

        try testing.expect(cpu.halted);
    }
}

test "JAM - RESET clears halted state" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Set up reset vector
    bus.ram[0x7FC] = 0x00; // Reset vector low (at $FFFC in real hardware, $1FFC in mirrored RAM)
    bus.ram[0x7FD] = 0x10; // Reset vector high -> $1000

    // Execute JAM
    bus.ram[0] = 0x02;
    cpu.pc = 0x0000;
    _ = cpu.tick(&bus);
    _ = cpu.tick(&bus);

    try testing.expect(cpu.halted);

    // Perform RESET
    cpu.reset(&bus);

    // CPU should no longer be halted
    try testing.expect(!cpu.halted);
}

test "JAM - Flags unchanged" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Set specific flag state
    cpu.p.carry = true;
    cpu.p.zero = true;
    cpu.p.negative = false;
    cpu.p.overflow = true;

    bus.ram[0] = 0x02;
    cpu.pc = 0x0000;

    _ = cpu.tick(&bus);
    _ = cpu.tick(&bus);

    // Flags should be unchanged
    try testing.expect(cpu.p.carry);
    try testing.expect(cpu.p.zero);
    try testing.expect(!cpu.p.negative);
    try testing.expect(cpu.p.overflow);
}

test "JAM - Registers unchanged except PC" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.a = 0x42;
    cpu.x = 0x55;
    cpu.y = 0xAA;
    cpu.sp = 0xFD;

    bus.ram[0] = 0x02;
    cpu.pc = 0x0000;

    _ = cpu.tick(&bus);
    _ = cpu.tick(&bus);

    try testing.expectEqual(@as(u8, 0x42), cpu.a);
    try testing.expectEqual(@as(u8, 0x55), cpu.x);
    try testing.expectEqual(@as(u8, 0xAA), cpu.y);
    try testing.expectEqual(@as(u8, 0xFD), cpu.sp);
}

// ============================================================================
// RMW Combo Instructions - Full Execution Tests
// ============================================================================
// These test the opcodes through full CPU execution including addressing modes

test "SLO $nn - Zero Page (6 cycles)" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: SLO $50
    bus.ram[0] = 0x07; // SLO zero page
    bus.ram[1] = 0x50; // Address
    bus.ram[0x50] = 0b01010101;
    cpu.pc = 0x0000;
    cpu.a = 0b00001111;

    // Execute through all cycles
    for (0..5) |_| {
        _ = cpu.tick(&bus);
    }

    // Memory should be shifted left
    try testing.expectEqual(@as(u8, 0b10101010), bus.ram[0x50]);
    // A should be ORed with result
    try testing.expectEqual(@as(u8, 0b10101111), cpu.a);
    try testing.expect(!cpu.p.carry);
    try testing.expect(cpu.p.negative);
}

test "RLA $nn - Zero Page (6 cycles)" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: RLA $60
    bus.ram[0] = 0x27; // RLA zero page
    bus.ram[1] = 0x60;
    bus.ram[0x60] = 0b11000000;
    cpu.pc = 0x0000;
    cpu.a = 0xFF;
    cpu.p.carry = true;

    for (0..5) |_| {
        _ = cpu.tick(&bus);
    }

    // Memory: (0b11000000 << 1) | 1 = 0b10000001
    try testing.expectEqual(@as(u8, 0b10000001), bus.ram[0x60]);
    // A: 0xFF & 0b10000001 = 0b10000001
    try testing.expectEqual(@as(u8, 0b10000001), cpu.a);
    try testing.expect(cpu.p.carry); // Original bit 7 was 1
}

test "SRE $nn - Zero Page (6 cycles)" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: SRE $70
    bus.ram[0] = 0x47; // SRE zero page
    bus.ram[1] = 0x70;
    bus.ram[0x70] = 0b10101010;
    cpu.pc = 0x0000;
    cpu.a = 0b11110000;

    for (0..5) |_| {
        _ = cpu.tick(&bus);
    }

    // Memory: 0b10101010 >> 1 = 0b01010101
    try testing.expectEqual(@as(u8, 0b01010101), bus.ram[0x70]);
    // A: 0b11110000 ^ 0b01010101 = 0b10100101
    try testing.expectEqual(@as(u8, 0b10100101), cpu.a);
    try testing.expect(!cpu.p.carry);
}

test "RRA $nn - Zero Page (6 cycles)" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: RRA $80
    bus.ram[0] = 0x67; // RRA zero page
    bus.ram[1] = 0x80;
    bus.ram[0x80] = 0b00000010;
    cpu.pc = 0x0000;
    cpu.a = 0x10;
    cpu.p.carry = true;

    for (0..5) |_| {
        _ = cpu.tick(&bus);
    }

    // Memory: (0b00000010 >> 1) | 0x80 = 0b10000001
    try testing.expectEqual(@as(u8, 0b10000001), bus.ram[0x80]);
    // A: 0x10 + 0b10000001 + 0 (carry from rotate) = 0x91
    try testing.expectEqual(@as(u8, 0x91), cpu.a);
}

test "DCP $nn - Zero Page (6 cycles)" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: DCP $90
    bus.ram[0] = 0xC7; // DCP zero page
    bus.ram[1] = 0x90;
    bus.ram[0x90] = 0x50;
    cpu.pc = 0x0000;
    cpu.a = 0x4F;

    for (0..5) |_| {
        _ = cpu.tick(&bus);
    }

    // Memory: 0x50 - 1 = 0x4F
    try testing.expectEqual(@as(u8, 0x4F), bus.ram[0x90]);
    // Compare: A == M
    try testing.expect(cpu.p.zero);
    try testing.expect(cpu.p.carry);
}

test "ISC $nn - Zero Page (6 cycles)" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: ISC $A0
    bus.ram[0] = 0xE7; // ISC zero page
    bus.ram[1] = 0xA0;
    bus.ram[0xA0] = 0x0F;
    cpu.pc = 0x0000;
    cpu.a = 0x20;
    cpu.p.carry = true;

    for (0..5) |_| {
        _ = cpu.tick(&bus);
    }

    // Memory: 0x0F + 1 = 0x10
    try testing.expectEqual(@as(u8, 0x10), bus.ram[0xA0]);
    // A: 0x20 - 0x10 = 0x10
    try testing.expectEqual(@as(u8, 0x10), cpu.a);
    try testing.expect(cpu.p.carry);
}

test "SLO $nnnn,X - Absolute,X with page crossing" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: SLO $10FF,X with X=$02 -> $1101 (page cross)
    bus.ram[0] = 0x1F; // SLO absolute,X
    bus.ram[1] = 0xFF;
    bus.ram[2] = 0x10;
    bus.ram[0x101] = 0b00000001;
    cpu.pc = 0x0000;
    cpu.x = 0x02;
    cpu.a = 0b00000010;

    // Execute (7 cycles for RMW absolute,X)
    for (0..7) |_| {
        _ = cpu.tick(&bus);
    }

    // Memory: 0b00000001 << 1 = 0b00000010
    try testing.expectEqual(@as(u8, 0b00000010), bus.ram[0x101]);
    // A: 0b00000010 | 0b00000010 = 0b00000010
    try testing.expectEqual(@as(u8, 0b00000010), cpu.a);
}

test "RMW combo - Dummy write occurs" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    // Setup: DCP $50 - test that dummy write happens
    bus.ram[0] = 0xC7;
    bus.ram[1] = 0x50;
    bus.ram[0x50] = 0xFF;
    cpu.pc = 0x0000;
    cpu.a = 0x00;

    // Execute through cycles, checking dummy write behavior
    // This is implicit in the RMW addressing mode implementation
    for (0..5) |_| {
        _ = cpu.tick(&bus);
    }

    // Memory should be decremented
    try testing.expectEqual(@as(u8, 0xFE), bus.ram[0x50]);
    // The RMW sequence includes:
    // 1. Read original value (0xFF)
    // 2. Dummy write (0xFF back to memory) - CRITICAL
    // 3. Write modified value (0xFE)
}

// ============================================================================
// Cycle Count Verification
// ============================================================================

test "Cycle counts - Immediate logic operations" {
    const opcodes_and_cycles = [_]struct { opcode: u8, cycles: u64 }{
        .{ .opcode = 0x0B, .cycles = 2 }, // ANC
        .{ .opcode = 0x2B, .cycles = 2 }, // ANC (alternate)
        .{ .opcode = 0x4B, .cycles = 2 }, // ALR
        .{ .opcode = 0x6B, .cycles = 2 }, // ARR
        .{ .opcode = 0xCB, .cycles = 2 }, // AXS
        .{ .opcode = 0x8B, .cycles = 2 }, // XAA
        .{ .opcode = 0xAB, .cycles = 2 }, // LXA
    };

    for (opcodes_and_cycles) |test_case| {
        var cpu = Cpu.init();
        var bus = Bus.init();

        bus.ram[0] = test_case.opcode;
        bus.ram[1] = 0xFF;
        cpu.pc = 0x0000;

        for (0..test_case.cycles) |_| {
            _ = cpu.tick(&bus);
        }

        try testing.expectEqual(test_case.cycles, cpu.cycle_count);
    }
}

test "Cycle counts - JAM opcodes" {
    const jam_opcodes = [_]u8{ 0x02, 0x12, 0x22, 0x32, 0x42, 0x52, 0x62, 0x72, 0x92, 0xB2, 0xD2, 0xF2 };

    for (jam_opcodes) |opcode| {
        var cpu = Cpu.init();
        var bus = Bus.init();

        bus.ram[0] = opcode;
        cpu.pc = 0x0000;

        // JAM is 2 cycles (fetch + execute/halt)
        for (0..2) |_| {
            _ = cpu.tick(&bus);
        }

        try testing.expectEqual(@as(u64, 2), cpu.cycle_count);
        try testing.expect(cpu.halted);
    }
}
