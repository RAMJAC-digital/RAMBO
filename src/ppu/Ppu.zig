//! PPU Module
//!
//! This module implements the complete PPU following the State/Logic pattern.
//! All core components in RAMBO use this separation:
//! - State: Pure data structures (State.zig)
//! - Logic: Pure functions operating on state (Logic.zig)
//! - Module: Clean re-exports (this file)
//!
//! Features:
//! - Cycle-accurate rendering pipeline
//! - Background rendering (nametables + pattern tables)
//! - Open bus behavior on all registers
//! - VBlank/NMI generation
//! - Proper VBlank/sprite flag timing
//! - Register mirroring through $3FFF

// Re-export State and Logic modules
pub const State = @import("State.zig");
pub const Logic = @import("Logic.zig");

// Re-export commonly used types for convenience
pub const PpuCtrl = State.PpuCtrl;
pub const PpuMask = State.PpuMask;
pub const PpuStatus = State.PpuStatus;
pub const OpenBus = State.OpenBus;
pub const InternalRegisters = State.InternalRegisters;
pub const BackgroundState = State.BackgroundState;
pub const PpuState = State.State;

// Backward compatibility alias
// Allows existing code to use `Ppu` instead of `State.State`
pub const Ppu = State.State;

/// Backward compatibility: Initialize a new PPU state
/// Equivalent to State.State.init() or Logic.init()
pub inline fn init() State.State {
    return State.State.init();
}
