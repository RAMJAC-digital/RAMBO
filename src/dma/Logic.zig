//! DMA Logic - OAM DMA and DMC DMA operations
//!
//! Self-contained DMA subsystem following PPU black box pattern.
//! Manages OAM DMA, DMC DMA, interaction tracking, and RDY line computation.

const std = @import("std");
const DmaState = @import("State.zig").DmaState;
const ApuLogic = @import("../apu/Logic.zig");

/// Main DMA tick function - handles all DMA operations and signal computation
///
/// Called every CPU cycle by EmulationState.
/// Manages:
/// - DMC/OAM interaction edge detection
/// - OAM DMA transfer execution
/// - DMC DMA transfer execution
/// - RDY line signal computation (output to CPU)
///
/// Parameters:
/// - dma: DMA state (owns all DMA state and outputs)
/// - master_cycles: Current master clock cycle (for timestamps)
/// - bus: Bus interface (for DMA memory reads/writes)
/// - apu: APU state (for DMC sample loading)
pub fn tick(dma: *DmaState, master_cycles: u64, bus: anytype, apu: anytype) void {
    // Update interaction ledger (edge detection)
    updateInteractionLedger(dma, master_cycles);

    // Tick DMA state machines if active
    if (dma.dmc.rdy_low) {
        tickDmcDma(dma, bus, apu);
    }
    if (dma.oam.active) {
        tickOamDma(dma, bus);
    }

    // Compute RDY line output signal
    // RDY line is LOW (false) when either DMA is active, HIGH (true) otherwise
    dma.rdy_line = !(dma.dmc.rdy_low or dma.oam.active);
}

/// Update DMA interaction ledger when DMC/OAM DMA state changes
/// Tracks edge transitions for debugging and timing validation
fn updateInteractionLedger(dma: *DmaState, master_cycles: u64) void {
    const ledger = &dma.interaction;

    // Handle DMC DMA transfer completion
    if (dma.dmc.transfer_complete) {
        dma.dmc.transfer_complete = false;
        ledger.last_dmc_inactive_cycle = master_cycles;

        const was_paused = ledger.oam_pause_cycle > ledger.oam_resume_cycle;
        if (was_paused and dma.oam.active) {
            ledger.oam_resume_cycle = master_cycles;
            ledger.needs_alignment_after_dmc = true;
        }
    }

    // Track DMC DMA state transitions (edge detection)
    const dmc_was_active = (ledger.last_dmc_active_cycle > ledger.last_dmc_inactive_cycle);
    const dmc_is_active = dma.dmc.rdy_low;

    if (dmc_is_active and !dmc_was_active) {
        ledger.last_dmc_active_cycle = master_cycles;

        if (dma.oam.active) {
            ledger.oam_pause_cycle = master_cycles;
        }
    }
}

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
fn tickOamDma(dma: *DmaState, bus: anytype) void {
    // Check 1: Is DMC stalling OAM?
    //
    // Hardware time-sharing behavior per nesdev.org:
    // When DMC and OAM both need memory access, DMC has priority but OAM execution
    // during DMC's idle cycles counts as DMC's halt/dummy cycles (time-sharing).
    //
    // DMC DMA cycle breakdown (stall_cycles_remaining countdown):
    //   Cycle 4 (halt):      OAM continues executing ✓ (counts as DMC halt cycle)
    //   Cycle 3 (dummy):     OAM continues executing ✓ (counts as DMC dummy cycle)
    //   Cycle 2 (alignment): OAM continues executing ✓ (counts as DMC alignment cycle)
    //   Cycle 1 (read):      OAM PAUSES ✗ (DMC reads memory, OAM must wait)
    //
    // Net result: OAM advances 3 cycles during DMC's 4-cycle operation
    // Hardware overhead: 4 (DMC) - 3 (OAM advancement) = 1 cycle + 1 post-DMC alignment = ~2 cycles total
    const dmc_is_stalling_oam = dma.dmc.rdy_low and
        dma.dmc.stall_cycles_remaining == 1; // Only DMC read cycle pauses OAM

    if (dmc_is_stalling_oam) {
        // OAM must wait during DMC read cycle only
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
    if (dma.interaction.needs_alignment_after_dmc) {
        dma.interaction.needs_alignment_after_dmc = false;
        return; // Consume this CPU cycle without advancing DMA state
    }

    // Calculate effective cycle (accounting for alignment)
    const effective_cycle: i32 = if (dma.oam.needs_alignment)
        @as(i32, @intCast(dma.oam.current_cycle)) - 1
    else
        @as(i32, @intCast(dma.oam.current_cycle));

    // Check 3: Alignment wait?
    if (effective_cycle < 0) {
        dma.oam.current_cycle += 1;
        return;
    }

    // Check 4: Completed?
    if (effective_cycle >= 512) {
        dma.oam.reset();
        dma.interaction.reset();
        return;
    }

    // Check 5: Read or write? (functional check based on cycle parity)
    const is_read_cycle = @rem(effective_cycle, 2) == 0;

    if (is_read_cycle) {
        // READ
        const addr = (@as(u16, dma.oam.source_page) << 8) | dma.oam.current_offset;
        dma.oam.temp_value = bus.busRead(addr);
    } else {
        // WRITE
        bus.ppu.oam[bus.ppu.oam_addr] = dma.oam.temp_value;
        bus.ppu.oam_addr +%= 1;
        dma.oam.current_offset +%= 1;
    }

    dma.oam.current_cycle += 1;
}

/// Tick DMC DMA (called every CPU cycle when active)
///
/// Pattern: Clear rdy_low on completion AND signal via transfer_complete
///
/// Hardware behavior (NTSC 2A03 only):
/// - CPU is stalled via RDY line for 4 cycles (3 idle + 1 fetch)
/// - During stall, CPU repeats last read cycle
/// - If last read was MMIO, side effects repeat (corruption)
///
/// PAL 2A07: Bug fixed, DMA is clean (no corruption)
///
/// Note: Public for unit testing (tests verify DMC timing directly)
pub fn tickDmcDma(dma: *DmaState, bus: anytype, apu: anytype) void {
    const cycle = dma.dmc.stall_cycles_remaining;

    if (cycle == 0) {
        // DMA already complete - just signal (for idempotency)
        dma.dmc.transfer_complete = true;
        return;
    }

    dma.dmc.stall_cycles_remaining -= 1;

    if (cycle == 1) {
        // Final cycle: Fetch sample byte
        const address = dma.dmc.sample_address;
        dma.dmc.sample_byte = bus.busRead(address);

        // Load into APU
        ApuLogic.loadSampleByte(apu, dma.dmc.sample_byte);

        // Complete: Clear rdy_low and signal completion
        dma.dmc.rdy_low = false;
        dma.dmc.transfer_complete = true;
        return;
    }

    // Idle cycles (2-4): CPU repeats last read
    // This is where corruption happens on NTSC
    const has_dpcm_bug = switch (bus.config.cpu.variant) {
        .rp2a03e, .rp2a03g, .rp2a03h => true, // NTSC - has bug
        .rp2a07 => false, // PAL - bug fixed
    };

    if (has_dpcm_bug) {
        // NTSC: Repeat last read (corruption occurs for any MMIO address)
        _ = bus.busRead(dma.dmc.last_read_address);
    }
    // PAL: Clean DMA, no repeat reads
}
