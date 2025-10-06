const std = @import("std");
const testing = std.testing;
const ApuModule = @import("RAMBO").Apu;
const ApuState = ApuModule.State.ApuState;
const ApuLogic = ApuModule.Logic;

// ============================================================================
// Linear Counter Reload Tests
// ============================================================================

test "Linear Counter: Reload flag triggers reload" {
    var apu = ApuState.init();
    apu.triangle_linear_reload = 50;
    apu.triangle_linear_counter = 10;
    apu.triangle_linear_reload_flag = true;

    // Clock - should reload counter
    ApuLogic.clockLinearCounter(&apu);

    try testing.expectEqual(@as(u7, 50), apu.triangle_linear_counter);
}

test "Linear Counter: Reload flag set by $400B write" {
    var apu = ApuState.init();
    apu.triangle_enabled = true;

    // Write to $400B (triangle length counter load)
    ApuLogic.writeTriangle(&apu, 3, 0b11111000);

    try testing.expect(apu.triangle_linear_reload_flag);
}

// ============================================================================
// Linear Counter Countdown Tests
// ============================================================================

test "Linear Counter: Counts down when reload flag clear" {
    var apu = ApuState.init();
    apu.triangle_linear_counter = 5;
    apu.triangle_linear_reload_flag = false;
    apu.triangle_halt = false;

    ApuLogic.clockLinearCounter(&apu);
    try testing.expectEqual(@as(u7, 4), apu.triangle_linear_counter);

    ApuLogic.clockLinearCounter(&apu);
    try testing.expectEqual(@as(u7, 3), apu.triangle_linear_counter);
}

test "Linear Counter: Stops at zero" {
    var apu = ApuState.init();
    apu.triangle_linear_counter = 1;
    apu.triangle_linear_reload_flag = false;
    apu.triangle_halt = false;

    ApuLogic.clockLinearCounter(&apu);
    try testing.expectEqual(@as(u7, 0), apu.triangle_linear_counter);

    // Should stay at zero
    ApuLogic.clockLinearCounter(&apu);
    try testing.expectEqual(@as(u7, 0), apu.triangle_linear_counter);
}

// ============================================================================
// Reload Flag Clearing Tests
// ============================================================================

test "Linear Counter: Reload flag cleared when halt flag clear" {
    var apu = ApuState.init();
    apu.triangle_linear_reload = 30;
    apu.triangle_linear_reload_flag = true;
    apu.triangle_halt = false;

    // First clock: Reload counter, clear reload flag
    ApuLogic.clockLinearCounter(&apu);

    try testing.expectEqual(@as(u7, 30), apu.triangle_linear_counter);
    try testing.expect(!apu.triangle_linear_reload_flag);

    // Second clock: Should count down (not reload)
    ApuLogic.clockLinearCounter(&apu);

    try testing.expectEqual(@as(u7, 29), apu.triangle_linear_counter);
}

test "Linear Counter: Reload flag persists when halt flag set" {
    var apu = ApuState.init();
    apu.triangle_linear_reload = 40;
    apu.triangle_linear_reload_flag = true;
    apu.triangle_halt = true;

    // Multiple clocks with halt flag set
    for (0..5) |_| {
        ApuLogic.clockLinearCounter(&apu);
    }

    // Reload flag should still be set
    try testing.expect(apu.triangle_linear_reload_flag);
    // Counter should keep reloading
    try testing.expectEqual(@as(u7, 40), apu.triangle_linear_counter);
}

// ============================================================================
// Register Write Integration Tests
// ============================================================================

test "Linear Counter: $4008 sets reload value" {
    var apu = ApuState.init();

    // Write to $4008: CRRR RRRR = 0b01010101 (halt clear, reload = 85)
    ApuLogic.writeTriangle(&apu, 0, 0b01010101);

    try testing.expectEqual(@as(u7, 85), apu.triangle_linear_reload);
    try testing.expect(!apu.triangle_halt);
}

test "Linear Counter: $4008 sets halt flag and reload value" {
    var apu = ApuState.init();

    // Write to $4008: 0b11001100 (halt set, reload = 76)
    ApuLogic.writeTriangle(&apu, 0, 0b11001100);

    try testing.expectEqual(@as(u7, 76), apu.triangle_linear_reload);
    try testing.expect(apu.triangle_halt);
}

test "Linear Counter: $400B sets reload flag" {
    var apu = ApuState.init();
    apu.triangle_enabled = true;

    // Write to $400B
    ApuLogic.writeTriangle(&apu, 3, 0b11111000);

    try testing.expect(apu.triangle_linear_reload_flag);
}

// ============================================================================
// Complete Cycles Tests
// ============================================================================

test "Linear Counter: Complete reload and countdown cycle" {
    var apu = ApuState.init();

    // Setup: reload value = 60, trigger reload
    ApuLogic.writeTriangle(&apu, 0, 0b00111100); // reload = 60, halt clear
    ApuLogic.writeTriangle(&apu, 3, 0b00000000); // trigger reload flag
    apu.triangle_enabled = true;

    try testing.expectEqual(@as(u7, 60), apu.triangle_linear_reload);
    try testing.expect(apu.triangle_linear_reload_flag);

    // First clock: Should reload counter and clear reload flag
    ApuLogic.clockLinearCounter(&apu);

    try testing.expectEqual(@as(u7, 60), apu.triangle_linear_counter);
    try testing.expect(!apu.triangle_linear_reload_flag);

    // Next 10 clocks: Should count down
    for (0..10) |_| {
        ApuLogic.clockLinearCounter(&apu);
    }

    try testing.expectEqual(@as(u7, 50), apu.triangle_linear_counter);
}

test "Linear Counter: Complete countdown to zero" {
    var apu = ApuState.init();

    // Setup: small counter value
    apu.triangle_linear_reload = 3;
    apu.triangle_linear_reload_flag = true;
    apu.triangle_halt = false;

    // Clock 1: Reload to 3, clear reload flag
    ApuLogic.clockLinearCounter(&apu);
    try testing.expectEqual(@as(u7, 3), apu.triangle_linear_counter);
    try testing.expect(!apu.triangle_linear_reload_flag);

    // Clock 2: 3 -> 2
    ApuLogic.clockLinearCounter(&apu);
    try testing.expectEqual(@as(u7, 2), apu.triangle_linear_counter);

    // Clock 3: 2 -> 1
    ApuLogic.clockLinearCounter(&apu);
    try testing.expectEqual(@as(u7, 1), apu.triangle_linear_counter);

    // Clock 4: 1 -> 0
    ApuLogic.clockLinearCounter(&apu);
    try testing.expectEqual(@as(u7, 0), apu.triangle_linear_counter);

    // Clock 5: Should stay at 0
    ApuLogic.clockLinearCounter(&apu);
    try testing.expectEqual(@as(u7, 0), apu.triangle_linear_counter);
}

// ============================================================================
// Halt Flag Behavior Tests
// ============================================================================

test "Linear Counter: Halt flag prevents reload flag clearing" {
    var apu = ApuState.init();

    // Setup with halt flag set
    ApuLogic.writeTriangle(&apu, 0, 0b11100000); // halt set, reload = 96
    ApuLogic.writeTriangle(&apu, 3, 0b00000000); // trigger reload flag
    apu.triangle_enabled = true;

    try testing.expect(apu.triangle_halt);
    try testing.expect(apu.triangle_linear_reload_flag);

    // Multiple clocks
    for (0..3) |_| {
        ApuLogic.clockLinearCounter(&apu);
    }

    // Reload flag should still be set
    try testing.expect(apu.triangle_linear_reload_flag);
    // Counter should keep getting reloaded
    try testing.expectEqual(@as(u7, 96), apu.triangle_linear_counter);
}

test "Linear Counter: Changing halt flag mid-countdown" {
    var apu = ApuState.init();

    // Start with halt clear
    ApuLogic.writeTriangle(&apu, 0, 0b00110010); // halt clear, reload = 50
    ApuLogic.writeTriangle(&apu, 3, 0b00000000); // trigger reload
    apu.triangle_enabled = true;

    // First clock: Reload and clear reload flag
    ApuLogic.clockLinearCounter(&apu);
    try testing.expectEqual(@as(u7, 50), apu.triangle_linear_counter);
    try testing.expect(!apu.triangle_linear_reload_flag);

    // Count down 5 times
    for (0..5) |_| {
        ApuLogic.clockLinearCounter(&apu);
    }
    try testing.expectEqual(@as(u7, 45), apu.triangle_linear_counter);

    // Now set halt flag and trigger reload
    ApuLogic.writeTriangle(&apu, 0, 0b10110010); // halt SET, reload = 50
    ApuLogic.writeTriangle(&apu, 3, 0b00000000); // trigger reload

    // Clock: Should reload, but NOT clear reload flag
    ApuLogic.clockLinearCounter(&apu);
    try testing.expectEqual(@as(u7, 50), apu.triangle_linear_counter);
    try testing.expect(apu.triangle_linear_reload_flag); // Should persist

    // Next clock: Should reload again
    ApuLogic.clockLinearCounter(&apu);
    try testing.expectEqual(@as(u7, 50), apu.triangle_linear_counter);
}

// ============================================================================
// Independence Tests
// ============================================================================

test "Linear Counter: Independent from envelopes" {
    var apu = ApuState.init();

    // Setup linear counter
    ApuLogic.writeTriangle(&apu, 0, 0b00101010); // reload = 42
    ApuLogic.writeTriangle(&apu, 3, 0b00000000); // trigger reload
    apu.triangle_enabled = true;

    // Setup pulse1 envelope
    ApuLogic.writePulse1(&apu, 0, 0b00110101); // envelope params
    ApuLogic.writePulse1(&apu, 3, 0b00000000); // trigger envelope
    apu.pulse1_enabled = true;

    // Clock linear counter
    ApuLogic.clockLinearCounter(&apu);

    // Linear counter should work independently
    try testing.expectEqual(@as(u7, 42), apu.triangle_linear_counter);
    try testing.expect(!apu.triangle_linear_reload_flag);

    // Envelope start flag should still be set (not clocked yet)
    try testing.expect(apu.pulse1_envelope.start_flag);
}

// ============================================================================
// Quarter-Frame Integration Test
// ============================================================================

test "Linear Counter: Quarter-frame integration" {
    var apu = ApuState.init();

    // Setup
    ApuLogic.writeTriangle(&apu, 0, 0b00000101); // reload = 5, halt clear
    ApuLogic.writeTriangle(&apu, 3, 0b00000000); // trigger reload
    apu.triangle_enabled = true;

    // Simulate quarter-frame clocking by calling tickFrameCounter
    // Run to first quarter-frame (7457 cycles)
    var i: u32 = 0;
    while (i < 7457) : (i += 1) {
        _ = ApuLogic.tickFrameCounter(&apu);
    }

    // Counter should be reloaded to 5, reload flag cleared
    try testing.expectEqual(@as(u7, 5), apu.triangle_linear_counter);
    try testing.expect(!apu.triangle_linear_reload_flag);
}
