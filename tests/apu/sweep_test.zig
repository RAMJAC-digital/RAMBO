const std = @import("std");
const testing = std.testing;
const ApuModule = @import("RAMBO").Apu;
const ApuState = ApuModule.State.ApuState;
const ApuLogic = ApuModule.Logic;
const SweepModule = ApuModule.Sweep;
const Sweep = SweepModule.Sweep;

// ============================================================================
// Sweep Divider Tests
// ============================================================================

test "Sweep: Divider countdown" {
    var sweep = Sweep{};
    var period: u11 = 100;

    sweep.period = 3;
    sweep.divider = 3;
    sweep.enabled = true;
    sweep.shift = 1;

    // Clock 1-3: Divider counts down
    SweepModule.clock(&sweep, &period, false);
    try testing.expectEqual(@as(u3, 2), sweep.divider);

    SweepModule.clock(&sweep, &period, false);
    try testing.expectEqual(@as(u3, 1), sweep.divider);

    SweepModule.clock(&sweep, &period, false);
    try testing.expectEqual(@as(u3, 0), sweep.divider);
}

test "Sweep: Divider reload on zero" {
    var sweep = Sweep{};
    var period: u11 = 100;

    sweep.period = 2;
    sweep.divider = 0;
    sweep.enabled = true;
    sweep.shift = 1;

    SweepModule.clock(&sweep, &period, false);
    try testing.expectEqual(@as(u3, 2), sweep.divider);
}

test "Sweep: Reload flag triggers immediate reload" {
    var sweep = Sweep{};
    var period: u11 = 100;

    sweep.period = 5;
    sweep.divider = 3;
    sweep.reload_flag = true;

    SweepModule.clock(&sweep, &period, false);
    try testing.expectEqual(@as(u3, 5), sweep.divider);
    try testing.expect(!sweep.reload_flag);
}

// ============================================================================
// Period Modification Tests
// ============================================================================

test "Sweep: Period increase (negate = false)" {
    var sweep = Sweep{};
    var period: u11 = 100;

    sweep.period = 0;
    sweep.divider = 0;
    sweep.enabled = true;
    sweep.negate = false;
    sweep.shift = 1; // change_amount = 100 >> 1 = 50

    // Divider expires, should update period
    SweepModule.clock(&sweep, &period, false);

    // Expected: 100 + 50 = 150
    try testing.expectEqual(@as(u11, 150), period);
}

test "Sweep: Period decrease with two's complement (Pulse 2)" {
    var sweep = Sweep{};
    var period: u11 = 100;

    sweep.period = 0;
    sweep.divider = 0;
    sweep.enabled = true;
    sweep.negate = true;
    sweep.shift = 2; // change_amount = 100 >> 2 = 25

    // Pulse 2 uses two's complement: 100 - 25 = 75
    SweepModule.clock(&sweep, &period, false);

    try testing.expectEqual(@as(u11, 75), period);
}

test "Sweep: Period decrease with one's complement (Pulse 1)" {
    var sweep = Sweep{};
    var period: u11 = 100;

    sweep.period = 0;
    sweep.divider = 0;
    sweep.enabled = true;
    sweep.negate = true;
    sweep.shift = 2; // change_amount = 100 >> 2 = 25

    // Pulse 1 uses one's complement: 100 - 25 - 1 = 74
    SweepModule.clock(&sweep, &period, true);

    try testing.expectEqual(@as(u11, 74), period);
}

test "Sweep: One's complement vs two's complement difference" {
    var sweep1 = Sweep{};
    var sweep2 = Sweep{};
    var period1: u11 = 200;
    var period2: u11 = 200;

    // Same sweep configuration
    sweep1.period = 0;
    sweep1.divider = 0;
    sweep1.enabled = true;
    sweep1.negate = true;
    sweep1.shift = 1;

    sweep2.period = 0;
    sweep2.divider = 0;
    sweep2.enabled = true;
    sweep2.negate = true;
    sweep2.shift = 1;

    // Clock both with different complement modes
    SweepModule.clock(&sweep1, &period1, true); // Pulse 1: one's complement
    SweepModule.clock(&sweep2, &period2, false); // Pulse 2: two's complement

    // Pulse 1: 200 - 100 - 1 = 99
    // Pulse 2: 200 - 100 = 100
    try testing.expectEqual(@as(u11, 99), period1);
    try testing.expectEqual(@as(u11, 100), period2);
}

// ============================================================================
// Sweep Update Conditions Tests
// ============================================================================

test "Sweep: No update when disabled" {
    var sweep = Sweep{};
    var period: u11 = 100;

    sweep.period = 0;
    sweep.divider = 0;
    sweep.enabled = false; // Disabled
    sweep.shift = 1;

    SweepModule.clock(&sweep, &period, false);

    // Period should not change
    try testing.expectEqual(@as(u11, 100), period);
}

test "Sweep: No update when shift is zero" {
    var sweep = Sweep{};
    var period: u11 = 100;

    sweep.period = 0;
    sweep.divider = 0;
    sweep.enabled = true;
    sweep.shift = 0; // Shift = 0

    SweepModule.clock(&sweep, &period, false);

    // Period should not change
    try testing.expectEqual(@as(u11, 100), period);
}

test "Sweep: No update when divider not zero" {
    var sweep = Sweep{};
    var period: u11 = 100;

    sweep.period = 0;
    sweep.divider = 1; // Not zero
    sweep.enabled = true;
    sweep.shift = 1;

    SweepModule.clock(&sweep, &period, false);

    // Period should not change
    try testing.expectEqual(@as(u11, 100), period);
}

test "Sweep: No update when target exceeds $7FF" {
    var sweep = Sweep{};
    var period: u11 = 0x600; // High starting period

    sweep.period = 0;
    sweep.divider = 0;
    sweep.enabled = true;
    sweep.negate = false; // Increasing
    sweep.shift = 1; // Would add 0x300, result = 0x900 > 0x7FF

    SweepModule.clock(&sweep, &period, false);

    // Period should not change (target > $7FF)
    try testing.expectEqual(@as(u11, 0x600), period);
}

// ============================================================================
// Muting Conditions Tests
// ============================================================================

test "Sweep: Muting when period < 8" {
    var sweep = Sweep{};
    const period: u11 = 5;

    const muted = SweepModule.isMuting(&sweep, period, false);
    try testing.expect(muted);
}

test "Sweep: Not muting when period >= 8" {
    var sweep = Sweep{};
    const period: u11 = 8;

    const muted = SweepModule.isMuting(&sweep, period, false);
    try testing.expect(!muted);
}

test "Sweep: Muting when target > $7FF (non-negate mode)" {
    var sweep = Sweep{};
    const period: u11 = 0x600;

    sweep.negate = false;
    sweep.shift = 1; // Target = 0x600 + 0x300 = 0x900 > 0x7FF

    const muted = SweepModule.isMuting(&sweep, period, false);
    try testing.expect(muted);
}

test "Sweep: Not muting when target <= $7FF (non-negate mode)" {
    var sweep = Sweep{};
    const period: u11 = 0x400;

    sweep.negate = false;
    sweep.shift = 1; // Target = 0x400 + 0x200 = 0x600 <= 0x7FF

    const muted = SweepModule.isMuting(&sweep, period, false);
    try testing.expect(!muted);
}

test "Sweep: Not muting in negate mode (decreasing frequency)" {
    var sweep = Sweep{};
    const period: u11 = 0x700;

    sweep.negate = true;
    sweep.shift = 1; // Target = 0x700 - 0x380 = 0x380

    const muted = SweepModule.isMuting(&sweep, period, false);
    try testing.expect(!muted);
}

// ============================================================================
// Register Write Tests
// ============================================================================

test "Sweep: writeControl sets all fields" {
    var sweep = Sweep{};

    // Write: EPPP NSSS = 0b10101101
    // E=1, PPP=010, N=1, SSS=101
    SweepModule.writeControl(&sweep, 0b10101101);

    try testing.expect(sweep.enabled);
    try testing.expectEqual(@as(u3, 2), sweep.period);
    try testing.expect(sweep.negate);
    try testing.expectEqual(@as(u3, 5), sweep.shift);
    try testing.expect(sweep.reload_flag);
}

test "Sweep: writeControl clears flags" {
    var sweep = Sweep{};
    sweep.enabled = true;
    sweep.negate = true;

    // Write: 0b00000000 (all disabled)
    SweepModule.writeControl(&sweep, 0b00000000);

    try testing.expect(!sweep.enabled);
    try testing.expectEqual(@as(u3, 0), sweep.period);
    try testing.expect(!sweep.negate);
    try testing.expectEqual(@as(u3, 0), sweep.shift);
    try testing.expect(sweep.reload_flag); // Always set on write
}

// ============================================================================
// Integration Tests with ApuState
// ============================================================================

test "Sweep: Pulse 1 register write integration" {
    var apu = ApuState.init();

    // Write to $4001: EPPP NSSS = 0b10110011
    ApuLogic.writePulse1(&apu, 1, 0b10110011);

    try testing.expect(apu.pulse1_sweep.enabled);
    try testing.expectEqual(@as(u3, 3), apu.pulse1_sweep.period);
    try testing.expect(!apu.pulse1_sweep.negate);
    try testing.expectEqual(@as(u3, 3), apu.pulse1_sweep.shift);
    try testing.expect(apu.pulse1_sweep.reload_flag);
}

test "Sweep: Pulse 2 register write integration" {
    var apu = ApuState.init();

    // Write to $4005: EPPP NSSS = 0b11001010
    // E=1, PPP=100, N=1, SSS=010
    ApuLogic.writePulse2(&apu, 1, 0b11001010);

    try testing.expect(apu.pulse2_sweep.enabled);
    try testing.expectEqual(@as(u3, 4), apu.pulse2_sweep.period);
    try testing.expect(apu.pulse2_sweep.negate); // Negate is set (bit 3 = 1)
    try testing.expectEqual(@as(u3, 2), apu.pulse2_sweep.shift);
}

test "Sweep: Pulse 1 period registers" {
    var apu = ApuState.init();

    // Write timer low: $4002 = 0xFF
    ApuLogic.writePulse1(&apu, 2, 0xFF);
    try testing.expectEqual(@as(u11, 0x0FF), apu.pulse1_period);

    // Write timer high: $4003 = 0b00000101 (high bits = 101)
    ApuLogic.writePulse1(&apu, 3, 0b00000101);
    try testing.expectEqual(@as(u11, 0x5FF), apu.pulse1_period);
}

test "Sweep: Pulse 2 period registers" {
    var apu = ApuState.init();

    // Write timer low: $4006 = 0xAB
    ApuLogic.writePulse2(&apu, 2, 0xAB);
    try testing.expectEqual(@as(u11, 0x0AB), apu.pulse2_period);

    // Write timer high: $4007 = 0b00000011 (high bits = 011)
    ApuLogic.writePulse2(&apu, 3, 0b00000011);
    try testing.expectEqual(@as(u11, 0x3AB), apu.pulse2_period);
}

// ============================================================================
// Complete Sweep Cycle Tests
// ============================================================================

test "Sweep: Complete sweep cycle with period update" {
    var sweep = Sweep{};
    var period: u11 = 200;

    // EPPP NSSS = 1_010_0_010 (E=1, PPP=010=2, N=0, SSS=010=2)
    SweepModule.writeControl(&sweep, 0b10100010); // enabled, period=2, shift=2

    // First clock: Reload divider (reload_flag set by writeControl)
    SweepModule.clock(&sweep, &period, false);
    try testing.expectEqual(@as(u3, 2), sweep.divider);
    // change_amount = 200 >> 2 = 50
    // new_period = 200 + 50 = 250 (updated immediately on reload)
    try testing.expectEqual(@as(u11, 250), period);

    // Second clock: Divider 2 -> 1
    SweepModule.clock(&sweep, &period, false);
    try testing.expectEqual(@as(u3, 1), sweep.divider);
    try testing.expectEqual(@as(u11, 250), period);

    // Third clock: Divider 1 -> 0
    SweepModule.clock(&sweep, &period, false);
    try testing.expectEqual(@as(u3, 0), sweep.divider);
    try testing.expectEqual(@as(u11, 250), period);

    // Fourth clock: Divider expires, update period again
    // change_amount = 250 >> 2 = 62
    // new_period = 250 + 62 = 312
    SweepModule.clock(&sweep, &period, false);
    try testing.expectEqual(@as(u11, 312), period);
    try testing.expectEqual(@as(u3, 2), sweep.divider); // Reloaded
}

test "Sweep: Continuous sweep with multiple updates" {
    var sweep = Sweep{};
    var period: u11 = 100;

    SweepModule.writeControl(&sweep, 0b10000001); // enabled, period=0, shift=1

    // First update: 100 + 50 = 150
    SweepModule.clock(&sweep, &period, false);
    try testing.expectEqual(@as(u11, 150), period);

    // Second update: 150 + 75 = 225
    SweepModule.clock(&sweep, &period, false);
    try testing.expectEqual(@as(u11, 225), period);

    // Third update: 225 + 112 = 337
    SweepModule.clock(&sweep, &period, false);
    try testing.expectEqual(@as(u11, 337), period);
}

test "Sweep: Negate mode sweeping down" {
    var sweep = Sweep{};
    var period: u11 = 200;

    SweepModule.writeControl(&sweep, 0b10001001); // enabled, period=0, negate=1, shift=1

    // Updates with two's complement negate
    // First: 200 - 100 = 100
    SweepModule.clock(&sweep, &period, false);
    try testing.expectEqual(@as(u11, 100), period);

    // Second: 100 - 50 = 50
    SweepModule.clock(&sweep, &period, false);
    try testing.expectEqual(@as(u11, 50), period);

    // Third: 50 - 25 = 25
    SweepModule.clock(&sweep, &period, false);
    try testing.expectEqual(@as(u11, 25), period);
}
