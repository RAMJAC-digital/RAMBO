//! CPU Logic
//!
//! This module contains pure helper functions for CPU operations.
//! All side effects (state mutations, bus I/O) happen in EmulationState.

const std = @import("std");
const StateModule = @import("State.zig");
const CpuState = StateModule.CpuState;
const StatusFlags = StateModule.StatusFlags;
const ExecutionState = StateModule.ExecutionState;
const InterruptType = StateModule.InterruptType;
const OpcodeResult = StateModule.OpcodeResult;
const CpuCoreState = StateModule.CpuCoreState;

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
            .interrupt = true, // Interrupts disabled on power-on
            .unused = true, // Always 1
        },
        .pc = 0, // Will be loaded from RESET vector
    };
}

/// Convert full CPU state to core CPU state (6502 registers + effective address)
///
/// Pure opcode functions operate on immutable 6502 state plus addressing context.
/// This extracts the architectural registers and computed effective address.
pub fn toCoreState(state: *const CpuState) CpuCoreState {
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

// Note: extractOperandValue and applyOpcodeResult are now inlined in EmulationState.tickCpu()
// This eliminates circular dependency and keeps all side effects in EmulationState

/// Check and latch interrupt signals
/// NMI is edge-triggered (falling edge)
/// IRQ is level-triggered
///
/// Hardware behavior verified against Mesen2 NesCpu.cpp:306-309:
/// - Simple edge detection: if(!_prevNmiFlag && _state.NmiFlag) { _needNmi = true; }
/// - NO VBlank-based suppression - multiple NMIs allowed per VBlank
/// - Toggling PPUCTRL.7 during VBlank causes multiple NMIs (AccuracyCoin test 7)
///
/// Hardware "second-to-last cycle" rule: Interrupt lines sampled at END of cycle N,
/// checked at START of cycle N+1. CPU manages this sampling internally.
/// Reference: nesdev.org/wiki/CPU_interrupts, Mesen2 NesCpu.cpp:311-314
pub fn checkInterrupts(state: *CpuState) void {
    // NMI has highest priority and is edge-triggered
    // Detect falling edge: was high (nmi_edge_detected=false), now low (nmi_line=true)
    // Note: nmi_line being TRUE means NMI is ASSERTED (active low in hardware)
    const nmi_prev = state.nmi_edge_detected;
    state.nmi_edge_detected = state.nmi_line;

    if (state.nmi_line and !nmi_prev) {
        // Falling edge detected (transition from not-asserted to asserted)
        // Hardware allows multiple NMIs during same VBlank if PPUCTRL.7 is toggled
        state.pending_interrupt = .nmi;
    }

    // IRQ is level-triggered and can be masked
    if (state.irq_line and !state.p.interrupt and state.pending_interrupt == .none) {
        state.pending_interrupt = .irq;
    }

    // Sample interrupt states for next cycle (second-to-last cycle rule)
    // This allows instructions one cycle to complete after register writes
    state.nmi_pending_prev = (state.pending_interrupt == .nmi);
    state.irq_pending_prev = (state.pending_interrupt == .irq);
}

/// Start interrupt sequence (7 cycles total)
/// Sets CPU state to begin hardware interrupt handling
/// Called when pending_interrupt is set (NMI/IRQ/RESET)
pub fn startInterruptSequence(state: *CpuState) void {
    state.state = .interrupt_sequence;
    state.instruction_cycle = 0;
}

// Note: push() and pull() are now handled by microsteps in EmulationState
// Stack operations have direct bus access via EmulationState.busRead/busWrite
