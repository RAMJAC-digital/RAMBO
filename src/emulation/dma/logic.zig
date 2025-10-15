//! DMA Logic - OAM DMA and DMC DMA State Machines
//!
//! This module contains the logic for two types of DMA:
//! 1. OAM DMA ($4014 write) - Transfers 256 bytes from CPU RAM to PPU OAM
//! 2. DMC DMA - APU sample fetch via RDY line stall
//!
//! Both are implemented as pure functions operating on EmulationState.

const std = @import("std");
const ApuLogic = @import("../../apu/Logic.zig");

// Debug flag for DMA tracing (enable for debugging)
const DEBUG_DMA = false;

/// Tick OAM DMA state machine (called every CPU cycle when active)
/// Executes OAM DMA transfer from CPU RAM ($XX00-$XXFF) to PPU OAM ($2004)
///
/// Timing (hardware-accurate):
/// - Cycle 0 (if needed): Alignment wait (odd CPU cycle start)
/// - Cycles 1-512: 256 read/write pairs
///   * Even cycles: Read byte from CPU RAM
///   * Odd cycles: Write byte to PPU OAM
/// - Total: 513 cycles (even start) or 514 cycles (odd start)
///
/// Hardware behavior:
/// - CPU is stalled (no instruction execution)
/// - PPU continues running normally
/// - Bus is monopolized by DMA controller
pub fn tickOamDma(state: anytype) void {
    // CPU cycle count removed - time tracked by MasterClock
    // No increment needed - clock is advanced in tick()

    // Increment DMA cycle counter
    const cycle = state.dma.current_cycle;
    state.dma.current_cycle += 1;

    // Only log cycle 0 (start) and alignment
    if (DEBUG_DMA and cycle == 0) {
        if (state.dma.needs_alignment) {
            std.debug.print("[DMA] cycle=0 ALIGN WAIT ppu={d}\n", .{state.clock.ppu_cycles});
        } else {
            std.debug.print("[DMA] cycle=0 START ppu={d}\n", .{state.clock.ppu_cycles});
        }
    }

    // Alignment wait cycle (if needed)
    if (state.dma.needs_alignment and cycle == 0) {
        return;
    }

    // Calculate effective cycle (after alignment)
    const effective_cycle = if (state.dma.needs_alignment) cycle - 1 else cycle;

    // Check if DMA is complete (512 cycles = 256 read/write pairs)
    if (effective_cycle >= 512) {
        if (DEBUG_DMA) {
            std.debug.print("[DMA COMPLETE] effective_cycle={d} >= 512, resetting DMA\n", .{effective_cycle});
        }
        state.dma.reset();
        return;
    }

    // DMA transfer: Alternate between read and write
    if (effective_cycle % 2 == 0) {
        // Even cycle: Read from CPU RAM
        const source_addr = (@as(u16, state.dma.source_page) << 8) | @as(u16, state.dma.current_offset);
        state.dma.temp_value = state.busRead(source_addr);
    } else {
        // Odd cycle: Write to PPU OAM via $2004 (respects oam_addr)
        // Hardware behavior: DMA writes through $2004, which auto-increments oam_addr
        // This allows games to set oam_addr before DMA for custom sprite ordering
        state.ppu.oam[state.ppu.oam_addr] = state.dma.temp_value;
        state.ppu.oam_addr +%= 1; // Auto-increment (wraps at 256)

        // Increment source offset for next byte
        state.dma.current_offset +%= 1;
    }
}

/// Tick DMC DMA state machine (called every CPU cycle when active)
///
/// Hardware behavior (NTSC 2A03 only):
/// - CPU is stalled via RDY line for 4 cycles (3 idle + 1 fetch)
/// - During stall, CPU repeats last read cycle
/// - If last read was $4016/$4017 (controller), corruption occurs
/// - If last read was $2002/$2007 (PPU), side effects repeat
///
/// PAL 2A07: Bug fixed, DMA is clean (no corruption)
pub fn tickDmcDma(state: anytype) void {
    // CPU cycle count removed - time tracked by MasterClock
    // No increment needed - clock is advanced in tick()

    const cycle = state.dmc_dma.stall_cycles_remaining;

    if (cycle == 0) {
        // DMA complete
        state.dmc_dma.rdy_low = false;
        return;
    }

    state.dmc_dma.stall_cycles_remaining -= 1;

    if (cycle == 1) {
        // Final cycle: Fetch sample byte
        const address = state.dmc_dma.sample_address;
        state.dmc_dma.sample_byte = state.busRead(address);

        // Load into APU
        ApuLogic.loadSampleByte(&state.apu, state.dmc_dma.sample_byte);

        // DMA complete - clear RDY line
        state.dmc_dma.rdy_low = false;
    } else {
        // Idle cycles (1-3): CPU repeats last read
        // This is where corruption happens on NTSC
        const has_dpcm_bug = switch (state.config.cpu.variant) {
            .rp2a03e, .rp2a03g, .rp2a03h => true, // NTSC - has bug
            .rp2a07 => false, // PAL - bug fixed
        };

        if (has_dpcm_bug) {
            // NTSC: Repeat last read (can cause corruption)
            const last_addr = state.dmc_dma.last_read_address;

            // If last read was controller, this extra read corrupts shift register
            if (last_addr == 0x4016 or last_addr == 0x4017) {
                // Extra read advances shift register -> corruption
                _ = state.busRead(last_addr);
            }

            // If last read was PPU status/data, side effects occur again
            if (last_addr == 0x2002 or last_addr == 0x2007) {
                _ = state.busRead(last_addr);
            }
        }
        // PAL: Clean DMA, no repeat reads
    }
}
