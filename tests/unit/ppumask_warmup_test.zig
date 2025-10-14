const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;

test "PPUMASK writes blocked when warmup_complete=false" {
    const allocator = testing.allocator;
    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    // Manually set warmup_complete to false
    state.ppu.warmup_complete = false;

    // Try to write 0x18 to PPUMASK
    state.busWrite(0x2001, 0x18);

    // Read back PPUMASK value
    const ppumask: u8 = @bitCast(state.ppu.mask);

    // Should be 0 (write was blocked)
    try testing.expectEqual(@as(u8, 0x00), ppumask);
}

test "PPUMASK writes accepted when warmup_complete=true" {
    const allocator = testing.allocator;
    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    // Set warmup_complete to true
    state.ppu.warmup_complete = true;

    // Try to write 0x18 to PPUMASK
    state.busWrite(0x2001, 0x18);

    // Read back PPUMASK value
    const ppumask: u8 = @bitCast(state.ppu.mask);

    // Should be 0x18 (write was accepted)
    try testing.expectEqual(@as(u8, 0x18), ppumask);
}

test "power_on() sets warmup_complete to false (warmup required)" {
    const allocator = testing.allocator;
    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    // Call power_on
    state.power_on();

    // warmup_complete should be FALSE after power-on (warmup period required)
    try testing.expect(!state.ppu.warmup_complete);
}

test "warmup_complete sets to true after 29,658 CPU cycles" {
    const allocator = testing.allocator;
    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.power_on();

    // Initially false
    try testing.expect(!state.ppu.warmup_complete);

    // Emulate 29,657 CPU cycles (still warming up)
    _ = state.emulateCpuCycles(29657);
    try testing.expect(!state.ppu.warmup_complete);

    // Emulate 1 more cycle (29,658 total - warmup complete)
    _ = state.emulateCpuCycles(1);
    try testing.expect(state.ppu.warmup_complete);
}

test "reset() sets warmup_complete to true (no warmup for reset)" {
    const allocator = testing.allocator;
    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    // Set to false first
    state.ppu.warmup_complete = false;

    // Call reset
    state.reset();

    // warmup_complete should be TRUE (reset button skips warmup)
    try testing.expect(state.ppu.warmup_complete);
}
