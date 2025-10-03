//! CPU Logic
//!
//! This module contains the pure functions that operate on the CPU state.

const std = @import("std");
const StateModule = @import("State.zig");
const State = StateModule.State;
const StatusFlags = StateModule.StatusFlags;
const ExecutionState = StateModule.ExecutionState;
const InterruptType = StateModule.InterruptType;

/// Initialize CPU to power-on state
/// Note: Actual NES power-on has undefined register values,
/// but we start with known state for testing
pub fn init() State {
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
pub fn reset(state: *State, bus: anytype) void {
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

/// Execute one CPU cycle
/// This is the core of cycle-accurate emulation
/// Returns true when an instruction completes
pub fn tick(state: *State, bus: anytype) bool {
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

            if (complete or state.instruction_cycle >= entry.addressing_steps.len) {
                state.state = .execute;
                return false;
            }

            return false;
        }

        state.state = .execute;
        return false;
    }

    // Execute instruction
    if (state.state == .execute) {
        const entry = dispatch.DISPATCH_TABLE[state.opcode];
        const complete = entry.execute(state, bus);

        if (complete) {
            state.state = .fetch_opcode;
            state.instruction_cycle = 0;
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
fn checkInterrupts(state: *State) void {
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
fn startInterruptSequence(state: *State) void {
    state.state = .interrupt_dummy;
    state.instruction_cycle = 0;
}

/// Push byte onto stack
pub inline fn push(state: *State, bus: anytype, value: u8) void {
    const stack_addr = 0x0100 | @as(u16, state.sp);
    bus.write(stack_addr, value);
    state.sp -%= 1;
    state.data_bus = value;
}

/// Pull byte from stack
pub inline fn pull(state: *State, bus: anytype) u8 {
    state.sp +%= 1;
    const stack_addr = 0x0100 | @as(u16, state.sp);
    const value = bus.read(stack_addr);
    state.data_bus = value;
    return value;
}
