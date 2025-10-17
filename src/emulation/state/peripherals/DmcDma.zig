//! DMC DMA state for emulation runtime
//! Simulates RDY line (CPU stall) during DMC sample fetch
//! NTSC (2A03) only: Causes controller/PPU register corruption

/// DMC DMA state
pub const DmcDma = struct {
    /// RDY line active (CPU stalled)
    rdy_low: bool = false,

    /// Completion signal (set when transfer finishes)
    /// execution.zig clears this AND rdy_low atomically
    /// Pattern: External state management (like NMI/VBlank)
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
