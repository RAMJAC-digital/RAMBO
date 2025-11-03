//! RAMBO Configuration System
//!
//! Thread-safe configuration management using KDL-style syntax.
//! Supports hot-reload via libxev file watching (future enhancement).
//!
//! Design principles:
//! - Parse once, immutable after init (lock-free reads)
//! - Thread-safe via std.Thread.Mutex for reload operations
//! - Minimal allocations (arena allocator for config lifetime)

const std = @import("std");

// Re-export all types (preserves existing API)
pub const ConsoleVariant = @import("types.zig").ConsoleVariant;
pub const CpuVariant = @import("types.zig").CpuVariant;
pub const CpuModel = @import("types.zig").CpuModel;
pub const CicVariant = @import("types.zig").CicVariant;
pub const CicEmulation = @import("types.zig").CicEmulation;
pub const CicModel = @import("types.zig").CicModel;
pub const ControllerType = @import("types.zig").ControllerType;
pub const ControllerModel = @import("types.zig").ControllerModel;
pub const PpuVariant = @import("types.zig").PpuVariant;
pub const VideoRegion = @import("types.zig").VideoRegion;
pub const AccuracyLevel = @import("types.zig").AccuracyLevel;
pub const VideoBackend = @import("types.zig").VideoBackend;
pub const PpuModel = @import("types.zig").PpuModel;
pub const VideoConfig = @import("types.zig").VideoConfig;
pub const AudioConfig = @import("types.zig").AudioConfig;
pub const InputConfig = @import("types.zig").InputConfig;

// Re-export parser module for testing
pub const parser = @import("parser.zig");

/// Complete RAMBO configuration
pub const Config = struct {
    /// Console variant (defines default hardware configuration)
    console: ConsoleVariant = .nes_ntsc_frontloader,

    /// CPU configuration
    cpu: CpuModel = .{},

    /// PPU configuration
    ppu: PpuModel = .{},

    /// CIC lockout chip configuration
    cic: CicModel = .{},

    /// Controller configuration
    controllers: ControllerModel = .{},

    /// Video output configuration
    video: VideoConfig = .{},

    /// Audio configuration
    audio: AudioConfig = .{},

    /// Input configuration
    input: InputConfig = .{},

    /// Arena allocator for config lifetime
    arena: std.heap.ArenaAllocator,
    /// Mutex for thread-safe reload operations
    mutex: std.Thread.Mutex = .{},

    /// Initialize with default configuration
    pub fn init(allocator: std.mem.Allocator) Config {
        return .{
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Config) void {
        self.arena.deinit();
    }

    /// Load configuration from KDL file (functional factory method)
    /// Returns immutable Config with ownership transferred to caller
    pub fn fromFile(path: []const u8, allocator: std.mem.Allocator) !Config {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
        defer allocator.free(content);

        // Parse and return - ownership transferred to caller
        return try parser.parseKdl(content, allocator);
    }

    // Configuration fields can be accessed directly: config.ppu.variant, config.video.backend, etc.
    // No helper methods needed - direct field access is the idiomatic Zig approach.
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "Config: default values" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    // Console
    try testing.expectEqual(ConsoleVariant.nes_ntsc_frontloader, config.console);

    // CPU
    try testing.expectEqual(CpuVariant.rp2a03g, config.cpu.variant);
    try testing.expectEqual(VideoRegion.ntsc, config.cpu.region);

    // PPU
    try testing.expectEqual(PpuVariant.rp2c02g_ntsc, config.ppu.variant);
    try testing.expectEqual(VideoRegion.ntsc, config.ppu.region);
    try testing.expectEqual(AccuracyLevel.cycle, config.ppu.accuracy);

    // CIC
    try testing.expectEqual(CicVariant.cic_nes_3193, config.cic.variant);
    try testing.expect(config.cic.enabled);
    try testing.expectEqual(CicEmulation.state_machine, config.cic.emulation);

    // Controllers
    try testing.expectEqual(ControllerType.nes, config.controllers.type);

    // Video
    try testing.expectEqual(VideoBackend.software, config.video.backend);
    try testing.expect(config.video.vsync);
    try testing.expectEqual(@as(u8, 3), config.video.scale);
}

test "Config: PPU timing calculations" {
    var config = Config.init(testing.allocator);
    defer config.deinit();

    config.ppu.variant = .rp2c02g_ntsc;
    try testing.expectEqual(@as(u16, 262), config.ppu.scanlinesPerFrame());
    try testing.expectEqual(@as(u16, 341), config.ppu.cyclesPerScanline());
    try testing.expectEqual(@as(u64, 16_639), config.ppu.frameDurationUs());
    try testing.expectApproxEqAbs(@as(f64, 60.0988), config.ppu.frameRate(), 0.0001);

    config.ppu.variant = .rp2c07_pal;
    try testing.expectEqual(@as(u16, 312), config.ppu.scanlinesPerFrame());
    try testing.expectEqual(@as(u64, 19_997), config.ppu.frameDurationUs());
}

test "Config: parse simple KDL" {
    const kdl_content =
        \\ppu {
        \\    variant "RP2C02G"
        \\    region "NTSC"
        \\    accuracy "cycle"
        \\}
        \\video {
        \\    backend "opengl"
        \\    vsync false
        \\    scale 2
        \\}
    ;

    // Parse using stateless parser - use result directly
    var config = try parser.parseKdl(kdl_content, testing.allocator);
    defer config.deinit();

    try testing.expectEqual(PpuVariant.rp2c02g_ntsc, config.ppu.variant);
    try testing.expectEqual(VideoRegion.ntsc, config.ppu.region);
    try testing.expectEqual(AccuracyLevel.cycle, config.ppu.accuracy);
    try testing.expectEqual(VideoBackend.opengl, config.video.backend);
    try testing.expect(!config.video.vsync);
    try testing.expectEqual(@as(u8, 2), config.video.scale);
}

test "Config: enum parsing" {
    try testing.expectEqual(PpuVariant.rp2c02g_ntsc, try PpuVariant.fromString("RP2C02G"));
    try testing.expectEqual(PpuVariant.rp2c07_pal, try PpuVariant.fromString("RP2C07"));
    try testing.expectError(error.InvalidPpuVariant, PpuVariant.fromString("INVALID"));

    try testing.expectEqual(VideoRegion.ntsc, try VideoRegion.fromString("NTSC"));
    try testing.expectEqual(VideoRegion.pal, try VideoRegion.fromString("PAL"));

    try testing.expectEqual(AccuracyLevel.cycle, try AccuracyLevel.fromString("cycle"));
    try testing.expectEqual(AccuracyLevel.frame, try AccuracyLevel.fromString("frame"));

    try testing.expectEqual(VideoBackend.software, try VideoBackend.fromString("software"));
    try testing.expectEqual(VideoBackend.opengl, try VideoBackend.fromString("opengl"));
    try testing.expectEqual(VideoBackend.vulkan, try VideoBackend.fromString("vulkan"));
}

// ============================================================================
// New Hardware Configuration Tests
// ============================================================================

test "Config: CPU variant parsing" {
    try testing.expectEqual(CpuVariant.rp2a03e, try CpuVariant.fromString("RP2A03E"));
    try testing.expectEqual(CpuVariant.rp2a03g, try CpuVariant.fromString("RP2A03G"));
    try testing.expectEqual(CpuVariant.rp2a03h, try CpuVariant.fromString("RP2A03H"));
    try testing.expectEqual(CpuVariant.rp2a07, try CpuVariant.fromString("RP2A07"));
    try testing.expectError(error.InvalidCpuVariant, CpuVariant.fromString("INVALID"));
}

test "Config: CIC variant parsing" {
    try testing.expectEqual(CicVariant.cic_nes_3193, try CicVariant.fromString("CIC-NES-3193"));
    try testing.expectEqual(CicVariant.cic_nes_3195, try CicVariant.fromString("CIC-NES-3195"));
    try testing.expectEqual(CicVariant.cic_nes_3197, try CicVariant.fromString("CIC-NES-3197"));
    try testing.expectError(error.InvalidCicVariant, CicVariant.fromString("INVALID"));
}

test "Config: CIC emulation mode parsing" {
    try testing.expectEqual(CicEmulation.state_machine, try CicEmulation.fromString("state_machine"));
    try testing.expectEqual(CicEmulation.bypass, try CicEmulation.fromString("bypass"));
    try testing.expectEqual(CicEmulation.disabled, try CicEmulation.fromString("disabled"));
    try testing.expectError(error.InvalidCicEmulation, CicEmulation.fromString("INVALID"));
}

test "Config: Controller type parsing" {
    try testing.expectEqual(ControllerType.nes, try ControllerType.fromString("NES"));
    try testing.expectEqual(ControllerType.famicom, try ControllerType.fromString("Famicom"));
    try testing.expectError(error.InvalidControllerType, ControllerType.fromString("INVALID"));
}

test "Config: Console variant parsing" {
    try testing.expectEqual(ConsoleVariant.nes_ntsc_frontloader, try ConsoleVariant.fromString("NES-NTSC-FrontLoader"));
    try testing.expectEqual(ConsoleVariant.nes_ntsc_toploader, try ConsoleVariant.fromString("NES-NTSC-TopLoader"));
    try testing.expectEqual(ConsoleVariant.nes_pal, try ConsoleVariant.fromString("NES-PAL"));
    try testing.expectEqual(ConsoleVariant.famicom, try ConsoleVariant.fromString("Famicom"));
    try testing.expectEqual(ConsoleVariant.famicom_av, try ConsoleVariant.fromString("Famicom-AV"));
    try testing.expectError(error.InvalidConsoleVariant, ConsoleVariant.fromString("INVALID"));
}

test "Config: parse AccuracyCoin target configuration" {
    const kdl_content =
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
        \\
        \\cic {
        \\    variant "CIC-NES-3193"
        \\    enabled true
        \\    emulation "state_machine"
        \\}
        \\
        \\controllers {
        \\    type "NES"
        \\}
    ;

    // Using exported parser module
    var config = try parser.parseKdl(kdl_content, testing.allocator);
    defer config.deinit();

    // Verify AccuracyCoin target configuration
    try testing.expectEqual(ConsoleVariant.nes_ntsc_frontloader, config.console);
    try testing.expectEqual(CpuVariant.rp2a03g, config.cpu.variant);
    try testing.expectEqual(VideoRegion.ntsc, config.cpu.region);
    try testing.expectEqual(PpuVariant.rp2c02g_ntsc, config.ppu.variant);
    try testing.expectEqual(VideoRegion.ntsc, config.ppu.region);
    try testing.expectEqual(AccuracyLevel.cycle, config.ppu.accuracy);
    try testing.expectEqual(CicVariant.cic_nes_3193, config.cic.variant);
    try testing.expect(config.cic.enabled);
    try testing.expectEqual(CicEmulation.state_machine, config.cic.emulation);
    try testing.expectEqual(ControllerType.nes, config.controllers.type);
}

test "Config: parse PAL configuration" {
    const kdl_content =
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
        \\    accuracy "cycle"
        \\}
        \\
        \\cic {
        \\    variant "CIC-NES-3195"
        \\    enabled true
        \\    emulation "state_machine"
        \\}
        \\
        \\controllers {
        \\    type "NES"
        \\}
    ;

    // Using exported parser module
    var config = try parser.parseKdl(kdl_content, testing.allocator);
    defer config.deinit();

    try testing.expectEqual(ConsoleVariant.nes_pal, config.console);
    try testing.expectEqual(CpuVariant.rp2a07, config.cpu.variant);
    try testing.expectEqual(VideoRegion.pal, config.cpu.region);
    try testing.expectEqual(PpuVariant.rp2c07_pal, config.ppu.variant);
    try testing.expectEqual(VideoRegion.pal, config.ppu.region);
    try testing.expectEqual(CicVariant.cic_nes_3195, config.cic.variant);
    try testing.expectEqual(ControllerType.nes, config.controllers.type);
}

test "Config: parse top-loader NES configuration" {
    const kdl_content =
        \\console "NES-NTSC-TopLoader"
        \\
        \\cpu {
        \\    variant "RP2A03G"
        \\}
        \\
        \\ppu {
        \\    variant "RP2C02G"
        \\}
        \\
        \\cic {
        \\    enabled false
        \\    emulation "bypass"
        \\}
        \\
        \\controllers {
        \\    type "NES"
        \\}
    ;

    // Using exported parser module
    var config = try parser.parseKdl(kdl_content, testing.allocator);
    defer config.deinit();

    try testing.expectEqual(ConsoleVariant.nes_ntsc_toploader, config.console);
    try testing.expect(!config.cic.enabled);
    try testing.expectEqual(CicEmulation.bypass, config.cic.emulation);
}

test "Config: parse Famicom configuration" {
    const kdl_content =
        \\console "Famicom"
        \\
        \\cpu {
        \\    variant "RP2A03G"
        \\}
        \\
        \\ppu {
        \\    variant "RP2C02G"
        \\}
        \\
        \\controllers {
        \\    type "Famicom"
        \\}
    ;

    // Using exported parser module
    var config = try parser.parseKdl(kdl_content, testing.allocator);
    defer config.deinit();

    try testing.expectEqual(ConsoleVariant.famicom, config.console);
    try testing.expectEqual(ControllerType.famicom, config.controllers.type);
}

test "Config: complete hardware configuration" {
    const kdl_content =
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
        \\
        \\cic {
        \\    variant "CIC-NES-3193"
        \\    enabled true
        \\    emulation "state_machine"
        \\}
        \\
        \\controllers {
        \\    type "NES"
        \\}
        \\
        \\video {
        \\    backend "software"
        \\    vsync true
        \\    scale 3
        \\}
        \\
        \\audio {
        \\    enabled false
        \\    sample_rate 48000
        \\}
    ;

    // Using exported parser module
    var config = try parser.parseKdl(kdl_content, testing.allocator);
    defer config.deinit();

    // Verify all sections parsed correctly
    try testing.expectEqual(ConsoleVariant.nes_ntsc_frontloader, config.console);
    try testing.expectEqual(CpuVariant.rp2a03g, config.cpu.variant);
    try testing.expectEqual(PpuVariant.rp2c02g_ntsc, config.ppu.variant);
    try testing.expectEqual(CicVariant.cic_nes_3193, config.cic.variant);
    try testing.expectEqual(ControllerType.nes, config.controllers.type);
    try testing.expectEqual(VideoBackend.software, config.video.backend);
    try testing.expect(!config.audio.enabled);
}

test "Config: toString roundtrip for all variants" {
    // CPU variants
    try testing.expectEqualStrings("RP2A03E", CpuVariant.rp2a03e.toString());
    try testing.expectEqualStrings("RP2A03G", CpuVariant.rp2a03g.toString());
    try testing.expectEqualStrings("RP2A03H", CpuVariant.rp2a03h.toString());
    try testing.expectEqualStrings("RP2A07", CpuVariant.rp2a07.toString());

    // PPU variants
    try testing.expectEqualStrings("RP2C02G", PpuVariant.rp2c02g_ntsc.toString());
    try testing.expectEqualStrings("RP2C07", PpuVariant.rp2c07_pal.toString());

    // CIC variants
    try testing.expectEqualStrings("CIC-NES-3193", CicVariant.cic_nes_3193.toString());
    try testing.expectEqualStrings("CIC-NES-3195", CicVariant.cic_nes_3195.toString());
    try testing.expectEqualStrings("CIC-NES-3197", CicVariant.cic_nes_3197.toString());

    // Controller types
    try testing.expectEqualStrings("NES", ControllerType.nes.toString());
    try testing.expectEqualStrings("Famicom", ControllerType.famicom.toString());

    // Console variants
    try testing.expectEqualStrings("NES-NTSC-FrontLoader", ConsoleVariant.nes_ntsc_frontloader.toString());
    try testing.expectEqualStrings("NES-NTSC-TopLoader", ConsoleVariant.nes_ntsc_toploader.toString());
    try testing.expectEqualStrings("NES-PAL", ConsoleVariant.nes_pal.toString());
    try testing.expectEqualStrings("Famicom", ConsoleVariant.famicom.toString());
    try testing.expectEqualStrings("Famicom-AV", ConsoleVariant.famicom_av.toString());
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
