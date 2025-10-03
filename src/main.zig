const std = @import("std");
const RAMBO = @import("RAMBO");

pub fn main() !void {
    std.debug.print("RAMBO NES Emulator\n", .{});
    std.debug.print("Initializing...\n", .{});

    // Initialize CPU and Bus using proper type exports
    const cpu = RAMBO.CpuType.init();
    const bus = RAMBO.BusType.init();

    // For now, just verify initialization
    std.debug.print("CPU initialized - PC: 0x{X:0>4}, SP: 0x{X:0>2}\n", .{ cpu.pc, cpu.sp });
    std.debug.print("Bus initialized - cycle: {}\n", .{bus.cycle});
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
