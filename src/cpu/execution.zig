const std = @import("std");
const Cpu = @import("Cpu.zig");
const BusModule = @import("../bus/Bus.zig");

const CpuState = Cpu.State.CpuState; // CPU State type, not module
const BusState = BusModule.State.BusState;

/// Microstep function signature
/// Returns true when the instruction completes
pub const MicrostepFn = *const fn (*CpuState, *BusState) bool;

/// Instruction executor containing array of microsteps
pub const InstructionExecutor = struct {
    microsteps: []const MicrostepFn,
    base_cycles: u8,

    /// Execute the current microstep for this instruction
    /// Returns true if the instruction is complete
    pub fn execute(self: InstructionExecutor, state: *CpuState, bus: *BusState) bool {
        const step = state.instruction_cycle;

        // Safety check: ensure we don't exceed microstep array bounds
        // This should never happen in correct code (all instructions have proper cycle counts)
        // Using unreachable maintains RT-safety (no allocation in error path)
        if (step >= self.microsteps.len) {
            unreachable;
        }

        const complete = self.microsteps[step](state, bus);

        if (!complete) {
            state.instruction_cycle += 1;
        } else {
            // Reset for next instruction
            state.instruction_cycle = 0;
        }

        return complete;
    }
};

// ============================================================================
// Common Microstep Functions
// ============================================================================

/// Fetch the opcode (always cycle 1)
pub fn fetchOpcode(state: *CpuState, bus: *BusState) bool {
    state.opcode = bus.read(state.pc);
    state.pc +%= 1;
    return false; // Never completes on opcode fetch
}

/// Fetch operand low byte (immediate/zero page address)
pub fn fetchOperandLow(state: *CpuState, bus: *BusState) bool {
    state.operand_low = bus.read(state.pc);
    state.pc +%= 1;
    return false;
}

/// Fetch absolute address low byte
pub fn fetchAbsLow(state: *CpuState, bus: *BusState) bool {
    state.operand_low = bus.read(state.pc);
    state.pc +%= 1;
    return false;
}

/// Fetch absolute address high byte
pub fn fetchAbsHigh(state: *CpuState, bus: *BusState) bool {
    state.operand_high = bus.read(state.pc);
    state.pc +%= 1;
    return false;
}

// ============================================================================
// Zero Page Indexed Addressing
// ============================================================================

/// Add X index to zero page address (wraps within page 0)
pub fn addXToZeroPage(state: *CpuState, bus: *BusState) bool {
    // Dummy read at base address
    _ = bus.read(@as(u16, state.operand_low));

    // Add index and wrap within page 0
    state.effective_address = @as(u16, state.operand_low +% state.x);
    return false;
}

/// Add Y index to zero page address (wraps within page 0)
pub fn addYToZeroPage(state: *CpuState, bus: *BusState) bool {
    // Dummy read at base address
    _ = bus.read(@as(u16, state.operand_low));

    // Add index and wrap within page 0
    state.effective_address = @as(u16, state.operand_low +% state.y);
    return false;
}

// ============================================================================
// Absolute Indexed Addressing
// ============================================================================

/// Calculate absolute,X address with page crossing check
/// Returns true if no page cross (completes addressing for read instructions)
pub fn calcAbsoluteX(state: *CpuState, bus: *BusState) bool {
    const base = (@as(u16, state.operand_high) << 8) | @as(u16, state.operand_low);
    state.effective_address = base +% state.x;
    state.page_crossed = (base & 0xFF00) != (state.effective_address & 0xFF00);

    // CRITICAL: Dummy read at wrong address (base_high | result_low)
    const dummy_addr = (base & 0xFF00) | (state.effective_address & 0x00FF);
    const dummy_value = bus.read(dummy_addr);

    // Store the dummy read value
    // For read instructions with no page cross, this IS the correct value!
    state.temp_value = dummy_value;

    // Return false (continue to execute state)
    // The execute function will check page_crossed and use temp_value if false
    return false;
}

/// Calculate absolute,Y address with page crossing check
pub fn calcAbsoluteY(state: *CpuState, bus: *BusState) bool {
    const base = (@as(u16, state.operand_high) << 8) | @as(u16, state.operand_low);
    state.effective_address = base +% state.y;
    state.page_crossed = (base & 0xFF00) != (state.effective_address & 0xFF00);

    // CRITICAL: Dummy read at wrong address
    const dummy_addr = (base & 0xFF00) | (state.effective_address & 0x00FF);
    _ = bus.read(dummy_addr);

    state.temp_value = bus.open_bus.value;

    return false;
}

/// Fix high byte after page crossing (for write/RMW instructions)
pub fn fixHighByte(state: *CpuState, bus: *BusState) bool {
    // Dummy read at incorrect address
    _ = bus.read(state.effective_address);
    return false;
}

// ============================================================================
// Indexed Indirect (Indirect,X)
// ============================================================================

/// Fetch zero page base for indexed indirect
pub fn fetchZpBase(state: *CpuState, bus: *BusState) bool {
    state.operand_low = bus.read(state.pc);
    state.pc +%= 1;
    return false;
}

/// Add X to base address (with dummy read)
pub fn addXToBase(state: *CpuState, bus: *BusState) bool {
    // Dummy read at base address
    _ = bus.read(@as(u16, state.operand_low));

    // Add X and wrap in zero page
    state.temp_address = @as(u16, state.operand_low +% state.x);
    return false;
}

/// Fetch low byte of indirect address
pub fn fetchIndirectLow(state: *CpuState, bus: *BusState) bool {
    state.operand_low = bus.read(state.temp_address);
    return false;
}

/// Fetch high byte of indirect address
pub fn fetchIndirectHigh(state: *CpuState, bus: *BusState) bool {
    // Wrap within zero page
    const high_addr = @as(u16, @as(u8, @truncate(state.temp_address)) +% 1);
    state.operand_high = bus.read(high_addr);
    state.effective_address = (@as(u16, state.operand_high) << 8) | @as(u16, state.operand_low);
    return false;
}

// ============================================================================
// Indirect Indexed (Indirect),Y
// ============================================================================

/// Fetch zero page pointer for indirect indexed
pub fn fetchZpPointer(state: *CpuState, bus: *BusState) bool {
    state.operand_low = bus.read(state.pc);
    state.pc +%= 1;
    return false;
}

/// Fetch low byte of pointer
pub fn fetchPointerLow(state: *CpuState, bus: *BusState) bool {
    state.temp_value = bus.read(@as(u16, state.operand_low));
    return false;
}

/// Fetch high byte of pointer
pub fn fetchPointerHigh(state: *CpuState, bus: *BusState) bool {
    // Wrap within zero page
    const high_addr = @as(u16, state.operand_low +% 1);
    state.operand_high = bus.read(high_addr);
    return false;
}

/// Add Y and check for page crossing
pub fn addYCheckPage(state: *CpuState, bus: *BusState) bool {
    const base = (@as(u16, state.operand_high) << 8) | @as(u16, state.temp_value);
    state.effective_address = base +% state.y;
    state.page_crossed = (base & 0xFF00) != (state.effective_address & 0xFF00);

    // Dummy read at wrong address
    const dummy_addr = (base & 0xFF00) | (state.effective_address & 0x00FF);
    _ = bus.read(dummy_addr);

    state.temp_value = bus.open_bus.value;

    return false;
}

// ============================================================================
// Stack Operations
// ============================================================================

/// Push byte to stack
pub fn pushByte(state: *CpuState, bus: *BusState, value: u8) bool {
    const stack_addr = 0x0100 | @as(u16, state.sp);
    bus.write(stack_addr, value);
    state.sp -%= 1;
    return false;
}

/// Pull byte from stack (increment SP first)
pub fn pullByte(state: *CpuState, bus: *BusState) bool {
    state.sp +%= 1;
    const stack_addr = 0x0100 | @as(u16, state.sp);
    state.temp_value = bus.read(stack_addr);
    return false;
}

/// Dummy read during stack operation
pub fn stackDummyRead(state: *CpuState, bus: *BusState) bool {
    const stack_addr = 0x0100 | @as(u16, state.sp);
    _ = bus.read(stack_addr);
    return false;
}

// ============================================================================
// Read-Modify-Write (RMW) Operations
// ============================================================================

/// Read operand for RMW instruction
pub fn rmwRead(state: *CpuState, bus: *BusState) bool {
    // Determine effective address based on addressing mode
    const addr = switch (state.address_mode) {
        .zero_page => @as(u16, state.operand_low),
        .zero_page_x, .absolute_x => state.effective_address,
        .absolute => (@as(u16, state.operand_high) << 8) | @as(u16, state.operand_low),
        else => unreachable,
    };

    state.effective_address = addr;
    state.temp_value = bus.read(addr);
    return false;
}

/// Dummy write original value (CRITICAL for hardware accuracy!)
pub fn rmwDummyWrite(state: *CpuState, bus: *BusState) bool {
    // MUST write original value back (hardware quirk)
    // This is visible to memory-mapped I/O!
    bus.write(state.effective_address, state.temp_value);
    return false;
}

// ============================================================================
// Branch Operations
// ============================================================================

/// Fetch branch offset
pub fn branchFetchOffset(state: *CpuState, bus: *BusState) bool {
    state.operand_low = bus.read(state.pc);
    state.pc +%= 1;
    return false;
}

/// Add offset to PC and check page crossing
pub fn branchAddOffset(state: *CpuState, bus: *BusState) bool {
    // Dummy read during offset calculation
    _ = bus.read(state.pc);

    const offset = @as(i8, @bitCast(state.operand_low));
    const old_pc = state.pc;
    state.pc = @as(u16, @bitCast(@as(i16, @bitCast(old_pc)) + offset));

    state.page_crossed = (old_pc & 0xFF00) != (state.pc & 0xFF00);

    if (!state.page_crossed) {
        return true; // Branch complete (3 cycles total)
    }

    return false; // Need page fix (4 cycles total)
}

/// Fix PC high byte after page crossing
pub fn branchFixPch(state: *CpuState, bus: *BusState) bool {
    // Dummy read at incorrect address
    const dummy_addr = (state.pc & 0x00FF) | ((state.pc -% (@as(u16, state.operand_low) & 0x0100)) & 0xFF00);
    _ = bus.read(dummy_addr);
    return true; // Branch complete
}

// ============================================================================
// JMP Indirect Addressing (with 6502 page boundary bug)
// ============================================================================

/// Fetch low byte of JMP indirect target
pub fn jmpIndirectFetchLow(state: *CpuState, bus: *BusState) bool {
    // effective_address contains the pointer address
    state.operand_low = bus.read(state.effective_address);
    return false;
}

/// Fetch high byte of JMP indirect target (with page boundary bug)
pub fn jmpIndirectFetchHigh(state: *CpuState, bus: *BusState) bool {
    // 6502 bug: If pointer is at page boundary (e.g. $10FF),
    // high byte is fetched from $1000 instead of $1100 (wraps within page)
    const ptr = state.effective_address;
    const high_addr = if ((ptr & 0xFF) == 0xFF)
        ptr & 0xFF00 // Wrap to start of same page
    else
        ptr + 1;

    state.operand_high = bus.read(high_addr);
    // Construct target address in effective_address for JMP to use
    state.effective_address = (@as(u16, state.operand_high) << 8) | state.operand_low;
    return false;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "InstructionExecutor - basic execution" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    const nop_steps = [_]MicrostepFn{
        fetchOperandLow,
    };

    const executor = InstructionExecutor{
        .microsteps = &nop_steps,
        .base_cycles = 2,
    };

    state.pc = 0x0000;
    bus.ram[0] = 0x42; // Dummy value

    // First microstep should not complete
    const complete1 = executor.execute(&state, &bus);
    try testing.expect(!complete1);
    try testing.expectEqual(@as(u8, 0x42), state.operand_low);
    try testing.expectEqual(@as(u8, 1), state.instruction_cycle);
    try testing.expectEqual(@as(u16, 1), state.pc); // PC should increment
}

test "fetchOpcode - updates PC and stores opcode" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.pc = 0x0000;
    bus.ram[0] = 0xEA; // NOP opcode

    const complete = fetchOpcode(&state, &bus);
    try testing.expect(!complete); // Fetch never completes
    try testing.expectEqual(@as(u8, 0xEA), state.opcode);
    try testing.expectEqual(@as(u16, 1), state.pc);
}

test "calcAbsoluteX - no page crossing" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.operand_low = 0x10;
    state.operand_high = 0x20;
    state.x = 0x05;

    const complete = calcAbsoluteX(&state, &bus);
    try testing.expect(!complete);
    try testing.expectEqual(@as(u16, 0x2015), state.effective_address);
    try testing.expect(!state.page_crossed);
}

test "calcAbsoluteX - page crossing" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.operand_low = 0xFF;
    state.operand_high = 0x20;
    state.x = 0x05;

    const complete = calcAbsoluteX(&state, &bus);
    try testing.expect(!complete);
    try testing.expectEqual(@as(u16, 0x2104), state.effective_address);
    try testing.expect(state.page_crossed);
}

test "addXToZeroPage - wraps in page 0" {
    var state = Cpu.Logic.init();
    var bus = BusState.init();

    state.operand_low = 0xFF;
    state.x = 0x05;

    const complete = addXToZeroPage(&state, &bus);
    try testing.expect(!complete);
    try testing.expectEqual(@as(u16, 0x0004), state.effective_address);
}
