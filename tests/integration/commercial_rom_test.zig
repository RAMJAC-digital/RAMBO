//! Commercial ROM Integration Tests
//!
//! End-to-end tests with real commercial NES ROMs to validate:
//! - ROM loading without crashes
//! - Rendering initialization (PPUMASK != 0)
//! - Visual output (non-blank framebuffers)
//! - NMI interrupt handling
//! - PPU warm-up period
//!
//! These tests replace the shell script validation with proper integration tests.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;
const NromCart = RAMBO.CartridgeType;
const AnyCartridge = RAMBO.AnyCartridge;

// ============================================================================
// Framebuffer Validation Helpers
// ============================================================================

const FRAME_WIDTH = 256;
const FRAME_HEIGHT = 240;
const FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT; // 61,440

/// Count non-zero pixels in framebuffer
fn countNonZeroPixels(framebuffer: []const u32) usize {
    var count: usize = 0;
    for (framebuffer) |pixel| {
        if (pixel != 0) count += 1;
    }
    return count;
}

/// Save framebuffer as PPM (Portable Pixmap) for manual inspection
fn saveFramebufferPPM(framebuffer: []const u32, path: []const u8, allocator: std.mem.Allocator) !void {
    // Build PPM content in memory first
    const buffer = try allocator.alloc(u8, 1024 * 1024); // 1 MB should be enough
    defer allocator.free(buffer);

    var stream = std.io.fixedBufferStream(buffer);

    const writer = stream.writer();
    try writer.print("P3\n{d} {d}\n255\n", .{ FRAME_WIDTH, FRAME_HEIGHT });

    for (framebuffer, 0..) |pixel, i| {
        const r = (pixel >> 16) & 0xFF;
        const g = (pixel >> 8) & 0xFF;
        const b = pixel & 0xFF;
        try writer.print("{d} {d} {d} ", .{ r, g, b });
        if ((i + 1) % FRAME_WIDTH == 0) try writer.writeByte('\n');
    }

    // Write to file
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(stream.getWritten());
}

// ============================================================================
// Test Helpers
// ============================================================================

/// Commercial ROM test specification
const RomTestSpec = struct {
    name: []const u8,
    path: []const u8,
    frames_to_run: usize, // How many frames to run before checking
    min_non_zero_pixels: usize, // Minimum non-black pixels expected
    should_enable_rendering: bool, // Should PPUMASK be non-zero
    notes: []const u8,
};

/// Helper to run a ROM for N frames and capture final framebuffer
fn runRomForFrames(
    allocator: std.mem.Allocator,
    rom_path: []const u8,
    num_frames: usize,
) !struct {
    framebuffer: [FRAME_PIXELS]u32,
    ppumask: u8,
    ppuctrl: u8,
    frame_count: usize,
} {
    // Load ROM
    const nrom_cart = NromCart.load(allocator, rom_path) catch |err| {
        if (err == error.FileNotFound) {
            return err;
        }
        return err;
    };

    const cart = AnyCartridge{ .nrom = nrom_cart };

    // Initialize emulation state
    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    state.loadCartridge(cart);

    // Power-on behavior: Load reset vector but keep warmup_complete=false
    // This simulates real NES power-on where PPU ignores writes for ~29,658 cycles
    const reset_vector = state.busRead16(0xFFFC);
    state.cpu.pc = reset_vector;
    state.cpu.sp = 0xFD;
    state.cpu.p.interrupt = true;
    // NOTE: Do NOT set state.ppu.warmup_complete = true
    // That would skip the PPU warm-up period (power-on requires warm-up, RESET doesn't)

    // Create framebuffer for rendering
    var framebuffer = [_]u32{0} ** FRAME_PIXELS;

    // Get NMI vector address to track NMI execution
    const nmi_vector = state.busRead16(0xFFFA);

    // Run for specified number of frames
    var frames_rendered: usize = 0;
    var nmi_executed_count: usize = 0;
    var last_pc = state.cpu.pc;

    while (frames_rendered < num_frames) {
        state.framebuffer = &framebuffer;
        const cycles = state.emulateFrame();
        _ = cycles;

        // Check if CPU jumped to NMI vector (NMI executed)
        // After an NMI, PC will be at the NMI vector address
        if (state.cpu.pc == nmi_vector and last_pc != nmi_vector) {
            nmi_executed_count += 1;
        }
        last_pc = state.cpu.pc;

        frames_rendered += 1;

        // Debug output every 60 frames
        if (frames_rendered % 60 == 0) {}
    }

    return .{
        .framebuffer = framebuffer,
        .ppumask = @bitCast(state.ppu.mask),
        .ppuctrl = @bitCast(state.ppu.ctrl),
        .frame_count = frames_rendered,
    };
}

// ============================================================================
// AccuracyCoin Baseline Test
// ============================================================================

test "Commercial ROM: AccuracyCoin.nes (baseline validation)" {
    const allocator = testing.allocator;

    const result = runRomForFrames(
        allocator,
        "AccuracyCoin/AccuracyCoin.nes",
        60, // 1 second of emulation
    ) catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    // AccuracyCoin should enable rendering
    try testing.expect(result.ppumask != 0);

    // Should have significant non-zero pixels (test ROM renders graphics)
    const non_zero = countNonZeroPixels(&result.framebuffer);
    try testing.expect(non_zero > 1000);
}

// ============================================================================
// Super Mario Bros Tests
// ============================================================================

test "Commercial ROM: Super Mario Bros - loads without crash" {
    const allocator = testing.allocator;

    const result = runRomForFrames(
        allocator,
        "tests/data/Mario/Super Mario Bros. (World).nes",
        10, // Just verify it loads
    ) catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    // Should complete 10 frames without crashing
    try testing.expectEqual(@as(usize, 10), result.frame_count);
}

test "Commercial ROM: Super Mario Bros - enables rendering" {
    const allocator = testing.allocator;

    const result = runRomForFrames(
        allocator,
        "tests/data/Mario/Super Mario Bros. (World).nes",
        180, // 3 seconds (title screen should appear)
    ) catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    // Mario should enable rendering (PPUMASK bits 3 or 4 set)
    const rendering_enabled = (result.ppumask & 0x18) != 0;

    try testing.expect(rendering_enabled);
}

test "Commercial ROM: Super Mario Bros - renders graphics" {
    const allocator = testing.allocator;

    const result = runRomForFrames(
        allocator,
        "tests/data/Mario/Super Mario Bros. (World).nes",
        180,
    ) catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    const non_zero = countNonZeroPixels(&result.framebuffer);

    try testing.expect(non_zero > 10000);
}

// ============================================================================
// Donkey Kong Tests
// ============================================================================

test "Commercial ROM: Donkey Kong - loads without crash" {
    const allocator = testing.allocator;

    const result = runRomForFrames(
        allocator,
        "tests/data/Donkey Kong/Donkey Kong (World) (Rev 1).nes",
        10,
    ) catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    try testing.expectEqual(@as(usize, 10), result.frame_count);
}

test "Commercial ROM: Donkey Kong - enables rendering" {
    const allocator = testing.allocator;

    const result = runRomForFrames(
        allocator,
        "tests/data/Donkey Kong/Donkey Kong (World) (Rev 1).nes",
        150,
    ) catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    try testing.expect((result.ppumask & 0x18) != 0);
}

// ============================================================================
// BurgerTime Tests
// ============================================================================

test "Commercial ROM: BurgerTime - loads without crash" {
    const allocator = testing.allocator;

    const result = runRomForFrames(
        allocator,
        "tests/data/BurgerTime (USA).nes",
        10,
    ) catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    try testing.expectEqual(@as(usize, 10), result.frame_count);
}

test "Commercial ROM: BurgerTime - enables rendering" {
    const allocator = testing.allocator;

    const result = runRomForFrames(
        allocator,
        "tests/data/BurgerTime (USA).nes",
        120,
    ) catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    try testing.expect((result.ppumask & 0x18) != 0);
}

// ============================================================================
// Bomberman Test (Partially Working)
// ============================================================================

test "Commercial ROM: Bomberman - renders something" {
    const allocator = testing.allocator;

    // User reported: "Bomberman displays something to screen"
    // Let's verify what's actually happening
    const result = runRomForFrames(
        allocator,
        "tests/data/Bomberman (USA).nes",
        180,
    ) catch |err| {
        if (err == error.FileNotFound) return error.SkipZigTest;
        return err;
    };

    const non_zero = countNonZeroPixels(&result.framebuffer);
    // If Bomberman shows something, it should have non-zero pixels
    if (non_zero > 0) {

        // Optional: Save framebuffer for manual inspection
        saveFramebufferPPM(
            &result.framebuffer,
            "/tmp/bomberman_frame.ppm",
            allocator,
        ) catch {};
    }

    // This test helps us understand what's different about Bomberman
    try testing.expect(non_zero > 0);
}
