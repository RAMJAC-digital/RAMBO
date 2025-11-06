//! VBlank Timing Ledger
//!
//! Separates VBlank FLAG (readable bit 7 of $2002) from VBlank SPAN (hardware timing window).
//! This distinction is critical for correct NMI behavior:
//! - VBlank SPAN: scanline 241 → pre-render (hardware timing window)
//! - VBlank FLAG: readable state, can be cleared by $2002 read while span is active
//!
//! Hardware reference: Mesen2 _statusFlags.VerticalBlank (flag) vs scanline range (span)
//! The EmulationState is responsible for all mutations.

const std = @import("std");

pub const VBlankLedger = struct {
    /// VBlank flag state (bit 7 of $2002)
    /// Set at scanline 241 dot 1, cleared by $2002 read or pre-render scanline
    /// Matches Mesen2's _statusFlags.VerticalBlank
    vblank_flag: bool = false,

    /// VBlank span active (hardware timing window)
    /// Active from scanline 241 dot 1 → pre-render scanline
    /// Can be true while vblank_flag is false (after $2002 read)
    vblank_span_active: bool = false,

    /// Master clock cycle when VBlank was last SET (scanline 241, dot 1).
    /// Kept for debugging/race detection
    last_set_cycle: u64 = 0,

    /// Master clock cycle when VBlank was last CLEARED by timing (scanline 261, dot 1).
    /// Kept for debugging
    last_clear_cycle: u64 = 0,

    /// Master clock cycle of the last read from PPUSTATUS ($2002).
    /// Kept for debugging
    last_read_cycle: u64 = 0,

    /// Master clock cycle when VBlank flag set should be PREVENTED.
    /// 0 means no prevention is scheduled. Non-zero values contain the exact
    /// master cycle that must block the next set.
    prevent_vbl_set_cycle: u64 = 0,

    /// Returns true if VBlank flag is set (for $2002 reads and NMI logic)
    /// This is the actual readable flag state, not the timing window
    /// Cleared by $2002 reads, can be false while span is active
    pub inline fn isFlagSet(self: VBlankLedger) bool {
        return self.vblank_flag;
    }

    /// Returns true if VBlank span is active (for timing/debugging)
    /// Hardware timing window from scanline 241 → pre-render
    /// Can be true while flag is false (after $2002 read)
    pub inline fn isSpanActive(self: VBlankLedger) bool {
        return self.vblank_span_active;
    }

    /// Resets all state to initial values
    pub fn reset(self: *VBlankLedger) void {
        self.vblank_flag = false;
        self.vblank_span_active = false;
        self.last_set_cycle = 0;
        self.last_clear_cycle = 0;
        self.last_read_cycle = 0;
        self.prevent_vbl_set_cycle = 0;
    }
};

test "VBlankLedger reset" {
    var ledger: VBlankLedger = .{
        .vblank_flag = true,
        .vblank_span_active = true,
        .last_set_cycle = 123,
        .last_clear_cycle = 456,
        .last_read_cycle = 789,
    };
    ledger.reset();
    try std.testing.expect(!ledger.vblank_flag);
    try std.testing.expect(!ledger.vblank_span_active);
    try std.testing.expectEqual(@as(u64, 0), ledger.last_set_cycle);
    try std.testing.expectEqual(@as(u64, 0), ledger.last_clear_cycle);
    try std.testing.expectEqual(@as(u64, 0), ledger.last_read_cycle);
}
