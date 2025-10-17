//! DMA Interaction Ledger - Timestamp-based tracking of DMC/OAM DMA conflicts
//!
//! Pure data structure following VBlankLedger pattern.
//! Tracks DMA interaction through timestamps only.
//!
//! ## Hardware Behavior Emulated
//!
//! When DMC DMA interrupts OAM DMA:
//! - DMC has higher priority and pauses OAM
//! - OAM state is captured at pause moment
//! - OAM resumes when DMC completes
//! - If interrupted during read: byte duplicates on resume (hardware bug)
//!
//! Reference: nesdev.org/wiki/APU_DMC#DMA_conflict

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

    /// Captured state at moment of pause (flattened fields)
    paused_during_read: bool = false,
    paused_at_offset: u8 = 0,
    paused_byte_value: u8 = 0,
    paused_oam_addr: u8 = 0,

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
        .paused_during_read = true,
        .paused_at_offset = 42,
        .paused_byte_value = 0xFF,
    };

    ledger.reset();

    // All fields should be zero/false after reset
    try testing.expectEqual(@as(u64, 0), ledger.last_dmc_active_cycle);
    try testing.expectEqual(@as(u64, 0), ledger.last_dmc_inactive_cycle);
    try testing.expectEqual(@as(u64, 0), ledger.oam_pause_cycle);
    try testing.expectEqual(@as(u64, 0), ledger.oam_resume_cycle);
    try testing.expect(!ledger.paused_during_read);
    try testing.expectEqual(@as(u8, 0), ledger.paused_at_offset);
}
