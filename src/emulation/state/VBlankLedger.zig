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
    ///
    /// Hardware behavior: If NMI is already enabled when VBlank sets,
    /// this creates a 0→1 edge on (VBlank AND NMI_enable) signal.
    pub fn recordVBlankSet(self: *VBlankLedger, cycle: u64, nmi_enabled: bool) void {
        const was_active = self.span_active;
        self.span_active = true;
        self.last_set_cycle = cycle;

        // Detect NMI edge: 0→1 transition of (VBlank span AND NMI_enable)
        // If VBlank sets while NMI is already enabled, fire NMI edge
        if (!was_active and nmi_enabled) {
            self.nmi_edge_pending = true;
        }
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
    /// This clears the readable VBlank flag (updates last_clear_cycle)
    /// but does NOT end the VBlank span (span_active remains true until 261.1)
    ///
    /// Hardware correspondence:
    /// - Reading $2002 clears bit 7 immediately (nesdev.org/wiki/PPU_registers)
    /// - But VBlank period continues until scanline 261.1
    /// - NMI edge already latched is NOT cleared by $2002 read
    pub fn recordStatusRead(self: *VBlankLedger, cycle: u64) void {
        self.last_status_read_cycle = cycle;

        // Reading $2002 clears the readable VBlank flag
        // Update clear timestamp so future reads work correctly
        self.last_clear_cycle = cycle;

        // Note: span_active remains true until scanline 261.1
        // Note: nmi_edge_pending is NOT cleared (NMI already latched)
    }

    /// Record PPUCTRL write (may toggle NMI enable)
    /// Multiple toggles during VBlank can generate multiple NMI edges
    pub fn recordCtrlToggle(self: *VBlankLedger, cycle: u64, old_enabled: bool, new_enabled: bool) void {
        self.last_ctrl_toggle_cycle = cycle;

        // Detect NMI edge: 0→1 transition of (VBlank AND NMI_enable)
        // Hardware: NMI fires when BOTH vblank flag and ctrl.nmi_enable are true
        if (!old_enabled and new_enabled and self.span_active) {
            self.nmi_edge_pending = true;
        }
    }

    /// Check if NMI edge should fire based on ledger state
    /// Pure function - no side effects
    ///
    /// NMI edge occurs when:
    /// 1. PPUCTRL.7 (NMI enable) is set (passed as parameter)
    /// 2. Edge hasn't been acknowledged yet
    /// 3. No race condition from $2002 read on exact set cycle
    ///
    /// CRITICAL: Once an NMI edge is latched (`nmi_edge_pending = true`), it persists
    /// until the CPU acknowledges it, **even after VBlank span ends** (scanline 261.1).
    /// This matches hardware behavior where NMI remains asserted until serviced.
    ///
    /// Returns: true if NMI should latch this cycle
    pub fn shouldNmiEdge(self: *const VBlankLedger, _: u64, nmi_enabled: bool) bool {
        // NMI output must be enabled
        if (!nmi_enabled) return false;

        // Check if edge is pending (latched edge persists until CPU acknowledges)
        if (!self.nmi_edge_pending) return false;

        // Race condition check: If $2002 read happened on exact VBlank set cycle,
        // NMI may be suppressed (hardware quirk documented on nesdev.org)
        const read_on_set = self.last_status_read_cycle == self.last_set_cycle;
        if (read_on_set) return false;

        return true;
    }

    /// Query if CPU NMI line should be asserted this cycle
    /// Combines edge (latched) and level (active) logic into single source of truth
    ///
    /// Hardware behavior (nesdev.org/wiki/NMI):
    /// - NMI is **EDGE-triggered** (triggers on 0→1 transition)
    /// - Once CPU latches the edge and starts interrupt sequence (7 cycles),
    ///   the NMI line going low does NOT affect the interrupt
    /// - The "NMI line" from PPU to CPU is actually (VBlank flag AND NMI enable)
    /// - When this signal goes 0→1, CPU latches an internal NMI pending flag
    /// - CPU checks NMI pending flag between instructions, starts 7-cycle sequence
    /// - Once sequence starts, NMI line state doesn't matter
    ///
    /// Implementation:
    /// - `nmi_edge_pending` represents the CPU's internal NMI latch
    /// - We assert cpu.nmi_line ONLY while edge is pending (not yet acknowledged)
    /// - Once CPU acknowledges (clears nmi_edge_pending), line goes low immediately
    /// - The level signal (vblank_flag && nmi_enabled) is NOT used for NMI after edge detection
    ///
    /// Returns: true if cpu.nmi_line should be asserted
    pub fn shouldAssertNmiLine(
        self: *const VBlankLedger,
        cycle: u64,
        nmi_enabled: bool,
        vblank_flag: bool,
    ) bool {
        _ = vblank_flag; // Unused after edge detection
        // NMI line is asserted ONLY when edge is pending (latched but not yet acknowledged)
        return self.shouldNmiEdge(cycle, nmi_enabled);
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
    try testing.expect(!ledger.nmi_edge_pending);
    try testing.expectEqual(@as(u64, 0), ledger.last_set_cycle);
}

test "VBlankLedger: VBlank set marks span active" {
    var ledger = VBlankLedger{};

    ledger.recordVBlankSet(100, false); // NMI not enabled yet

    try testing.expect(ledger.span_active);
    try testing.expectEqual(@as(u64, 100), ledger.last_set_cycle);
}

test "VBlankLedger: PPUCTRL toggle during VBlank triggers NMI edge" {
    var ledger = VBlankLedger{};

    // Set VBlank active (NMI not enabled yet)
    ledger.recordVBlankSet(100, false);

    // Enable NMI during VBlank (0→1 transition)
    ledger.recordCtrlToggle(110, false, true);

    try testing.expect(ledger.nmi_edge_pending);
}

test "VBlankLedger: PPUCTRL toggle before VBlank does not trigger edge" {
    var ledger = VBlankLedger{};

    // Enable NMI before VBlank (0→1 transition, but no VBlank yet)
    ledger.recordCtrlToggle(50, false, true);

    try testing.expect(!ledger.nmi_edge_pending);

    // VBlank starts WITH NMI already enabled → should trigger edge
    ledger.recordVBlankSet(100, true);

    // Edge should now be pending (VBlank 0→1 with NMI pre-enabled)
    try testing.expect(ledger.nmi_edge_pending);
}

test "VBlankLedger: shouldNmiEdge returns true when conditions met" {
    var ledger = VBlankLedger{};

    ledger.recordVBlankSet(100, false);
    ledger.recordCtrlToggle(110, false, true);

    // NMI is enabled, VBlank is active, edge is pending
    try testing.expect(ledger.shouldNmiEdge(120, true));
}

test "VBlankLedger: shouldNmiEdge returns false after acknowledgment" {
    var ledger = VBlankLedger{};

    ledger.recordVBlankSet(100, false);
    ledger.recordCtrlToggle(110, false, true);

    // Acknowledge NMI
    ledger.acknowledgeCpu(120);

    // After acknowledgment, edge is no longer pending
    try testing.expect(!ledger.shouldNmiEdge(130, true));
}

test "VBlankLedger: $2002 read on exact set cycle suppresses NMI" {
    var ledger = VBlankLedger{};

    const vblank_set_cycle = 100;

    // VBlank sets with NMI already enabled → edge pending
    ledger.recordVBlankSet(vblank_set_cycle, true);
    try testing.expect(ledger.nmi_edge_pending);

    // Read $2002 on exact same cycle VBlank sets (race condition)
    ledger.recordStatusRead(vblank_set_cycle);

    // NMI should be suppressed due to race condition
    try testing.expect(!ledger.shouldNmiEdge(vblank_set_cycle + 1, true));
}

test "VBlankLedger: $2002 read after VBlank set does not suppress NMI" {
    var ledger = VBlankLedger{};

    // VBlank sets with NMI enabled → edge pending
    ledger.recordVBlankSet(100, true);
    try testing.expect(ledger.nmi_edge_pending);

    // Read $2002 a few cycles AFTER VBlank set (no race)
    ledger.recordStatusRead(105);

    // NMI should still fire (no race condition, read was not on exact cycle)
    try testing.expect(ledger.shouldNmiEdge(110, true));
}

test "VBlankLedger: reset clears all state" {
    var ledger = VBlankLedger{};

    ledger.recordVBlankSet(100, true);
    ledger.recordCtrlToggle(110, false, true);

    ledger.reset();

    try testing.expect(!ledger.span_active);
    try testing.expect(!ledger.nmi_edge_pending);
    try testing.expectEqual(@as(u64, 0), ledger.last_set_cycle);
}
