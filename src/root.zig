//! RAMBO - Cycle-Accurate NES Emulator Library
//!
//! This library provides hardware-accurate NES emulation components.
//! All components communicate through the Bus for proper cycle-accurate behavior.

const std = @import("std");

// ============================================================================
// Core Components
// ============================================================================

/// Memory bus - central communication hub for all components
pub const Bus = @import("bus/Bus.zig");

/// 6502 CPU emulation
pub const Cpu = @import("cpu/Cpu.zig");

/// Cartridge/ROM loader
pub const Cartridge = @import("cartridge/Cartridge.zig");

/// Configuration system
pub const Config = @import("config/Config.zig");

/// PPU (Picture Processing Unit)
pub const Ppu = @import("ppu/Ppu.zig");

/// PPU Logic (for testing)
pub const PpuLogic = @import("ppu/Logic.zig");

/// PPU timing constants
pub const PpuTiming = @import("ppu/timing.zig");

/// Frame timing for V-sync
pub const FrameTimer = @import("timing/FrameTimer.zig");

/// Emulation state machine (RT loop)
pub const EmulationState = @import("emulation/State.zig");

/// State snapshot system (save/load emulation state)
pub const Snapshot = @import("snapshot/Snapshot.zig");

/// Debugger system (breakpoints, watchpoints, stepping, history)
pub const Debugger = @import("debugger/Debugger.zig");

// ============================================================================
// Re-export commonly used types for convenience
// ============================================================================

/// CPU type (from Cpu module)
pub const CpuType = Cpu.State.CpuState;

/// Bus type (from Bus module)
pub const BusType = Bus.State.BusState;

/// CPU Status Flags
pub const StatusFlags = Cpu.StatusFlags;

/// CPU State enum
pub const ExecutionState = Cpu.ExecutionState;

/// Addressing modes
pub const AddressingMode = Cpu.AddressingMode;

/// Cartridge type (from Cartridge module)
/// Currently uses NROM (Mapper 0) - generic mapper support via Cartridge(MapperType)
pub const CartridgeType = Cartridge.NromCart;

/// Nametable mirroring mode
pub const MirroringType = Cartridge.Mirroring;

/// PPU type (from Ppu module)
pub const PpuType = Ppu.State.PpuState;

// ============================================================================
// Test reference (for zig build test)
// ============================================================================

test {
    // Reference all declarations to run their tests
    std.testing.refAllDecls(@This());

    // Import and run tests from core modules
    _ = Bus;
    _ = Cpu;
    _ = Cartridge;
    _ = Config;
    _ = Ppu;
    _ = PpuTiming;
    _ = FrameTimer;
    _ = EmulationState;
    _ = Snapshot;
    _ = Debugger;
}
