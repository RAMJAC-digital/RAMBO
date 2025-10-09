//! PPU and video configuration types
//! Types defining PPU variants, video settings, and rendering configuration

const std = @import("std");

/// PPU variant defines timing characteristics
pub const PpuVariant = enum {
    /// RP2C02G - NTSC USA/Canada
    /// - 341 PPU cycles per scanline
    /// - 262 scanlines per frame
    /// - 60.0988 Hz frame rate
    rp2c02g_ntsc,

    /// RP2C07 - PAL Europe
    /// - 341 PPU cycles per scanline
    /// - 312 scanlines per frame
    /// - 50.0070 Hz frame rate
    rp2c07_pal,

    pub fn fromString(str: []const u8) !PpuVariant {
        if (std.mem.eql(u8, str, "RP2C02G")) return .rp2c02g_ntsc;
        if (std.mem.eql(u8, str, "RP2C07")) return .rp2c07_pal;
        return error.InvalidPpuVariant;
    }

    pub fn toString(self: PpuVariant) []const u8 {
        return switch (self) {
            .rp2c02g_ntsc => "RP2C02G",
            .rp2c07_pal => "RP2C07",
        };
    }
};

/// Video region (NTSC/PAL)
pub const VideoRegion = enum {
    ntsc,
    pal,

    pub fn fromString(str: []const u8) !VideoRegion {
        if (std.mem.eql(u8, str, "NTSC")) return .ntsc;
        if (std.mem.eql(u8, str, "PAL")) return .pal;
        return error.InvalidVideoRegion;
    }
};

/// Emulation accuracy level
pub const AccuracyLevel = enum {
    /// Cycle-accurate: Required for light guns, mid-frame effects
    cycle,
    /// Frame-accurate: Faster, suitable for most games
    frame,

    pub fn fromString(str: []const u8) !AccuracyLevel {
        if (std.mem.eql(u8, str, "cycle")) return .cycle;
        if (std.mem.eql(u8, str, "frame")) return .frame;
        return error.InvalidAccuracyLevel;
    }
};

/// Video backend renderer
pub const VideoBackend = enum {
    software,
    opengl,
    vulkan,

    pub fn fromString(str: []const u8) !VideoBackend {
        if (std.mem.eql(u8, str, "software")) return .software;
        if (std.mem.eql(u8, str, "opengl")) return .opengl;
        if (std.mem.eql(u8, str, "vulkan")) return .vulkan;
        return error.InvalidVideoBackend;
    }
};

/// PPU Configuration
pub const PpuModel = struct {
    variant: PpuVariant = .rp2c02g_ntsc,
    region: VideoRegion = .ntsc,
    accuracy: AccuracyLevel = .cycle,

    /// Get scanlines per frame based on variant
    pub fn scanlinesPerFrame(self: PpuModel) u16 {
        return switch (self.variant) {
            .rp2c02g_ntsc => 262,
            .rp2c07_pal => 312,
        };
    }

    /// Get PPU cycles per scanline (always 341 for 2C02/2C07)
    pub fn cyclesPerScanline(self: PpuModel) u16 {
        _ = self;
        return 341;
    }

    /// Get frame duration in microseconds
    pub fn frameDurationUs(self: PpuModel) u64 {
        return switch (self.variant) {
            .rp2c02g_ntsc => 16_639, // 1/60.0988 Hz = 16,639μs
            .rp2c07_pal => 19_997, // 1/50.0070 Hz = 19,997μs
        };
    }

    /// Get frame rate in Hz
    pub fn frameRate(self: PpuModel) f64 {
        return switch (self.variant) {
            .rp2c02g_ntsc => 60.0988,
            .rp2c07_pal => 50.0070,
        };
    }
};
