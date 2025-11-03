//! PPU Timing Constants and Scanline Architecture
//!
//! Critical for cycle-accurate emulation required by:
//! - Light gun games (Duck Hunt, Hogan's Alley, Gum Shoe)
//! - Mid-frame palette/scroll changes
//! - Sprite 0 hit timing
//! - IRQ timing (MMC3 scanline counter)
//!
//! References:
//! - NESDev Wiki: https://www.nesdev.org/wiki/PPU_rendering
//! - Visual 2C02: http://www.visual6502.org/wiki/index.php?title=Visual_2C02

const std = @import("std");
const Config = @import("../config/Config.zig");

/// NTSC PPU (RP2C02G) Timing Constants
pub const NTSC = struct {
    /// PPU cycles per scanline
    /// Each PPU cycle is 1/3 of a CPU cycle
    pub const CYCLES_PER_SCANLINE: u16 = 341;

    /// Scanlines per frame
    pub const SCANLINES_PER_FRAME: u16 = 262;

    /// Total PPU cycles per frame
    pub const CYCLES_PER_FRAME: u32 = @as(u32, CYCLES_PER_SCANLINE) * @as(u32, SCANLINES_PER_FRAME); // 89,342

    /// Frame rate in Hz
    pub const FRAME_RATE: f64 = 60.0988;

    /// Frame duration in microseconds
    pub const FRAME_DURATION_US: u64 = 16_639;

    /// Frame duration in nanoseconds (for high-precision timing)
    pub const FRAME_DURATION_NS: u64 = 16_639_267;

    /// CPU cycles per frame (PPU runs 3x faster than CPU)
    pub const CPU_CYCLES_PER_FRAME: u32 = CYCLES_PER_FRAME / 3; // 29,780.67

    /// Scanline ranges (min/max inclusive)
    pub const VISIBLE_SCANLINE_START: u16 = 0;
    pub const VISIBLE_SCANLINE_END: u16 = 239;
    pub const POST_RENDER_SCANLINE: u16 = 240;
    pub const VBLANK_SCANLINE_START: u16 = 241;
    pub const VBLANK_SCANLINE_END: u16 = 260;
    pub const PRE_RENDER_SCANLINE: i16 = -1;

    /// Horizontal timing (cycles within scanline, 1-indexed for visible)
    pub const VISIBLE_DOT_START: u16 = 1;
    pub const VISIBLE_DOT_END: u16 = 256;
    pub const HBLANK_DOT_START: u16 = 257;
    pub const HBLANK_DOT_END: u16 = 340;

    /// VBlank flag timing
    pub const VBLANK_SET_CYCLE: u16 = 1;      // Cycle 1 of scanline 241
    pub const VBLANK_CLEAR_CYCLE: u16 = 1;    // Cycle 1 of pre-render line

    /// Sprite 0 hit can occur during visible scanlines (0-239)
    pub const SPRITE_0_HIT_SCANLINE_START: u16 = 0;
    pub const SPRITE_0_HIT_SCANLINE_END: u16 = 239;
};

/// PAL PPU (RP2C07) Timing Constants
pub const PAL = struct {
    pub const CYCLES_PER_SCANLINE: u16 = 341;
    pub const SCANLINES_PER_FRAME: u16 = 312;
    pub const CYCLES_PER_FRAME: u32 = @as(u32, CYCLES_PER_SCANLINE) * @as(u32, SCANLINES_PER_FRAME); // 106,392
    pub const FRAME_RATE: f64 = 50.0070;
    pub const FRAME_DURATION_US: u64 = 19_997;
    pub const FRAME_DURATION_NS: u64 = 19_997_200;
    pub const CPU_CYCLES_PER_FRAME: u32 = CYCLES_PER_FRAME / 3; // 35,464

    pub const VISIBLE_SCANLINE_START: u16 = 0;
    pub const VISIBLE_SCANLINE_END: u16 = 239;
    pub const POST_RENDER_SCANLINE: u16 = 240;
    pub const VBLANK_SCANLINE_START: u16 = 241;
    pub const VBLANK_SCANLINE_END: u16 = 310;
    pub const PRE_RENDER_SCANLINE: u16 = 311;
};

/// Scanline type classification
pub const ScanlineType = enum {
    /// Scanlines 0-239: Visible rendering
    visible,
    /// Scanline 240: Post-render (idle)
    post_render,
    /// Scanlines 241-260 (NTSC) or 241-310 (PAL): VBlank period
    vblank,
    /// Scanline 261 (NTSC) or 311 (PAL): Pre-render (prepare for next frame)
    pre_render,

    /// Classify scanline by number
    pub fn classify(scanline: u16, region: Config.VideoRegion) ScanlineType {
        return switch (region) {
            .ntsc => blk: {
                if (scanline <= NTSC.VISIBLE_SCANLINE_END) break :blk .visible;
                if (scanline == NTSC.POST_RENDER_SCANLINE) break :blk .post_render;
                if (scanline >= NTSC.VBLANK_SCANLINE_START and scanline <= NTSC.VBLANK_SCANLINE_END) break :blk .vblank;
                if (scanline == NTSC.PRE_RENDER_SCANLINE) break :blk .pre_render;
                unreachable;
            },
            .pal => blk: {
                if (scanline <= PAL.VISIBLE_SCANLINE_END) break :blk .visible;
                if (scanline == PAL.POST_RENDER_SCANLINE) break :blk .post_render;
                if (scanline >= PAL.VBLANK_SCANLINE_START and scanline <= PAL.VBLANK_SCANLINE_END) break :blk .vblank;
                if (scanline == PAL.PRE_RENDER_SCANLINE) break :blk .pre_render;
                unreachable;
            },
        };
    }
};

/// PPU-CPU clock ratio
/// PPU runs at 3x CPU speed (1 CPU cycle = 3 PPU cycles)
pub const PPU_TO_CPU_RATIO: u8 = 3;

/// Helper to convert CPU cycles to PPU cycles
pub inline fn cpuToPpuCycles(cpu_cycles: u64) u64 {
    return cpu_cycles * PPU_TO_CPU_RATIO;
}

/// Helper to convert PPU cycles to CPU cycles
pub inline fn ppuToCpuCycles(ppu_cycles: u64) u64 {
    return ppu_cycles / PPU_TO_CPU_RATIO;
}

/// Scanline position for light gun and precise timing
pub const ScanlinePosition = struct {
    scanline: u16,  // 0-261 (NTSC) or 0-311 (PAL)
    cycle: u16,     // 0-340

    /// Check if position is within visible rendering area
    pub fn isVisible(self: ScanlinePosition, region: Config.VideoRegion) bool {
        const in_visible_scanline = switch (region) {
            .ntsc => self.scanline <= NTSC.VISIBLE_SCANLINE_END,
            .pal => self.scanline <= PAL.VISIBLE_SCANLINE_END,
        };
        const in_visible_cycle = self.cycle >= NTSC.VISIBLE_DOT_START and self.cycle <= NTSC.VISIBLE_DOT_END;
        return in_visible_scanline and in_visible_cycle;
    }

    /// Get pixel X coordinate (0-255) if visible, null otherwise
    pub fn getPixelX(self: ScanlinePosition) ?u8 {
        if (self.cycle >= NTSC.VISIBLE_DOT_START and self.cycle <= NTSC.VISIBLE_DOT_END) {
            return @intCast(self.cycle - 1);
        }
        return null;
    }

    /// Get pixel Y coordinate (0-239) if visible, null otherwise
    pub fn getPixelY(self: ScanlinePosition, region: Config.VideoRegion) ?u8 {
        const max_visible = switch (region) {
            .ntsc => NTSC.VISIBLE_SCANLINE_END,
            .pal => PAL.VISIBLE_SCANLINE_END,
        };
        if (self.scanline <= max_visible) {
            return @intCast(self.scanline);
        }
        return null;
    }

    /// Convert to absolute PPU cycle count in frame
    pub fn toAbsoluteCycle(self: ScanlinePosition) u32 {
        return @as(u32, self.scanline) * 341 + self.cycle;
    }

    /// Create from absolute PPU cycle count
    pub fn fromAbsoluteCycle(cycle: u32) ScanlinePosition {
        return .{
            .scanline = @intCast(cycle / 341),
            .cycle = @intCast(cycle % 341),
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "timing: NTSC constants" {
    try testing.expectEqual(@as(u16, 341), NTSC.CYCLES_PER_SCANLINE);
    try testing.expectEqual(@as(u16, 262), NTSC.SCANLINES_PER_FRAME);
    try testing.expectEqual(@as(u32, 89_342), NTSC.CYCLES_PER_FRAME);
    try testing.expectApproxEqAbs(@as(f64, 60.0988), NTSC.FRAME_RATE, 0.0001);
}

test "timing: PAL constants" {
    try testing.expectEqual(@as(u16, 341), PAL.CYCLES_PER_SCANLINE);
    try testing.expectEqual(@as(u16, 312), PAL.SCANLINES_PER_FRAME);
    try testing.expectEqual(@as(u32, 106_392), PAL.CYCLES_PER_FRAME);
    try testing.expectApproxEqAbs(@as(f64, 50.0070), PAL.FRAME_RATE, 0.0001);
}

test "timing: scanline classification NTSC" {
    try testing.expectEqual(ScanlineType.visible, ScanlineType.classify(0, .ntsc));
    try testing.expectEqual(ScanlineType.visible, ScanlineType.classify(239, .ntsc));
    try testing.expectEqual(ScanlineType.post_render, ScanlineType.classify(240, .ntsc));
    try testing.expectEqual(ScanlineType.vblank, ScanlineType.classify(241, .ntsc));
    try testing.expectEqual(ScanlineType.vblank, ScanlineType.classify(260, .ntsc));
    try testing.expectEqual(ScanlineType.pre_render, ScanlineType.classify(261, .ntsc));
}

test "timing: PPU-CPU cycle conversion" {
    try testing.expectEqual(@as(u64, 30), cpuToPpuCycles(10));
    try testing.expectEqual(@as(u64, 10), ppuToCpuCycles(30));
}

test "timing: ScanlinePosition pixel coordinates" {
    const pos1 = ScanlinePosition{ .scanline = 100, .cycle = 50 };
    try testing.expect(pos1.isVisible(.ntsc));
    try testing.expectEqual(@as(u8, 49), pos1.getPixelX().?);
    try testing.expectEqual(@as(u8, 100), pos1.getPixelY(.ntsc).?);

    const pos2 = ScanlinePosition{ .scanline = 241, .cycle = 100 }; // VBlank
    try testing.expect(!pos2.isVisible(.ntsc));
    try testing.expectEqual(@as(?u8, null), pos2.getPixelY(.ntsc));
}

test "timing: ScanlinePosition absolute cycle conversion" {
    const pos = ScanlinePosition{ .scanline = 10, .cycle = 50 };
    const abs_cycle = pos.toAbsoluteCycle();
    try testing.expectEqual(@as(u32, 10 * 341 + 50), abs_cycle);

    const pos2 = ScanlinePosition.fromAbsoluteCycle(abs_cycle);
    try testing.expectEqual(@as(u16, 10), pos2.scanline);
    try testing.expectEqual(@as(u16, 50), pos2.cycle);
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
