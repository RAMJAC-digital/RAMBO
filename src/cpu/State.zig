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

    /// Pure function: Update zero and negative flags based on value
    /// Returns NEW StatusFlags, does not mutate self
    pub inline fn setZN(self: StatusFlags, value: u8) StatusFlags {
        return StatusFlags{
            .carry = self.carry,
            .zero = (value == 0),
            .interrupt = self.interrupt,
            .decimal = self.decimal,
            .break_flag = self.break_flag,
            .unused = true,
            .overflow = self.overflow,
            .negative = (value & 0x80) != 0,
        };
    }

    /// Pure function: Set carry flag
    pub inline fn setCarry(self: StatusFlags, carry: bool) StatusFlags {
        return StatusFlags{
            .carry = carry,
            .zero = self.zero,
            .interrupt = self.interrupt,
            .decimal = self.decimal,
            .break_flag = self.break_flag,
            .unused = true,
            .overflow = self.overflow,
            .negative = self.negative,
        };
    }

    /// Pure function: Set overflow flag
    pub inline fn setOverflow(self: StatusFlags, overflow: bool) StatusFlags {
        return StatusFlags{
            .carry = self.carry,
            .zero = self.zero,
            .interrupt = self.interrupt,
            .decimal = self.decimal,
            .break_flag = self.break_flag,
            .unused = true,
            .overflow = overflow,
            .negative = self.negative,
        };
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
    /// Interrupt sequence state
    /// Hardware interrupt (NMI/IRQ/RESET) - 7 cycles
    /// Uses instruction_cycle counter (0-6) for progress tracking
    interrupt_sequence,
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

    // ===== Microstep State Machine =====
    // Note: Total cycle count removed - now derived from MasterClock (ppu_cycles / 3)
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

    // ===== Signal Interface =====
    // Input signals (set by coordinator)
    nmi_line: bool = false,         // NMI input (level signal from PPU)
    irq_line: bool = false,         // IRQ input (level signal from APU/mapper)
    rdy_line: bool = true,          // RDY input (level signal from DMA, low = halt)

    // Output signals (computed by CPU, read by coordinator)
    instruction_complete: bool = false,  // Set when instruction finishes (for debugger)
    bus_cycle_complete: bool = false,    // Set each bus cycle (for DMA coordination)
    halted: bool = false,                // CPU halted by JAM/KIL or DMA, only RESET recovers

    // ===== Interrupt State (CPU internal) =====
    pending_interrupt: InterruptType = .none,
    nmi_edge_detected: bool = false, // NMI is edge-triggered
    nmi_enable_prev: bool = false,  // Previous PPUCTRL.NMI_ENABLE for edge detection

    // Hardware "second-to-last cycle" rule: Interrupt lines sampled at END of cycle N,
    // checked at START of cycle N+1. This gives instructions one cycle to complete
    // after register writes (e.g., STA $2000 to enable NMI).
    // Reference: nesdev.org/wiki/CPU_interrupts, Mesen2 NesCpu.cpp:311-314
    nmi_pending_prev: bool = false,  // NMI pending from previous cycle
    irq_pending_prev: bool = false,  // IRQ pending from previous cycle

    // ===== Temporary Storage =====
    temp_value: u8 = 0,             // For RMW operations and other temporary needs
    temp_address: u16 = 0,          // Temporary address storage for indirect modes
};

// ============================================================================
// Pure CPU State for Opcode Functions
// ============================================================================

/// Pure CPU State - 6502 Registers Only
///
/// Minimal immutable state containing ONLY architectural registers.
/// Used by pure opcode functions for computation without side effects.
///
/// Design: NO execution context, NO bus access, NO side effects.
/// Size: ~15 bytes (optimal for frequent copying)
pub const CpuCoreState = struct {
    a: u8 = 0,       // Accumulator
    x: u8 = 0,       // X index register
    y: u8 = 0,       // Y index register
    sp: u8 = 0xFD,   // Stack pointer
    pc: u16 = 0,     // Program counter
    p: StatusFlags = .{}, // Status flags
    effective_address: u16 = 0,  // Computed address (for stores/RMW)
};

// ============================================================================
// Opcode Result - Delta Structure
// ============================================================================

/// Result of executing a pure opcode function
///
/// Describes state changes without performing mutations.
/// The execution engine applies these deltas to the CPU state.
///
/// Design:
/// - All fields optional (null = no change)
/// - Separates computation (opcodes) from coordination (engine)
/// - Enables testability without mocking
/// - Size: ~24 bytes (most fields optimized away)
pub const OpcodeResult = struct {
    // ===== Register Updates (null = unchanged) =====
    a: ?u8 = null,
    x: ?u8 = null,
    y: ?u8 = null,
    sp: ?u8 = null,
    pc: ?u16 = null,

    // ===== Flag Updates (null = unchanged) =====
    flags: ?StatusFlags = null,

    // ===== Bus Operations =====
    bus_write: ?BusWrite = null,

    // ===== Stack Operations =====
    push: ?u8 = null,  // Value to push (engine decrements SP)
    pull: bool = false, // Request pull (engine increments SP, provides value)

    // ===== Special Operations =====
    halt: bool = false, // Halt CPU (JAM/KIL instructions)

    pub const BusWrite = struct {
        address: u16,
        value: u8,
    };
};
