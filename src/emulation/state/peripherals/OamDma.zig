//! OAM DMA state for emulation runtime
//! Cycle-accurate DMA transfer from CPU RAM to PPU OAM
//! Follows microstep pattern for hardware accuracy

/// OAM DMA state
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
