//! Super Mario Bros Sprite Palette Diagnostic
//!
//! Investigates the "green left 4 pixels" issue on `?` boxes.
//! Dumps OAM sprite data and palette RAM to identify incorrect palette selection.

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;
const NromCart = RAMBO.CartridgeType;
const AnyCartridge = RAMBO.AnyCartridge;

test "SMB: Sprite palette diagnostic (? boxes)" {
    const allocator = testing.allocator;

    // Load SMB ROM
    const nrom_cart = NromCart.load(allocator, "tests/data/Mario/Super Mario Bros. (World).nes") catch |err| {
        if (err == error.FileNotFound) return err;
        std.debug.print("Failed to load SMB ROM: {}\n", .{err});
        return error.SkipZigTest;
    };

    const cart = AnyCartridge{ .nrom = nrom_cart };

    // Create emulation state
    var config = Config.init(allocator);
    defer config.deinit();

    var state = EmulationState.init(&config);
    defer state.deinit();

    // Load cartridge and power on
    state.loadCartridge(cart);
    state.power_on();

    // Run until gameplay starts (World 1-1)
    // Title screen is around frame 180, but we need to wait for game to start
    // After pressing start, gameplay begins around frame 240-300
    // Need framebuffer for rendering
    const FRAME_PIXELS = 256 * 240;
    var framebuffer = [_]u32{0} ** FRAME_PIXELS;

    // Run for 500 frames to get well into gameplay with ? boxes visible
    const target_frame: u64 = 500;
    var frames_run: usize = 0;
    while (frames_run < target_frame) {
        state.framebuffer = &framebuffer;
        _ = state.emulateFrame();
        frames_run += 1;
    }

    std.debug.print("\n=== SMB Sprite Palette Diagnostic ===\n", .{});
    std.debug.print("Frame: {}\n\n", .{state.clock.frame()});

    // Dump OAM sprite data for first 16 sprites
    std.debug.print("OAM Sprites (first 16):\n", .{});
    std.debug.print("  Idx  Y    Tile  Attr  X     Palette  H-Flip  V-Flip  Priority\n", .{});
    std.debug.print("  ---  ---  ----  ----  ---   -------  ------  ------  --------\n", .{});

    for (0..16) |i| {
        const oam_offset = i * 4;
        const y = state.ppu.oam[oam_offset];
        const tile = state.ppu.oam[oam_offset + 1];
        const attr = state.ppu.oam[oam_offset + 2];
        const x = state.ppu.oam[oam_offset + 3];

        const palette_select = attr & 0x03;
        const h_flip = (attr & 0x40) != 0;
        const v_flip = (attr & 0x80) != 0;
        const priority = (attr & 0x20) != 0;

        std.debug.print("  {:3}  {:3}  $", .{i, y});
        std.debug.print("{X:0>2}  $", .{tile});
        std.debug.print("{X:0>2}  {:3}   {}        {}       {}       {}\n", .{
            attr,
            x,
            palette_select,
            @intFromBool(h_flip),
            @intFromBool(v_flip),
            @intFromBool(priority),
        });
    }

    // Dump sprite palette RAM ($3F10-$3F1F)
    std.debug.print("\nSprite Palette RAM:\n", .{});
    for (0..4) |pal| {
        const base = 0x10 + (pal * 4);
        std.debug.print("  Palette {}: ${X:0>2} ${X:0>2} ${X:0>2} ${X:0>2}\n", .{
            pal,
            state.ppu.palette_ram[base],
            state.ppu.palette_ram[base + 1],
            state.ppu.palette_ram[base + 2],
            state.ppu.palette_ram[base + 3],
        });
    }

    // Dump background palette RAM for comparison ($3F00-$3F0F)
    std.debug.print("\nBackground Palette RAM:\n", .{});
    for (0..4) |pal| {
        const base = pal * 4;
        std.debug.print("  Palette {}: ${X:0>2} ${X:0>2} ${X:0>2} ${X:0>2}\n", .{
            pal,
            state.ppu.palette_ram[base],
            state.ppu.palette_ram[base + 1],
            state.ppu.palette_ram[base + 2],
            state.ppu.palette_ram[base + 3],
        });
    }

    // Identify ALL visible sprites (Y < 240, not $FF)
    std.debug.print("\nAll visible sprites:\n", .{});
    var visible_count: usize = 0;
    for (0..64) |i| {
        const oam_offset = i * 4;
        const y = state.ppu.oam[oam_offset];
        const tile = state.ppu.oam[oam_offset + 1];
        const attr = state.ppu.oam[oam_offset + 2];
        const x = state.ppu.oam[oam_offset + 3];

        // Skip $FF entries and off-screen sprites
        if (y < 240 and tile != 0xFF) {
            const palette_select = attr & 0x03;
            std.debug.print("  Sprite {:2}: Y={:3} Tile=${X:0>2} X={:3} Attr=${X:0>2} Palette={}\n", .{
                i,
                y,
                tile,
                x,
                attr,
                palette_select,
            });
            visible_count += 1;
        }
    }

    std.debug.print("Total visible sprites: {}\n", .{visible_count});

    // Look for ? box candidates specifically
    // SMB uses various tile indices for ? boxes depending on animation frame
    // Common indices: $24-$27 (item blocks), $C0-$C4 (various block types)
    std.debug.print("\nSearching for potential ? box sprites (wide tile range):\n", .{});
    var box_candidates: usize = 0;
    for (0..64) |i| {
        const oam_offset = i * 4;
        const y = state.ppu.oam[oam_offset];
        const tile = state.ppu.oam[oam_offset + 1];
        const attr = state.ppu.oam[oam_offset + 2];
        const x = state.ppu.oam[oam_offset + 3];

        // Broad search: tiles $20-$30 (item blocks) or $C0-$D0 (block variants)
        if (y < 240 and ((tile >= 0x20 and tile <= 0x30) or (tile >= 0xC0 and tile <= 0xD0))) {
            const palette_select = attr & 0x03;
            const h_flip = (attr & 0x40) != 0;
            const v_flip = (attr & 0x80) != 0;
            const priority = (attr & 0x20) != 0;

            std.debug.print("  CANDIDATE {:2}: Y={:3} X={:3} Tile=${X:0>2} Attr=${X:0>2}\n", .{
                i,
                y,
                x,
                tile,
                attr,
            });
            std.debug.print("                Palette={} H-Flip={} V-Flip={} Priority={}\n", .{
                palette_select,
                @intFromBool(h_flip),
                @intFromBool(v_flip),
                @intFromBool(priority),
            });
            box_candidates += 1;
        }
    }

    if (box_candidates == 0) {
        std.debug.print("  (No ? box candidates found - may use different tile indices)\n", .{});
        std.debug.print("  (Try examining sprites with tiles $24-$27 or check sprite pattern table)\n", .{});
    }

    std.debug.print("\n=== Diagnostic Complete ===\n", .{});

    // Don't fail the test - this is purely diagnostic
    try testing.expect(true);
}
