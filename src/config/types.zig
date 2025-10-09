//! Type definitions re-export facade
//! Single import point for all config types

// Hardware types
pub const ConsoleVariant = @import("types/hardware.zig").ConsoleVariant;
pub const CpuVariant = @import("types/hardware.zig").CpuVariant;
pub const CpuModel = @import("types/hardware.zig").CpuModel;
pub const CicVariant = @import("types/hardware.zig").CicVariant;
pub const CicEmulation = @import("types/hardware.zig").CicEmulation;
pub const CicModel = @import("types/hardware.zig").CicModel;
pub const ControllerType = @import("types/hardware.zig").ControllerType;
pub const ControllerModel = @import("types/hardware.zig").ControllerModel;

// PPU/Video types
pub const PpuVariant = @import("types/ppu.zig").PpuVariant;
pub const VideoRegion = @import("types/ppu.zig").VideoRegion;
pub const AccuracyLevel = @import("types/ppu.zig").AccuracyLevel;
pub const VideoBackend = @import("types/ppu.zig").VideoBackend;
pub const PpuModel = @import("types/ppu.zig").PpuModel;

// Settings types
pub const VideoConfig = @import("types/settings.zig").VideoConfig;
pub const AudioConfig = @import("types/settings.zig").AudioConfig;
pub const InputConfig = @import("types/settings.zig").InputConfig;
