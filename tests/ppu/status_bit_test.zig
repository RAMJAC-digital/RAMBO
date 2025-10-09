//! Test that PpuStatus bit layout is correct

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const PpuState = RAMBO.PpuState;

test "PpuStatus: VBlank is bit 7" {
    var status = PpuState.PpuStatus{};

    // Set only VBlank
    status.vblank = true;

    // Convert to byte
    const byte = status.toByte(0);

    // Should be 0x80 (bit 7 set)
    try testing.expectEqual(@as(u8, 0x80), byte);
}

test "PpuStatus: All flags set correctly" {
    var status = PpuState.PpuStatus{
        .vblank = true,
        .sprite_0_hit = true,
        .sprite_overflow = true,
        .open_bus = 0,
    };

    const byte = status.toByte(0);

    // Should be 0xE0 (bits 7, 6, 5 set)
    try testing.expectEqual(@as(u8, 0xE0), byte);
}