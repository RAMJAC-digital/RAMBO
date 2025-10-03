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

/// PPU timing constants
pub const PpuTiming = @import("ppu/timing.zig");

/// Frame timing for V-sync
pub const FrameTimer = @import("timing/FrameTimer.zig");

/// Emulation state machine (RT loop)
pub const EmulationState = @import("emulation/State.zig");

/// Async I/O Architecture
pub const IoArchitecture = @import("io/Architecture.zig");

/// Runtime system with RT/OS thread separation
pub const Runtime = @import("io/Runtime.zig");

// ============================================================================
// Re-export commonly used types for convenience
// ============================================================================

/// CPU type (from Cpu module)
pub const CpuType = Cpu.Cpu;

/// Bus type (from Bus module)
pub const BusType = Bus.Bus;

/// CPU Status Flags
pub const StatusFlags = Cpu.StatusFlags;

/// CPU State enum
pub const CpuState = Cpu.CpuState;

/// Addressing modes
pub const AddressingMode = Cpu.AddressingMode;

/// Cartridge type (from Cartridge module)
pub const CartridgeType = Cartridge.Cartridge;

/// Nametable mirroring mode
pub const MirroringType = Cartridge.Mirroring;

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
    _ = IoArchitecture;
    _ = Runtime;
}
