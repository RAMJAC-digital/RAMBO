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

    /// Master clock cycle when VBlank flag set should be PREVENTED.
    /// Set when $2002 is read at scanline 241, dot 0 (one cycle before VBlank set).
    /// When current cycle equals this value, the flag set at 241:1 is skipped.
    /// Per Mesen2 NesPpu.cpp:590-592, 1340-1344: _preventVblFlag pattern.
    /// Hardware: "Reading one PPU clock before...never sets the flag" (nesdev.org)
    prevent_vbl_set_cycle: u64 = 0,

    /// Returns true if hardware VBlank is currently active (between set and clear)
    pub inline fn isActive(self: VBlankLedger) bool {
        return self.last_set_cycle > self.last_clear_cycle;
    }

    /// Returns true if the VBlank flag would read as 1 on the PPU bus
    /// (i.e., active AND not cleared by a $2002 read)
    ///
    /// Hardware behavior per Mesen2 NesPpu.cpp:344 - UpdateStatusFlag() clears
    /// VBlank flag unconditionally on every $2002 read. NMI line is also cleared.
    pub inline fn isFlagVisible(self: VBlankLedger) bool {
        // 1. VBlank span not active?
        if (!self.isActive()) return false;

        // 2. Has any $2002 read occurred since VBlank set?
        // Per BUG #1 fix: last_read_cycle always updated on $2002 read
        if (self.last_read_cycle >= self.last_set_cycle) return false;

        // 3. Flag is set and hasn't been read yet
        return true;
    }

    /// Resets all timestamps to their initial state.
    pub fn reset(self: *VBlankLedger) void {
        self.last_set_cycle = 0;
        self.last_clear_cycle = 0;
        self.last_read_cycle = 0;
        self.prevent_vbl_set_cycle = 0;
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
