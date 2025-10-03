const std = @import("std");
const CpuModule = @import("Cpu.zig");
const BusModule = @import("../bus/Bus.zig");

const Cpu = CpuModule.Cpu;
const Bus = BusModule.Bus;

/// Microstep function signature
/// Returns true when the instruction completes
pub const MicrostepFn = *const fn (*Cpu, *Bus) bool;

/// Instruction executor containing array of microsteps
pub const InstructionExecutor = struct {
    microsteps: []const MicrostepFn,
    base_cycles: u8,

    /// Execute the current microstep for this instruction
    /// Returns true if the instruction is complete
    pub fn execute(self: InstructionExecutor, cpu: *Cpu, bus: *Bus) bool {
        const step = cpu.instruction_cycle;

        // Safety check: ensure we don't exceed microstep array bounds
        if (step >= self.microsteps.len) {
            @panic("Instruction cycle exceeded microstep array length");
        }

        const complete = self.microsteps[step](cpu, bus);

        if (!complete) {
            cpu.instruction_cycle += 1;
        } else {
            // Reset for next instruction
            cpu.instruction_cycle = 0;
        }

        return complete;
    }
};

// ============================================================================
// Common Microstep Functions
// ============================================================================

/// Fetch the opcode (always cycle 1)
pub fn fetchOpcode(cpu: *Cpu, bus: *Bus) bool {
    cpu.opcode = bus.read(cpu.pc);
    cpu.pc +%= 1;
    return false; // Never completes on opcode fetch
}

/// Fetch operand low byte (immediate/zero page address)
pub fn fetchOperandLow(cpu: *Cpu, bus: *Bus) bool {
    cpu.operand_low = bus.read(cpu.pc);
    cpu.pc +%= 1;
    return false;
}

/// Fetch absolute address low byte
pub fn fetchAbsLow(cpu: *Cpu, bus: *Bus) bool {
    cpu.operand_low = bus.read(cpu.pc);
    cpu.pc +%= 1;
    return false;
}

/// Fetch absolute address high byte
pub fn fetchAbsHigh(cpu: *Cpu, bus: *Bus) bool {
    cpu.operand_high = bus.read(cpu.pc);
    cpu.pc +%= 1;
    return false;
}

// ============================================================================
// Zero Page Indexed Addressing
// ============================================================================

/// Add X index to zero page address (wraps within page 0)
pub fn addXToZeroPage(cpu: *Cpu, bus: *Bus) bool {
    // Dummy read at base address
    _ = bus.read(@as(u16, cpu.operand_low));

    // Add index and wrap within page 0
    cpu.effective_address = @as(u16, cpu.operand_low +% cpu.x);
    return false;
}

/// Add Y index to zero page address (wraps within page 0)
pub fn addYToZeroPage(cpu: *Cpu, bus: *Bus) bool {
    // Dummy read at base address
    _ = bus.read(@as(u16, cpu.operand_low));

    // Add index and wrap within page 0
    cpu.effective_address = @as(u16, cpu.operand_low +% cpu.y);
    return false;
}

// ============================================================================
// Absolute Indexed Addressing
// ============================================================================

/// Calculate absolute,X address with page crossing check
/// Returns true if no page cross (completes addressing for read instructions)
pub fn calcAbsoluteX(cpu: *Cpu, bus: *Bus) bool {
    const base = (@as(u16, cpu.operand_high) << 8) | @as(u16, cpu.operand_low);
    cpu.effective_address = base +% cpu.x;
    cpu.page_crossed = (base & 0xFF00) != (cpu.effective_address & 0xFF00);

    // CRITICAL: Dummy read at wrong address (base_high | result_low)
    const dummy_addr = (base & 0xFF00) | (cpu.effective_address & 0x00FF);
    const dummy_value = bus.read(dummy_addr);

    // Store the dummy read value
    // For read instructions with no page cross, this IS the correct value!
    cpu.temp_value = dummy_value;

    // Return false (continue to execute state)
    // The execute function will check page_crossed and use temp_value if false
    return false;
}

/// Calculate absolute,Y address with page crossing check
pub fn calcAbsoluteY(cpu: *Cpu, bus: *Bus) bool {
    const base = (@as(u16, cpu.operand_high) << 8) | @as(u16, cpu.operand_low);
    cpu.effective_address = base +% cpu.y;
    cpu.page_crossed = (base & 0xFF00) != (cpu.effective_address & 0xFF00);

    // CRITICAL: Dummy read at wrong address
    const dummy_addr = (base & 0xFF00) | (cpu.effective_address & 0x00FF);
    _ = bus.read(dummy_addr);

    cpu.temp_value = bus.open_bus.value;

    return false;
}

/// Fix high byte after page crossing (for write/RMW instructions)
pub fn fixHighByte(cpu: *Cpu, bus: *Bus) bool {
    // Dummy read at incorrect address
    _ = bus.read(cpu.effective_address);
    return false;
}

// ============================================================================
// Indexed Indirect (Indirect,X)
// ============================================================================

/// Fetch zero page base for indexed indirect
pub fn fetchZpBase(cpu: *Cpu, bus: *Bus) bool {
    cpu.operand_low = bus.read(cpu.pc);
    cpu.pc +%= 1;
    return false;
}

/// Add X to base address (with dummy read)
pub fn addXToBase(cpu: *Cpu, bus: *Bus) bool {
    // Dummy read at base address
    _ = bus.read(@as(u16, cpu.operand_low));

    // Add X and wrap in zero page
    cpu.temp_address = @as(u16, cpu.operand_low +% cpu.x);
    return false;
}

/// Fetch low byte of indirect address
pub fn fetchIndirectLow(cpu: *Cpu, bus: *Bus) bool {
    cpu.operand_low = bus.read(cpu.temp_address);
    return false;
}

/// Fetch high byte of indirect address
pub fn fetchIndirectHigh(cpu: *Cpu, bus: *Bus) bool {
    // Wrap within zero page
    const high_addr = @as(u16, @as(u8, @truncate(cpu.temp_address)) +% 1);
    cpu.operand_high = bus.read(high_addr);
    cpu.effective_address = (@as(u16, cpu.operand_high) << 8) | @as(u16, cpu.operand_low);
    return false;
}

// ============================================================================
// Indirect Indexed (Indirect),Y
// ============================================================================

/// Fetch zero page pointer for indirect indexed
pub fn fetchZpPointer(cpu: *Cpu, bus: *Bus) bool {
    cpu.operand_low = bus.read(cpu.pc);
    cpu.pc +%= 1;
    return false;
}

/// Fetch low byte of pointer
pub fn fetchPointerLow(cpu: *Cpu, bus: *Bus) bool {
    cpu.temp_value = bus.read(@as(u16, cpu.operand_low));
    return false;
}

/// Fetch high byte of pointer
pub fn fetchPointerHigh(cpu: *Cpu, bus: *Bus) bool {
    // Wrap within zero page
    const high_addr = @as(u16, cpu.operand_low +% 1);
    cpu.operand_high = bus.read(high_addr);
    return false;
}

/// Add Y and check for page crossing
pub fn addYCheckPage(cpu: *Cpu, bus: *Bus) bool {
    const base = (@as(u16, cpu.operand_high) << 8) | @as(u16, cpu.temp_value);
    cpu.effective_address = base +% cpu.y;
    cpu.page_crossed = (base & 0xFF00) != (cpu.effective_address & 0xFF00);

    // Dummy read at wrong address
    const dummy_addr = (base & 0xFF00) | (cpu.effective_address & 0x00FF);
    _ = bus.read(dummy_addr);

    cpu.temp_value = bus.open_bus.value;

    return false;
}

// ============================================================================
// Stack Operations
// ============================================================================

/// Push byte to stack
pub fn pushByte(cpu: *Cpu, bus: *Bus, value: u8) bool {
    const stack_addr = 0x0100 | @as(u16, cpu.sp);
    bus.write(stack_addr, value);
    cpu.sp -%= 1;
    return false;
}

/// Pull byte from stack (increment SP first)
pub fn pullByte(cpu: *Cpu, bus: *Bus) bool {
    cpu.sp +%= 1;
    const stack_addr = 0x0100 | @as(u16, cpu.sp);
    cpu.temp_value = bus.read(stack_addr);
    return false;
}

/// Dummy read during stack operation
pub fn stackDummyRead(cpu: *Cpu, bus: *Bus) bool {
    const stack_addr = 0x0100 | @as(u16, cpu.sp);
    _ = bus.read(stack_addr);
    return false;
}

// ============================================================================
// Read-Modify-Write (RMW) Operations
// ============================================================================

/// Read operand for RMW instruction
pub fn rmwRead(cpu: *Cpu, bus: *Bus) bool {
    // Determine effective address based on addressing mode
    const addr = switch (cpu.address_mode) {
        .zero_page => @as(u16, cpu.operand_low),
        .zero_page_x, .absolute_x => cpu.effective_address,
        .absolute => (@as(u16, cpu.operand_high) << 8) | @as(u16, cpu.operand_low),
        else => unreachable,
    };

    cpu.effective_address = addr;
    cpu.temp_value = bus.read(addr);
    return false;
}

/// Dummy write original value (CRITICAL for hardware accuracy!)
pub fn rmwDummyWrite(cpu: *Cpu, bus: *Bus) bool {
    // MUST write original value back (hardware quirk)
    // This is visible to memory-mapped I/O!
    bus.write(cpu.effective_address, cpu.temp_value);
    return false;
}

// ============================================================================
// Branch Operations
// ============================================================================

/// Fetch branch offset
pub fn branchFetchOffset(cpu: *Cpu, bus: *Bus) bool {
    cpu.operand_low = bus.read(cpu.pc);
    cpu.pc +%= 1;
    return false;
}

/// Add offset to PC and check page crossing
pub fn branchAddOffset(cpu: *Cpu, bus: *Bus) bool {
    // Dummy read during offset calculation
    _ = bus.read(cpu.pc);

    const offset = @as(i8, @bitCast(cpu.operand_low));
    const old_pc = cpu.pc;
    cpu.pc = @as(u16, @bitCast(@as(i16, @bitCast(old_pc)) + offset));

    cpu.page_crossed = (old_pc & 0xFF00) != (cpu.pc & 0xFF00);

    if (!cpu.page_crossed) {
        return true; // Branch complete (3 cycles total)
    }

    return false; // Need page fix (4 cycles total)
}

/// Fix PC high byte after page crossing
pub fn branchFixPch(cpu: *Cpu, bus: *Bus) bool {
    // Dummy read at incorrect address
    const dummy_addr = (cpu.pc & 0x00FF) | ((cpu.pc -% (@as(u16, cpu.operand_low) & 0x0100)) & 0xFF00);
    _ = bus.read(dummy_addr);
    return true; // Branch complete
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "InstructionExecutor - basic execution" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    const nop_steps = [_]MicrostepFn{
        fetchOperandLow,
    };

    const executor = InstructionExecutor{
        .microsteps = &nop_steps,
        .base_cycles = 2,
    };

    cpu.pc = 0x0000;
    bus.ram[0] = 0x42; // Dummy value

    // First microstep should not complete
    const complete1 = executor.execute(&cpu, &bus);
    try testing.expect(!complete1);
    try testing.expectEqual(@as(u8, 0x42), cpu.operand_low);
    try testing.expectEqual(@as(u8, 1), cpu.instruction_cycle);
    try testing.expectEqual(@as(u16, 1), cpu.pc); // PC should increment
}

test "fetchOpcode - updates PC and stores opcode" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.pc = 0x0000;
    bus.ram[0] = 0xEA; // NOP opcode

    const complete = fetchOpcode(&cpu, &bus);
    try testing.expect(!complete); // Fetch never completes
    try testing.expectEqual(@as(u8, 0xEA), cpu.opcode);
    try testing.expectEqual(@as(u16, 1), cpu.pc);
}

test "calcAbsoluteX - no page crossing" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.operand_low = 0x10;
    cpu.operand_high = 0x20;
    cpu.x = 0x05;

    const complete = calcAbsoluteX(&cpu, &bus);
    try testing.expect(!complete);
    try testing.expectEqual(@as(u16, 0x2015), cpu.effective_address);
    try testing.expect(!cpu.page_crossed);
}

test "calcAbsoluteX - page crossing" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.operand_low = 0xFF;
    cpu.operand_high = 0x20;
    cpu.x = 0x05;

    const complete = calcAbsoluteX(&cpu, &bus);
    try testing.expect(!complete);
    try testing.expectEqual(@as(u16, 0x2104), cpu.effective_address);
    try testing.expect(cpu.page_crossed);
}

test "addXToZeroPage - wraps in page 0" {
    var cpu = Cpu.init();
    var bus = Bus.init();

    cpu.operand_low = 0xFF;
    cpu.x = 0x05;

    const complete = addXToZeroPage(&cpu, &bus);
    try testing.expect(!complete);
    try testing.expectEqual(@as(u16, 0x0004), cpu.effective_address);
}
