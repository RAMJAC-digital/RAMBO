//! CPU State
//!
//! This module defines the pure data structures for the CPU state.

const std = @import("std");

/// 6502 Status Register (P register) flags
/// Using packed struct for exact bit layout matching hardware
pub const StatusFlags = packed struct(u8) {
    carry: bool = false,        // C: Bit 0 - Carry flag
    zero: bool = false,         // Z: Bit 1 - Zero flag
    interrupt: bool = false,    // I: Bit 2 - Interrupt disable
    decimal: bool = false,      // D: Bit 3 - Decimal mode (not used on NES, but tracked)
    break_flag: bool = false,   // B: Bit 4 - Software interrupt (BRK/PHP)
    unused: bool = true,        // -: Bit 5 - Always 1
    overflow: bool = false,     // V: Bit 6 - Overflow flag
    negative: bool = false,     // N: Bit 7 - Negative flag

    /// Convert flags to byte for stack operations
    pub inline fn toByte(self: StatusFlags) u8 {
        return @bitCast(self);
    }

    /// Create flags from byte (for pulling from stack)
    pub inline fn fromByte(byte: u8) StatusFlags {
        var flags: StatusFlags = @bitCast(byte);
        flags.unused = true; // Ensure bit 5 always reads as 1
        return flags;
    }

    /// Update zero and negative flags based on value
    pub inline fn updateZN(self: *StatusFlags, value: u8) void {
        self.zero = (value == 0);
        self.negative = (value & 0x80) != 0;
    }
};

/// Addressing modes for 6502 instructions
pub const AddressingMode = enum(u8) {
    implied,          // No operand (e.g., NOP, CLC)
    accumulator,      // Operates on accumulator (e.g., ASL A)
    immediate,        // Immediate value (e.g., LDA #$10)
    zero_page,        // Zero page address (e.g., LDA $10)
    zero_page_x,      // Zero page indexed with X (e.g., LDA $10,X)
    zero_page_y,      // Zero page indexed with Y (e.g., LDX $10,Y)
    absolute,         // Absolute address (e.g., LDA $1234)
    absolute_x,       // Absolute indexed with X (e.g., LDA $1234,X)
    absolute_y,       // Absolute indexed with Y (e.g., LDA $1234,Y)
    indirect,         // Indirect (JMP only) (e.g., JMP ($1234))
    indexed_indirect, // Indexed indirect (Indirect,X) (e.g., LDA ($10,X))
    indirect_indexed, // Indirect indexed (Indirect),Y (e.g., LDA ($10),Y)
    relative,         // Relative (branches) (e.g., BNE label)
};

/// CPU execution state for cycle-accurate emulation
/// Each instruction is broken down into multiple states
pub const ExecutionState = enum(u8) {
    /// Fetching opcode from PC
    fetch_opcode,
    /// Fetching operand bytes
    fetch_operand_low,
    fetch_operand_high,
    /// Address calculation with potential dummy reads
    calc_address_low,
    calc_address_high,
    /// Dummy read cycle (critical for hardware accuracy)
    dummy_read,
    /// Dummy write cycle (for RMW instructions)
    dummy_write,
    /// Actual operation execution
    execute,
    /// Write result back to memory
    write_result,
    /// Stack operations
    push_high,
    push_low,
    pull,
    /// Interrupt handling states
    interrupt_dummy,
    interrupt_push_pch,
    interrupt_push_pcl,
    interrupt_push_p,
    interrupt_vector_low,
    interrupt_vector_high,
    /// Branch taken additional cycles
    branch_taken,
    branch_page_cross,
};

/// Interrupt type for tracking active interrupt
pub const InterruptType = enum(u8) {
    none,
    nmi,
    irq,
    reset,
    brk, // Software interrupt
};

/// Complete 6502 CPU state
pub const CpuState = struct {
    // ===== Registers =====
    a: u8 = 0,      // Accumulator
    x: u8 = 0,      // X index register
    y: u8 = 0,      // Y index register
    sp: u8 = 0xFD,  // Stack pointer (starts at 0xFD after reset)
    pc: u16 = 0,    // Program counter
    p: StatusFlags = .{}, // Status flags

    // ===== Cycle Tracking =====
    cycle_count: u64 = 0,           // Total cycles since power-on
    instruction_cycle: u8 = 0,      // Current cycle within instruction
    state: ExecutionState = .fetch_opcode, // Current execution state

    // ===== Current Instruction Context =====
    opcode: u8 = 0,
    operand_low: u8 = 0,
    operand_high: u8 = 0,
    effective_address: u16 = 0,
    address_mode: AddressingMode = .implied,
    page_crossed: bool = false,     // Track page boundary crossings

    // ===== Open Bus Simulation =====
    // The data bus retains the last value read - critical for accuracy
    data_bus: u8 = 0,

    // ===== Interrupt State =====
    pending_interrupt: InterruptType = .none,
    nmi_line: bool = false,         // NMI input (level)
    nmi_edge_detected: bool = false, // NMI is edge-triggered
    irq_line: bool = false,         // IRQ input (level-triggered)

    // ===== CPU Halt State (for JAM/KIL unofficial opcodes) =====
    halted: bool = false,           // CPU halted by JAM/KIL, only RESET recovers

    // ===== Temporary Storage =====
    temp_value: u8 = 0,             // For RMW operations and other temporary needs
    temp_address: u16 = 0,          // Temporary address storage for indirect modes
};
