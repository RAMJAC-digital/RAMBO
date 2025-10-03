//! Jump and Control Flow Instructions
//!
//! JMP - Jump (absolute, indirect)
//! JSR - Jump to Subroutine
//! RTS - Return from Subroutine
//! RTI - Return from Interrupt
//! BRK - Force Break/Interrupt

const std = @import("std");
const Cpu = @import("../Cpu.zig");
const Bus = @import("../../bus/Bus.zig").Bus;
const Logic = @import("../Logic.zig");

const State = Cpu.State.State;

/// JMP - Jump
/// PC = address
/// No flags affected
///
/// Supports: Absolute (3 cycles), Indirect (5 cycles)
pub fn jmp(state: *State, bus: *Bus) bool {
    if (state.address_mode == .absolute) {
        // Absolute: PC already points to target from addressing mode
        state.pc = state.effective_address;
    } else if (state.address_mode == .indirect) {
        // Indirect: effective_address contains the pointer address
        // Note: 6502 bug - if pointer is at page boundary (e.g. $10FF),
        // high byte is fetched from $1000 instead of $1100
        const ptr_lo = state.effective_address;
        const ptr_hi = if ((ptr_lo & 0xFF) == 0xFF)
            ptr_lo & 0xFF00  // Bug: wrap within page
        else
            ptr_lo + 1;

        const target_lo = bus.read(ptr_lo);
        const target_hi = bus.read(ptr_hi);
        state.pc = (@as(u16, target_hi) << 8) | target_lo;
    } else {
        unreachable; // JMP only supports absolute and indirect
    }

    return true;
}

/// JSR - Jump to Subroutine
/// Push return address - 1, then jump
/// No flags affected
///
/// 6 cycles total
pub fn jsr(state: *State, bus: *Bus) bool {
    // At this point, we've fetched the target address
    // PC currently points to the next instruction

    // Calculate return address (PC - 1)
    const return_addr = state.pc -% 1;

    // Push return address high byte
    Logic.push(state, bus, @as(u8, @truncate(return_addr >> 8)));

    // Push return address low byte
    Logic.push(state, bus, @as(u8, @truncate(return_addr)));

    // Jump to subroutine
    state.pc = state.effective_address;

    return true;
}

/// RTS - Return from Subroutine
/// Pull return address, increment PC
/// No flags affected
///
/// 6 cycles total
pub fn rts(state: *State, bus: *Bus) bool {
    // Pull return address low byte
    const ret_lo = Logic.pull(state, bus);

    // Pull return address high byte
    const ret_hi = Logic.pull(state, bus);

    // Reconstruct address and increment (JSR pushed PC-1)
    state.pc = ((@as(u16, ret_hi) << 8) | ret_lo) +% 1;

    // Dummy read for cycle accuracy
    _ = bus.read(state.pc);

    return true;
}

/// RTI - Return from Interrupt
/// Pull processor status, then return address
/// Flags: Restored from stack
///
/// 6 cycles total
pub fn rti(state: *State, bus: *Bus) bool {
    // Pull processor status (ignore bits 4 and 5)
    const status = Logic.pull(state, bus);
    state.p = @TypeOf(state.p).fromByte(status);

    // Pull return address low byte
    const ret_lo = Logic.pull(state, bus);

    // Pull return address high byte
    const ret_hi = Logic.pull(state, bus);

    // Restore PC
    state.pc = (@as(u16, ret_hi) << 8) | ret_lo;

    return true;
}

/// BRK - Force Break/Interrupt
/// Push PC+2, push status with B flag set, load interrupt vector
/// Flags: I = 1
///
/// 7 cycles total
pub fn brk(state: *State, bus: *Bus) bool {
    // PC already incremented past BRK operand (padding byte)
    const return_addr = state.pc;

    // Push return address high byte
    Logic.push(state, bus, @as(u8, @truncate(return_addr >> 8)));

    // Push return address low byte
    Logic.push(state, bus, @as(u8, @truncate(return_addr)));

    // Push processor status with B flag set
    var status = state.p.toByte();
    status |= 0x10; // Set B flag (bit 4)
    Logic.push(state, bus, status);

    // Set interrupt disable flag
    state.p.interrupt = true;

    // Load interrupt vector from $FFFE-$FFFF
    const vec_lo = bus.read(0xFFFE);
    const vec_hi = bus.read(0xFFFF);
    state.pc = (@as(u16, vec_hi) << 8) | vec_lo;

    return true;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "JMP: absolute mode" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.address_mode = .absolute;
    state.effective_address = 0x8000;

    _ = jmp(&state, &bus);

    try testing.expectEqual(@as(u16, 0x8000), state.pc);
}

test "JMP: indirect mode - normal" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.address_mode = .indirect;
    state.effective_address = 0x0200; // Pointer address

    bus.write(0x0200, 0x00); // Target low
    bus.write(0x0201, 0x80); // Target high

    _ = jmp(&state, &bus);

    try testing.expectEqual(@as(u16, 0x8000), state.pc);
}

test "JMP: indirect mode - page boundary bug" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.address_mode = .indirect;
    state.effective_address = 0x10FF; // Pointer at page boundary

    bus.write(0x10FF, 0x00); // Target low
    bus.write(0x1000, 0x80); // High byte wraps to start of page (bug!)
    bus.write(0x1100, 0x90); // This would be correct, but isn't used

    _ = jmp(&state, &bus);

    try testing.expectEqual(@as(u16, 0x8000), state.pc); // Uses $1000, not $1100
}

test "JSR: pushes return address and jumps" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.sp = 0xFF;
    state.pc = 0x8003; // Current PC
    state.effective_address = 0x9000; // Subroutine address

    _ = jsr(&state, &bus);

    // Check return address on stack (PC-1 = $8002)
    try testing.expectEqual(@as(u8, 0x80), bus.read(0x01FF)); // High byte
    try testing.expectEqual(@as(u8, 0x02), bus.read(0x01FE)); // Low byte
    try testing.expectEqual(@as(u8, 0xFD), state.sp); // SP decremented twice
    try testing.expectEqual(@as(u16, 0x9000), state.pc); // Jumped to subroutine
}

test "RTS: pulls return address and increments" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.sp = 0xFD;
    bus.write(0x01FE, 0x02); // Return low
    bus.write(0x01FF, 0x80); // Return high

    _ = rts(&state, &bus);

    try testing.expectEqual(@as(u16, 0x8003), state.pc); // Pulled $8002, incremented to $8003
    try testing.expectEqual(@as(u8, 0xFF), state.sp); // SP incremented twice
}

test "RTI: restores status and PC" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.sp = 0xFC;
    bus.write(0x01FD, 0b11000011); // Status byte (N=1, V=1, Z=1, C=1)
    bus.write(0x01FE, 0x00); // Return low
    bus.write(0x01FF, 0x80); // Return high

    _ = rti(&state, &bus);

    try testing.expect(state.p.negative);
    try testing.expect(state.p.overflow);
    try testing.expect(state.p.zero);
    try testing.expect(state.p.carry);
    try testing.expectEqual(@as(u16, 0x8000), state.pc);
    try testing.expectEqual(@as(u8, 0xFF), state.sp);
}

test "BRK: pushes PC+2 and status, loads vector" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    // Allocate test RAM for interrupt vectors
    var test_ram = [_]u8{0} ** 32768; // 32KB for $8000-$FFFF
    bus.test_ram = &test_ram;

    state.sp = 0xFF;
    state.pc = 0x8001; // After BRK opcode and padding
    state.p.carry = true;
    state.p.zero = true;

    // Set interrupt vector ($FFFE-$FFFF)
    bus.write(0xFFFE, 0x00);
    bus.write(0xFFFF, 0x90);

    _ = brk(&state, &bus);

    // Check PC on stack
    try testing.expectEqual(@as(u8, 0x80), bus.read(0x01FF)); // PC high
    try testing.expectEqual(@as(u8, 0x01), bus.read(0x01FE)); // PC low

    // Check status on stack (with B flag set)
    const status = bus.read(0x01FD);
    try testing.expectEqual(@as(u8, 1), (status >> 4) & 1); // B flag set

    // Check interrupt disable set
    try testing.expect(state.p.interrupt);

    // Check jumped to vector
    try testing.expectEqual(@as(u16, 0x9000), state.pc);
    try testing.expectEqual(@as(u8, 0xFC), state.sp);
}

test "JSR and RTS: round trip" {
    var state = Cpu.Logic.init();
    var bus = Bus.init();

    state.sp = 0xFF;
    state.pc = 0x8003;
    state.effective_address = 0x9000;

    // JSR
    _ = jsr(&state, &bus);
    try testing.expectEqual(@as(u16, 0x9000), state.pc);

    // RTS
    _ = rts(&state, &bus);
    try testing.expectEqual(@as(u16, 0x8003), state.pc);
    try testing.expectEqual(@as(u8, 0xFF), state.sp); // Stack balanced
}
