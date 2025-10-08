const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

// Import dispatch directly
const CpuModule = @import("cpu/Cpu.zig");
const dispatch = @import("cpu/dispatch.zig");

test "Dispatch table entry for 0x80" {
    const entry = dispatch.DISPATCH_TABLE[0x80];

    try testing.expectEqual(@as(usize, 1), entry.addressing_steps.len);
}

test "Dispatch table entry for 0xA9 (LDA immediate)" {
    const entry = dispatch.DISPATCH_TABLE[0xA9];

    try testing.expectEqual(@as(usize, 1), entry.addressing_steps.len);
}

test "Dispatch table entry for 0xEA (NOP implied)" {
    const entry = dispatch.DISPATCH_TABLE[0xEA];

    try testing.expectEqual(@as(usize, 0), entry.addressing_steps.len);
}
