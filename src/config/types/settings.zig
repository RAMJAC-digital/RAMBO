//! Runtime settings types
//! Types defining non-hardware settings (video, audio, input)

const VideoBackend = @import("ppu.zig").VideoBackend;

/// Video Configuration
pub const VideoConfig = struct {
    backend: VideoBackend = .software,
    vsync: bool = true,
    scale: u8 = 3, // 1x = 256x240, 3x = 768x720
};

/// Audio Configuration (placeholder)
pub const AudioConfig = struct {
    enabled: bool = false,
    sample_rate: u32 = 48000,
};

/// Input Configuration (placeholder)
pub const InputConfig = struct {
    light_gun_enabled: bool = false,
};
