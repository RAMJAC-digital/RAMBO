//! DMA Interaction Ledger - Timestamp-based tracking of DMC/OAM DMA conflicts
//!
//! This module implements the "isolated side effects" pattern following VBlankLedger.
//! All DMA interaction state is tracked through timestamps and captured snapshots,
//! allowing pure functions to make decisions based on historical data.
//!
//! ## Architecture Pattern: 3-Layer Separation
//!
//! 1. **DmaInteractionLedger** (this file) - Pure timestamp-based data structure
//! 2. **OamDma state** - Edge detection flags and phase machine
//! 3. **interaction.zig** - Pure logic functions for pause/resume
//!
//! ## Hardware Behavior Emulated
//!
//! When DMC DMA interrupts OAM DMA:
//! - DMC has higher priority and pauses OAM
//! - OAM state is captured at pause edge
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
    /// Zero means "never occurred" or "cleared"
    last_dmc_active_cycle: u64 = 0,

    /// Timestamp when DMC DMA last became inactive (rdy_low = false)
    /// Used to detect DMC completion edge
    last_dmc_inactive_cycle: u64 = 0,

    /// Timestamp when OAM DMA was paused by DMC
    /// Zero means "not currently paused" or "never paused"
    oam_pause_cycle: u64 = 0,

    /// Timestamp when OAM DMA resumed after DMC completion
    /// Used for edge detection and double-resume suppression
    oam_resume_cycle: u64 = 0,

    /// Snapshot of OAM DMA state captured at pause edge
    /// Only valid when oam_pause_cycle != 0
    interrupted_state: InterruptedState = .{},

    /// Duplication tracking flag
    /// Set when interrupted during read, cleared after duplication completes
    duplication_pending: bool = false,

    /// Captured state at moment of DMC interrupt
    pub const InterruptedState = struct {
        /// True if paused during read phase (even cycle)
        was_reading: bool = false,

        /// OAM offset at moment of pause (0-255)
        offset: u8 = 0,

        /// Byte that was being read when interrupted
        /// Only valid if was_reading = true
        byte_value: u8 = 0,

        /// OAM address at moment of pause
        oam_addr: u8 = 0,
    };

    /// Reset ledger to initial state
    ///
    /// Only mutation method (following VBlankLedger pattern).
    /// All other mutations happen via direct field assignment in EmulationState.
    pub fn reset(self: *DmaInteractionLedger) void {
        self.* = .{};
    }

    /// Debug: Format ledger state for logging
    pub fn format(
        self: *const DmaInteractionLedger,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("DmaInteractionLedger{{ " ++
            "dmc_active={d}, dmc_inactive={d}, " ++
            "oam_pause={d}, oam_resume={d}, " ++
            "interrupted=(reading={}, offset={d}, byte=0x{x:0>2}), " ++
            "dup_pending={} }}", .{
            self.last_dmc_active_cycle,
            self.last_dmc_inactive_cycle,
            self.oam_pause_cycle,
            self.oam_resume_cycle,
            self.interrupted_state.was_reading,
            self.interrupted_state.offset,
            self.interrupted_state.byte_value,
            self.duplication_pending,
        });
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
        .duplication_pending = true,
    };

    ledger.reset();

    // All fields should be zero/false after reset
    try testing.expectEqual(@as(u64, 0), ledger.last_dmc_active_cycle);
    try testing.expectEqual(@as(u64, 0), ledger.last_dmc_inactive_cycle);
    try testing.expectEqual(@as(u64, 0), ledger.oam_pause_cycle);
    try testing.expectEqual(@as(u64, 0), ledger.oam_resume_cycle);
    try testing.expect(!ledger.duplication_pending);
}
