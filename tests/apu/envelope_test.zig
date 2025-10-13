const std = @import("std");
const testing = std.testing;
const ApuModule = @import("RAMBO").Apu;
const ApuState = ApuModule.State.ApuState;
const ApuLogic = ApuModule.Logic;
const Envelope = ApuModule.Envelope;
const envelope_logic = @import("RAMBO").Apu.envelope_logic;

// ============================================================================
// Envelope Start Flag Tests
// ============================================================================

test "Envelope: Start flag triggers reload" {
    var env = Envelope.Envelope{};
    env.volume_envelope = 5;
    env.start_flag = true;

    // Clock - should clear start flag and reload
    env = envelope_logic.clock(&env);

    try testing.expect(!env.start_flag);
    try testing.expectEqual(@as(u4, 15), env.decay_level);
    try testing.expectEqual(@as(u4, 5), env.divider);
}

test "Envelope: Restart sets start flag" {
    var env = Envelope.Envelope{};

    env = envelope_logic.restart(&env);

    try testing.expect(env.start_flag);
}

// ============================================================================
// Envelope Divider Tests
// ============================================================================

test "Envelope: Divider counts down" {
    var env = Envelope.Envelope{};
    env.volume_envelope = 3;
    env.divider = 3;
    env.decay_level = 10;

    // Clock - divider should decrement
    env = envelope_logic.clock(&env);
    try testing.expectEqual(@as(u4, 2), env.divider);
    try testing.expectEqual(@as(u4, 10), env.decay_level); // No change yet

    env = envelope_logic.clock(&env);
    try testing.expectEqual(@as(u4, 1), env.divider);
    try testing.expectEqual(@as(u4, 10), env.decay_level);

    env = envelope_logic.clock(&env);
    try testing.expectEqual(@as(u4, 0), env.divider);
    try testing.expectEqual(@as(u4, 10), env.decay_level);
}

test "Envelope: Divider reload and decay level decrement" {
    var env = Envelope.Envelope{};
    env.volume_envelope = 2;
    env.divider = 0; // Already expired
    env.decay_level = 10;

    // Clock - should reload divider and decrement decay_level
    env = envelope_logic.clock(&env);

    try testing.expectEqual(@as(u4, 2), env.divider); // Reloaded
    try testing.expectEqual(@as(u4, 9), env.decay_level); // Decremented
}

// ============================================================================
// Envelope Decay Level Tests
// ============================================================================

test "Envelope: Decay level counts down to zero" {
    var env = Envelope.Envelope{};
    env.volume_envelope = 0; // Divider always reloads to 0 (clocks every time)
    env.decay_level = 3;

    env = envelope_logic.clock(&env);
    try testing.expectEqual(@as(u4, 2), env.decay_level);

    env = envelope_logic.clock(&env);
    try testing.expectEqual(@as(u4, 1), env.decay_level);

    env = envelope_logic.clock(&env);
    try testing.expectEqual(@as(u4, 0), env.decay_level);

    // Should stay at 0 (no loop)
    env = envelope_logic.clock(&env);
    try testing.expectEqual(@as(u4, 0), env.decay_level);
}

test "Envelope: Loop flag causes decay level reload" {
    var env = Envelope.Envelope{};
    env.volume_envelope = 0;
    env.decay_level = 1;
    env.loop_flag = true;

    // Decay to 0
    env = envelope_logic.clock(&env);
    try testing.expectEqual(@as(u4, 0), env.decay_level);

    // Next clock should reload to 15 (loop mode)
    env = envelope_logic.clock(&env);
    try testing.expectEqual(@as(u4, 15), env.decay_level);
}

test "Envelope: No loop stays at zero" {
    var env = Envelope.Envelope{};
    env.volume_envelope = 0;
    env.decay_level = 0;
    env.loop_flag = false;

    // Should stay at 0
    env = envelope_logic.clock(&env);
    try testing.expectEqual(@as(u4, 0), env.decay_level);

    env = envelope_logic.clock(&env);
    try testing.expectEqual(@as(u4, 0), env.decay_level);
}

// ============================================================================
// Envelope Volume Output Tests
// ============================================================================

test "Envelope: Constant volume mode" {
    var env = Envelope.Envelope{};
    env.constant_volume = true;
    env.volume_envelope = 12;
    env.decay_level = 5; // Should be ignored

    const volume = Envelope.getVolume(&env);
    try testing.expectEqual(@as(u4, 12), volume);
}

test "Envelope: Decay mode outputs decay level" {
    var env = Envelope.Envelope{};
    env.constant_volume = false;
    env.volume_envelope = 12; // Should be ignored
    env.decay_level = 7;

    const volume = Envelope.getVolume(&env);
    try testing.expectEqual(@as(u4, 7), volume);
}

test "Envelope: Volume changes as decay level decreases" {
    var env = Envelope.Envelope{};
    env.constant_volume = false;
    env.volume_envelope = 0;
    env.decay_level = 3;

    try testing.expectEqual(@as(u4, 3), Envelope.getVolume(&env));

    env = envelope_logic.clock(&env);
    try testing.expectEqual(@as(u4, 2), Envelope.getVolume(&env));

    env = envelope_logic.clock(&env);
    try testing.expectEqual(@as(u4, 1), Envelope.getVolume(&env));

    env = envelope_logic.clock(&env);
    try testing.expectEqual(@as(u4, 0), Envelope.getVolume(&env));
}

// ============================================================================
// Envelope Control Register Tests
// ============================================================================

test "Envelope: writeControl sets all fields" {
    var env = Envelope.Envelope{};

    // Write: --LC VVVV = 0b00111010 (loop, constant, volume=10)
    env = envelope_logic.writeControl(&env, 0b00111010);

    try testing.expect(env.loop_flag);
    try testing.expect(env.constant_volume);
    try testing.expectEqual(@as(u4, 10), env.volume_envelope);
}

test "Envelope: writeControl clears loop and constant flags" {
    var env = Envelope.Envelope{};
    env.loop_flag = true;
    env.constant_volume = true;

    // Write: 0b00000101 (no loop, no constant, volume=5)
    env = envelope_logic.writeControl(&env, 0b00000101);

    try testing.expect(!env.loop_flag);
    try testing.expect(!env.constant_volume);
    try testing.expectEqual(@as(u4, 5), env.volume_envelope);
}

// ============================================================================
// Integration Tests with ApuState
// ============================================================================

test "Envelope: Pulse 1 register write integration" {
    var apu = ApuState.init();

    // Write to $4000: --LC VVVV = 0b00110111 (loop, constant, volume=7)
    ApuLogic.writePulse1(&apu, 0, 0b00110111);

    try testing.expect(apu.pulse1_envelope.loop_flag);
    try testing.expect(apu.pulse1_envelope.constant_volume);
    try testing.expectEqual(@as(u4, 7), apu.pulse1_envelope.volume_envelope);
}

test "Envelope: Pulse 1 length counter write restarts envelope" {
    var apu = ApuState.init();
    apu.pulse1_enabled = true;

    // Write to $4003 (length counter load)
    ApuLogic.writePulse1(&apu, 3, 0b11111000);

    try testing.expect(apu.pulse1_envelope.start_flag);
}

test "Envelope: Pulse 2 integration" {
    var apu = ApuState.init();

    ApuLogic.writePulse2(&apu, 0, 0b00011010);

    try testing.expect(!apu.pulse2_envelope.loop_flag);
    try testing.expect(apu.pulse2_envelope.constant_volume);
    try testing.expectEqual(@as(u4, 10), apu.pulse2_envelope.volume_envelope);
}

test "Envelope: Noise integration" {
    var apu = ApuState.init();

    ApuLogic.writeNoise(&apu, 0, 0b00100011);

    try testing.expect(apu.noise_envelope.loop_flag);
    try testing.expect(!apu.noise_envelope.constant_volume);
    try testing.expectEqual(@as(u4, 3), apu.noise_envelope.volume_envelope);
}

// ============================================================================
// Quarter-Frame Clocking Integration Tests
// ============================================================================

test "Envelope: Quarter-frame clocks all three envelopes" {
    var apu = ApuState.init();

    // Setup all three envelopes with start flag
    apu.pulse1_envelope.start_flag = true;
    apu.pulse1_envelope.volume_envelope = 3;

    apu.pulse2_envelope.start_flag = true;
    apu.pulse2_envelope.volume_envelope = 5;

    apu.noise_envelope.start_flag = true;
    apu.noise_envelope.volume_envelope = 7;

    // Tick frame counter to first quarter-frame (7457 cycles)
    var i: u32 = 0;
    while (i < 7457) : (i += 1) {
        _ = ApuLogic.tickFrameCounter(&apu);
    }

    // All start flags should be cleared, decay levels reset
    try testing.expect(!apu.pulse1_envelope.start_flag);
    try testing.expectEqual(@as(u4, 15), apu.pulse1_envelope.decay_level);

    try testing.expect(!apu.pulse2_envelope.start_flag);
    try testing.expectEqual(@as(u4, 15), apu.pulse2_envelope.decay_level);

    try testing.expect(!apu.noise_envelope.start_flag);
    try testing.expectEqual(@as(u4, 15), apu.noise_envelope.decay_level);
}

test "Envelope: Independent envelope instances" {
    var apu = ApuState.init();

    // Setup pulse1 with fast decay, pulse2 with slow decay
    apu.pulse1_envelope.volume_envelope = 0; // Clocks every time
    apu.pulse1_envelope.decay_level = 5;

    apu.pulse2_envelope.volume_envelope = 5; // Clocks every 6th time
    apu.pulse2_envelope.decay_level = 10;
    apu.pulse2_envelope.divider = 5;

    // Clock quarter-frame multiple times
    for (0..10) |_| {
        var i: u32 = 0;
        while (i < 7457) : (i += 1) {
            _ = ApuLogic.tickFrameCounter(&apu);
        }
    }

    // Pulse1 should have decayed significantly
    try testing.expect(apu.pulse1_envelope.decay_level < 5);

    // Pulse2 should have decayed less (slower rate)
    try testing.expect(apu.pulse2_envelope.decay_level > apu.pulse1_envelope.decay_level);
}

// ============================================================================
// Complete Decay Cycle Test
// ============================================================================

test "Envelope: Complete decay cycle with loop" {
    var env = Envelope.Envelope{};
    env.volume_envelope = 1;
    env.loop_flag = true;
    env.constant_volume = false;

    // Start envelope
    env = envelope_logic.restart(&env);
    env = envelope_logic.clock(&env); // Start flag cleared, decay=15, divider=1

    try testing.expectEqual(@as(u4, 15), env.decay_level);

    // Clock through full decay cycle
    // Each decay takes 2 clocks (divider=1)
    for (0..15) |_| {
        env = envelope_logic.clock(&env); // Divider: 1 -> 0
        env = envelope_logic.clock(&env); // Divider: reload, decay--
    }

    // At this point decay_level = 0
    try testing.expectEqual(@as(u4, 0), env.decay_level);

    // One more clock cycle should trigger loop reload
    env = envelope_logic.clock(&env); // Divider: 1 -> 0
    env = envelope_logic.clock(&env); // Divider: reload, decay_level: 0 -> 15 (loop)

    // Should have looped back to 15
    try testing.expectEqual(@as(u4, 15), env.decay_level);
}

test "Envelope: Complete decay cycle without loop" {
    var env = Envelope.Envelope{};
    env.volume_envelope = 0; // Fast decay (divider always 0)
    env.loop_flag = false;
    env.constant_volume = false;

    env = envelope_logic.restart(&env);
    env = envelope_logic.clock(&env); // Start: decay=15

    // Decay to 0
    for (0..15) |_| {
        env = envelope_logic.clock(&env);
    }

    try testing.expectEqual(@as(u4, 0), env.decay_level);

    // Should stay at 0
    env = envelope_logic.clock(&env);
    try testing.expectEqual(@as(u4, 0), env.decay_level);
}
