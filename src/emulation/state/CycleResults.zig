//! PPU, CPU, and APU cycle result structures
//! Used by EmulationState.tick() to communicate component events

/// Result of a single PPU cycle
pub const PpuCycleResult = struct {
    frame_complete: bool = false,
    rendering_enabled: bool = false,
    nmi_signal: bool = false,
    vblank_clear: bool = false,
    a12_rising: bool = false,
};

/// Result of a single CPU cycle
pub const CpuCycleResult = struct {
    mapper_irq: bool = false,
};

/// Result of a single APU cycle
pub const ApuCycleResult = struct {
    frame_irq: bool = false,
    dmc_irq: bool = false,
};
