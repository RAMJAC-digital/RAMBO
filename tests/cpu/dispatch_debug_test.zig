const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

// Import dispatch directly
const CpuModule = @import("cpu/Cpu.zig");
const dispatch = @import("cpu/dispatch.zig");

test "Dispatch table entry for 0x80" {
    const entry = dispatch.DISPATCH_TABLE[0x80];

    std.debug.print("\n=== Dispatch Entry 0x80 ===\n", .{});
    std.debug.print("Mnemonic: {s}\n", .{entry.info.mnemonic});
    std.debug.print("Mode: {s}\n", .{@tagName(entry.info.mode)});
    std.debug.print("Cycles: {}\n", .{entry.info.cycles});
    std.debug.print("Addressing steps length: {}\n", .{entry.addressing_steps.len});
    std.debug.print("Execute fn: {*}\n", .{entry.execute});

    try testing.expectEqual(@as(usize, 1), entry.addressing_steps.len);
}

test "Dispatch table entry for 0xA9 (LDA immediate)" {
    const entry = dispatch.DISPATCH_TABLE[0xA9];

    std.debug.print("\n=== Dispatch Entry 0xA9 ===\n", .{});
    std.debug.print("Mnemonic: {s}\n", .{entry.info.mnemonic});
    std.debug.print("Mode: {s}\n", .{@tagName(entry.info.mode)});
    std.debug.print("Addressing steps length: {}\n", .{entry.addressing_steps.len});

    try testing.expectEqual(@as(usize, 1), entry.addressing_steps.len);
}

test "Dispatch table entry for 0xEA (NOP implied)" {
    const entry = dispatch.DISPATCH_TABLE[0xEA];

    std.debug.print("\n=== Dispatch Entry 0xEA ===\n", .{});
    std.debug.print("Mnemonic: {s}\n", .{entry.info.mnemonic});
    std.debug.print("Mode: {s}\n", .{@tagName(entry.info.mode)});
    std.debug.print("Addressing steps length: {}\n", .{entry.addressing_steps.len});

    try testing.expectEqual(@as(usize, 0), entry.addressing_steps.len);
}
