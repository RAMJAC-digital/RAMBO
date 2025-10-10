//! Master Clock - Single Source of Truth for NES Timing
//!
//! Hardware Reference (nesdev.org):
//! - NTSC NES uses 21.477272 MHz master oscillator
//! - CPU clock = 21.477272 MHz ÷ 12 = 1.789773 MHz
//! - PPU clock = 21.477272 MHz ÷ 4 = 5.369318 MHz
//! - Ratio: 3 PPU cycles per 1 CPU cycle
//!
//! Frame Timing (NTSC):
//! - 341 dots per scanline
//! - 262 scanlines per frame (0-261)
//! - Even frames: 341 × 262 = 89,342 PPU cycles
//! - Odd frames with rendering: 89,341 PPU cycles (skip dot 0 of scanline 0)
//!
//! This module provides the ONLY timing counter for the emulator.
//! All other timing (scanline, dot, frame, CPU cycles) is derived on demand.
//! Components NEVER advance timing - only the master clock advances.
//!
//! Benefits:
//! - Single source of truth (no timing state divergence)
//! - Externally controllable (emulation thread controls speed)
//! - Components are pure (no timing mutation)
//! - Hardware-accurate (models single crystal oscillator)

const std = @import("std");

/// Master clock for NES emulation
/// Tracks PPU cycles as the single source of truth
/// All other timing derived from this counter
pub const MasterClock = struct {
    /// Total PPU cycles elapsed since power-on
    /// This is the ONLY timing counter in the entire emulator
    /// Hardware correspondence: Counts cycles from 21.477272 MHz ÷ 4 oscillator
    ppu_cycles: u64 = 0,

    /// Speed control multiplier for emulation
    /// 1.0 = normal speed (60 FPS)
    /// 2.0 = 2× fast forward
    /// 0.5 = half speed (slow motion)
    /// Note: This doesn't affect timing accuracy, only controls external tick rate
    speed_multiplier: f64 = 1.0,

    /// Initialize clock to power-on state
    pub fn init() MasterClock {
        return .{};
    }

    /// Advance clock by N PPU cycles
    /// This is the ONLY function that mutates timing state
    /// Called by EmulationState.tick() to advance emulation
    ///
    /// Hardware: Each call represents N cycles of the 5.369318 MHz PPU clock
    pub fn advance(self: *MasterClock, cycles: u64) void {
        self.ppu_cycles +%= cycles; // Wrapping add (handles overflow after ~109 years at 60 FPS)
    }

    /// Get current scanline (0-261)
    /// Hardware: NES has 262 scanlines per frame
    /// - Scanlines 0-239: Visible scanlines (240 total)
    /// - Scanline 240: Post-render (idle)
    /// - Scanlines 241-260: VBlank (20 scanlines)
    /// - Scanline 261: Pre-render (prepares for next frame)
    ///
    /// Derivation: (total_cycles / 341) mod 262
    /// Each scanline is 341 PPU cycles (dots 0-340)
    pub fn scanline(self: MasterClock) u16 {
        const cycles_per_scanline = 341;
        const scanlines_per_frame = 262;
        return @intCast((self.ppu_cycles / cycles_per_scanline) % scanlines_per_frame);
    }

    /// Get current dot within scanline (0-340)
    /// Hardware: NES PPU renders 341 dots per scanline
    /// - Dots 0-255: Visible pixels (256 total)
    /// - Dots 256-340: HBlank and tile prefetch (85 dots)
    ///
    /// Derivation: total_cycles mod 341
    pub fn dot(self: MasterClock) u16 {
        const cycles_per_scanline = 341;
        return @intCast(self.ppu_cycles % cycles_per_scanline);
    }

    /// Get current frame number
    /// Hardware: NTSC runs at 60.0988 Hz (slightly faster than 60 Hz)
    /// - Even frames: 89,342 PPU cycles
    /// - Odd frames with rendering: 89,341 PPU cycles (1 cycle shorter)
    ///
    /// Note: This calculation assumes all frames are 89,342 cycles (even frames)
    /// The actual frame count may be slightly off due to odd frame skipping,
    /// but this is sufficient for frame counting purposes.
    ///
    /// Derivation: total_cycles / 89342 (approximate)
    pub fn frame(self: MasterClock) u64 {
        const cycles_per_frame = 89342; // Even frame length
        return self.ppu_cycles / cycles_per_frame;
    }

    /// Get total CPU cycles elapsed
    /// Hardware: CPU runs at 1/3 the speed of PPU (1.789773 MHz vs 5.369318 MHz)
    /// - 1 CPU cycle = 3 PPU cycles (exact ratio)
    ///
    /// Derivation: total_ppu_cycles / 3
    ///
    /// Note: Returns integer division. The NES doesn't have fractional CPU cycles,
    /// but the relationship isn't always exact due to timing quirks. For example,
    /// a frame has 89,342 PPU cycles, which is 29,780.67 CPU cycles. The 0.67
    /// accumulates over multiple frames.
    pub fn cpuCycles(self: MasterClock) u64 {
        return self.ppu_cycles / 3;
    }

    /// Check if current cycle is a CPU tick
    /// Hardware: CPU ticks every 3rd PPU cycle
    /// - PPU cycle 0, 3, 6, 9... → CPU ticks
    /// - PPU cycle 1, 2, 4, 5... → CPU idle
    ///
    /// Used by EmulationState.tick() to determine when to tick CPU
    pub fn isCpuTick(self: MasterClock) bool {
        return (self.ppu_cycles % 3) == 0;
    }

    /// Check if current cycle is an APU tick
    /// Hardware: APU is synchronized with CPU (same clock divider)
    /// - APU ticks whenever CPU ticks
    ///
    /// Alias for isCpuTick() for clarity
    pub fn isApuTick(self: MasterClock) bool {
        return self.isCpuTick();
    }

    /// Check if current frame is odd
    /// Hardware: Odd frames have special behavior (skip dot 0 when rendering enabled)
    ///
    /// Used for odd frame skip detection
    pub fn isOddFrame(self: MasterClock) bool {
        return (self.frame() & 1) == 1;
    }

    /// Get position within current frame (0-89341)
    /// Useful for frame-relative timing
    ///
    /// Note: Returns position assuming even frame (89,342 cycles)
    /// On odd frames with rendering, max value is 89,340 (1 cycle shorter)
    pub fn framePosition(self: MasterClock) u32 {
        const cycles_per_frame = 89342;
        return @intCast(self.ppu_cycles % cycles_per_frame);
    }

    /// Calculate exact scanline and dot from current cycle count
    /// Returns both values efficiently without double computation
    ///
    /// Useful when both values are needed simultaneously
    pub fn scanlineAndDot(self: MasterClock) struct { scanline: u16, dot: u16 } {
        const cycles_per_scanline = 341;
        const scanlines_per_frame = 262;

        const total_scanlines = self.ppu_cycles / cycles_per_scanline;
        const current_scanline = @as(u16, @intCast(total_scanlines % scanlines_per_frame));
        const current_dot = @as(u16, @intCast(self.ppu_cycles % cycles_per_scanline));

        return .{
            .scanline = current_scanline,
            .dot = current_dot,
        };
    }

    /// Reset clock to power-on state
    /// Used when emulator is reset or ROM is loaded
    pub fn reset(self: *MasterClock) void {
        self.ppu_cycles = 0;
        // Note: speed_multiplier is NOT reset (user preference persists)
    }

    /// Set speed multiplier for emulation
    /// Controls how fast the external thread ticks the emulator
    ///
    /// Values:
    /// - 1.0: Normal speed (60 FPS)
    /// - 2.0: 2× fast forward
    /// - 0.5: Half speed (slow motion)
    /// - 0.0: Paused (no ticking)
    ///
    /// Note: This doesn't affect timing accuracy, only controls how often
    /// the emulation thread calls tick(). The clock still advances by 1 cycle
    /// per tick, but ticks happen faster/slower.
    pub fn setSpeed(self: *MasterClock, multiplier: f64) void {
        self.speed_multiplier = multiplier;
    }

    /// Get current speed multiplier
    pub fn getSpeed(self: MasterClock) f64 {
        return self.speed_multiplier;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "MasterClock: initialization" {
    const clock = MasterClock.init();

    try testing.expectEqual(@as(u64, 0), clock.ppu_cycles);
    try testing.expectEqual(@as(f64, 1.0), clock.speed_multiplier);
}

test "MasterClock: advance cycles" {
    var clock = MasterClock.init();

    clock.advance(10);
    try testing.expectEqual(@as(u64, 10), clock.ppu_cycles);

    clock.advance(5);
    try testing.expectEqual(@as(u64, 15), clock.ppu_cycles);
}

test "MasterClock: scanline derivation" {
    var clock = MasterClock.init();

    // Scanline 0, dot 0
    try testing.expectEqual(@as(u16, 0), clock.scanline());

    // Advance to end of scanline 0 (dot 340)
    clock.advance(340);
    try testing.expectEqual(@as(u16, 0), clock.scanline());

    // Advance to scanline 1, dot 0
    clock.advance(1);
    try testing.expectEqual(@as(u16, 1), clock.scanline());

    // Advance to scanline 261 (pre-render)
    clock.ppu_cycles = 261 * 341;
    try testing.expectEqual(@as(u16, 261), clock.scanline());

    // Wrap to scanline 0 (next frame)
    clock.ppu_cycles = 262 * 341;
    try testing.expectEqual(@as(u16, 0), clock.scanline());
}

test "MasterClock: dot derivation" {
    var clock = MasterClock.init();

    // Dot 0
    try testing.expectEqual(@as(u16, 0), clock.dot());

    // Advance to dot 100
    clock.advance(100);
    try testing.expectEqual(@as(u16, 100), clock.dot());

    // Advance to dot 340 (last dot)
    clock.ppu_cycles = 340;
    try testing.expectEqual(@as(u16, 340), clock.dot());

    // Wrap to dot 0 (next scanline)
    clock.ppu_cycles = 341;
    try testing.expectEqual(@as(u16, 0), clock.dot());
}

test "MasterClock: frame derivation" {
    var clock = MasterClock.init();

    // Frame 0
    try testing.expectEqual(@as(u64, 0), clock.frame());

    // Advance to end of frame 0
    clock.ppu_cycles = 89341;
    try testing.expectEqual(@as(u64, 0), clock.frame());

    // Advance to frame 1
    clock.ppu_cycles = 89342;
    try testing.expectEqual(@as(u64, 1), clock.frame());

    // Frame 10
    clock.ppu_cycles = 89342 * 10;
    try testing.expectEqual(@as(u64, 10), clock.frame());
}

test "MasterClock: CPU cycle derivation" {
    var clock = MasterClock.init();

    // 0 CPU cycles
    try testing.expectEqual(@as(u64, 0), clock.cpuCycles());

    // 1 CPU cycle = 3 PPU cycles
    clock.advance(3);
    try testing.expectEqual(@as(u64, 1), clock.cpuCycles());

    // 10 CPU cycles = 30 PPU cycles
    clock.ppu_cycles = 30;
    try testing.expectEqual(@as(u64, 10), clock.cpuCycles());

    // Fractional CPU cycles (integer division)
    clock.ppu_cycles = 31; // 10.33 CPU cycles → 10
    try testing.expectEqual(@as(u64, 10), clock.cpuCycles());

    clock.ppu_cycles = 32; // 10.67 CPU cycles → 10
    try testing.expectEqual(@as(u64, 10), clock.cpuCycles());

    clock.ppu_cycles = 33; // 11.0 CPU cycles → 11
    try testing.expectEqual(@as(u64, 11), clock.cpuCycles());
}

test "MasterClock: CPU tick detection" {
    var clock = MasterClock.init();

    // Cycle 0: CPU tick
    try testing.expect(clock.isCpuTick());

    // Cycle 1: No CPU tick
    clock.advance(1);
    try testing.expect(!clock.isCpuTick());

    // Cycle 2: No CPU tick
    clock.advance(1);
    try testing.expect(!clock.isCpuTick());

    // Cycle 3: CPU tick
    clock.advance(1);
    try testing.expect(clock.isCpuTick());

    // Cycle 6: CPU tick
    clock.ppu_cycles = 6;
    try testing.expect(clock.isCpuTick());
}

test "MasterClock: odd frame detection" {
    var clock = MasterClock.init();

    // Frame 0: Even
    try testing.expect(!clock.isOddFrame());

    // Frame 1: Odd
    clock.ppu_cycles = 89342;
    try testing.expect(clock.isOddFrame());

    // Frame 2: Even
    clock.ppu_cycles = 89342 * 2;
    try testing.expect(!clock.isOddFrame());

    // Frame 3: Odd
    clock.ppu_cycles = 89342 * 3;
    try testing.expect(clock.isOddFrame());
}

test "MasterClock: frame position" {
    var clock = MasterClock.init();

    // Start of frame
    try testing.expectEqual(@as(u32, 0), clock.framePosition());

    // Middle of frame
    clock.ppu_cycles = 50000;
    try testing.expectEqual(@as(u32, 50000), clock.framePosition());

    // End of frame
    clock.ppu_cycles = 89341;
    try testing.expectEqual(@as(u32, 89341), clock.framePosition());

    // Next frame (wraps)
    clock.ppu_cycles = 89342;
    try testing.expectEqual(@as(u32, 0), clock.framePosition());
}

test "MasterClock: scanline and dot together" {
    var clock = MasterClock.init();

    // Scanline 0, dot 0
    var pos = clock.scanlineAndDot();
    try testing.expectEqual(@as(u16, 0), pos.scanline);
    try testing.expectEqual(@as(u16, 0), pos.dot);

    // Scanline 10, dot 50
    clock.ppu_cycles = 10 * 341 + 50;
    pos = clock.scanlineAndDot();
    try testing.expectEqual(@as(u16, 10), pos.scanline);
    try testing.expectEqual(@as(u16, 50), pos.dot);

    // Scanline 261, dot 340 (end of frame)
    clock.ppu_cycles = 261 * 341 + 340;
    pos = clock.scanlineAndDot();
    try testing.expectEqual(@as(u16, 261), pos.scanline);
    try testing.expectEqual(@as(u16, 340), pos.dot);
}

test "MasterClock: reset" {
    var clock = MasterClock.init();

    clock.advance(10000);
    clock.setSpeed(2.0);

    try testing.expectEqual(@as(u64, 10000), clock.ppu_cycles);

    clock.reset();

    try testing.expectEqual(@as(u64, 0), clock.ppu_cycles);
    try testing.expectEqual(@as(f64, 2.0), clock.speed_multiplier); // Speed persists
}

test "MasterClock: speed control" {
    var clock = MasterClock.init();

    // Default speed
    try testing.expectEqual(@as(f64, 1.0), clock.getSpeed());

    // Set fast forward
    clock.setSpeed(2.0);
    try testing.expectEqual(@as(f64, 2.0), clock.getSpeed());

    // Set slow motion
    clock.setSpeed(0.5);
    try testing.expectEqual(@as(f64, 0.5), clock.getSpeed());

    // Pause
    clock.setSpeed(0.0);
    try testing.expectEqual(@as(f64, 0.0), clock.getSpeed());
}

test "MasterClock: frame timing accuracy" {
    var clock = MasterClock.init();

    // Even frame: 89,342 cycles
    const even_frame_cycles = 89342;

    // Run one even frame
    clock.advance(even_frame_cycles);

    // Should advance to frame 1
    try testing.expectEqual(@as(u64, 1), clock.frame());

    // Should be at scanline 0, dot 0
    try testing.expectEqual(@as(u16, 0), clock.scanline());
    try testing.expectEqual(@as(u16, 0), clock.dot());

    // CPU cycles in one frame
    const cpu_cycles_per_frame = even_frame_cycles / 3;
    try testing.expectEqual(@as(u64, 29780), cpu_cycles_per_frame);
    try testing.expectEqual(cpu_cycles_per_frame, clock.cpuCycles());
}

test "MasterClock: CPU/PPU ratio verification" {
    var clock = MasterClock.init();

    // Advance by 10,000 CPU cycles worth of PPU cycles
    const cpu_cycles_target: u64 = 10000;
    const ppu_cycles_needed = cpu_cycles_target * 3;

    clock.advance(ppu_cycles_needed);

    // Verify exact 1:3 ratio
    try testing.expectEqual(cpu_cycles_target, clock.cpuCycles());
    try testing.expectEqual(ppu_cycles_needed, clock.ppu_cycles);
}

test "MasterClock: VBlank timing" {
    var clock = MasterClock.init();

    // VBlank starts at scanline 241, dot 1
    const vblank_start_cycle = 241 * 341 + 1;

    clock.ppu_cycles = vblank_start_cycle;

    try testing.expectEqual(@as(u16, 241), clock.scanline());
    try testing.expectEqual(@as(u16, 1), clock.dot());

    // VBlank ends at scanline 261, dot 1 (pre-render clears VBlank)
    const vblank_end_cycle = 261 * 341 + 1;

    clock.ppu_cycles = vblank_end_cycle;

    try testing.expectEqual(@as(u16, 261), clock.scanline());
    try testing.expectEqual(@as(u16, 1), clock.dot());
}
