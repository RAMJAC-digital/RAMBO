const std = @import("std");
const testing = std.testing;
const ApuModule = @import("RAMBO").Apu;
const ApuState = ApuModule.State.ApuState;
const ApuLogic = ApuModule.Logic;

test "APU: initialization" {
    const apu = ApuState.init();
    try testing.expectEqual(false, apu.frame_counter_mode);
    try testing.expectEqual(false, apu.irq_inhibit);
    try testing.expectEqual(false, apu.frame_irq_flag);
}

test "APU: $4015 write enables channels" {
    var apu = ApuState.init();
    ApuLogic.writeControl(&apu, 0b00011111);

    try testing.expect(apu.pulse1_enabled);
    try testing.expect(apu.pulse2_enabled);
    try testing.expect(apu.triangle_enabled);
    try testing.expect(apu.noise_enabled);
    try testing.expect(apu.dmc_enabled);
}

test "APU: $4017 sets frame counter mode" {
    var apu = ApuState.init();

    // 4-step mode
    ApuLogic.writeFrameCounter(&apu, 0x00);
    try testing.expectEqual(false, apu.frame_counter_mode);

    // 5-step mode
    ApuLogic.writeFrameCounter(&apu, 0x80);
    try testing.expectEqual(true, apu.frame_counter_mode);
}

test "APU: Frame IRQ generation in 4-step mode" {
    var apu = ApuState.init();
    ApuLogic.writeFrameCounter(&apu, 0x00); // 4-step, IRQ enabled

    // Tick to step 4 (29829 cycles)
    var i: u32 = 0;
    while (i < 29829) : (i += 1) {
        _ = ApuLogic.tickFrameCounter(&apu);
    }

    try testing.expect(apu.frame_irq_flag);
}

test "APU: IRQ inhibit prevents IRQ" {
    var apu = ApuState.init();
    ApuLogic.writeFrameCounter(&apu, 0x40); // IRQ inhibit

    var i: u32 = 0;
    while (i < 29830) : (i += 1) {
        _ = ApuLogic.tickFrameCounter(&apu);
    }

    try testing.expectEqual(false, apu.frame_irq_flag);
}

test "APU: Reading $4015 clears frame IRQ" {
    var apu = ApuState.init();
    apu.frame_irq_flag = true;

    const status = ApuLogic.readStatus(&apu);
    try testing.expectEqual(@as(u8, 0x40), status); // Bit 6 set

    ApuLogic.clearFrameIrq(&apu);
    try testing.expectEqual(false, apu.frame_irq_flag);
}

test "APU: Frame counter 4-step timing" {
    var apu = ApuState.init();
    ApuLogic.writeFrameCounter(&apu, 0x00);

    // Should reset at cycle 29830
    var i: u32 = 0;
    while (i < 29830) : (i += 1) {
        _ = ApuLogic.tickFrameCounter(&apu);
    }

    try testing.expectEqual(@as(u32, 0), apu.frame_counter_cycles);
}

test "APU: Frame counter 5-step timing" {
    var apu = ApuState.init();
    ApuLogic.writeFrameCounter(&apu, 0x80);

    // Should reset at cycle 37281
    var i: u32 = 0;
    while (i < 37281) : (i += 1) {
        _ = ApuLogic.tickFrameCounter(&apu);
    }

    try testing.expectEqual(@as(u32, 0), apu.frame_counter_cycles);
}
