const std = @import("std");
const testing = std.testing;
const ApuModule = @import("RAMBO").Apu;
const ApuState = ApuModule.State.ApuState;
const ApuLogic = ApuModule.Logic;

// ============================================================================
// Frame IRQ Edge Case Tests
// ============================================================================
//
// Tests the hardware behavior where the IRQ flag is actively RE-SET during
// cycles 29829-29831 in 4-step mode. This means even if the flag is cleared
// by reading $4015, it gets set again on the next cycle.

test "Frame IRQ: Flag set at cycle 29829" {
    var apu = ApuState.init();

    // Setup 4-step mode, IRQ enabled
    apu.frame_counter_mode = false; // 4-step mode
    apu.irq_inhibit = false;
    apu.frame_counter_cycles = 29828;

    // Tick to cycle 29829
    const should_irq = ApuLogic.tickFrameCounter(&apu);

    try testing.expect(apu.frame_irq_flag);
    try testing.expect(should_irq);
    try testing.expectEqual(@as(u32, 29829), apu.frame_counter_cycles);
}

test "Frame IRQ: Flag stays set at cycle 29830" {
    var apu = ApuState.init();

    // Setup 4-step mode, IRQ enabled
    apu.frame_counter_mode = false;
    apu.irq_inhibit = false;
    apu.frame_counter_cycles = 29829;

    // Tick to cycle 29830
    const should_irq = ApuLogic.tickFrameCounter(&apu);

    try testing.expect(apu.frame_irq_flag);
    try testing.expect(should_irq);
    try testing.expectEqual(@as(u32, 29830), apu.frame_counter_cycles);
}

test "Frame IRQ: Flag stays set at cycle 29831" {
    var apu = ApuState.init();

    // Setup 4-step mode, IRQ enabled
    apu.frame_counter_mode = false;
    apu.irq_inhibit = false;
    apu.frame_counter_cycles = 29830;

    // Tick to cycle 29831
    const should_irq = ApuLogic.tickFrameCounter(&apu);

    try testing.expect(apu.frame_irq_flag);
    try testing.expect(should_irq);
    try testing.expectEqual(@as(u32, 29831), apu.frame_counter_cycles);
}

test "Frame IRQ: Flag re-set after reading $4015 at cycle 29829" {
    var apu = ApuState.init();

    // Setup 4-step mode, IRQ enabled
    apu.frame_counter_mode = false;
    apu.irq_inhibit = false;
    apu.frame_counter_cycles = 29828;

    // Tick to cycle 29829 - sets flag
    _ = ApuLogic.tickFrameCounter(&apu);
    try testing.expect(apu.frame_irq_flag);

    // Read $4015 - clears flag (side effect)
    const status = ApuLogic.readStatus(&apu);
    _ = status;
    ApuLogic.clearFrameIrq(&apu); // Side effect of reading $4015
    try testing.expect(!apu.frame_irq_flag); // Flag cleared by read

    // Tick to cycle 29830 - RE-SETS flag (edge case)
    const should_irq = ApuLogic.tickFrameCounter(&apu);
    try testing.expect(apu.frame_irq_flag); // Flag re-set!
    try testing.expect(should_irq);
}

test "Frame IRQ: Flag re-set after reading $4015 at cycle 29830" {
    var apu = ApuState.init();

    // Setup 4-step mode, IRQ enabled, already at cycle 29829
    apu.frame_counter_mode = false;
    apu.irq_inhibit = false;
    apu.frame_counter_cycles = 29829;
    apu.frame_irq_flag = true;

    // Read $4015 at cycle 29829 - clears flag
    _ = ApuLogic.readStatus(&apu);
    ApuLogic.clearFrameIrq(&apu); // Side effect
    try testing.expect(!apu.frame_irq_flag);

    // Tick to cycle 29830 - RE-SETS flag
    _ = ApuLogic.tickFrameCounter(&apu);
    try testing.expect(apu.frame_irq_flag);

    // Read $4015 at cycle 29830 - clears flag again
    _ = ApuLogic.readStatus(&apu);
    ApuLogic.clearFrameIrq(&apu); // Side effect
    try testing.expect(!apu.frame_irq_flag);

    // Tick to cycle 29831 - RE-SETS flag again
    const should_irq = ApuLogic.tickFrameCounter(&apu);
    try testing.expect(apu.frame_irq_flag);
    try testing.expect(should_irq);
}

test "Frame IRQ: Flag cleared successfully after cycle 29832" {
    var apu = ApuState.init();

    // Setup 4-step mode, IRQ enabled
    apu.frame_counter_mode = false;
    apu.irq_inhibit = false;
    apu.frame_counter_cycles = 29831;
    apu.frame_irq_flag = true;

    // Tick to cycle 29832 - resets frame, no longer sets IRQ
    const should_irq = ApuLogic.tickFrameCounter(&apu);
    try testing.expect(!should_irq); // Frame reset, cycles now at 0

    // Read $4015 - clears flag
    _ = ApuLogic.readStatus(&apu);
    ApuLogic.clearFrameIrq(&apu); // Side effect
    try testing.expect(!apu.frame_irq_flag);

    // Tick - flag stays cleared
    _ = ApuLogic.tickFrameCounter(&apu);
    try testing.expect(!apu.frame_irq_flag);
}

test "Frame IRQ: IRQ inhibit prevents flag setting" {
    var apu = ApuState.init();

    // Setup 4-step mode, IRQ INHIBITED
    apu.frame_counter_mode = false;
    apu.irq_inhibit = true; // IRQ disabled
    apu.frame_counter_cycles = 29828;

    // Tick through cycles 29829-29831
    for (0..3) |_| {
        const should_irq = ApuLogic.tickFrameCounter(&apu);
        try testing.expect(!apu.frame_irq_flag);
        try testing.expect(!should_irq);
    }
}

test "Frame IRQ: Cycle 29828 doesn't set flag" {
    var apu = ApuState.init();

    // Setup 4-step mode, IRQ enabled
    apu.frame_counter_mode = false;
    apu.irq_inhibit = false;
    apu.frame_counter_cycles = 29827;

    // Tick to cycle 29828
    const should_irq = ApuLogic.tickFrameCounter(&apu);

    try testing.expect(!apu.frame_irq_flag);
    try testing.expect(!should_irq);
    try testing.expectEqual(@as(u32, 29828), apu.frame_counter_cycles);
}

test "Frame IRQ: 5-step mode never sets IRQ flag" {
    var apu = ApuState.init();

    // Setup 5-step mode (no IRQ)
    apu.frame_counter_mode = true; // 5-step mode
    apu.irq_inhibit = false;
    apu.frame_counter_cycles = 29828;

    // Tick through cycles 29829-29831
    for (0..3) |_| {
        const should_irq = ApuLogic.tickFrameCounter(&apu);
        try testing.expect(!apu.frame_irq_flag);
        try testing.expect(!should_irq);
    }
}

test "Frame IRQ: Edge case across frame reset boundary" {
    var apu = ApuState.init();

    // Setup 4-step mode, IRQ enabled
    apu.frame_counter_mode = false;
    apu.irq_inhibit = false;
    apu.frame_counter_cycles = 29829;

    // Tick to cycle 29830 - sets flag
    _ = ApuLogic.tickFrameCounter(&apu);
    try testing.expect(apu.frame_irq_flag);
    try testing.expectEqual(@as(u32, 29830), apu.frame_counter_cycles);

    // Tick to cycle 29831 - still setting flag
    _ = ApuLogic.tickFrameCounter(&apu);
    try testing.expect(apu.frame_irq_flag);
    try testing.expectEqual(@as(u32, 29831), apu.frame_counter_cycles);

    // Tick to cycle 29832 - frame resets after IRQ edge case period
    _ = ApuLogic.tickFrameCounter(&apu);

    // Frame should reset to cycle 0
    try testing.expectEqual(@as(u32, 0), apu.frame_counter_cycles);

    // Flag should still be set (was set during 29829-29831)
    try testing.expect(apu.frame_irq_flag);
}
