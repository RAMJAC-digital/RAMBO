//! VBlankLedger Unit Tests
//!
//! Direct tests for VBlankLedger state management and query functions.
//! These are white-box tests focusing on the ledger's internal logic.
//!
//! Coverage:
//! - Multiple $2002 reads within same VBlank period
//! - Flag persistence after reads
//! - Race condition handling
//! - VBlank span lifecycle
//! - NMI edge generation

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const VBlankLedger = RAMBO.EmulationState.VBlankLedger;

// ============================================================================
// Multiple Reads Within VBlank Period
// ============================================================================

test "VBlankLedger: Multiple $2002 reads - first returns true, rest return false" {
    var ledger = VBlankLedger{};

    // VBlank sets at cycle 100
    ledger.recordVBlankSet(100, false);

    // First read at cycle 110 - should return TRUE
    try testing.expect(ledger.isReadableFlagSet(110));
    ledger.recordStatusRead(110);

    // Second read at cycle 120 - should return FALSE (cleared by first read)
    try testing.expect(!ledger.isReadableFlagSet(120));
    ledger.recordStatusRead(120);

    // Third read at cycle 130 - should STILL return FALSE
    try testing.expect(!ledger.isReadableFlagSet(130));
}

test "VBlankLedger: Multiple reads with large cycle gaps" {
    var ledger = VBlankLedger{};

    // VBlank sets at cycle 1000
    ledger.recordVBlankSet(1000, false);

    // First read at cycle 1500
    try testing.expect(ledger.isReadableFlagSet(1500));
    ledger.recordStatusRead(1500);

    // Second read at cycle 5000 (large gap)
    try testing.expect(!ledger.isReadableFlagSet(5000));
    ledger.recordStatusRead(5000);

    // Third read at cycle 10000 (even larger gap)
    try testing.expect(!ledger.isReadableFlagSet(10000));
}

test "VBlankLedger: Consecutive reads at adjacent cycles" {
    var ledger = VBlankLedger{};

    ledger.recordVBlankSet(100, false);

    // Rapid consecutive reads
    try testing.expect(ledger.isReadableFlagSet(101));
    ledger.recordStatusRead(101);

    try testing.expect(!ledger.isReadableFlagSet(102));
    ledger.recordStatusRead(102);

    try testing.expect(!ledger.isReadableFlagSet(103));
    ledger.recordStatusRead(103);

    try testing.expect(!ledger.isReadableFlagSet(104));
}

// ============================================================================
// Race Condition (nesdev.org Spec)
// ============================================================================

test "VBlankLedger: Race condition - read on exact set cycle keeps flag set" {
    var ledger = VBlankLedger{};

    // VBlank sets at cycle 100
    ledger.recordVBlankSet(100, false);

    // Read on EXACT same cycle (race condition)
    try testing.expect(ledger.isReadableFlagSet(100));
    ledger.recordStatusRead(100);

    // Hardware behavior: Flag stays set after race condition read
    // (nesdev.org: "the flag will not be cleared")
    try testing.expect(ledger.isReadableFlagSet(101));
    try testing.expect(ledger.isReadableFlagSet(110));

    // Remains set until VBlank span ends or another read happens
    // after the race condition resolves
}

test "VBlankLedger: Race condition - read one cycle after set" {
    var ledger = VBlankLedger{};

    ledger.recordVBlankSet(100, false);

    // Read one cycle AFTER set (not race condition)
    try testing.expect(ledger.isReadableFlagSet(101));
    ledger.recordStatusRead(101);

    // Subsequent reads return false
    try testing.expect(!ledger.isReadableFlagSet(102));
}

// ============================================================================
// VBlank Span Lifecycle
// ============================================================================

test "VBlankLedger: VBlank span active between set and end" {
    var ledger = VBlankLedger{};

    // Before VBlank
    try testing.expect(!ledger.isReadableFlagSet(50));

    // Set VBlank at cycle 100
    ledger.recordVBlankSet(100, false);

    // During VBlank span
    try testing.expect(ledger.isReadableFlagSet(100));
    try testing.expect(ledger.isReadableFlagSet(150));
    try testing.expect(ledger.isReadableFlagSet(200));

    // End VBlank span at cycle 250
    ledger.recordVBlankSpanEnd(250);

    // After VBlank span ends
    try testing.expect(!ledger.isReadableFlagSet(251));
    try testing.expect(!ledger.isReadableFlagSet(300));
}

test "VBlankLedger: Read after span ends returns false" {
    var ledger = VBlankLedger{};

    ledger.recordVBlankSet(100, false);
    ledger.recordVBlankSpanEnd(200);

    // Query after span ended
    try testing.expect(!ledger.isReadableFlagSet(201));
}

test "VBlankLedger: Multiple VBlank cycles" {
    var ledger = VBlankLedger{};

    // First VBlank cycle
    ledger.recordVBlankSet(100, false);
    try testing.expect(ledger.isReadableFlagSet(110));
    ledger.recordStatusRead(110);
    try testing.expect(!ledger.isReadableFlagSet(120));
    ledger.recordVBlankSpanEnd(200);

    // Second VBlank cycle
    ledger.recordVBlankSet(300, false);
    try testing.expect(ledger.isReadableFlagSet(310));
    ledger.recordStatusRead(310);
    try testing.expect(!ledger.isReadableFlagSet(320));
    ledger.recordVBlankSpanEnd(400);

    // Third VBlank cycle
    ledger.recordVBlankSet(500, false);
    try testing.expect(ledger.isReadableFlagSet(510));
}

// ============================================================================
// NMI Edge Generation
// ============================================================================

test "VBlankLedger: NMI enabled - produces NMI edge on set" {
    var ledger = VBlankLedger{};

    // VBlank with NMI enabled
    ledger.recordVBlankSet(100, true);

    // Should have NMI edge pending
    try testing.expect(ledger.shouldNmiEdge(110, true));
    try testing.expect(ledger.shouldAssertNmiLine(110, true));

    // CPU acknowledges NMI
    ledger.acknowledgeCpu(115);

    // No longer pending
    try testing.expect(!ledger.shouldNmiEdge(120, true));
    try testing.expect(!ledger.shouldAssertNmiLine(120, true));
}

test "VBlankLedger: NMI disabled - no NMI edge" {
    var ledger = VBlankLedger{};

    // VBlank with NMI disabled
    ledger.recordVBlankSet(100, false);

    // Should NOT have NMI edge
    try testing.expect(!ledger.shouldNmiEdge(110, false));
}

test "VBlankLedger: $2002 read does not consume NMI edge" {
    var ledger = VBlankLedger{};

    // VBlank with NMI enabled
    ledger.recordVBlankSet(100, true);
    try testing.expect(ledger.shouldNmiEdge(110, true));

    // Read $2002 multiple times
    ledger.recordStatusRead(110);
    try testing.expect(ledger.shouldNmiEdge(115, true)); // Still pending

    ledger.recordStatusRead(120);
    try testing.expect(ledger.shouldNmiEdge(125, true)); // Still pending

    // Only CPU acknowledgement clears it
    ledger.acknowledgeCpu(130);
    try testing.expect(!ledger.shouldNmiEdge(135, true));
}

// ============================================================================
// Edge Cases
// ============================================================================

test "VBlankLedger: Read before any VBlank set returns false" {
    var ledger = VBlankLedger{};

    // Query before any VBlank
    try testing.expect(!ledger.isReadableFlagSet(50));
}

test "VBlankLedger: Reset clears all state" {
    var ledger = VBlankLedger{};

    ledger.recordVBlankSet(100, true);
    ledger.recordStatusRead(110);

    // Reset
    ledger.reset();

    // All state cleared
    try testing.expect(!ledger.isReadableFlagSet(200));
    try testing.expect(!ledger.shouldNmiEdge(200, false));
}

test "VBlankLedger: Read at cycle 0 (race condition)" {
    var ledger = VBlankLedger{};

    ledger.recordVBlankSet(0, false);
    try testing.expect(ledger.isReadableFlagSet(0));
    ledger.recordStatusRead(0); // Race condition read

    // Flag stays set (race condition behavior)
    try testing.expect(ledger.isReadableFlagSet(1));
    try testing.expect(ledger.isReadableFlagSet(10));
}

// ============================================================================
// Regression Tests for Bug Fix
// ============================================================================

test "VBlankLedger: REGRESSION - Bug fix for line 208" {
    // This test verifies the fix for the critical bug where
    // isReadableFlagSet() was using last_clear_cycle instead of
    // last_status_read_cycle in the comparison.
    //
    // Before fix: Second read would incorrectly return true
    // After fix: Second read correctly returns false

    var ledger = VBlankLedger{};

    ledger.recordVBlankSet(82181, false);

    // First read at cycle 82185
    try testing.expect(ledger.isReadableFlagSet(82185));
    ledger.recordStatusRead(82185);

    // CRITICAL: Second read at cycle 82190 must return FALSE
    // Before fix, this would incorrectly return true because
    // last_clear_cycle (82185) was not > last_set_cycle (82181)
    const second_read_result = ledger.isReadableFlagSet(82190);
    try testing.expect(!second_read_result);
}

test "VBlankLedger: REGRESSION - SMB polling pattern" {
    // Simulates Super Mario Bros VBlank polling pattern:
    // 1. VBlank sets at scanline 241.1
    // 2. CPU polls $2002 multiple times in rapid succession
    // 3. Only first read should see VBlank flag

    var ledger = VBlankLedger{};

    // VBlank sets (scanline 241.1 in real cycles)
    const vblank_cycle: u64 = 82181;
    ledger.recordVBlankSet(vblank_cycle, false);

    // SMB polls $2002 - first poll
    const poll1 = vblank_cycle + 10;
    try testing.expect(ledger.isReadableFlagSet(poll1));
    ledger.recordStatusRead(poll1);

    // SMB polls $2002 - second poll (should be cleared)
    const poll2 = poll1 + 5;
    try testing.expect(!ledger.isReadableFlagSet(poll2));
    ledger.recordStatusRead(poll2);

    // SMB polls $2002 - third poll (still cleared)
    const poll3 = poll2 + 5;
    try testing.expect(!ledger.isReadableFlagSet(poll3));
}
