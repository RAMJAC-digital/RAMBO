const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const Harness = RAMBO.TestHarness.Harness;
const CartridgeLoader = RAMBO.CartridgeLoader;

fn loadRom(path: []const u8) !RAMBO.AnyCartridge {
    return CartridgeLoader.loadAnyCartridgeFile(testing.allocator, path) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("\n⚠️  Skipping test – ROM not found: {s}\n", .{path});
            return error.SkipZigTest;
        },
        else => return err,
    };
}

fn warmup(h: *Harness) void {
    while (!h.state.ppu.warmup_complete) {
        h.state.tick();
    }
}

fn bottomRegionIsMonotone(framebuffer: []const u32, rows: usize) bool {
    const width: usize = 256;
    const total_rows: usize = 240;
    const start_row = if (rows >= total_rows) 0 else total_rows - rows;
    const start_index = start_row * width;
    const slice = framebuffer[start_index .. width * total_rows];
    const first = slice[0];
    for (slice) |pixel| {
        if (pixel != first) {
            return false;
        }
    }
    return true;
}

fn runFramesCaptureBottom(
    rom_path: []const u8,
    frames: usize,
    bottom_rows: usize,
) !void {
    var harness = try Harness.init();
    defer harness.deinit();

    const cart = try loadRom(rom_path);
    harness.loadCartridge(cart);
    harness.state.reset();

    warmup(&harness);

    var framebuffer: [256 * 240]u32 = [_]u32{0} ** (256 * 240);
    harness.state.framebuffer = &framebuffer;

    // Advance frames; ensure final frame buffer is freshly written
    for (0..frames) |frame_index| {
        if (frame_index == frames - 1) {
            @memset(framebuffer[0..], 0);
        }
        _ = harness.state.emulateFrame();
    }

    const monotone = bottomRegionIsMonotone(framebuffer[0..], bottom_rows);
    try testing.expect(!monotone);
}

test "SMB3: status bar renders non-monotone bottom region" {
    try runFramesCaptureBottom(
        "tests/data/Mario/Super Mario Bros. 3 (USA) (Rev 1).nes",
        240,
        48,
    );
}

test "Kirby: intro dialog renders non-monotone bottom region" {
    try runFramesCaptureBottom(
        "tests/data/Kirby's Adventure (USA) (Rev 1).nes",
        300,
        48,
    );
}

test "Mega Man 4: gameplay renders non-monotone bottom region" {
    try runFramesCaptureBottom(
        "tests/data/Mega Man/Mega Man 4 (USA) (Rev 1).nes",
        300,
        64,
    );
}
