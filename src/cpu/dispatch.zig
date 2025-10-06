//! CPU Instruction Dispatch System
//!
//! This module provides the dispatch table that maps all 256 6502 opcodes to
//! their pure function implementations and addressing mode microsteps.
//!
//! Architecture:
//! - Pure opcode functions return OpcodeResult (delta structure)
//! - Addressing microsteps populate operands in CpuState
//! - Execution engine calls pure function, then applies result
//! - Unofficial opcodes use comptime variant dispatch (RP2A03G default)
//!
//! Organization:
//! - Type definitions (MicrostepFn, OpcodeFn, DispatchEntry)
//! - Helper functions to build dispatch table by category
//! - buildDispatchTable() orchestrates all helpers
//!
//! References:
//! - Code Review: docs/code-review/02-cpu.md (dispatch refactoring)
//! - Opcode Table: src/cpu/decode.zig (metadata)
//! - Pure Functions: src/cpu/opcodes.zig (implementations)
//! - Variant Dispatch: src/cpu/variants.zig (comptime variant specialization)

const std = @import("std");
const Cpu = @import("Cpu.zig");
const decode = @import("decode.zig");

// Import pure opcode implementations
const Opcodes = @import("opcodes/mod.zig");
const StateModule = @import("State.zig");
const variants = @import("variants.zig");

// Default CPU variant for dispatch table (RP2A03G - standard NTSC)
// This is the most common NES CPU revision and AccuracyCoin target
const DefaultCpuVariant = variants.Cpu(.rp2a03g);

const CpuCoreState = StateModule.CpuCoreState; // Pure CPU state (for opcodes)
const OpcodeResult = StateModule.OpcodeResult;

// ============================================================================
// Type Definitions
// ============================================================================

/// Opcode function signature
/// Takes core CPU state (read-only) and operand value, returns delta structure
pub const OpcodeFn = *const fn (CpuCoreState, u8) OpcodeResult;

/// Dispatch table entry - pure metadata, no function pointers for addressing
/// EmulationState uses info.mode to inline the correct addressing logic
pub const DispatchEntry = struct {
    /// Opcode function (returns delta)
    operation: OpcodeFn,

    /// Opcode metadata (mnemonic, addressing mode, cycles, etc.)
    info: decode.OpcodeInfo,

    /// Read-Modify-Write operation flag
    /// RMW operations have temp_value pre-loaded during addressing
    is_rmw: bool = false,

    /// Stack pull operation flag
    /// Pull operations (PLA, PLP) have temp_value loaded during addressing
    is_pull: bool = false,
};

// ============================================================================
// Global Dispatch Table
// ============================================================================

/// The complete dispatch table for all 256 opcodes
/// Built at comptime via buildDispatchTable()
pub const DISPATCH_TABLE = buildDispatchTable();

// ============================================================================
// Dispatch Table Builder (Main Orchestrator)
// ============================================================================

/// Build the complete dispatch table for all 256 opcodes
///
/// This function orchestrates category-specific helpers to populate
/// the dispatch table. Each helper handles a logical group of opcodes
/// (e.g., load/store, arithmetic, branches).
///
/// Organization improves maintainability by:
/// - Breaking 1370-line monolith into focused helpers
/// - Grouping related opcodes together
/// - Making patterns more visible
pub fn buildDispatchTable() [256]DispatchEntry {
    @setEvalBranchQuota(100000);
    var table: [256]DispatchEntry = undefined;

    // Initialize all entries with NOP (handles illegal opcodes)
    for (&table, 0..) |*entry, i| {
        entry.* = .{
            
            .operation = Opcodes.nop,
            .info = decode.OPCODE_TABLE[i],
        };
    }

    // Populate table by category
    buildNopOpcodes(&table);
    buildLoadStoreOpcodes(&table);
    buildArithmeticOpcodes(&table);
    buildLogicalOpcodes(&table);
    buildCompareOpcodes(&table);
    buildShiftRotateOpcodes(&table);
    buildIncDecOpcodes(&table);
    buildTransferOpcodes(&table);
    buildFlagOpcodes(&table);
    buildStackOpcodes(&table);
    buildBranchOpcodes(&table);
    buildJumpOpcodes(&table);
    buildUnofficialOpcodes(&table);

    return table;
}

// ============================================================================
// Category Helpers (Organized by Instruction Type)
// ============================================================================

/// NOP Instructions (Official and Unofficial)
fn buildNopOpcodes(table: *[256]DispatchEntry) void {
    // Official NOP - 0xEA (Implied, 2 cycles)
    table[0xEA] = .{
        
        .operation = Opcodes.nop,
        .info = decode.OPCODE_TABLE[0xEA],
    };

    // Unofficial 1-byte implied NOPs (2 cycles)
    const implied_nops = [_]u8{ 0x1A, 0x3A, 0x5A, 0x7A, 0xDA, 0xFA };
    for (implied_nops) |op| {
        table[op] = .{
            
            .operation = Opcodes.nop,
            .info = decode.OPCODE_TABLE[op],
        };
    }

    // Unofficial 2-byte immediate NOPs (2 cycles) - DOP
    const imm_nops = [_]u8{ 0x80, 0x82, 0x89, 0xC2, 0xE2 };
    for (imm_nops) |op| {
        table[op] = .{
            
            .operation = Opcodes.nop,
            .info = decode.OPCODE_TABLE[op],
        };
    }

    // Unofficial zero page NOPs (3 cycles)
    const zp_nops = [_]u8{ 0x04, 0x44, 0x64 };
    for (zp_nops) |op| {
        table[op] = .{
            
            .operation = Opcodes.nop,
            .info = decode.OPCODE_TABLE[op],
        };
    }

    // Unofficial zero page,X NOPs (4 cycles)
    const zpx_nops = [_]u8{ 0x14, 0x34, 0x54, 0x74, 0xD4, 0xF4 };
    for (zpx_nops) |op| {
        table[op] = .{
            
            .operation = Opcodes.nop,
            .info = decode.OPCODE_TABLE[op],
        };
    }

    // Unofficial 3-byte absolute NOPs (4 cycles) - TOP
    const abs_nops = [_]u8{0x0C};
    for (abs_nops) |op| {
        table[op] = .{
            
            .operation = Opcodes.nop,
            .info = decode.OPCODE_TABLE[op],
        };
    }

    // Unofficial absolute,X NOPs (4-5 cycles)
    const absx_nops = [_]u8{ 0x1C, 0x3C, 0x5C, 0x7C, 0xDC, 0xFC };
    for (absx_nops) |op| {
        table[op] = .{
            
            .operation = Opcodes.nop,
            .info = decode.OPCODE_TABLE[op],
        };
    }
}

/// Load and Store Instructions
fn buildLoadStoreOpcodes(table: *[256]DispatchEntry) void {
    // ===== LDA - Load Accumulator =====
    table[0xA9] = .{  .operation = Opcodes.lda, .info = decode.OPCODE_TABLE[0xA9] };
    table[0xA5] = .{  .operation = Opcodes.lda, .info = decode.OPCODE_TABLE[0xA5] };
    table[0xB5] = .{  .operation = Opcodes.lda, .info = decode.OPCODE_TABLE[0xB5] };
    table[0xAD] = .{  .operation = Opcodes.lda, .info = decode.OPCODE_TABLE[0xAD] };
    table[0xBD] = .{  .operation = Opcodes.lda, .info = decode.OPCODE_TABLE[0xBD] };
    table[0xB9] = .{  .operation = Opcodes.lda, .info = decode.OPCODE_TABLE[0xB9] };
    table[0xA1] = .{  .operation = Opcodes.lda, .info = decode.OPCODE_TABLE[0xA1] };
    table[0xB1] = .{  .operation = Opcodes.lda, .info = decode.OPCODE_TABLE[0xB1] };

    // ===== LDX - Load X Register =====
    table[0xA2] = .{  .operation = Opcodes.ldx, .info = decode.OPCODE_TABLE[0xA2] };
    table[0xA6] = .{  .operation = Opcodes.ldx, .info = decode.OPCODE_TABLE[0xA6] };
    table[0xB6] = .{  .operation = Opcodes.ldx, .info = decode.OPCODE_TABLE[0xB6] };
    table[0xAE] = .{  .operation = Opcodes.ldx, .info = decode.OPCODE_TABLE[0xAE] };
    table[0xBE] = .{  .operation = Opcodes.ldx, .info = decode.OPCODE_TABLE[0xBE] };

    // ===== LDY - Load Y Register =====
    table[0xA0] = .{  .operation = Opcodes.ldy, .info = decode.OPCODE_TABLE[0xA0] };
    table[0xA4] = .{  .operation = Opcodes.ldy, .info = decode.OPCODE_TABLE[0xA4] };
    table[0xB4] = .{  .operation = Opcodes.ldy, .info = decode.OPCODE_TABLE[0xB4] };
    table[0xAC] = .{  .operation = Opcodes.ldy, .info = decode.OPCODE_TABLE[0xAC] };
    table[0xBC] = .{  .operation = Opcodes.ldy, .info = decode.OPCODE_TABLE[0xBC] };

    // ===== STA - Store Accumulator =====
    table[0x85] = .{  .operation = Opcodes.sta, .info = decode.OPCODE_TABLE[0x85] };
    table[0x95] = .{  .operation = Opcodes.sta, .info = decode.OPCODE_TABLE[0x95] };
    table[0x8D] = .{  .operation = Opcodes.sta, .info = decode.OPCODE_TABLE[0x8D] };
    table[0x9D] = .{  .operation = Opcodes.sta, .info = decode.OPCODE_TABLE[0x9D] };
    table[0x99] = .{  .operation = Opcodes.sta, .info = decode.OPCODE_TABLE[0x99] };
    table[0x81] = .{  .operation = Opcodes.sta, .info = decode.OPCODE_TABLE[0x81] };
    table[0x91] = .{  .operation = Opcodes.sta, .info = decode.OPCODE_TABLE[0x91] };

    // ===== STX - Store X Register =====
    table[0x86] = .{  .operation = Opcodes.stx, .info = decode.OPCODE_TABLE[0x86] };
    table[0x96] = .{  .operation = Opcodes.stx, .info = decode.OPCODE_TABLE[0x96] };
    table[0x8E] = .{  .operation = Opcodes.stx, .info = decode.OPCODE_TABLE[0x8E] };

    // ===== STY - Store Y Register =====
    table[0x84] = .{  .operation = Opcodes.sty, .info = decode.OPCODE_TABLE[0x84] };
    table[0x94] = .{  .operation = Opcodes.sty, .info = decode.OPCODE_TABLE[0x94] };
    table[0x8C] = .{  .operation = Opcodes.sty, .info = decode.OPCODE_TABLE[0x8C] };
}

/// Arithmetic Instructions (ADC, SBC)
fn buildArithmeticOpcodes(table: *[256]DispatchEntry) void {
    // ===== ADC - Add with Carry =====
    table[0x69] = .{  .operation = Opcodes.adc, .info = decode.OPCODE_TABLE[0x69] };
    table[0x65] = .{  .operation = Opcodes.adc, .info = decode.OPCODE_TABLE[0x65] };
    table[0x75] = .{  .operation = Opcodes.adc, .info = decode.OPCODE_TABLE[0x75] };
    table[0x6D] = .{  .operation = Opcodes.adc, .info = decode.OPCODE_TABLE[0x6D] };
    table[0x7D] = .{  .operation = Opcodes.adc, .info = decode.OPCODE_TABLE[0x7D] };
    table[0x79] = .{  .operation = Opcodes.adc, .info = decode.OPCODE_TABLE[0x79] };
    table[0x61] = .{  .operation = Opcodes.adc, .info = decode.OPCODE_TABLE[0x61] };
    table[0x71] = .{  .operation = Opcodes.adc, .info = decode.OPCODE_TABLE[0x71] };

    // ===== SBC - Subtract with Carry =====
    table[0xE9] = .{  .operation = Opcodes.sbc, .info = decode.OPCODE_TABLE[0xE9] };
    table[0xE5] = .{  .operation = Opcodes.sbc, .info = decode.OPCODE_TABLE[0xE5] };
    table[0xF5] = .{  .operation = Opcodes.sbc, .info = decode.OPCODE_TABLE[0xF5] };
    table[0xED] = .{  .operation = Opcodes.sbc, .info = decode.OPCODE_TABLE[0xED] };
    table[0xFD] = .{  .operation = Opcodes.sbc, .info = decode.OPCODE_TABLE[0xFD] };
    table[0xF9] = .{  .operation = Opcodes.sbc, .info = decode.OPCODE_TABLE[0xF9] };
    table[0xE1] = .{  .operation = Opcodes.sbc, .info = decode.OPCODE_TABLE[0xE1] };
    table[0xF1] = .{  .operation = Opcodes.sbc, .info = decode.OPCODE_TABLE[0xF1] };

    // ===== SBC Unofficial Duplicate (0xEB) =====
    table[0xEB] = .{  .operation = Opcodes.sbc, .info = decode.OPCODE_TABLE[0xEB] };
}

/// Logical Instructions (AND, ORA, EOR)
fn buildLogicalOpcodes(table: *[256]DispatchEntry) void {
    // ===== AND - Logical AND =====
    table[0x29] = .{  .operation = Opcodes.logicalAnd, .info = decode.OPCODE_TABLE[0x29] };
    table[0x25] = .{  .operation = Opcodes.logicalAnd, .info = decode.OPCODE_TABLE[0x25] };
    table[0x35] = .{  .operation = Opcodes.logicalAnd, .info = decode.OPCODE_TABLE[0x35] };
    table[0x2D] = .{  .operation = Opcodes.logicalAnd, .info = decode.OPCODE_TABLE[0x2D] };
    table[0x3D] = .{  .operation = Opcodes.logicalAnd, .info = decode.OPCODE_TABLE[0x3D] };
    table[0x39] = .{  .operation = Opcodes.logicalAnd, .info = decode.OPCODE_TABLE[0x39] };
    table[0x21] = .{  .operation = Opcodes.logicalAnd, .info = decode.OPCODE_TABLE[0x21] };
    table[0x31] = .{  .operation = Opcodes.logicalAnd, .info = decode.OPCODE_TABLE[0x31] };

    // ===== ORA - Logical OR =====
    table[0x09] = .{  .operation = Opcodes.logicalOr, .info = decode.OPCODE_TABLE[0x09] };
    table[0x05] = .{  .operation = Opcodes.logicalOr, .info = decode.OPCODE_TABLE[0x05] };
    table[0x15] = .{  .operation = Opcodes.logicalOr, .info = decode.OPCODE_TABLE[0x15] };
    table[0x0D] = .{  .operation = Opcodes.logicalOr, .info = decode.OPCODE_TABLE[0x0D] };
    table[0x1D] = .{  .operation = Opcodes.logicalOr, .info = decode.OPCODE_TABLE[0x1D] };
    table[0x19] = .{  .operation = Opcodes.logicalOr, .info = decode.OPCODE_TABLE[0x19] };
    table[0x01] = .{  .operation = Opcodes.logicalOr, .info = decode.OPCODE_TABLE[0x01] };
    table[0x11] = .{  .operation = Opcodes.logicalOr, .info = decode.OPCODE_TABLE[0x11] };

    // ===== EOR - Logical XOR =====
    table[0x49] = .{  .operation = Opcodes.logicalXor, .info = decode.OPCODE_TABLE[0x49] };
    table[0x45] = .{  .operation = Opcodes.logicalXor, .info = decode.OPCODE_TABLE[0x45] };
    table[0x55] = .{  .operation = Opcodes.logicalXor, .info = decode.OPCODE_TABLE[0x55] };
    table[0x4D] = .{  .operation = Opcodes.logicalXor, .info = decode.OPCODE_TABLE[0x4D] };
    table[0x5D] = .{  .operation = Opcodes.logicalXor, .info = decode.OPCODE_TABLE[0x5D] };
    table[0x59] = .{  .operation = Opcodes.logicalXor, .info = decode.OPCODE_TABLE[0x59] };
    table[0x41] = .{  .operation = Opcodes.logicalXor, .info = decode.OPCODE_TABLE[0x41] };
    table[0x51] = .{  .operation = Opcodes.logicalXor, .info = decode.OPCODE_TABLE[0x51] };
}

/// Compare Instructions (CMP, CPX, CPY, BIT)
fn buildCompareOpcodes(table: *[256]DispatchEntry) void {
    // ===== CMP - Compare Accumulator =====
    table[0xC9] = .{  .operation = Opcodes.cmp, .info = decode.OPCODE_TABLE[0xC9] };
    table[0xC5] = .{  .operation = Opcodes.cmp, .info = decode.OPCODE_TABLE[0xC5] };
    table[0xD5] = .{  .operation = Opcodes.cmp, .info = decode.OPCODE_TABLE[0xD5] };
    table[0xCD] = .{  .operation = Opcodes.cmp, .info = decode.OPCODE_TABLE[0xCD] };
    table[0xDD] = .{  .operation = Opcodes.cmp, .info = decode.OPCODE_TABLE[0xDD] };
    table[0xD9] = .{  .operation = Opcodes.cmp, .info = decode.OPCODE_TABLE[0xD9] };
    table[0xC1] = .{  .operation = Opcodes.cmp, .info = decode.OPCODE_TABLE[0xC1] };
    table[0xD1] = .{  .operation = Opcodes.cmp, .info = decode.OPCODE_TABLE[0xD1] };

    // ===== CPX - Compare X Register =====
    table[0xE0] = .{  .operation = Opcodes.cpx, .info = decode.OPCODE_TABLE[0xE0] };
    table[0xE4] = .{  .operation = Opcodes.cpx, .info = decode.OPCODE_TABLE[0xE4] };
    table[0xEC] = .{  .operation = Opcodes.cpx, .info = decode.OPCODE_TABLE[0xEC] };

    // ===== CPY - Compare Y Register =====
    table[0xC0] = .{  .operation = Opcodes.cpy, .info = decode.OPCODE_TABLE[0xC0] };
    table[0xC4] = .{  .operation = Opcodes.cpy, .info = decode.OPCODE_TABLE[0xC4] };
    table[0xCC] = .{  .operation = Opcodes.cpy, .info = decode.OPCODE_TABLE[0xCC] };

    // ===== BIT - Test Bits =====
    table[0x24] = .{  .operation = Opcodes.bit, .info = decode.OPCODE_TABLE[0x24] };
    table[0x2C] = .{  .operation = Opcodes.bit, .info = decode.OPCODE_TABLE[0x2C] };
}

/// Shift/Rotate Instructions (ASL, LSR, ROL, ROR)
fn buildShiftRotateOpcodes(table: *[256]DispatchEntry) void {
    // ===== ASL - Arithmetic Shift Left =====
    table[0x0A] = .{  .operation = Opcodes.aslAcc, .info = decode.OPCODE_TABLE[0x0A] }; // Accumulator
    table[0x06] = .{  .operation = Opcodes.aslMem, .info = decode.OPCODE_TABLE[0x06], .is_rmw = true };
    table[0x16] = .{  .operation = Opcodes.aslMem, .info = decode.OPCODE_TABLE[0x16], .is_rmw = true };
    table[0x0E] = .{  .operation = Opcodes.aslMem, .info = decode.OPCODE_TABLE[0x0E], .is_rmw = true };
    table[0x1E] = .{  .operation = Opcodes.aslMem, .info = decode.OPCODE_TABLE[0x1E], .is_rmw = true };

    // ===== LSR - Logical Shift Right =====
    table[0x4A] = .{  .operation = Opcodes.lsrAcc, .info = decode.OPCODE_TABLE[0x4A] }; // Accumulator
    table[0x46] = .{  .operation = Opcodes.lsrMem, .info = decode.OPCODE_TABLE[0x46], .is_rmw = true };
    table[0x56] = .{  .operation = Opcodes.lsrMem, .info = decode.OPCODE_TABLE[0x56], .is_rmw = true };
    table[0x4E] = .{  .operation = Opcodes.lsrMem, .info = decode.OPCODE_TABLE[0x4E], .is_rmw = true };
    table[0x5E] = .{  .operation = Opcodes.lsrMem, .info = decode.OPCODE_TABLE[0x5E], .is_rmw = true };

    // ===== ROL - Rotate Left =====
    table[0x2A] = .{  .operation = Opcodes.rolAcc, .info = decode.OPCODE_TABLE[0x2A] }; // Accumulator
    table[0x26] = .{  .operation = Opcodes.rolMem, .info = decode.OPCODE_TABLE[0x26], .is_rmw = true };
    table[0x36] = .{  .operation = Opcodes.rolMem, .info = decode.OPCODE_TABLE[0x36], .is_rmw = true };
    table[0x2E] = .{  .operation = Opcodes.rolMem, .info = decode.OPCODE_TABLE[0x2E], .is_rmw = true };
    table[0x3E] = .{  .operation = Opcodes.rolMem, .info = decode.OPCODE_TABLE[0x3E], .is_rmw = true };

    // ===== ROR - Rotate Right =====
    table[0x6A] = .{  .operation = Opcodes.rorAcc, .info = decode.OPCODE_TABLE[0x6A] }; // Accumulator
    table[0x66] = .{  .operation = Opcodes.rorMem, .info = decode.OPCODE_TABLE[0x66], .is_rmw = true };
    table[0x76] = .{  .operation = Opcodes.rorMem, .info = decode.OPCODE_TABLE[0x76], .is_rmw = true };
    table[0x6E] = .{  .operation = Opcodes.rorMem, .info = decode.OPCODE_TABLE[0x6E], .is_rmw = true };
    table[0x7E] = .{  .operation = Opcodes.rorMem, .info = decode.OPCODE_TABLE[0x7E], .is_rmw = true };
}

/// Increment/Decrement Instructions
fn buildIncDecOpcodes(table: *[256]DispatchEntry) void {
    // ===== INC - Increment Memory =====
    table[0xE6] = .{  .operation = Opcodes.inc, .info = decode.OPCODE_TABLE[0xE6], .is_rmw = true };
    table[0xF6] = .{  .operation = Opcodes.inc, .info = decode.OPCODE_TABLE[0xF6], .is_rmw = true };
    table[0xEE] = .{  .operation = Opcodes.inc, .info = decode.OPCODE_TABLE[0xEE], .is_rmw = true };
    table[0xFE] = .{  .operation = Opcodes.inc, .info = decode.OPCODE_TABLE[0xFE], .is_rmw = true };

    // ===== DEC - Decrement Memory =====
    table[0xC6] = .{  .operation = Opcodes.dec, .info = decode.OPCODE_TABLE[0xC6], .is_rmw = true };
    table[0xD6] = .{  .operation = Opcodes.dec, .info = decode.OPCODE_TABLE[0xD6], .is_rmw = true };
    table[0xCE] = .{  .operation = Opcodes.dec, .info = decode.OPCODE_TABLE[0xCE], .is_rmw = true };
    table[0xDE] = .{  .operation = Opcodes.dec, .info = decode.OPCODE_TABLE[0xDE], .is_rmw = true };

    // ===== Register Inc/Dec Instructions =====
    table[0xE8] = .{  .operation = Opcodes.inx, .info = decode.OPCODE_TABLE[0xE8] }; // INX
    table[0xC8] = .{  .operation = Opcodes.iny, .info = decode.OPCODE_TABLE[0xC8] }; // INY
    table[0xCA] = .{  .operation = Opcodes.dex, .info = decode.OPCODE_TABLE[0xCA] }; // DEX
    table[0x88] = .{  .operation = Opcodes.dey, .info = decode.OPCODE_TABLE[0x88] }; // DEY
}

/// Transfer Instructions (TAX, TAY, TXA, TYA, TSX, TXS)
fn buildTransferOpcodes(table: *[256]DispatchEntry) void {
    table[0xAA] = .{  .operation = Opcodes.tax, .info = decode.OPCODE_TABLE[0xAA] }; // TAX
    table[0xA8] = .{  .operation = Opcodes.tay, .info = decode.OPCODE_TABLE[0xA8] }; // TAY
    table[0x8A] = .{  .operation = Opcodes.txa, .info = decode.OPCODE_TABLE[0x8A] }; // TXA
    table[0x98] = .{  .operation = Opcodes.tya, .info = decode.OPCODE_TABLE[0x98] }; // TYA
    table[0xBA] = .{  .operation = Opcodes.tsx, .info = decode.OPCODE_TABLE[0xBA] }; // TSX
    table[0x9A] = .{  .operation = Opcodes.txs, .info = decode.OPCODE_TABLE[0x9A] }; // TXS
}

/// Flag Instructions (CLC, CLD, CLI, CLV, SEC, SED, SEI)
fn buildFlagOpcodes(table: *[256]DispatchEntry) void {
    table[0x18] = .{  .operation = Opcodes.clc, .info = decode.OPCODE_TABLE[0x18] }; // CLC
    table[0xD8] = .{  .operation = Opcodes.cld, .info = decode.OPCODE_TABLE[0xD8] }; // CLD
    table[0x58] = .{  .operation = Opcodes.cli, .info = decode.OPCODE_TABLE[0x58] }; // CLI
    table[0xB8] = .{  .operation = Opcodes.clv, .info = decode.OPCODE_TABLE[0xB8] }; // CLV
    table[0x38] = .{  .operation = Opcodes.sec, .info = decode.OPCODE_TABLE[0x38] }; // SEC
    table[0xF8] = .{  .operation = Opcodes.sed, .info = decode.OPCODE_TABLE[0xF8] }; // SED
    table[0x78] = .{  .operation = Opcodes.sei, .info = decode.OPCODE_TABLE[0x78] }; // SEI
}

/// Stack Instructions (PHA, PHP, PLA, PLP)
fn buildStackOpcodes(table: *[256]DispatchEntry) void {
    // Push operations (3 cycles: fetch + dummy read + push)
    table[0x48] = .{  .operation = Opcodes.pha, .info = decode.OPCODE_TABLE[0x48] }; // PHA
    table[0x08] = .{  .operation = Opcodes.php, .info = decode.OPCODE_TABLE[0x08] }; // PHP

    // Pull operations (4 cycles: fetch + dummy read + pull + execute)
    table[0x68] = .{  .operation = Opcodes.pla, .info = decode.OPCODE_TABLE[0x68], .is_pull = true }; // PLA
    table[0x28] = .{  .operation = Opcodes.plp, .info = decode.OPCODE_TABLE[0x28], .is_pull = true }; // PLP
}

/// Branch Instructions (BCC, BCS, BEQ, BNE, BMI, BPL, BVC, BVS)
fn buildBranchOpcodes(table: *[256]DispatchEntry) void {
    table[0x90] = .{  .operation = Opcodes.bcc, .info = decode.OPCODE_TABLE[0x90] }; // BCC
    table[0xB0] = .{  .operation = Opcodes.bcs, .info = decode.OPCODE_TABLE[0xB0] }; // BCS
    table[0xF0] = .{  .operation = Opcodes.beq, .info = decode.OPCODE_TABLE[0xF0] }; // BEQ
    table[0xD0] = .{  .operation = Opcodes.bne, .info = decode.OPCODE_TABLE[0xD0] }; // BNE
    table[0x30] = .{  .operation = Opcodes.bmi, .info = decode.OPCODE_TABLE[0x30] }; // BMI
    table[0x10] = .{  .operation = Opcodes.bpl, .info = decode.OPCODE_TABLE[0x10] }; // BPL
    table[0x50] = .{  .operation = Opcodes.bvc, .info = decode.OPCODE_TABLE[0x50] }; // BVC
    table[0x70] = .{  .operation = Opcodes.bvs, .info = decode.OPCODE_TABLE[0x70] }; // BVS
}

/// Jump/Control Flow Instructions (JMP, JSR, RTS, RTI, BRK)
fn buildJumpOpcodes(table: *[256]DispatchEntry) void {
    // JMP opcodes (pure - just set PC to effective_address)
    table[0x4C] = .{  .operation = Opcodes.jmp, .info = decode.OPCODE_TABLE[0x4C] }; // JMP absolute
    table[0x6C] = .{  .operation = Opcodes.jmp, .info = decode.OPCODE_TABLE[0x6C] }; // JMP indirect

    // Control flow opcodes (microstep-based, no pure execution)
    // All logic is handled in microstep sequences - operation  is nop
    table[0x20] = .{  .operation = Opcodes.nop, .info = decode.OPCODE_TABLE[0x20] }; // JSR (6 cycles)
    table[0x60] = .{  .operation = Opcodes.nop, .info = decode.OPCODE_TABLE[0x60] }; // RTS (6 cycles)
    table[0x40] = .{  .operation = Opcodes.nop, .info = decode.OPCODE_TABLE[0x40] }; // RTI (6 cycles)
    table[0x00] = .{  .operation = Opcodes.nop, .info = decode.OPCODE_TABLE[0x00] }; // BRK (7 cycles)
}

/// Unofficial/Undocumented Opcodes
fn buildUnofficialOpcodes(table: *[256]DispatchEntry) void {
    // ===== LAX - Load A and X =====
    table[0xA7] = .{  .operation = DefaultCpuVariant.lax, .info = decode.OPCODE_TABLE[0xA7] };
    table[0xB7] = .{  .operation = DefaultCpuVariant.lax, .info = decode.OPCODE_TABLE[0xB7] };
    table[0xAF] = .{  .operation = DefaultCpuVariant.lax, .info = decode.OPCODE_TABLE[0xAF] };
    table[0xBF] = .{  .operation = DefaultCpuVariant.lax, .info = decode.OPCODE_TABLE[0xBF] };
    table[0xA3] = .{  .operation = DefaultCpuVariant.lax, .info = decode.OPCODE_TABLE[0xA3] };
    table[0xB3] = .{  .operation = DefaultCpuVariant.lax, .info = decode.OPCODE_TABLE[0xB3] };

    // ===== SAX - Store A AND X =====
    table[0x87] = .{  .operation = DefaultCpuVariant.sax, .info = decode.OPCODE_TABLE[0x87] };
    table[0x97] = .{  .operation = DefaultCpuVariant.sax, .info = decode.OPCODE_TABLE[0x97] };
    table[0x8F] = .{  .operation = DefaultCpuVariant.sax, .info = decode.OPCODE_TABLE[0x8F] };
    table[0x83] = .{  .operation = DefaultCpuVariant.sax, .info = decode.OPCODE_TABLE[0x83] };

    // ===== SLO - ASL + ORA (RMW) =====
    table[0x07] = .{  .operation = DefaultCpuVariant.slo, .info = decode.OPCODE_TABLE[0x07], .is_rmw = true };
    table[0x17] = .{  .operation = DefaultCpuVariant.slo, .info = decode.OPCODE_TABLE[0x17], .is_rmw = true };
    table[0x0F] = .{  .operation = DefaultCpuVariant.slo, .info = decode.OPCODE_TABLE[0x0F], .is_rmw = true };
    table[0x1F] = .{  .operation = DefaultCpuVariant.slo, .info = decode.OPCODE_TABLE[0x1F], .is_rmw = true };
    table[0x1B] = .{  .operation = DefaultCpuVariant.slo, .info = decode.OPCODE_TABLE[0x1B], .is_rmw = true }; // abs,Y uses X rmw steps
    table[0x03] = .{  .operation = DefaultCpuVariant.slo, .info = decode.OPCODE_TABLE[0x03], .is_rmw = true };
    table[0x13] = .{  .operation = DefaultCpuVariant.slo, .info = decode.OPCODE_TABLE[0x13], .is_rmw = true };

    // ===== RLA - ROL + AND (RMW) =====
    table[0x27] = .{  .operation = DefaultCpuVariant.rla, .info = decode.OPCODE_TABLE[0x27], .is_rmw = true };
    table[0x37] = .{  .operation = DefaultCpuVariant.rla, .info = decode.OPCODE_TABLE[0x37], .is_rmw = true };
    table[0x2F] = .{  .operation = DefaultCpuVariant.rla, .info = decode.OPCODE_TABLE[0x2F], .is_rmw = true };
    table[0x3F] = .{  .operation = DefaultCpuVariant.rla, .info = decode.OPCODE_TABLE[0x3F], .is_rmw = true };
    table[0x3B] = .{  .operation = DefaultCpuVariant.rla, .info = decode.OPCODE_TABLE[0x3B], .is_rmw = true };
    table[0x23] = .{  .operation = DefaultCpuVariant.rla, .info = decode.OPCODE_TABLE[0x23], .is_rmw = true };
    table[0x33] = .{  .operation = DefaultCpuVariant.rla, .info = decode.OPCODE_TABLE[0x33], .is_rmw = true };

    // ===== SRE - LSR + EOR (RMW) =====
    table[0x47] = .{  .operation = DefaultCpuVariant.sre, .info = decode.OPCODE_TABLE[0x47], .is_rmw = true };
    table[0x57] = .{  .operation = DefaultCpuVariant.sre, .info = decode.OPCODE_TABLE[0x57], .is_rmw = true };
    table[0x4F] = .{  .operation = DefaultCpuVariant.sre, .info = decode.OPCODE_TABLE[0x4F], .is_rmw = true };
    table[0x5F] = .{  .operation = DefaultCpuVariant.sre, .info = decode.OPCODE_TABLE[0x5F], .is_rmw = true };
    table[0x5B] = .{  .operation = DefaultCpuVariant.sre, .info = decode.OPCODE_TABLE[0x5B], .is_rmw = true };
    table[0x43] = .{  .operation = DefaultCpuVariant.sre, .info = decode.OPCODE_TABLE[0x43], .is_rmw = true };
    table[0x53] = .{  .operation = DefaultCpuVariant.sre, .info = decode.OPCODE_TABLE[0x53], .is_rmw = true };

    // ===== RRA - ROR + ADC (RMW) =====
    table[0x67] = .{  .operation = DefaultCpuVariant.rra, .info = decode.OPCODE_TABLE[0x67], .is_rmw = true };
    table[0x77] = .{  .operation = DefaultCpuVariant.rra, .info = decode.OPCODE_TABLE[0x77], .is_rmw = true };
    table[0x6F] = .{  .operation = DefaultCpuVariant.rra, .info = decode.OPCODE_TABLE[0x6F], .is_rmw = true };
    table[0x7F] = .{  .operation = DefaultCpuVariant.rra, .info = decode.OPCODE_TABLE[0x7F], .is_rmw = true };
    table[0x7B] = .{  .operation = DefaultCpuVariant.rra, .info = decode.OPCODE_TABLE[0x7B], .is_rmw = true };
    table[0x63] = .{  .operation = DefaultCpuVariant.rra, .info = decode.OPCODE_TABLE[0x63], .is_rmw = true };
    table[0x73] = .{  .operation = DefaultCpuVariant.rra, .info = decode.OPCODE_TABLE[0x73], .is_rmw = true };

    // ===== DCP - DEC + CMP (RMW) =====
    table[0xC7] = .{  .operation = DefaultCpuVariant.dcp, .info = decode.OPCODE_TABLE[0xC7], .is_rmw = true };
    table[0xD7] = .{  .operation = DefaultCpuVariant.dcp, .info = decode.OPCODE_TABLE[0xD7], .is_rmw = true };
    table[0xCF] = .{  .operation = DefaultCpuVariant.dcp, .info = decode.OPCODE_TABLE[0xCF], .is_rmw = true };
    table[0xDF] = .{  .operation = DefaultCpuVariant.dcp, .info = decode.OPCODE_TABLE[0xDF], .is_rmw = true };
    table[0xDB] = .{  .operation = DefaultCpuVariant.dcp, .info = decode.OPCODE_TABLE[0xDB], .is_rmw = true };
    table[0xC3] = .{  .operation = DefaultCpuVariant.dcp, .info = decode.OPCODE_TABLE[0xC3], .is_rmw = true };
    table[0xD3] = .{  .operation = DefaultCpuVariant.dcp, .info = decode.OPCODE_TABLE[0xD3], .is_rmw = true };

    // ===== ISC - INC + SBC (RMW) =====
    table[0xE7] = .{  .operation = DefaultCpuVariant.isc, .info = decode.OPCODE_TABLE[0xE7], .is_rmw = true };
    table[0xF7] = .{  .operation = DefaultCpuVariant.isc, .info = decode.OPCODE_TABLE[0xF7], .is_rmw = true };
    table[0xEF] = .{  .operation = DefaultCpuVariant.isc, .info = decode.OPCODE_TABLE[0xEF], .is_rmw = true };
    table[0xFF] = .{  .operation = DefaultCpuVariant.isc, .info = decode.OPCODE_TABLE[0xFF], .is_rmw = true };
    table[0xFB] = .{  .operation = DefaultCpuVariant.isc, .info = decode.OPCODE_TABLE[0xFB], .is_rmw = true };
    table[0xE3] = .{  .operation = DefaultCpuVariant.isc, .info = decode.OPCODE_TABLE[0xE3], .is_rmw = true };
    table[0xF3] = .{  .operation = DefaultCpuVariant.isc, .info = decode.OPCODE_TABLE[0xF3], .is_rmw = true };

    // ===== Immediate Logic/Math Instructions =====
    table[0x0B] = .{  .operation = DefaultCpuVariant.anc, .info = decode.OPCODE_TABLE[0x0B] }; // ANC
    table[0x2B] = .{  .operation = DefaultCpuVariant.anc, .info = decode.OPCODE_TABLE[0x2B] }; // ANC (duplicate)
    table[0x4B] = .{  .operation = DefaultCpuVariant.alr, .info = decode.OPCODE_TABLE[0x4B] }; // ALR
    table[0x6B] = .{  .operation = DefaultCpuVariant.arr, .info = decode.OPCODE_TABLE[0x6B] }; // ARR
    table[0x8B] = .{  .operation = DefaultCpuVariant.xaa, .info = decode.OPCODE_TABLE[0x8B] }; // XAA
    table[0xAB] = .{  .operation = DefaultCpuVariant.lxa, .info = decode.OPCODE_TABLE[0xAB] }; // LXA
    table[0xCB] = .{  .operation = DefaultCpuVariant.axs, .info = decode.OPCODE_TABLE[0xCB] }; // AXS

    // ===== Unstable Store Operations =====
    table[0x9F] = .{  .operation = DefaultCpuVariant.sha, .info = decode.OPCODE_TABLE[0x9F] }; // SHA abs,Y
    table[0x93] = .{  .operation = DefaultCpuVariant.sha, .info = decode.OPCODE_TABLE[0x93] }; // SHA (ind),Y
    table[0x9E] = .{  .operation = DefaultCpuVariant.shx, .info = decode.OPCODE_TABLE[0x9E] }; // SHX
    table[0x9C] = .{  .operation = DefaultCpuVariant.shy, .info = decode.OPCODE_TABLE[0x9C] }; // SHY
    table[0x9B] = .{  .operation = DefaultCpuVariant.tas, .info = decode.OPCODE_TABLE[0x9B] }; // TAS

    // ===== Other Unstable Load/Transfer =====
    table[0xBB] = .{  .operation = DefaultCpuVariant.lae, .info = decode.OPCODE_TABLE[0xBB] }; // LAE

    // ===== JAM/KIL - CPU Halt =====
    const jam_opcodes = [_]u8{ 0x02, 0x12, 0x22, 0x32, 0x42, 0x52, 0x62, 0x72, 0x92, 0xB2, 0xD2, 0xF2 };
    for (jam_opcodes) |op| {
        table[op] = .{
            
            .operation = DefaultCpuVariant.jam,
            .info = decode.OPCODE_TABLE[op],
        };
    }
}
