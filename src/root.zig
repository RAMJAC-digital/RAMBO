//! RAMBO - Cycle-Accurate NES Emulator Library
//!
//! This library provides hardware-accurate NES emulation components.
//! All components communicate through the Bus for proper cycle-accurate behavior.

const std = @import("std");

// ============================================================================
// Core Components
// ============================================================================

/// 6502 CPU emulation
pub const Cpu = @import("cpu/Cpu.zig");

/// Cartridge/ROM loader
pub const Cartridge = @import("cartridge/Cartridge.zig");

/// Configuration system
pub const Config = @import("config/Config.zig");

/// Stateless configuration parser
pub const ConfigParser = @import("config/parser.zig");

/// PPU (Picture Processing Unit)
pub const Ppu = @import("ppu/Ppu.zig");

/// PPU timing constants
pub const PpuTiming = @import("ppu/timing.zig");

/// APU (Audio Processing Unit)
pub const Apu = @import("apu/Apu.zig");

/// Frame timing for V-sync
pub const FrameTimer = @import("timing/FrameTimer.zig");

/// Emulation state machine (RT loop)
pub const EmulationState = @import("emulation/State.zig");
/// Emulator runtime helpers (PPU orchestration)
pub const EmulationPpu = @import("emulation/Ppu.zig");
/// Shared test harness utilities
pub const TestHarness = @import("test/Harness.zig");

/// State snapshot system (save/load emulation state)
pub const Snapshot = @import("snapshot/Snapshot.zig");

/// Debugger system (breakpoints, watchpoints, stepping, history)
pub const Debugger = @import("debugger/Debugger.zig");

/// Mailbox system for thread communication (video, emulation, config)
pub const Mailboxes = @import("mailboxes/Mailboxes.zig");

/// Benchmarking infrastructure for performance measurement
pub const Benchmark = @import("benchmark/Benchmark.zig");

/// iNES ROM format parser (stateless, separate from cartridge emulation)
pub const iNES = @import("cartridge/ines/mod.zig");

/// NES controller button state (8 buttons packed into 1 byte)
pub const ButtonState = @import("input/ButtonState.zig").ButtonState;

/// Keyboard mapper (Wayland events → NES buttons)
pub const KeyboardMapper = @import("input/KeyboardMapper.zig").KeyboardMapper;

// ============================================================================
// Threading System
// ============================================================================

/// Emulation thread (timer-driven, RT-safe)
pub const EmulationThread = @import("threads/EmulationThread.zig");

/// Render thread (Wayland + Vulkan stub)
pub const RenderThread = @import("threads/RenderThread.zig");

// ============================================================================
// Re-export commonly used types for convenience
// ============================================================================

/// CPU type (from Cpu module)
pub const CpuType = Cpu.State.CpuState;

/// CPU Status Flags
pub const StatusFlags = Cpu.StatusFlags;

/// CPU State enum
pub const ExecutionState = Cpu.ExecutionState;

/// Addressing modes
pub const AddressingMode = Cpu.AddressingMode;

/// Cartridge types (from Cartridge module)
/// - CartridgeType: NROM cartridge (Mapper 0) - for backward compatibility
/// - AnyCartridge: Tagged union of all supported mappers (new unified system)
/// - MapperRegistry: Mapper metadata and dispatch
pub const CartridgeType = Cartridge.NromCart;

/// Mapper registry and dispatch system
pub const MapperRegistry = @import("cartridge/mappers/registry.zig");

/// Tagged union of all supported cartridges (unified mapper system)
pub const AnyCartridge = MapperRegistry.AnyCartridge;

/// Mapper ID enum
pub const MapperId = MapperRegistry.MapperId;

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
    _ = Cpu;
    _ = Cartridge;
    _ = MapperRegistry;
    _ = Config;
    _ = Ppu;
    _ = PpuTiming;
    _ = Apu;
    _ = FrameTimer;
    _ = EmulationState;
    _ = Snapshot;
    _ = Debugger;
    _ = Mailboxes;
    _ = iNES;
}
