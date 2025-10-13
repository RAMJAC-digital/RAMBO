const std = @import("std");
const testing = std.testing;
const RAMBO = @import("RAMBO");
const Config = RAMBO.Config;
const parser = RAMBO.ConfigParser;

// ============================================================================
// Basic Parsing Tests
// ============================================================================

test "parseKdl: empty content returns default config" {
    const allocator = testing.allocator;
    const config = try parser.parseKdl("", allocator);
    defer config.deinit();

    // Should have all default values
    try testing.expectEqual(Config.ConsoleVariant.nes_ntsc_frontloader, config.console);
    try testing.expectEqual(Config.CpuVariant.rp2a03g, config.cpu.variant);
}

test "parseKdl: simple CPU variant" {
    const allocator = testing.allocator;
    const kdl =
        \\cpu {
        \\    variant "RP2A03H"
        \\}
    ;
    const config = try parser.parseKdl(kdl, allocator);
    defer config.deinit();

    try testing.expectEqual(Config.CpuVariant.rp2a03h, config.cpu.variant);
}

test "parseKdl: PPU configuration" {
    const allocator = testing.allocator;
    const kdl =
        \\ppu {
        \\    variant "RP2C07"
        \\    region "PAL"
        \\    accuracy "frame"
        \\}
    ;
    const config = try parser.parseKdl(kdl, allocator);
    defer config.deinit();

    try testing.expectEqual(Config.PpuVariant.rp2c07_pal, config.ppu.variant);
    try testing.expectEqual(Config.VideoRegion.pal, config.ppu.region);
    try testing.expectEqual(Config.AccuracyLevel.frame, config.ppu.accuracy);
}

test "parseKdl: complete AccuracyCoin configuration" {
    const allocator = testing.allocator;
    const kdl =
        \\// AccuracyCoin target: NES NTSC front-loader
        \\console "NES-NTSC-FrontLoader"
        \\
        \\cpu {
        \\    variant "RP2A03G"
        \\    region "NTSC"
        \\}
        \\
        \\ppu {
        \\    variant "RP2C02G"
        \\    region "NTSC"
        \\    accuracy "cycle"
        \\}
    ;
    const config = try parser.parseKdl(kdl, allocator);
    defer config.deinit();

    try testing.expectEqual(Config.ConsoleVariant.nes_ntsc_frontloader, config.console);
    try testing.expectEqual(Config.CpuVariant.rp2a03g, config.cpu.variant);
    try testing.expectEqual(Config.VideoRegion.ntsc, config.cpu.region);
    try testing.expectEqual(Config.PpuVariant.rp2c02g_ntsc, config.ppu.variant);
    try testing.expectEqual(Config.AccuracyLevel.cycle, config.ppu.accuracy);
}

// ============================================================================
// Robustness Tests (inspired by zzt config.zig)
// ============================================================================

test "parseKdl: handles comments correctly" {
    const allocator = testing.allocator;
    const kdl =
        \\// This is a comment
        \\cpu {
        \\    variant "RP2A03G"  // inline comment
        \\    // another comment
        \\    region "NTSC"
        \\}
    ;
    const config = try parser.parseKdl(kdl, allocator);
    defer config.deinit();

    try testing.expectEqual(Config.CpuVariant.rp2a03g, config.cpu.variant);
    try testing.expectEqual(Config.VideoRegion.ntsc, config.cpu.region);
}

test "parseKdl: handles empty lines and whitespace" {
    const allocator = testing.allocator;
    const kdl =
        \\
        \\  cpu {
        \\
        \\    variant   "RP2A03G"
        \\
        \\  }
        \\
    ;
    const config = try parser.parseKdl(kdl, allocator);
    defer config.deinit();

    try testing.expectEqual(Config.CpuVariant.rp2a03g, config.cpu.variant);
}

test "parseKdl: malformed input doesn't crash - unknown key" {
    const allocator = testing.allocator;
    const kdl =
        \\cpu {
        \\    unknown_setting "value"
        \\    variant "RP2A03G"
        \\}
    ;
    // Should not crash, should ignore unknown key
    const config = try parser.parseKdl(kdl, allocator);
    defer config.deinit();

    try testing.expectEqual(Config.CpuVariant.rp2a03g, config.cpu.variant);
}

test "parseKdl: malformed input doesn't crash - invalid variant name" {
    const allocator = testing.allocator;
    const kdl =
        \\cpu {
        \\    variant "INVALID"
        \\}
    ;
    // Should not crash, should use default
    const config = try parser.parseKdl(kdl, allocator);
    defer config.deinit();

    // Should have default CPU variant
    try testing.expectEqual(Config.CpuVariant.rp2a03g, config.cpu.variant);
}

// ============================================================================
// Safety Limits Tests (prevent infinite loops, excessive processing)
// ============================================================================

test "parseKdl: respects maximum line limit" {
    const allocator = testing.allocator;

    // Create config with more than MAX_LINES (1000)
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try buffer.appendSlice("cpu {\n");
    var i: usize = 0;
    while (i < 1500) : (i += 1) {
        try buffer.writer().print("    variant \"RP2A03G\"  // line {}\n", .{i});
    }
    try buffer.appendSlice("}\n");

    // Should not hang or crash
    const config = try parser.parseKdl(buffer.items, allocator);
    defer config.deinit();

    // Should have parsed something before hitting limit
    try testing.expectEqual(Config.CpuVariant.rp2a03g, config.cpu.variant);
}

test "parseKdl: handles very long lines gracefully" {
    const allocator = testing.allocator;

    // Create line longer than MAX_LINE_LENGTH (1024)
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try buffer.appendSlice("cpu { variant \"RP2A03G\"");
    var i: usize = 0;
    while (i < 2000) : (i += 1) {
        try buffer.append(' ');
    }
    try buffer.appendSlice("}\n");

    // Should not crash, should skip the long line or truncate safely
    const config = try parser.parseKdl(buffer.items, allocator);
    defer config.deinit();

    // May or may not parse depending on line length handling
    // The important thing is it doesn't crash
    _ = config.cpu.variant;
}

// ============================================================================
// Video Configuration Tests
// ============================================================================

test "parseKdl: video backend configuration" {
    const allocator = testing.allocator;
    const kdl =
        \\video {
        \\    backend "vulkan"
        \\    vsync false
        \\    scale 4
        \\}
    ;
    const config = try parser.parseKdl(kdl, allocator);
    defer config.deinit();

    try testing.expectEqual(Config.VideoBackend.vulkan, config.video.backend);
    try testing.expect(!config.video.vsync);
    try testing.expectEqual(@as(u8, 4), config.video.scale);
}

// ============================================================================
// Multiple Sections Test
// ============================================================================

test "parseKdl: multiple sections together" {
    const allocator = testing.allocator;
    const kdl =
        \\console "NES-PAL"
        \\
        \\cpu {
        \\    variant "RP2A07"
        \\    region "PAL"
        \\}
        \\
        \\ppu {
        \\    variant "RP2C07"
        \\    region "PAL"
        \\}
        \\
        \\cic {
        \\    variant "CIC-NES-3195"
        \\    enabled true
        \\}
        \\
        \\controllers {
        \\    type "NES"
        \\}
        \\
        \\video {
        \\    backend "software"
        \\    vsync true
        \\    scale 2
        \\}
    ;
    const config = try parser.parseKdl(kdl, allocator);
    defer config.deinit();

    try testing.expectEqual(Config.ConsoleVariant.nes_pal, config.console);
    try testing.expectEqual(Config.CpuVariant.rp2a07, config.cpu.variant);
    try testing.expectEqual(Config.PpuVariant.rp2c07_pal, config.ppu.variant);
    try testing.expectEqual(Config.CicVariant.cic_nes_3195, config.cic.variant);
    try testing.expectEqual(Config.ControllerType.nes, config.controllers.type);
    try testing.expectEqual(Config.VideoBackend.software, config.video.backend);
}

// ============================================================================
// Fuzz Testing (various edge cases)
// ============================================================================

test "parseKdl: fuzz with various inputs" {
    const allocator = testing.allocator;

    const fuzz_inputs = [_][]const u8{
        "", // Empty
        "    \n  \n  ", // Only whitespace
        "// just comments\n", // Only comments
        "{\n}\n", // Empty braces
        "cpu { }", // Empty section
        "cpu {\nvariant\n}", // Missing value
        "cpu { variant }", // Missing value inline
        "\x00\x01\x02", // Binary data
    };

    for (fuzz_inputs) |input| {
        // Should not crash regardless of input
        const config = try parser.parseKdl(input, allocator);
        defer config.deinit();

        // Should return some valid config (likely defaults)
        _ = config.cpu.variant;
    }
}
