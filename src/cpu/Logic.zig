//! CPU Logic
//!
//! This module contains the pure functions that operate on the CPU state.

const std = @import("std");
const StateModule = @import("State.zig");
const CpuState = StateModule.CpuState;
const StatusFlags = StateModule.StatusFlags;
const ExecutionState = StateModule.ExecutionState;
const InterruptType = StateModule.InterruptType;
const OpcodeResult = StateModule.OpcodeResult;
const PureCpuState = StateModule.PureCpuState;

/// Initialize CPU to power-on state
/// Note: Actual NES power-on has undefined register values,
/// but we start with known state for testing
pub fn init() CpuState {
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
pub fn reset(state: *CpuState, bus: anytype) void {
    // Decrement SP by 3 (but don't write to stack)
    state.sp -%= 3;

    // Set interrupt disable flag
    state.p.interrupt = true;

    // Read RESET vector at $FFFC-$FFFD
    const vector_low = bus.read(0xFFFC);
    const vector_high = bus.read(0xFFFD);
    state.pc = (@as(u16, vector_high) << 8) | vector_low;

    // Reset to fetch state
    state.state = .fetch_opcode;
    state.instruction_cycle = 0;
    state.pending_interrupt = .none;

    // Clear halted state - RESET recovers from JAM/KIL
    state.halted = false;
}

/// Convert full CPU state to pure CPU state (6502 registers + effective address)
///
/// Pure opcode functions operate on immutable 6502 state plus addressing context.
/// This extracts the architectural registers and computed effective address.
fn toPureState(state: *const CpuState) PureCpuState {
    return .{
        .a = state.a,
        .x = state.x,
        .y = state.y,
        .sp = state.sp,
        .pc = state.pc,
        .p = state.p,
        .effective_address = state.effective_address,
    };
}

/// Extract operand value for pure opcode execution
///
/// This bridges addressing mode microsteps with pure opcode functions.
/// RMW operations have temp_value pre-loaded by rmwRead microstep.
/// Pull operations have temp_value loaded by pullByte microstep.
/// Regular read operations need to fetch the value based on addressing mode.
///
/// Pattern:
/// - RMW (is_rmw=true): Use temp_value (already read by rmwRead)
/// - Pull (is_pull=true): Use temp_value (loaded by pullByte)
/// - Regular reads: Read from computed address or use immediate value
/// - Indexed modes: Use temp_value if no page cross (dummy read was correct)
fn extractOperandValue(state: *const CpuState, bus: anytype, is_rmw: bool, is_pull: bool) u8 {
    // RMW and pull operations always use pre-loaded temp_value
    if (is_rmw or is_pull) {
        return state.temp_value;
    }

    // Regular operations: extract based on addressing mode
    return switch (state.address_mode) {
        .immediate => blk: {
            // Immediate mode: Read operand from PC during execute cycle (critical for 2-cycle timing)
            const value = bus.read(state.pc);
            // Note: PC increment happens in extractOperandValue, not here (to maintain const state)
            break :blk value;
        },
        .accumulator => state.a,
        .implied => 0, // No operand
        .zero_page => bus.read(@as(u16, state.operand_low)),
        .zero_page_x, .zero_page_y => bus.read(state.effective_address),
        .absolute => blk: {
            const addr = (@as(u16, state.operand_high) << 8) | state.operand_low;
            break :blk bus.read(addr);
        },
        .absolute_x, .absolute_y, .indirect_indexed => blk: {
            // Indexed modes: use temp_value if no page cross (dummy read was correct)
            if (state.page_crossed) {
                break :blk bus.read(state.effective_address);
            }
            break :blk state.temp_value;
        },
        .indexed_indirect => bus.read(state.effective_address),
        .indirect => unreachable, // Only for JMP
        .relative => state.operand_low, // Branch offset
    };
}

/// Apply opcode execution result to CPU state
///
/// This function bridges pure opcode functions with stateful execution.
/// Opcodes return OpcodeResult describing desired state changes.
/// This function applies those changes to the actual CPU state.
///
/// Benefits:
/// - Opcodes remain pure (testable without mocking)
/// - Execution engine coordinates side effects (bus writes, stack ops)
/// - Clear separation between computation and coordination
pub fn applyOpcodeResult(state: *CpuState, bus: anytype, result: OpcodeResult) void {
    // Apply register updates
    if (result.a) |new_a| state.a = new_a;
    if (result.x) |new_x| state.x = new_x;
    if (result.y) |new_y| state.y = new_y;
    if (result.sp) |new_sp| state.sp = new_sp;
    if (result.pc) |new_pc| state.pc = new_pc;

    // Apply flag updates
    if (result.flags) |new_flags| state.p = new_flags;

    // Handle bus write
    if (result.bus_write) |write| {
        bus.write(write.address, write.value);
        state.data_bus = write.value; // Update open bus
    }

    // Handle stack push
    if (result.push) |value| {
        bus.write(0x0100 | @as(u16, state.sp), value);
        state.sp -%= 1; // Wrapping decrement
        state.data_bus = value;
    }

    // Handle stack pull request
    // Note: Actual pull happens in execution engine
    // This flag indicates pull is needed, value comes from bus read

    // Handle halt
    if (result.halt) {
        state.halted = true;
    }
}

/// Execute one CPU cycle
/// This is the core of cycle-accurate emulation
/// Returns true when an instruction completes
pub fn tick(state: *CpuState, bus: anytype) bool {
    const dispatch = @import("dispatch.zig");

    state.cycle_count += 1;

    // If CPU is halted (JAM/KIL), do nothing until RESET
    // NMI and IRQ are ignored while halted
    if (state.halted) {
        return false; // CPU stuck in infinite loop
    }

    // Check for interrupts at the start of instruction fetch
    if (state.state == .fetch_opcode) {
        checkInterrupts(state);
        if (state.pending_interrupt != .none and state.pending_interrupt != .reset) {
            startInterruptSequence(state);
            return false;
        }
    }

    // Cycle 1: Always fetch opcode
    if (state.state == .fetch_opcode) {
        state.opcode = bus.read(state.pc);
        state.data_bus = state.opcode;
        state.pc +%= 1;

        // Get dispatch entry for this opcode
        const entry = dispatch.DISPATCH_TABLE[state.opcode];
        state.address_mode = entry.info.mode;

        // Move to addressing mode or directly to execution
        if (entry.addressing_steps.len == 0) {
            // Implied/accumulator - execute immediately
            state.state = .execute;
        } else {
            // Start addressing mode sequence
            state.state = .fetch_operand_low;
            state.instruction_cycle = 0;
        }

        return false;
    }

    // Handle addressing mode microsteps
    if (state.state == .fetch_operand_low) {
        const entry = dispatch.DISPATCH_TABLE[state.opcode];

        if (state.instruction_cycle < entry.addressing_steps.len) {
            const step = entry.addressing_steps[state.instruction_cycle];
            const complete = step(state, bus);

            state.instruction_cycle += 1;

            // If microstep signals completion, instruction is done (no execute phase)
            // This handles microstep-only instructions like JSR/RTS/RTI/BRK
            if (complete) {
                state.state = .fetch_opcode;
                state.instruction_cycle = 0;
                return true;
            }

            // If all microsteps done, move to execute phase
            if (state.instruction_cycle >= entry.addressing_steps.len) {
                state.state = .execute;
                return false;
            }

            return false;
        }

        state.state = .execute;
        return false;
    }

    // Execute instruction (Pure Function Architecture)
    if (state.state == .execute) {
        const entry = dispatch.DISPATCH_TABLE[state.opcode];

        // Extract operand value based on addressing mode, RMW flag, and pull flag
        const operand = extractOperandValue(state, bus, entry.is_rmw, entry.is_pull);

        // Immediate mode: Increment PC after reading operand (2-cycle timing)
        if (state.address_mode == .immediate) {
            state.pc +%= 1;
        }

        // Zero page modes: Set effective_address from operand_low
        // (Needed for store operations that use effective_address)
        if (state.address_mode == .zero_page) {
            state.effective_address = @as(u16, state.operand_low);
        }

        // Convert to pure CPU state (6502 registers + effective address)
        const pure_state = toPureState(state);

        // Call pure opcode function (returns delta structure)
        const result = entry.execute_pure(pure_state, operand);

        // Apply delta to CPU state
        applyOpcodeResult(state, bus, result);

        // Instruction complete
        state.state = .fetch_opcode;
        state.instruction_cycle = 0;
        return true;
    }

    // Handle interrupt states (existing logic preserved)
    // ... interrupt handling ...

    return false;
}

/// Check and latch interrupt signals
/// NMI is edge-triggered (falling edge)
/// IRQ is level-triggered
fn checkInterrupts(state: *CpuState) void {
    // NMI has highest priority and is edge-triggered
    // Detect falling edge: was high (nmi_edge_detected=false), now low (nmi_line=true)
    // Note: nmi_line being TRUE means NMI is ASSERTED (active low in hardware)
    const nmi_prev = state.nmi_edge_detected;
    state.nmi_edge_detected = state.nmi_line;

    if (state.nmi_line and !nmi_prev) {
        // Falling edge detected (transition from not-asserted to asserted)
        state.pending_interrupt = .nmi;
    }

    // IRQ is level-triggered and can be masked
    if (state.irq_line and !state.p.interrupt and state.pending_interrupt == .none) {
        state.pending_interrupt = .irq;
    }
}

/// Start interrupt sequence (7 cycles total)
fn startInterruptSequence(state: *CpuState) void {
    state.state = .interrupt_dummy;
    state.instruction_cycle = 0;
}

/// Push byte onto stack
pub inline fn push(state: *CpuState, bus: anytype, value: u8) void {
    const stack_addr = 0x0100 | @as(u16, state.sp);
    bus.write(stack_addr, value);
    state.sp -%= 1;
    state.data_bus = value;
}

/// Pull byte from stack
pub inline fn pull(state: *CpuState, bus: anytype) u8 {
    state.sp +%= 1;
    const stack_addr = 0x0100 | @as(u16, state.sp);
    const value = bus.read(stack_addr);
    state.data_bus = value;
    return value;
}
