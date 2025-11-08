//! CPU microstep functions for cycle-accurate 6502 emulation
//! These atomic functions perform hardware-perfect CPU operations
//! All side effects (bus access, state mutation) happen through state parameter
//!
//! Returns: bool indicating whether instruction completes early (e.g., branch not taken)

/// Fetch operand low byte (immediate/zero page address)
pub fn fetchOperandLow(state: anytype) bool {
    state.cpu.operand_low = state.busRead(state.cpu.pc);
    state.cpu.pc +%= 1;
    return false;
}

/// Fetch absolute address low byte
pub fn fetchAbsLow(state: anytype) bool {
    state.cpu.operand_low = state.busRead(state.cpu.pc);
    state.cpu.pc +%= 1;
    return false;
}

/// Fetch absolute address high byte
pub fn fetchAbsHigh(state: anytype) bool {
    state.cpu.operand_high = state.busRead(state.cpu.pc);
    state.cpu.pc +%= 1;
    return false;
}

/// Add X index to zero page address (wraps within page 0)
pub fn addXToZeroPage(state: anytype) bool {
    state.dummyRead(@as(u16, state.cpu.operand_low));
    state.cpu.effective_address = @as(u16, state.cpu.operand_low +% state.cpu.x);
    return false;
}

/// Add Y index to zero page address (wraps within page 0)
pub fn addYToZeroPage(state: anytype) bool {
    state.dummyRead(@as(u16, state.cpu.operand_low));
    state.cpu.effective_address = @as(u16, state.cpu.operand_low +% state.cpu.y);
    return false;
}

/// Calculate absolute,X address with page crossing check
pub fn calcAbsoluteX(state: anytype) bool {
    const base = (@as(u16, state.cpu.operand_high) << 8) | @as(u16, state.cpu.operand_low);
    state.cpu.effective_address = base +% state.cpu.x;
    state.cpu.page_crossed = (base & 0xFF00) != (state.cpu.effective_address & 0xFF00);

    // CRITICAL: Dummy read at wrong address (base_high | result_low)
    const dummy_addr = (base & 0xFF00) | (state.cpu.effective_address & 0x00FF);
    const dummy_value = state.busRead(dummy_addr);
    state.cpu.temp_value = dummy_value;

    // Early completion when page NOT crossed (4 cycles vs 5)
    // When page not crossed, dummy_value IS the correct value (hardware behavior)
    return !state.cpu.page_crossed;
}

/// Calculate absolute,Y address with page crossing check
pub fn calcAbsoluteY(state: anytype) bool {
    const base = (@as(u16, state.cpu.operand_high) << 8) | @as(u16, state.cpu.operand_low);
    state.cpu.effective_address = base +% state.cpu.y;
    state.cpu.page_crossed = (base & 0xFF00) != (state.cpu.effective_address & 0xFF00);

    const dummy_addr = (base & 0xFF00) | (state.cpu.effective_address & 0x00FF);
    const dummy_value = state.busRead(dummy_addr);
    state.cpu.temp_value = dummy_value;

    // Early completion when page NOT crossed (4 cycles vs 5)
    // When page not crossed, dummy_value IS the correct value (hardware behavior)
    return !state.cpu.page_crossed;
}

/// Calculate absolute,X address for WRITE operations (never early completion)
/// Write operations always take the dummy read cycle regardless of page crossing
pub fn calcAbsoluteXWrite(state: anytype) bool {
    const base = (@as(u16, state.cpu.operand_high) << 8) | @as(u16, state.cpu.operand_low);
    state.cpu.effective_address = base +% state.cpu.x;
    state.cpu.page_crossed = (base & 0xFF00) != (state.cpu.effective_address & 0xFF00);

    const dummy_addr = (base & 0xFF00) | (state.cpu.effective_address & 0x00FF);
    _ = state.busRead(dummy_addr);

    // Writes NEVER complete early (hardware always does dummy read)
    return false;
}

/// Calculate absolute,Y address for WRITE operations (never early completion)
/// Write operations always take the dummy read cycle regardless of page crossing
pub fn calcAbsoluteYWrite(state: anytype) bool {
    const base = (@as(u16, state.cpu.operand_high) << 8) | @as(u16, state.cpu.operand_low);
    state.cpu.effective_address = base +% state.cpu.y;
    state.cpu.page_crossed = (base & 0xFF00) != (state.cpu.effective_address & 0xFF00);

    const dummy_addr = (base & 0xFF00) | (state.cpu.effective_address & 0x00FF);
    _ = state.busRead(dummy_addr);

    // Writes NEVER complete early (hardware always does dummy read)
    return false;
}

/// Fix high byte after page crossing
/// For reads: Do REAL read when page crossed (hardware behavior)
/// For RMW: This is always a dummy read before the real read cycle
pub fn fixHighByte(state: anytype) bool {
    if (state.cpu.page_crossed) {
        // Read the actual value at correct address
        // For read instructions: this IS the operand value (execute will use temp_value)
        // For RMW instructions: this is a dummy read (RMW will re-read in next cycle)
        state.cpu.temp_value = state.busRead(state.cpu.effective_address);
    }
    // Page not crossed: temp_value already has correct value from previous microstep
    // - For absolute,X/Y: calcAbsoluteX/Y set it
    // - For indirect_indexed: addYCheckPage set it (after fix)
    return false;
}

/// Fetch zero page base for indexed indirect
pub fn fetchZpBase(state: anytype) bool {
    state.cpu.operand_low = state.busRead(state.cpu.pc);
    state.cpu.pc +%= 1;
    return false;
}

/// Add X to base address
pub fn addXToBase(state: anytype) bool {
    state.dummyRead(@as(u16, state.cpu.operand_low));
    state.cpu.temp_address = @as(u16, state.cpu.operand_low +% state.cpu.x);
    return false;
}

/// Fetch low byte of indirect address
pub fn fetchIndirectLow(state: anytype) bool {
    state.cpu.operand_low = state.busRead(state.cpu.temp_address);
    return false;
}

/// Fetch high byte of indirect address
pub fn fetchIndirectHigh(state: anytype) bool {
    const high_addr = @as(u16, @as(u8, @truncate(state.cpu.temp_address)) +% 1);
    state.cpu.operand_high = state.busRead(high_addr);
    state.cpu.effective_address = (@as(u16, state.cpu.operand_high) << 8) | @as(u16, state.cpu.operand_low);
    return false;
}

/// Fetch zero page pointer for indirect indexed
pub fn fetchZpPointer(state: anytype) bool {
    state.cpu.operand_low = state.busRead(state.cpu.pc);
    state.cpu.pc +%= 1;
    return false;
}

/// Fetch low byte of pointer
pub fn fetchPointerLow(state: anytype) bool {
    state.cpu.temp_value = state.busRead(@as(u16, state.cpu.operand_low));
    return false;
}

/// Fetch high byte of pointer
pub fn fetchPointerHigh(state: anytype) bool {
    const high_addr = @as(u16, state.cpu.operand_low +% 1);
    state.cpu.operand_high = state.busRead(high_addr);
    return false;
}

/// Add Y and check for page crossing
pub fn addYCheckPage(state: anytype) bool {
    const base = (@as(u16, state.cpu.operand_high) << 8) | @as(u16, state.cpu.temp_value);
    state.cpu.effective_address = base +% state.cpu.y;
    state.cpu.page_crossed = (base & 0xFF00) != (state.cpu.effective_address & 0xFF00);

    const dummy_addr = (base & 0xFF00) | (state.cpu.effective_address & 0x00FF);
    const dummy_value = state.busRead(dummy_addr);

    // CRITICAL: When page NOT crossed, the dummy read IS the actual read (hardware behavior)
    // The dummy address happens to be the correct address when base and effective are in same page
    if (!state.cpu.page_crossed) {
        state.cpu.temp_value = dummy_value; // Use the value we just read
    } else {
        state.cpu.temp_value = state.bus.open_bus.get(); // Page crossed: value discarded, fixHighByte will re-read
    }

    // Early completion when page NOT crossed (5 cycles vs 6 for indirect_indexed)
    return !state.cpu.page_crossed;
}

/// Pull byte from stack (increment SP first)
pub fn pullByte(state: anytype) bool {
    state.cpu.sp +%= 1;
    const stack_addr = 0x0100 | @as(u16, state.cpu.sp);
    state.cpu.temp_value = state.busRead(stack_addr);
    return false;
}

/// Dummy read during stack operation
pub fn stackDummyRead(state: anytype) bool {
    const stack_addr = 0x0100 | @as(u16, state.cpu.sp);
    _ = state.busRead(stack_addr);
    return false;
}

/// Push PC high byte to stack (for JSR/BRK)
pub fn pushPch(state: anytype) bool {
    const stack_addr = 0x0100 | @as(u16, state.cpu.sp);
    const value = @as(u8, @truncate(state.cpu.pc >> 8));
    state.busWrite(stack_addr, value);
    state.cpu.sp -%= 1;
    return false;
}

/// Push PC low byte to stack (for JSR/BRK)
pub fn pushPcl(state: anytype) bool {
    const stack_addr = 0x0100 | @as(u16, state.cpu.sp);
    const value = @as(u8, @truncate(state.cpu.pc & 0xFF));
    state.busWrite(stack_addr, value);
    state.cpu.sp -%= 1;
    return false;
}

/// Push status register to stack with B flag set (for BRK)
pub fn pushStatusBrk(state: anytype) bool {
    const stack_addr = 0x0100 | @as(u16, state.cpu.sp);
    const status = state.cpu.p.toByte() | 0x30; // B flag + unused flag set
    state.busWrite(stack_addr, status);
    state.cpu.sp -%= 1;
    return false;
}

/// Push status register to stack (for NMI/IRQ - B flag clear)
/// Reference: nesdev.org/wiki/Status_flags#The_B_flag
pub fn pushStatusInterrupt(state: anytype) bool {
    const stack_addr = 0x0100 | @as(u16, state.cpu.sp);
    const status = (state.cpu.p.toByte() & ~@as(u8, 0x10)) | 0x20;
    state.busWrite(stack_addr, status);
    state.cpu.sp -%= 1;
    return false;
}

/// Pull PC low byte from stack (for RTS/RTI)
pub fn pullPcl(state: anytype) bool {
    state.cpu.sp +%= 1;
    const stack_addr = 0x0100 | @as(u16, state.cpu.sp);
    state.cpu.operand_low = state.busRead(stack_addr);
    return false;
}

/// Pull PC high byte from stack and reconstruct PC (for RTS/RTI)
pub fn pullPch(state: anytype) bool {
    state.cpu.sp +%= 1;
    const stack_addr = 0x0100 | @as(u16, state.cpu.sp);
    state.cpu.operand_high = state.busRead(stack_addr);
    state.cpu.pc = (@as(u16, state.cpu.operand_high) << 8) | @as(u16, state.cpu.operand_low);
    return false;
}

/// Pull PC high byte and signal completion (for RTI final cycle)
pub fn pullPchRti(state: anytype) bool {
    state.cpu.sp +%= 1;
    const stack_addr = 0x0100 | @as(u16, state.cpu.sp);
    state.cpu.operand_high = state.busRead(stack_addr);
    state.cpu.pc = (@as(u16, state.cpu.operand_high) << 8) | @as(u16, state.cpu.operand_low);
    return true; // RTI complete
}

/// Pull status register from stack (for RTI/PLP)
pub fn pullStatus(state: anytype) bool {
    state.cpu.sp +%= 1;
    const stack_addr = 0x0100 | @as(u16, state.cpu.sp);
    const status = state.busRead(stack_addr);
    state.cpu.p = @TypeOf(state.cpu.p).fromByte(status);
    return false;
}

/// Increment PC after RTS (PC was pushed as PC-1 by JSR)
pub fn incrementPcAfterRts(state: anytype) bool {
    state.dummyRead(state.cpu.pc);
    state.cpu.pc +%= 1;
    return true;
}

/// Stack dummy read for JSR cycle 3 (internal operation)
pub fn jsrStackDummy(state: anytype) bool {
    const stack_addr = 0x0100 | @as(u16, state.cpu.sp);
    state.dummyRead(stack_addr);
    return false;
}

/// Fetch absolute high byte for JSR and jump (final cycle)
pub fn fetchAbsHighJsr(state: anytype) bool {
    state.cpu.operand_high = state.busRead(state.cpu.pc);
    state.cpu.effective_address = (@as(u16, state.cpu.operand_high) << 8) | @as(u16, state.cpu.operand_low);
    state.cpu.pc = state.cpu.effective_address;
    return true; // JSR complete
}

/// Fetch IRQ vector low byte (for BRK) and set interrupt disable flag
pub fn fetchIrqVectorLow(state: anytype) bool {
    state.cpu.operand_low = state.busRead(0xFFFE);
    state.cpu.p.interrupt = true;
    return false;
}

/// Fetch IRQ vector high byte and jump (completes BRK)
pub fn fetchIrqVectorHigh(state: anytype) bool {
    state.cpu.operand_high = state.busRead(0xFFFF);
    state.cpu.pc = (@as(u16, state.cpu.operand_high) << 8) | @as(u16, state.cpu.operand_low);
    return true; // BRK complete
}

/// Read operand for RMW instruction
pub fn rmwRead(state: anytype) bool {
    const addr = switch (state.cpu.address_mode) {
        .zero_page => @as(u16, state.cpu.operand_low),
        .zero_page_x => state.cpu.effective_address,
        .absolute => (@as(u16, state.cpu.operand_high) << 8) | @as(u16, state.cpu.operand_low),
        .absolute_x => state.cpu.effective_address,
        .absolute_y => state.cpu.effective_address,
        .indexed_indirect => state.cpu.effective_address, // (ind,X)
        .indirect_indexed => state.cpu.effective_address, // (ind),Y
        else => unreachable,
    };

    state.cpu.effective_address = addr;
    state.cpu.temp_value = state.busRead(addr);
    return false;
}

/// Dummy write original value (CRITICAL for hardware accuracy!)
pub fn rmwDummyWrite(state: anytype) bool {
    state.busWrite(state.cpu.effective_address, state.cpu.temp_value);
    return false;
}

/// Fetch branch offset and check condition
pub fn branchFetchOffset(state: anytype) bool {
    state.cpu.operand_low = state.busRead(state.cpu.pc);
    state.cpu.pc +%= 1;

    // Check branch condition based on opcode
    // If condition false, branch not taken → complete immediately (2 cycles total)
    // If condition true, branch taken → continue to branchAddOffset (3-4 cycles)
    const should_branch = switch (state.cpu.opcode) {
        0x10 => !state.cpu.p.negative, // BPL - Branch if Plus (N=0)
        0x30 => state.cpu.p.negative, // BMI - Branch if Minus (N=1)
        0x50 => !state.cpu.p.overflow, // BVC - Branch if Overflow Clear (V=0)
        0x70 => state.cpu.p.overflow, // BVS - Branch if Overflow Set (V=1)
        0x90 => !state.cpu.p.carry, // BCC - Branch if Carry Clear (C=0)
        0xB0 => state.cpu.p.carry, // BCS - Branch if Carry Set (C=1)
        0xD0 => !state.cpu.p.zero, // BNE - Branch if Not Equal (Z=0)
        0xF0 => state.cpu.p.zero, // BEQ - Branch if Equal (Z=1)
        else => unreachable,
    };

    if (!should_branch) {
        // Branch not taken - complete immediately (2 cycles total)
        // PC already advanced past offset byte, pointing to next instruction
        return true;
    }

    // Branch taken - continue to branchAddOffset (3-4 cycles total)
    return false;
}

/// Add offset to PC and check page crossing
pub fn branchAddOffset(state: anytype) bool {
    _ = state.busRead(state.cpu.pc); // Dummy read during offset calculation

    const offset = @as(i8, @bitCast(state.cpu.operand_low));
    const old_pc = state.cpu.pc;
    state.cpu.pc = @as(u16, @bitCast(@as(i16, @bitCast(old_pc)) + offset));

    state.cpu.page_crossed = (old_pc & 0xFF00) != (state.cpu.pc & 0xFF00);

    if (!state.cpu.page_crossed) {
        return true; // Branch complete (3 cycles total)
    }
    return false; // Need page fix (4 cycles total)
}

/// Fix PC high byte after page crossing
pub fn branchFixPch(state: anytype) bool {
    const dummy_addr = (state.cpu.pc & 0x00FF) | ((state.cpu.pc -% (@as(u16, state.cpu.operand_low) & 0x0100)) & 0xFF00);
    _ = state.busRead(dummy_addr);
    return true; // Branch complete
}

/// Fetch low byte of JMP indirect target
pub fn jmpIndirectFetchLow(state: anytype) bool {
    // Initialize effective_address from the indirect pointer base (fetched in cycles 0-1)
    // CRITICAL: Must set effective_address before reading from it!
    state.cpu.effective_address = (@as(u16, state.cpu.operand_high) << 8) | @as(u16, state.cpu.operand_low);

    // Read low byte of target address from the computed pointer
    state.cpu.operand_low = state.busRead(state.cpu.effective_address);
    return false;
}

/// Fetch high byte of JMP indirect target (with page boundary bug)
pub fn jmpIndirectFetchHigh(state: anytype) bool {
    // 6502 bug: If pointer is at page boundary, wraps within page
    const ptr = state.cpu.effective_address;
    const high_addr = if ((ptr & 0xFF) == 0xFF)
        ptr & 0xFF00 // Wrap to start of same page
    else
        ptr + 1;

    state.cpu.operand_high = state.busRead(high_addr);
    state.cpu.effective_address = (@as(u16, state.cpu.operand_high) << 8) | @as(u16, state.cpu.operand_low);

    return false;
}

/// Dummy read at PC (used by RTI final cycle)
/// This is the hardware-accurate dummy read that occurs after PC is restored
pub fn dummyReadPc(state: anytype) bool {
    state.dummyRead(state.cpu.pc);
    return true; // Signal completion
}
