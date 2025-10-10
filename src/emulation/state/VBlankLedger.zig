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

        // TEMP DEBUG
        std.debug.print("[VBlankLedger] recordVBlankSet: was_active={}, nmi_enabled={}, will_set_edge={}\n", .{was_active, nmi_enabled, !was_active and nmi_enabled});

        // Detect NMI edge: 0→1 transition of (VBlank span AND NMI_enable)
        // If VBlank sets while NMI is already enabled, fire NMI edge
        if (!was_active and nmi_enabled) {
            self.nmi_edge_pending = true;
            std.debug.print("[VBlankLedger] NMI EDGE PENDING SET!\n", .{});
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
    ///
    /// VBlank Migration (Phase 4): Removed vblank_flag parameter - no longer needed
    /// The ledger tracks VBlank span internally and doesn't need external flag state.
    ///
    /// Returns: true if cpu.nmi_line should be asserted
    pub fn shouldAssertNmiLine(
        self: *const VBlankLedger,
        cycle: u64,
        nmi_enabled: bool,
    ) bool {
        // NMI line is asserted ONLY when edge is pending (latched but not yet acknowledged)
        return self.shouldNmiEdge(cycle, nmi_enabled);
    }

    /// CPU acknowledged NMI (during interrupt sequence cycle 6)
    /// Clears pending edge flag
    pub fn acknowledgeCpu(self: *VBlankLedger, cycle: u64) void {
        self.nmi_edge_pending = false;
        self.last_cpu_ack_cycle = cycle;
    }

    /// Query if readable VBlank flag should be set
    /// This is the hardware-visible flag (bit 7 of $2002 PPUSTATUS)
    ///
    /// Hardware behavior (nesdev.org/wiki/PPU_registers):
    /// - Flag sets at scanline 241 dot 1
    /// - Flag clears at scanline 261 dot 1 OR when $2002 read
    /// - EXCEPTION: If $2002 read on EXACT cycle flag set, flag STAYS set (NMI suppressed)
    ///
    /// This decouples readable flag state from internal NMI edge state.
    /// The readable flag can be cleared (by $2002 read) while NMI edge remains latched.
    ///
    /// Returns: true if VBlank flag should appear set when reading $2002
    pub fn isReadableFlagSet(self: *const VBlankLedger, current_cycle: u64) bool {
        _ = current_cycle; // Reserved for future use if needed

        // VBlank flag is NOT active if span hasn't started yet
        if (!self.span_active) return false;

        // Race condition: If $2002 read on exact cycle VBlank set,
        // flag STAYS set (but NMI is suppressed - handled by shouldNmiEdge)
        // This is documented hardware behavior on nesdev.org
        if (self.last_status_read_cycle == self.last_set_cycle) {
            // Reading on exact set cycle preserves the flag
            return true;
        }

        // Normal case: Check if flag was cleared by read
        // If last_clear_cycle > last_set_cycle, flag was cleared
        if (self.last_clear_cycle > self.last_set_cycle) {
            return false; // Cleared by $2002 read or scanline 261.1
        }

        // Flag is active (set and not yet cleared)
        return true;
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

test "VBlankLedger: NMI edge persists after VBlank span ends" {
    var ledger = VBlankLedger{};

    // VBlank sets with NMI enabled → edge pending
    ledger.recordVBlankSet(100, true);
    try testing.expect(ledger.span_active);
    try testing.expect(ledger.nmi_edge_pending);

    // VBlank span ends at scanline 261.1 (pre-render)
    ledger.recordVBlankSpanEnd(200);

    // Span is no longer active
    try testing.expect(!ledger.span_active);

    // CRITICAL: NMI edge should STILL be pending (persists until CPU acknowledges)
    try testing.expect(ledger.nmi_edge_pending);

    // NMI line should still be asserted
    try testing.expect(ledger.shouldAssertNmiLine(210, true));

    // shouldNmiEdge should return true (edge still pending)
    try testing.expect(ledger.shouldNmiEdge(210, true));

    // CPU acknowledges NMI
    ledger.acknowledgeCpu(220);

    // NOW edge should be cleared
    try testing.expect(!ledger.nmi_edge_pending);
    try testing.expect(!ledger.shouldAssertNmiLine(230, true));
}

test "VBlankLedger: isReadableFlagSet returns true after VBlank set" {
    var ledger = VBlankLedger{};

    // VBlank not set yet
    try testing.expect(!ledger.isReadableFlagSet(50));

    // Set VBlank (NMI not enabled)
    ledger.recordVBlankSet(100, false);

    // Readable flag should be true
    try testing.expect(ledger.isReadableFlagSet(110));
    try testing.expect(ledger.isReadableFlagSet(150));
}

test "VBlankLedger: isReadableFlagSet returns false after $2002 read" {
    var ledger = VBlankLedger{};

    // Set VBlank
    ledger.recordVBlankSet(100, false);
    try testing.expect(ledger.isReadableFlagSet(105));

    // Read $2002 at cycle 110
    ledger.recordStatusRead(110);

    // Readable flag should now be false (cleared by read)
    try testing.expect(!ledger.isReadableFlagSet(120));
    try testing.expect(!ledger.isReadableFlagSet(150));
}

test "VBlankLedger: isReadableFlagSet stays true if read on exact set cycle" {
    var ledger = VBlankLedger{};

    const set_cycle = 100;

    // Set VBlank and read $2002 on SAME cycle (race condition)
    ledger.recordVBlankSet(set_cycle, false);
    ledger.recordStatusRead(set_cycle);

    // CRITICAL: Flag should STAY set despite read (hardware race condition behavior)
    try testing.expect(ledger.isReadableFlagSet(set_cycle + 1));
    try testing.expect(ledger.isReadableFlagSet(set_cycle + 100));
}

test "VBlankLedger: isReadableFlagSet returns false after VBlank span end" {
    var ledger = VBlankLedger{};

    // Set VBlank
    ledger.recordVBlankSet(100, false);
    try testing.expect(ledger.isReadableFlagSet(150));

    // End VBlank span at scanline 261.1
    ledger.recordVBlankSpanEnd(200);

    // Readable flag should be false (span ended)
    try testing.expect(!ledger.isReadableFlagSet(210));
}

test "VBlankLedger: isReadableFlagSet race condition does not affect NMI suppression" {
    var ledger = VBlankLedger{};

    const set_cycle = 100;

    // Set VBlank with NMI enabled, read on exact same cycle
    ledger.recordVBlankSet(set_cycle, true);
    ledger.recordStatusRead(set_cycle);

    // Readable flag stays set (race condition behavior)
    try testing.expect(ledger.isReadableFlagSet(set_cycle + 1));

    // But NMI should be suppressed (existing shouldNmiEdge handles this)
    try testing.expect(!ledger.shouldNmiEdge(set_cycle + 1, true));
}

test "VBlankLedger: isReadableFlagSet multiple reads only first clears" {
    var ledger = VBlankLedger{};

    // Set VBlank
    ledger.recordVBlankSet(100, false);
    try testing.expect(ledger.isReadableFlagSet(105));

    // First read clears flag
    ledger.recordStatusRead(110);
    try testing.expect(!ledger.isReadableFlagSet(115));

    // Second read doesn't change anything (already cleared)
    ledger.recordStatusRead(120);
    try testing.expect(!ledger.isReadableFlagSet(125));

    // VBlank sets again in next frame
    ledger.recordVBlankSet(200, false);
    try testing.expect(ledger.isReadableFlagSet(205));
}
