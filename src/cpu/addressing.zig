const std = @import("std");
const CpuModule = @import("Cpu.zig");
const BusModule = @import("../bus/Bus.zig");
const execution = @import("execution.zig");

const Cpu = CpuModule.Cpu;
const Bus = BusModule.Bus;
const AddressingMode = CpuModule.AddressingMode;
const MicrostepFn = execution.MicrostepFn;

/// Addressing mode microstep sequences
/// Each addressing mode is decomposed into its individual cycles

// ============================================================================
// Implied/Accumulator (1 cycle - opcode fetch only)
// ============================================================================

// No additional cycles needed - instruction executes immediately after opcode fetch

// ============================================================================
// Immediate (2 cycles total)
// ============================================================================

pub const immediate_steps = [_]MicrostepFn{
    execution.fetchOperandLow, // Cycle 2: Fetch operand
};

// ============================================================================
// Zero Page (3 cycles total)
// ============================================================================

pub const zero_page_steps = [_]MicrostepFn{
    execution.fetchOperandLow, // Cycle 2: Fetch ZP address
    // Cycle 3: Execute (read/write at ZP address)
};

// ============================================================================
// Zero Page,X (4 cycles total)
// ============================================================================

pub const zero_page_x_steps = [_]MicrostepFn{
    execution.fetchOperandLow, // Cycle 2: Fetch base address
    execution.addXToZeroPage, // Cycle 3: Add X with dummy read
    // Cycle 4: Execute (read/write)
};

// ============================================================================
// Zero Page,Y (4 cycles total)
// ============================================================================

pub const zero_page_y_steps = [_]MicrostepFn{
    execution.fetchOperandLow, // Cycle 2: Fetch base address
    execution.addYToZeroPage, // Cycle 3: Add Y with dummy read
    // Cycle 4: Execute (read/write)
};

// ============================================================================
// Absolute (4 cycles total)
// ============================================================================

pub const absolute_steps = [_]MicrostepFn{
    execution.fetchAbsLow, // Cycle 2: Fetch low byte
    execution.fetchAbsHigh, // Cycle 3: Fetch high byte
    // Cycle 4: Execute (read/write)
};

// ============================================================================
// Absolute,X (4-5 cycles, +1 if page crossed for reads, always +1 for writes)
// ============================================================================

pub const absolute_x_read_steps = [_]MicrostepFn{
    execution.fetchAbsLow, // Cycle 2
    execution.fetchAbsHigh, // Cycle 3
    execution.calcAbsoluteX, // Cycle 4: Calculate + dummy read
    // Cycle 5: Execute (only if page crossed)
};

pub const absolute_x_write_steps = [_]MicrostepFn{
    execution.fetchAbsLow, // Cycle 2
    execution.fetchAbsHigh, // Cycle 3
    execution.calcAbsoluteX, // Cycle 4: Calculate + dummy read
    execution.fixHighByte, // Cycle 5: Dummy read (always for writes)
    // Cycle 6: Execute (write)
};

// ============================================================================
// Absolute,Y (4-5 cycles, +1 if page crossed for reads, always +1 for writes)
// ============================================================================

pub const absolute_y_read_steps = [_]MicrostepFn{
    execution.fetchAbsLow, // Cycle 2
    execution.fetchAbsHigh, // Cycle 3
    execution.calcAbsoluteY, // Cycle 4: Calculate + dummy read
    // Cycle 5: Execute (only if page crossed)
};

pub const absolute_y_write_steps = [_]MicrostepFn{
    execution.fetchAbsLow, // Cycle 2
    execution.fetchAbsHigh, // Cycle 3
    execution.calcAbsoluteY, // Cycle 4: Calculate + dummy read
    execution.fixHighByte, // Cycle 5: Dummy read (always for writes)
    // Cycle 6: Execute (write)
};

// ============================================================================
// Indexed Indirect (Indirect,X) - 6 cycles
// ============================================================================

pub const indexed_indirect_steps = [_]MicrostepFn{
    execution.fetchZpBase, // Cycle 2: Fetch ZP base
    execution.addXToBase, // Cycle 3: Add X with dummy read
    execution.fetchIndirectLow, // Cycle 4: Fetch pointer low
    execution.fetchIndirectHigh, // Cycle 5: Fetch pointer high
    // Cycle 6: Execute (read/write)
};

// ============================================================================
// Indirect Indexed (Indirect),Y - 5-6 cycles
// ============================================================================

pub const indirect_indexed_read_steps = [_]MicrostepFn{
    execution.fetchZpPointer, // Cycle 2: Fetch ZP pointer address
    execution.fetchPointerLow, // Cycle 3: Fetch pointer low
    execution.fetchPointerHigh, // Cycle 4: Fetch pointer high
    execution.addYCheckPage, // Cycle 5: Add Y + dummy read
    // Cycle 6: Execute (only if page crossed)
};

pub const indirect_indexed_write_steps = [_]MicrostepFn{
    execution.fetchZpPointer, // Cycle 2: Fetch ZP pointer address
    execution.fetchPointerLow, // Cycle 3: Fetch pointer low
    execution.fetchPointerHigh, // Cycle 4: Fetch pointer high
    execution.addYCheckPage, // Cycle 5: Add Y + dummy read
    execution.fixHighByte, // Cycle 6: Dummy read (always for writes)
    // Cycle 7: Execute (write)
};

// ============================================================================
// Relative (2-4 cycles for branches)
// ============================================================================

pub const relative_steps = [_]MicrostepFn{
    execution.branchFetchOffset, // Cycle 2: Fetch offset
    // Branch instruction checks condition:
    // - Not taken: Complete (2 cycles)
    // - Taken, no page cross: branchAddOffset returns true (3 cycles)
    // - Taken, page cross: branchAddOffset + branchFixPch (4 cycles)
};

// ============================================================================
// Indirect (for JMP only) - 5 cycles
// ============================================================================

pub const indirect_jmp_steps = [_]MicrostepFn{
    execution.fetchAbsLow, // Cycle 2: Fetch pointer low
    execution.fetchAbsHigh, // Cycle 3: Fetch pointer high
    // Cycle 4: Fetch low byte of target
    // Cycle 5: Fetch high byte of target (with page boundary bug)
};

// ============================================================================
// Read-Modify-Write (RMW) Addressing Modes
// These include the critical dummy write cycle
// ============================================================================

/// RMW Zero Page - 5 cycles
pub const zero_page_rmw_steps = [_]MicrostepFn{
    execution.fetchOperandLow, // Cycle 2: Fetch ZP address
    execution.rmwRead,          // Cycle 3: Read value
    execution.rmwDummyWrite,    // Cycle 4: Write original value (CRITICAL!)
    // Cycle 5: Execute (modify and write result)
};

/// RMW Zero Page,X - 6 cycles
pub const zero_page_x_rmw_steps = [_]MicrostepFn{
    execution.fetchOperandLow, // Cycle 2: Fetch base address
    execution.addXToZeroPage,   // Cycle 3: Add X with dummy read
    execution.rmwRead,          // Cycle 4: Read value
    execution.rmwDummyWrite,    // Cycle 5: Write original value (CRITICAL!)
    // Cycle 6: Execute (modify and write result)
};

/// RMW Absolute - 6 cycles
pub const absolute_rmw_steps = [_]MicrostepFn{
    execution.fetchAbsLow,   // Cycle 2: Fetch low byte
    execution.fetchAbsHigh,  // Cycle 3: Fetch high byte
    execution.rmwRead,       // Cycle 4: Read value
    execution.rmwDummyWrite, // Cycle 5: Write original value (CRITICAL!)
    // Cycle 6: Execute (modify and write result)
};

/// RMW Absolute,X - 7 cycles
pub const absolute_x_rmw_steps = [_]MicrostepFn{
    execution.fetchAbsLow,   // Cycle 2: Fetch low byte
    execution.fetchAbsHigh,  // Cycle 3: Fetch high byte
    execution.calcAbsoluteX, // Cycle 4: Calculate + dummy read
    execution.rmwRead,       // Cycle 5: Read value from correct address
    execution.rmwDummyWrite, // Cycle 6: Write original value (CRITICAL!)
    // Cycle 7: Execute (modify and write result)
};

/// RMW Indexed Indirect - 8 cycles
pub const indexed_indirect_rmw_steps = [_]MicrostepFn{
    execution.fetchZpBase,      // Cycle 2: Fetch ZP base
    execution.addXToBase,       // Cycle 3: Add X with dummy read
    execution.fetchIndirectLow, // Cycle 4: Fetch pointer low
    execution.fetchIndirectHigh, // Cycle 5: Fetch pointer high
    execution.rmwRead,          // Cycle 6: Read value
    execution.rmwDummyWrite,    // Cycle 7: Write original value (CRITICAL!)
    // Cycle 8: Execute (modify and write result)
};

/// RMW Indirect Indexed - 8 cycles
pub const indirect_indexed_rmw_steps = [_]MicrostepFn{
    execution.fetchZpPointer,    // Cycle 2: Fetch ZP pointer address
    execution.fetchPointerLow,   // Cycle 3: Fetch pointer low
    execution.fetchPointerHigh,  // Cycle 4: Fetch pointer high
    execution.addYCheckPage,     // Cycle 5: Add Y + dummy read
    execution.rmwRead,           // Cycle 6: Read value from correct address
    execution.rmwDummyWrite,     // Cycle 7: Write original value (CRITICAL!)
    // Cycle 8: Execute (modify and write result)
};

// ============================================================================
// Helper: Get addressing mode microsteps for an instruction
// ============================================================================

pub const AddressingModeSteps = struct {
    steps: []const MicrostepFn,
    is_read: bool = true, // false for write/RMW instructions
};

/// Get the microstep sequence for a given addressing mode
pub fn getAddressingSteps(mode: AddressingMode, is_read: bool) AddressingModeSteps {
    return switch (mode) {
        .implied, .accumulator => .{
            .steps = &[_]MicrostepFn{},
            .is_read = is_read,
        },
        .immediate => .{
            .steps = &immediate_steps,
            .is_read = true, // Always read for immediate
        },
        .zero_page => .{
            .steps = &zero_page_steps,
            .is_read = is_read,
        },
        .zero_page_x => .{
            .steps = &zero_page_x_steps,
            .is_read = is_read,
        },
        .zero_page_y => .{
            .steps = &zero_page_y_steps,
            .is_read = is_read,
        },
        .absolute => .{
            .steps = &absolute_steps,
            .is_read = is_read,
        },
        .absolute_x => .{
            .steps = if (is_read) &absolute_x_read_steps else &absolute_x_write_steps,
            .is_read = is_read,
        },
        .absolute_y => .{
            .steps = if (is_read) &absolute_y_read_steps else &absolute_y_write_steps,
            .is_read = is_read,
        },
        .indexed_indirect => .{
            .steps = &indexed_indirect_steps,
            .is_read = is_read,
        },
        .indirect_indexed => .{
            .steps = if (is_read) &indirect_indexed_read_steps else &indirect_indexed_write_steps,
            .is_read = is_read,
        },
        .relative => .{
            .steps = &relative_steps,
            .is_read = true,
        },
        .indirect => .{
            .steps = &indirect_jmp_steps,
            .is_read = true,
        },
    };
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;
const opcodes = @import("opcodes.zig");

test "immediate mode - correct step count" {
    const steps = getAddressingSteps(.immediate, true);
    try testing.expectEqual(@as(usize, 1), steps.steps.len);
}

test "zero_page_x mode - correct step count" {
    const steps = getAddressingSteps(.zero_page_x, true);
    try testing.expectEqual(@as(usize, 2), steps.steps.len);
}

test "absolute_x mode - read vs write step count" {
    const read_steps = getAddressingSteps(.absolute_x, true);
    const write_steps = getAddressingSteps(.absolute_x, false);

    try testing.expectEqual(@as(usize, 3), read_steps.steps.len);
    try testing.expectEqual(@as(usize, 4), write_steps.steps.len);
}

test "indexed_indirect mode - correct step count" {
    const steps = getAddressingSteps(.indexed_indirect, true);
    try testing.expectEqual(@as(usize, 4), steps.steps.len);
}

test "indirect_indexed mode - read vs write step count" {
    const read_steps = getAddressingSteps(.indirect_indexed, true);
    const write_steps = getAddressingSteps(.indirect_indexed, false);

    try testing.expectEqual(@as(usize, 4), read_steps.steps.len);
    try testing.expectEqual(@as(usize, 5), write_steps.steps.len);
}
