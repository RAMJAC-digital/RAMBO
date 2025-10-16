//! DMA Logic - OAM DMA and DMC DMA State Machines
//!
//! This module contains the logic for two types of DMA:
//! 1. OAM DMA ($4014 write) - Transfers 256 bytes from CPU RAM to PPU OAM
//! 2. DMC DMA - APU sample fetch via RDY line stall
//!
//! Both are implemented as pure functions operating on EmulationState.

const std = @import("std");
const ApuLogic = @import("../../apu/Logic.zig");
const DmaInteraction = @import("interaction.zig");
const DmaActions = @import("actions.zig");

// Debug flag for DMA tracing (enable for debugging)
const DEBUG_DMA = false;

/// Tick OAM DMA state machine (called every CPU cycle when active)
/// Executes OAM DMA transfer from CPU RAM ($XX00-$XXFF) to PPU OAM ($2004)
///
/// Clean 3-phase architecture:
/// 1. QUERY: Determine action (pure, no mutations)
/// 2. EXECUTE: Perform action (single side effect)
/// 3. UPDATE: Bookkeeping (state mutations after action)
///
/// Hardware behavior:
/// - CPU is stalled (no instruction execution)
/// - PPU continues running normally
/// - Bus is monopolized by DMA controller
/// - DMC DMA can interrupt OAM DMA (handled by interaction ledger)
pub fn tickOamDma(state: anytype) void {
    // PHASE 1: QUERY - Determine action (pure, no mutations)
    const action = DmaActions.determineAction(&state.dma, &state.dma_interaction_ledger);

    // PHASE 2: EXECUTE - Perform action (single side effect)
    DmaActions.executeAction(state, action);

    // PHASE 3: UPDATE - Bookkeeping (state mutations)
    DmaActions.updateBookkeeping(
        &state.dma,
        &state.ppu.oam_addr,
        &state.dma_interaction_ledger,
        action,
    );
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
