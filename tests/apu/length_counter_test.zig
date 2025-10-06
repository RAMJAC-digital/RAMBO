//! APU Length Counter Unit Tests
//!
//! Validates Phase 1.5 length counter implementation:
//! - LENGTH_TABLE values
//! - Load/decrement/halt behavior
//! - $4015 status register
//! - Immediate clocking on $4017 write

const std = @import("std");
const testing = std.testing;
const Apu = @import("RAMBO").Apu;
const ApuState = Apu.ApuState;
const ApuLogic = Apu.Logic;

// ============================================================================
// LENGTH_TABLE Validation
// ============================================================================

test "LENGTH_TABLE: All 32 entries match NESDev specification" {
    // Expected values from NESDev wiki
    const EXPECTED_LENGTH_TABLE: [32]u8 = .{
        10, 254, 20, 2, 40, 4, 80, 6, // 0x00-0x07
        160, 8, 60, 10, 14, 12, 26, 14, // 0x08-0x0F
        12, 16, 24, 18, 48, 20, 96, 22, // 0x10-0x17
        192, 24, 72, 26, 16, 28, 32, 30, // 0x18-0x1F
    };

    var state = ApuLogic.init();

    // Test all 32 table entries
    for (EXPECTED_LENGTH_TABLE, 0..) |expected, index| {
        const table_index: u8 = @intCast(index);

        // Enable pulse 1 channel
        ApuLogic.writeControl(&state, 0x01);

        // Write table index to $4003 (bits 3-7)
        const reg_value = (table_index << 3) | 0x00; // Table index in upper 5 bits
        ApuLogic.writePulse1(&state, 3, reg_value);

        try testing.expectEqual(expected, state.pulse1_length);
    }
}

// ============================================================================
// Length Counter Load Behavior
// ============================================================================

test "Length counter: Load from $4003 write when channel enabled" {
    var state = ApuLogic.init();

    // Enable pulse 1
    ApuLogic.writeControl(&state, 0x01);

    // Write $4003 with table index 1 (254) in bits 3-7
    ApuLogic.writePulse1(&state, 3, 0x08); // Index 1 = 0b00001 -> value 254

    try testing.expectEqual(@as(u8, 254), state.pulse1_length);
}

test "Length counter: NOT loaded when channel disabled" {
    var state = ApuLogic.init();

    // Channel disabled (default)
    try testing.expectEqual(false, state.pulse1_enabled);

    // Write $4003 with table index 1 (254)
    ApuLogic.writePulse1(&state, 3, 0x08);

    // Length counter should remain 0
    try testing.expectEqual(@as(u8, 0), state.pulse1_length);
}

test "Length counter: All 4 channels load independently" {
    var state = ApuLogic.init();

    // Enable all channels
    ApuLogic.writeControl(&state, 0x0F);

    // Load different values into each channel
    ApuLogic.writePulse1(&state, 3, 0x00); // Index 0 -> 10
    ApuLogic.writePulse2(&state, 3, 0x08); // Index 1 -> 254
    ApuLogic.writeTriangle(&state, 3, 0x10); // Index 2 -> 20
    ApuLogic.writeNoise(&state, 3, 0x18); // Index 3 -> 2

    try testing.expectEqual(@as(u8, 10), state.pulse1_length);
    try testing.expectEqual(@as(u8, 254), state.pulse2_length);
    try testing.expectEqual(@as(u8, 20), state.triangle_length);
    try testing.expectEqual(@as(u8, 2), state.noise_length);
}

// ============================================================================
// Halt Flag Behavior
// ============================================================================

test "Halt flag: Extracted from $4000 bit 5 (pulse)" {
    var state = ApuLogic.init();

    // Write $4000 with halt bit clear
    ApuLogic.writePulse1(&state, 0, 0x00);
    try testing.expectEqual(false, state.pulse1_halt);

    // Write $4000 with halt bit set
    ApuLogic.writePulse1(&state, 0, 0x20); // Bit 5 set
    try testing.expectEqual(true, state.pulse1_halt);

    // Same for pulse 2
    ApuLogic.writePulse2(&state, 0, 0x20);
    try testing.expectEqual(true, state.pulse2_halt);
}

test "Halt flag: Extracted from $4008 bit 7 (triangle)" {
    var state = ApuLogic.init();

    // Triangle uses bit 7 for halt
    ApuLogic.writeTriangle(&state, 0, 0x00);
    try testing.expectEqual(false, state.triangle_halt);

    ApuLogic.writeTriangle(&state, 0, 0x80); // Bit 7 set
    try testing.expectEqual(true, state.triangle_halt);
}

test "Halt flag: Extracted from $400C bit 5 (noise)" {
    var state = ApuLogic.init();

    ApuLogic.writeNoise(&state, 0, 0x00);
    try testing.expectEqual(false, state.noise_halt);

    ApuLogic.writeNoise(&state, 0, 0x20); // Bit 5 set
    try testing.expectEqual(true, state.noise_halt);
}

// ============================================================================
// Length Counter Decrement Behavior
// ============================================================================

test "Length counter: Decrements on half-frame clock" {
    var state = ApuLogic.init();

    // Enable pulse 1, load length counter
    ApuLogic.writeControl(&state, 0x01);
    ApuLogic.writePulse1(&state, 3, 0x00); // Load 10

    try testing.expectEqual(@as(u8, 10), state.pulse1_length);

    // Simulate frame counter reaching half-frame (14913 cycles in 4-step mode)
    state.frame_counter_cycles = 14913 - 1; // One cycle before

    // Tick to half-frame
    _ = ApuLogic.tickFrameCounter(&state);

    // Length counter should decrement to 9
    try testing.expectEqual(@as(u8, 9), state.pulse1_length);
}

test "Length counter: Halt flag prevents decrement" {
    var state = ApuLogic.init();

    // Enable pulse 1, set halt flag
    ApuLogic.writeControl(&state, 0x01);
    ApuLogic.writePulse1(&state, 0, 0x20); // Set halt flag
    ApuLogic.writePulse1(&state, 3, 0x00); // Load 10

    try testing.expectEqual(@as(u8, 10), state.pulse1_length);
    try testing.expectEqual(true, state.pulse1_halt);

    // Simulate half-frame clock
    state.frame_counter_cycles = 14913 - 1;
    _ = ApuLogic.tickFrameCounter(&state);

    // Length counter should NOT decrement
    try testing.expectEqual(@as(u8, 10), state.pulse1_length);
}

test "Length counter: Does not underflow below zero" {
    var state = ApuLogic.init();

    // Enable pulse 1, set length to 1
    ApuLogic.writeControl(&state, 0x01);
    state.pulse1_length = 1;

    // Clock twice
    state.frame_counter_cycles = 14913 - 1;
    _ = ApuLogic.tickFrameCounter(&state);
    try testing.expectEqual(@as(u8, 0), state.pulse1_length);

    // Reset frame counter
    state.frame_counter_cycles = 14913 - 1;
    _ = ApuLogic.tickFrameCounter(&state);

    // Should stay at 0
    try testing.expectEqual(@as(u8, 0), state.pulse1_length);
}

test "Length counter: Decrements at both half-frame points in 4-step mode" {
    var state = ApuLogic.init();

    // Enable pulse 1, load counter
    ApuLogic.writeControl(&state, 0x01);
    ApuLogic.writePulse1(&state, 3, 0x00); // Load 10

    try testing.expectEqual(@as(u8, 10), state.pulse1_length);

    // First half-frame at cycle 14913
    state.frame_counter_cycles = 14913 - 1;
    _ = ApuLogic.tickFrameCounter(&state);
    try testing.expectEqual(@as(u8, 9), state.pulse1_length);

    // Second half-frame at cycle 29829
    state.frame_counter_cycles = 29829 - 1;
    _ = ApuLogic.tickFrameCounter(&state);
    try testing.expectEqual(@as(u8, 8), state.pulse1_length);
}

test "Length counter: Decrements at both half-frame points in 5-step mode" {
    var state = ApuLogic.init();

    // Enable pulse 1 and load counter FIRST
    ApuLogic.writeControl(&state, 0x01);
    ApuLogic.writePulse1(&state, 3, 0x00); // Load 10

    try testing.expectEqual(@as(u8, 10), state.pulse1_length);

    // Enable 5-step mode - immediately clocks, decrementing 10 -> 9
    ApuLogic.writeFrameCounter(&state, 0x80); // Bit 7 = 5-step

    try testing.expectEqual(@as(u8, 9), state.pulse1_length);

    // First half-frame at cycle 14913 (9 -> 8)
    state.frame_counter_cycles = 14913 - 1;
    _ = ApuLogic.tickFrameCounter(&state);
    try testing.expectEqual(@as(u8, 8), state.pulse1_length);

    // Second half-frame at cycle 37281 (8 -> 7) (NOT 29829 in 5-step mode)
    state.frame_counter_cycles = 37281 - 1;
    _ = ApuLogic.tickFrameCounter(&state);
    try testing.expectEqual(@as(u8, 7), state.pulse1_length);
}

// ============================================================================
// $4015 Write Behavior (Channel Enable/Disable)
// ============================================================================

test "$4015 write: Disabling channel clears length counter immediately" {
    var state = ApuLogic.init();

    // Enable pulse 1, load length counter
    ApuLogic.writeControl(&state, 0x01);
    ApuLogic.writePulse1(&state, 3, 0x00); // Load 10
    try testing.expectEqual(@as(u8, 10), state.pulse1_length);

    // Disable pulse 1
    ApuLogic.writeControl(&state, 0x00); // All channels off

    // Length counter should be cleared immediately
    try testing.expectEqual(@as(u8, 0), state.pulse1_length);
}

test "$4015 write: Clearing length counter does not affect other channels" {
    var state = ApuLogic.init();

    // Enable all channels, load all counters
    ApuLogic.writeControl(&state, 0x0F);
    ApuLogic.writePulse1(&state, 3, 0x00); // Load 10
    ApuLogic.writePulse2(&state, 3, 0x00); // Load 10
    ApuLogic.writeTriangle(&state, 3, 0x00); // Load 10
    ApuLogic.writeNoise(&state, 3, 0x00); // Load 10

    // Disable only pulse 1
    ApuLogic.writeControl(&state, 0x0E); // Bits 1-3 on, bit 0 off

    try testing.expectEqual(@as(u8, 0), state.pulse1_length);
    try testing.expectEqual(@as(u8, 10), state.pulse2_length);
    try testing.expectEqual(@as(u8, 10), state.triangle_length);
    try testing.expectEqual(@as(u8, 10), state.noise_length);
}

// ============================================================================
// $4015 Read Behavior (Status Register)
// ============================================================================

test "$4015 read: Returns length counter status in bits 0-3" {
    var state = ApuLogic.init();

    // All channels disabled, all lengths 0
    var status = ApuLogic.readStatus(&state);
    try testing.expectEqual(@as(u8, 0x00), status & 0x0F); // Bits 0-3 clear

    // Enable all channels, load counters
    ApuLogic.writeControl(&state, 0x0F);
    ApuLogic.writePulse1(&state, 3, 0x00); // Load 10
    ApuLogic.writePulse2(&state, 3, 0x00); // Load 10
    ApuLogic.writeTriangle(&state, 3, 0x00); // Load 10
    ApuLogic.writeNoise(&state, 3, 0x00); // Load 10

    status = ApuLogic.readStatus(&state);
    try testing.expectEqual(@as(u8, 0x0F), status & 0x0F); // All bits 0-3 set
}

test "$4015 read: Bit 0 reflects pulse 1 length > 0" {
    var state = ApuLogic.init();

    ApuLogic.writeControl(&state, 0x01);
    ApuLogic.writePulse1(&state, 3, 0x00); // Load 10

    var status = ApuLogic.readStatus(&state);
    try testing.expectEqual(@as(u8, 0x01), status & 0x01);

    // Decrement to 0
    state.pulse1_length = 0;
    status = ApuLogic.readStatus(&state);
    try testing.expectEqual(@as(u8, 0x00), status & 0x01);
}

test "$4015 read: Each channel bit independent" {
    var state = ApuLogic.init();

    ApuLogic.writeControl(&state, 0x0F);

    // Set specific length values
    state.pulse1_length = 0; // Bit 0 = 0
    state.pulse2_length = 5; // Bit 1 = 1
    state.triangle_length = 0; // Bit 2 = 0
    state.noise_length = 3; // Bit 3 = 1

    const status = ApuLogic.readStatus(&state);
    try testing.expectEqual(@as(u8, 0x0A), status & 0x0F); // Bits 1 and 3 set (0b1010)
}

// ============================================================================
// $4017 Write Immediate Clocking (5-Step Mode)
// ============================================================================

test "$4017 write: 5-step mode immediately clocks quarter + half frame" {
    var state = ApuLogic.init();

    // Enable pulse 1, load counter
    ApuLogic.writeControl(&state, 0x01);
    ApuLogic.writePulse1(&state, 3, 0x00); // Load 10

    try testing.expectEqual(@as(u8, 10), state.pulse1_length);

    // Write $4017 with 5-step mode (bit 7 = 1)
    ApuLogic.writeFrameCounter(&state, 0x80);

    // Should immediately clock half-frame, decrementing length counter
    try testing.expectEqual(@as(u8, 9), state.pulse1_length);
}

test "$4017 write: 4-step mode does NOT immediately clock" {
    var state = ApuLogic.init();

    // Enable pulse 1, load counter
    ApuLogic.writeControl(&state, 0x01);
    ApuLogic.writePulse1(&state, 3, 0x00); // Load 10

    try testing.expectEqual(@as(u8, 10), state.pulse1_length);

    // Write $4017 with 4-step mode (bit 7 = 0)
    ApuLogic.writeFrameCounter(&state, 0x00);

    // Should NOT clock immediately
    try testing.expectEqual(@as(u8, 10), state.pulse1_length);
}

test "$4017 write: Resets frame counter to 0" {
    var state = ApuLogic.init();

    // Advance frame counter
    state.frame_counter_cycles = 12345;

    // Write $4017
    ApuLogic.writeFrameCounter(&state, 0x00);

    try testing.expectEqual(@as(u32, 0), state.frame_counter_cycles);
}

// ============================================================================
// Integration Tests
// ============================================================================

test "Integration: Full length counter lifecycle (load, decrement, silence)" {
    var state = ApuLogic.init();

    // Enable pulse 1
    ApuLogic.writeControl(&state, 0x01);

    // Load length counter with small value (index 3 = value 2)
    ApuLogic.writePulse1(&state, 3, 0x18); // Index 3

    try testing.expectEqual(@as(u8, 2), state.pulse1_length);

    // First half-frame: 2 -> 1
    state.frame_counter_cycles = 14913 - 1;
    _ = ApuLogic.tickFrameCounter(&state);
    try testing.expectEqual(@as(u8, 1), state.pulse1_length);

    // Status should still show active
    var status = ApuLogic.readStatus(&state);
    try testing.expectEqual(@as(u8, 0x01), status & 0x01);

    // Second half-frame: 1 -> 0
    state.frame_counter_cycles = 29829 - 1;
    _ = ApuLogic.tickFrameCounter(&state);
    try testing.expectEqual(@as(u8, 0), state.pulse1_length);

    // Status should now show inactive
    status = ApuLogic.readStatus(&state);
    try testing.expectEqual(@as(u8, 0x00), status & 0x01);
}

test "Integration: Halt flag prevents silencing" {
    var state = ApuLogic.init();

    // Enable pulse 1, set halt
    ApuLogic.writeControl(&state, 0x01);
    ApuLogic.writePulse1(&state, 0, 0x20); // Halt flag
    ApuLogic.writePulse1(&state, 3, 0x18); // Load 2

    // Clock many times
    for (0..100) |_| {
        state.frame_counter_cycles = 14913 - 1;
        _ = ApuLogic.tickFrameCounter(&state);
        state.frame_counter_cycles = 0; // Reset for next iteration
    }

    // Should never decrement
    try testing.expectEqual(@as(u8, 2), state.pulse1_length);
}

test "Integration: Reloading length counter mid-playback" {
    var state = ApuLogic.init();

    // Enable pulse 1, load initial value
    ApuLogic.writeControl(&state, 0x01);
    ApuLogic.writePulse1(&state, 3, 0x18); // Load 2

    // Decrement once
    state.frame_counter_cycles = 14913 - 1;
    _ = ApuLogic.tickFrameCounter(&state);
    try testing.expectEqual(@as(u8, 1), state.pulse1_length);

    // Reload with new value
    ApuLogic.writePulse1(&state, 3, 0x00); // Load 10

    // Should be 10, not 11
    try testing.expectEqual(@as(u8, 10), state.pulse1_length);
}
