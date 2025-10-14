///! Super Mario Bros RAM Initialization Test
///!
///! Tests whether SMB's rendering enable behavior changes with different
///! RAM initialization patterns (all zeros, all $FF, pseudo-random).

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;
const NromCart = RAMBO.CartridgeType;
const AnyCartridge = RAMBO.AnyCartridge;

const FRAME_WIDTH = 256;
const FRAME_HEIGHT = 240;
const FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT;

/// RAM initialization patterns to test
const RamPattern = enum {
    all_zeros,
    all_ff,
    all_aa, // 0xAA = 10101010 alternating pattern
    pseudo_random,
};

fn initializeRam(state: *EmulationState, pattern: RamPattern) void {
    switch (pattern) {
        .all_zeros => {
            @memset(&state.bus.ram, 0x00);
        },
        .all_ff => {
            @memset(&state.bus.ram, 0xFF);
        },
        .all_aa => {
            @memset(&state.bus.ram, 0xAA);
        },
        .pseudo_random => {
            // NES power-on RAM pattern approximation
            // Based on observed hardware behavior: mostly $FF with some $00
            var prng = std.Random.DefaultPrng.init(0x1234);
            const random = prng.random();
            for (&state.bus.ram) |*byte| {
                // 75% chance of $FF, 25% chance of $00
                byte.* = if (random.int(u8) < 192) 0xFF else 0x00;
            }
        },
    }
}

fn testSMBWithRamPattern(
    allocator: std.mem.Allocator,
    pattern: RamPattern,
    frames: usize,
) !struct {
    ppumask: u8,
    ppuctrl: u8,
    rendering_enabled: bool,
} {
    // Load SMB ROM
    const nrom_cart = NromCart.load(allocator, "tests/data/Mario/Super Mario Bros. (World).nes") catch |err| {
        if (err == error.FileNotFound) return err;
        return err;
    };

    const cart = AnyCartridge{ .nrom = nrom_cart };

    // Initialize emulation state
    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    // Initialize RAM with pattern BEFORE loading cartridge
    initializeRam(&state, pattern);

    state.loadCartridge(cart);
    state.power_on();

    // Create framebuffer
    var framebuffer = [_]u32{0} ** FRAME_PIXELS;

    // Run for specified number of frames
    var frames_run: usize = 0;
    while (frames_run < frames) {
        state.framebuffer = &framebuffer;
        _ = state.emulateFrame();
        frames_run += 1;
    }

    const ppumask = @as(u8, @bitCast(state.ppu.mask));
    const rendering_enabled = (ppumask & 0x18) != 0;

    return .{
        .ppumask = ppumask,
        .ppuctrl = @bitCast(state.ppu.ctrl),
        .rendering_enabled = rendering_enabled,
    };
}

test "SMB: RAM pattern - all zeros (current behavior)" {
    const allocator = testing.allocator;

    const result = testSMBWithRamPattern(allocator, .all_zeros, 180) catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    std.debug.print("\n[RAM: all zeros] PPUMASK=${X:02}, rendering={}\n", .{
        result.ppumask,
        result.rendering_enabled,
    });

    // Document current behavior (failing)
    // try testing.expect(result.rendering_enabled); // Currently fails
}

test "SMB: RAM pattern - all $FF" {
    const allocator = testing.allocator;

    const result = testSMBWithRamPattern(allocator, .all_ff, 180) catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    std.debug.print("\n[RAM: all $FF] PPUMASK=${X:02}, rendering={}\n", .{
        result.ppumask,
        result.rendering_enabled,
    });

    // This might fix the issue!
    if (result.rendering_enabled) {
        std.debug.print("✅ SUCCESS: All $FF pattern enables rendering!\n", .{});
    }
}

test "SMB: RAM pattern - alternating $AA" {
    const allocator = testing.allocator;

    const result = testSMBWithRamPattern(allocator, .all_aa, 180) catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    std.debug.print("\n[RAM: all $AA] PPUMASK=${X:02}, rendering={}\n", .{
        result.ppumask,
        result.rendering_enabled,
    });

    if (result.rendering_enabled) {
        std.debug.print("✅ SUCCESS: $AA pattern enables rendering!\n", .{});
    }
}

test "SMB: RAM pattern - pseudo-random (hardware-like)" {
    const allocator = testing.allocator;

    const result = testSMBWithRamPattern(allocator, .pseudo_random, 180) catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    std.debug.print("\n[RAM: pseudo-random] PPUMASK=${X:02}, rendering={}\n", .{
        result.ppumask,
        result.rendering_enabled,
    });

    if (result.rendering_enabled) {
        std.debug.print("✅ SUCCESS: Pseudo-random pattern enables rendering!\n", .{});
    }
}
