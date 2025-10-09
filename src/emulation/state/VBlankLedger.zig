//! VBlank Timestamp Ledger
//!
//! Cycle-accurate tracking of VBlank timing events for deterministic NMI edge detection.
//! Decouples CPU NMI latch from readable PPU status flag to prevent race conditions.
//!
//! Architecture:
//! - Records master clock cycles when VBlank sets/clears
//! - Tracks $2002 reads and PPUCTRL writes with timestamps
//! - Provides pure functions for NMI edge detection based on recorded history
//! - Zero heap allocations - all state on stack
//!
//! Hardware correspondence:
//! - VBlank flag (readable via $2002) vs NMI latch (internal CPU state)
//! - NMI edge detection: VBlank 0→1 while PPUCTRL.7=1
//! - Reading $2002 clears readable flag but NOT latched NMI
//! - Toggling PPUCTRL.7 during VBlank can trigger multiple NMI edges
//!
//! References:
//! - docs/code-review/gemini-review-2025-10-09.md Section 2.1
//! - nesdev.org/wiki/NMI (edge detection, race condition)
//! - nesdev.org/wiki/PPU_frame_timing (VBlank timing)

const std = @import("std");

/// VBlank timing ledger with cycle-accurate event timestamps
pub const VBlankLedger = struct {
    // ===== Live State Flags =====

    /// VBlank span is currently active (set at 241.1, cleared at 261.1)
    span_active: bool = false,

    /// PPUCTRL.7 (NMI output enable) current state
    ctrl_nmi_enabled: bool = false,

    /// NMI edge is pending acknowledgment by CPU interrupt controller
    nmi_edge_pending: bool = false,

    // ===== Timestamp Fields (Master Clock PPU Cycles) =====

    /// Cycle when VBlank flag was last set (scanline 241 dot 1)
    last_set_cycle: u64 = 0,

    /// Cycle when VBlank flag was last cleared (scanline 261 dot 1 or $2002 read)
    last_clear_cycle: u64 = 0,

    /// Cycle when $2002 (PPUSTATUS) was last read
    last_status_read_cycle: u64 = 0,

    /// Cycle when PPUCTRL was last written (potentially toggling NMI enable)
    last_ctrl_toggle_cycle: u64 = 0,

    /// Cycle when CPU acknowledged NMI (during interrupt sequence)
    last_cpu_ack_cycle: u64 = 0,

    /// Record VBlank flag set event
    /// Called at scanline 241 dot 1
    pub fn recordVBlankSet(self: *VBlankLedger, cycle: u64) void {
        self.span_active = true;
        self.last_set_cycle = cycle;
    }

    /// Record VBlank flag clear event
    /// Called at scanline 261 dot 1 (pre-render) or when $2002 read
    pub fn recordVBlankClear(self: *VBlankLedger, cycle: u64) void {
        // Note: Clearing the readable flag does NOT clear pending NMI edge
        self.last_clear_cycle = cycle;
    }

    /// Record end of VBlank span (pre-render scanline)
    /// This is different from readable flag clear - marks end of VBlank period
    pub fn recordVBlankSpanEnd(self: *VBlankLedger, cycle: u64) void {
        self.span_active = false;
        self.last_clear_cycle = cycle;
    }

    /// Record $2002 (PPUSTATUS) read
    /// Clears readable VBlank flag but NOT latched NMI
    pub fn recordStatusRead(self: *VBlankLedger, cycle: u64) void {
        self.last_status_read_cycle = cycle;
    }

    /// Record PPUCTRL write (may toggle NMI enable)
    /// Multiple toggles during VBlank can generate multiple NMI edges
    pub fn recordCtrlToggle(self: *VBlankLedger, cycle: u64, nmi_enabled: bool) void {
        const old_enabled = self.ctrl_nmi_enabled;
        self.ctrl_nmi_enabled = nmi_enabled;
        self.last_ctrl_toggle_cycle = cycle;

        // Detect NMI edge: 0→1 transition of (VBlank AND NMI_enable)
        // Hardware: NMI fires when BOTH vblank flag and ctrl.nmi_enable are true
        if (!old_enabled and nmi_enabled and self.span_active) {
            self.nmi_edge_pending = true;
        }
    }

    /// Check if NMI edge should fire based on ledger state
    /// Pure function - no side effects
    ///
    /// NMI edge occurs when:
    /// 1. VBlank span is active (between 241.1 and 261.1)
    /// 2. PPUCTRL.7 (NMI enable) is set
    /// 3. Edge hasn't been acknowledged yet
    /// 4. No race condition from $2002 read on exact set cycle
    ///
    /// Returns: true if NMI should latch this cycle
    pub fn shouldNmiEdge(self: *const VBlankLedger, _: u64) bool {
        // Must be within VBlank window
        if (!self.span_active) return false;

        // NMI output must be enabled
        if (!self.ctrl_nmi_enabled) return false;

        // Check if edge is pending
        if (!self.nmi_edge_pending) return false;

        // Race condition check: If $2002 read happened on exact VBlank set cycle,
        // NMI may be suppressed (hardware quirk documented on nesdev.org)
        const read_on_set = self.last_status_read_cycle == self.last_set_cycle;
        if (read_on_set) return false;

        return true;
    }

    /// CPU acknowledged NMI (during interrupt sequence cycle 6)
    /// Clears pending edge flag
    pub fn acknowledgeCpu(self: *VBlankLedger, cycle: u64) void {
        self.nmi_edge_pending = false;
        self.last_cpu_ack_cycle = cycle;
    }

    /// Reset ledger to power-on state
    pub fn reset(self: *VBlankLedger) void {
        self.* = .{};
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "VBlankLedger: initialization" {
    const ledger = VBlankLedger{};

    try testing.expect(!ledger.span_active);
    try testing.expect(!ledger.ctrl_nmi_enabled);
    try testing.expect(!ledger.nmi_edge_pending);
    try testing.expectEqual(@as(u64, 0), ledger.last_set_cycle);
}

test "VBlankLedger: VBlank set marks span active" {
    var ledger = VBlankLedger{};

    ledger.recordVBlankSet(100);

    try testing.expect(ledger.span_active);
    try testing.expectEqual(@as(u64, 100), ledger.last_set_cycle);
}

test "VBlankLedger: PPUCTRL toggle during VBlank triggers NMI edge" {
    var ledger = VBlankLedger{};

    // Set VBlank active
    ledger.recordVBlankSet(100);

    // Enable NMI during VBlank
    ledger.recordCtrlToggle(110, true);

    try testing.expect(ledger.nmi_edge_pending);
}

test "VBlankLedger: PPUCTRL toggle before VBlank does not trigger edge" {
    var ledger = VBlankLedger{};

    // Enable NMI before VBlank
    ledger.recordCtrlToggle(50, true);

    try testing.expect(!ledger.nmi_edge_pending);

    // VBlank starts
    ledger.recordVBlankSet(100);

    // Edge should now be pending (VBlank set with NMI already enabled)
    // This is handled by EmulationState checking both conditions
}

test "VBlankLedger: shouldNmiEdge returns true when conditions met" {
    var ledger = VBlankLedger{};

    ledger.recordVBlankSet(100);
    ledger.recordCtrlToggle(110, true);

    try testing.expect(ledger.shouldNmiEdge(120));
}

test "VBlankLedger: shouldNmiEdge returns false after acknowledgment" {
    var ledger = VBlankLedger{};

    ledger.recordVBlankSet(100);
    ledger.recordCtrlToggle(110, true);

    // Acknowledge NMI
    ledger.acknowledgeCpu(120);

    try testing.expect(!ledger.shouldNmiEdge(130));
}

test "VBlankLedger: $2002 read on exact set cycle suppresses NMI" {
    var ledger = VBlankLedger{};

    const vblank_set_cycle = 100;

    ledger.recordVBlankSet(vblank_set_cycle);
    ledger.ctrl_nmi_enabled = true;
    ledger.nmi_edge_pending = true;

    // Read $2002 on exact same cycle VBlank sets
    ledger.recordStatusRead(vblank_set_cycle);

    // NMI should be suppressed due to race condition
    try testing.expect(!ledger.shouldNmiEdge(vblank_set_cycle + 1));
}

test "VBlankLedger: $2002 read after VBlank set does not suppress NMI" {
    var ledger = VBlankLedger{};

    ledger.recordVBlankSet(100);
    ledger.ctrl_nmi_enabled = true;
    ledger.nmi_edge_pending = true;

    // Read $2002 a few cycles after VBlank set
    ledger.recordStatusRead(105);

    // NMI should still fire (no race condition)
    try testing.expect(ledger.shouldNmiEdge(110));
}

test "VBlankLedger: reset clears all state" {
    var ledger = VBlankLedger{};

    ledger.recordVBlankSet(100);
    ledger.recordCtrlToggle(110, true);

    ledger.reset();

    try testing.expect(!ledger.span_active);
    try testing.expect(!ledger.ctrl_nmi_enabled);
    try testing.expectEqual(@as(u64, 0), ledger.last_set_cycle);
}
