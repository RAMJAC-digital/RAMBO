//! OAM DMA state for emulation runtime
//! Cycle-accurate DMA transfer from CPU RAM to PPU OAM
//! Follows microstep pattern for hardware accuracy

const std = @import("std");

// Debug flag (should match dma/logic.zig)
const DEBUG_DMA = false;

/// OAM DMA execution phase (explicit state machine)
///
/// Replaces implicit state tracking with clear enumeration.
/// All transitions are explicit and documented.
pub const OamDmaPhase = enum {
    /// Not active
    idle,

    /// Alignment wait cycle (triggered on odd CPU cycle)
    /// Next: -> reading (cycle 0 effective)
    aligning,

    /// Read cycle (even effective cycles: 0, 2, 4, ...)
    /// Reading byte from CPU RAM into temp_value
    /// Next: -> writing
    reading,

    /// Write cycle (odd effective cycles: 1, 3, 5, ...)
    /// Writing temp_value to PPU OAM
    /// Next: -> reading (next byte) or -> idle (complete)
    writing,

    /// Paused by DMC DMA during read phase
    /// State captured in DmaInteractionLedger
    /// Next: -> resuming_with_duplication (if DMC completes)
    paused_during_read,

    /// Paused by DMC DMA during write phase
    /// No byte duplication needed
    /// Next: -> resuming_normal (if DMC completes)
    paused_during_write,

    /// Resuming after DMC, with byte duplication
    /// Write interrupted byte, then re-read same offset
    /// Next: -> reading
    resuming_with_duplication,

    /// Resuming after DMC, normal continuation
    /// No special handling needed
    /// Next: -> reading or -> writing (continue where left off)
    resuming_normal,
};

/// OAM DMA state
pub const OamDma = struct {
    /// DMA active flag
    active: bool = false,

    /// Current execution phase (explicit state machine)
    phase: OamDmaPhase = .idle,

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
        self.phase = if (on_odd_cycle) .aligning else .reading;
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

// Export phase enum at module level for convenience
pub const Phase = OamDmaPhase;
