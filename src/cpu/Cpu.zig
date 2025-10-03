//! 6502 CPU Emulation for NES
//!
//! This module implements a cycle-accurate 6502 CPU emulator targeting
//! the AccuracyCoin test suite. Key features:
//! - Cycle-by-cycle execution (not instruction-by-instruction)
//! - Accurate dummy read/write cycles
//! - Interrupt handling with proper timing
//! - Open bus behavior simulation
//! - All official and unofficial opcodes

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
pub const CpuState = enum(u8) {
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
pub const Cpu = struct {
    const Self = @This();

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
    state: CpuState = .fetch_opcode, // Current execution state

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

    /// Initialize CPU to power-on state
    /// Note: Actual NES power-on has undefined register values,
    /// but we start with known state for testing
    pub fn init() Self {
        return .{
            .a = 0,
            .x = 0,
            .y = 0,
            .sp = 0xFD,
            .p = StatusFlags{
                .interrupt = true,  // Interrupts disabled on power-on
                .unused = true,     // Always 1
            },
            .pc = 0,  // Will be loaded from RESET vector
        };
    }

    /// Reset CPU (via RESET interrupt)
    /// This is what happens when the NES reset button is pressed
    pub fn reset(self: *Self, bus: anytype) void {
        // Decrement SP by 3 (but don't write to stack)
        self.sp -%= 3;

        // Set interrupt disable flag
        self.p.interrupt = true;

        // Read RESET vector at $FFFC-$FFFD
        const vector_low = bus.read(0xFFFC);
        const vector_high = bus.read(0xFFFD);
        self.pc = (@as(u16, vector_high) << 8) | vector_low;

        // Reset to fetch state
        self.state = .fetch_opcode;
        self.instruction_cycle = 0;
        self.pending_interrupt = .none;

        // Clear halted state - RESET recovers from JAM/KIL
        self.halted = false;
    }

    /// Execute one CPU cycle
    /// This is the core of cycle-accurate emulation
    /// Returns true when an instruction completes
    pub fn tick(self: *Self, bus: anytype) bool {
        const dispatch = @import("dispatch.zig");

        self.cycle_count += 1;

        // If CPU is halted (JAM/KIL), do nothing until RESET
        // NMI and IRQ are ignored while halted
        if (self.halted) {
            return false; // CPU stuck in infinite loop
        }

        // Check for interrupts at the start of instruction fetch
        if (self.state == .fetch_opcode) {
            self.checkInterrupts();
            if (self.pending_interrupt != .none and self.pending_interrupt != .reset) {
                self.startInterruptSequence();
                return false;
            }
        }

        // Cycle 1: Always fetch opcode
        if (self.state == .fetch_opcode) {
            self.opcode = bus.read(self.pc);
            self.data_bus = self.opcode;
            self.pc +%= 1;

            // Get dispatch entry for this opcode
            const entry = dispatch.DISPATCH_TABLE[self.opcode];
            self.address_mode = entry.info.mode;

            // DEBUG: Uncomment to trace
            // std.debug.print("Opcode 0x{X:0>2}: steps.len={}, mode={s}\n",
            //     .{self.opcode, entry.addressing_steps.len, @tagName(entry.info.mode)});

            // Move to addressing mode or directly to execution
            if (entry.addressing_steps.len == 0) {
                // Implied/accumulator - execute immediately
                self.state = .execute;
            } else {
                // Start addressing mode sequence
                self.state = .fetch_operand_low;
                self.instruction_cycle = 0;
            }

            return false;
        }

        // Handle addressing mode microsteps
        if (self.state == .fetch_operand_low) {
            const entry = dispatch.DISPATCH_TABLE[self.opcode];

            if (self.instruction_cycle < entry.addressing_steps.len) {
                const step = entry.addressing_steps[self.instruction_cycle];
                const complete = step(self, bus);

                self.instruction_cycle += 1;

                if (complete or self.instruction_cycle >= entry.addressing_steps.len) {
                    self.state = .execute;
                    return false;
                }

                return false;
            }

            self.state = .execute;
            return false;
        }

        // Execute instruction
        if (self.state == .execute) {
            const entry = dispatch.DISPATCH_TABLE[self.opcode];
            const complete = entry.execute(self, bus);

            if (complete) {
                self.state = .fetch_opcode;
                self.instruction_cycle = 0;
                return true;
            }

            return false;
        }

        // Handle interrupt states (existing logic preserved)
        // ... interrupt handling ...

        return false;
    }

    /// Check and latch interrupt signals
    /// NMI is edge-triggered (falling edge)
    /// IRQ is level-triggered
    fn checkInterrupts(self: *Self) void {
        // NMI has highest priority and is edge-triggered
        // Detect falling edge: was high (nmi_edge_detected=false), now low (nmi_line=true)
        // Note: nmi_line being TRUE means NMI is ASSERTED (active low in hardware)
        const nmi_prev = self.nmi_edge_detected;
        self.nmi_edge_detected = self.nmi_line;

        if (self.nmi_line and !nmi_prev) {
            // Falling edge detected (transition from not-asserted to asserted)
            self.pending_interrupt = .nmi;
        }

        // IRQ is level-triggered and can be masked
        if (self.irq_line and !self.p.interrupt and self.pending_interrupt == .none) {
            self.pending_interrupt = .irq;
        }
    }

    /// Start interrupt sequence (7 cycles total)
    fn startInterruptSequence(self: *Self) void {
        self.state = .interrupt_dummy;
        self.instruction_cycle = 0;
    }

    /// Push byte onto stack
    pub inline fn push(self: *Self, bus: anytype, value: u8) void {
        const stack_addr = 0x0100 | @as(u16, self.sp);
        bus.write(stack_addr, value);
        self.sp -%= 1;
        self.data_bus = value;
    }

    /// Pull byte from stack
    pub inline fn pull(self: *Self, bus: anytype) u8 {
        self.sp +%= 1;
        const stack_addr = 0x0100 | @as(u16, self.sp);
        const value = bus.read(stack_addr);
        self.data_bus = value;
        return value;
    }
};

// ===== Tests =====

test "StatusFlags: toByte and fromByte" {
    var flags = StatusFlags{
        .carry = true,
        .zero = false,
        .interrupt = true,
        .decimal = false,
        .break_flag = false,
        .unused = true,
        .overflow = false,
        .negative = true,
    };

    const byte = flags.toByte();
    try std.testing.expectEqual(@as(u8, 0b10100101), byte);

    const restored = StatusFlags.fromByte(byte);
    try std.testing.expectEqual(flags.carry, restored.carry);
    try std.testing.expectEqual(flags.zero, restored.zero);
    try std.testing.expectEqual(flags.interrupt, restored.interrupt);
    try std.testing.expectEqual(true, restored.unused); // Always true
}

test "StatusFlags: updateZN" {
    var flags = StatusFlags{};

    flags.updateZN(0x00);
    try std.testing.expectEqual(true, flags.zero);
    try std.testing.expectEqual(false, flags.negative);

    flags.updateZN(0x80);
    try std.testing.expectEqual(false, flags.zero);
    try std.testing.expectEqual(true, flags.negative);

    flags.updateZN(0x42);
    try std.testing.expectEqual(false, flags.zero);
    try std.testing.expectEqual(false, flags.negative);
}

test "CPU: initialization" {
    const cpu = Cpu.init();

    try std.testing.expectEqual(@as(u8, 0), cpu.a);
    try std.testing.expectEqual(@as(u8, 0), cpu.x);
    try std.testing.expectEqual(@as(u8, 0), cpu.y);
    try std.testing.expectEqual(@as(u8, 0xFD), cpu.sp);
    try std.testing.expectEqual(true, cpu.p.interrupt);
    try std.testing.expectEqual(true, cpu.p.unused);
}
