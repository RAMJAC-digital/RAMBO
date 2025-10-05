//! CPU Instruction Dispatch System
//!
//! This module provides the dispatch table that maps all 256 6502 opcodes to
//! their pure function implementations and addressing mode microsteps.
//!
//! Architecture:
//! - Pure opcode functions return OpcodeResult (delta structure)
//! - Addressing microsteps populate operands in CpuState
//! - Execution engine calls pure function, then applies result
//!
//! Organization:
//! - Type definitions (MicrostepFn, PureOpcodeFn, DispatchEntry)
//! - Helper functions to build dispatch table by category
//! - buildDispatchTable() orchestrates all helpers
//!
//! References:
//! - Code Review: docs/code-review/02-cpu.md (dispatch refactoring)
//! - Opcode Table: src/cpu/decode.zig (metadata)
//! - Pure Functions: src/cpu/opcodes.zig (implementations)

const std = @import("std");
const Cpu = @import("Cpu.zig");
const BusModule = @import("../bus/Bus.zig");
const decode = @import("decode.zig");
const addressing = @import("addressing.zig");

// Import pure opcode implementations
const Opcodes = @import("opcodes/mod.zig");
const StateModule = @import("State.zig");

const CpuState = Cpu.State.CpuState;  // Full CPU state (for microsteps)
const PureCpuState = StateModule.PureCpuState;  // Pure CPU state (for opcodes)
const BusState = BusModule.State.BusState;
const OpcodeResult = StateModule.OpcodeResult;

// ============================================================================
// Type Definitions
// ============================================================================

/// Microstep function signature for addressing modes
/// Returns true when addressing is complete
pub const MicrostepFn = *const fn (*CpuState, *BusState) bool;

/// Pure opcode function signature
/// Takes pure CPU state (read-only) and operand value, returns delta structure
pub const PureOpcodeFn = *const fn (PureCpuState, u8) OpcodeResult;

/// Dispatch table entry combining addressing and pure execution
pub const DispatchEntry = struct {
    /// Addressing mode microsteps (populated by addressing.zig)
    addressing_steps: []const MicrostepFn,

    /// Pure opcode function (returns delta)
    execute_pure: PureOpcodeFn,

    /// Opcode metadata (mnemonic, cycles, etc.)
    info: decode.OpcodeInfo,

    /// Read-Modify-Write operation flag
    /// RMW operations have temp_value pre-loaded by rmwRead microstep
    /// Non-RMW operations need to read operand value in execute phase
    is_rmw: bool = false,

    /// Stack pull operation flag
    /// Pull operations (PLA, PLP) have temp_value loaded by pullByte microstep
    /// Execute phase uses temp_value as operand (like RMW operations)
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
            .addressing_steps = &[_]MicrostepFn{},
            .execute_pure = Opcodes.nop,
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
        .addressing_steps = &[_]MicrostepFn{},
        .execute_pure = Opcodes.nop,
        .info = decode.OPCODE_TABLE[0xEA],
    };

    // Unofficial 1-byte implied NOPs (2 cycles)
    const implied_nops = [_]u8{ 0x1A, 0x3A, 0x5A, 0x7A, 0xDA, 0xFA };
    for (implied_nops) |op| {
        table[op] = .{
            .addressing_steps = &[_]MicrostepFn{},
            .execute_pure = Opcodes.nop,
            .info = decode.OPCODE_TABLE[op],
        };
    }

    // Unofficial 2-byte immediate NOPs (2 cycles) - DOP
    const imm_nops = [_]u8{ 0x80, 0x82, 0x89, 0xC2, 0xE2 };
    for (imm_nops) |op| {
        table[op] = .{
            .addressing_steps = &addressing.immediate_steps,
            .execute_pure = Opcodes.nop,
            .info = decode.OPCODE_TABLE[op],
        };
    }

    // Unofficial zero page NOPs (3 cycles)
    const zp_nops = [_]u8{ 0x04, 0x44, 0x64 };
    for (zp_nops) |op| {
        table[op] = .{
            .addressing_steps = &addressing.zero_page_steps,
            .execute_pure = Opcodes.nop,
            .info = decode.OPCODE_TABLE[op],
        };
    }

    // Unofficial zero page,X NOPs (4 cycles)
    const zpx_nops = [_]u8{ 0x14, 0x34, 0x54, 0x74, 0xD4, 0xF4 };
    for (zpx_nops) |op| {
        table[op] = .{
            .addressing_steps = &addressing.zero_page_x_steps,
            .execute_pure = Opcodes.nop,
            .info = decode.OPCODE_TABLE[op],
        };
    }

    // Unofficial 3-byte absolute NOPs (4 cycles) - TOP
    const abs_nops = [_]u8{0x0C};
    for (abs_nops) |op| {
        table[op] = .{
            .addressing_steps = &addressing.absolute_steps,
            .execute_pure = Opcodes.nop,
            .info = decode.OPCODE_TABLE[op],
        };
    }

    // Unofficial absolute,X NOPs (4-5 cycles)
    const absx_nops = [_]u8{ 0x1C, 0x3C, 0x5C, 0x7C, 0xDC, 0xFC };
    for (absx_nops) |op| {
        table[op] = .{
            .addressing_steps = &addressing.absolute_x_read_steps,
            .execute_pure = Opcodes.nop,
            .info = decode.OPCODE_TABLE[op],
        };
    }
}

/// Load and Store Instructions
fn buildLoadStoreOpcodes(table: *[256]DispatchEntry) void {
    // ===== LDA - Load Accumulator =====
    table[0xA9] = .{ .addressing_steps = &addressing.immediate_steps, .execute_pure = Opcodes.lda, .info = decode.OPCODE_TABLE[0xA9] };
    table[0xA5] = .{ .addressing_steps = &addressing.zero_page_steps, .execute_pure = Opcodes.lda, .info = decode.OPCODE_TABLE[0xA5] };
    table[0xB5] = .{ .addressing_steps = &addressing.zero_page_x_steps, .execute_pure = Opcodes.lda, .info = decode.OPCODE_TABLE[0xB5] };
    table[0xAD] = .{ .addressing_steps = &addressing.absolute_steps, .execute_pure = Opcodes.lda, .info = decode.OPCODE_TABLE[0xAD] };
    table[0xBD] = .{ .addressing_steps = &addressing.absolute_x_read_steps, .execute_pure = Opcodes.lda, .info = decode.OPCODE_TABLE[0xBD] };
    table[0xB9] = .{ .addressing_steps = &addressing.absolute_y_read_steps, .execute_pure = Opcodes.lda, .info = decode.OPCODE_TABLE[0xB9] };
    table[0xA1] = .{ .addressing_steps = &addressing.indexed_indirect_steps, .execute_pure = Opcodes.lda, .info = decode.OPCODE_TABLE[0xA1] };
    table[0xB1] = .{ .addressing_steps = &addressing.indirect_indexed_read_steps, .execute_pure = Opcodes.lda, .info = decode.OPCODE_TABLE[0xB1] };

    // ===== LDX - Load X Register =====
    table[0xA2] = .{ .addressing_steps = &addressing.immediate_steps, .execute_pure = Opcodes.ldx, .info = decode.OPCODE_TABLE[0xA2] };
    table[0xA6] = .{ .addressing_steps = &addressing.zero_page_steps, .execute_pure = Opcodes.ldx, .info = decode.OPCODE_TABLE[0xA6] };
    table[0xB6] = .{ .addressing_steps = &addressing.zero_page_y_steps, .execute_pure = Opcodes.ldx, .info = decode.OPCODE_TABLE[0xB6] };
    table[0xAE] = .{ .addressing_steps = &addressing.absolute_steps, .execute_pure = Opcodes.ldx, .info = decode.OPCODE_TABLE[0xAE] };
    table[0xBE] = .{ .addressing_steps = &addressing.absolute_y_read_steps, .execute_pure = Opcodes.ldx, .info = decode.OPCODE_TABLE[0xBE] };

    // ===== LDY - Load Y Register =====
    table[0xA0] = .{ .addressing_steps = &addressing.immediate_steps, .execute_pure = Opcodes.ldy, .info = decode.OPCODE_TABLE[0xA0] };
    table[0xA4] = .{ .addressing_steps = &addressing.zero_page_steps, .execute_pure = Opcodes.ldy, .info = decode.OPCODE_TABLE[0xA4] };
    table[0xB4] = .{ .addressing_steps = &addressing.zero_page_x_steps, .execute_pure = Opcodes.ldy, .info = decode.OPCODE_TABLE[0xB4] };
    table[0xAC] = .{ .addressing_steps = &addressing.absolute_steps, .execute_pure = Opcodes.ldy, .info = decode.OPCODE_TABLE[0xAC] };
    table[0xBC] = .{ .addressing_steps = &addressing.absolute_x_read_steps, .execute_pure = Opcodes.ldy, .info = decode.OPCODE_TABLE[0xBC] };

    // ===== STA - Store Accumulator =====
    table[0x85] = .{ .addressing_steps = &addressing.zero_page_steps, .execute_pure = Opcodes.sta, .info = decode.OPCODE_TABLE[0x85] };
    table[0x95] = .{ .addressing_steps = &addressing.zero_page_x_steps, .execute_pure = Opcodes.sta, .info = decode.OPCODE_TABLE[0x95] };
    table[0x8D] = .{ .addressing_steps = &addressing.absolute_steps, .execute_pure = Opcodes.sta, .info = decode.OPCODE_TABLE[0x8D] };
    table[0x9D] = .{ .addressing_steps = &addressing.absolute_x_write_steps, .execute_pure = Opcodes.sta, .info = decode.OPCODE_TABLE[0x9D] };
    table[0x99] = .{ .addressing_steps = &addressing.absolute_y_write_steps, .execute_pure = Opcodes.sta, .info = decode.OPCODE_TABLE[0x99] };
    table[0x81] = .{ .addressing_steps = &addressing.indexed_indirect_steps, .execute_pure = Opcodes.sta, .info = decode.OPCODE_TABLE[0x81] };
    table[0x91] = .{ .addressing_steps = &addressing.indirect_indexed_write_steps, .execute_pure = Opcodes.sta, .info = decode.OPCODE_TABLE[0x91] };

    // ===== STX - Store X Register =====
    table[0x86] = .{ .addressing_steps = &addressing.zero_page_steps, .execute_pure = Opcodes.stx, .info = decode.OPCODE_TABLE[0x86] };
    table[0x96] = .{ .addressing_steps = &addressing.zero_page_y_steps, .execute_pure = Opcodes.stx, .info = decode.OPCODE_TABLE[0x96] };
    table[0x8E] = .{ .addressing_steps = &addressing.absolute_steps, .execute_pure = Opcodes.stx, .info = decode.OPCODE_TABLE[0x8E] };

    // ===== STY - Store Y Register =====
    table[0x84] = .{ .addressing_steps = &addressing.zero_page_steps, .execute_pure = Opcodes.sty, .info = decode.OPCODE_TABLE[0x84] };
    table[0x94] = .{ .addressing_steps = &addressing.zero_page_x_steps, .execute_pure = Opcodes.sty, .info = decode.OPCODE_TABLE[0x94] };
    table[0x8C] = .{ .addressing_steps = &addressing.absolute_steps, .execute_pure = Opcodes.sty, .info = decode.OPCODE_TABLE[0x8C] };
}

/// Arithmetic Instructions (ADC, SBC)
fn buildArithmeticOpcodes(table: *[256]DispatchEntry) void {
    // ===== ADC - Add with Carry =====
    table[0x69] = .{ .addressing_steps = &addressing.immediate_steps, .execute_pure = Opcodes.adc, .info = decode.OPCODE_TABLE[0x69] };
    table[0x65] = .{ .addressing_steps = &addressing.zero_page_steps, .execute_pure = Opcodes.adc, .info = decode.OPCODE_TABLE[0x65] };
    table[0x75] = .{ .addressing_steps = &addressing.zero_page_x_steps, .execute_pure = Opcodes.adc, .info = decode.OPCODE_TABLE[0x75] };
    table[0x6D] = .{ .addressing_steps = &addressing.absolute_steps, .execute_pure = Opcodes.adc, .info = decode.OPCODE_TABLE[0x6D] };
    table[0x7D] = .{ .addressing_steps = &addressing.absolute_x_read_steps, .execute_pure = Opcodes.adc, .info = decode.OPCODE_TABLE[0x7D] };
    table[0x79] = .{ .addressing_steps = &addressing.absolute_y_read_steps, .execute_pure = Opcodes.adc, .info = decode.OPCODE_TABLE[0x79] };
    table[0x61] = .{ .addressing_steps = &addressing.indexed_indirect_steps, .execute_pure = Opcodes.adc, .info = decode.OPCODE_TABLE[0x61] };
    table[0x71] = .{ .addressing_steps = &addressing.indirect_indexed_read_steps, .execute_pure = Opcodes.adc, .info = decode.OPCODE_TABLE[0x71] };

    // ===== SBC - Subtract with Carry =====
    table[0xE9] = .{ .addressing_steps = &addressing.immediate_steps, .execute_pure = Opcodes.sbc, .info = decode.OPCODE_TABLE[0xE9] };
    table[0xE5] = .{ .addressing_steps = &addressing.zero_page_steps, .execute_pure = Opcodes.sbc, .info = decode.OPCODE_TABLE[0xE5] };
    table[0xF5] = .{ .addressing_steps = &addressing.zero_page_x_steps, .execute_pure = Opcodes.sbc, .info = decode.OPCODE_TABLE[0xF5] };
    table[0xED] = .{ .addressing_steps = &addressing.absolute_steps, .execute_pure = Opcodes.sbc, .info = decode.OPCODE_TABLE[0xED] };
    table[0xFD] = .{ .addressing_steps = &addressing.absolute_x_read_steps, .execute_pure = Opcodes.sbc, .info = decode.OPCODE_TABLE[0xFD] };
    table[0xF9] = .{ .addressing_steps = &addressing.absolute_y_read_steps, .execute_pure = Opcodes.sbc, .info = decode.OPCODE_TABLE[0xF9] };
    table[0xE1] = .{ .addressing_steps = &addressing.indexed_indirect_steps, .execute_pure = Opcodes.sbc, .info = decode.OPCODE_TABLE[0xE1] };
    table[0xF1] = .{ .addressing_steps = &addressing.indirect_indexed_read_steps, .execute_pure = Opcodes.sbc, .info = decode.OPCODE_TABLE[0xF1] };

    // ===== SBC Unofficial Duplicate (0xEB) =====
    table[0xEB] = .{ .addressing_steps = &addressing.immediate_steps, .execute_pure = Opcodes.sbc, .info = decode.OPCODE_TABLE[0xEB] };
}

/// Logical Instructions (AND, ORA, EOR)
fn buildLogicalOpcodes(table: *[256]DispatchEntry) void {
    // ===== AND - Logical AND =====
    table[0x29] = .{ .addressing_steps = &addressing.immediate_steps, .execute_pure = Opcodes.logicalAnd, .info = decode.OPCODE_TABLE[0x29] };
    table[0x25] = .{ .addressing_steps = &addressing.zero_page_steps, .execute_pure = Opcodes.logicalAnd, .info = decode.OPCODE_TABLE[0x25] };
    table[0x35] = .{ .addressing_steps = &addressing.zero_page_x_steps, .execute_pure = Opcodes.logicalAnd, .info = decode.OPCODE_TABLE[0x35] };
    table[0x2D] = .{ .addressing_steps = &addressing.absolute_steps, .execute_pure = Opcodes.logicalAnd, .info = decode.OPCODE_TABLE[0x2D] };
    table[0x3D] = .{ .addressing_steps = &addressing.absolute_x_read_steps, .execute_pure = Opcodes.logicalAnd, .info = decode.OPCODE_TABLE[0x3D] };
    table[0x39] = .{ .addressing_steps = &addressing.absolute_y_read_steps, .execute_pure = Opcodes.logicalAnd, .info = decode.OPCODE_TABLE[0x39] };
    table[0x21] = .{ .addressing_steps = &addressing.indexed_indirect_steps, .execute_pure = Opcodes.logicalAnd, .info = decode.OPCODE_TABLE[0x21] };
    table[0x31] = .{ .addressing_steps = &addressing.indirect_indexed_read_steps, .execute_pure = Opcodes.logicalAnd, .info = decode.OPCODE_TABLE[0x31] };

    // ===== ORA - Logical OR =====
    table[0x09] = .{ .addressing_steps = &addressing.immediate_steps, .execute_pure = Opcodes.logicalOr, .info = decode.OPCODE_TABLE[0x09] };
    table[0x05] = .{ .addressing_steps = &addressing.zero_page_steps, .execute_pure = Opcodes.logicalOr, .info = decode.OPCODE_TABLE[0x05] };
    table[0x15] = .{ .addressing_steps = &addressing.zero_page_x_steps, .execute_pure = Opcodes.logicalOr, .info = decode.OPCODE_TABLE[0x15] };
    table[0x0D] = .{ .addressing_steps = &addressing.absolute_steps, .execute_pure = Opcodes.logicalOr, .info = decode.OPCODE_TABLE[0x0D] };
    table[0x1D] = .{ .addressing_steps = &addressing.absolute_x_read_steps, .execute_pure = Opcodes.logicalOr, .info = decode.OPCODE_TABLE[0x1D] };
    table[0x19] = .{ .addressing_steps = &addressing.absolute_y_read_steps, .execute_pure = Opcodes.logicalOr, .info = decode.OPCODE_TABLE[0x19] };
    table[0x01] = .{ .addressing_steps = &addressing.indexed_indirect_steps, .execute_pure = Opcodes.logicalOr, .info = decode.OPCODE_TABLE[0x01] };
    table[0x11] = .{ .addressing_steps = &addressing.indirect_indexed_read_steps, .execute_pure = Opcodes.logicalOr, .info = decode.OPCODE_TABLE[0x11] };

    // ===== EOR - Logical XOR =====
    table[0x49] = .{ .addressing_steps = &addressing.immediate_steps, .execute_pure = Opcodes.logicalXor, .info = decode.OPCODE_TABLE[0x49] };
    table[0x45] = .{ .addressing_steps = &addressing.zero_page_steps, .execute_pure = Opcodes.logicalXor, .info = decode.OPCODE_TABLE[0x45] };
    table[0x55] = .{ .addressing_steps = &addressing.zero_page_x_steps, .execute_pure = Opcodes.logicalXor, .info = decode.OPCODE_TABLE[0x55] };
    table[0x4D] = .{ .addressing_steps = &addressing.absolute_steps, .execute_pure = Opcodes.logicalXor, .info = decode.OPCODE_TABLE[0x4D] };
    table[0x5D] = .{ .addressing_steps = &addressing.absolute_x_read_steps, .execute_pure = Opcodes.logicalXor, .info = decode.OPCODE_TABLE[0x5D] };
    table[0x59] = .{ .addressing_steps = &addressing.absolute_y_read_steps, .execute_pure = Opcodes.logicalXor, .info = decode.OPCODE_TABLE[0x59] };
    table[0x41] = .{ .addressing_steps = &addressing.indexed_indirect_steps, .execute_pure = Opcodes.logicalXor, .info = decode.OPCODE_TABLE[0x41] };
    table[0x51] = .{ .addressing_steps = &addressing.indirect_indexed_read_steps, .execute_pure = Opcodes.logicalXor, .info = decode.OPCODE_TABLE[0x51] };
}

/// Compare Instructions (CMP, CPX, CPY, BIT)
fn buildCompareOpcodes(table: *[256]DispatchEntry) void {
    // ===== CMP - Compare Accumulator =====
    table[0xC9] = .{ .addressing_steps = &addressing.immediate_steps, .execute_pure = Opcodes.cmp, .info = decode.OPCODE_TABLE[0xC9] };
    table[0xC5] = .{ .addressing_steps = &addressing.zero_page_steps, .execute_pure = Opcodes.cmp, .info = decode.OPCODE_TABLE[0xC5] };
    table[0xD5] = .{ .addressing_steps = &addressing.zero_page_x_steps, .execute_pure = Opcodes.cmp, .info = decode.OPCODE_TABLE[0xD5] };
    table[0xCD] = .{ .addressing_steps = &addressing.absolute_steps, .execute_pure = Opcodes.cmp, .info = decode.OPCODE_TABLE[0xCD] };
    table[0xDD] = .{ .addressing_steps = &addressing.absolute_x_read_steps, .execute_pure = Opcodes.cmp, .info = decode.OPCODE_TABLE[0xDD] };
    table[0xD9] = .{ .addressing_steps = &addressing.absolute_y_read_steps, .execute_pure = Opcodes.cmp, .info = decode.OPCODE_TABLE[0xD9] };
    table[0xC1] = .{ .addressing_steps = &addressing.indexed_indirect_steps, .execute_pure = Opcodes.cmp, .info = decode.OPCODE_TABLE[0xC1] };
    table[0xD1] = .{ .addressing_steps = &addressing.indirect_indexed_read_steps, .execute_pure = Opcodes.cmp, .info = decode.OPCODE_TABLE[0xD1] };

    // ===== CPX - Compare X Register =====
    table[0xE0] = .{ .addressing_steps = &addressing.immediate_steps, .execute_pure = Opcodes.cpx, .info = decode.OPCODE_TABLE[0xE0] };
    table[0xE4] = .{ .addressing_steps = &addressing.zero_page_steps, .execute_pure = Opcodes.cpx, .info = decode.OPCODE_TABLE[0xE4] };
    table[0xEC] = .{ .addressing_steps = &addressing.absolute_steps, .execute_pure = Opcodes.cpx, .info = decode.OPCODE_TABLE[0xEC] };

    // ===== CPY - Compare Y Register =====
    table[0xC0] = .{ .addressing_steps = &addressing.immediate_steps, .execute_pure = Opcodes.cpy, .info = decode.OPCODE_TABLE[0xC0] };
    table[0xC4] = .{ .addressing_steps = &addressing.zero_page_steps, .execute_pure = Opcodes.cpy, .info = decode.OPCODE_TABLE[0xC4] };
    table[0xCC] = .{ .addressing_steps = &addressing.absolute_steps, .execute_pure = Opcodes.cpy, .info = decode.OPCODE_TABLE[0xCC] };

    // ===== BIT - Test Bits =====
    table[0x24] = .{ .addressing_steps = &addressing.zero_page_steps, .execute_pure = Opcodes.bit, .info = decode.OPCODE_TABLE[0x24] };
    table[0x2C] = .{ .addressing_steps = &addressing.absolute_steps, .execute_pure = Opcodes.bit, .info = decode.OPCODE_TABLE[0x2C] };
}

/// Shift/Rotate Instructions (ASL, LSR, ROL, ROR)
fn buildShiftRotateOpcodes(table: *[256]DispatchEntry) void {
    // ===== ASL - Arithmetic Shift Left =====
    table[0x0A] = .{ .addressing_steps = &[_]MicrostepFn{}, .execute_pure = Opcodes.aslAcc, .info = decode.OPCODE_TABLE[0x0A] }; // Accumulator
    table[0x06] = .{ .addressing_steps = &addressing.zero_page_rmw_steps, .execute_pure = Opcodes.aslMem, .info = decode.OPCODE_TABLE[0x06], .is_rmw = true };
    table[0x16] = .{ .addressing_steps = &addressing.zero_page_x_rmw_steps, .execute_pure = Opcodes.aslMem, .info = decode.OPCODE_TABLE[0x16], .is_rmw = true };
    table[0x0E] = .{ .addressing_steps = &addressing.absolute_rmw_steps, .execute_pure = Opcodes.aslMem, .info = decode.OPCODE_TABLE[0x0E], .is_rmw = true };
    table[0x1E] = .{ .addressing_steps = &addressing.absolute_x_rmw_steps, .execute_pure = Opcodes.aslMem, .info = decode.OPCODE_TABLE[0x1E], .is_rmw = true };

    // ===== LSR - Logical Shift Right =====
    table[0x4A] = .{ .addressing_steps = &[_]MicrostepFn{}, .execute_pure = Opcodes.lsrAcc, .info = decode.OPCODE_TABLE[0x4A] }; // Accumulator
    table[0x46] = .{ .addressing_steps = &addressing.zero_page_rmw_steps, .execute_pure = Opcodes.lsrMem, .info = decode.OPCODE_TABLE[0x46], .is_rmw = true };
    table[0x56] = .{ .addressing_steps = &addressing.zero_page_x_rmw_steps, .execute_pure = Opcodes.lsrMem, .info = decode.OPCODE_TABLE[0x56], .is_rmw = true };
    table[0x4E] = .{ .addressing_steps = &addressing.absolute_rmw_steps, .execute_pure = Opcodes.lsrMem, .info = decode.OPCODE_TABLE[0x4E], .is_rmw = true };
    table[0x5E] = .{ .addressing_steps = &addressing.absolute_x_rmw_steps, .execute_pure = Opcodes.lsrMem, .info = decode.OPCODE_TABLE[0x5E], .is_rmw = true };

    // ===== ROL - Rotate Left =====
    table[0x2A] = .{ .addressing_steps = &[_]MicrostepFn{}, .execute_pure = Opcodes.rolAcc, .info = decode.OPCODE_TABLE[0x2A] }; // Accumulator
    table[0x26] = .{ .addressing_steps = &addressing.zero_page_rmw_steps, .execute_pure = Opcodes.rolMem, .info = decode.OPCODE_TABLE[0x26], .is_rmw = true };
    table[0x36] = .{ .addressing_steps = &addressing.zero_page_x_rmw_steps, .execute_pure = Opcodes.rolMem, .info = decode.OPCODE_TABLE[0x36], .is_rmw = true };
    table[0x2E] = .{ .addressing_steps = &addressing.absolute_rmw_steps, .execute_pure = Opcodes.rolMem, .info = decode.OPCODE_TABLE[0x2E], .is_rmw = true };
    table[0x3E] = .{ .addressing_steps = &addressing.absolute_x_rmw_steps, .execute_pure = Opcodes.rolMem, .info = decode.OPCODE_TABLE[0x3E], .is_rmw = true };

    // ===== ROR - Rotate Right =====
    table[0x6A] = .{ .addressing_steps = &[_]MicrostepFn{}, .execute_pure = Opcodes.rorAcc, .info = decode.OPCODE_TABLE[0x6A] }; // Accumulator
    table[0x66] = .{ .addressing_steps = &addressing.zero_page_rmw_steps, .execute_pure = Opcodes.rorMem, .info = decode.OPCODE_TABLE[0x66], .is_rmw = true };
    table[0x76] = .{ .addressing_steps = &addressing.zero_page_x_rmw_steps, .execute_pure = Opcodes.rorMem, .info = decode.OPCODE_TABLE[0x76], .is_rmw = true };
    table[0x6E] = .{ .addressing_steps = &addressing.absolute_rmw_steps, .execute_pure = Opcodes.rorMem, .info = decode.OPCODE_TABLE[0x6E], .is_rmw = true };
    table[0x7E] = .{ .addressing_steps = &addressing.absolute_x_rmw_steps, .execute_pure = Opcodes.rorMem, .info = decode.OPCODE_TABLE[0x7E], .is_rmw = true };
}

/// Increment/Decrement Instructions
fn buildIncDecOpcodes(table: *[256]DispatchEntry) void {
    // ===== INC - Increment Memory =====
    table[0xE6] = .{ .addressing_steps = &addressing.zero_page_rmw_steps, .execute_pure = Opcodes.inc, .info = decode.OPCODE_TABLE[0xE6], .is_rmw = true };
    table[0xF6] = .{ .addressing_steps = &addressing.zero_page_x_rmw_steps, .execute_pure = Opcodes.inc, .info = decode.OPCODE_TABLE[0xF6], .is_rmw = true };
    table[0xEE] = .{ .addressing_steps = &addressing.absolute_rmw_steps, .execute_pure = Opcodes.inc, .info = decode.OPCODE_TABLE[0xEE], .is_rmw = true };
    table[0xFE] = .{ .addressing_steps = &addressing.absolute_x_rmw_steps, .execute_pure = Opcodes.inc, .info = decode.OPCODE_TABLE[0xFE], .is_rmw = true };

    // ===== DEC - Decrement Memory =====
    table[0xC6] = .{ .addressing_steps = &addressing.zero_page_rmw_steps, .execute_pure = Opcodes.dec, .info = decode.OPCODE_TABLE[0xC6], .is_rmw = true };
    table[0xD6] = .{ .addressing_steps = &addressing.zero_page_x_rmw_steps, .execute_pure = Opcodes.dec, .info = decode.OPCODE_TABLE[0xD6], .is_rmw = true };
    table[0xCE] = .{ .addressing_steps = &addressing.absolute_rmw_steps, .execute_pure = Opcodes.dec, .info = decode.OPCODE_TABLE[0xCE], .is_rmw = true };
    table[0xDE] = .{ .addressing_steps = &addressing.absolute_x_rmw_steps, .execute_pure = Opcodes.dec, .info = decode.OPCODE_TABLE[0xDE], .is_rmw = true };

    // ===== Register Inc/Dec Instructions =====
    table[0xE8] = .{ .addressing_steps = &[_]MicrostepFn{}, .execute_pure = Opcodes.inx, .info = decode.OPCODE_TABLE[0xE8] }; // INX
    table[0xC8] = .{ .addressing_steps = &[_]MicrostepFn{}, .execute_pure = Opcodes.iny, .info = decode.OPCODE_TABLE[0xC8] }; // INY
    table[0xCA] = .{ .addressing_steps = &[_]MicrostepFn{}, .execute_pure = Opcodes.dex, .info = decode.OPCODE_TABLE[0xCA] }; // DEX
    table[0x88] = .{ .addressing_steps = &[_]MicrostepFn{}, .execute_pure = Opcodes.dey, .info = decode.OPCODE_TABLE[0x88] }; // DEY
}

/// Transfer Instructions (TAX, TAY, TXA, TYA, TSX, TXS)
fn buildTransferOpcodes(table: *[256]DispatchEntry) void {
    table[0xAA] = .{ .addressing_steps = &[_]MicrostepFn{}, .execute_pure = Opcodes.tax, .info = decode.OPCODE_TABLE[0xAA] }; // TAX
    table[0xA8] = .{ .addressing_steps = &[_]MicrostepFn{}, .execute_pure = Opcodes.tay, .info = decode.OPCODE_TABLE[0xA8] }; // TAY
    table[0x8A] = .{ .addressing_steps = &[_]MicrostepFn{}, .execute_pure = Opcodes.txa, .info = decode.OPCODE_TABLE[0x8A] }; // TXA
    table[0x98] = .{ .addressing_steps = &[_]MicrostepFn{}, .execute_pure = Opcodes.tya, .info = decode.OPCODE_TABLE[0x98] }; // TYA
    table[0xBA] = .{ .addressing_steps = &[_]MicrostepFn{}, .execute_pure = Opcodes.tsx, .info = decode.OPCODE_TABLE[0xBA] }; // TSX
    table[0x9A] = .{ .addressing_steps = &[_]MicrostepFn{}, .execute_pure = Opcodes.txs, .info = decode.OPCODE_TABLE[0x9A] }; // TXS
}

/// Flag Instructions (CLC, CLD, CLI, CLV, SEC, SED, SEI)
fn buildFlagOpcodes(table: *[256]DispatchEntry) void {
    table[0x18] = .{ .addressing_steps = &[_]MicrostepFn{}, .execute_pure = Opcodes.clc, .info = decode.OPCODE_TABLE[0x18] }; // CLC
    table[0xD8] = .{ .addressing_steps = &[_]MicrostepFn{}, .execute_pure = Opcodes.cld, .info = decode.OPCODE_TABLE[0xD8] }; // CLD
    table[0x58] = .{ .addressing_steps = &[_]MicrostepFn{}, .execute_pure = Opcodes.cli, .info = decode.OPCODE_TABLE[0x58] }; // CLI
    table[0xB8] = .{ .addressing_steps = &[_]MicrostepFn{}, .execute_pure = Opcodes.clv, .info = decode.OPCODE_TABLE[0xB8] }; // CLV
    table[0x38] = .{ .addressing_steps = &[_]MicrostepFn{}, .execute_pure = Opcodes.sec, .info = decode.OPCODE_TABLE[0x38] }; // SEC
    table[0xF8] = .{ .addressing_steps = &[_]MicrostepFn{}, .execute_pure = Opcodes.sed, .info = decode.OPCODE_TABLE[0xF8] }; // SED
    table[0x78] = .{ .addressing_steps = &[_]MicrostepFn{}, .execute_pure = Opcodes.sei, .info = decode.OPCODE_TABLE[0x78] }; // SEI
}

/// Stack Instructions (PHA, PHP, PLA, PLP)
fn buildStackOpcodes(table: *[256]DispatchEntry) void {
    // Push operations (3 cycles: fetch + dummy read + push)
    table[0x48] = .{ .addressing_steps = &addressing.stack_push_steps, .execute_pure = Opcodes.pha, .info = decode.OPCODE_TABLE[0x48] }; // PHA
    table[0x08] = .{ .addressing_steps = &addressing.stack_push_steps, .execute_pure = Opcodes.php, .info = decode.OPCODE_TABLE[0x08] }; // PHP

    // Pull operations (4 cycles: fetch + dummy read + pull + execute)
    table[0x68] = .{ .addressing_steps = &addressing.stack_pull_steps, .execute_pure = Opcodes.pla, .info = decode.OPCODE_TABLE[0x68], .is_pull = true }; // PLA
    table[0x28] = .{ .addressing_steps = &addressing.stack_pull_steps, .execute_pure = Opcodes.plp, .info = decode.OPCODE_TABLE[0x28], .is_pull = true }; // PLP
}

/// Branch Instructions (BCC, BCS, BEQ, BNE, BMI, BPL, BVC, BVS)
fn buildBranchOpcodes(table: *[256]DispatchEntry) void {
    table[0x90] = .{ .addressing_steps = &addressing.relative_steps, .execute_pure = Opcodes.bcc, .info = decode.OPCODE_TABLE[0x90] }; // BCC
    table[0xB0] = .{ .addressing_steps = &addressing.relative_steps, .execute_pure = Opcodes.bcs, .info = decode.OPCODE_TABLE[0xB0] }; // BCS
    table[0xF0] = .{ .addressing_steps = &addressing.relative_steps, .execute_pure = Opcodes.beq, .info = decode.OPCODE_TABLE[0xF0] }; // BEQ
    table[0xD0] = .{ .addressing_steps = &addressing.relative_steps, .execute_pure = Opcodes.bne, .info = decode.OPCODE_TABLE[0xD0] }; // BNE
    table[0x30] = .{ .addressing_steps = &addressing.relative_steps, .execute_pure = Opcodes.bmi, .info = decode.OPCODE_TABLE[0x30] }; // BMI
    table[0x10] = .{ .addressing_steps = &addressing.relative_steps, .execute_pure = Opcodes.bpl, .info = decode.OPCODE_TABLE[0x10] }; // BPL
    table[0x50] = .{ .addressing_steps = &addressing.relative_steps, .execute_pure = Opcodes.bvc, .info = decode.OPCODE_TABLE[0x50] }; // BVC
    table[0x70] = .{ .addressing_steps = &addressing.relative_steps, .execute_pure = Opcodes.bvs, .info = decode.OPCODE_TABLE[0x70] }; // BVS
}

/// Jump/Control Flow Instructions (JMP, JSR, RTS, RTI, BRK)
fn buildJumpOpcodes(table: *[256]DispatchEntry) void {
    // JMP opcodes (pure - just set PC to effective_address)
    table[0x4C] = .{ .addressing_steps = &addressing.absolute_steps, .execute_pure = Opcodes.jmp, .info = decode.OPCODE_TABLE[0x4C] }; // JMP absolute
    table[0x6C] = .{ .addressing_steps = &addressing.indirect_jmp_steps, .execute_pure = Opcodes.jmp, .info = decode.OPCODE_TABLE[0x6C] }; // JMP indirect

    // Control flow opcodes (microstep-based, no pure execution)
    // All logic is handled in microstep sequences - execute_pure is nop
    table[0x20] = .{ .addressing_steps = &addressing.jsr_steps, .execute_pure = Opcodes.nop, .info = decode.OPCODE_TABLE[0x20] }; // JSR (6 cycles)
    table[0x60] = .{ .addressing_steps = &addressing.rts_steps, .execute_pure = Opcodes.nop, .info = decode.OPCODE_TABLE[0x60] }; // RTS (6 cycles)
    table[0x40] = .{ .addressing_steps = &addressing.rti_steps, .execute_pure = Opcodes.nop, .info = decode.OPCODE_TABLE[0x40] }; // RTI (6 cycles)
    table[0x00] = .{ .addressing_steps = &addressing.brk_steps, .execute_pure = Opcodes.nop, .info = decode.OPCODE_TABLE[0x00] }; // BRK (7 cycles)
}

/// Unofficial/Undocumented Opcodes
fn buildUnofficialOpcodes(table: *[256]DispatchEntry) void {
    // ===== LAX - Load A and X =====
    table[0xA7] = .{ .addressing_steps = &addressing.zero_page_steps, .execute_pure = Opcodes.lax, .info = decode.OPCODE_TABLE[0xA7] };
    table[0xB7] = .{ .addressing_steps = &addressing.zero_page_y_steps, .execute_pure = Opcodes.lax, .info = decode.OPCODE_TABLE[0xB7] };
    table[0xAF] = .{ .addressing_steps = &addressing.absolute_steps, .execute_pure = Opcodes.lax, .info = decode.OPCODE_TABLE[0xAF] };
    table[0xBF] = .{ .addressing_steps = &addressing.absolute_y_read_steps, .execute_pure = Opcodes.lax, .info = decode.OPCODE_TABLE[0xBF] };
    table[0xA3] = .{ .addressing_steps = &addressing.indexed_indirect_steps, .execute_pure = Opcodes.lax, .info = decode.OPCODE_TABLE[0xA3] };
    table[0xB3] = .{ .addressing_steps = &addressing.indirect_indexed_read_steps, .execute_pure = Opcodes.lax, .info = decode.OPCODE_TABLE[0xB3] };

    // ===== SAX - Store A AND X =====
    table[0x87] = .{ .addressing_steps = &addressing.zero_page_steps, .execute_pure = Opcodes.sax, .info = decode.OPCODE_TABLE[0x87] };
    table[0x97] = .{ .addressing_steps = &addressing.zero_page_y_steps, .execute_pure = Opcodes.sax, .info = decode.OPCODE_TABLE[0x97] };
    table[0x8F] = .{ .addressing_steps = &addressing.absolute_steps, .execute_pure = Opcodes.sax, .info = decode.OPCODE_TABLE[0x8F] };
    table[0x83] = .{ .addressing_steps = &addressing.indexed_indirect_steps, .execute_pure = Opcodes.sax, .info = decode.OPCODE_TABLE[0x83] };

    // ===== SLO - ASL + ORA (RMW) =====
    table[0x07] = .{ .addressing_steps = &addressing.zero_page_rmw_steps, .execute_pure = Opcodes.slo, .info = decode.OPCODE_TABLE[0x07], .is_rmw = true };
    table[0x17] = .{ .addressing_steps = &addressing.zero_page_x_rmw_steps, .execute_pure = Opcodes.slo, .info = decode.OPCODE_TABLE[0x17], .is_rmw = true };
    table[0x0F] = .{ .addressing_steps = &addressing.absolute_rmw_steps, .execute_pure = Opcodes.slo, .info = decode.OPCODE_TABLE[0x0F], .is_rmw = true };
    table[0x1F] = .{ .addressing_steps = &addressing.absolute_x_rmw_steps, .execute_pure = Opcodes.slo, .info = decode.OPCODE_TABLE[0x1F], .is_rmw = true };
    table[0x1B] = .{ .addressing_steps = &addressing.absolute_x_rmw_steps, .execute_pure = Opcodes.slo, .info = decode.OPCODE_TABLE[0x1B], .is_rmw = true }; // abs,Y uses X rmw steps
    table[0x03] = .{ .addressing_steps = &addressing.indexed_indirect_rmw_steps, .execute_pure = Opcodes.slo, .info = decode.OPCODE_TABLE[0x03], .is_rmw = true };
    table[0x13] = .{ .addressing_steps = &addressing.indirect_indexed_rmw_steps, .execute_pure = Opcodes.slo, .info = decode.OPCODE_TABLE[0x13], .is_rmw = true };

    // ===== RLA - ROL + AND (RMW) =====
    table[0x27] = .{ .addressing_steps = &addressing.zero_page_rmw_steps, .execute_pure = Opcodes.rla, .info = decode.OPCODE_TABLE[0x27], .is_rmw = true };
    table[0x37] = .{ .addressing_steps = &addressing.zero_page_x_rmw_steps, .execute_pure = Opcodes.rla, .info = decode.OPCODE_TABLE[0x37], .is_rmw = true };
    table[0x2F] = .{ .addressing_steps = &addressing.absolute_rmw_steps, .execute_pure = Opcodes.rla, .info = decode.OPCODE_TABLE[0x2F], .is_rmw = true };
    table[0x3F] = .{ .addressing_steps = &addressing.absolute_x_rmw_steps, .execute_pure = Opcodes.rla, .info = decode.OPCODE_TABLE[0x3F], .is_rmw = true };
    table[0x3B] = .{ .addressing_steps = &addressing.absolute_x_rmw_steps, .execute_pure = Opcodes.rla, .info = decode.OPCODE_TABLE[0x3B], .is_rmw = true };
    table[0x23] = .{ .addressing_steps = &addressing.indexed_indirect_rmw_steps, .execute_pure = Opcodes.rla, .info = decode.OPCODE_TABLE[0x23], .is_rmw = true };
    table[0x33] = .{ .addressing_steps = &addressing.indirect_indexed_rmw_steps, .execute_pure = Opcodes.rla, .info = decode.OPCODE_TABLE[0x33], .is_rmw = true };

    // ===== SRE - LSR + EOR (RMW) =====
    table[0x47] = .{ .addressing_steps = &addressing.zero_page_rmw_steps, .execute_pure = Opcodes.sre, .info = decode.OPCODE_TABLE[0x47], .is_rmw = true };
    table[0x57] = .{ .addressing_steps = &addressing.zero_page_x_rmw_steps, .execute_pure = Opcodes.sre, .info = decode.OPCODE_TABLE[0x57], .is_rmw = true };
    table[0x4F] = .{ .addressing_steps = &addressing.absolute_rmw_steps, .execute_pure = Opcodes.sre, .info = decode.OPCODE_TABLE[0x4F], .is_rmw = true };
    table[0x5F] = .{ .addressing_steps = &addressing.absolute_x_rmw_steps, .execute_pure = Opcodes.sre, .info = decode.OPCODE_TABLE[0x5F], .is_rmw = true };
    table[0x5B] = .{ .addressing_steps = &addressing.absolute_x_rmw_steps, .execute_pure = Opcodes.sre, .info = decode.OPCODE_TABLE[0x5B], .is_rmw = true };
    table[0x43] = .{ .addressing_steps = &addressing.indexed_indirect_rmw_steps, .execute_pure = Opcodes.sre, .info = decode.OPCODE_TABLE[0x43], .is_rmw = true };
    table[0x53] = .{ .addressing_steps = &addressing.indirect_indexed_rmw_steps, .execute_pure = Opcodes.sre, .info = decode.OPCODE_TABLE[0x53], .is_rmw = true };

    // ===== RRA - ROR + ADC (RMW) =====
    table[0x67] = .{ .addressing_steps = &addressing.zero_page_rmw_steps, .execute_pure = Opcodes.rra, .info = decode.OPCODE_TABLE[0x67], .is_rmw = true };
    table[0x77] = .{ .addressing_steps = &addressing.zero_page_x_rmw_steps, .execute_pure = Opcodes.rra, .info = decode.OPCODE_TABLE[0x77], .is_rmw = true };
    table[0x6F] = .{ .addressing_steps = &addressing.absolute_rmw_steps, .execute_pure = Opcodes.rra, .info = decode.OPCODE_TABLE[0x6F], .is_rmw = true };
    table[0x7F] = .{ .addressing_steps = &addressing.absolute_x_rmw_steps, .execute_pure = Opcodes.rra, .info = decode.OPCODE_TABLE[0x7F], .is_rmw = true };
    table[0x7B] = .{ .addressing_steps = &addressing.absolute_x_rmw_steps, .execute_pure = Opcodes.rra, .info = decode.OPCODE_TABLE[0x7B], .is_rmw = true };
    table[0x63] = .{ .addressing_steps = &addressing.indexed_indirect_rmw_steps, .execute_pure = Opcodes.rra, .info = decode.OPCODE_TABLE[0x63], .is_rmw = true };
    table[0x73] = .{ .addressing_steps = &addressing.indirect_indexed_rmw_steps, .execute_pure = Opcodes.rra, .info = decode.OPCODE_TABLE[0x73], .is_rmw = true };

    // ===== DCP - DEC + CMP (RMW) =====
    table[0xC7] = .{ .addressing_steps = &addressing.zero_page_rmw_steps, .execute_pure = Opcodes.dcp, .info = decode.OPCODE_TABLE[0xC7], .is_rmw = true };
    table[0xD7] = .{ .addressing_steps = &addressing.zero_page_x_rmw_steps, .execute_pure = Opcodes.dcp, .info = decode.OPCODE_TABLE[0xD7], .is_rmw = true };
    table[0xCF] = .{ .addressing_steps = &addressing.absolute_rmw_steps, .execute_pure = Opcodes.dcp, .info = decode.OPCODE_TABLE[0xCF], .is_rmw = true };
    table[0xDF] = .{ .addressing_steps = &addressing.absolute_x_rmw_steps, .execute_pure = Opcodes.dcp, .info = decode.OPCODE_TABLE[0xDF], .is_rmw = true };
    table[0xDB] = .{ .addressing_steps = &addressing.absolute_x_rmw_steps, .execute_pure = Opcodes.dcp, .info = decode.OPCODE_TABLE[0xDB], .is_rmw = true };
    table[0xC3] = .{ .addressing_steps = &addressing.indexed_indirect_rmw_steps, .execute_pure = Opcodes.dcp, .info = decode.OPCODE_TABLE[0xC3], .is_rmw = true };
    table[0xD3] = .{ .addressing_steps = &addressing.indirect_indexed_rmw_steps, .execute_pure = Opcodes.dcp, .info = decode.OPCODE_TABLE[0xD3], .is_rmw = true };

    // ===== ISC - INC + SBC (RMW) =====
    table[0xE7] = .{ .addressing_steps = &addressing.zero_page_rmw_steps, .execute_pure = Opcodes.isc, .info = decode.OPCODE_TABLE[0xE7], .is_rmw = true };
    table[0xF7] = .{ .addressing_steps = &addressing.zero_page_x_rmw_steps, .execute_pure = Opcodes.isc, .info = decode.OPCODE_TABLE[0xF7], .is_rmw = true };
    table[0xEF] = .{ .addressing_steps = &addressing.absolute_rmw_steps, .execute_pure = Opcodes.isc, .info = decode.OPCODE_TABLE[0xEF], .is_rmw = true };
    table[0xFF] = .{ .addressing_steps = &addressing.absolute_x_rmw_steps, .execute_pure = Opcodes.isc, .info = decode.OPCODE_TABLE[0xFF], .is_rmw = true };
    table[0xFB] = .{ .addressing_steps = &addressing.absolute_x_rmw_steps, .execute_pure = Opcodes.isc, .info = decode.OPCODE_TABLE[0xFB], .is_rmw = true };
    table[0xE3] = .{ .addressing_steps = &addressing.indexed_indirect_rmw_steps, .execute_pure = Opcodes.isc, .info = decode.OPCODE_TABLE[0xE3], .is_rmw = true };
    table[0xF3] = .{ .addressing_steps = &addressing.indirect_indexed_rmw_steps, .execute_pure = Opcodes.isc, .info = decode.OPCODE_TABLE[0xF3], .is_rmw = true };

    // ===== Immediate Logic/Math Instructions =====
    table[0x0B] = .{ .addressing_steps = &addressing.immediate_steps, .execute_pure = Opcodes.anc, .info = decode.OPCODE_TABLE[0x0B] }; // ANC
    table[0x2B] = .{ .addressing_steps = &addressing.immediate_steps, .execute_pure = Opcodes.anc, .info = decode.OPCODE_TABLE[0x2B] }; // ANC (duplicate)
    table[0x4B] = .{ .addressing_steps = &addressing.immediate_steps, .execute_pure = Opcodes.alr, .info = decode.OPCODE_TABLE[0x4B] }; // ALR
    table[0x6B] = .{ .addressing_steps = &addressing.immediate_steps, .execute_pure = Opcodes.arr, .info = decode.OPCODE_TABLE[0x6B] }; // ARR
    table[0x8B] = .{ .addressing_steps = &addressing.immediate_steps, .execute_pure = Opcodes.xaa, .info = decode.OPCODE_TABLE[0x8B] }; // XAA
    table[0xAB] = .{ .addressing_steps = &addressing.immediate_steps, .execute_pure = Opcodes.lxa, .info = decode.OPCODE_TABLE[0xAB] }; // LXA
    table[0xCB] = .{ .addressing_steps = &addressing.immediate_steps, .execute_pure = Opcodes.axs, .info = decode.OPCODE_TABLE[0xCB] }; // AXS

    // ===== Unstable Store Operations =====
    table[0x9F] = .{ .addressing_steps = &addressing.absolute_y_write_steps, .execute_pure = Opcodes.sha, .info = decode.OPCODE_TABLE[0x9F] }; // SHA abs,Y
    table[0x93] = .{ .addressing_steps = &addressing.indirect_indexed_write_steps, .execute_pure = Opcodes.sha, .info = decode.OPCODE_TABLE[0x93] }; // SHA (ind),Y
    table[0x9E] = .{ .addressing_steps = &addressing.absolute_y_write_steps, .execute_pure = Opcodes.shx, .info = decode.OPCODE_TABLE[0x9E] }; // SHX
    table[0x9C] = .{ .addressing_steps = &addressing.absolute_x_write_steps, .execute_pure = Opcodes.shy, .info = decode.OPCODE_TABLE[0x9C] }; // SHY
    table[0x9B] = .{ .addressing_steps = &addressing.absolute_y_write_steps, .execute_pure = Opcodes.tas, .info = decode.OPCODE_TABLE[0x9B] }; // TAS

    // ===== Other Unstable Load/Transfer =====
    table[0xBB] = .{ .addressing_steps = &addressing.absolute_y_read_steps, .execute_pure = Opcodes.lae, .info = decode.OPCODE_TABLE[0xBB] }; // LAE

    // ===== JAM/KIL - CPU Halt =====
    const jam_opcodes = [_]u8{ 0x02, 0x12, 0x22, 0x32, 0x42, 0x52, 0x62, 0x72, 0x92, 0xB2, 0xD2, 0xF2 };
    for (jam_opcodes) |op| {
        table[op] = .{
            .addressing_steps = &[_]MicrostepFn{},
            .execute_pure = Opcodes.jam,
            .info = decode.OPCODE_TABLE[op],
        };
    }
}
