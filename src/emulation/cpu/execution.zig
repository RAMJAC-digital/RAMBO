//! CPU execution logic for cycle-accurate 6502 emulation
//!
//! This module contains the core CPU execution functions extracted from EmulationState.
//! These functions implement the 6502 state machine with cycle-accurate timing.
//!
//! ## Architecture
//!
//! The CPU execution follows a 4-state machine:
//! 1. `.interrupt_sequence` - Hardware interrupt handling (NMI/IRQ/RESET, 7 cycles)
//! 2. `.fetch_opcode` - Fetch next instruction opcode (1 cycle)
//! 3. `.fetch_operand_low` - Addressing mode microsteps (1-8 cycles)
//! 4. `.execute` - Instruction execution (1 cycle)
//!
//! ## Side Effects
//!
//! All side effects flow explicitly through the state parameter:
//! - `state.busRead()` - Memory reads with PPU/APU/debugger/cartridge side effects
//! - `state.busWrite()` - Memory writes with PPU/APU/debugger/cartridge side effects
//! - `state.cpu.*` - Direct CPU state mutations (registers, flags, state machine)
//! - `state.ppu.*` - PPU state mutations (warmup flag)
//! - `state.debugger.*` - Debugger state checks (breakpoints, watchpoints)
//!
//! ## Timing Critical Behavior
//!
//! **CRITICAL:** All busRead/busWrite calls must maintain exact ordering for hardware accuracy:
//! - Dummy reads at specific addresses (dummy_addr calculations)
//! - Read-Modify-Write sequences (read, dummy write original, write modified)
//! - Interrupt vector fetches
//! - Stack operations
//!
//! **Known Timing Deviation (+1 cycle):**
//! Absolute,X/Y and Indirect,Y reads without page crossing have +1 cycle deviation:
//! - Hardware: 4 cycles (dummy read IS the actual read)
//! - Implementation: 5 cycles (separate addressing + execute states)
//! - Documented in CLAUDE.md:89-95
//! - Mitigated by fallthrough logic (lines 1115-1135 in original)
//! - Impact: Functionally correct, timing slightly off
//! - Priority: MEDIUM (defer to post-playability)
//!
//! ## Memory Ownership
//!
//! - Uses `anytype` parameter for duck typing with EmulationState
//! - All access through state.* field syntax (no pointer extraction)
//! - Single ownership guarantee through state parameter
//! - Zero aliasing - no subcomponent pointers passed around
//! - RT-safe - no heap allocations during execution
//!
//! ## Functions
//!
//! - `stepCycle()` - Entry point for one CPU cycle (checks DMA, calls executeCycle)
//! - `executeCycle()` - Execute one CPU micro-operation (state machine dispatcher)
//!
//! These functions use `pub fn` (NOT inline) for proper side effect isolation.

const std = @import("std");
const CpuModule = @import("../../cpu/Cpu.zig");
const CpuLogic = CpuModule.Logic;
const CpuMicrosteps = @import("microsteps.zig");
const CycleResults = @import("../state/CycleResults.zig");
const CpuCycleResult = CycleResults.CpuCycleResult;
// DMA interaction logic is now inline (functional pattern)

/// Execute one CPU cycle with DMA and debugger checks.
/// Entry point called from EmulationState.tick() via stepCpuCycle wrapper.
///
/// Handles:
/// - PPU warmup period completion (29,658 CPU cycles)
/// - NMI line synchronization (queries VBlankLedger - single source of truth)
/// - CPU halted state (JAM/KIL opcodes)
/// - Debugger breakpoint/watchpoint checks
/// - DMC DMA stall cycles (RDY line low)
/// - OAM DMA active cycles (CPU frozen)
/// - Normal CPU execution via executeCycle()
/// - Mapper IRQ counter tick
///
/// Returns: CpuCycleResult with mapper_irq flag
pub fn stepCycle(state: anytype) CpuCycleResult {
    // Check PPU warm-up period completion (29,658 CPU cycles)
    // Hardware: PPU ignores writes to $2000/$2001/$2005/$2006 during warmup
    // Reference: nesdev.org/wiki/PPU_power_up_state
    if (!state.ppu.warmup_complete and state.clock.cpuCycles() >= 29658) {
        state.ppu.warmup_complete = true;

        // Apply buffered $2001 write if ROM wrote to it during warmup
        // Hardware: ROMs often write to PPUMASK before warmup completes
        // We buffer the last write and apply it here
        if (state.ppu.warmup_ppumask_buffer) |buffered_value| {
            state.ppu.mask = @import("../../ppu/State.zig").PpuMask.fromByte(buffered_value);
            state.ppu.warmup_ppumask_buffer = null;
        }
    }

    // NMI line reflects VBlank flag state (when NMI enabled in PPUCTRL)
    // Hardware: NMI line stays asserted as long as:
    // 1. VBlank is active (last_set > last_clear)
    // 2. NMI is enabled in PPUCTRL
    // 3. Not in race condition suppression
    //
    // Edge detection in checkInterrupts() handles latching pending_interrupt.
    // NMI fires ONCE per VBlank because:
    // - After pending_interrupt = .nmi, checkInterrupts() stops checking
    // - pending_interrupt cleared when interrupt sequence completes
    // - VBlank flag cleared by $2002 read or scanline 261 dot 1
    // - Double-trigger suppression via nmi_vblank_set_cycle tracking
    const vblank_flag_visible = state.vblank_ledger.isFlagVisible();
    const nmi_line_should_assert = vblank_flag_visible and
        state.ppu.ctrl.nmi_enable and
        !state.vblank_ledger.hasRace();

    state.cpu.nmi_line = nmi_line_should_assert;

    // Track current VBlank set cycle for double-trigger suppression
    // Pass this to checkInterrupts() to prevent multiple NMIs during same VBlank
    const vblank_active = state.vblank_ledger.isActive();
    const current_vblank_set_cycle = if (vblank_active)
        state.vblank_ledger.last_set_cycle
    else
        0;

    // If CPU is halted (JAM/KIL), do nothing until RESET
    if (state.cpu.halted) {
        return .{};
    }

    // Check debugger breakpoints/watchpoints (RT-safe, zero allocations)
    if (state.debuggerShouldHalt()) {
        return .{};
    }

    // DMC completion handling (external state management pattern)
    // DMC logic clears rdy_low itself; we just need to update timestamps
    if (state.dmc_dma.transfer_complete) {
        // Clear signal and record timestamp atomically
        // Pattern follows NMI/VBlank: timestamp updated when state changes
        state.dmc_dma.transfer_complete = false;
        state.dma_interaction_ledger.last_dmc_inactive_cycle = state.clock.ppu_cycles;

        // If OAM was paused, mark it as resumed and set alignment flag
        const was_paused = state.dma_interaction_ledger.oam_pause_cycle >
            state.dma_interaction_ledger.oam_resume_cycle;
        if (was_paused and state.dma.active) {
            state.dma_interaction_ledger.oam_resume_cycle = state.clock.ppu_cycles;
            state.dma_interaction_ledger.needs_alignment_after_dmc = true;
        }
    }

    // DMC edge detection for rising edge (DMC becoming active)
    const dmc_was_active = (state.dma_interaction_ledger.last_dmc_active_cycle >
        state.dma_interaction_ledger.last_dmc_inactive_cycle);
    const dmc_is_active = state.dmc_dma.rdy_low;

    if (dmc_is_active and !dmc_was_active) {
        state.dma_interaction_ledger.last_dmc_active_cycle = state.clock.ppu_cycles;

        // If OAM is active, mark it as paused
        if (state.dma.active) {
            state.dma_interaction_ledger.oam_pause_cycle = state.clock.ppu_cycles;
        }
    }

    // DMC DMA active - CPU stalled (RDY line low)
    // Per nesdev.org wiki: DMC and OAM are independent, both can run same cycle (time-sharing)
    if (dmc_is_active) {
        state.tickDmcDma();
        // Don't return - OAM can continue if active (time-sharing)
    }

    // OAM DMA active - CPU frozen for 512 cycles
    // tickOamDma handles coordination with DMC internally
    if (state.dma.active) {
        state.tickDma();
        return .{};
    }

    // If we only had DMC (no OAM), return now
    if (dmc_is_active) {
        return .{};
    }

    // Normal CPU execution
    executeCycle(state, current_vblank_set_cycle);

    // Mapper IRQ is now polled before CPU execution in State.zig
    // to ensure CPU sees IRQ line changes in the same cycle
    return .{};
}

/// Execute CPU micro-operations for the current cycle.
/// Implements the 6502 state machine with cycle-accurate timing.
///
/// State Machine:
/// - .interrupt_sequence → .fetch_opcode (7 cycles: NMI/IRQ/RESET)
/// - .fetch_opcode → .fetch_operand_low or .execute (1 cycle)
/// - .fetch_operand_low → .execute (1-8 cycles: addressing modes)
/// - .execute → .fetch_opcode (1 cycle: opcode execution)
///
/// Caller is responsible for clock management.
///
/// @param vblank_set_cycle: Current VBlank set_cycle (0 if no VBlank active) for double-trigger suppression
pub fn executeCycle(state: anytype, vblank_set_cycle: u64) void {
    // Clock advancement happens in tick() - not here
    // This keeps timing management centralized

    // Check for interrupts at the start of instruction fetch
    // CRITICAL: Interrupt must hijack the opcode fetch in the CURRENT cycle,
    // not the next cycle. If we detect an interrupt, we do the dummy read
    // (hijacked opcode fetch) immediately and transition to interrupt_sequence
    // at cycle 1 (since we just completed cycle 0).
    if (state.cpu.state == .fetch_opcode) {
        CpuLogic.checkInterrupts(&state.cpu, vblank_set_cycle);
        if (state.cpu.pending_interrupt != .none and state.cpu.pending_interrupt != .reset) {
            // Interrupt hijacks the opcode fetch - do dummy read at PC NOW
            _ = state.busRead(state.cpu.pc);
            // DO NOT increment PC - interrupt will set new PC from vector

            // Transition to interrupt sequence at cycle 1 (we just did cycle 0)
            state.cpu.state = .interrupt_sequence;
            state.cpu.instruction_cycle = 1; // Start at cycle 1, not 0
            return;
        }

        // Check debugger breakpoints/watchpoints (RT-safe, zero allocations)
        if (state.debugger) |*debugger| {
            if (debugger.shouldBreak(state) catch false) {
                // Breakpoint hit - set flag for EmulationThread to post event
                state.debug_break_occurred = true;
                return;
            }
        }
    }

    // Handle hardware interrupts (NMI/IRQ/RESET) - 7 cycles
    // NOTE: Cycle 0 (dummy read) happens in fetch_opcode handler above
    // We enter this handler at instruction_cycle = 1
    if (state.cpu.state == .interrupt_sequence) {
        const complete = switch (state.cpu.instruction_cycle) {
            // Cycle 0 done in fetch_opcode (dummy read at PC - hijacked opcode fetch)
            1 => CpuMicrosteps.pushPch(state), // Cycle 1: Push PC high byte
            2 => CpuMicrosteps.pushPcl(state), // Cycle 2: Push PC low byte
            3 => CpuMicrosteps.pushStatusInterrupt(state), // Cycle 3: Push P (B=0)
            4 => blk: {
                // Cycle 4: Fetch vector low byte
                state.cpu.operand_low = switch (state.cpu.pending_interrupt) {
                    .nmi => state.busRead(0xFFFA),
                    .irq => state.busRead(0xFFFE),
                    .reset => state.busRead(0xFFFC),
                    else => unreachable,
                };
                state.cpu.p.interrupt = true; // Set I flag
                break :blk false;
            },
            5 => blk: {
                // Cycle 5: Fetch vector high byte
                state.cpu.operand_high = switch (state.cpu.pending_interrupt) {
                    .nmi => state.busRead(0xFFFB),
                    .irq => state.busRead(0xFFFF),
                    .reset => state.busRead(0xFFFD),
                    else => unreachable,
                };
                break :blk false;
            },
            6 => blk: {
                // Cycle 6: Jump to handler
                state.cpu.pc = (@as(u16, state.cpu.operand_high) << 8) |
                    @as(u16, state.cpu.operand_low);

                // Clear pending interrupt
                // Note: NMI line remains asserted until VBlank flag is cleared
                // (via $2002 read or scanline 261 dot 1). This allows the CPU
                // edge detector to properly latch the interrupt signal.
                state.cpu.pending_interrupt = .none;

                break :blk true; // Complete
            },
            else => unreachable,
        };

        if (complete) {
            state.cpu.state = .fetch_opcode;
            state.cpu.instruction_cycle = 0;
        } else {
            state.cpu.instruction_cycle += 1;
        }
        return;
    }

    // Cycle 1: Always fetch opcode
    if (state.cpu.state == .fetch_opcode) {
        state.cpu.opcode = state.busRead(state.cpu.pc);
        state.cpu.data_bus = state.cpu.opcode;
        state.cpu.pc +%= 1;

        const entry = CpuModule.dispatch.DISPATCH_TABLE[state.cpu.opcode];
        state.cpu.address_mode = entry.info.mode;

        // Determine if addressing cycles needed (inline logic, no arrays)
        // IMPORTANT: Control flow opcodes (JSR/RTS/RTI/BRK/PHA/PLA/PHP/PLP) have custom microstep
        // sequences even though they're marked as .implied or .absolute in the decode table
        const needs_addressing = switch (state.cpu.opcode) {
            0x20, 0x60, 0x40, 0x00, 0x48, 0x68, 0x08, 0x28 => true, // Force addressing state for control flow
            else => switch (entry.info.mode) {
                .implied, .accumulator, .immediate => false,
                else => true,
            },
        };

        if (needs_addressing) {
            state.cpu.state = .fetch_operand_low;
            state.cpu.instruction_cycle = 0;
        } else {
            state.cpu.state = .execute;
        }
        return;
    }

    // Handle addressing mode microsteps (inline switch logic)
    if (state.cpu.state == .fetch_operand_low) {
        const entry = CpuModule.dispatch.DISPATCH_TABLE[state.cpu.opcode];

        // Check for control flow opcodes with custom microstep sequences FIRST
        // These have special cycle patterns that don't match their addressing mode
        const is_control_flow = switch (state.cpu.opcode) {
            0x20, 0x60, 0x40, 0x00, 0x48, 0x68, 0x08, 0x28 => true, // JSR, RTS, RTI, BRK, PHA, PLA, PHP, PLP
            else => false,
        };

        // Call appropriate microstep based on mode and cycle
        // Returns true if instruction completes early (e.g., branch not taken)
        const complete = if (is_control_flow) blk: {
            // Control flow instructions with completely custom microstep sequences
            break :blk switch (state.cpu.opcode) {
                // JSR - 6 cycles
                0x20 => switch (state.cpu.instruction_cycle) {
                    0 => CpuMicrosteps.fetchAbsLow(state),
                    1 => CpuMicrosteps.jsrStackDummy(state),
                    2 => CpuMicrosteps.pushPch(state),
                    3 => CpuMicrosteps.pushPcl(state),
                    4 => CpuMicrosteps.fetchAbsHighJsr(state),
                    else => unreachable,
                },
                // RTS - 6 cycles
                0x60 => switch (state.cpu.instruction_cycle) {
                    0 => CpuMicrosteps.stackDummyRead(state),
                    1 => CpuMicrosteps.stackDummyRead(state),
                    2 => CpuMicrosteps.pullPcl(state),
                    3 => CpuMicrosteps.pullPch(state),
                    4 => CpuMicrosteps.incrementPcAfterRts(state),
                    else => unreachable,
                },
                // RTI - 6 cycles
                0x40 => switch (state.cpu.instruction_cycle) {
                    0 => CpuMicrosteps.stackDummyRead(state),
                    1 => CpuMicrosteps.pullStatus(state),
                    2 => CpuMicrosteps.pullPcl(state),
                    3 => CpuMicrosteps.pullPch(state), // Pull PC high
                    4 => blk2: { // Dummy read at new PC before completing
                        _ = state.busRead(state.cpu.pc);
                        break :blk2 true; // RTI complete
                    },
                    else => unreachable,
                },
                // BRK - 7 cycles
                0x00 => switch (state.cpu.instruction_cycle) {
                    0 => CpuMicrosteps.fetchOperandLow(state),
                    1 => CpuMicrosteps.pushPch(state),
                    2 => CpuMicrosteps.pushPcl(state),
                    3 => CpuMicrosteps.pushStatusBrk(state),
                    4 => CpuMicrosteps.fetchIrqVectorLow(state),
                    5 => CpuMicrosteps.fetchIrqVectorHigh(state),
                    else => unreachable,
                },
                // PHA - 3 cycles (dummy read, then execute pushes)
                0x48 => switch (state.cpu.instruction_cycle) {
                    0 => CpuMicrosteps.stackDummyRead(state),
                    else => unreachable,
                },
                // PHP - 3 cycles (dummy read, then execute pushes)
                0x08 => switch (state.cpu.instruction_cycle) {
                    0 => CpuMicrosteps.stackDummyRead(state),
                    else => unreachable,
                },
                // PLA - 4 cycles (dummy read twice, then pull)
                0x68 => switch (state.cpu.instruction_cycle) {
                    0 => CpuMicrosteps.stackDummyRead(state),
                    1 => CpuMicrosteps.pullByte(state),
                    else => unreachable,
                },
                // PLP - 4 cycles
                0x28 => switch (state.cpu.instruction_cycle) {
                    0 => CpuMicrosteps.stackDummyRead(state),
                    1 => CpuMicrosteps.pullStatus(state),
                    else => unreachable,
                },
                else => unreachable,
            };
        } else switch (entry.info.mode) {
            .zero_page => blk: {
                if (entry.is_rmw) {
                    // RMW: 5 cycles (fetch, read, dummy write, execute)
                    break :blk switch (state.cpu.instruction_cycle) {
                        0 => CpuMicrosteps.fetchOperandLow(state),
                        1 => CpuMicrosteps.rmwRead(state),
                        2 => CpuMicrosteps.rmwDummyWrite(state),
                        else => unreachable,
                    };
                } else {
                    break :blk switch (state.cpu.instruction_cycle) {
                        0 => CpuMicrosteps.fetchOperandLow(state),
                        else => unreachable,
                    };
                }
            },
            .zero_page_x => blk: {
                if (entry.is_rmw) {
                    // RMW: 6 cycles (fetch, add X, read, dummy write, execute)
                    break :blk switch (state.cpu.instruction_cycle) {
                        0 => CpuMicrosteps.fetchOperandLow(state),
                        1 => CpuMicrosteps.addXToZeroPage(state),
                        2 => CpuMicrosteps.rmwRead(state),
                        3 => CpuMicrosteps.rmwDummyWrite(state),
                        else => unreachable,
                    };
                } else {
                    break :blk switch (state.cpu.instruction_cycle) {
                        0 => CpuMicrosteps.fetchOperandLow(state),
                        1 => CpuMicrosteps.addXToZeroPage(state),
                        else => unreachable,
                    };
                }
            },
            .zero_page_y => switch (state.cpu.instruction_cycle) {
                0 => CpuMicrosteps.fetchOperandLow(state),
                1 => CpuMicrosteps.addYToZeroPage(state),
                else => unreachable,
            },
            .absolute => blk: {
                if (entry.is_rmw) {
                    // RMW: 6 cycles (fetch low, high, read, dummy write, execute)
                    break :blk switch (state.cpu.instruction_cycle) {
                        0 => CpuMicrosteps.fetchAbsLow(state),
                        1 => CpuMicrosteps.fetchAbsHigh(state),
                        2 => CpuMicrosteps.rmwRead(state),
                        3 => CpuMicrosteps.rmwDummyWrite(state),
                        else => unreachable,
                    };
                } else {
                    break :blk switch (state.cpu.instruction_cycle) {
                        0 => CpuMicrosteps.fetchAbsLow(state),
                        1 => CpuMicrosteps.fetchAbsHigh(state),
                        else => unreachable,
                    };
                }
            },
            .absolute_x => blk: {
                // Read vs write have different cycle counts
                if (entry.is_rmw) {
                    // RMW: 7 cycles (fetch low, high, calc+dummy, read, dummy write, execute)
                    break :blk switch (state.cpu.instruction_cycle) {
                        0 => CpuMicrosteps.fetchAbsLow(state),
                        1 => CpuMicrosteps.fetchAbsHigh(state),
                        2 => CpuMicrosteps.calcAbsoluteX(state),
                        3 => CpuMicrosteps.rmwRead(state),
                        4 => CpuMicrosteps.rmwDummyWrite(state),
                        else => unreachable,
                    };
                } else {
                    // Regular read: 4-5 cycles (4 if no page cross, 5 if page cross)
                    break :blk switch (state.cpu.instruction_cycle) {
                        0 => CpuMicrosteps.fetchAbsLow(state),
                        1 => CpuMicrosteps.fetchAbsHigh(state),
                        2 => CpuMicrosteps.calcAbsoluteX(state),
                        3 => CpuMicrosteps.fixHighByte(state),
                        else => unreachable,
                    };
                }
            },
            .absolute_y => blk: {
                if (entry.is_rmw) {
                    // RMW not used with absolute_y, but handle for completeness
                    break :blk switch (state.cpu.instruction_cycle) {
                        0 => CpuMicrosteps.fetchAbsLow(state),
                        1 => CpuMicrosteps.fetchAbsHigh(state),
                        2 => CpuMicrosteps.calcAbsoluteY(state),
                        3 => CpuMicrosteps.rmwRead(state),
                        4 => CpuMicrosteps.rmwDummyWrite(state),
                        else => unreachable,
                    };
                } else {
                    // Regular read: 4-5 cycles (4 if no page cross, 5 if page cross)
                    break :blk switch (state.cpu.instruction_cycle) {
                        0 => CpuMicrosteps.fetchAbsLow(state),
                        1 => CpuMicrosteps.fetchAbsHigh(state),
                        2 => CpuMicrosteps.calcAbsoluteY(state),
                        3 => CpuMicrosteps.fixHighByte(state),
                        else => unreachable,
                    };
                }
            },
            .indexed_indirect => blk: {
                if (entry.is_rmw) {
                    // RMW: 8 cycles
                    break :blk switch (state.cpu.instruction_cycle) {
                        0 => CpuMicrosteps.fetchZpBase(state),
                        1 => CpuMicrosteps.addXToBase(state),
                        2 => CpuMicrosteps.fetchIndirectLow(state),
                        3 => CpuMicrosteps.fetchIndirectHigh(state),
                        4 => CpuMicrosteps.rmwRead(state),
                        5 => CpuMicrosteps.rmwDummyWrite(state),
                        else => unreachable,
                    };
                } else {
                    // Regular: 6 cycles
                    break :blk switch (state.cpu.instruction_cycle) {
                        0 => CpuMicrosteps.fetchZpBase(state),
                        1 => CpuMicrosteps.addXToBase(state),
                        2 => CpuMicrosteps.fetchIndirectLow(state),
                        3 => CpuMicrosteps.fetchIndirectHigh(state),
                        else => unreachable,
                    };
                }
            },
            .indirect_indexed => blk: {
                if (entry.is_rmw) {
                    // RMW: 8 cycles
                    break :blk switch (state.cpu.instruction_cycle) {
                        0 => CpuMicrosteps.fetchZpPointer(state),
                        1 => CpuMicrosteps.fetchPointerLow(state),
                        2 => CpuMicrosteps.fetchPointerHigh(state),
                        3 => CpuMicrosteps.addYCheckPage(state),
                        4 => CpuMicrosteps.rmwRead(state),
                        5 => CpuMicrosteps.rmwDummyWrite(state),
                        else => unreachable,
                    };
                } else {
                    // Regular read: 5-6 cycles (5 if no page cross, 6 if page cross)
                    break :blk switch (state.cpu.instruction_cycle) {
                        0 => CpuMicrosteps.fetchZpPointer(state),
                        1 => CpuMicrosteps.fetchPointerLow(state),
                        2 => CpuMicrosteps.fetchPointerHigh(state),
                        3 => CpuMicrosteps.addYCheckPage(state),
                        4, 5 => CpuMicrosteps.fixHighByte(state), // Cycle 4: no page cross final read, Cycle 5: page cross final read
                        else => unreachable,
                    };
                }
            },
            .relative => switch (state.cpu.instruction_cycle) {
                0 => CpuMicrosteps.branchFetchOffset(state),
                1 => CpuMicrosteps.branchAddOffset(state),
                2 => CpuMicrosteps.branchFixPch(state),
                else => unreachable,
            },
            .indirect => switch (state.cpu.instruction_cycle) {
                0 => CpuMicrosteps.fetchAbsLow(state),
                1 => CpuMicrosteps.fetchAbsHigh(state),
                2 => CpuMicrosteps.jmpIndirectFetchLow(state),
                3 => CpuMicrosteps.jmpIndirectFetchHigh(state),
                else => unreachable,
            },
            else => unreachable, // All addressing modes should be handled above
        };

        state.cpu.instruction_cycle += 1;

        if (complete) {
            // Instruction completed early (e.g., branch not taken)
            state.cpu.state = .fetch_opcode;
            state.cpu.instruction_cycle = 0;
            return;
        }

        // Check if addressing is complete and we should move to execute
        // IMPORTANT: Check for control flow opcodes FIRST before checking addressing mode
        // These opcodes have conventional addressing modes but custom microstep sequences
        const addressing_done = if (is_control_flow) blk: {
            // Control flow instructions complete via their final microstep
            break :blk switch (state.cpu.opcode) {
                0x20 => state.cpu.instruction_cycle >= 5, // JSR (6 cycles total)
                0x60 => state.cpu.instruction_cycle >= 5, // RTS (6 cycles total)
                0x40 => state.cpu.instruction_cycle >= 5, // RTI (6 cycles total)
                0x00 => state.cpu.instruction_cycle >= 6, // BRK (7 cycles total)
                0x48, 0x08 => state.cpu.instruction_cycle >= 1, // PHA, PHP (3 cycles total)
                0x68, 0x28 => state.cpu.instruction_cycle >= 2, // PLA, PLP (4 cycles total)
                else => unreachable,
            };
        } else switch (entry.info.mode) {
            .zero_page => blk: {
                if (entry.is_rmw) {
                    break :blk state.cpu.instruction_cycle >= 3;
                } else {
                    break :blk state.cpu.instruction_cycle >= 1;
                }
            },
            .zero_page_x => blk: {
                if (entry.is_rmw) {
                    break :blk state.cpu.instruction_cycle >= 4;
                } else {
                    break :blk state.cpu.instruction_cycle >= 2;
                }
            },
            .zero_page_y => state.cpu.instruction_cycle >= 2,
            .absolute => blk: {
                if (entry.is_rmw) {
                    break :blk state.cpu.instruction_cycle >= 4;
                } else {
                    break :blk state.cpu.instruction_cycle >= 2;
                }
            },
            .absolute_x, .absolute_y => blk: {
                if (entry.is_rmw) {
                    break :blk state.cpu.instruction_cycle >= 5;
                } else {
                    // Non-RMW reads: Executes cycles 0-2 (no page cross) or 0-3 (page cross)
                    // Threshold check happens AFTER incrementing cycle, so threshold = last_cycle + 1
                    const threshold: u8 = if (state.cpu.page_crossed) 4 else 3;
                    break :blk state.cpu.instruction_cycle >= threshold;
                }
            },
            .indexed_indirect => blk: {
                if (entry.is_rmw) {
                    break :blk state.cpu.instruction_cycle >= 6;
                } else {
                    break :blk state.cpu.instruction_cycle >= 4;
                }
            },
            .indirect_indexed => blk: {
                if (entry.is_rmw) {
                    break :blk state.cpu.instruction_cycle >= 6;
                } else {
                    // Non-RMW reads: Execute cycles 0-4 (no page cross) or 0-5 (page cross)
                    // Threshold check happens AFTER cycle increment, so threshold = last_cycle + 1
                    const threshold: u8 = if (state.cpu.page_crossed) 6 else 5;
                    break :blk state.cpu.instruction_cycle >= threshold;
                }
            },
            .relative => false, // Branches always complete via return value
            .indirect => state.cpu.instruction_cycle >= 4,
            else => true, // implied, accumulator, immediate
        };

        if (addressing_done) {
            state.cpu.state = .execute;

            // Conditional fallthrough: ONLY for indexed modes with +1 cycle deviation
            // Hardware combines final operand read + execute in same cycle for:
            // - absolute,X / absolute,Y
            // - indirect,Y (indirect indexed)
            // Other modes already have correct timing - don't fall through!
            const dispatch_entry = CpuModule.dispatch.DISPATCH_TABLE[state.cpu.opcode];
            const should_fallthrough = !dispatch_entry.is_rmw and
                (state.cpu.address_mode == .absolute_x or
                    state.cpu.address_mode == .absolute_y or
                    state.cpu.address_mode == .indirect_indexed);

            if (should_fallthrough) {
                // Fall through to execute state (don't return)
                // Indexed modes complete in same tick as final addressing
            } else {
                // All other modes: execute in separate cycle
                return;
            }
        } else {
            return;
        }
    }

    // Execute instruction (Pure Function Architecture)
    if (state.cpu.state == .execute) {
        const entry = CpuModule.dispatch.DISPATCH_TABLE[state.cpu.opcode];

        // Extract operand value based on addressing mode (inline for bus access)
        const operand = if (entry.is_rmw or entry.is_pull)
            state.cpu.temp_value
        else switch (state.cpu.address_mode) {
            .immediate => state.busRead(state.cpu.pc),
            .accumulator => state.cpu.a,
            .implied => 0,
            .zero_page => state.busRead(@as(u16, state.cpu.operand_low)),
            .zero_page_x, .zero_page_y => state.busRead(state.cpu.effective_address),
            .absolute => blk: {
                const addr = (@as(u16, state.cpu.operand_high) << 8) | state.cpu.operand_low;

                // Check if this is a write-only instruction (STA, STX, STY)
                // Real 6502 hardware doesn't read before writing for these instructions
                const is_write_only = switch (state.cpu.opcode) {
                    0x8D, // STA absolute
                    0x8E, // STX absolute
                    0x8C, // STY absolute
                    => true,
                    else => false,
                };

                if (is_write_only) {
                    break :blk 0; // Operand not used for write-only instructions
                }

                const value = state.busRead(addr);
                break :blk value;
            },
            // Indexed modes: Always use temp_value (already read in addressing state)
            // No page cross: calcAbsoluteX/Y read it
            // Page cross: fixHighByte read it
            .absolute_x, .absolute_y, .indirect_indexed => state.cpu.temp_value,
            .indexed_indirect => state.busRead(state.cpu.effective_address),
            // Indirect: JMP ($nnnn) doesn't use operand, effective_address set during addressing
            .indirect => 0, // Dummy value, not used by JMP
            .relative => state.cpu.operand_low,
        };

        // Immediate mode: Increment PC after reading operand
        if (state.cpu.address_mode == .immediate) {
            state.cpu.pc +%= 1;
        }

        // Set effective_address for modes that need it
        switch (state.cpu.address_mode) {
            .zero_page => {
                state.cpu.effective_address = @as(u16, state.cpu.operand_low);
            },
            .absolute => {
                state.cpu.effective_address = (@as(u16, state.cpu.operand_high) << 8) | @as(u16, state.cpu.operand_low);
            },
            else => {},
        }

        // Convert to core CPU state (6502 registers + effective address)
        const core_state = CpuLogic.toCoreState(&state.cpu);

        // Call pure opcode function (returns delta structure)
        const result = entry.operation(core_state, operand);

        // Apply result (inline for bus writes)
        if (result.a) |new_a| state.cpu.a = new_a;
        if (result.x) |new_x| state.cpu.x = new_x;
        if (result.y) |new_y| state.cpu.y = new_y;
        if (result.sp) |new_sp| state.cpu.sp = new_sp;
        if (result.pc) |new_pc| state.cpu.pc = new_pc;
        if (result.flags) |new_flags| state.cpu.p = new_flags;

        if (result.bus_write) |write| {
            state.busWrite(write.address, write.value);
            state.cpu.data_bus = write.value;
        }

        if (result.push) |value| {
            const stack_addr = 0x0100 | @as(u16, state.cpu.sp);
            state.busWrite(stack_addr, value);
            state.cpu.sp -%= 1;
            state.cpu.data_bus = value;
        }

        if (result.halt) {
            state.cpu.halted = true;
        }

        // Instruction complete
        state.cpu.state = .fetch_opcode;
        state.cpu.instruction_cycle = 0;
    }
}
