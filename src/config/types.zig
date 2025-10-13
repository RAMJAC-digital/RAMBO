//! Configuration Type Definitions
//! All configuration structs and enums in single source of truth file
//!
//! Organized into three sections:
//! 1. Hardware types (Console, CPU, CIC, Controller)
//! 2. PPU/Video types (PPU variants, video settings)
//! 3. Runtime settings (Video, Audio, Input configuration)

const std = @import("std");

// ============================================================================
// Hardware Configuration Types
// ============================================================================

/// Console variant - defines overall hardware configuration
pub const ConsoleVariant = enum {
    /// NES NTSC front-loader (standard North America console)
    /// - RP2A03G CPU, RP2C02G PPU
    /// - CIC-NES-3193 lockout chip
    /// - NES controller ports
    nes_ntsc_frontloader,

    /// NES NTSC top-loader (NES-101)
    /// - RP2A03G CPU, RP2C02G PPU
    /// - No CIC lockout chip
    /// - NES controller ports
    nes_ntsc_toploader,

    /// NES PAL (Europe)
    /// - RP2A07 CPU, RP2C07 PPU
    /// - CIC-NES-3195/3197 lockout chip
    /// - NES controller ports
    nes_pal,

    /// Famicom (Japan)
    /// - RP2A03 CPU, RP2C02 PPU
    /// - CIC variants
    /// - Famicom controller ports (different clocking)
    famicom,

    /// AV Famicom (Japan, later model)
    /// - RP2A03 CPU, RP2C02 PPU
    /// - No CIC lockout chip
    /// - Famicom controller ports
    famicom_av,

    pub fn fromString(str: []const u8) !ConsoleVariant {
        if (std.mem.eql(u8, str, "NES-NTSC-FrontLoader")) return .nes_ntsc_frontloader;
        if (std.mem.eql(u8, str, "NES-NTSC-TopLoader")) return .nes_ntsc_toploader;
        if (std.mem.eql(u8, str, "NES-PAL")) return .nes_pal;
        if (std.mem.eql(u8, str, "Famicom")) return .famicom;
        if (std.mem.eql(u8, str, "Famicom-AV")) return .famicom_av;
        return error.InvalidConsoleVariant;
    }

    pub fn toString(self: ConsoleVariant) []const u8 {
        return switch (self) {
            .nes_ntsc_frontloader => "NES-NTSC-FrontLoader",
            .nes_ntsc_toploader => "NES-NTSC-TopLoader",
            .nes_pal => "NES-PAL",
            .famicom => "Famicom",
            .famicom_av => "Famicom-AV",
        };
    }
};

/// CPU variant - defines 6502 variant behavior
pub const CpuVariant = enum {
    /// RP2A03E - Early NTSC revision
    rp2a03e,

    /// RP2A03G - Standard NTSC revision (AccuracyCoin target)
    /// Most common in NES front-loaders
    rp2a03g,

    /// RP2A03H - Later NTSC revision
    /// Different unstable opcode behavior
    rp2a03h,

    /// RP2A07 - PAL revision
    /// Runs at 1.66 MHz instead of 1.79 MHz
    rp2a07,

    pub fn fromString(str: []const u8) !CpuVariant {
        if (std.mem.eql(u8, str, "RP2A03E")) return .rp2a03e;
        if (std.mem.eql(u8, str, "RP2A03G")) return .rp2a03g;
        if (std.mem.eql(u8, str, "RP2A03H")) return .rp2a03h;
        if (std.mem.eql(u8, str, "RP2A07")) return .rp2a07;
        return error.InvalidCpuVariant;
    }

    pub fn toString(self: CpuVariant) []const u8 {
        return switch (self) {
            .rp2a03e => "RP2A03E",
            .rp2a03g => "RP2A03G",
            .rp2a03h => "RP2A03H",
            .rp2a07 => "RP2A07",
        };
    }
};

// Forward declare VideoRegion here since CpuModel needs it
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

/// CPU Configuration
pub const CpuModel = struct {
    /// CPU variant (RP2A03G/H, RP2A07)
    variant: CpuVariant = .rp2a03g,

    /// Video region (determines clock frequency)
    region: VideoRegion = .ntsc,
};

/// CIC lockout chip variant
pub const CicVariant = enum {
    /// CIC-NES-3193 - NTSC lockout chip
    /// 4-bit Sharp SM590 microcontroller @ 4 MHz
    cic_nes_3193,

    /// CIC-NES-3195 - PAL lockout chip
    cic_nes_3195,

    /// CIC-NES-3197 - PAL lockout chip (alternate)
    cic_nes_3197,

    pub fn fromString(str: []const u8) !CicVariant {
        if (std.mem.eql(u8, str, "CIC-NES-3193")) return .cic_nes_3193;
        if (std.mem.eql(u8, str, "CIC-NES-3195")) return .cic_nes_3195;
        if (std.mem.eql(u8, str, "CIC-NES-3197")) return .cic_nes_3197;
        return error.InvalidCicVariant;
    }

    pub fn toString(self: CicVariant) []const u8 {
        return switch (self) {
            .cic_nes_3193 => "CIC-NES-3193",
            .cic_nes_3195 => "CIC-NES-3195",
            .cic_nes_3197 => "CIC-NES-3197",
        };
    }
};

/// CIC emulation mode
pub const CicEmulation = enum {
    /// Full state machine emulation (accurate behavior)
    state_machine,

    /// Bypass mode (top-loader NES, no CIC)
    bypass,

    /// Disabled (no authentication)
    disabled,

    pub fn fromString(str: []const u8) !CicEmulation {
        if (std.mem.eql(u8, str, "state_machine")) return .state_machine;
        if (std.mem.eql(u8, str, "bypass")) return .bypass;
        if (std.mem.eql(u8, str, "disabled")) return .disabled;
        return error.InvalidCicEmulation;
    }
};

/// CIC Configuration
pub const CicModel = struct {
    /// CIC chip variant
    variant: CicVariant = .cic_nes_3193,

    /// Whether CIC is enabled
    enabled: bool = true,

    /// Emulation mode (state machine, bypass, disabled)
    emulation: CicEmulation = .state_machine,
};

/// Controller port type
pub const ControllerType = enum {
    /// NES controller ports (standard North America/Europe)
    /// Different clocking behavior than Famicom
    nes,

    /// Famicom controller ports (Japan)
    /// Hardwired controllers with different clocking
    famicom,

    pub fn fromString(str: []const u8) !ControllerType {
        if (std.mem.eql(u8, str, "NES")) return .nes;
        if (std.mem.eql(u8, str, "Famicom")) return .famicom;
        return error.InvalidControllerType;
    }

    pub fn toString(self: ControllerType) []const u8 {
        return switch (self) {
            .nes => "NES",
            .famicom => "Famicom",
        };
    }
};

/// Controller Configuration
pub const ControllerModel = struct {
    /// Controller port type (NES vs Famicom)
    type: ControllerType = .nes,
};

// ============================================================================
// PPU and Video Configuration Types
// ============================================================================

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

// ============================================================================
// Runtime Settings Types
// ============================================================================

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
