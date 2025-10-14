//! Super Mario Bros Animation Diagnostic Test
//!
//! This test verifies that SMB title screen animations work correctly after bug fixes:
//! - Bug Fix #1: Sprite 0 hit requires BOTH BG and sprite rendering
//! - Bug Fix #2: Write toggle (w register) cleared at scanline 261 dot 1
//!
//! Expected behavior: OAM sprite positions should change frame-to-frame

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

test "SMB: Title screen sprite data changes frame-to-frame" {
    const allocator = testing.allocator;

    // Load SMB ROM
    const rom_path = "tests/data/Mario/Super Mario Bros. (World).nes";
    const rom_data = std.fs.cwd().readFileAlloc(allocator, rom_path, 1024 * 1024) catch |err| {
        std.debug.print("Failed to load SMB ROM: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer allocator.free(rom_data);

    // Parse ROM
    var cart = try RAMBO.Cartridge.Loader.loadFromBytes(allocator, rom_data);
    defer cart.deinit(allocator);

    // Create emulation state
    var config = RAMBO.Config.Config.init(allocator);
    defer config.deinit();

    var state = RAMBO.EmulationState.EmulationState.init(allocator, &config);
    defer state.deinit();

    // Connect cartridge
    state.cart = cart;
    state.connectComponents();
    state.reset();

    // Run for 180 frames (SMB displays title screen around frame 180)
    const target_frames: u64 = 180;
    while (state.clock.frame() < target_frames) {
        state.tick();
    }

    // Capture OAM sprite Y positions at frame 180
    var oam_snapshot_1: [64]u8 = undefined;
    for (0..64) |i| {
        oam_snapshot_1[i] = state.ppu.oam[i * 4]; // Y position
    }

    // Run for 60 more frames (1 second of animation)
    const end_frame = target_frames + 60;
    while (state.clock.frame() < end_frame) {
        state.tick();
    }

    // Capture OAM sprite Y positions at frame 240
    var oam_snapshot_2: [64]u8 = undefined;
    for (0..64) |i| {
        oam_snapshot_2[i] = state.ppu.oam[i * 4]; // Y position
    }

    // Count how many sprites changed position
    var changed_count: usize = 0;
    for (0..64) |i| {
        if (oam_snapshot_1[i] != oam_snapshot_2[i]) {
            changed_count += 1;
        }
    }

    // SMB coin bounce animation should cause at least 1 sprite to change Y position
    // If animation is working, we expect changed_count > 0
    // If animation is frozen (bug), changed_count == 0

    std.debug.print("\nSMB Animation Diagnostic:\n", .{});
    std.debug.print("  Sprites with changed Y position: {}/{}\n", .{ changed_count, 64 });
    std.debug.print("  Frame range: {} -> {}\n", .{ target_frames, end_frame });

    // Print first 8 sprite Y positions for debugging
    std.debug.print("  Frame {}: [", .{target_frames});
    for (0..8) |i| {
        std.debug.print("{} ", .{oam_snapshot_1[i]});
    }
    std.debug.print("]\n", .{});

    std.debug.print("  Frame {}: [", .{end_frame});
    for (0..8) |i| {
        std.debug.print("{} ", .{oam_snapshot_2[i]});
    }
    std.debug.print("]\n", .{});

    // Expect at least 1 sprite changed (animation working)
    if (changed_count == 0) {
        std.debug.print("  ❌ ANIMATION FROZEN: No sprites changed position!\n", .{});
        return error.TestExpectedEqual;
    } else {
        std.debug.print("  ✅ ANIMATION WORKING: Sprites are moving!\n", .{});
    }

    try testing.expect(changed_count > 0);
}

test "SMB: Rendering enabled after initialization" {
    const allocator = testing.allocator;

    // Load SMB ROM
    const rom_path = "tests/data/Mario/Super Mario Bros. (World).nes";
    const rom_data = std.fs.cwd().readFileAlloc(allocator, rom_path, 1024 * 1024) catch |err| {
        std.debug.print("Failed to load SMB ROM: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer allocator.free(rom_data);

    // Parse ROM
    var cart = try RAMBO.Cartridge.Loader.loadFromBytes(allocator, rom_data);
    defer cart.deinit(allocator);

    // Create emulation state
    var config = RAMBO.Config.Config.init(allocator);
    defer config.deinit();

    var state = RAMBO.EmulationState.EmulationState.init(allocator, &config);
    defer state.deinit();

    state.cart = cart;
    state.connectComponents();
    state.reset();

    // Run for 180 frames
    const target_frames: u64 = 180;
    while (state.clock.frame() < target_frames) {
        state.tick();
    }

    // Verify rendering is enabled (this was working even before the fix)
    std.debug.print("\nSMB Rendering Status at frame {}:\n", .{target_frames});
    std.debug.print("  PPUMASK=${{X:02}}\n", .{state.ppu.mask.raw()});
    std.debug.print("  show_bg={}\n", .{state.ppu.mask.show_bg});
    std.debug.print("  show_sprites={}\n", .{state.ppu.mask.show_sprites});

    try testing.expect(state.ppu.mask.show_bg);
    try testing.expect(state.ppu.mask.show_sprites);
}
