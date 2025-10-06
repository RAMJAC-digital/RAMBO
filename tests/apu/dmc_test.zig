const std = @import("std");
const testing = std.testing;
const ApuModule = @import("RAMBO").Apu;
const ApuState = ApuModule.State.ApuState;
const ApuLogic = ApuModule.Logic;
const Dmc = ApuModule.Dmc;

// ============================================================================
// DMC Timer Tests
// ============================================================================

test "DMC: Timer counts down every CPU cycle" {
    var apu = ApuState.init();
    apu.dmc_enabled = true;
    apu.dmc_timer = 100;
    apu.dmc_timer_period = 100;

    // Tick once - timer should decrement
    _ = ApuLogic.tickDmc(&apu);
    try testing.expectEqual(@as(u16, 99), apu.dmc_timer);

    // Tick again
    _ = ApuLogic.tickDmc(&apu);
    try testing.expectEqual(@as(u16, 98), apu.dmc_timer);
}

test "DMC: Timer reloads on expiration" {
    var apu = ApuState.init();
    apu.dmc_enabled = true;
    apu.dmc_timer = 0; // Already expired
    apu.dmc_timer_period = 100;
    apu.dmc_bits_remaining = 8;
    apu.dmc_silence_flag = false;
    apu.dmc_shift_register = 0xFF;

    // Tick - timer at 0 should reload to period
    _ = ApuLogic.tickDmc(&apu);
    try testing.expectEqual(@as(u16, 100), apu.dmc_timer);
}

test "DMC: Timer does not tick when DMC disabled" {
    var apu = ApuState.init();
    apu.dmc_enabled = false;
    apu.dmc_timer = 50;
    apu.dmc_timer_period = 100;

    _ = ApuLogic.tickDmc(&apu);
    try testing.expectEqual(@as(u16, 50), apu.dmc_timer); // No change
}

test "DMC: Rate table selection (NTSC)" {
    var apu = ApuState.init();

    // Test lowest rate (index 0)
    ApuLogic.writeDmc(&apu, 0, 0x00);
    try testing.expectEqual(@as(u16, 428), apu.dmc_timer_period);

    // Test highest rate (index 15)
    ApuLogic.writeDmc(&apu, 0, 0x0F);
    try testing.expectEqual(@as(u16, 54), apu.dmc_timer_period);

    // Test middle rate (index 7)
    ApuLogic.writeDmc(&apu, 0, 0x07);
    try testing.expectEqual(@as(u16, 214), apu.dmc_timer_period);
}

// ============================================================================
// DMC Output Unit Tests
// ============================================================================

test "DMC: Output level increment on bit=1" {
    var apu = ApuState.init();
    apu.dmc_enabled = true;
    apu.dmc_timer = 0;
    apu.dmc_timer_period = 100;
    apu.dmc_output = 64;
    apu.dmc_silence_flag = false;
    apu.dmc_shift_register = 0b00000001; // LSB = 1
    apu.dmc_bits_remaining = 8;

    // Tick - should shift out bit 1, increment output by 2
    _ = ApuLogic.tickDmc(&apu);
    try testing.expectEqual(@as(u7, 66), apu.dmc_output);
    try testing.expectEqual(@as(u4, 7), apu.dmc_bits_remaining);
}

test "DMC: Output level decrement on bit=0" {
    var apu = ApuState.init();
    apu.dmc_enabled = true;
    apu.dmc_timer = 0;
    apu.dmc_timer_period = 100;
    apu.dmc_output = 64;
    apu.dmc_silence_flag = false;
    apu.dmc_shift_register = 0b00000000; // LSB = 0
    apu.dmc_bits_remaining = 8;

    // Tick - should shift out bit 0, decrement output by 2
    _ = ApuLogic.tickDmc(&apu);
    try testing.expectEqual(@as(u7, 62), apu.dmc_output);
    try testing.expectEqual(@as(u4, 7), apu.dmc_bits_remaining);
}

test "DMC: Output level clamping (maximum)" {
    var apu = ApuState.init();
    apu.dmc_enabled = true;
    apu.dmc_timer = 0;
    apu.dmc_timer_period = 100;
    apu.dmc_output = 125; // Will increment to 127
    apu.dmc_silence_flag = false;
    apu.dmc_shift_register = 0b00000001; // LSB = 1
    apu.dmc_bits_remaining = 8;

    // Should increment to 127 (max)
    _ = ApuLogic.tickDmc(&apu);
    try testing.expectEqual(@as(u7, 127), apu.dmc_output);

    // Another tick with bit=1 should stay at 127 (clamp)
    apu.dmc_shift_register = 0b00000001;
    apu.dmc_bits_remaining = 8;
    apu.dmc_timer = 0;
    _ = ApuLogic.tickDmc(&apu);
    try testing.expectEqual(@as(u7, 127), apu.dmc_output);
}

test "DMC: Output level clamping (minimum)" {
    var apu = ApuState.init();
    apu.dmc_enabled = true;
    apu.dmc_timer = 0;
    apu.dmc_timer_period = 100;
    apu.dmc_output = 2; // Will decrement to 0
    apu.dmc_silence_flag = false;
    apu.dmc_shift_register = 0b00000000; // LSB = 0
    apu.dmc_bits_remaining = 8;

    // Should decrement to 0 (min)
    _ = ApuLogic.tickDmc(&apu);
    try testing.expectEqual(@as(u7, 0), apu.dmc_output);

    // Another tick with bit=0 should stay at 0 (clamp)
    apu.dmc_shift_register = 0b00000000;
    apu.dmc_bits_remaining = 8;
    apu.dmc_timer = 0;
    _ = ApuLogic.tickDmc(&apu);
    try testing.expectEqual(@as(u7, 0), apu.dmc_output);
}

test "DMC: Shift register advances correctly" {
    var apu = ApuState.init();
    apu.dmc_enabled = true;
    apu.dmc_timer = 0;
    apu.dmc_timer_period = 100;
    apu.dmc_silence_flag = false;
    apu.dmc_shift_register = 0b10101010;
    apu.dmc_bits_remaining = 8;
    apu.dmc_output = 64;

    // Bit 0 = 0 -> decrement
    _ = ApuLogic.tickDmc(&apu);
    try testing.expectEqual(@as(u8, 0b01010101), apu.dmc_shift_register);
    try testing.expectEqual(@as(u7, 62), apu.dmc_output);

    // Bit 0 = 1 -> increment
    apu.dmc_timer = 0;
    _ = ApuLogic.tickDmc(&apu);
    try testing.expectEqual(@as(u8, 0b00101010), apu.dmc_shift_register);
    try testing.expectEqual(@as(u7, 64), apu.dmc_output);
}

test "DMC: Silence flag prevents output modification" {
    var apu = ApuState.init();
    apu.dmc_enabled = true;
    apu.dmc_timer = 0;
    apu.dmc_timer_period = 100;
    apu.dmc_silence_flag = true; // Silence mode
    apu.dmc_shift_register = 0xFF;
    apu.dmc_bits_remaining = 8;
    apu.dmc_output = 64;

    // Tick - output should NOT change (silence mode)
    _ = ApuLogic.tickDmc(&apu);
    try testing.expectEqual(@as(u7, 64), apu.dmc_output);
    try testing.expectEqual(@as(u4, 8), apu.dmc_bits_remaining); // No decrement
}

// ============================================================================
// DMC Sample Buffer Tests
// ============================================================================

test "DMC: Sample buffer refill triggers DMA" {
    var apu = ApuState.init();
    apu.dmc_enabled = true;
    apu.dmc_timer = 0;
    apu.dmc_timer_period = 100;
    apu.dmc_silence_flag = false;
    apu.dmc_shift_register = 0xFF;
    apu.dmc_bits_remaining = 1; // Last bit
    apu.dmc_sample_buffer_empty = true; // Buffer empty
    apu.dmc_bytes_remaining = 10; // More bytes to play

    // Tick - should exhaust bits, set silence flag, NOT trigger DMA (buffer empty)
    const trigger_dma1 = ApuLogic.tickDmc(&apu);
    try testing.expect(!trigger_dma1);
    try testing.expect(apu.dmc_silence_flag);

    // Load sample byte - should exit silence and start playing
    apu.dmc_sample_buffer = 0xAA;
    apu.dmc_sample_buffer_empty = false;
    apu.dmc_silence_flag = true; // Reset to silence
    apu.dmc_bits_remaining = 0;
    ApuLogic.loadSampleByte(&apu, 0xAA);

    try testing.expect(!apu.dmc_silence_flag);
    try testing.expectEqual(@as(u8, 0xAA), apu.dmc_shift_register);
    try testing.expectEqual(@as(u4, 8), apu.dmc_bits_remaining);
}

test "DMC: Sample buffer load with data triggers DMA for next byte" {
    var apu = ApuState.init();
    apu.dmc_enabled = true;
    apu.dmc_timer = 0;
    apu.dmc_timer_period = 100;
    apu.dmc_silence_flag = false;
    apu.dmc_shift_register = 0xFF;
    apu.dmc_bits_remaining = 1;
    apu.dmc_sample_buffer = 0xAA; // Buffer full
    apu.dmc_sample_buffer_empty = false;
    apu.dmc_bytes_remaining = 10;

    // Tick - should load buffer into shift register, trigger DMA for next byte
    const trigger_dma = ApuLogic.tickDmc(&apu);
    try testing.expect(trigger_dma);
    try testing.expectEqual(@as(u8, 0xAA), apu.dmc_shift_register);
    try testing.expectEqual(@as(u4, 8), apu.dmc_bits_remaining);
    try testing.expect(apu.dmc_sample_buffer_empty);
}

// ============================================================================
// DMC Register Write Tests
// ============================================================================

test "DMC: $4010 IRQ enable flag" {
    var apu = ApuState.init();

    // Enable IRQ
    ApuLogic.writeDmc(&apu, 0, 0x80);
    try testing.expect(apu.dmc_irq_enabled);

    // Disable IRQ (should clear IRQ flag)
    apu.dmc_irq_flag = true;
    ApuLogic.writeDmc(&apu, 0, 0x00);
    try testing.expect(!apu.dmc_irq_enabled);
    try testing.expect(!apu.dmc_irq_flag);
}

test "DMC: $4010 loop flag" {
    var apu = ApuState.init();

    // Enable loop
    ApuLogic.writeDmc(&apu, 0, 0x40);
    try testing.expect(apu.dmc_loop_flag);

    // Disable loop
    ApuLogic.writeDmc(&apu, 0, 0x00);
    try testing.expect(!apu.dmc_loop_flag);
}

test "DMC: $4011 direct load" {
    var apu = ApuState.init();

    // Load output level
    ApuLogic.writeDmc(&apu, 1, 0x7F);
    try testing.expectEqual(@as(u7, 0x7F), apu.dmc_output);

    // Bit 7 should be masked
    ApuLogic.writeDmc(&apu, 1, 0xFF);
    try testing.expectEqual(@as(u7, 0x7F), apu.dmc_output);

    ApuLogic.writeDmc(&apu, 1, 0x42);
    try testing.expectEqual(@as(u7, 0x42), apu.dmc_output);
}

test "DMC: $4012 sample address" {
    var apu = ApuState.init();

    ApuLogic.writeDmc(&apu, 2, 0x50);
    try testing.expectEqual(@as(u8, 0x50), apu.dmc_sample_address);

    ApuLogic.writeDmc(&apu, 2, 0xFF);
    try testing.expectEqual(@as(u8, 0xFF), apu.dmc_sample_address);
}

test "DMC: $4013 sample length" {
    var apu = ApuState.init();

    ApuLogic.writeDmc(&apu, 3, 0x80);
    try testing.expectEqual(@as(u8, 0x80), apu.dmc_sample_length);

    ApuLogic.writeDmc(&apu, 3, 0x00);
    try testing.expectEqual(@as(u8, 0x00), apu.dmc_sample_length);
}

// ============================================================================
// DMC Sample Playback Tests
// ============================================================================

test "DMC: Sample start via $4015" {
    var apu = ApuState.init();

    // Setup sample parameters
    ApuLogic.writeDmc(&apu, 2, 0x10); // Address = $C000 + ($10 << 6) = $C400
    ApuLogic.writeDmc(&apu, 3, 0x05); // Length = (5 << 4) + 1 = 81 bytes

    // Enable DMC channel
    ApuLogic.writeControl(&apu, 0x10);

    try testing.expectEqual(@as(u16, 0xC400), apu.dmc_current_address);
    try testing.expectEqual(@as(u16, 81), apu.dmc_bytes_remaining);
}

test "DMC: Sample address wrapping" {
    var apu = ApuState.init();
    apu.dmc_current_address = 0xFFFF;
    apu.dmc_bytes_remaining = 10;
    apu.dmc_sample_buffer_empty = true;

    // Load byte - address should wrap to $8000
    ApuLogic.loadSampleByte(&apu, 0x42);

    try testing.expectEqual(@as(u16, 0x8000), apu.dmc_current_address);
    try testing.expectEqual(@as(u16, 9), apu.dmc_bytes_remaining);
}

test "DMC: Sample completion with IRQ" {
    var apu = ApuState.init();
    apu.dmc_irq_enabled = true;
    apu.dmc_loop_flag = false;
    apu.dmc_bytes_remaining = 1;
    apu.dmc_current_address = 0xC000;

    // Load last byte
    ApuLogic.loadSampleByte(&apu, 0xFF);

    try testing.expectEqual(@as(u16, 0), apu.dmc_bytes_remaining);
    try testing.expect(apu.dmc_irq_flag);
}

test "DMC: Sample looping" {
    var apu = ApuState.init();
    apu.dmc_irq_enabled = false;
    apu.dmc_loop_flag = true;
    apu.dmc_sample_address = 0x20; // $C800
    apu.dmc_sample_length = 0x03; // 49 bytes
    apu.dmc_bytes_remaining = 1;
    apu.dmc_current_address = 0xC810;

    // Load last byte - should restart sample
    ApuLogic.loadSampleByte(&apu, 0xFF);

    try testing.expectEqual(@as(u16, 0xC800), apu.dmc_current_address);
    try testing.expectEqual(@as(u16, 49), apu.dmc_bytes_remaining);
    try testing.expect(!apu.dmc_irq_flag); // No IRQ on loop
}

test "DMC: Stop via $4015 clear" {
    var apu = ApuState.init();
    apu.dmc_bytes_remaining = 100;

    // Disable DMC
    ApuLogic.writeControl(&apu, 0x00);

    try testing.expectEqual(@as(u16, 0), apu.dmc_bytes_remaining);
}

// ============================================================================
// DMC Status Tests
// ============================================================================

test "DMC: $4015 read reflects bytes_remaining" {
    var apu = ApuState.init();

    // No bytes remaining
    apu.dmc_bytes_remaining = 0;
    var status = ApuLogic.readStatus(&apu);
    try testing.expectEqual(@as(u8, 0), status & 0x10);

    // Bytes remaining
    apu.dmc_bytes_remaining = 50;
    status = ApuLogic.readStatus(&apu);
    try testing.expectEqual(@as(u8, 0x10), status & 0x10);
}

test "DMC: $4015 read reflects DMC IRQ" {
    var apu = ApuState.init();

    // No IRQ
    apu.dmc_irq_flag = false;
    var status = ApuLogic.readStatus(&apu);
    try testing.expectEqual(@as(u8, 0), status & 0x80);

    // IRQ set
    apu.dmc_irq_flag = true;
    status = ApuLogic.readStatus(&apu);
    try testing.expectEqual(@as(u8, 0x80), status & 0x80);
}

test "DMC: $4015 write clears DMC IRQ" {
    var apu = ApuState.init();
    apu.dmc_irq_flag = true;

    ApuLogic.writeControl(&apu, 0x10); // Enable DMC

    try testing.expect(!apu.dmc_irq_flag); // Cleared
}
