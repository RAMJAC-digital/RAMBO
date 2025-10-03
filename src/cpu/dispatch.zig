const std = @import("std");
const CpuModule = @import("Cpu.zig");
const BusModule = @import("../bus/Bus.zig");
const opcodes = @import("opcodes.zig");
const execution = @import("execution.zig");

const Cpu = CpuModule.Cpu;
const Bus = BusModule.Bus;
const MicrostepFn = execution.MicrostepFn;
const InstructionExecutor = execution.InstructionExecutor;

/// Instruction implementation function signature
/// Takes CPU and Bus, executes the instruction logic, returns true when complete
pub const InstructionFn = *const fn (*Cpu, *Bus) bool;

/// Dispatch table entry combining addressing and execution
pub const DispatchEntry = struct {
    addressing_steps: []const MicrostepFn,
    execute: InstructionFn,
    info: opcodes.OpcodeInfo,
};

// Import instruction implementations
const loadstore = @import("instructions/loadstore.zig");
const shifts = @import("instructions/shifts.zig");
const incdec = @import("instructions/incdec.zig");
const arithmetic = @import("instructions/arithmetic.zig");
const logical = @import("instructions/logical.zig");
const compare = @import("instructions/compare.zig");
const transfer = @import("instructions/transfer.zig");
const branch = @import("instructions/branch.zig");
const jumps = @import("instructions/jumps.zig");
const stack = @import("instructions/stack.zig");
const unofficial = @import("instructions/unofficial.zig");

// ============================================================================
// NOP Instructions
// ============================================================================

fn nopImplied(cpu: *Cpu, bus: *Bus) bool {
    _ = cpu;
    _ = bus;
    return true; // Complete immediately
}

fn nopImmediate(cpu: *Cpu, bus: *Bus) bool {
    // Immediate mode: fetch and discard operand
    _ = bus.read(cpu.pc);
    cpu.pc +%= 1;
    return true;
}

fn nopRead(cpu: *Cpu, bus: *Bus) bool {
    // NOP with addressing: perform read but discard result
    // This is important for hardware accuracy - the read DOES occur
    const helpers = @import("helpers.zig");
    _ = helpers.readOperand(cpu, bus);
    return true;
}

// ============================================================================
// Dispatch Table Builder
// ============================================================================

const addressing = @import("addressing.zig");

/// Build the complete dispatch table for all 256 opcodes
pub fn buildDispatchTable() [256]DispatchEntry {
    @setEvalBranchQuota(100000);
    var table: [256]DispatchEntry = undefined;

    // Initialize all entries with illegal opcode handler
    for (&table, 0..) |*entry, i| {
        const info = opcodes.OPCODE_TABLE[i];
        entry.* = .{
            .addressing_steps = &[_]MicrostepFn{},
            .execute = nopImplied, // Default to NOP for illegal opcodes
            .info = info,
        };
    }

    // ===== NOP Instructions =====
    table[0xEA] = .{
        .addressing_steps = &[_]MicrostepFn{}, // Implied, no addressing
        .execute = nopImplied,
        .info = opcodes.OPCODE_TABLE[0xEA],
    };

    // Unofficial NOP variants (immediate mode)
    const nop_immediate_opcodes = [_]u8{ 0x80, 0x82, 0x89, 0xC2, 0xE2 };
    for (nop_immediate_opcodes) |opcode| {
        table[opcode] = .{
            .addressing_steps = &[_]MicrostepFn{},
            .execute = nopImmediate,
            .info = opcodes.OPCODE_TABLE[opcode],
        };
    }

    // 1-byte implied NOPs (2 cycles)
    const implied_nop_opcodes = [_]u8{ 0x1A, 0x3A, 0x5A, 0x7A, 0xDA, 0xFA };
    for (implied_nop_opcodes) |opcode| {
        table[opcode] = .{
            .addressing_steps = &[_]MicrostepFn{},
            .execute = nopImplied,
            .info = opcodes.OPCODE_TABLE[opcode],
        };
    }

    // 2-byte zero page NOPs (3 cycles)
    const zp_nop_opcodes = [_]u8{ 0x04, 0x44, 0x64 };
    for (zp_nop_opcodes) |opcode| {
        table[opcode] = .{
            .addressing_steps = &addressing.zero_page_steps,
            .execute = nopRead,
            .info = opcodes.OPCODE_TABLE[opcode],
        };
    }

    // 2-byte zero page,X NOPs (4 cycles)
    const zpx_nop_opcodes = [_]u8{ 0x14, 0x34, 0x54, 0x74, 0xD4, 0xF4 };
    for (zpx_nop_opcodes) |opcode| {
        table[opcode] = .{
            .addressing_steps = &addressing.zero_page_x_steps,
            .execute = nopRead,
            .info = opcodes.OPCODE_TABLE[opcode],
        };
    }

    // 3-byte absolute NOP (4 cycles)
    table[0x0C] = .{
        .addressing_steps = &addressing.absolute_steps,
        .execute = nopRead,
        .info = opcodes.OPCODE_TABLE[0x0C],
    };

    // 3-byte absolute,X NOPs (4-5 cycles with page crossing)
    const absx_nop_opcodes = [_]u8{ 0x1C, 0x3C, 0x5C, 0x7C, 0xDC, 0xFC };
    for (absx_nop_opcodes) |opcode| {
        table[opcode] = .{
            .addressing_steps = &addressing.absolute_x_read_steps,
            .execute = nopRead,
            .info = opcodes.OPCODE_TABLE[opcode],
        };
    }

    // ===== LDA Instructions =====
    table[0xA9] = .{
        .addressing_steps = &[_]MicrostepFn{}, // Immediate: no addressing steps
        .execute = loadstore.lda,
        .info = opcodes.OPCODE_TABLE[0xA9],
    };

    table[0xA5] = .{
        .addressing_steps = &addressing.zero_page_steps,
        .execute = loadstore.lda,
        .info = opcodes.OPCODE_TABLE[0xA5],
    };

    table[0xB5] = .{
        .addressing_steps = &addressing.zero_page_x_steps,
        .execute = loadstore.lda,
        .info = opcodes.OPCODE_TABLE[0xB5],
    };

    table[0xAD] = .{
        .addressing_steps = &addressing.absolute_steps,
        .execute = loadstore.lda,
        .info = opcodes.OPCODE_TABLE[0xAD],
    };

    table[0xBD] = .{
        .addressing_steps = &addressing.absolute_x_read_steps,
        .execute = loadstore.lda,
        .info = opcodes.OPCODE_TABLE[0xBD],
    };

    table[0xB9] = .{
        .addressing_steps = &addressing.absolute_y_read_steps,
        .execute = loadstore.lda,
        .info = opcodes.OPCODE_TABLE[0xB9],
    };

    table[0xA1] = .{
        .addressing_steps = &addressing.indexed_indirect_steps,
        .execute = loadstore.lda,
        .info = opcodes.OPCODE_TABLE[0xA1],
    };

    table[0xB1] = .{
        .addressing_steps = &addressing.indirect_indexed_read_steps,
        .execute = loadstore.lda,
        .info = opcodes.OPCODE_TABLE[0xB1],
    };

    // ===== STA Instructions =====
    table[0x85] = .{
        .addressing_steps = &addressing.zero_page_steps,
        .execute = loadstore.sta,
        .info = opcodes.OPCODE_TABLE[0x85],
    };

    table[0x95] = .{
        .addressing_steps = &addressing.zero_page_x_steps,
        .execute = loadstore.sta,
        .info = opcodes.OPCODE_TABLE[0x95],
    };

    table[0x8D] = .{
        .addressing_steps = &addressing.absolute_steps,
        .execute = loadstore.sta,
        .info = opcodes.OPCODE_TABLE[0x8D],
    };

    table[0x9D] = .{
        .addressing_steps = &addressing.absolute_x_write_steps,
        .execute = loadstore.sta,
        .info = opcodes.OPCODE_TABLE[0x9D],
    };

    table[0x99] = .{
        .addressing_steps = &addressing.absolute_y_write_steps,
        .execute = loadstore.sta,
        .info = opcodes.OPCODE_TABLE[0x99],
    };

    table[0x81] = .{
        .addressing_steps = &addressing.indexed_indirect_steps,
        .execute = loadstore.sta,
        .info = opcodes.OPCODE_TABLE[0x81],
    };

    table[0x91] = .{
        .addressing_steps = &addressing.indirect_indexed_write_steps,
        .execute = loadstore.sta,
        .info = opcodes.OPCODE_TABLE[0x91],
    };

    // ===== ASL Instructions =====
    table[0x0A] = .{ // ASL accumulator
        .addressing_steps = &[_]MicrostepFn{},
        .execute = shifts.asl,
        .info = opcodes.OPCODE_TABLE[0x0A],
    };
    table[0x06] = .{ // ASL zero page
        .addressing_steps = &addressing.zero_page_rmw_steps,
        .execute = shifts.asl,
        .info = opcodes.OPCODE_TABLE[0x06],
    };
    table[0x16] = .{ // ASL zero page,X
        .addressing_steps = &addressing.zero_page_x_rmw_steps,
        .execute = shifts.asl,
        .info = opcodes.OPCODE_TABLE[0x16],
    };
    table[0x0E] = .{ // ASL absolute
        .addressing_steps = &addressing.absolute_rmw_steps,
        .execute = shifts.asl,
        .info = opcodes.OPCODE_TABLE[0x0E],
    };
    table[0x1E] = .{ // ASL absolute,X
        .addressing_steps = &addressing.absolute_x_rmw_steps,
        .execute = shifts.asl,
        .info = opcodes.OPCODE_TABLE[0x1E],
    };

    // ===== LSR Instructions =====
    table[0x4A] = .{ // LSR accumulator
        .addressing_steps = &[_]MicrostepFn{},
        .execute = shifts.lsr,
        .info = opcodes.OPCODE_TABLE[0x4A],
    };
    table[0x46] = .{ // LSR zero page
        .addressing_steps = &addressing.zero_page_rmw_steps,
        .execute = shifts.lsr,
        .info = opcodes.OPCODE_TABLE[0x46],
    };
    table[0x56] = .{ // LSR zero page,X
        .addressing_steps = &addressing.zero_page_x_rmw_steps,
        .execute = shifts.lsr,
        .info = opcodes.OPCODE_TABLE[0x56],
    };
    table[0x4E] = .{ // LSR absolute
        .addressing_steps = &addressing.absolute_rmw_steps,
        .execute = shifts.lsr,
        .info = opcodes.OPCODE_TABLE[0x4E],
    };
    table[0x5E] = .{ // LSR absolute,X
        .addressing_steps = &addressing.absolute_x_rmw_steps,
        .execute = shifts.lsr,
        .info = opcodes.OPCODE_TABLE[0x5E],
    };

    // ===== ROL Instructions =====
    table[0x2A] = .{ // ROL accumulator
        .addressing_steps = &[_]MicrostepFn{},
        .execute = shifts.rol,
        .info = opcodes.OPCODE_TABLE[0x2A],
    };
    table[0x26] = .{ // ROL zero page
        .addressing_steps = &addressing.zero_page_rmw_steps,
        .execute = shifts.rol,
        .info = opcodes.OPCODE_TABLE[0x26],
    };
    table[0x36] = .{ // ROL zero page,X
        .addressing_steps = &addressing.zero_page_x_rmw_steps,
        .execute = shifts.rol,
        .info = opcodes.OPCODE_TABLE[0x36],
    };
    table[0x2E] = .{ // ROL absolute
        .addressing_steps = &addressing.absolute_rmw_steps,
        .execute = shifts.rol,
        .info = opcodes.OPCODE_TABLE[0x2E],
    };
    table[0x3E] = .{ // ROL absolute,X
        .addressing_steps = &addressing.absolute_x_rmw_steps,
        .execute = shifts.rol,
        .info = opcodes.OPCODE_TABLE[0x3E],
    };

    // ===== ROR Instructions =====
    table[0x6A] = .{ // ROR accumulator
        .addressing_steps = &[_]MicrostepFn{},
        .execute = shifts.ror,
        .info = opcodes.OPCODE_TABLE[0x6A],
    };
    table[0x66] = .{ // ROR zero page
        .addressing_steps = &addressing.zero_page_rmw_steps,
        .execute = shifts.ror,
        .info = opcodes.OPCODE_TABLE[0x66],
    };
    table[0x76] = .{ // ROR zero page,X
        .addressing_steps = &addressing.zero_page_x_rmw_steps,
        .execute = shifts.ror,
        .info = opcodes.OPCODE_TABLE[0x76],
    };
    table[0x6E] = .{ // ROR absolute
        .addressing_steps = &addressing.absolute_rmw_steps,
        .execute = shifts.ror,
        .info = opcodes.OPCODE_TABLE[0x6E],
    };
    table[0x7E] = .{ // ROR absolute,X
        .addressing_steps = &addressing.absolute_x_rmw_steps,
        .execute = shifts.ror,
        .info = opcodes.OPCODE_TABLE[0x7E],
    };

    // ===== INC Instructions =====
    table[0xE6] = .{ // INC zero page
        .addressing_steps = &addressing.zero_page_rmw_steps,
        .execute = incdec.inc,
        .info = opcodes.OPCODE_TABLE[0xE6],
    };
    table[0xF6] = .{ // INC zero page,X
        .addressing_steps = &addressing.zero_page_x_rmw_steps,
        .execute = incdec.inc,
        .info = opcodes.OPCODE_TABLE[0xF6],
    };
    table[0xEE] = .{ // INC absolute
        .addressing_steps = &addressing.absolute_rmw_steps,
        .execute = incdec.inc,
        .info = opcodes.OPCODE_TABLE[0xEE],
    };
    table[0xFE] = .{ // INC absolute,X
        .addressing_steps = &addressing.absolute_x_rmw_steps,
        .execute = incdec.inc,
        .info = opcodes.OPCODE_TABLE[0xFE],
    };

    // ===== DEC Instructions =====
    table[0xC6] = .{ // DEC zero page
        .addressing_steps = &addressing.zero_page_rmw_steps,
        .execute = incdec.dec,
        .info = opcodes.OPCODE_TABLE[0xC6],
    };
    table[0xD6] = .{ // DEC zero page,X
        .addressing_steps = &addressing.zero_page_x_rmw_steps,
        .execute = incdec.dec,
        .info = opcodes.OPCODE_TABLE[0xD6],
    };
    table[0xCE] = .{ // DEC absolute
        .addressing_steps = &addressing.absolute_rmw_steps,
        .execute = incdec.dec,
        .info = opcodes.OPCODE_TABLE[0xCE],
    };
    table[0xDE] = .{ // DEC absolute,X
        .addressing_steps = &addressing.absolute_x_rmw_steps,
        .execute = incdec.dec,
        .info = opcodes.OPCODE_TABLE[0xDE],
    };

    // ===== Register Inc/Dec Instructions =====
    table[0xE8] = .{ // INX
        .addressing_steps = &[_]MicrostepFn{},
        .execute = incdec.inx,
        .info = opcodes.OPCODE_TABLE[0xE8],
    };
    table[0xC8] = .{ // INY
        .addressing_steps = &[_]MicrostepFn{},
        .execute = incdec.iny,
        .info = opcodes.OPCODE_TABLE[0xC8],
    };
    table[0xCA] = .{ // DEX
        .addressing_steps = &[_]MicrostepFn{},
        .execute = incdec.dex,
        .info = opcodes.OPCODE_TABLE[0xCA],
    };
    table[0x88] = .{ // DEY
        .addressing_steps = &[_]MicrostepFn{},
        .execute = incdec.dey,
        .info = opcodes.OPCODE_TABLE[0x88],
    };

    // ===== ADC Instructions (Add with Carry) =====
    table[0x69] = .{ // ADC immediate
        .addressing_steps = &[_]MicrostepFn{},
        .execute = arithmetic.adc,
        .info = opcodes.OPCODE_TABLE[0x69],
    };
    table[0x65] = .{ // ADC zero page
        .addressing_steps = &addressing.zero_page_steps,
        .execute = arithmetic.adc,
        .info = opcodes.OPCODE_TABLE[0x65],
    };
    table[0x75] = .{ // ADC zero page,X
        .addressing_steps = &addressing.zero_page_x_steps,
        .execute = arithmetic.adc,
        .info = opcodes.OPCODE_TABLE[0x75],
    };
    table[0x6D] = .{ // ADC absolute
        .addressing_steps = &addressing.absolute_steps,
        .execute = arithmetic.adc,
        .info = opcodes.OPCODE_TABLE[0x6D],
    };
    table[0x7D] = .{ // ADC absolute,X
        .addressing_steps = &addressing.absolute_x_read_steps,
        .execute = arithmetic.adc,
        .info = opcodes.OPCODE_TABLE[0x7D],
    };
    table[0x79] = .{ // ADC absolute,Y
        .addressing_steps = &addressing.absolute_y_read_steps,
        .execute = arithmetic.adc,
        .info = opcodes.OPCODE_TABLE[0x79],
    };
    table[0x61] = .{ // ADC indexed indirect
        .addressing_steps = &addressing.indexed_indirect_steps,
        .execute = arithmetic.adc,
        .info = opcodes.OPCODE_TABLE[0x61],
    };
    table[0x71] = .{ // ADC indirect indexed
        .addressing_steps = &addressing.indirect_indexed_read_steps,
        .execute = arithmetic.adc,
        .info = opcodes.OPCODE_TABLE[0x71],
    };

    // ===== SBC Instructions (Subtract with Carry) =====
    table[0xE9] = .{ // SBC immediate
        .addressing_steps = &[_]MicrostepFn{},
        .execute = arithmetic.sbc,
        .info = opcodes.OPCODE_TABLE[0xE9],
    };
    table[0xE5] = .{ // SBC zero page
        .addressing_steps = &addressing.zero_page_steps,
        .execute = arithmetic.sbc,
        .info = opcodes.OPCODE_TABLE[0xE5],
    };
    table[0xF5] = .{ // SBC zero page,X
        .addressing_steps = &addressing.zero_page_x_steps,
        .execute = arithmetic.sbc,
        .info = opcodes.OPCODE_TABLE[0xF5],
    };
    table[0xED] = .{ // SBC absolute
        .addressing_steps = &addressing.absolute_steps,
        .execute = arithmetic.sbc,
        .info = opcodes.OPCODE_TABLE[0xED],
    };
    table[0xFD] = .{ // SBC absolute,X
        .addressing_steps = &addressing.absolute_x_read_steps,
        .execute = arithmetic.sbc,
        .info = opcodes.OPCODE_TABLE[0xFD],
    };
    table[0xF9] = .{ // SBC absolute,Y
        .addressing_steps = &addressing.absolute_y_read_steps,
        .execute = arithmetic.sbc,
        .info = opcodes.OPCODE_TABLE[0xF9],
    };
    table[0xE1] = .{ // SBC indexed indirect
        .addressing_steps = &addressing.indexed_indirect_steps,
        .execute = arithmetic.sbc,
        .info = opcodes.OPCODE_TABLE[0xE1],
    };
    table[0xF1] = .{ // SBC indirect indexed
        .addressing_steps = &addressing.indirect_indexed_read_steps,
        .execute = arithmetic.sbc,
        .info = opcodes.OPCODE_TABLE[0xF1],
    };

    // ===== AND Instructions (Logical AND) =====
    table[0x29] = .{ // AND immediate
        .addressing_steps = &[_]MicrostepFn{},
        .execute = logical.logicalAnd,
        .info = opcodes.OPCODE_TABLE[0x29],
    };
    table[0x25] = .{ // AND zero page
        .addressing_steps = &addressing.zero_page_steps,
        .execute = logical.logicalAnd,
        .info = opcodes.OPCODE_TABLE[0x25],
    };
    table[0x35] = .{ // AND zero page,X
        .addressing_steps = &addressing.zero_page_x_steps,
        .execute = logical.logicalAnd,
        .info = opcodes.OPCODE_TABLE[0x35],
    };
    table[0x2D] = .{ // AND absolute
        .addressing_steps = &addressing.absolute_steps,
        .execute = logical.logicalAnd,
        .info = opcodes.OPCODE_TABLE[0x2D],
    };
    table[0x3D] = .{ // AND absolute,X
        .addressing_steps = &addressing.absolute_x_read_steps,
        .execute = logical.logicalAnd,
        .info = opcodes.OPCODE_TABLE[0x3D],
    };
    table[0x39] = .{ // AND absolute,Y
        .addressing_steps = &addressing.absolute_y_read_steps,
        .execute = logical.logicalAnd,
        .info = opcodes.OPCODE_TABLE[0x39],
    };
    table[0x21] = .{ // AND indexed indirect
        .addressing_steps = &addressing.indexed_indirect_steps,
        .execute = logical.logicalAnd,
        .info = opcodes.OPCODE_TABLE[0x21],
    };
    table[0x31] = .{ // AND indirect indexed
        .addressing_steps = &addressing.indirect_indexed_read_steps,
        .execute = logical.logicalAnd,
        .info = opcodes.OPCODE_TABLE[0x31],
    };

    // ===== ORA Instructions (Logical OR) =====
    table[0x09] = .{ // ORA immediate
        .addressing_steps = &[_]MicrostepFn{},
        .execute = logical.logicalOr,
        .info = opcodes.OPCODE_TABLE[0x09],
    };
    table[0x05] = .{ // ORA zero page
        .addressing_steps = &addressing.zero_page_steps,
        .execute = logical.logicalOr,
        .info = opcodes.OPCODE_TABLE[0x05],
    };
    table[0x15] = .{ // ORA zero page,X
        .addressing_steps = &addressing.zero_page_x_steps,
        .execute = logical.logicalOr,
        .info = opcodes.OPCODE_TABLE[0x15],
    };
    table[0x0D] = .{ // ORA absolute
        .addressing_steps = &addressing.absolute_steps,
        .execute = logical.logicalOr,
        .info = opcodes.OPCODE_TABLE[0x0D],
    };
    table[0x1D] = .{ // ORA absolute,X
        .addressing_steps = &addressing.absolute_x_read_steps,
        .execute = logical.logicalOr,
        .info = opcodes.OPCODE_TABLE[0x1D],
    };
    table[0x19] = .{ // ORA absolute,Y
        .addressing_steps = &addressing.absolute_y_read_steps,
        .execute = logical.logicalOr,
        .info = opcodes.OPCODE_TABLE[0x19],
    };
    table[0x01] = .{ // ORA indexed indirect
        .addressing_steps = &addressing.indexed_indirect_steps,
        .execute = logical.logicalOr,
        .info = opcodes.OPCODE_TABLE[0x01],
    };
    table[0x11] = .{ // ORA indirect indexed
        .addressing_steps = &addressing.indirect_indexed_read_steps,
        .execute = logical.logicalOr,
        .info = opcodes.OPCODE_TABLE[0x11],
    };

    // ===== EOR Instructions (Logical XOR) =====
    table[0x49] = .{ // EOR immediate
        .addressing_steps = &[_]MicrostepFn{},
        .execute = logical.logicalXor,
        .info = opcodes.OPCODE_TABLE[0x49],
    };
    table[0x45] = .{ // EOR zero page
        .addressing_steps = &addressing.zero_page_steps,
        .execute = logical.logicalXor,
        .info = opcodes.OPCODE_TABLE[0x45],
    };
    table[0x55] = .{ // EOR zero page,X
        .addressing_steps = &addressing.zero_page_x_steps,
        .execute = logical.logicalXor,
        .info = opcodes.OPCODE_TABLE[0x55],
    };
    table[0x4D] = .{ // EOR absolute
        .addressing_steps = &addressing.absolute_steps,
        .execute = logical.logicalXor,
        .info = opcodes.OPCODE_TABLE[0x4D],
    };
    table[0x5D] = .{ // EOR absolute,X
        .addressing_steps = &addressing.absolute_x_read_steps,
        .execute = logical.logicalXor,
        .info = opcodes.OPCODE_TABLE[0x5D],
    };
    table[0x59] = .{ // EOR absolute,Y
        .addressing_steps = &addressing.absolute_y_read_steps,
        .execute = logical.logicalXor,
        .info = opcodes.OPCODE_TABLE[0x59],
    };
    table[0x41] = .{ // EOR indexed indirect
        .addressing_steps = &addressing.indexed_indirect_steps,
        .execute = logical.logicalXor,
        .info = opcodes.OPCODE_TABLE[0x41],
    };
    table[0x51] = .{ // EOR indirect indexed
        .addressing_steps = &addressing.indirect_indexed_read_steps,
        .execute = logical.logicalXor,
        .info = opcodes.OPCODE_TABLE[0x51],
    };

    // ===== CMP Instructions (Compare Accumulator) =====
    table[0xC9] = .{ // CMP immediate
        .addressing_steps = &[_]MicrostepFn{},
        .execute = compare.cmp,
        .info = opcodes.OPCODE_TABLE[0xC9],
    };
    table[0xC5] = .{ // CMP zero page
        .addressing_steps = &addressing.zero_page_steps,
        .execute = compare.cmp,
        .info = opcodes.OPCODE_TABLE[0xC5],
    };
    table[0xD5] = .{ // CMP zero page,X
        .addressing_steps = &addressing.zero_page_x_steps,
        .execute = compare.cmp,
        .info = opcodes.OPCODE_TABLE[0xD5],
    };
    table[0xCD] = .{ // CMP absolute
        .addressing_steps = &addressing.absolute_steps,
        .execute = compare.cmp,
        .info = opcodes.OPCODE_TABLE[0xCD],
    };
    table[0xDD] = .{ // CMP absolute,X
        .addressing_steps = &addressing.absolute_x_read_steps,
        .execute = compare.cmp,
        .info = opcodes.OPCODE_TABLE[0xDD],
    };
    table[0xD9] = .{ // CMP absolute,Y
        .addressing_steps = &addressing.absolute_y_read_steps,
        .execute = compare.cmp,
        .info = opcodes.OPCODE_TABLE[0xD9],
    };
    table[0xC1] = .{ // CMP indexed indirect
        .addressing_steps = &addressing.indexed_indirect_steps,
        .execute = compare.cmp,
        .info = opcodes.OPCODE_TABLE[0xC1],
    };
    table[0xD1] = .{ // CMP indirect indexed
        .addressing_steps = &addressing.indirect_indexed_read_steps,
        .execute = compare.cmp,
        .info = opcodes.OPCODE_TABLE[0xD1],
    };

    // ===== CPX Instructions (Compare X) =====
    table[0xE0] = .{ // CPX immediate
        .addressing_steps = &[_]MicrostepFn{},
        .execute = compare.cpx,
        .info = opcodes.OPCODE_TABLE[0xE0],
    };
    table[0xE4] = .{ // CPX zero page
        .addressing_steps = &addressing.zero_page_steps,
        .execute = compare.cpx,
        .info = opcodes.OPCODE_TABLE[0xE4],
    };
    table[0xEC] = .{ // CPX absolute
        .addressing_steps = &addressing.absolute_steps,
        .execute = compare.cpx,
        .info = opcodes.OPCODE_TABLE[0xEC],
    };

    // ===== CPY Instructions (Compare Y) =====
    table[0xC0] = .{ // CPY immediate
        .addressing_steps = &[_]MicrostepFn{},
        .execute = compare.cpy,
        .info = opcodes.OPCODE_TABLE[0xC0],
    };
    table[0xC4] = .{ // CPY zero page
        .addressing_steps = &addressing.zero_page_steps,
        .execute = compare.cpy,
        .info = opcodes.OPCODE_TABLE[0xC4],
    };
    table[0xCC] = .{ // CPY absolute
        .addressing_steps = &addressing.absolute_steps,
        .execute = compare.cpy,
        .info = opcodes.OPCODE_TABLE[0xCC],
    };

    // ===== Transfer Instructions (2 cycles, implied) =====
    table[0xAA] = .{ // TAX
        .addressing_steps = &[_]MicrostepFn{},
        .execute = transfer.tax,
        .info = opcodes.OPCODE_TABLE[0xAA],
    };
    table[0x8A] = .{ // TXA
        .addressing_steps = &[_]MicrostepFn{},
        .execute = transfer.txa,
        .info = opcodes.OPCODE_TABLE[0x8A],
    };
    table[0xA8] = .{ // TAY
        .addressing_steps = &[_]MicrostepFn{},
        .execute = transfer.tay,
        .info = opcodes.OPCODE_TABLE[0xA8],
    };
    table[0x98] = .{ // TYA
        .addressing_steps = &[_]MicrostepFn{},
        .execute = transfer.tya,
        .info = opcodes.OPCODE_TABLE[0x98],
    };
    table[0xBA] = .{ // TSX
        .addressing_steps = &[_]MicrostepFn{},
        .execute = transfer.tsx,
        .info = opcodes.OPCODE_TABLE[0xBA],
    };
    table[0x9A] = .{ // TXS
        .addressing_steps = &[_]MicrostepFn{},
        .execute = transfer.txs,
        .info = opcodes.OPCODE_TABLE[0x9A],
    };

    // ===== Flag Instructions (2 cycles, implied) =====
    table[0x38] = .{ // SEC
        .addressing_steps = &[_]MicrostepFn{},
        .execute = transfer.sec,
        .info = opcodes.OPCODE_TABLE[0x38],
    };
    table[0x18] = .{ // CLC
        .addressing_steps = &[_]MicrostepFn{},
        .execute = transfer.clc,
        .info = opcodes.OPCODE_TABLE[0x18],
    };
    table[0x78] = .{ // SEI
        .addressing_steps = &[_]MicrostepFn{},
        .execute = transfer.sei,
        .info = opcodes.OPCODE_TABLE[0x78],
    };
    table[0x58] = .{ // CLI
        .addressing_steps = &[_]MicrostepFn{},
        .execute = transfer.cli,
        .info = opcodes.OPCODE_TABLE[0x58],
    };
    table[0xF8] = .{ // SED
        .addressing_steps = &[_]MicrostepFn{},
        .execute = transfer.sed,
        .info = opcodes.OPCODE_TABLE[0xF8],
    };
    table[0xD8] = .{ // CLD
        .addressing_steps = &[_]MicrostepFn{},
        .execute = transfer.cld,
        .info = opcodes.OPCODE_TABLE[0xD8],
    };
    table[0xB8] = .{ // CLV
        .addressing_steps = &[_]MicrostepFn{},
        .execute = transfer.clv,
        .info = opcodes.OPCODE_TABLE[0xB8],
    };

    // ===== BIT Instruction =====
    table[0x24] = .{ // BIT zero page
        .addressing_steps = &addressing.zero_page_steps,
        .execute = transfer.bit,
        .info = opcodes.OPCODE_TABLE[0x24],
    };
    table[0x2C] = .{ // BIT absolute
        .addressing_steps = &addressing.absolute_steps,
        .execute = transfer.bit,
        .info = opcodes.OPCODE_TABLE[0x2C],
    };

    // ===== Branch Instructions =====
    table[0x90] = .{ // BCC - Branch if Carry Clear
        .addressing_steps = &addressing.relative_steps,
        .execute = branch.bcc,
        .info = opcodes.OPCODE_TABLE[0x90],
    };
    table[0xB0] = .{ // BCS - Branch if Carry Set
        .addressing_steps = &addressing.relative_steps,
        .execute = branch.bcs,
        .info = opcodes.OPCODE_TABLE[0xB0],
    };
    table[0xF0] = .{ // BEQ - Branch if Equal
        .addressing_steps = &addressing.relative_steps,
        .execute = branch.beq,
        .info = opcodes.OPCODE_TABLE[0xF0],
    };
    table[0xD0] = .{ // BNE - Branch if Not Equal
        .addressing_steps = &addressing.relative_steps,
        .execute = branch.bne,
        .info = opcodes.OPCODE_TABLE[0xD0],
    };
    table[0x30] = .{ // BMI - Branch if Minus
        .addressing_steps = &addressing.relative_steps,
        .execute = branch.bmi,
        .info = opcodes.OPCODE_TABLE[0x30],
    };
    table[0x10] = .{ // BPL - Branch if Plus
        .addressing_steps = &addressing.relative_steps,
        .execute = branch.bpl,
        .info = opcodes.OPCODE_TABLE[0x10],
    };
    table[0x50] = .{ // BVC - Branch if Overflow Clear
        .addressing_steps = &addressing.relative_steps,
        .execute = branch.bvc,
        .info = opcodes.OPCODE_TABLE[0x50],
    };
    table[0x70] = .{ // BVS - Branch if Overflow Set
        .addressing_steps = &addressing.relative_steps,
        .execute = branch.bvs,
        .info = opcodes.OPCODE_TABLE[0x70],
    };

    // ===== Jump/Control Flow Instructions =====
    table[0x4C] = .{ // JMP absolute
        .addressing_steps = &addressing.absolute_steps,
        .execute = jumps.jmp,
        .info = opcodes.OPCODE_TABLE[0x4C],
    };
    table[0x6C] = .{ // JMP indirect
        .addressing_steps = &addressing.indirect_jmp_steps,
        .execute = jumps.jmp,
        .info = opcodes.OPCODE_TABLE[0x6C],
    };
    table[0x20] = .{ // JSR absolute
        .addressing_steps = &addressing.absolute_steps,
        .execute = jumps.jsr,
        .info = opcodes.OPCODE_TABLE[0x20],
    };
    table[0x60] = .{ // RTS
        .addressing_steps = &[_]MicrostepFn{},
        .execute = jumps.rts,
        .info = opcodes.OPCODE_TABLE[0x60],
    };
    table[0x40] = .{ // RTI
        .addressing_steps = &[_]MicrostepFn{},
        .execute = jumps.rti,
        .info = opcodes.OPCODE_TABLE[0x40],
    };
    table[0x00] = .{ // BRK
        .addressing_steps = &[_]MicrostepFn{},
        .execute = jumps.brk,
        .info = opcodes.OPCODE_TABLE[0x00],
    };

    // ===== LDX Instructions =====
    table[0xA2] = .{ // LDX immediate
        .addressing_steps = &[_]MicrostepFn{},
        .execute = loadstore.ldx,
        .info = opcodes.OPCODE_TABLE[0xA2],
    };
    table[0xA6] = .{ // LDX zero page
        .addressing_steps = &addressing.zero_page_steps,
        .execute = loadstore.ldx,
        .info = opcodes.OPCODE_TABLE[0xA6],
    };
    table[0xB6] = .{ // LDX zero page,Y
        .addressing_steps = &addressing.zero_page_y_steps,
        .execute = loadstore.ldx,
        .info = opcodes.OPCODE_TABLE[0xB6],
    };
    table[0xAE] = .{ // LDX absolute
        .addressing_steps = &addressing.absolute_steps,
        .execute = loadstore.ldx,
        .info = opcodes.OPCODE_TABLE[0xAE],
    };
    table[0xBE] = .{ // LDX absolute,Y
        .addressing_steps = &addressing.absolute_y_read_steps,
        .execute = loadstore.ldx,
        .info = opcodes.OPCODE_TABLE[0xBE],
    };

    // ===== LDY Instructions =====
    table[0xA0] = .{ // LDY immediate
        .addressing_steps = &[_]MicrostepFn{},
        .execute = loadstore.ldy,
        .info = opcodes.OPCODE_TABLE[0xA0],
    };
    table[0xA4] = .{ // LDY zero page
        .addressing_steps = &addressing.zero_page_steps,
        .execute = loadstore.ldy,
        .info = opcodes.OPCODE_TABLE[0xA4],
    };
    table[0xB4] = .{ // LDY zero page,X
        .addressing_steps = &addressing.zero_page_x_steps,
        .execute = loadstore.ldy,
        .info = opcodes.OPCODE_TABLE[0xB4],
    };
    table[0xAC] = .{ // LDY absolute
        .addressing_steps = &addressing.absolute_steps,
        .execute = loadstore.ldy,
        .info = opcodes.OPCODE_TABLE[0xAC],
    };
    table[0xBC] = .{ // LDY absolute,X
        .addressing_steps = &addressing.absolute_x_read_steps,
        .execute = loadstore.ldy,
        .info = opcodes.OPCODE_TABLE[0xBC],
    };

    // ===== STX Instructions =====
    table[0x86] = .{ // STX zero page
        .addressing_steps = &addressing.zero_page_steps,
        .execute = loadstore.stx,
        .info = opcodes.OPCODE_TABLE[0x86],
    };
    table[0x96] = .{ // STX zero page,Y
        .addressing_steps = &addressing.zero_page_y_steps,
        .execute = loadstore.stx,
        .info = opcodes.OPCODE_TABLE[0x96],
    };
    table[0x8E] = .{ // STX absolute
        .addressing_steps = &addressing.absolute_steps,
        .execute = loadstore.stx,
        .info = opcodes.OPCODE_TABLE[0x8E],
    };

    // ===== STY Instructions =====
    table[0x84] = .{ // STY zero page
        .addressing_steps = &addressing.zero_page_steps,
        .execute = loadstore.sty,
        .info = opcodes.OPCODE_TABLE[0x84],
    };
    table[0x94] = .{ // STY zero page,X
        .addressing_steps = &addressing.zero_page_x_steps,
        .execute = loadstore.sty,
        .info = opcodes.OPCODE_TABLE[0x94],
    };
    table[0x8C] = .{ // STY absolute
        .addressing_steps = &addressing.absolute_steps,
        .execute = loadstore.sty,
        .info = opcodes.OPCODE_TABLE[0x8C],
    };

    // ===== LAX Instructions (Unofficial) =====
    table[0xA7] = .{ // LAX zero page
        .addressing_steps = &addressing.zero_page_steps,
        .execute = unofficial.lax,
        .info = opcodes.OPCODE_TABLE[0xA7],
    };
    table[0xB7] = .{ // LAX zero page,Y
        .addressing_steps = &addressing.zero_page_y_steps,
        .execute = unofficial.lax,
        .info = opcodes.OPCODE_TABLE[0xB7],
    };
    table[0xAF] = .{ // LAX absolute
        .addressing_steps = &addressing.absolute_steps,
        .execute = unofficial.lax,
        .info = opcodes.OPCODE_TABLE[0xAF],
    };
    table[0xBF] = .{ // LAX absolute,Y
        .addressing_steps = &addressing.absolute_y_read_steps,
        .execute = unofficial.lax,
        .info = opcodes.OPCODE_TABLE[0xBF],
    };
    table[0xA3] = .{ // LAX indexed indirect
        .addressing_steps = &addressing.indexed_indirect_steps,
        .execute = unofficial.lax,
        .info = opcodes.OPCODE_TABLE[0xA3],
    };
    table[0xB3] = .{ // LAX indirect indexed
        .addressing_steps = &addressing.indirect_indexed_read_steps,
        .execute = unofficial.lax,
        .info = opcodes.OPCODE_TABLE[0xB3],
    };

    // ===== SAX Instructions (Unofficial) =====
    table[0x87] = .{ // SAX zero page
        .addressing_steps = &addressing.zero_page_steps,
        .execute = unofficial.sax,
        .info = opcodes.OPCODE_TABLE[0x87],
    };
    table[0x97] = .{ // SAX zero page,Y
        .addressing_steps = &addressing.zero_page_y_steps,
        .execute = unofficial.sax,
        .info = opcodes.OPCODE_TABLE[0x97],
    };
    table[0x8F] = .{ // SAX absolute
        .addressing_steps = &addressing.absolute_steps,
        .execute = unofficial.sax,
        .info = opcodes.OPCODE_TABLE[0x8F],
    };
    table[0x83] = .{ // SAX indexed indirect
        .addressing_steps = &addressing.indexed_indirect_steps,
        .execute = unofficial.sax,
        .info = opcodes.OPCODE_TABLE[0x83],
    };

    // ===== SLO Instructions (Unofficial RMW) =====
    table[0x07] = .{ // SLO zero page
        .addressing_steps = &addressing.zero_page_rmw_steps,
        .execute = unofficial.slo,
        .info = opcodes.OPCODE_TABLE[0x07],
    };
    table[0x17] = .{ // SLO zero page,X
        .addressing_steps = &addressing.zero_page_x_rmw_steps,
        .execute = unofficial.slo,
        .info = opcodes.OPCODE_TABLE[0x17],
    };
    table[0x0F] = .{ // SLO absolute
        .addressing_steps = &addressing.absolute_rmw_steps,
        .execute = unofficial.slo,
        .info = opcodes.OPCODE_TABLE[0x0F],
    };
    table[0x1F] = .{ // SLO absolute,X
        .addressing_steps = &addressing.absolute_x_rmw_steps,
        .execute = unofficial.slo,
        .info = opcodes.OPCODE_TABLE[0x1F],
    };
    table[0x1B] = .{ // SLO absolute,Y
        .addressing_steps = &addressing.absolute_x_rmw_steps, // Y uses same RMW pattern
        .execute = unofficial.slo,
        .info = opcodes.OPCODE_TABLE[0x1B],
    };
    table[0x03] = .{ // SLO indexed indirect
        .addressing_steps = &addressing.indexed_indirect_rmw_steps,
        .execute = unofficial.slo,
        .info = opcodes.OPCODE_TABLE[0x03],
    };
    table[0x13] = .{ // SLO indirect indexed
        .addressing_steps = &addressing.indirect_indexed_rmw_steps,
        .execute = unofficial.slo,
        .info = opcodes.OPCODE_TABLE[0x13],
    };

    // ===== RLA Instructions (Unofficial RMW) =====
    table[0x27] = .{ // RLA zero page
        .addressing_steps = &addressing.zero_page_rmw_steps,
        .execute = unofficial.rla,
        .info = opcodes.OPCODE_TABLE[0x27],
    };
    table[0x37] = .{ // RLA zero page,X
        .addressing_steps = &addressing.zero_page_x_rmw_steps,
        .execute = unofficial.rla,
        .info = opcodes.OPCODE_TABLE[0x37],
    };
    table[0x2F] = .{ // RLA absolute
        .addressing_steps = &addressing.absolute_rmw_steps,
        .execute = unofficial.rla,
        .info = opcodes.OPCODE_TABLE[0x2F],
    };
    table[0x3F] = .{ // RLA absolute,X
        .addressing_steps = &addressing.absolute_x_rmw_steps,
        .execute = unofficial.rla,
        .info = opcodes.OPCODE_TABLE[0x3F],
    };
    table[0x3B] = .{ // RLA absolute,Y
        .addressing_steps = &addressing.absolute_x_rmw_steps,
        .execute = unofficial.rla,
        .info = opcodes.OPCODE_TABLE[0x3B],
    };
    table[0x23] = .{ // RLA indexed indirect
        .addressing_steps = &addressing.indexed_indirect_rmw_steps,
        .execute = unofficial.rla,
        .info = opcodes.OPCODE_TABLE[0x23],
    };
    table[0x33] = .{ // RLA indirect indexed
        .addressing_steps = &addressing.indirect_indexed_rmw_steps,
        .execute = unofficial.rla,
        .info = opcodes.OPCODE_TABLE[0x33],
    };

    // ===== SRE Instructions (Unofficial RMW) =====
    table[0x47] = .{ // SRE zero page
        .addressing_steps = &addressing.zero_page_rmw_steps,
        .execute = unofficial.sre,
        .info = opcodes.OPCODE_TABLE[0x47],
    };
    table[0x57] = .{ // SRE zero page,X
        .addressing_steps = &addressing.zero_page_x_rmw_steps,
        .execute = unofficial.sre,
        .info = opcodes.OPCODE_TABLE[0x57],
    };
    table[0x4F] = .{ // SRE absolute
        .addressing_steps = &addressing.absolute_rmw_steps,
        .execute = unofficial.sre,
        .info = opcodes.OPCODE_TABLE[0x4F],
    };
    table[0x5F] = .{ // SRE absolute,X
        .addressing_steps = &addressing.absolute_x_rmw_steps,
        .execute = unofficial.sre,
        .info = opcodes.OPCODE_TABLE[0x5F],
    };
    table[0x5B] = .{ // SRE absolute,Y
        .addressing_steps = &addressing.absolute_x_rmw_steps,
        .execute = unofficial.sre,
        .info = opcodes.OPCODE_TABLE[0x5B],
    };
    table[0x43] = .{ // SRE indexed indirect
        .addressing_steps = &addressing.indexed_indirect_rmw_steps,
        .execute = unofficial.sre,
        .info = opcodes.OPCODE_TABLE[0x43],
    };
    table[0x53] = .{ // SRE indirect indexed
        .addressing_steps = &addressing.indirect_indexed_rmw_steps,
        .execute = unofficial.sre,
        .info = opcodes.OPCODE_TABLE[0x53],
    };

    // ===== RRA Instructions (Unofficial RMW) =====
    table[0x67] = .{ // RRA zero page
        .addressing_steps = &addressing.zero_page_rmw_steps,
        .execute = unofficial.rra,
        .info = opcodes.OPCODE_TABLE[0x67],
    };
    table[0x77] = .{ // RRA zero page,X
        .addressing_steps = &addressing.zero_page_x_rmw_steps,
        .execute = unofficial.rra,
        .info = opcodes.OPCODE_TABLE[0x77],
    };
    table[0x6F] = .{ // RRA absolute
        .addressing_steps = &addressing.absolute_rmw_steps,
        .execute = unofficial.rra,
        .info = opcodes.OPCODE_TABLE[0x6F],
    };
    table[0x7F] = .{ // RRA absolute,X
        .addressing_steps = &addressing.absolute_x_rmw_steps,
        .execute = unofficial.rra,
        .info = opcodes.OPCODE_TABLE[0x7F],
    };
    table[0x7B] = .{ // RRA absolute,Y
        .addressing_steps = &addressing.absolute_x_rmw_steps,
        .execute = unofficial.rra,
        .info = opcodes.OPCODE_TABLE[0x7B],
    };
    table[0x63] = .{ // RRA indexed indirect
        .addressing_steps = &addressing.indexed_indirect_rmw_steps,
        .execute = unofficial.rra,
        .info = opcodes.OPCODE_TABLE[0x63],
    };
    table[0x73] = .{ // RRA indirect indexed
        .addressing_steps = &addressing.indirect_indexed_rmw_steps,
        .execute = unofficial.rra,
        .info = opcodes.OPCODE_TABLE[0x73],
    };

    // ===== DCP Instructions (Unofficial RMW) =====
    table[0xC7] = .{ // DCP zero page
        .addressing_steps = &addressing.zero_page_rmw_steps,
        .execute = unofficial.dcp,
        .info = opcodes.OPCODE_TABLE[0xC7],
    };
    table[0xD7] = .{ // DCP zero page,X
        .addressing_steps = &addressing.zero_page_x_rmw_steps,
        .execute = unofficial.dcp,
        .info = opcodes.OPCODE_TABLE[0xD7],
    };
    table[0xCF] = .{ // DCP absolute
        .addressing_steps = &addressing.absolute_rmw_steps,
        .execute = unofficial.dcp,
        .info = opcodes.OPCODE_TABLE[0xCF],
    };
    table[0xDF] = .{ // DCP absolute,X
        .addressing_steps = &addressing.absolute_x_rmw_steps,
        .execute = unofficial.dcp,
        .info = opcodes.OPCODE_TABLE[0xDF],
    };
    table[0xDB] = .{ // DCP absolute,Y
        .addressing_steps = &addressing.absolute_x_rmw_steps,
        .execute = unofficial.dcp,
        .info = opcodes.OPCODE_TABLE[0xDB],
    };
    table[0xC3] = .{ // DCP indexed indirect
        .addressing_steps = &addressing.indexed_indirect_rmw_steps,
        .execute = unofficial.dcp,
        .info = opcodes.OPCODE_TABLE[0xC3],
    };
    table[0xD3] = .{ // DCP indirect indexed
        .addressing_steps = &addressing.indirect_indexed_rmw_steps,
        .execute = unofficial.dcp,
        .info = opcodes.OPCODE_TABLE[0xD3],
    };

    // ===== ISC Instructions (Unofficial RMW) =====
    table[0xE7] = .{ // ISC zero page
        .addressing_steps = &addressing.zero_page_rmw_steps,
        .execute = unofficial.isc,
        .info = opcodes.OPCODE_TABLE[0xE7],
    };
    table[0xF7] = .{ // ISC zero page,X
        .addressing_steps = &addressing.zero_page_x_rmw_steps,
        .execute = unofficial.isc,
        .info = opcodes.OPCODE_TABLE[0xF7],
    };
    table[0xEF] = .{ // ISC absolute
        .addressing_steps = &addressing.absolute_rmw_steps,
        .execute = unofficial.isc,
        .info = opcodes.OPCODE_TABLE[0xEF],
    };
    table[0xFF] = .{ // ISC absolute,X
        .addressing_steps = &addressing.absolute_x_rmw_steps,
        .execute = unofficial.isc,
        .info = opcodes.OPCODE_TABLE[0xFF],
    };
    table[0xFB] = .{ // ISC absolute,Y
        .addressing_steps = &addressing.absolute_x_rmw_steps,
        .execute = unofficial.isc,
        .info = opcodes.OPCODE_TABLE[0xFB],
    };
    table[0xE3] = .{ // ISC indexed indirect
        .addressing_steps = &addressing.indexed_indirect_rmw_steps,
        .execute = unofficial.isc,
        .info = opcodes.OPCODE_TABLE[0xE3],
    };
    table[0xF3] = .{ // ISC indirect indexed
        .addressing_steps = &addressing.indirect_indexed_rmw_steps,
        .execute = unofficial.isc,
        .info = opcodes.OPCODE_TABLE[0xF3],
    };

    // ===== Duplicate SBC (Unofficial) =====
    table[0xEB] = .{ // SBC immediate (duplicate of 0xE9)
        .addressing_steps = &[_]MicrostepFn{},
        .execute = arithmetic.sbc,
        .info = opcodes.OPCODE_TABLE[0xEB],
    };

    // ===== Immediate Logic/Math Instructions (Unofficial) =====
    table[0x0B] = .{ // ANC immediate
        .addressing_steps = &[_]MicrostepFn{},
        .execute = unofficial.anc,
        .info = opcodes.OPCODE_TABLE[0x0B],
    };
    table[0x2B] = .{ // ANC immediate (duplicate)
        .addressing_steps = &[_]MicrostepFn{},
        .execute = unofficial.anc,
        .info = opcodes.OPCODE_TABLE[0x2B],
    };
    table[0x4B] = .{ // ALR/ASR immediate
        .addressing_steps = &[_]MicrostepFn{},
        .execute = unofficial.alr,
        .info = opcodes.OPCODE_TABLE[0x4B],
    };
    table[0x6B] = .{ // ARR immediate
        .addressing_steps = &[_]MicrostepFn{},
        .execute = unofficial.arr,
        .info = opcodes.OPCODE_TABLE[0x6B],
    };
    table[0xCB] = .{ // AXS/SBX immediate
        .addressing_steps = &[_]MicrostepFn{},
        .execute = unofficial.axs,
        .info = opcodes.OPCODE_TABLE[0xCB],
    };

    // ===== Unstable Store Operations (Unofficial) =====
    table[0x9F] = .{ // SHA/AHX absolute,Y
        .addressing_steps = &addressing.absolute_y_write_steps,
        .execute = unofficial.sha,
        .info = opcodes.OPCODE_TABLE[0x9F],
    };
    table[0x93] = .{ // SHA/AHX indirect,Y
        .addressing_steps = &addressing.indirect_indexed_write_steps,
        .execute = unofficial.sha,
        .info = opcodes.OPCODE_TABLE[0x93],
    };
    table[0x9E] = .{ // SHX absolute,Y
        .addressing_steps = &addressing.absolute_y_write_steps,
        .execute = unofficial.shx,
        .info = opcodes.OPCODE_TABLE[0x9E],
    };
    table[0x9C] = .{ // SHY absolute,X
        .addressing_steps = &addressing.absolute_x_write_steps,
        .execute = unofficial.shy,
        .info = opcodes.OPCODE_TABLE[0x9C],
    };
    table[0x9B] = .{ // TAS/SHS absolute,Y
        .addressing_steps = &addressing.absolute_y_write_steps,
        .execute = unofficial.tas,
        .info = opcodes.OPCODE_TABLE[0x9B],
    };

    // ===== Other Unstable Load/Transfer (Unofficial) =====
    table[0xBB] = .{ // LAE/LAS absolute,Y
        .addressing_steps = &addressing.absolute_y_read_steps,
        .execute = unofficial.lae,
        .info = opcodes.OPCODE_TABLE[0xBB],
    };
    table[0x8B] = .{ // XAA/ANE immediate
        .addressing_steps = &[_]MicrostepFn{},
        .execute = unofficial.xaa,
        .info = opcodes.OPCODE_TABLE[0x8B],
    };
    table[0xAB] = .{ // LXA immediate
        .addressing_steps = &[_]MicrostepFn{},
        .execute = unofficial.lxa,
        .info = opcodes.OPCODE_TABLE[0xAB],
    };

    // ===== JAM/KIL Instructions (Unofficial - CPU Halt) =====
    const jam_opcodes = [_]u8{ 0x02, 0x12, 0x22, 0x32, 0x42, 0x52, 0x62, 0x72, 0x92, 0xB2, 0xD2, 0xF2 };
    for (jam_opcodes) |opcode| {
        table[opcode] = .{
            .addressing_steps = &[_]MicrostepFn{},
            .execute = unofficial.jam,
            .info = opcodes.OPCODE_TABLE[opcode],
        };
    }

    // ===== Stack Instructions =====
    table[0x48] = .{ // PHA - Push Accumulator
        .addressing_steps = &[_]MicrostepFn{},
        .execute = stack.pha,
        .info = opcodes.OPCODE_TABLE[0x48],
    };
    table[0x68] = .{ // PLA - Pull Accumulator
        .addressing_steps = &[_]MicrostepFn{},
        .execute = stack.pla,
        .info = opcodes.OPCODE_TABLE[0x68],
    };
    table[0x08] = .{ // PHP - Push Processor Status
        .addressing_steps = &[_]MicrostepFn{},
        .execute = stack.php,
        .info = opcodes.OPCODE_TABLE[0x08],
    };
    table[0x28] = .{ // PLP - Pull Processor Status
        .addressing_steps = &[_]MicrostepFn{},
        .execute = stack.plp,
        .info = opcodes.OPCODE_TABLE[0x28],
    };

    return table;
}

/// Global dispatch table (computed at compile time)
pub const DISPATCH_TABLE: [256]DispatchEntry = blk: {
    break :blk buildDispatchTable();
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "dispatch table - all entries initialized" {
    for (DISPATCH_TABLE, 0..) |entry, i| {
        // Every entry should have valid info
        try testing.expect(entry.info.mnemonic.len > 0);

        // Opcode should match
        const expected_info = opcodes.OPCODE_TABLE[i];
        try testing.expectEqualStrings(expected_info.mnemonic, entry.info.mnemonic);
    }
}

test "dispatch table - NOP immediate has no addressing steps" {
    const entry = DISPATCH_TABLE[0x80]; // Unofficial NOP immediate
    try testing.expect(entry.addressing_steps.len == 0);
    try testing.expectEqualStrings("NOP", entry.info.mnemonic);
}

test "dispatch table - LDA modes" {
    const lda_imm = DISPATCH_TABLE[0xA9];
    try testing.expectEqualStrings("LDA", lda_imm.info.mnemonic);
    try testing.expect(lda_imm.addressing_steps.len == 0); // immediate: no addressing steps

    const lda_zp = DISPATCH_TABLE[0xA5];
    try testing.expectEqualStrings("LDA", lda_zp.info.mnemonic);
    try testing.expect(lda_zp.addressing_steps.len == 1); // zero page

    const lda_abs_x = DISPATCH_TABLE[0xBD];
    try testing.expectEqualStrings("LDA", lda_abs_x.info.mnemonic);
    try testing.expect(lda_abs_x.addressing_steps.len == 3); // absolute,X read
}
