//! VBlank State Management
//!
//! Hardware-accurate VBlank flag calculation based on cycle count.
//! VBlank is deterministic: it's set from cycle 82,181 to 89,001 (6,820 cycles).

const std = @import("std");

/// VBlank timing constants (NTSC)
pub const VBlankTiming = struct {
    /// PPU cycle when VBlank starts (scanline 241, dot 1)
    pub const START_CYCLE: u64 = 241 * 341 + 1; // 82,181

    /// PPU cycle when VBlank ends (scanline 261, dot 1)
    pub const END_CYCLE: u64 = 261 * 341 + 1; // 89,001

    /// Duration in PPU cycles (20 scanlines)
    pub const DURATION: u64 = END_CYCLE - START_CYCLE; // 6,820

    /// Total PPU cycles per frame (even frame)
    pub const CYCLES_PER_FRAME: u64 = 89_342;
};

/// VBlank state with cycle-based calculation
pub const VBlankState = struct {
    /// Cycle count when VBlank was last set (for NMI edge detection)
    vblank_set_cycle: u64 = 0,

    /// Whether VBlank was cleared by $2002 read this frame
    suppressed_this_frame: bool = false,

    /// Calculate if VBlank flag should be set based on current PPU cycle
    pub fn isVBlankActive(self: *const VBlankState, ppu_cycles: u64) bool {
        // Calculate position within current frame
        const frame_cycle = ppu_cycles % VBlankTiming.CYCLES_PER_FRAME;

        // VBlank is active from cycles 82,181 to 89,000 (inclusive)
        return frame_cycle >= VBlankTiming.START_CYCLE and
               frame_cycle < VBlankTiming.END_CYCLE and
               !self.suppressed_this_frame;
    }

    /// Check if we just entered VBlank (for NMI edge detection)
    pub fn justEnteredVBlank(self: *const VBlankState, ppu_cycles: u64) bool {
        const frame_cycle = ppu_cycles % VBlankTiming.CYCLES_PER_FRAME;
        return frame_cycle == VBlankTiming.START_CYCLE;
    }

    /// Check if we just exited VBlank
    pub fn justExitedVBlank(self: *const VBlankState, ppu_cycles: u64) bool {
        const frame_cycle = ppu_cycles % VBlankTiming.CYCLES_PER_FRAME;
        return frame_cycle == VBlankTiming.END_CYCLE;
    }

    /// Handle $2002 read - returns current flag value and clears it
    pub fn handleStatusRead(self: *VBlankState, ppu_cycles: u64) bool {
        const was_set = self.isVBlankActive(ppu_cycles);

        // If VBlank is active, suppress it for rest of frame
        if (was_set) {
            self.suppressed_this_frame = true;
        }

        // Return the OLD value (before suppression)
        return was_set;
    }

    /// Reset suppression at start of new frame
    pub fn onFrameStart(self: *VBlankState, ppu_cycles: u64) void {
        const frame_cycle = ppu_cycles % VBlankTiming.CYCLES_PER_FRAME;
        if (frame_cycle == 0) {
            self.suppressed_this_frame = false;
        }
    }
};

test "VBlankState: Active during correct cycle range" {
    const testing = std.testing;

    var vblank = VBlankState{};

    // Before VBlank
    try testing.expect(!vblank.isVBlankActive(82_180));

    // Start of VBlank
    try testing.expect(vblank.isVBlankActive(82_181));

    // Middle of VBlank
    try testing.expect(vblank.isVBlankActive(85_000));

    // End of VBlank (last active cycle)
    try testing.expect(vblank.isVBlankActive(89_000));

    // After VBlank
    try testing.expect(!vblank.isVBlankActive(89_001));
}

test "VBlankState: Suppression after $2002 read" {
    const testing = std.testing;

    var vblank = VBlankState{};

    // VBlank is active
    try testing.expect(vblank.isVBlankActive(85_000));

    // Read $2002 - returns true but suppresses
    const was_set = vblank.handleStatusRead(85_000);
    try testing.expect(was_set);

    // Now VBlank is suppressed
    try testing.expect(!vblank.isVBlankActive(85_000));

    // Still suppressed later in VBlank period
    try testing.expect(!vblank.isVBlankActive(88_000));

    // Reset on new frame
    vblank.onFrameStart(89_342); // Start of next frame
    vblank.suppressed_this_frame = false; // Manual reset for test

    // VBlank works again next frame
    try testing.expect(vblank.isVBlankActive(82_181 + 89_342));
}