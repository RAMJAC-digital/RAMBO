//! 6502 Opcode Definitions and Decode Table
//!
//! This module contains:
//! - Complete opcode decode table (all 256 opcodes)
//! - Instruction metadata (addressing mode, cycles, etc.)
//! - Both official and unofficial opcodes
//!
//! Reference: https://www.nesdev.org/wiki/CPU_unofficial_opcodes
//! AccuracyCoin tests all opcodes including unofficial ones

const std = @import("std");
const AddressingMode = @import("Cpu.zig").AddressingMode;

/// Opcode metadata for instruction decoding
pub const OpcodeInfo = struct {
    /// Instruction mnemonic for debugging
    mnemonic: []const u8,

    /// Addressing mode
    mode: AddressingMode,

    /// Base cycle count (additional cycles may be added for page crosses)
    cycles: u8,

    /// Does this instruction add a cycle on page boundary crossing?
    page_cross_cycle: bool = false,

    /// Is this an unofficial/illegal opcode?
    unofficial: bool = false,
};

/// Complete 6502 opcode decode table (256 entries)
/// Indexed by opcode value (0x00-0xFF)
pub const OPCODE_TABLE = blk: {
    @setEvalBranchQuota(10000);
    var table: [256]OpcodeInfo = undefined;

    // Initialize all as invalid/NOPs first
    for (&table, 0..) |*entry, i| {
        entry.* = OpcodeInfo{
            .mnemonic = "???",
            .mode = .implied,
            .cycles = 2,
            .unofficial = true,
        };
        _ = i;
    }

    // ===== Official Opcodes =====

    // ADC - Add with Carry
    table[0x69] = .{ .mnemonic = "ADC", .mode = .immediate, .cycles = 2 };
    table[0x65] = .{ .mnemonic = "ADC", .mode = .zero_page, .cycles = 3 };
    table[0x75] = .{ .mnemonic = "ADC", .mode = .zero_page_x, .cycles = 4 };
    table[0x6D] = .{ .mnemonic = "ADC", .mode = .absolute, .cycles = 4 };
    table[0x7D] = .{ .mnemonic = "ADC", .mode = .absolute_x, .cycles = 4, .page_cross_cycle = true };
    table[0x79] = .{ .mnemonic = "ADC", .mode = .absolute_y, .cycles = 4, .page_cross_cycle = true };
    table[0x61] = .{ .mnemonic = "ADC", .mode = .indexed_indirect, .cycles = 6 };
    table[0x71] = .{ .mnemonic = "ADC", .mode = .indirect_indexed, .cycles = 5, .page_cross_cycle = true };

    // AND - Logical AND
    table[0x29] = .{ .mnemonic = "AND", .mode = .immediate, .cycles = 2 };
    table[0x25] = .{ .mnemonic = "AND", .mode = .zero_page, .cycles = 3 };
    table[0x35] = .{ .mnemonic = "AND", .mode = .zero_page_x, .cycles = 4 };
    table[0x2D] = .{ .mnemonic = "AND", .mode = .absolute, .cycles = 4 };
    table[0x3D] = .{ .mnemonic = "AND", .mode = .absolute_x, .cycles = 4, .page_cross_cycle = true };
    table[0x39] = .{ .mnemonic = "AND", .mode = .absolute_y, .cycles = 4, .page_cross_cycle = true };
    table[0x21] = .{ .mnemonic = "AND", .mode = .indexed_indirect, .cycles = 6 };
    table[0x31] = .{ .mnemonic = "AND", .mode = .indirect_indexed, .cycles = 5, .page_cross_cycle = true };

    // ASL - Arithmetic Shift Left
    table[0x0A] = .{ .mnemonic = "ASL", .mode = .accumulator, .cycles = 2 };
    table[0x06] = .{ .mnemonic = "ASL", .mode = .zero_page, .cycles = 5 };
    table[0x16] = .{ .mnemonic = "ASL", .mode = .zero_page_x, .cycles = 6 };
    table[0x0E] = .{ .mnemonic = "ASL", .mode = .absolute, .cycles = 6 };
    table[0x1E] = .{ .mnemonic = "ASL", .mode = .absolute_x, .cycles = 7 };

    // Branch Instructions (all relative addressing)
    table[0x90] = .{ .mnemonic = "BCC", .mode = .relative, .cycles = 2 }; // Branch if Carry Clear
    table[0xB0] = .{ .mnemonic = "BCS", .mode = .relative, .cycles = 2 }; // Branch if Carry Set
    table[0xF0] = .{ .mnemonic = "BEQ", .mode = .relative, .cycles = 2 }; // Branch if Equal
    table[0x30] = .{ .mnemonic = "BMI", .mode = .relative, .cycles = 2 }; // Branch if Minus
    table[0xD0] = .{ .mnemonic = "BNE", .mode = .relative, .cycles = 2 }; // Branch if Not Equal
    table[0x10] = .{ .mnemonic = "BPL", .mode = .relative, .cycles = 2 }; // Branch if Plus
    table[0x50] = .{ .mnemonic = "BVC", .mode = .relative, .cycles = 2 }; // Branch if Overflow Clear
    table[0x70] = .{ .mnemonic = "BVS", .mode = .relative, .cycles = 2 }; // Branch if Overflow Set

    // BIT - Bit Test
    table[0x24] = .{ .mnemonic = "BIT", .mode = .zero_page, .cycles = 3 };
    table[0x2C] = .{ .mnemonic = "BIT", .mode = .absolute, .cycles = 4 };

    // BRK - Force Interrupt
    table[0x00] = .{ .mnemonic = "BRK", .mode = .implied, .cycles = 7 };

    // CMP - Compare
    table[0xC9] = .{ .mnemonic = "CMP", .mode = .immediate, .cycles = 2 };
    table[0xC5] = .{ .mnemonic = "CMP", .mode = .zero_page, .cycles = 3 };
    table[0xD5] = .{ .mnemonic = "CMP", .mode = .zero_page_x, .cycles = 4 };
    table[0xCD] = .{ .mnemonic = "CMP", .mode = .absolute, .cycles = 4 };
    table[0xDD] = .{ .mnemonic = "CMP", .mode = .absolute_x, .cycles = 4, .page_cross_cycle = true };
    table[0xD9] = .{ .mnemonic = "CMP", .mode = .absolute_y, .cycles = 4, .page_cross_cycle = true };
    table[0xC1] = .{ .mnemonic = "CMP", .mode = .indexed_indirect, .cycles = 6 };
    table[0xD1] = .{ .mnemonic = "CMP", .mode = .indirect_indexed, .cycles = 5, .page_cross_cycle = true };

    // CPX - Compare X Register
    table[0xE0] = .{ .mnemonic = "CPX", .mode = .immediate, .cycles = 2 };
    table[0xE4] = .{ .mnemonic = "CPX", .mode = .zero_page, .cycles = 3 };
    table[0xEC] = .{ .mnemonic = "CPX", .mode = .absolute, .cycles = 4 };

    // CPY - Compare Y Register
    table[0xC0] = .{ .mnemonic = "CPY", .mode = .immediate, .cycles = 2 };
    table[0xC4] = .{ .mnemonic = "CPY", .mode = .zero_page, .cycles = 3 };
    table[0xCC] = .{ .mnemonic = "CPY", .mode = .absolute, .cycles = 4 };

    // DEC - Decrement Memory
    table[0xC6] = .{ .mnemonic = "DEC", .mode = .zero_page, .cycles = 5 };
    table[0xD6] = .{ .mnemonic = "DEC", .mode = .zero_page_x, .cycles = 6 };
    table[0xCE] = .{ .mnemonic = "DEC", .mode = .absolute, .cycles = 6 };
    table[0xDE] = .{ .mnemonic = "DEC", .mode = .absolute_x, .cycles = 7 };

    // EOR - Exclusive OR
    table[0x49] = .{ .mnemonic = "EOR", .mode = .immediate, .cycles = 2 };
    table[0x45] = .{ .mnemonic = "EOR", .mode = .zero_page, .cycles = 3 };
    table[0x55] = .{ .mnemonic = "EOR", .mode = .zero_page_x, .cycles = 4 };
    table[0x4D] = .{ .mnemonic = "EOR", .mode = .absolute, .cycles = 4 };
    table[0x5D] = .{ .mnemonic = "EOR", .mode = .absolute_x, .cycles = 4, .page_cross_cycle = true };
    table[0x59] = .{ .mnemonic = "EOR", .mode = .absolute_y, .cycles = 4, .page_cross_cycle = true };
    table[0x41] = .{ .mnemonic = "EOR", .mode = .indexed_indirect, .cycles = 6 };
    table[0x51] = .{ .mnemonic = "EOR", .mode = .indirect_indexed, .cycles = 5, .page_cross_cycle = true };

    // Flag Instructions
    table[0x18] = .{ .mnemonic = "CLC", .mode = .implied, .cycles = 2 }; // Clear Carry
    table[0x38] = .{ .mnemonic = "SEC", .mode = .implied, .cycles = 2 }; // Set Carry
    table[0x58] = .{ .mnemonic = "CLI", .mode = .implied, .cycles = 2 }; // Clear Interrupt
    table[0x78] = .{ .mnemonic = "SEI", .mode = .implied, .cycles = 2 }; // Set Interrupt
    table[0xB8] = .{ .mnemonic = "CLV", .mode = .implied, .cycles = 2 }; // Clear Overflow
    table[0xD8] = .{ .mnemonic = "CLD", .mode = .implied, .cycles = 2 }; // Clear Decimal
    table[0xF8] = .{ .mnemonic = "SED", .mode = .implied, .cycles = 2 }; // Set Decimal

    // INC - Increment Memory
    table[0xE6] = .{ .mnemonic = "INC", .mode = .zero_page, .cycles = 5 };
    table[0xF6] = .{ .mnemonic = "INC", .mode = .zero_page_x, .cycles = 6 };
    table[0xEE] = .{ .mnemonic = "INC", .mode = .absolute, .cycles = 6 };
    table[0xFE] = .{ .mnemonic = "INC", .mode = .absolute_x, .cycles = 7 };

    // JMP - Jump
    table[0x4C] = .{ .mnemonic = "JMP", .mode = .absolute, .cycles = 3 };
    table[0x6C] = .{ .mnemonic = "JMP", .mode = .indirect, .cycles = 5 };

    // JSR - Jump to Subroutine
    table[0x20] = .{ .mnemonic = "JSR", .mode = .absolute, .cycles = 6 };

    // LDA - Load Accumulator
    table[0xA9] = .{ .mnemonic = "LDA", .mode = .immediate, .cycles = 2 };
    table[0xA5] = .{ .mnemonic = "LDA", .mode = .zero_page, .cycles = 3 };
    table[0xB5] = .{ .mnemonic = "LDA", .mode = .zero_page_x, .cycles = 4 };
    table[0xAD] = .{ .mnemonic = "LDA", .mode = .absolute, .cycles = 4 };
    table[0xBD] = .{ .mnemonic = "LDA", .mode = .absolute_x, .cycles = 4, .page_cross_cycle = true };
    table[0xB9] = .{ .mnemonic = "LDA", .mode = .absolute_y, .cycles = 4, .page_cross_cycle = true };
    table[0xA1] = .{ .mnemonic = "LDA", .mode = .indexed_indirect, .cycles = 6 };
    table[0xB1] = .{ .mnemonic = "LDA", .mode = .indirect_indexed, .cycles = 5, .page_cross_cycle = true };

    // LDX - Load X Register
    table[0xA2] = .{ .mnemonic = "LDX", .mode = .immediate, .cycles = 2 };
    table[0xA6] = .{ .mnemonic = "LDX", .mode = .zero_page, .cycles = 3 };
    table[0xB6] = .{ .mnemonic = "LDX", .mode = .zero_page_y, .cycles = 4 };
    table[0xAE] = .{ .mnemonic = "LDX", .mode = .absolute, .cycles = 4 };
    table[0xBE] = .{ .mnemonic = "LDX", .mode = .absolute_y, .cycles = 4, .page_cross_cycle = true };

    // LDY - Load Y Register
    table[0xA0] = .{ .mnemonic = "LDY", .mode = .immediate, .cycles = 2 };
    table[0xA4] = .{ .mnemonic = "LDY", .mode = .zero_page, .cycles = 3 };
    table[0xB4] = .{ .mnemonic = "LDY", .mode = .zero_page_x, .cycles = 4 };
    table[0xAC] = .{ .mnemonic = "LDY", .mode = .absolute, .cycles = 4 };
    table[0xBC] = .{ .mnemonic = "LDY", .mode = .absolute_x, .cycles = 4, .page_cross_cycle = true };

    // LSR - Logical Shift Right
    table[0x4A] = .{ .mnemonic = "LSR", .mode = .accumulator, .cycles = 2 };
    table[0x46] = .{ .mnemonic = "LSR", .mode = .zero_page, .cycles = 5 };
    table[0x56] = .{ .mnemonic = "LSR", .mode = .zero_page_x, .cycles = 6 };
    table[0x4E] = .{ .mnemonic = "LSR", .mode = .absolute, .cycles = 6 };
    table[0x5E] = .{ .mnemonic = "LSR", .mode = .absolute_x, .cycles = 7 };

    // NOP - No Operation
    table[0xEA] = .{ .mnemonic = "NOP", .mode = .implied, .cycles = 2 };

    // ORA - Logical OR
    table[0x09] = .{ .mnemonic = "ORA", .mode = .immediate, .cycles = 2 };
    table[0x05] = .{ .mnemonic = "ORA", .mode = .zero_page, .cycles = 3 };
    table[0x15] = .{ .mnemonic = "ORA", .mode = .zero_page_x, .cycles = 4 };
    table[0x0D] = .{ .mnemonic = "ORA", .mode = .absolute, .cycles = 4 };
    table[0x1D] = .{ .mnemonic = "ORA", .mode = .absolute_x, .cycles = 4, .page_cross_cycle = true };
    table[0x19] = .{ .mnemonic = "ORA", .mode = .absolute_y, .cycles = 4, .page_cross_cycle = true };
    table[0x01] = .{ .mnemonic = "ORA", .mode = .indexed_indirect, .cycles = 6 };
    table[0x11] = .{ .mnemonic = "ORA", .mode = .indirect_indexed, .cycles = 5, .page_cross_cycle = true };

    // Register Instructions
    table[0xAA] = .{ .mnemonic = "TAX", .mode = .implied, .cycles = 2 }; // Transfer A to X
    table[0x8A] = .{ .mnemonic = "TXA", .mode = .implied, .cycles = 2 }; // Transfer X to A
    table[0xCA] = .{ .mnemonic = "DEX", .mode = .implied, .cycles = 2 }; // Decrement X
    table[0xE8] = .{ .mnemonic = "INX", .mode = .implied, .cycles = 2 }; // Increment X
    table[0xA8] = .{ .mnemonic = "TAY", .mode = .implied, .cycles = 2 }; // Transfer A to Y
    table[0x98] = .{ .mnemonic = "TYA", .mode = .implied, .cycles = 2 }; // Transfer Y to A
    table[0x88] = .{ .mnemonic = "DEY", .mode = .implied, .cycles = 2 }; // Decrement Y
    table[0xC8] = .{ .mnemonic = "INY", .mode = .implied, .cycles = 2 }; // Increment Y

    // ROL - Rotate Left
    table[0x2A] = .{ .mnemonic = "ROL", .mode = .accumulator, .cycles = 2 };
    table[0x26] = .{ .mnemonic = "ROL", .mode = .zero_page, .cycles = 5 };
    table[0x36] = .{ .mnemonic = "ROL", .mode = .zero_page_x, .cycles = 6 };
    table[0x2E] = .{ .mnemonic = "ROL", .mode = .absolute, .cycles = 6 };
    table[0x3E] = .{ .mnemonic = "ROL", .mode = .absolute_x, .cycles = 7 };

    // ROR - Rotate Right
    table[0x6A] = .{ .mnemonic = "ROR", .mode = .accumulator, .cycles = 2 };
    table[0x66] = .{ .mnemonic = "ROR", .mode = .zero_page, .cycles = 5 };
    table[0x76] = .{ .mnemonic = "ROR", .mode = .zero_page_x, .cycles = 6 };
    table[0x6E] = .{ .mnemonic = "ROR", .mode = .absolute, .cycles = 6 };
    table[0x7E] = .{ .mnemonic = "ROR", .mode = .absolute_x, .cycles = 7 };

    // RTI - Return from Interrupt
    table[0x40] = .{ .mnemonic = "RTI", .mode = .implied, .cycles = 6 };

    // RTS - Return from Subroutine
    table[0x60] = .{ .mnemonic = "RTS", .mode = .implied, .cycles = 6 };

    // SBC - Subtract with Carry
    table[0xE9] = .{ .mnemonic = "SBC", .mode = .immediate, .cycles = 2 };
    table[0xE5] = .{ .mnemonic = "SBC", .mode = .zero_page, .cycles = 3 };
    table[0xF5] = .{ .mnemonic = "SBC", .mode = .zero_page_x, .cycles = 4 };
    table[0xED] = .{ .mnemonic = "SBC", .mode = .absolute, .cycles = 4 };
    table[0xFD] = .{ .mnemonic = "SBC", .mode = .absolute_x, .cycles = 4, .page_cross_cycle = true };
    table[0xF9] = .{ .mnemonic = "SBC", .mode = .absolute_y, .cycles = 4, .page_cross_cycle = true };
    table[0xE1] = .{ .mnemonic = "SBC", .mode = .indexed_indirect, .cycles = 6 };
    table[0xF1] = .{ .mnemonic = "SBC", .mode = .indirect_indexed, .cycles = 5, .page_cross_cycle = true };

    // STA - Store Accumulator
    table[0x85] = .{ .mnemonic = "STA", .mode = .zero_page, .cycles = 3 };
    table[0x95] = .{ .mnemonic = "STA", .mode = .zero_page_x, .cycles = 4 };
    table[0x8D] = .{ .mnemonic = "STA", .mode = .absolute, .cycles = 4 };
    table[0x9D] = .{ .mnemonic = "STA", .mode = .absolute_x, .cycles = 5 };
    table[0x99] = .{ .mnemonic = "STA", .mode = .absolute_y, .cycles = 5 };
    table[0x81] = .{ .mnemonic = "STA", .mode = .indexed_indirect, .cycles = 6 };
    table[0x91] = .{ .mnemonic = "STA", .mode = .indirect_indexed, .cycles = 6 };

    // Stack Instructions
    table[0x9A] = .{ .mnemonic = "TXS", .mode = .implied, .cycles = 2 }; // Transfer X to Stack Pointer
    table[0xBA] = .{ .mnemonic = "TSX", .mode = .implied, .cycles = 2 }; // Transfer Stack Pointer to X
    table[0x48] = .{ .mnemonic = "PHA", .mode = .implied, .cycles = 3 }; // Push Accumulator
    table[0x68] = .{ .mnemonic = "PLA", .mode = .implied, .cycles = 4 }; // Pull Accumulator
    table[0x08] = .{ .mnemonic = "PHP", .mode = .implied, .cycles = 3 }; // Push Processor Status
    table[0x28] = .{ .mnemonic = "PLP", .mode = .implied, .cycles = 4 }; // Pull Processor Status

    // STX - Store X Register
    table[0x86] = .{ .mnemonic = "STX", .mode = .zero_page, .cycles = 3 };
    table[0x96] = .{ .mnemonic = "STX", .mode = .zero_page_y, .cycles = 4 };
    table[0x8E] = .{ .mnemonic = "STX", .mode = .absolute, .cycles = 4 };

    // STY - Store Y Register
    table[0x84] = .{ .mnemonic = "STY", .mode = .zero_page, .cycles = 3 };
    table[0x94] = .{ .mnemonic = "STY", .mode = .zero_page_x, .cycles = 4 };
    table[0x8C] = .{ .mnemonic = "STY", .mode = .absolute, .cycles = 4 };

    // ===== Unofficial/Illegal Opcodes =====
    // These are critical for AccuracyCoin!

    // SLO - ASL + ORA (unofficial)
    table[0x07] = .{ .mnemonic = "SLO", .mode = .zero_page, .cycles = 5, .unofficial = true };
    table[0x17] = .{ .mnemonic = "SLO", .mode = .zero_page_x, .cycles = 6, .unofficial = true };
    table[0x0F] = .{ .mnemonic = "SLO", .mode = .absolute, .cycles = 6, .unofficial = true };
    table[0x1F] = .{ .mnemonic = "SLO", .mode = .absolute_x, .cycles = 7, .unofficial = true };
    table[0x1B] = .{ .mnemonic = "SLO", .mode = .absolute_y, .cycles = 7, .unofficial = true };
    table[0x03] = .{ .mnemonic = "SLO", .mode = .indexed_indirect, .cycles = 8, .unofficial = true };
    table[0x13] = .{ .mnemonic = "SLO", .mode = .indirect_indexed, .cycles = 8, .unofficial = true };

    // RLA - ROL + AND (unofficial)
    table[0x27] = .{ .mnemonic = "RLA", .mode = .zero_page, .cycles = 5, .unofficial = true };
    table[0x37] = .{ .mnemonic = "RLA", .mode = .zero_page_x, .cycles = 6, .unofficial = true };
    table[0x2F] = .{ .mnemonic = "RLA", .mode = .absolute, .cycles = 6, .unofficial = true };
    table[0x3F] = .{ .mnemonic = "RLA", .mode = .absolute_x, .cycles = 7, .unofficial = true };
    table[0x3B] = .{ .mnemonic = "RLA", .mode = .absolute_y, .cycles = 7, .unofficial = true };
    table[0x23] = .{ .mnemonic = "RLA", .mode = .indexed_indirect, .cycles = 8, .unofficial = true };
    table[0x33] = .{ .mnemonic = "RLA", .mode = .indirect_indexed, .cycles = 8, .unofficial = true };

    // SRE - LSR + EOR (unofficial)
    table[0x47] = .{ .mnemonic = "SRE", .mode = .zero_page, .cycles = 5, .unofficial = true };
    table[0x57] = .{ .mnemonic = "SRE", .mode = .zero_page_x, .cycles = 6, .unofficial = true };
    table[0x4F] = .{ .mnemonic = "SRE", .mode = .absolute, .cycles = 6, .unofficial = true };
    table[0x5F] = .{ .mnemonic = "SRE", .mode = .absolute_x, .cycles = 7, .unofficial = true };
    table[0x5B] = .{ .mnemonic = "SRE", .mode = .absolute_y, .cycles = 7, .unofficial = true };
    table[0x43] = .{ .mnemonic = "SRE", .mode = .indexed_indirect, .cycles = 8, .unofficial = true };
    table[0x53] = .{ .mnemonic = "SRE", .mode = .indirect_indexed, .cycles = 8, .unofficial = true };

    // RRA - ROR + ADC (unofficial)
    table[0x67] = .{ .mnemonic = "RRA", .mode = .zero_page, .cycles = 5, .unofficial = true };
    table[0x77] = .{ .mnemonic = "RRA", .mode = .zero_page_x, .cycles = 6, .unofficial = true };
    table[0x6F] = .{ .mnemonic = "RRA", .mode = .absolute, .cycles = 6, .unofficial = true };
    table[0x7F] = .{ .mnemonic = "RRA", .mode = .absolute_x, .cycles = 7, .unofficial = true };
    table[0x7B] = .{ .mnemonic = "RRA", .mode = .absolute_y, .cycles = 7, .unofficial = true };
    table[0x63] = .{ .mnemonic = "RRA", .mode = .indexed_indirect, .cycles = 8, .unofficial = true };
    table[0x73] = .{ .mnemonic = "RRA", .mode = .indirect_indexed, .cycles = 8, .unofficial = true };

    // SAX - STA & STX (unofficial)
    table[0x87] = .{ .mnemonic = "SAX", .mode = .zero_page, .cycles = 3, .unofficial = true };
    table[0x97] = .{ .mnemonic = "SAX", .mode = .zero_page_y, .cycles = 4, .unofficial = true };
    table[0x8F] = .{ .mnemonic = "SAX", .mode = .absolute, .cycles = 4, .unofficial = true };
    table[0x83] = .{ .mnemonic = "SAX", .mode = .indexed_indirect, .cycles = 6, .unofficial = true };

    // LAX - LDA + LDX (unofficial)
    table[0xA7] = .{ .mnemonic = "LAX", .mode = .zero_page, .cycles = 3, .unofficial = true };
    table[0xB7] = .{ .mnemonic = "LAX", .mode = .zero_page_y, .cycles = 4, .unofficial = true };
    table[0xAF] = .{ .mnemonic = "LAX", .mode = .absolute, .cycles = 4, .unofficial = true };
    table[0xBF] = .{ .mnemonic = "LAX", .mode = .absolute_y, .cycles = 4, .page_cross_cycle = true, .unofficial = true };
    table[0xA3] = .{ .mnemonic = "LAX", .mode = .indexed_indirect, .cycles = 6, .unofficial = true };
    table[0xB3] = .{ .mnemonic = "LAX", .mode = .indirect_indexed, .cycles = 5, .page_cross_cycle = true, .unofficial = true };

    // DCP - DEC + CMP (unofficial)
    table[0xC7] = .{ .mnemonic = "DCP", .mode = .zero_page, .cycles = 5, .unofficial = true };
    table[0xD7] = .{ .mnemonic = "DCP", .mode = .zero_page_x, .cycles = 6, .unofficial = true };
    table[0xCF] = .{ .mnemonic = "DCP", .mode = .absolute, .cycles = 6, .unofficial = true };
    table[0xDF] = .{ .mnemonic = "DCP", .mode = .absolute_x, .cycles = 7, .unofficial = true };
    table[0xDB] = .{ .mnemonic = "DCP", .mode = .absolute_y, .cycles = 7, .unofficial = true };
    table[0xC3] = .{ .mnemonic = "DCP", .mode = .indexed_indirect, .cycles = 8, .unofficial = true };
    table[0xD3] = .{ .mnemonic = "DCP", .mode = .indirect_indexed, .cycles = 8, .unofficial = true };

    // ISC - INC + SBC (unofficial)
    table[0xE7] = .{ .mnemonic = "ISC", .mode = .zero_page, .cycles = 5, .unofficial = true };
    table[0xF7] = .{ .mnemonic = "ISC", .mode = .zero_page_x, .cycles = 6, .unofficial = true };
    table[0xEF] = .{ .mnemonic = "ISC", .mode = .absolute, .cycles = 6, .unofficial = true };
    table[0xFF] = .{ .mnemonic = "ISC", .mode = .absolute_x, .cycles = 7, .unofficial = true };
    table[0xFB] = .{ .mnemonic = "ISC", .mode = .absolute_y, .cycles = 7, .unofficial = true };
    table[0xE3] = .{ .mnemonic = "ISC", .mode = .indexed_indirect, .cycles = 8, .unofficial = true };
    table[0xF3] = .{ .mnemonic = "ISC", .mode = .indirect_indexed, .cycles = 8, .unofficial = true };

    // ANC - AND + set carry (unofficial)
    table[0x0B] = .{ .mnemonic = "ANC", .mode = .immediate, .cycles = 2, .unofficial = true };
    table[0x2B] = .{ .mnemonic = "ANC", .mode = .immediate, .cycles = 2, .unofficial = true };

    // ALR/ASR - AND + LSR (unofficial)
    table[0x4B] = .{ .mnemonic = "ALR", .mode = .immediate, .cycles = 2, .unofficial = true };

    // ARR - AND + ROR (unofficial)
    table[0x6B] = .{ .mnemonic = "ARR", .mode = .immediate, .cycles = 2, .unofficial = true };

    // XAA/ANE - unstable (unofficial)
    table[0x8B] = .{ .mnemonic = "XAA", .mode = .immediate, .cycles = 2, .unofficial = true };

    // LXA - unstable (unofficial)
    table[0xAB] = .{ .mnemonic = "LXA", .mode = .immediate, .cycles = 2, .unofficial = true };

    // AXS/SBX - (A & X) - operand (unofficial)
    table[0xCB] = .{ .mnemonic = "AXS", .mode = .immediate, .cycles = 2, .unofficial = true };

    // SBC - duplicate (unofficial)
    table[0xEB] = .{ .mnemonic = "SBC", .mode = .immediate, .cycles = 2, .unofficial = true };

    // SHA/AHX - A & X & H (unofficial, unstable)
    table[0x9F] = .{ .mnemonic = "SHA", .mode = .absolute_y, .cycles = 5, .unofficial = true };
    table[0x93] = .{ .mnemonic = "SHA", .mode = .indirect_indexed, .cycles = 6, .unofficial = true };

    // SHX - X & H (unofficial, unstable)
    table[0x9E] = .{ .mnemonic = "SHX", .mode = .absolute_y, .cycles = 5, .unofficial = true };

    // SHY - Y & H (unofficial, unstable)
    table[0x9C] = .{ .mnemonic = "SHY", .mode = .absolute_x, .cycles = 5, .unofficial = true };

    // TAS/SHS - A & X -> SP, A & X & H -> M (unofficial, unstable)
    table[0x9B] = .{ .mnemonic = "TAS", .mode = .absolute_y, .cycles = 5, .unofficial = true };

    // LAE/LAS - M & SP -> A, X, SP (unofficial)
    table[0xBB] = .{ .mnemonic = "LAE", .mode = .absolute_y, .cycles = 4, .page_cross_cycle = true, .unofficial = true };

    // NOP variants (unofficial - different addressing modes)
    table[0x1A] = .{ .mnemonic = "NOP", .mode = .implied, .cycles = 2, .unofficial = true };
    table[0x3A] = .{ .mnemonic = "NOP", .mode = .implied, .cycles = 2, .unofficial = true };
    table[0x5A] = .{ .mnemonic = "NOP", .mode = .implied, .cycles = 2, .unofficial = true };
    table[0x7A] = .{ .mnemonic = "NOP", .mode = .implied, .cycles = 2, .unofficial = true };
    table[0xDA] = .{ .mnemonic = "NOP", .mode = .implied, .cycles = 2, .unofficial = true };
    table[0xFA] = .{ .mnemonic = "NOP", .mode = .implied, .cycles = 2, .unofficial = true };

    // DOP - Double NOP (2-byte NOP, unofficial)
    table[0x04] = .{ .mnemonic = "NOP", .mode = .zero_page, .cycles = 3, .unofficial = true };
    table[0x14] = .{ .mnemonic = "NOP", .mode = .zero_page_x, .cycles = 4, .unofficial = true };
    table[0x34] = .{ .mnemonic = "NOP", .mode = .zero_page_x, .cycles = 4, .unofficial = true };
    table[0x44] = .{ .mnemonic = "NOP", .mode = .zero_page, .cycles = 3, .unofficial = true };
    table[0x54] = .{ .mnemonic = "NOP", .mode = .zero_page_x, .cycles = 4, .unofficial = true };
    table[0x64] = .{ .mnemonic = "NOP", .mode = .zero_page, .cycles = 3, .unofficial = true };
    table[0x74] = .{ .mnemonic = "NOP", .mode = .zero_page_x, .cycles = 4, .unofficial = true };
    table[0x80] = .{ .mnemonic = "NOP", .mode = .immediate, .cycles = 2, .unofficial = true };
    table[0x82] = .{ .mnemonic = "NOP", .mode = .immediate, .cycles = 2, .unofficial = true };
    table[0x89] = .{ .mnemonic = "NOP", .mode = .immediate, .cycles = 2, .unofficial = true };
    table[0xC2] = .{ .mnemonic = "NOP", .mode = .immediate, .cycles = 2, .unofficial = true };
    table[0xD4] = .{ .mnemonic = "NOP", .mode = .zero_page_x, .cycles = 4, .unofficial = true };
    table[0xE2] = .{ .mnemonic = "NOP", .mode = .immediate, .cycles = 2, .unofficial = true };
    table[0xF4] = .{ .mnemonic = "NOP", .mode = .zero_page_x, .cycles = 4, .unofficial = true };

    // TOP - Triple NOP (3-byte NOP, unofficial)
    table[0x0C] = .{ .mnemonic = "NOP", .mode = .absolute, .cycles = 4, .unofficial = true };
    table[0x1C] = .{ .mnemonic = "NOP", .mode = .absolute_x, .cycles = 4, .page_cross_cycle = true, .unofficial = true };
    table[0x3C] = .{ .mnemonic = "NOP", .mode = .absolute_x, .cycles = 4, .page_cross_cycle = true, .unofficial = true };
    table[0x5C] = .{ .mnemonic = "NOP", .mode = .absolute_x, .cycles = 4, .page_cross_cycle = true, .unofficial = true };
    table[0x7C] = .{ .mnemonic = "NOP", .mode = .absolute_x, .cycles = 4, .page_cross_cycle = true, .unofficial = true };
    table[0xDC] = .{ .mnemonic = "NOP", .mode = .absolute_x, .cycles = 4, .page_cross_cycle = true, .unofficial = true };
    table[0xFC] = .{ .mnemonic = "NOP", .mode = .absolute_x, .cycles = 4, .page_cross_cycle = true, .unofficial = true };

    // JAM/KIL - Halt the CPU (unofficial)
    table[0x02] = .{ .mnemonic = "JAM", .mode = .implied, .cycles = 0, .unofficial = true };
    table[0x12] = .{ .mnemonic = "JAM", .mode = .implied, .cycles = 0, .unofficial = true };
    table[0x22] = .{ .mnemonic = "JAM", .mode = .implied, .cycles = 0, .unofficial = true };
    table[0x32] = .{ .mnemonic = "JAM", .mode = .implied, .cycles = 0, .unofficial = true };
    table[0x42] = .{ .mnemonic = "JAM", .mode = .implied, .cycles = 0, .unofficial = true };
    table[0x52] = .{ .mnemonic = "JAM", .mode = .implied, .cycles = 0, .unofficial = true };
    table[0x62] = .{ .mnemonic = "JAM", .mode = .implied, .cycles = 0, .unofficial = true };
    table[0x72] = .{ .mnemonic = "JAM", .mode = .implied, .cycles = 0, .unofficial = true };
    table[0x92] = .{ .mnemonic = "JAM", .mode = .implied, .cycles = 0, .unofficial = true };
    table[0xB2] = .{ .mnemonic = "JAM", .mode = .implied, .cycles = 0, .unofficial = true };
    table[0xD2] = .{ .mnemonic = "JAM", .mode = .implied, .cycles = 0, .unofficial = true };
    table[0xF2] = .{ .mnemonic = "JAM", .mode = .implied, .cycles = 0, .unofficial = true };

    break :blk table;
};

// ===== Tests =====

test "opcodes: official opcodes are marked correctly" {
    try std.testing.expect(!OPCODE_TABLE[0xEA].unofficial); // NOP
    try std.testing.expect(!OPCODE_TABLE[0xA9].unofficial); // LDA imm
    try std.testing.expect(!OPCODE_TABLE[0x00].unofficial); // BRK
}

test "opcodes: unofficial opcodes are marked correctly" {
    try std.testing.expect(OPCODE_TABLE[0x0F].unofficial); // SLO abs
    try std.testing.expect(OPCODE_TABLE[0x04].unofficial); // NOP zp
    try std.testing.expect(OPCODE_TABLE[0x8B].unofficial); // XAA imm
}

test "opcodes: LDA addressing modes" {
    try std.testing.expectEqual(AddressingMode.immediate, OPCODE_TABLE[0xA9].mode);
    try std.testing.expectEqual(AddressingMode.zero_page, OPCODE_TABLE[0xA5].mode);
    try std.testing.expectEqual(AddressingMode.absolute, OPCODE_TABLE[0xAD].mode);
    try std.testing.expectEqual(AddressingMode.absolute_x, OPCODE_TABLE[0xBD].mode);
}

test "opcodes: cycle counts" {
    try std.testing.expectEqual(@as(u8, 2), OPCODE_TABLE[0xA9].cycles); // LDA imm
    try std.testing.expectEqual(@as(u8, 3), OPCODE_TABLE[0xA5].cycles); // LDA zp
    try std.testing.expectEqual(@as(u8, 4), OPCODE_TABLE[0xAD].cycles); // LDA abs
    try std.testing.expectEqual(@as(u8, 7), OPCODE_TABLE[0x00].cycles); // BRK
}

test "opcodes: page crossing" {
    try std.testing.expect(OPCODE_TABLE[0xBD].page_cross_cycle); // LDA abs,X
    try std.testing.expect(!OPCODE_TABLE[0x9D].page_cross_cycle); // STA abs,X (writes don't save cycle)
}
