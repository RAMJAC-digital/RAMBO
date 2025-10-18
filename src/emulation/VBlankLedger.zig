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

    /// If true, a read of $2002 occurred on the exact cycle VBlank was set.
    /// Hardware keeps the VBlank flag visible for subsequent reads in this frame.
    /// Cleared when VBlank is cleared by timing (pre-render line).
    race_hold: bool = false,

    /// Returns true if hardware VBlank is currently active (between set and clear)
    pub inline fn isActive(self: VBlankLedger) bool {
        return self.last_set_cycle > self.last_clear_cycle;
    }

    /// Returns true if the VBlank flag would read as 1 on the PPU bus
    /// (i.e., active AND not cleared by a $2002 read, or held by the race condition)
    pub inline fn isFlagVisible(self: VBlankLedger) bool {
        if (!self.isActive()) return false;
        return self.race_hold or (self.last_set_cycle > self.last_read_cycle);
    }

    /// Resets all timestamps to their initial state.
    pub fn reset(self: *VBlankLedger) void {
        self.last_set_cycle = 0;
        self.last_clear_cycle = 0;
        self.last_read_cycle = 0;
        self.race_hold = false;
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
