//! DMA Logic - OAM DMA and DMC DMA
//!
//! Functional pattern following VBlank idioms.
//! All logic is pure - calculates what to do from cycle counts and timestamps.

const std = @import("std");
const ApuLogic = @import("../../apu/Logic.zig");

/// Tick OAM DMA (called every CPU cycle when active)
/// Executes OAM DMA transfer from CPU RAM ($XX00-$XXFF) to PPU OAM ($2004)
///
/// Hardware behavior per nesdev.org wiki:
/// - OAM and DMC are independent DMA units
/// - When both access memory same cycle, DMC has priority
/// - OAM continues executing during DMC dummy/alignment cycles (time-sharing)
/// - OAM only pauses during actual DMC read cycle
/// - After DMC completes, OAM needs one extra alignment cycle
/// - No byte duplication - OAM reads sequential addresses
///
/// Reference: https://www.nesdev.org/wiki/DMA#DMC_DMA_during_OAM_DMA
pub fn tickOamDma(state: anytype) void {
    const dma = &state.dma;

    // Check 1: Is DMC stalling OAM?
    // Per nesdev.org wiki: OAM pauses during DMC's halt cycle (stall==4) AND read cycle (stall==1)
    // OAM continues during dummy (stall==3) and alignment (stall==2) cycles (time-sharing)
    const dmc_is_stalling_oam = state.dmc_dma.rdy_low and
        (state.dmc_dma.stall_cycles_remaining == 4 or  // Halt cycle
         state.dmc_dma.stall_cycles_remaining == 1);   // Read cycle

    if (dmc_is_stalling_oam) {
        // OAM must wait during DMC halt and read cycles
        // Do not advance current_cycle - will retry this same cycle next tick
        return;
    }

    // Check 2: Do we need post-DMC alignment cycle?
    // Per nesdev.org wiki: After DMC completes, OAM needs one extra alignment cycle
    // to get back into proper get/put rhythm
    //
    // CRITICAL: This cycle should NOT advance current_cycle OR do any transfer.
    // It's a pure "wait" cycle that consumes CPU time but doesn't affect DMA state.
    // This preserves the read/write phase alignment.
    const ledger = &state.dma_interaction_ledger;
    if (ledger.needs_alignment_after_dmc) {
        ledger.needs_alignment_after_dmc = false;
        return; // Consume this CPU cycle without advancing DMA state
    }

    // Calculate effective cycle (accounting for alignment)
    const effective_cycle: i32 = if (dma.needs_alignment)
        @as(i32, @intCast(dma.current_cycle)) - 1
    else
        @as(i32, @intCast(dma.current_cycle));

    // Check 3: Alignment wait?
    if (effective_cycle < 0) {
        dma.current_cycle += 1;
        return;
    }

    // Check 4: Completed?
    if (effective_cycle >= 512) {
        dma.reset();
        state.dma_interaction_ledger.reset();
        return;
    }

    // Check 5: Read or write? (functional check based on cycle parity)
    const is_read_cycle = @rem(effective_cycle, 2) == 0;

    if (is_read_cycle) {
        // READ
        const addr = (@as(u16, dma.source_page) << 8) | dma.current_offset;
        dma.temp_value = state.busRead(addr);
    } else {
        // WRITE
        state.ppu.oam[state.ppu.oam_addr] = dma.temp_value;
        state.ppu.oam_addr +%= 1;
        dma.current_offset +%= 1;
    }

    dma.current_cycle += 1;
}

/// Tick DMC DMA (called every CPU cycle when active)
///
/// Pattern: Clear rdy_low on completion AND signal via transfer_complete
/// execution.zig uses transfer_complete to update timestamps atomically
///
/// Hardware behavior (NTSC 2A03 only):
/// - CPU is stalled via RDY line for 4 cycles (3 idle + 1 fetch)
/// - During stall, CPU repeats last read cycle
/// - If last read was MMIO, side effects repeat (corruption)
///
/// PAL 2A07: Bug fixed, DMA is clean (no corruption)
pub fn tickDmcDma(state: anytype) void {
    const cycle = state.dmc_dma.stall_cycles_remaining;

    if (cycle == 0) {
        // DMA already complete - just signal (for idempotency)
        state.dmc_dma.transfer_complete = true;
        return;
    }

    state.dmc_dma.stall_cycles_remaining -= 1;

    if (cycle == 1) {
        // Final cycle: Fetch sample byte
        const address = state.dmc_dma.sample_address;
        state.dmc_dma.sample_byte = state.busRead(address);

        // Load into APU
        ApuLogic.loadSampleByte(&state.apu, state.dmc_dma.sample_byte);

        // Complete: Clear rdy_low and signal completion
        state.dmc_dma.rdy_low = false;
        state.dmc_dma.transfer_complete = true;
        return;
    }

    // Idle cycles (2-4): CPU repeats last read
    // This is where corruption happens on NTSC
    const has_dpcm_bug = switch (state.config.cpu.variant) {
        .rp2a03e, .rp2a03g, .rp2a03h => true, // NTSC - has bug
        .rp2a07 => false, // PAL - bug fixed
    };

    if (has_dpcm_bug) {
        // NTSC: Repeat last read (corruption occurs for any MMIO address)
        _ = state.busRead(state.dmc_dma.last_read_address);
    }
    // PAL: Clean DMA, no repeat reads
}
