//! DMA Interaction Ledger - Timestamp-based tracking of DMC/OAM DMA conflicts
//!
//! Pure data structure following VBlankLedger pattern.
//! Tracks DMA interaction through timestamps only.
//!
//! ## Hardware Behavior Emulated
//!
//! When DMC DMA interrupts OAM DMA:
//! - DMC has higher priority (pauses OAM during halt and read cycles)
//! - OAM continues during DMC dummy/alignment cycles (time-sharing)
//! - OAM needs one extra alignment cycle after DMC completes
//! - No byte duplication (OAM reads sequential addresses)
//!
//! Reference: nesdev.org/wiki/DMA#DMC_DMA_during_OAM_DMA

const std = @import("std");

/// Timestamp-based ledger for DMC/OAM DMA interaction tracking
///
/// Follows VBlankLedger pattern: pure data structure with no embedded logic.
/// All state interpretation happens through comparison of timestamps.
pub const DmaInteractionLedger = struct {
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
    /// Per nesdev.org wiki: OAM requires extra alignment cycle to get back into get/put rhythm
    needs_alignment_after_dmc: bool = false,

    /// Reset ledger to initial state
    ///
    /// Only mutation method (following VBlankLedger pattern).
    /// All other mutations happen via direct field assignment in EmulationState.
    pub fn reset(self: *DmaInteractionLedger) void {
        self.* = .{};
    }
};

// Unit tests
test "DmaInteractionLedger: reset" {
    const testing = std.testing;

    var ledger = DmaInteractionLedger{
        .last_dmc_active_cycle = 123,
        .last_dmc_inactive_cycle = 456,
        .oam_pause_cycle = 789,
        .oam_resume_cycle = 1011,
        .needs_alignment_after_dmc = true,
    };

    ledger.reset();

    // All fields should be zero/false after reset
    try testing.expectEqual(@as(u64, 0), ledger.last_dmc_active_cycle);
    try testing.expectEqual(@as(u64, 0), ledger.last_dmc_inactive_cycle);
    try testing.expectEqual(@as(u64, 0), ledger.oam_pause_cycle);
    try testing.expectEqual(@as(u64, 0), ledger.oam_resume_cycle);
    try testing.expect(!ledger.needs_alignment_after_dmc);
}
