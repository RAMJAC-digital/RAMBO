//! VBlank Flag Determinism Test
//!
//! This test explicitly verifies the EXACT behavior of VBlankLedger
//! with detailed state logging to identify the SMB failure root cause.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const VBlankLedger = RAMBO.EmulationState.VBlankLedger;

test "VBlankLedger: DETERMINISM - Set, Read, Query sequence" {
    var ledger = VBlankLedger{};

    std.debug.print("\n=== VBlankLedger Determinism Test ===\n", .{});

    // STEP 1: VBlank sets at cycle 100
    std.debug.print("STEP 1: VBlank sets at cycle 100\n", .{});
    ledger.recordVBlankSet(100, false);
    std.debug.print("  last_set_cycle={}, last_status_read_cycle={}, span_active={}\n", .{
        ledger.last_set_cycle,
        ledger.last_status_read_cycle,
        ledger.span_active,
    });

    // STEP 2: Query at cycle 100 (same cycle - race condition)
    std.debug.print("\nSTEP 2: Query at cycle 100 (race condition)\n", .{});
    const flag_at_100 = ledger.isReadableFlagSet(100);
    std.debug.print("  Result: {}\n", .{flag_at_100});
    std.debug.print("  Check: last_status_read_cycle({}) == last_set_cycle({})? {}\n", .{
        ledger.last_status_read_cycle,
        ledger.last_set_cycle,
        ledger.last_status_read_cycle == ledger.last_set_cycle,
    });
    try testing.expect(flag_at_100); // Should be TRUE

    // STEP 3: Record status read at cycle 100
    std.debug.print("\nSTEP 3: Record status read at cycle 100\n", .{});
    ledger.recordStatusRead(100);
    std.debug.print("  last_set_cycle={}, last_status_read_cycle={}, span_active={}\n", .{
        ledger.last_set_cycle,
        ledger.last_status_read_cycle,
        ledger.span_active,
    });

    // STEP 4: Query at cycle 101 (after race condition read)
    std.debug.print("\nSTEP 4: Query at cycle 101 (after race condition read)\n", .{});
    const flag_at_101 = ledger.isReadableFlagSet(101);
    std.debug.print("  Result: {}\n", .{flag_at_101});
    std.debug.print("  Check 1: last_status_read_cycle({}) == last_set_cycle({})? {}\n", .{
        ledger.last_status_read_cycle,
        ledger.last_set_cycle,
        ledger.last_status_read_cycle == ledger.last_set_cycle,
    });
    std.debug.print("  Check 2: last_status_read_cycle({}) > last_set_cycle({})? {}\n", .{
        ledger.last_status_read_cycle,
        ledger.last_set_cycle,
        ledger.last_status_read_cycle > ledger.last_set_cycle,
    });

    // CRITICAL: This is the PROBLEM!
    // After race condition read, last_status_read_cycle == last_set_cycle
    // So check 1 returns TRUE, flag stays set FOREVER
    std.debug.print("\n!!! PROBLEM IDENTIFIED !!!\n", .{});
    std.debug.print("Race condition check persists forever because equality persists!\n", .{});

    // STEP 5: Record another read at cycle 110
    std.debug.print("\nSTEP 5: Record status read at cycle 110\n", .{});
    ledger.recordStatusRead(110);
    std.debug.print("  last_set_cycle={}, last_status_read_cycle={}\n", .{
        ledger.last_set_cycle,
        ledger.last_status_read_cycle,
    });

    // STEP 6: Query at cycle 120
    std.debug.print("\nSTEP 6: Query at cycle 120 (after normal read)\n", .{});
    const flag_at_120 = ledger.isReadableFlagSet(120);
    std.debug.print("  Result: {}\n", .{flag_at_120});
    std.debug.print("  Check 1: last_status_read_cycle({}) == last_set_cycle({})? {}\n", .{
        ledger.last_status_read_cycle,
        ledger.last_set_cycle,
        ledger.last_status_read_cycle == ledger.last_set_cycle,
    });
    std.debug.print("  Check 2: last_status_read_cycle({}) > last_set_cycle({})? {}\n", .{
        ledger.last_status_read_cycle,
        ledger.last_set_cycle,
        ledger.last_status_read_cycle > ledger.last_set_cycle,
    });

    // NOW it should be cleared
    try testing.expect(!flag_at_120);
}

test "VBlankLedger: DETERMINISM - Normal case (no race condition)" {
    var ledger = VBlankLedger{};

    std.debug.print("\n=== Normal Case (No Race Condition) ===\n", .{});

    // VBlank sets at cycle 100
    std.debug.print("VBlank sets at cycle 100\n", .{});
    ledger.recordVBlankSet(100, false);

    // Read happens AFTER set (cycle 110 - no race condition)
    std.debug.print("Status read at cycle 110 (10 cycles after set)\n", .{});
    ledger.recordStatusRead(110);
    std.debug.print("  last_set_cycle={}, last_status_read_cycle={}\n", .{
        ledger.last_set_cycle,
        ledger.last_status_read_cycle,
    });

    // Query at cycle 120
    std.debug.print("Query at cycle 120\n", .{});
    const flag = ledger.isReadableFlagSet(120);
    std.debug.print("  Result: {}\n", .{flag});
    std.debug.print("  Check 1: last_status_read_cycle({}) == last_set_cycle({})? {}\n", .{
        ledger.last_status_read_cycle,
        ledger.last_set_cycle,
        ledger.last_status_read_cycle == ledger.last_set_cycle,
    });
    std.debug.print("  Check 2: last_status_read_cycle({}) > last_set_cycle({})? {}\n", .{
        ledger.last_status_read_cycle,
        ledger.last_set_cycle,
        ledger.last_status_read_cycle > ledger.last_set_cycle,
    });

    // Should be FALSE (110 > 100, so cleared)
    try testing.expect(!flag);
}
