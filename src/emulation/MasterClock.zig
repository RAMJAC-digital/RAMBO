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
/// Now simplified to ONLY track master_cycles for timestamps
/// PPU timing is now owned by PpuState (cycle, scanline, frame_count)
/// Mesen2 architecture: _masterClock for timestamps, PPU owns _cycle/_scanline/_frameCount
pub const MasterClock = struct {
    /// Monotonic master clock - ALWAYS advances by 1
    /// This is the authoritative timing source for all timestamps
    /// Hardware correspondence: Counts every tick of the emulator
    /// CRITICAL: This counter NEVER skips values (0, 1, 2, 3, 4...)
    /// Used by VBlankLedger and other systems for timestamp comparisons
    master_cycles: u64 = 0,

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

    /// Advance clock by 1 master cycle
    /// This is the ONLY function that mutates timing state
    /// Called by EmulationState.tick() to advance emulation
    ///
    /// Hardware: Master clock ALWAYS advances by 1 (monotonic)
    /// PPU clock advances separately via PpuLogic.advanceClock()
    ///
    /// Note: PPU timing (cycle, scanline, frame_count) is now owned by PpuState
    /// Odd frame skip is handled in PPU clock, not here
    pub fn advance(self: *MasterClock) void {
        self.master_cycles +%= 1; // ALWAYS +1 (monotonic)
    }

    /// Get total CPU cycles elapsed
    /// Hardware: CPU runs at 1/3 the speed of PPU (1.789773 MHz vs 5.369318 MHz)
    /// - 1 CPU cycle = 3 master clock ticks
    ///
    /// Now derives from master_cycles instead of ppu_cycles
    /// Since master_cycles advances 1:1 with PPU cycles (before PPU handles odd frame skip),
    /// the 1:3 ratio is maintained.
    pub fn cpuCycles(self: MasterClock) u64 {
        return self.master_cycles / 3;
    }

    /// Check if current cycle is a CPU tick
    /// Hardware: CPU ticks every 3rd master cycle
    /// - Master cycle 0, 3, 6, 9... → CPU ticks
    /// - Master cycle 1, 2, 4, 5... → CPU idle
    ///
    /// Now checks master_cycles instead of ppu_cycles
    /// Used by EmulationState.tick() to determine when to tick CPU
    pub fn isCpuTick(self: MasterClock) bool {
        return (self.master_cycles % 3) == 0;
    }

    /// Check if current cycle is an APU tick
    /// Hardware: APU is synchronized with CPU (same clock divider)
    /// - APU ticks whenever CPU ticks
    ///
    /// Alias for isCpuTick() for clarity
    pub fn isApuTick(self: MasterClock) bool {
        return self.isCpuTick();
    }

    /// Reset clock to power-on state
    /// Used when emulator is reset or ROM is loaded
    ///
    /// CRITICAL: CPU/PPU phase offset
    /// Hardware has an arbitrary phase relationship between CPU and PPU clocks.
    /// CPU ticks every 3 master cycles, but the initial offset varies by console.
    /// Starting at master_cycles = 0 means CPU ticks when (master % 3 == 0).
    /// Real hardware might have CPU tick when (master % 3 == 1) or (master % 3 == 2).
    ///
    /// AccuracyCoin tests are sensitive to this phase! Testing different offsets:
    /// - Phase 0 (master_cycles = 0): CPU at master % 3 == 0
    /// - Phase 1 (master_cycles = 1): CPU at master % 3 == 1
    /// - Phase 2 (master_cycles = 2): CPU at master % 3 == 2
    pub fn reset(self: *MasterClock) void {
        // TODO: Make this configurable or determine correct hardware phase
        self.master_cycles = 2; // TESTING: Phase 2 to see if it fixes AccuracyCoin
        // Note: speed_multiplier is NOT reset (user preference persists)
        // Note: PPU clock is reset separately via PpuState.init()
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

    try testing.expectEqual(@as(u64, 0), clock.master_cycles);
    try testing.expectEqual(@as(f64, 1.0), clock.speed_multiplier);
}

test "MasterClock: advance cycles" {
    var clock = MasterClock.init();

    // Advance always increments by 1 (monotonic)
    clock.advance();
    try testing.expectEqual(@as(u64, 1), clock.master_cycles);

    // Advance again
    clock.advance();
    try testing.expectEqual(@as(u64, 2), clock.master_cycles);

    // Verify monotonicity: master_cycles should never skip values
    const prev_master = clock.master_cycles;
    clock.advance();
    try testing.expectEqual(prev_master + 1, clock.master_cycles);
}

test "MasterClock: CPU cycle derivation" {
    var clock = MasterClock.init();

    // 0 CPU cycles
    try testing.expectEqual(@as(u64, 0), clock.cpuCycles());

    // 1 CPU cycle = 3 master cycles
    clock.advance();
    clock.advance();
    clock.advance();
    try testing.expectEqual(@as(u64, 1), clock.cpuCycles());

    // 10 CPU cycles = 30 master cycles
    clock.master_cycles = 30;
    try testing.expectEqual(@as(u64, 10), clock.cpuCycles());

    // Fractional CPU cycles (integer division)
    clock.master_cycles = 31; // 10.33 CPU cycles → 10
    try testing.expectEqual(@as(u64, 10), clock.cpuCycles());

    clock.master_cycles = 32; // 10.67 CPU cycles → 10
    try testing.expectEqual(@as(u64, 10), clock.cpuCycles());

    clock.master_cycles = 33; // 11.0 CPU cycles → 11
    try testing.expectEqual(@as(u64, 11), clock.cpuCycles());
}

test "MasterClock: CPU tick detection" {
    var clock = MasterClock.init();

    // Cycle 0: CPU tick
    try testing.expect(clock.isCpuTick());

    // Cycle 1: No CPU tick
    clock.advance();
    try testing.expect(!clock.isCpuTick());

    // Cycle 2: No CPU tick
    clock.advance();
    try testing.expect(!clock.isCpuTick());

    // Cycle 3: CPU tick
    clock.advance();
    try testing.expect(clock.isCpuTick());

    // Cycle 6: CPU tick
    clock.master_cycles = 6;
    try testing.expect(clock.isCpuTick());
}

test "MasterClock: APU tick detection" {
    var clock = MasterClock.init();

    // APU ticks are same as CPU ticks
    try testing.expect(clock.isApuTick() == clock.isCpuTick());

    clock.advance();
    try testing.expect(clock.isApuTick() == clock.isCpuTick());
}

test "MasterClock: reset" {
    var clock = MasterClock.init();

    // Advance counter
    clock.advance();
    clock.advance();
    clock.advance();
    clock.setSpeed(2.0);

    try testing.expectEqual(@as(u64, 3), clock.master_cycles);

    clock.reset();

    // Reset to phase 2
    try testing.expectEqual(@as(u64, 2), clock.master_cycles);
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

test "MasterClock: CPU/master ratio verification" {
    var clock = MasterClock.init();

    // Advance by 10,000 CPU cycles worth of master cycles
    const cpu_cycles_target: u64 = 10000;
    const master_cycles_needed = cpu_cycles_target * 3;

    clock.master_cycles = master_cycles_needed;

    // Verify exact 1:3 ratio
    try testing.expectEqual(cpu_cycles_target, clock.cpuCycles());
    try testing.expectEqual(master_cycles_needed, clock.master_cycles);
}
