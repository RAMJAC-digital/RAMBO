//! Sprite Evaluation Tests
//!
//! Tests PPU sprite evaluation algorithm per nesdev.org specification.
//! References: docs/architecture/ppu-sprites.md
//!
//! Sprite evaluation occurs on visible scanlines (0-239):
//! - Cycles 1-64: Clear secondary OAM to $FF
//! - Cycles 65-256: Evaluate up to 8 sprites for next scanline
//! - Sets sprite_overflow flag if >8 sprites on scanline
//! - Sets sprite_0_hit flag when sprite 0 overlaps background

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Harness = RAMBO.TestHarness.Harness;

// ============================================================================
// SECONDARY OAM TESTS
// ============================================================================

test "Sprite Evaluation: Secondary OAM cleared to $FF at scanline start" {
    var harness = try Harness.init();
    defer harness.deinit();
    const ppu = &harness.state.ppu;

    // Fill secondary OAM with non-$FF values
    for (&ppu.secondary_oam) |*byte| {
        byte.* = 0xAA;
    }

    // Advance to scanline 0, before sprite evaluation
    harness.setPpuTiming(0, 0);

    // Run through clearing phase (cycles 1-64)
    harness.tickPpuCycles(64);

    // All secondary OAM should be $FF
    for (ppu.secondary_oam) |byte| {
        try testing.expectEqual(@as(u8, 0xFF), byte);
    }
}

test "Sprite Evaluation: Secondary OAM cleared every visible scanline" {
    var harness = try Harness.init();
    defer harness.deinit();
    const ppu = &harness.state.ppu;

    // Test on multiple scanlines
    for ([_]u16{ 0, 50, 120, 200, 239 }) |scanline| {
        // Fill with test pattern
        for (&ppu.secondary_oam) |*byte| {
            byte.* = 0x42;
        }

        // Position at start of scanline
        harness.setPpuTiming(scanline, 0);

        // Run clearing phase
        harness.tickPpuCycles(64);

        // Verify all $FF
        for (ppu.secondary_oam, 0..) |byte, i| {
            testing.expectEqual(
                @as(u8, 0xFF),
                byte,
            ) catch |err| {
                std.debug.print("Failed at scanline {}, byte {}\n", .{ scanline, i });
                return err;
            };
        }
    }
}

// ============================================================================
// SPRITE IN-RANGE DETECTION TESTS
// ============================================================================

test "Sprite Evaluation: Sprite Y=0 visible on scanline 0" {
    var harness = try Harness.init();
    defer harness.deinit();
    const ppu = &harness.state.ppu;

    // Enable rendering
    ppu.mask.show_sprites = true;

    // Place sprite at Y=0 (8×8 sprite, visible on scanlines 0-7)
    ppu.oam[0] = 0; // Y position
    ppu.oam[1] = 0; // Tile index
    ppu.oam[2] = 0; // Attributes
    ppu.oam[3] = 0; // X position

    // Mark other sprites as off-screen
    for (1..64) |i| {
        ppu.oam[i * 4] = 0xFF; // Y = $FF (never visible)
    }

    // Run sprite evaluation on scanline 0
    harness.setPpuTiming(0, 0);

    // Run through evaluation phase (cycles 1-256)
    harness.tickPpuCycles(256);

    // Secondary OAM should contain sprite 0
    try testing.expectEqual(@as(u8, 0), ppu.secondary_oam[0]); // Y
    try testing.expectEqual(@as(u8, 0), ppu.secondary_oam[1]); // Tile
    try testing.expectEqual(@as(u8, 0), ppu.secondary_oam[2]); // Attributes
    try testing.expectEqual(@as(u8, 0), ppu.secondary_oam[3]); // X
}

test "Sprite Evaluation: Sprite Y=$FF never visible" {
    var harness = try Harness.init();
    defer harness.deinit();
    const ppu = &harness.state.ppu;
    ppu.mask.show_sprites = true;

    // Place sprite at Y=$FF (should never be visible)
    ppu.oam[0] = 0xFF;
    ppu.oam[1] = 0x42;
    ppu.oam[2] = 0x00;
    ppu.oam[3] = 0x80;

    // Mark other sprites off-screen
    for (1..64) |i| {
        ppu.oam[i * 4] = 0xFF;
    }

    // Test on various scanlines
    for ([_]u16{ 0, 100, 200, 239 }) |scanline| {
        // Clear secondary OAM
        for (&ppu.secondary_oam) |*byte| {
            byte.* = 0xAA;
        }

        harness.setPpuTiming(scanline, 0);

        // Run evaluation
        harness.tickPpuCycles(256);

        // Secondary OAM should be cleared but empty (all $FF)
        try testing.expectEqual(@as(u8, 0xFF), ppu.secondary_oam[0]);
        try testing.expectEqual(@as(u8, 0xFF), ppu.secondary_oam[1]);
        try testing.expectEqual(@as(u8, 0xFF), ppu.secondary_oam[2]);
        try testing.expectEqual(@as(u8, 0xFF), ppu.secondary_oam[3]);
    }
}

test "Sprite Evaluation: 8×8 sprite range check" {
    var harness = try Harness.init();
    defer harness.deinit();
    const ppu = &harness.state.ppu;
    ppu.mask.show_sprites = true;
    ppu.ctrl.sprite_size = false; // 8×8 mode

    // Sprite at Y=100 visible on scanlines 100-107 (8 pixels tall)
    ppu.oam[0] = 100;
    ppu.oam[1] = 0x42;
    ppu.oam[2] = 0x00;
    ppu.oam[3] = 0x80;

    // Mark other sprites off-screen
    for (1..64) |i| {
        ppu.oam[i * 4] = 0xFF;
    }

    // Test visible range
    for ([_]u16{ 100, 103, 107 }) |scanline| {
        // Clear secondary OAM
        for (&ppu.secondary_oam) |*byte| {
            byte.* = 0xFF;
        }

        harness.setPpuTiming(scanline, 0);

        harness.tickPpuCycles(256);

        // Should be in secondary OAM
        testing.expectEqual(@as(u8, 100), ppu.secondary_oam[0]) catch |err| {
            std.debug.print("Failed at scanline {} (should be visible)\n", .{scanline});
            return err;
        };
    }

    // Test outside range
    for ([_]u16{ 99, 108, 150 }) |scanline| {
        // Clear secondary OAM
        for (&ppu.secondary_oam) |*byte| {
            byte.* = 0xAA;
        }

        harness.setPpuTiming(scanline, 0);

        harness.tickPpuCycles(256);

        // Should NOT be in secondary OAM (all $FF)
        testing.expectEqual(@as(u8, 0xFF), ppu.secondary_oam[0]) catch |err| {
            std.debug.print("Failed at scanline {} (should NOT be visible)\n", .{scanline});
            return err;
        };
    }
}

test "Sprite Evaluation: 8×16 sprite range check" {
    var harness = try Harness.init();
    defer harness.deinit();
    const ppu = &harness.state.ppu;
    ppu.mask.show_sprites = true;
    ppu.ctrl.sprite_size = true; // 8×16 mode

    // Sprite at Y=100 visible on scanlines 100-115 (16 pixels tall)
    ppu.oam[0] = 100;
    ppu.oam[1] = 0x42;
    ppu.oam[2] = 0x00;
    ppu.oam[3] = 0x80;

    // Mark other sprites off-screen
    for (1..64) |i| {
        ppu.oam[i * 4] = 0xFF;
    }

    // Test visible range
    for ([_]u16{ 100, 107, 115 }) |scanline| {
        // Clear secondary OAM
        for (&ppu.secondary_oam) |*byte| {
            byte.* = 0xFF;
        }

        harness.setPpuTiming(scanline, 0);

        harness.tickPpuCycles(256);

        // Should be in secondary OAM
        testing.expectEqual(@as(u8, 100), ppu.secondary_oam[0]) catch |err| {
            std.debug.print("Failed at scanline {} (should be visible in 8×16 mode)\n", .{scanline});
            return err;
        };
    }

    // Test outside range
    for ([_]u16{ 99, 116, 150 }) |scanline| {
        // Clear secondary OAM
        for (&ppu.secondary_oam) |*byte| {
            byte.* = 0xAA;
        }

        harness.setPpuTiming(scanline, 0);

        harness.tickPpuCycles(256);

        // Should NOT be in secondary OAM (all $FF)
        testing.expectEqual(@as(u8, 0xFF), ppu.secondary_oam[0]) catch |err| {
            std.debug.print("Failed at scanline {} (should NOT be visible)\n", .{scanline});
            return err;
        };
    }
}

// ============================================================================
// 8 SPRITE LIMIT TESTS
// ============================================================================

test "Sprite Evaluation: 8 sprite limit enforced" {
    var harness = try Harness.init();
    defer harness.deinit();
    const ppu = &harness.state.ppu;
    ppu.mask.show_sprites = true;

    // Place 10 sprites on scanline 100-107 (all overlapping)
    for (0..10) |i| {
        ppu.oam[i * 4 + 0] = 100; // Y position
        ppu.oam[i * 4 + 1] = @intCast(i); // Tile index (unique per sprite)
        ppu.oam[i * 4 + 2] = 0x00; // Attributes
        ppu.oam[i * 4 + 3] = @intCast(i * 8); // X position (spread out)
    }

    // Mark remaining sprites off-screen
    for (10..64) |i| {
        ppu.oam[i * 4] = 0xFF;
    }

    // Run evaluation on scanline 100
    harness.setPpuTiming(100, 0);

    harness.tickPpuCycles(256);

    // Secondary OAM should contain first 8 sprites (32 bytes)
    for (0..8) |i| {
        const y = ppu.secondary_oam[i * 4 + 0];
        const tile = ppu.secondary_oam[i * 4 + 1];

        testing.expectEqual(@as(u8, 100), y) catch |err| {
            std.debug.print("Sprite {} Y mismatch\n", .{i});
            return err;
        };

        testing.expectEqual(@as(u8, @intCast(i)), tile) catch |err| {
            std.debug.print("Sprite {} tile mismatch\n", .{i});
            return err;
        };
    }

    // Remaining secondary OAM should be $FF (9th and 10th sprites not copied)
    // Note: This assumes secondary OAM remains at 32 bytes (8 sprites × 4 bytes)
}

test "Sprite Evaluation: Sprite overflow flag set when >8 sprites" {
    var harness = try Harness.init();
    defer harness.deinit();
    const ppu = &harness.state.ppu;
    ppu.mask.show_sprites = true;

    // Clear overflow flag
    ppu.status.sprite_overflow = false;

    // Place 10 sprites all on same scanline
    for (0..10) |i| {
        ppu.oam[i * 4 + 0] = 100; // Y position
        ppu.oam[i * 4 + 1] = @intCast(i);
        ppu.oam[i * 4 + 2] = 0x00;
        ppu.oam[i * 4 + 3] = @intCast(i * 8);
    }

    for (10..64) |i| {
        ppu.oam[i * 4] = 0xFF;
    }

    // Run evaluation
    harness.setPpuTiming(100, 0);

    harness.tickPpuCycles(256);

    // Overflow flag should be set
    try testing.expect(ppu.status.sprite_overflow);
}

test "Sprite Evaluation: Sprite overflow flag NOT set when ≤8 sprites" {
    var harness = try Harness.init();
    defer harness.deinit();
    const ppu = &harness.state.ppu;
    ppu.mask.show_sprites = true;

    // Clear overflow flag
    ppu.status.sprite_overflow = false;

    // Place exactly 8 sprites on scanline
    for (0..8) |i| {
        ppu.oam[i * 4 + 0] = 100;
        ppu.oam[i * 4 + 1] = @intCast(i);
        ppu.oam[i * 4 + 2] = 0x00;
        ppu.oam[i * 4 + 3] = @intCast(i * 8);
    }

    for (8..64) |i| {
        ppu.oam[i * 4] = 0xFF;
    }

    // Run evaluation
    harness.setPpuTiming(100, 0);

    harness.tickPpuCycles(256);

    // Overflow flag should NOT be set
    try testing.expect(!ppu.status.sprite_overflow);
}

test "Sprite Evaluation: Sprite overflow cleared at pre-render scanline" {
    var harness = try Harness.init();
    defer harness.deinit();
    const ppu = &harness.state.ppu;
    ppu.mask.show_sprites = true;

    // Set overflow flag
    ppu.status.sprite_overflow = true;

    // Advance to pre-render scanline (261), dot 1
    // Flags are cleared DURING dot 1, so we need to tick AT dot 1
    harness.setPpuTiming(261, 1);
    harness.tickPpu(); // Ticks at dot 1 (where clearing happens)

    // Overflow flag should be cleared
    try testing.expect(!ppu.status.sprite_overflow);
}

// ============================================================================
// SPRITE 0 HIT DETECTION TESTS
// ============================================================================

test "Sprite 0 Hit: Not set when sprites disabled" {
    var harness = try Harness.init();
    defer harness.deinit();
    const ppu = &harness.state.ppu;
    ppu.mask.show_sprites = false; // Sprites disabled
    ppu.mask.show_bg = true;

    // Place sprite 0 on screen
    ppu.oam[0] = 50; // Y
    ppu.oam[1] = 0x00; // Tile
    ppu.oam[2] = 0x00; // Attributes
    ppu.oam[3] = 50; // X

    // Fill background with non-transparent pixels
    for (&ppu.palette_ram) |*p| {
        p.* = 0x0F;
    }

    // Run full scanline 50
    harness.setPpuTiming(50, 0);
    var framebuffer = [_]u32{0} ** (256 * 240);

    for (0..341) |_| {
        harness.tickPpuWithFramebuffer(framebuffer[0..]);
    }

    // Sprite 0 hit should NOT be set (sprites disabled)
    try testing.expect(!ppu.status.sprite_0_hit);
}

test "Sprite 0 Hit: Not set when background disabled" {
    var harness = try Harness.init();
    defer harness.deinit();
    const ppu = &harness.state.ppu;
    ppu.mask.show_sprites = true;
    ppu.mask.show_bg = false; // Background disabled

    // Place sprite 0 on screen
    ppu.oam[0] = 50;
    ppu.oam[1] = 0x00;
    ppu.oam[2] = 0x00;
    ppu.oam[3] = 50;

    // Run full scanline
    harness.setPpuTiming(50, 0);
    var framebuffer = [_]u32{0} ** (256 * 240);

    for (0..341) |_| {
        harness.tickPpuWithFramebuffer(framebuffer[0..]);
    }

    // Sprite 0 hit should NOT be set (background disabled)
    try testing.expect(!ppu.status.sprite_0_hit);
}

test "Sprite 0 Hit: Cleared at pre-render scanline" {
    var harness = try Harness.init();
    defer harness.deinit();
    const ppu = &harness.state.ppu;
    ppu.mask.show_sprites = true;
    ppu.mask.show_bg = true;

    // Set sprite 0 hit flag
    ppu.status.sprite_0_hit = true;

    // Advance to pre-render scanline (261), dot 1
    // Flags are cleared DURING dot 1, so we need to tick AT dot 1
    harness.setPpuTiming(261, 1);
    harness.tickPpu();

    // Flag should be cleared
    try testing.expect(!ppu.status.sprite_0_hit);
}

// ============================================================================
// SPRITE EVALUATION TIMING TESTS
// ============================================================================

test "Sprite Evaluation: Only occurs on visible scanlines (0-239)" {
    var harness = try Harness.init();
    defer harness.deinit();
    const ppu = &harness.state.ppu;
    ppu.mask.show_sprites = true;

    // Mark all sprites off-screen initially
    for (0..64) |i| {
        ppu.oam[i * 4] = 0xFF;
    }

    // Place sprite 0 at Y=240 (visible on scanlines 240-247)
    ppu.oam[0] = 240;
    ppu.oam[1] = 0x42;
    ppu.oam[2] = 0x00;
    ppu.oam[3] = 0x80;

    // Test VBlank scanline (241) - no evaluation
    harness.setPpuTiming(241, 0);

    harness.tickPpuCycles(256);

    // Secondary OAM should be all $FF (no evaluation during VBlank)
    try testing.expectEqual(@as(u8, 0xFF), ppu.secondary_oam[0]);

    // Test pre-render scanline (261) - no evaluation
    harness.setPpuTiming(261, 0);

    harness.tickPpuCycles(256);

    // Secondary OAM should still be all $FF
    try testing.expectEqual(@as(u8, 0xFF), ppu.secondary_oam[0]);
}

test "Sprite Evaluation: Rendering disabled prevents evaluation" {
    var harness = try Harness.init();
    defer harness.deinit();
    const ppu = &harness.state.ppu;
    ppu.mask.show_sprites = false; // Rendering disabled
    ppu.mask.show_bg = false;

    // Mark all sprites off-screen initially
    for (0..64) |i| {
        ppu.oam[i * 4] = 0xFF;
    }

    // Place sprite at Y=100
    ppu.oam[0] = 100;
    ppu.oam[1] = 0x42;
    ppu.oam[2] = 0x00;
    ppu.oam[3] = 0x80;

    // Run evaluation on scanline 100
    harness.setPpuTiming(100, 0);

    harness.tickPpuCycles(256);

    // Secondary OAM should be all $FF (no evaluation when rendering disabled)
    try testing.expectEqual(@as(u8, 0xFF), ppu.secondary_oam[0]);
}
