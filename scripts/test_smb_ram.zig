///! Quick SMB RAM pattern test runner
const std = @import("std");
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;
const NromCart = RAMBO.CartridgeType;
const AnyCartridge = RAMBO.AnyCartridge;

const FRAME_PIXELS = 256 * 240;

fn testPattern(allocator: std.mem.Allocator, pattern_name: []const u8, pattern_value: u8, comptime use_random: bool) !void {
    std.debug.print("\n[Testing {s}]\n", .{pattern_name});

    const nrom_cart = NromCart.load(allocator, "tests/data/Mario/Super Mario Bros. (World).nes") catch |err| {
        std.debug.print("  ERROR: {}\n", .{err});
        return;
    };

    const cart = AnyCartridge{ .nrom = nrom_cart };

    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    // Initialize RAM with pattern
    if (use_random) {
        var prng = std.Random.DefaultPrng.init(0x1234);
        const random = prng.random();
        for (&state.bus.ram) |*byte| {
            byte.* = if (random.int(u8) < 192) 0xFF else 0x00;
        }
    } else {
        @memset(&state.bus.ram, pattern_value);
    }

    state.loadCartridge(cart);
    state.power_on();

    var framebuffer = [_]u32{0} ** FRAME_PIXELS;

    // Run for 180 frames (3 seconds)
    var frame: usize = 0;
    while (frame < 180) : (frame += 1) {
        state.framebuffer = &framebuffer;
        _ = state.emulateFrame();
    }

    const ppumask = @as(u8, @bitCast(state.ppu.mask));
    const rendering_enabled = (ppumask & 0x18) != 0;

    std.debug.print("  PPUMASK: ${X:02}\n", .{ppumask});
    std.debug.print("  Rendering enabled: {}\n", .{rendering_enabled});

    if (rendering_enabled) {
        std.debug.print("  ✅ SUCCESS: Rendering enabled!\n", .{});
    } else {
        std.debug.print("  ❌ FAIL: Rendering not enabled\n", .{});
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== SMB RAM Initialization Pattern Test ===\n", .{});

    try testPattern(allocator, "All $00 (current)", 0x00, false);
    try testPattern(allocator, "All $FF", 0xFF, false);
    try testPattern(allocator, "All $AA", 0xAA, false);
    try testPattern(allocator, "Pseudo-random", 0, true);

    std.debug.print("\n=== Test Complete ===\n", .{});
}
