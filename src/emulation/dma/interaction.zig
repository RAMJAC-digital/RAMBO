//! DMA Interaction Logic - Pure functions for DMC/OAM DMA conflicts
//!
//! This module implements pure logic functions for handling DMC/OAM DMA interaction.
//! Follows the 3-layer architecture pattern:
//!
//! 1. DmaInteractionLedger - Pure timestamp data (single source of truth)
//! 2. OamDma state - Phase machine and edge detection
//! 3. This module - Pure logic functions (stateless)
//!
//! ## Hardware Behavior
//!
//! When DMC DMA activates while OAM DMA is active:
//! - DMC has higher priority, pauses OAM
//! - OAM state captured at pause edge
//! - OAM resumes when DMC completes
//! - If interrupted during read: byte duplicates (hardware bug)
//!
//! Reference: nesdev.org/wiki/APU_DMC#DMA_conflict

const std = @import("std");
const DmaInteractionLedger = @import("../DmaInteractionLedger.zig").DmaInteractionLedger;
const OamDma = @import("../state/peripherals/OamDma.zig").OamDma;
const OamDmaPhase = @import("../state/peripherals/OamDma.zig").OamDmaPhase;

// ============================================================================
// Query Functions (moved from DmaInteractionLedger)
// ============================================================================

/// Query: Is DMC currently active?
///
/// Based on timestamp comparison: active when last active > last inactive
pub fn isDmcActive(ledger: *const DmaInteractionLedger) bool {
    return ledger.last_dmc_active_cycle > ledger.last_dmc_inactive_cycle;
}

/// Query: Is OAM currently paused?
///
/// Based on timestamp: paused when pause_cycle > resume_cycle
pub fn isOamPaused(ledger: *const DmaInteractionLedger) bool {
    return ledger.oam_pause_cycle > ledger.oam_resume_cycle;
}

/// Query: Did DMC just complete? (inactive edge detection)
///
/// True when DMC just transitioned from active to inactive.
/// This is the resume edge for OAM.
pub fn didDmcJustComplete(ledger: *const DmaInteractionLedger, current_cycle: u64) bool {
    return ledger.last_dmc_inactive_cycle == current_cycle and
        !isDmcActive(ledger);
}

// ============================================================================
// Pause/Resume Logic
// ============================================================================

/// Handle DMC becoming active while OAM is running
///
/// This is called on the DMC active edge (rdy_low: false → true)
/// when OAM DMA is active and not already paused.
///
/// **PURE FUNCTION** - Returns data only, NO mutations.
/// Caller must perform all state updates.
pub fn handleDmcPausesOam(
    ledger: *const DmaInteractionLedger,  // NOW CONST
    oam: *const OamDma,
    cycle: u64,
) PauseData {
    _ = ledger; // Not used in pure function

    // Calculate effective cycle (accounting for alignment)
    const effective_cycle: i32 = if (oam.needs_alignment)
        @as(i32, @intCast(oam.current_cycle)) - 1
    else
        @as(i32, @intCast(oam.current_cycle));

    // Determine if pausing during read (even) or write (odd)
    const is_reading = (effective_cycle >= 0 and @rem(effective_cycle, 2) == 0);

    // Capture interrupted state (data only)
    const interrupted = DmaInteractionLedger.InterruptedState{
        .was_reading = is_reading,
        .offset = oam.current_offset,
        .byte_value = 0, // Will be filled by caller after bus read
        .oam_addr = 0,   // Will be filled by caller
    };

    // Return ALL data needed for mutations (no side effects)
    const pause_phase: OamDmaPhase = if (is_reading) .paused_during_read else .paused_during_write;

    return .{
        .pause_phase = pause_phase,
        .pause_cycle = cycle,
        .interrupted_state = interrupted,
        .read_interrupted_byte = if (is_reading) .{
            .source_page = oam.source_page,
            .offset = oam.current_offset,
        } else null,
    };
}

/// Data returned from pause analysis (pure - no mutations)
pub const PauseData = struct {
    /// Phase to transition to
    pause_phase: OamDmaPhase,

    /// Cycle when pause occurred
    pause_cycle: u64,

    /// Captured state at moment of pause
    interrupted_state: DmaInteractionLedger.InterruptedState,

    /// If non-null, caller should read this byte and store in ledger
    read_interrupted_byte: ?struct {
        source_page: u8,
        offset: u8,
    },
};

/// Handle OAM resuming after DMC completes
///
/// This is called on the DMC inactive edge (rdy_low: true → false)
/// when OAM is paused.
///
/// **PURE FUNCTION** - Returns data only, NO mutations.
/// Caller must perform all state updates.
pub fn handleOamResumes(
    ledger: *const DmaInteractionLedger,
    cycle: u64,
) ResumeData {
    // Determine resume action based on interrupted state
    if (ledger.interrupted_state.was_reading) {
        // Interrupted during read - need byte duplication
        return .{
            .resume_phase = .resuming_with_duplication,
            .resume_cycle = cycle,
            .duplicate_byte = ledger.interrupted_state.byte_value,
        };
    } else {
        // Interrupted during write - continue normally
        return .{
            .resume_phase = .resuming_normal,
            .resume_cycle = cycle,
            .duplicate_byte = null,
        };
    }
}

/// Data returned from resume analysis (pure - no mutations)
pub const ResumeData = struct {
    /// Phase to transition to
    resume_phase: OamDmaPhase,

    /// Cycle when resume occurred
    resume_cycle: u64,

    /// If non-null, write this byte as first action on resume
    duplicate_byte: ?u8,
};

/// Query if OAM should pause on this cycle
///
/// **Pure function** - reads ledger state, no mutations.
pub fn shouldOamPause(
    _: *const DmaInteractionLedger,
    oam: *const OamDma,
    dmc_active: bool,
) bool {
    // Pause if:
    // 1. DMC is currently active (rdy_low = true)
    // 2. OAM is active
    // 3. OAM is not already paused
    return dmc_active and
        oam.active and
        !isPaused(oam.phase);
}

/// Query if OAM should resume on this cycle
///
/// **Pure function** - reads ledger state, no mutations.
pub fn shouldOamResume(
    ledger: *const DmaInteractionLedger,
    oam: *const OamDma,
    dmc_active: bool,
    cycle: u64,
) bool {
    // Resume if:
    // 1. OAM is paused
    // 2. DMC is not currently active
    // 3. OAM pause happened (oam_pause_cycle > 0)
    // 4. Resume hasn't happened yet (oam_resume_cycle is still 0)
    // 5. DMC completed since the pause
    // 6. EXACT cycle match (edge detection - BUG #4 FIX)
    return isPaused(oam.phase) and
        !dmc_active and
        ledger.oam_pause_cycle > 0 and
        ledger.oam_resume_cycle == 0 and
        ledger.last_dmc_inactive_cycle > ledger.oam_pause_cycle and
        ledger.last_dmc_inactive_cycle == cycle;
}

/// Helper: Check if phase is a paused state
fn isPaused(phase: OamDmaPhase) bool {
    return phase == .paused_during_read or phase == .paused_during_write;
}

/// Helper: Check if phase is a resuming state
fn isResuming(phase: OamDmaPhase) bool {
    return phase == .resuming_with_duplication or phase == .resuming_normal;
}

/// Query what action tickOamDma should take on this cycle
///
/// **Pure function** - determines DMA tick behavior based on phase.
pub fn getDmaTickAction(
    ledger: *const DmaInteractionLedger,
    oam: *const OamDma,
) DmaTickAction {
    switch (oam.phase) {
        .idle => return .skip, // Not active

        .paused_during_read, .paused_during_write => return .skip, // Frozen

        .resuming_with_duplication => {
            // Write the interrupted byte first, then continue
            return .{
                .resume_with_duplication = .{
                    .byte_to_write = ledger.interrupted_state.byte_value,
                    .oam_addr = ledger.interrupted_state.oam_addr,
                },
            };
        },

        .resuming_normal => {
            // Just continue from where we left off
            return .continue_normal;
        },

        .aligning, .reading, .writing => {
            // Normal operation
            return .continue_normal;
        },
    }
}

/// Action for tickOamDma to take
pub const DmaTickAction = union(enum) {
    /// Skip this tick (paused or inactive)
    skip,

    /// Continue normal DMA operation
    continue_normal,

    /// Resume with byte duplication
    resume_with_duplication: struct {
        byte_to_write: u8,
        oam_addr: u8,
    },
};

// Unit tests
const testing = std.testing;

test "interaction: Pause during read phase" {
    var ledger = DmaInteractionLedger{};
    const oam = OamDma{
        .active = true,
        .phase = .reading,
        .source_page = 0x03,
        .current_offset = 50,
        .current_cycle = 100,
        .needs_alignment = false,
    };

    const pause_data = handleDmcPausesOam(&ledger, &oam, 1000);

    // Should pause during read
    try testing.expectEqual(OamDmaPhase.paused_during_read, pause_data.pause_phase);
    try testing.expect(pause_data.read_interrupted_byte != null);

    // Should set up byte read
    const read_info = pause_data.read_interrupted_byte.?;
    try testing.expectEqual(@as(u8, 0x03), read_info.source_page);
    try testing.expectEqual(@as(u8, 50), read_info.offset);

    // Manually apply mutations (simulating what execution.zig will do)
    ledger.oam_pause_cycle = pause_data.pause_cycle;
    ledger.interrupted_state = pause_data.interrupted_state;

    // Ledger should now record pause
    try testing.expect(ledger.isOamPaused());
    try testing.expect(ledger.interrupted_state.was_reading);
}

test "interaction: Pause during write phase" {
    var ledger = DmaInteractionLedger{};
    const oam = OamDma{
        .active = true,
        .phase = .writing,
        .source_page = 0x04,
        .current_offset = 75,
        .current_cycle = 151, // Odd cycle = write
        .needs_alignment = false,
    };

    const pause_data = handleDmcPausesOam(&ledger, &oam, 2000);

    // Should pause during write
    try testing.expectEqual(OamDmaPhase.paused_during_write, pause_data.pause_phase);
    try testing.expect(pause_data.read_interrupted_byte == null);

    // Manually apply mutations (simulating what execution.zig will do)
    ledger.oam_pause_cycle = pause_data.pause_cycle;
    ledger.interrupted_state = pause_data.interrupted_state;

    // Ledger should now record pause
    try testing.expect(ledger.isOamPaused());
    try testing.expect(!ledger.interrupted_state.was_reading);
}

test "interaction: Resume with duplication" {
    var ledger = DmaInteractionLedger{};

    // Setup paused state (interrupted during read) - direct field assignment
    ledger.oam_pause_cycle = 1000;
    ledger.interrupted_state = .{
        .was_reading = true,
        .offset = 50,
        .byte_value = 0xAA,
        .oam_addr = 50,
    };

    const resume_data = handleOamResumes(&ledger, 1004);

    // Should resume with duplication
    try testing.expectEqual(OamDmaPhase.resuming_with_duplication, resume_data.resume_phase);
    try testing.expect(resume_data.duplicate_byte != null);
    try testing.expectEqual(@as(u8, 0xAA), resume_data.duplicate_byte.?);
    try testing.expectEqual(@as(u64, 1004), resume_data.resume_cycle);
}

test "interaction: Resume normal (no duplication)" {
    var ledger = DmaInteractionLedger{};

    // Setup paused state (interrupted during write) - direct field assignment
    ledger.oam_pause_cycle = 1000;
    ledger.interrupted_state = .{
        .was_reading = false,
        .offset = 75,
        .byte_value = 0,
        .oam_addr = 75,
    };

    const resume_data = handleOamResumes(&ledger, 1004);

    // Should resume normally
    try testing.expectEqual(OamDmaPhase.resuming_normal, resume_data.resume_phase);
    try testing.expect(resume_data.duplicate_byte == null);
    try testing.expectEqual(@as(u64, 1004), resume_data.resume_cycle);
}

test "interaction: shouldOamPause logic" {
    var ledger = DmaInteractionLedger{};
    var oam = OamDma{ .active = true, .phase = .reading };

    // Should pause when DMC active and OAM running
    try testing.expect(shouldOamPause(&ledger, &oam, true));

    // Should NOT pause when DMC inactive
    try testing.expect(!shouldOamPause(&ledger, &oam, false));

    // Should NOT pause when OAM already paused
    oam.phase = .paused_during_read;
    try testing.expect(!shouldOamPause(&ledger, &oam, true));
}

test "interaction: shouldOamResume logic" {
    var ledger = DmaInteractionLedger{};
    var oam = OamDma{ .active = true, .phase = .paused_during_read };

    // Setup ledger for resume detection - direct field assignment
    ledger.last_dmc_active_cycle = 1000;
    ledger.oam_pause_cycle = 1000;
    ledger.last_dmc_inactive_cycle = 1004;

    // Should resume any time after DMC completes (oam_resume_cycle still 0)
    try testing.expect(shouldOamResume(&ledger, &oam, false, 1004));
    try testing.expect(shouldOamResume(&ledger, &oam, false, 1005));
    try testing.expect(shouldOamResume(&ledger, &oam, false, 1010));

    // Should NOT resume when DMC still active
    try testing.expect(!shouldOamResume(&ledger, &oam, true, 1004));

    // Should NOT resume after oam_resume_cycle is set (resume already happened)
    ledger.oam_resume_cycle = 1005;
    try testing.expect(!shouldOamResume(&ledger, &oam, false, 1006));
}
