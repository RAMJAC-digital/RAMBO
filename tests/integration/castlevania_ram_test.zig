//! Castlevania RAM Initialization Pattern Test
//!
//! Based on SMB RAM test findings, this tests if Castlevania's boot behavior
//! is affected by initial RAM state (all zeros, all $FF, specific patterns, etc.)
//!
//! Hypothesis: Some games check RAM for specific patterns during initialization
//! and take different code paths based on what they find.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Config = RAMBO.Config.Config;
const EmulationState = RAMBO.EmulationState.EmulationState;
const CartridgeLoader = RAMBO.CartridgeLoader;

const FRAME_PIXELS = 256 * 240;

test "Castlevania: RAM pattern affects rendering initialization" {
    const allocator = testing.allocator;

    // Load Castlevania ROM (Mapper 2 / UxROM)
    const rom_path = "tests/data/Castlevania/Castlevania (USA) (Rev 1).nes";
    const cart = try CartridgeLoader.loadAnyCartridgeFile(allocator, rom_path);

    var config = Config.init(allocator);
    defer config.deinit();

    const ram_patterns = [_]struct {
        name: []const u8,
        fill: u8,
    }{
        .{ .name = "all zeros", .fill = 0x00 },
        .{ .name = "all $FF", .fill = 0xFF },
        .{ .name = "all $AA", .fill = 0xAA },
        .{ .name = "all $55", .fill = 0x55 },
    };

    for (ram_patterns) |pattern| {
        std.debug.print("\n[RAM: {s}] Testing Castlevania boot...\n", .{pattern.name});

        var state = EmulationState.init(&config);
        defer state.deinit();

        // Fill RAM with pattern BEFORE loading cartridge
        @memset(&state.bus.ram, pattern.fill);

        state.loadCartridge(cart);
        state.power_on();

        var framebuffer = [_]u32{0} ** FRAME_PIXELS;

        // Run for 60 frames (1 second)
        var frame: usize = 0;
        var rendering_enabled = false;

        while (frame < 60) : (frame += 1) {
            state.framebuffer = &framebuffer;
            _ = state.emulateFrame();

            const ppumask: u8 = @bitCast(state.ppu.mask);
            const show_bg = (ppumask >> 3) & 1;
            const show_sprites = (ppumask >> 4) & 1;

            if (show_bg != 0 or show_sprites != 0) {
                rendering_enabled = true;
                std.debug.print("[RAM: {s}] PPUMASK=${X:0>2}, rendering=true at frame {d}\n",
                    .{ pattern.name, ppumask, frame });
                break;
            }
        }

        if (!rendering_enabled) {
            const final_mask: u8 = @bitCast(state.ppu.mask);
            const final_ctrl: u8 = @bitCast(state.ppu.ctrl);
            std.debug.print("[RAM: {s}] No rendering after 60 frames. PPUCTRL=${X:0>2} PPUMASK=${X:0>2} PC=${X:0>4}\n",
                .{ pattern.name, final_ctrl, final_mask, state.cpu.pc });
        }

        // For now, just report findings - don't fail test
        // If we find a pattern that works, we can make this a proper assertion
    }

    std.debug.print("\n=== RAM Pattern Test Complete ===\n", .{});
    std.debug.print("If all patterns show same behavior, RAM initialization is not the issue.\n", .{});
    std.debug.print("If one pattern enables rendering, we've found a dependency!\n", .{});
}

test "Castlevania: Pseudo-random RAM pattern" {
    const allocator = testing.allocator;

    const rom_path = "tests/data/Castlevania/Castlevania (USA) (Rev 1).nes";
    const cart = try CartridgeLoader.loadAnyCartridgeFile(allocator, rom_path);

    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    // Fill RAM with pseudo-random pattern (like power-on hardware behavior)
    // NES power-on RAM is unpredictable but tends toward certain patterns
    var prng = std.Random.DefaultPrng.init(0x12345678);
    const random = prng.random();
    for (&state.bus.ram) |*byte| {
        byte.* = random.int(u8);
    }

    state.loadCartridge(cart);
    state.power_on();

    var framebuffer = [_]u32{0} ** FRAME_PIXELS;

    std.debug.print("\n[RAM: pseudo-random] Testing Castlevania boot...\n", .{});

    var frame: usize = 0;
    while (frame < 60) : (frame += 1) {
        state.framebuffer = &framebuffer;
        _ = state.emulateFrame();

        const ppumask: u8 = @bitCast(state.ppu.mask);
        const show_bg = (ppumask >> 3) & 1;
        const show_sprites = (ppumask >> 4) & 1;

        if (show_bg != 0 or show_sprites != 0) {
            std.debug.print("[RAM: pseudo-random] PPUMASK=${X:0>2}, rendering=true at frame {d}\n",
                .{ ppumask, frame });
            std.debug.print("✅ SUCCESS: Pseudo-random pattern enables rendering!\n", .{});
            return; // Test passes!
        }
    }

    const final_mask: u8 = @bitCast(state.ppu.mask);
    const final_ctrl: u8 = @bitCast(state.ppu.ctrl);
    std.debug.print("[RAM: pseudo-random] No rendering after 60 frames. PPUCTRL=${X:0>2} PPUMASK=${X:0>2} PC=${X:0>4}\n",
        .{ final_ctrl, final_mask, state.cpu.pc });
}
