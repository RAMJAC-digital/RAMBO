//! VBlank Timing Ledger
//!
//! Phase 4 Refactor: This is now a pure data struct.
//! It holds timestamps of critical VBlank-related events. The EmulationState
//! is responsible for all mutations. Logic for interpreting this state is
//! handled by consumers (e.g., the PPU register read function).

const std = @import("std");

pub const VBlankLedger = struct {
    /// Master clock cycle when VBlank was last SET (scanline 241, dot 1).
    last_set_cycle: u64 = 0,

    /// Master clock cycle when VBlank was last CLEARED by timing (scanline 261, dot 1).
    last_clear_cycle: u64 = 0,

    /// Master clock cycle of the last read from PPUSTATUS ($2002).
    last_read_cycle: u64 = 0,

    /// Master clock cycle of a $2002 read that raced with VBlank set (same cycle).
    /// When >= last_set_cycle, the race suppression/visibility applies for the
    /// remainder of that VBlank span.
    last_race_cycle: u64 = 0,

    /// Returns true if hardware VBlank is currently active (between set and clear)
    pub inline fn isActive(self: VBlankLedger) bool {
        return self.last_set_cycle > self.last_clear_cycle;
    }

    /// Returns true if the VBlank flag would read as 1 on the PPU bus
    /// (i.e., active AND not cleared by a $2002 read)
    /// Race conditions SUPPRESS the flag from being readable.
    pub inline fn isFlagVisible(self: VBlankLedger) bool {
        if (!self.isActive()) return false;
        if (self.hasRace()) return false;  // Race condition suppresses flag
        return self.last_set_cycle > self.last_read_cycle;
    }

    /// Returns true when a race read (same-cycle $2002 read) has occurred in the
    /// current VBlank span and its effects are still active.
    pub inline fn hasRace(self: VBlankLedger) bool {
        return self.last_race_cycle >= self.last_set_cycle;
    }

    /// Resets all timestamps to their initial state.
    pub fn reset(self: *VBlankLedger) void {
        self.last_set_cycle = 0;
        self.last_clear_cycle = 0;
        self.last_read_cycle = 0;
        self.last_race_cycle = 0;
    }
};

test "VBlankLedger reset" {
    var ledger: VBlankLedger = .{
        .last_set_cycle = 123,
        .last_clear_cycle = 456,
        .last_read_cycle = 789,
    };
    ledger.reset();
    try std.testing.expectEqual(@as(u64, 0), ledger.last_set_cycle);
    try std.testing.expectEqual(@as(u64, 0), ledger.last_clear_cycle);
    try std.testing.expectEqual(@as(u64, 0), ledger.last_read_cycle);
}
