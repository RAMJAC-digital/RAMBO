//! Timing Step Structure
//!
//! Represents a single timing slot in the emulation loop.
//! This structure is computed BEFORE clock advancement and component work,
//! providing deterministic scheduling semantics.
//!
//! Architecture:
//! - Read-only snapshot computed before any state changes
//! - Explicitly communicates timing decisions to tick() coordinator
//! - Enables pure testing of timing logic without component coupling
//!
//! References:
//! - docs/code-review/clock-advance-refactor-plan.md
//! - Hardware: nesdev.org/wiki/PPU_frame_timing (odd frame skip)

const std = @import("std");

/// Timing slot descriptor for one emulation tick
/// Computed by nextTimingStep() before clock advancement
pub const TimingStep = struct {
    /// Whether CPU should tick this cycle (every 3rd PPU cycle)
    cpu_tick: bool,
};

/// Timing helper functions (pure, no state mutation)
pub const TimingHelpers = struct {
    /// Check if current position is the odd-frame skip point
    /// Hardware: On odd frames with rendering enabled, the PPU skips
    /// the first idle tick of the pre-render scanline (scanline 261, dot 340)
    ///
    /// Parameters:
    ///   - odd_frame: Even/odd frame flag (toggled each frame)
    ///   - rendering_enabled: PPU mask bits 3-4 (show BG or sprites)
    ///   - scanline: Current scanline (0-261)
    ///   - dot: Current dot (0-340)
    ///
    /// Returns: true if next tick should skip dot 0 of scanline 0
    pub fn shouldSkipOddFrame(
        odd_frame: bool,
        rendering_enabled: bool,
        scanline: i16, // Changed from u16 to match PPU state type
        dot: u16,
    ) bool {
        // Hardware: Odd frame skip jumps from (339,-1) to (0,0) on pre-render scanline
        // Reference: https://www.nesdev.org/wiki/PPU_frame_timing
        // The skip occurs when we're AT dot 339, skipping dot 340
        return odd_frame and
            rendering_enabled and
            scanline == -1 and
            dot == 339;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "TimingHelpers: shouldSkipOddFrame returns false on even frames" {
    const should_skip = TimingHelpers.shouldSkipOddFrame(
        false, // even frame
        true, // rendering enabled
        261, // scanline
        339, // dot - skip occurs FROM 339, not 340
    );
    try testing.expect(!should_skip);
}

test "TimingHelpers: shouldSkipOddFrame returns false when rendering disabled" {
    const should_skip = TimingHelpers.shouldSkipOddFrame(
        true, // odd frame
        false, // rendering disabled
        261,
        339,
    );
    try testing.expect(!should_skip);
}

test "TimingHelpers: shouldSkipOddFrame returns false at wrong scanline" {
    const should_skip = TimingHelpers.shouldSkipOddFrame(
        true,
        true,
        260, // wrong scanline
        339,
    );
    try testing.expect(!should_skip);
}

test "TimingHelpers: shouldSkipOddFrame returns false at wrong dot" {
    const should_skip = TimingHelpers.shouldSkipOddFrame(
        true,
        true,
        261,
        340, // wrong dot - should be 339
    );
    try testing.expect(!should_skip);
}

test "TimingHelpers: shouldSkipOddFrame returns true when all conditions met" {
    const should_skip = TimingHelpers.shouldSkipOddFrame(
        true, // odd frame
        true, // rendering enabled
        -1, // scanline -1 (pre-render scanline)
        339, // dot 339 - skip occurs FROM here
    );
    try testing.expect(should_skip);
}

test "TimingStep: structure size is reasonable" {
    // Ensure TimingStep doesn't bloat the stack
    try testing.expect(@sizeOf(TimingStep) <= 16);
}
