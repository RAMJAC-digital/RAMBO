//! DMA State - Consolidated DMA subsystem state
//!
//! Owns OAM DMA state, DMC DMA state, interaction tracking, and RDY line output signal.
//! Follows PPU module pattern: DMA is self-contained black box outputting signals.

const std = @import("std");

/// OAM DMA state
/// Cycle-accurate DMA transfer from CPU RAM to PPU OAM
pub const OamDma = struct {
    /// DMA active flag
    active: bool = false,

    /// Source page number (written to $4014)
    /// DMA copies from ($source_page << 8) to ($source_page << 8) + 255
    source_page: u8 = 0,

    /// Current byte offset within page (0-255)
    current_offset: u8 = 0,

    /// Cycle counter within DMA transfer
    /// Used for read/write cycle alternation
    current_cycle: u16 = 0,

    /// Alignment wait needed (odd CPU cycle start)
    /// True if DMA triggered on odd cycle (adds 1 extra wait cycle)
    needs_alignment: bool = false,

    /// Temporary value for read/write pair
    /// Cycle N (even): Read into temp_value
    /// Cycle N+1 (odd): Write temp_value to OAM
    temp_value: u8 = 0,

    /// Trigger DMA transfer
    /// Called when $4014 is written
    pub fn trigger(self: *OamDma, page: u8, on_odd_cycle: bool) void {
        self.active = true;
        self.source_page = page;
        self.current_offset = 0;
        self.current_cycle = 0;
        self.needs_alignment = on_odd_cycle;
        self.temp_value = 0;
    }

    /// Reset DMA state
    pub fn reset(self: *OamDma) void {
        self.* = .{};
    }
};

/// DMC DMA state
/// Simulates RDY line (CPU stall) during DMC sample fetch
pub const DmcDma = struct {
    /// RDY line active (CPU stalled)
    rdy_low: bool = false,

    /// Completion signal (set when transfer finishes)
    transfer_complete: bool = false,

    /// Cycles remaining in RDY stall (0-4)
    /// Hardware: 3 idle cycles + 1 fetch cycle
    stall_cycles_remaining: u8 = 0,

    /// Sample address to fetch
    sample_address: u16 = 0,

    /// Sample byte fetched (returned to APU)
    sample_byte: u8 = 0,

    /// Last CPU read address (for repeat reads during stall)
    /// This is where corruption happens
    last_read_address: u16 = 0,

    /// Trigger DMC sample fetch
    /// Called by APU when it needs next sample byte
    pub fn triggerFetch(self: *DmcDma, address: u16) void {
        self.rdy_low = true;
        self.stall_cycles_remaining = 4; // 3 idle + 1 fetch
        self.sample_address = address;
    }

    /// Reset DMC DMA state
    pub fn reset(self: *DmcDma) void {
        self.* = .{};
    }
};

/// DMA Interaction Ledger
/// Timestamp-based tracking of DMC/OAM DMA conflicts
pub const InteractionLedger = struct {
    /// Timestamp when DMC DMA last became active (rdy_low = true)
    last_dmc_active_cycle: u64 = 0,

    /// Timestamp when DMC DMA last became inactive (rdy_low = false)
    last_dmc_inactive_cycle: u64 = 0,

    /// Timestamp when OAM DMA was paused by DMC
    /// Zero means "not currently paused"
    oam_pause_cycle: u64 = 0,

    /// Timestamp when OAM DMA resumed after DMC completion
    oam_resume_cycle: u64 = 0,

    /// Flag indicating OAM needs one alignment cycle after DMC completes
    needs_alignment_after_dmc: bool = false,

    /// Reset ledger to initial state
    pub fn reset(self: *InteractionLedger) void {
        self.* = .{};
    }
};

/// Consolidated DMA state
/// Owns all DMA subsystem state and outputs RDY line signal
pub const DmaState = struct {
    /// OAM DMA state ($4014 sprite DMA)
    oam: OamDma = .{},

    /// DMC DMA state (APU sample fetch)
    dmc: DmcDma = .{},

    /// Interaction tracking ledger
    interaction: InteractionLedger = .{},

    /// RDY line output signal (CPU input)
    /// false = CPU halted (DMA active)
    /// true = CPU running (DMA inactive)
    rdy_line: bool = true,

    /// Reset all DMA state
    pub fn reset(self: *DmaState) void {
        self.oam.reset();
        self.dmc.reset();
        self.interaction.reset();
        self.rdy_line = true;
    }
};
