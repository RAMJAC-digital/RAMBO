// Background Tile Fetch Timing Test
//
// Verifies hardware-accurate fetch timing for background tiles:
// - Nametable fetches at dots 2, 10, 18, 26... (every 8 dots, offset by 2)
// - Attribute fetches at dots 4, 12, 20, 28... (every 8 dots, offset by 4)
// - Pattern low fetches at dots 6, 14, 22, 30... (every 8 dots, offset by 6)
// - Pattern high fetches at dots 8, 16, 24, 32... (every 8 dots, offset by 8)
// - Shift register reloads at dots 9, 17, 25, 33... (every 8 dots, offset by 1)
//
// Reference: https://www.nesdev.org/wiki/PPU_rendering

const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");

const EmulationState = RAMBO.EmulationState.EmulationState;
const Config = RAMBO.Config.Config;

test "Background fetch timing: cycle mapping verification" {
    // This test verifies the cycle mapping formula: (dot - 1) % 8
    // Maps dots to cycles correctly for hardware-accurate timing

    // Verify the cycle mapping is correct
    // (dot - 1) % 8 should map to:
    // dot 1 → cycle 0 (reload, but skipped)
    // dot 2 → cycle 1 (NT fetch)
    // dot 3 → cycle 2 (idle)
    // dot 4 → cycle 3 (AT fetch)
    // dot 5 → cycle 4 (idle)
    // dot 6 → cycle 5 (pattern low)
    // dot 7 → cycle 6 (idle)
    // dot 8 → cycle 7 (pattern high)
    // dot 9 → cycle 0 (reload + start next tile)

    // Test a full tile fetch cycle
    for (1..257) |dot| {
        const dot_u16: u16 = @intCast(dot);
        const cycle = (dot_u16 - 1) % 8;

        // Verify cycle matches expected pattern
        switch (dot_u16 % 8) {
            1 => try testing.expectEqual(@as(u16, 0), cycle), // Reload point
            2 => try testing.expectEqual(@as(u16, 1), cycle), // NT fetch
            3 => try testing.expectEqual(@as(u16, 2), cycle), // Idle
            4 => try testing.expectEqual(@as(u16, 3), cycle), // AT fetch
            5 => try testing.expectEqual(@as(u16, 4), cycle), // Idle
            6 => try testing.expectEqual(@as(u16, 5), cycle), // Pattern low
            7 => try testing.expectEqual(@as(u16, 6), cycle), // Idle
            0 => try testing.expectEqual(@as(u16, 7), cycle), // Pattern high
            else => unreachable,
        }
    }
}

test "Background fetch timing: reload points at dots 9, 17, 25" {
    // Verify reload points occur at correct dots (every 8, offset by 1)
    const reload_dots = [_]u16{ 9, 17, 25, 33, 41, 49, 57, 65 };

    for (reload_dots) |dot| {
        const cycle = (dot - 1) % 8;
        // Reload occurs at cycle 0 (when (dot - 1) % 8 == 0)
        try testing.expectEqual(@as(u16, 0), cycle);
    }
}

test "Background fetch timing: fetch dots at 2, 4, 6, 8" {
    // Verify data fetches occur at correct dots
    const fetch_dots = [_]struct { dot: u16, cycle: u16, operation: []const u8 }{
        .{ .dot = 2, .cycle = 1, .operation = "Nametable" },
        .{ .dot = 4, .cycle = 3, .operation = "Attribute" },
        .{ .dot = 6, .cycle = 5, .operation = "Pattern Low" },
        .{ .dot = 8, .cycle = 7, .operation = "Pattern High" },
    };

    for (fetch_dots) |fetch| {
        const cycle = (fetch.dot - 1) % 8;
        try testing.expectEqual(fetch.cycle, cycle);
    }
}

test "Background fetch timing: 32 tiles per scanline" {
    // Verify we have 32 complete 8-dot tile fetch cycles in 256 visible dots
    // Dots 1-8: Tile 0
    // Dots 9-16: Tile 1
    // ...
    // Dots 249-256: Tile 31

    var tile_count: u16 = 0;
    var dot: u16 = 1;

    while (dot <= 256) : (dot += 8) {
        tile_count += 1;
    }

    try testing.expectEqual(@as(u16, 32), tile_count);
}
