//! DMA Logic - OAM DMA and DMC DMA
//!
//! Functional pattern following VBlank idioms.
//! All logic is pure - calculates what to do from cycle counts and timestamps.

const std = @import("std");
const ApuLogic = @import("../../apu/Logic.zig");

/// Tick OAM DMA (called every CPU cycle when active)
/// Executes OAM DMA transfer from CPU RAM ($XX00-$XXFF) to PPU OAM ($2004)
///
/// Functional pattern - no state machine:
/// - Calculate effective cycle from current_cycle and alignment
/// - Determine read vs write from cycle parity
/// - Check for pause/resume from timestamps
///
/// Hardware behavior:
/// - CPU is stalled (no instruction execution)
/// - PPU continues running normally
/// - Bus is monopolized by DMA controller
/// - DMC DMA can interrupt OAM DMA (handled by ledger timestamps)
pub fn tickOamDma(state: anytype) void {
    const ledger = &state.dma_interaction_ledger;
    const dma = &state.dma;
    const now = state.clock.ppu_cycles;

    // Check 1: Are we paused by DMC? (functional check)
    const dmc_is_active = ledger.last_dmc_active_cycle > ledger.last_dmc_inactive_cycle;
    const was_paused = ledger.oam_pause_cycle > ledger.oam_resume_cycle;

    if (dmc_is_active and was_paused) {
        return; // Frozen, do nothing
    }

    // Check 2: Just resumed - handle duplication
    const just_resumed = !dmc_is_active and was_paused;
    if (just_resumed) {
        // Mark as resumed FIRST to prevent re-entering this block
        ledger.oam_resume_cycle = now;

        // If paused during read, write the duplicate byte
        // Then fall through to re-read from same offset (hardware behavior)
        if (ledger.paused_during_read) {
            state.ppu.oam[state.ppu.oam_addr] = ledger.paused_byte_value;
            state.ppu.oam_addr +%= 1;
            ledger.paused_during_read = false; // Clear flag to prevent re-duplication
        }
        // Fall through to continue normal operation
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
        ledger.reset();
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
