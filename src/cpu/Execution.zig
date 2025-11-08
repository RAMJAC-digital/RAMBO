//! CPU execution logic for cycle-accurate 6502 emulation
//!
//! 4-state machine:
//! 1. `.interrupt_sequence` - Hardware interrupt handling (NMI/IRQ/RESET, 7 cycles)
//! 2. `.fetch_opcode` - Fetch next instruction opcode (1 cycle)
//! 3. `.fetch_operand_low` - Addressing mode microsteps (0-7 cycles, table-driven)
//! 4. `.execute` - Instruction execution (1 cycle)
//!
//! Phase 6 Refactor (2025-11-07):
//! - Table-driven microstep dispatch (replaced 217 lines of switches)
//! - Single source of truth for addressing modes (MicrostepTable)
//! - Eliminated duplication across 3 dispatch sites

const std = @import("std");
const CpuModule = @import("Cpu.zig");
const CpuState = CpuModule.State.CpuState;
const CpuLogic = CpuModule.Logic;
const CpuMicrosteps = @import("Microsteps.zig");
const MicrostepTable = @import("MicrostepTable.zig");
const DebuggerModule = @import("../debugger/Debugger.zig");
const Debugger = DebuggerModule.Debugger;

/// Execute one CPU cycle
/// Parameters:
///   - cpu: CPU state (modified in-place)
///   - bus: Bus interface (must have busRead/busWrite methods)
///   - debugger: Optional debugger for breakpoint/watchpoint checks
pub fn stepCycle(cpu: *CpuState, bus: anytype, debugger: ?*Debugger) void {
    // Clear output signals at start of cycle
    cpu.instruction_complete = false;
    cpu.bus_cycle_complete = false;

    // Check RDY line (DMA halt signal)
    // Hardware: RDY line pulled low halts CPU until DMA completes
    if (!cpu.rdy_line) {
        cpu.halted = true;
        return;
    }
    cpu.halted = false;

    executeCycle(cpu, bus, debugger);
}

/// Execute CPU micro-operations for the current cycle
fn executeCycle(cpu: *CpuState, bus: anytype, debugger: ?*Debugger) void {
    // Restore interrupt state from previous cycle (hardware "second-to-last cycle" rule)
    // Reference: nesdev.org/wiki/CPU_interrupts
    if (cpu.state != .interrupt_sequence) {
        if (cpu.nmi_pending_prev) {
            cpu.pending_interrupt = .nmi;
        } else if (cpu.irq_pending_prev and !cpu.p.interrupt) {
            cpu.pending_interrupt = .irq;
        }
    }

    if (cpu.state == .fetch_opcode) {
        if (cpu.pending_interrupt != .none and cpu.pending_interrupt != .reset) {
            bus.dummyRead(cpu.pc);

            cpu.nmi_pending_prev = false;
            cpu.irq_pending_prev = false;

            cpu.state = .interrupt_sequence;
            cpu.instruction_cycle = 1;
            return;
        }

        if (debugger) |dbg| {
            if (dbg.shouldBreak(bus) catch false) {
                bus.debug_break_occurred = true;
                return;
            }
        }
    }

    if (cpu.state == .interrupt_sequence) {
        const complete = switch (cpu.instruction_cycle) {
            1 => CpuMicrosteps.pushPch(bus),
            2 => CpuMicrosteps.pushPcl(bus),
            3 => CpuMicrosteps.pushStatusInterrupt(bus),
            4 => blk: {
                cpu.operand_low = switch (cpu.pending_interrupt) {
                    .nmi => bus.busRead(0xFFFA),
                    .irq => bus.busRead(0xFFFE),
                    .reset => bus.busRead(0xFFFC),
                    else => unreachable,
                };
                cpu.p.interrupt = true;
                break :blk false;
            },
            5 => blk: {
                cpu.operand_high = switch (cpu.pending_interrupt) {
                    .nmi => bus.busRead(0xFFFB),
                    .irq => bus.busRead(0xFFFF),
                    .reset => bus.busRead(0xFFFD),
                    else => unreachable,
                };
                break :blk false;
            },
            6 => blk: {
                cpu.pc = (@as(u16, cpu.operand_high) << 8) |
                    @as(u16, cpu.operand_low);

                cpu.pending_interrupt = .none;

                break :blk true;
            },
            else => unreachable,
        };

        if (complete) {
            cpu.state = .fetch_opcode;
            cpu.instruction_cycle = 0;
            cpu.instruction_complete = true;
        } else {
            cpu.instruction_cycle += 1;
        }
        return;
    }

    if (cpu.state == .fetch_opcode) {
        cpu.opcode = bus.busRead(cpu.pc);
        cpu.data_bus = cpu.opcode;
        cpu.pc +%= 1;

        const entry = CpuModule.dispatch.DISPATCH_TABLE[cpu.opcode];
        cpu.address_mode = entry.info.mode;

        // Determine if addressing phase is needed (table-driven)
        const sequence = MicrostepTable.MICROSTEP_TABLE[cpu.opcode];
        const needs_addressing = (sequence.max_cycles > 0);

        if (needs_addressing) {
            cpu.state = .fetch_operand_low;
            cpu.instruction_cycle = 0;
        } else {
            cpu.state = .execute;
        }
        return;
    }

    // ================================================================
    // Addressing Mode Microsteps (Table-Driven Dispatch)
    // ================================================================
    // Phase 6 refactor: Replaced 217 lines of nested switches with
    // single table lookup. All 256 opcodes have microstep sequences
    // defined in MicrostepTable.MICROSTEP_TABLE.
    //
    // Early Completion Pattern:
    // Some microsteps return true to signal early completion before max_cycles:
    // - Branch not taken: 2 cycles (vs 3-4 max)
    // - Branch taken, no page cross: 3 cycles (vs 4 max)
    // This preserves hardware-accurate variable cycle counts.
    // ================================================================
    if (cpu.state == .fetch_operand_low) {
        const sequence = MicrostepTable.MICROSTEP_TABLE[cpu.opcode];

        // Execute current microstep from table
        if (cpu.instruction_cycle < sequence.steps.len) {
            const microstep_idx = sequence.steps[cpu.instruction_cycle];
            const early_complete = MicrostepTable.callMicrostep(microstep_idx, bus);
            if (early_complete) {
                // Microstep signaled early completion
                // Two types:
                // 1. Control flow (branches, JSR/RTS/RTI) - instruction fully done, go to fetch_opcode
                // 2. Addressing (no page cross on reads) - addressing done, go to execute
                const is_control_flow = (cpu.address_mode == .relative) or (sequence.operand_source == .none);

                if (is_control_flow) {
                    cpu.state = .fetch_opcode;
                    cpu.instruction_complete = true;
                } else {
                    cpu.state = .execute;
                }
                cpu.instruction_cycle = 0;
                return;
            }
        }

        cpu.instruction_cycle += 1;

        // Check if addressing is complete
        const addressing_done = (cpu.instruction_cycle >= sequence.max_cycles);

        if (addressing_done) {
            cpu.state = .execute;

            // Fallthrough optimization: absolute_x/y/indirect_indexed reads
            // complete addressing and execute in same iteration (no page cross)
            const dispatch_entry = CpuModule.dispatch.DISPATCH_TABLE[cpu.opcode];
            const should_fallthrough = !dispatch_entry.is_rmw and
                (cpu.address_mode == .absolute_x or
                cpu.address_mode == .absolute_y or
                cpu.address_mode == .indirect_indexed);

            if (!should_fallthrough) {
                return;
            }
        } else {
            return;
        }
    }

    // ================================================================
    // Instruction Execution
    // ================================================================
    if (cpu.state == .execute) {
        const entry = CpuModule.dispatch.DISPATCH_TABLE[cpu.opcode];
        const sequence = MicrostepTable.MICROSTEP_TABLE[cpu.opcode];

        // Fetch operand value based on operand_source from table
        const operand = switch (sequence.operand_source) {
            .none => 0,
            .immediate_pc => blk: {
                const val = bus.busRead(cpu.pc);
                cpu.pc +%= 1;
                break :blk val;
            },
            .temp_value => cpu.temp_value,
            .operand_low => bus.busRead(@as(u16, cpu.operand_low)),
            .effective_addr => bus.busRead(cpu.effective_address),
            .operand_hl => blk: {
                const addr = (@as(u16, cpu.operand_high) << 8) | cpu.operand_low;
                break :blk bus.busRead(addr);
            },
            .accumulator => cpu.a,
        };

        // Set effective_address for zero_page and absolute modes (needed by some operations)
        // Skip if already set by RMW addressing microsteps (would overwrite indexed address)
        if (!entry.is_rmw) {
            switch (cpu.address_mode) {
                .zero_page => {
                    cpu.effective_address = @as(u16, cpu.operand_low);
                },
                .absolute => {
                    cpu.effective_address = (@as(u16, cpu.operand_high) << 8) | @as(u16, cpu.operand_low);
                },
                else => {},
            }
        }

        // Execute pure opcode function
        const core_state = CpuLogic.toCoreState(cpu);
        const result = entry.operation(core_state, operand);

        // Apply register updates from pure function
        if (result.a) |new_a| cpu.a = new_a;
        if (result.x) |new_x| cpu.x = new_x;
        if (result.y) |new_y| cpu.y = new_y;
        if (result.sp) |new_sp| cpu.sp = new_sp;
        if (result.pc) |new_pc| cpu.pc = new_pc;
        if (result.flags) |new_flags| cpu.p = new_flags;

        // Apply bus write if requested
        if (result.bus_write) |write| {
            bus.busWrite(write.address, write.value);
            cpu.data_bus = write.value;
        }

        // Apply stack push if requested
        if (result.push) |value| {
            const stack_addr = 0x0100 | @as(u16, cpu.sp);
            bus.busWrite(stack_addr, value);
            cpu.sp -%= 1;
            cpu.data_bus = value;
        }

        // Apply halt if requested (JAM/KIL instructions)
        if (result.halt) {
            cpu.halted = true;
        }

        cpu.state = .fetch_opcode;
        cpu.instruction_cycle = 0;
        cpu.instruction_complete = true;
    }

    // Every cycle completes a bus operation (read or write)
    cpu.bus_cycle_complete = true;
}
