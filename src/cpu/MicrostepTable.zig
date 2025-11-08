//! CPU Microstep Dispatch Table
//!
//! This module provides a table-driven dispatch system for 6502 addressing modes.
//! Instead of nested switches on addressing mode and instruction cycle, we use
//! a comptime-built table that maps each opcode to its microstep sequence.
//!
//! Architecture:
//! - MicrostepSequence: Defines microstep array, max cycles, and operand source
//! - Addressing mode sequences: Predefined for all 13 modes (read/write/rmw variants)
//! - Special opcode sequences: JSR, RTS, RTI, BRK, stack operations
//! - MICROSTEP_TABLE: Comptime-built [256] table for all opcodes
//!
//! Benefits:
//! - Single source of truth (no duplication across 3 switch sites)
//! - Declarative (what microsteps, not how to dispatch)
//! - Maintainable (add opcode = add 1 table entry, not 3+ switch cases)
//!
//! References:
//! - Phase 6 Plan: /tmp/cpu_refactor.md (lines 883-1104)
//! - Duplication Analysis: /tmp/phase6_duplication_analysis.md

const std = @import("std");
const CpuMicrosteps = @import("Microsteps.zig");
const dispatch = @import("dispatch.zig");
const decode = @import("decode.zig");

/// Microstep function signature
/// Takes bus interface (duck-typed), returns completion status
pub const MicrostepFn = *const fn (anytype) bool;

/// Runtime dispatch to microstep functions via comptime switch
/// This allows calling generic functions by index while preserving zero-cost polymorphism
/// Index mapping:
///  0: fetchOperandLow      | 12: fetchIndirectLow     | 24: fetchAbsHighJsr
///  1: rmwRead              | 13: fetchIndirectHigh    | 25: stackDummyRead
///  2: rmwDummyWrite        | 14: fetchZpPointer       | 26: pullPcl
///  3: addXToZeroPage       | 15: addYCheckPage        | 27: pullPch
///  4: addYToZeroPage       | 16: branchFetchOffset    | 28: incrementPcAfterRts
///  5: fetchAbsLow          | 17: branchAddOffset      | 29: pullStatus
///  6: fetchAbsHigh         | 18: branchFixPch         | 30: dummyReadPc
///  7: calcAbsoluteX        | 19: jmpIndirectFetchLow  | 31: pushStatusBrk
///  8: fixHighByte          | 20: jmpIndirectFetchHigh | 32: fetchIrqVectorLow
///  9: calcAbsoluteY        | 21: jsrStackDummy        | 33: fetchIrqVectorHigh
/// 10: fetchZpBase          | 22: pushPch              | 34: pullByte
/// 11: addXToBase           | 23: pushPcl              | 35: fetchPointerLow
///                          |                          | 36: fetchPointerHigh
///                          |                          | 37: calcAbsoluteXWrite
///                          |                          | 38: calcAbsoluteYWrite
pub fn callMicrostep(idx: u8, bus: anytype) bool {
    return switch (idx) {
        0 => CpuMicrosteps.fetchOperandLow(bus),
        1 => CpuMicrosteps.rmwRead(bus),
        2 => CpuMicrosteps.rmwDummyWrite(bus),
        3 => CpuMicrosteps.addXToZeroPage(bus),
        4 => CpuMicrosteps.addYToZeroPage(bus),
        5 => CpuMicrosteps.fetchAbsLow(bus),
        6 => CpuMicrosteps.fetchAbsHigh(bus),
        7 => CpuMicrosteps.calcAbsoluteX(bus),
        8 => CpuMicrosteps.fixHighByte(bus),
        9 => CpuMicrosteps.calcAbsoluteY(bus),
        10 => CpuMicrosteps.fetchZpBase(bus),
        11 => CpuMicrosteps.addXToBase(bus),
        12 => CpuMicrosteps.fetchIndirectLow(bus),
        13 => CpuMicrosteps.fetchIndirectHigh(bus),
        14 => CpuMicrosteps.fetchZpPointer(bus),
        15 => CpuMicrosteps.addYCheckPage(bus),
        16 => CpuMicrosteps.branchFetchOffset(bus),
        17 => CpuMicrosteps.branchAddOffset(bus),
        18 => CpuMicrosteps.branchFixPch(bus),
        19 => CpuMicrosteps.jmpIndirectFetchLow(bus),
        20 => CpuMicrosteps.jmpIndirectFetchHigh(bus),
        21 => CpuMicrosteps.jsrStackDummy(bus),
        22 => CpuMicrosteps.pushPch(bus),
        23 => CpuMicrosteps.pushPcl(bus),
        24 => CpuMicrosteps.fetchAbsHighJsr(bus),
        25 => CpuMicrosteps.stackDummyRead(bus),
        26 => CpuMicrosteps.pullPcl(bus),
        27 => CpuMicrosteps.pullPch(bus),
        28 => CpuMicrosteps.incrementPcAfterRts(bus),
        29 => CpuMicrosteps.pullStatus(bus),
        30 => CpuMicrosteps.dummyReadPc(bus),
        31 => CpuMicrosteps.pushStatusBrk(bus),
        32 => CpuMicrosteps.fetchIrqVectorLow(bus),
        33 => CpuMicrosteps.fetchIrqVectorHigh(bus),
        34 => CpuMicrosteps.pullByte(bus),
        35 => CpuMicrosteps.fetchPointerLow(bus),
        36 => CpuMicrosteps.fetchPointerHigh(bus),
        37 => CpuMicrosteps.calcAbsoluteXWrite(bus),
        38 => CpuMicrosteps.calcAbsoluteYWrite(bus),
        else => unreachable,
    };
}

/// How to obtain the operand value during execution phase
pub const OperandSource = enum {
    none,           // Implied/accumulator modes (value not used)
    immediate_pc,   // Read from PC (immediate mode: LDA #$42)
    temp_value,     // Preloaded by RMW or pull operations
    operand_low,    // Zero page address (LDA $10)
    effective_addr, // Computed address (LDA $10,X or indexed modes)
    operand_hl,     // Absolute address (combine operand_high << 8 | operand_low)
    accumulator,    // Accumulator mode (ASL A, ROL A)
};

/// Complete microstep sequence for an opcode
pub const MicrostepSequence = struct {
    /// Array of microstep function indices to execute in order
    /// Index = instruction_cycle value, value = index into MICROSTEP_FUNCTIONS
    steps: []const u8,

    /// Maximum cycles for addressing phase
    /// Used to determine when addressing is complete
    max_cycles: u8,

    /// How to fetch operand during execute phase
    operand_source: OperandSource,
};

// ============================================================================
// Addressing Mode Sequences (13 modes × 3 variants = 39 sequences)
// ============================================================================

/// Immediate mode - operand is next byte (#$42)
/// 0 addressing cycles - operand read directly from PC in execute phase
const IMMEDIATE_SEQ = MicrostepSequence{
    .steps = &[_]u8{},
    .max_cycles = 0,
    .operand_source = .immediate_pc,
};

/// Accumulator mode - operates on A register (ASL A, ROL A)
/// 0 addressing cycles - no memory access needed
const ACCUMULATOR_SEQ = MicrostepSequence{
    .steps = &[_]u8{},
    .max_cycles = 0,
    .operand_source = .accumulator,
};

/// Implied mode - no operand (NOP, CLC, etc.)
/// 0 addressing cycles - instruction has no operand
const IMPLIED_SEQ = MicrostepSequence{
    .steps = &[_]u8{},
    .max_cycles = 0,
    .operand_source = .none,
};

// === Zero Page ===

/// Zero page read/write - address is 00:XX (LDA $10, STA $10)
/// 1 addressing cycle: fetch ZP address from PC
const ZERO_PAGE_READ_SEQ = MicrostepSequence{
    .steps = &[_]u8{0}, // fetchOperandLow
    .max_cycles = 1,
    .operand_source = .operand_low,
};

/// Zero page RMW - address is 00:XX (ASL $10, INC $10)
/// 3 addressing cycles: fetch address, read value, dummy write
const ZERO_PAGE_RMW_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 0, 1, 2 }, // fetchOperandLow, rmwRead, rmwDummyWrite
    .max_cycles = 3,
    .operand_source = .temp_value,
};

// === Zero Page,X ===

/// Zero page,X read/write - address is 00:(XX + X) (LDA $10,X, STA $10,X)
/// 2 addressing cycles: fetch base, add X with ZP wrap
const ZERO_PAGE_X_READ_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 0, 3 }, // fetchOperandLow, addXToZeroPage
    .max_cycles = 2,
    .operand_source = .effective_addr,
};

/// Zero page,X RMW - address is 00:(XX + X) (ASL $10,X, INC $10,X)
/// 4 addressing cycles: fetch base, add X, read value, dummy write
const ZERO_PAGE_X_RMW_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 0, 3, 1, 2 }, // fetchOperandLow, addXToZeroPage, rmwRead, rmwDummyWrite
    .max_cycles = 4,
    .operand_source = .temp_value,
};

// === Zero Page,Y ===

/// Zero page,Y read/write - address is 00:(XX + Y) (LDX $10,Y, STX $10,Y)
/// 2 addressing cycles: fetch base, add Y with ZP wrap
const ZERO_PAGE_Y_READ_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 0, 4 }, // fetchOperandLow, addYToZeroPage
    .max_cycles = 2,
    .operand_source = .effective_addr,
};

// Note: No official zero_page_y RMW opcodes exist
// Unofficial opcodes use zero_page_y for some operations, but not RMW

// === Absolute ===

/// Absolute read - address is HHLL (LDA $1234)
/// 2 addressing cycles: fetch low byte, fetch high byte
const ABSOLUTE_READ_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 5, 6 }, // fetchAbsLow, fetchAbsHigh
    .max_cycles = 2,
    .operand_source = .operand_hl,
};

/// Absolute write - address is HHLL (STA $1234)
/// 2 addressing cycles: fetch low byte, fetch high byte
/// NOTE: No read from target address (hardware writes directly)
const ABSOLUTE_WRITE_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 5, 6 }, // fetchAbsLow, fetchAbsHigh
    .max_cycles = 2,
    .operand_source = .none,
};

/// Absolute RMW - address is HHLL (ASL $1234, INC $1234)
/// 4 addressing cycles: fetch low, fetch high, read value, dummy write
const ABSOLUTE_RMW_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 5, 6, 1, 2 }, // fetchAbsLow, fetchAbsHigh, rmwRead, rmwDummyWrite
    .max_cycles = 4,
    .operand_source = .temp_value,
};

// === Absolute,X ===

/// Absolute,X read - address is HHLL + X (LDA $1234,X)
/// 2-3 addressing cycles: fetch low, fetch high, add X (+ page fix if crossed)
/// Note: Non-RMW can complete early if no page cross
const ABSOLUTE_X_READ_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 5, 6, 7, 8 }, // fetchAbsLow, fetchAbsHigh, calcAbsoluteX, fixHighByte
    .max_cycles = 4, // Max cycles, may complete at 3 if no page cross
    .operand_source = .temp_value,
};

/// Absolute,X write - address is HHLL + X (STA $1234,X)
/// 3 addressing cycles: fetch low, fetch high, add X + dummy read
/// Note: Writes always take the dummy read cycle (no early completion)
const ABSOLUTE_X_WRITE_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 5, 6, 37 }, // fetchAbsLow, fetchAbsHigh, calcAbsoluteXWrite
    .max_cycles = 3,
    .operand_source = .effective_addr,
};

/// Absolute,X RMW - address is HHLL + X (ASL $1234,X, INC $1234,X)
/// 5 addressing cycles: fetch low, fetch high, add X, dummy read, read value, dummy write
/// Note: RMW always does page fix (even if not crossed)
const ABSOLUTE_X_RMW_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 5, 6, 7, 8, 1, 2 }, // fetchAbsLow, fetchAbsHigh, calcAbsoluteX, fixHighByte, rmwRead, rmwDummyWrite
    .max_cycles = 6,
    .operand_source = .temp_value,
};

// === Absolute,Y ===

/// Absolute,Y read - address is HHLL + Y (LDA $1234,Y)
/// 2-3 addressing cycles: fetch low, fetch high, add Y (+ page fix if crossed)
const ABSOLUTE_Y_READ_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 5, 6, 9, 8 }, // fetchAbsLow, fetchAbsHigh, calcAbsoluteY, fixHighByte
    .max_cycles = 4,
    .operand_source = .temp_value,
};

/// Absolute,Y write - address is HHLL + Y (STA $1234,Y)
/// 3 addressing cycles: fetch low, fetch high, add Y + dummy read
const ABSOLUTE_Y_WRITE_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 5, 6, 38 }, // fetchAbsLow, fetchAbsHigh, calcAbsoluteYWrite
    .max_cycles = 3,
    .operand_source = .effective_addr,
};

/// Absolute,Y RMW - address is HHLL + Y (unofficial opcodes only)
/// 5 addressing cycles: fetch low, fetch high, add Y, dummy read, read value, dummy write
const ABSOLUTE_Y_RMW_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 5, 6, 9, 8, 1, 2 }, // fetchAbsLow, fetchAbsHigh, calcAbsoluteY, fixHighByte, rmwRead, rmwDummyWrite
    .max_cycles = 6,
    .operand_source = .temp_value,
};

// === Indexed Indirect - (ZP,X) ===

/// Indexed indirect read/write - address at 00:((XX + X) & 0xFF) (LDA ($10,X))
/// 4 addressing cycles: fetch base, add X, fetch indirect pointer low/high
const INDEXED_INDIRECT_READ_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 10, 11, 12, 13 }, // fetchZpBase, addXToBase, fetchIndirectLow, fetchIndirectHigh
    .max_cycles = 4,
    .operand_source = .effective_addr,
};

/// Indexed indirect RMW - address at 00:((XX + X) & 0xFF) (SLO ($10,X))
/// 6 addressing cycles: fetch base, add X, fetch pointer, read value, dummy write
const INDEXED_INDIRECT_RMW_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 10, 11, 12, 13, 1, 2 }, // fetchZpBase, addXToBase, fetchIndirectLow, fetchIndirectHigh, rmwRead, rmwDummyWrite
    .max_cycles = 6,
    .operand_source = .temp_value,
};

// === Indirect Indexed - (ZP),Y ===

/// Indirect indexed read - address at (00:XX) + Y (LDA ($10),Y)
/// 3-4 addressing cycles: fetch ZP, fetch pointer, add Y (+ page fix if crossed)
const INDIRECT_INDEXED_READ_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 14, 35, 36, 15, 8 }, // fetchZpPointer, fetchPointerLow, fetchPointerHigh, addYCheckPage, fixHighByte
    .max_cycles = 5,
    .operand_source = .temp_value,
};

/// Indirect indexed write - address at (00:XX) + Y (STA ($10),Y)
/// 4 addressing cycles: fetch ZP, fetch pointer, add Y + dummy read
const INDIRECT_INDEXED_WRITE_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 14, 35, 36, 15 }, // fetchZpPointer, fetchPointerLow, fetchPointerHigh, addYCheckPage
    .max_cycles = 4,
    .operand_source = .effective_addr,
};

/// Indirect indexed RMW - address at (00:XX) + Y (SLO ($10),Y)
/// 6 addressing cycles: fetch ZP, fetch pointer, add Y, dummy read, read value, dummy write
const INDIRECT_INDEXED_RMW_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 14, 35, 36, 15, 8, 1, 2 }, // fetchZpPointer, fetchPointerLow, fetchPointerHigh, addYCheckPage, fixHighByte, rmwRead, rmwDummyWrite
    .max_cycles = 7,
    .operand_source = .temp_value,
};

// === Relative (Branches) ===

/// Relative addressing - signed offset for branches (BEQ, BNE, etc.)
/// 1-3 addressing cycles: fetch offset (+ branch taken + page cross)
/// Note: Branches have variable length based on taken/not-taken and page crossing
const RELATIVE_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 16, 17, 18 }, // branchFetchOffset, branchAddOffset, branchFixPch
    .max_cycles = 3,
    .operand_source = .operand_low,
};

// === Indirect (JMP only) ===

/// Indirect addressing - JMP ($1234) with page wrap bug
/// 4 addressing cycles: fetch pointer address, fetch target address
const INDIRECT_JMP_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 5, 6, 19, 20 }, // fetchAbsLow, fetchAbsHigh, jmpIndirectFetchLow, jmpIndirectFetchHigh
    .max_cycles = 4,
    .operand_source = .none, // JMP doesn't use operand, just sets PC
};

// ============================================================================
// Special Opcode Sequences (8 opcodes with unique timing)
// ============================================================================

/// JSR - Jump to Subroutine (0x20) - 6 cycles total
/// Pushes return address (PC-1) to stack, sets PC to target
const JSR_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 5, 21, 22, 23, 24 }, // fetchAbsLow, jsrStackDummy, pushPch, pushPcl, fetchAbsHighJsr
    .max_cycles = 5,
    .operand_source = .none,
};

/// RTS - Return from Subroutine (0x60) - 6 cycles total
/// Pulls return address from stack, increments PC
const RTS_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 25, 25, 26, 27, 28 }, // stackDummyRead, stackDummyRead, pullPcl, pullPch, incrementPcAfterRts
    .max_cycles = 5,
    .operand_source = .none,
};

/// RTI - Return from Interrupt (0x40) - 6 cycles total
/// Pulls status flags and return address from stack
const RTI_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 25, 29, 26, 27, 30 }, // stackDummyRead, pullStatus, pullPcl, pullPch, dummyReadPc
    .max_cycles = 5,
    .operand_source = .none,
};

/// BRK - Software Interrupt (0x00) - 7 cycles total
/// Pushes PC+2 and status to stack, loads IRQ vector
const BRK_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 0, 22, 23, 31, 32, 33 }, // fetchOperandLow, pushPch, pushPcl, pushStatusBrk, fetchIrqVectorLow, fetchIrqVectorHigh
    .max_cycles = 6,
    .operand_source = .none,
};

/// PHA - Push Accumulator (0x48) - 3 cycles total
/// Pushes A to stack
const PHA_SEQ = MicrostepSequence{
    .steps = &[_]u8{25}, // stackDummyRead
    .max_cycles = 1,
    .operand_source = .none,
};

/// PHP - Push Processor Status (0x08) - 3 cycles total
/// Pushes P to stack with B flag set
const PHP_SEQ = MicrostepSequence{
    .steps = &[_]u8{25}, // stackDummyRead
    .max_cycles = 1,
    .operand_source = .none,
};

/// PLA - Pull Accumulator (0x68) - 4 cycles total
/// Pulls A from stack
const PLA_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 25, 34 }, // stackDummyRead, pullByte
    .max_cycles = 2,
    .operand_source = .temp_value,
};

/// PLP - Pull Processor Status (0x28) - 4 cycles total
/// Pulls P from stack
const PLP_SEQ = MicrostepSequence{
    .steps = &[_]u8{ 25, 29 }, // stackDummyRead, pullStatus
    .max_cycles = 2,
    .operand_source = .none,
};

// ============================================================================
// Table Builder
// ============================================================================

/// Get microstep sequence for an addressing mode and operation type
fn getSequenceForMode(mode: decode.AddressingMode, is_rmw: bool, is_write: bool) MicrostepSequence {
    return switch (mode) {
        .immediate => IMMEDIATE_SEQ,
        .accumulator => ACCUMULATOR_SEQ,
        .implied => IMPLIED_SEQ,
        .zero_page => if (is_rmw) ZERO_PAGE_RMW_SEQ else ZERO_PAGE_READ_SEQ,
        .zero_page_x => if (is_rmw) ZERO_PAGE_X_RMW_SEQ else ZERO_PAGE_X_READ_SEQ,
        .zero_page_y => ZERO_PAGE_Y_READ_SEQ,
        .absolute => blk: {
            if (is_rmw) {
                break :blk ABSOLUTE_RMW_SEQ;
            } else if (is_write) {
                break :blk ABSOLUTE_WRITE_SEQ;
            } else {
                break :blk ABSOLUTE_READ_SEQ;
            }
        },
        .absolute_x => blk: {
            if (is_rmw) {
                break :blk ABSOLUTE_X_RMW_SEQ;
            } else if (is_write) {
                break :blk ABSOLUTE_X_WRITE_SEQ;
            } else {
                break :blk ABSOLUTE_X_READ_SEQ;
            }
        },
        .absolute_y => blk: {
            if (is_rmw) {
                break :blk ABSOLUTE_Y_RMW_SEQ;
            } else if (is_write) {
                break :blk ABSOLUTE_Y_WRITE_SEQ;
            } else {
                break :blk ABSOLUTE_Y_READ_SEQ;
            }
        },
        .indexed_indirect => if (is_rmw) INDEXED_INDIRECT_RMW_SEQ else INDEXED_INDIRECT_READ_SEQ,
        .indirect_indexed => blk: {
            if (is_rmw) {
                break :blk INDIRECT_INDEXED_RMW_SEQ;
            } else if (is_write) {
                break :blk INDIRECT_INDEXED_WRITE_SEQ;
            } else {
                break :blk INDIRECT_INDEXED_READ_SEQ;
            }
        },
        .relative => RELATIVE_SEQ,
        .indirect => INDIRECT_JMP_SEQ,
    };
}

/// Build complete microstep table for all 256 opcodes
/// Called at comptime to create MICROSTEP_TABLE constant
pub fn buildMicrostepTable() [256]MicrostepSequence {
    @setEvalBranchQuota(100000);
    var table: [256]MicrostepSequence = undefined;

    // Default: Populate from addressing mode
    for (0..256) |i| {
        const dispatch_entry = dispatch.DISPATCH_TABLE[i];
        const is_write = isWriteOpcode(@intCast(i));
        table[i] = getSequenceForMode(
            dispatch_entry.info.mode,
            dispatch_entry.is_rmw,
            is_write,
        );
    }

    // Override special opcodes that don't follow addressing mode patterns
    table[0x20] = JSR_SEQ; // JSR
    table[0x60] = RTS_SEQ; // RTS
    table[0x40] = RTI_SEQ; // RTI
    table[0x00] = BRK_SEQ; // BRK
    table[0x48] = PHA_SEQ; // PHA
    table[0x08] = PHP_SEQ; // PHP
    table[0x68] = PLA_SEQ; // PLA
    table[0x28] = PLP_SEQ; // PLP

    return table;
}

/// Determine if an opcode is a write operation (for absolute_x/y/indirect_indexed)
/// Write operations always take the dummy read cycle (no early completion on page cross)
fn isWriteOpcode(opcode: u8) bool {
    return switch (opcode) {
        // STA - all modes
        0x85, 0x95, 0x8D, 0x9D, 0x99, 0x81, 0x91 => true,
        // STX - all modes
        0x86, 0x96, 0x8E => true,
        // STY - all modes
        0x84, 0x94, 0x8C => true,
        // SAX - unofficial
        0x87, 0x97, 0x8F, 0x83 => true,
        // SHA - unofficial
        0x9F, 0x93 => true,
        // SHX - unofficial
        0x9E => true,
        // SHY - unofficial
        0x9C => true,
        // TAS - unofficial
        0x9B => true,
        else => false,
    };
}

/// The complete microstep dispatch table
/// Built at comptime, indexed by opcode
pub const MICROSTEP_TABLE = buildMicrostepTable();
