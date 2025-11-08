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

/// CPU microstep functions (for testing)
pub const CpuMicrosteps = @import("cpu/Microsteps.zig");

/// Cartridge/ROM loader
pub const Cartridge = @import("cartridge/Cartridge.zig");

/// Cartridge file loader (dynamic and static)
pub const CartridgeLoader = @import("cartridge/loader.zig");

/// Configuration system
pub const Config = @import("config/Config.zig");

// ConfigParser removed - use Config.parser instead if needed

/// PPU (Picture Processing Unit)
pub const Ppu = @import("ppu/Ppu.zig");

/// PPU timing constants
pub const PpuTiming = @import("ppu/timing.zig");

/// PPU palette module
pub const PpuPalette = @import("ppu/palette.zig");

/// APU (Audio Processing Unit)
pub const Apu = @import("apu/Apu.zig");

/// Frame timing for V-sync
pub const FrameTimer = @import("timing/FrameTimer.zig");

/// Emulation state machine (RT loop)
pub const EmulationState = @import("emulation/State.zig");
// EmulationPpu removed - internal to EmulationState only

/// Master clock (timing system)
pub const MasterClock = @import("emulation/MasterClock.zig").MasterClock;

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

// iNES export removed - parser is internal to Cartridge module
// Types available via Cartridge.Mirroring, Cartridge.InesHeader

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
// Rendering Backends
// ============================================================================

/// Vulkan/Wayland rendering backend
pub const VulkanBackend = @import("video/backends/VulkanBackend.zig").VulkanBackend;

/// Movy terminal rendering backend (conditional on build option)
pub const MovyBackend = @import("video/backends/MovyBackend.zig").MovyBackend;

// ============================================================================
// Re-export commonly used types for convenience
// ============================================================================

/// CPU type (from Cpu module)
pub const CpuType = Cpu.State.CpuState;

// StatusFlags, ExecutionState, AddressingMode removed
// Use Cpu.StatusFlags, Cpu.ExecutionState, Cpu.AddressingMode directly

/// NROM Cartridge Type (Mapper 0 Only) - Backward Compatibility Alias
///
/// ⚠️  WARNING: This is NOT a generic cartridge type despite the name!
/// This alias specifically refers to Mapper 0 (NROM) only and will NOT work
/// with other mappers (MMC1, MMC3, etc.).
///
/// For new code, prefer one of these alternatives:
/// - `Cartridge.NromCart` - Direct NROM usage (explicit, clear intent)
/// - `AnyCartridge` - Polymorphic cartridge (supports all mappers via tagged union)
///
/// This alias exists purely for backward compatibility with existing test code.
///
/// Example usage:
/// ```zig
/// // Load NROM cartridge
/// const nrom = try CartridgeType.load(allocator, "game.nes");
/// defer nrom.deinit();
///
/// // Wrap in AnyCartridge for polymorphic use
/// const any_cart = AnyCartridge{ .nrom = nrom };
/// emu_state.loadCartridge(any_cart);
/// ```
///
/// Migration guidance:
/// - Test code: Can continue using `CartridgeType` (backward compatible)
/// - Production code: Use `AnyCartridge` for flexibility
/// - NROM-specific code: Use `Cartridge.NromCart` for clarity
pub const CartridgeType = Cartridge.NromCart;

/// Mapper registry and dispatch system
pub const MapperRegistry = @import("cartridge/mappers/registry.zig");

/// Tagged union of all supported cartridges (unified mapper system)
pub const AnyCartridge = MapperRegistry.AnyCartridge;

/// Mapper ID enum
pub const MapperId = MapperRegistry.MapperId;

// MirroringType removed - use Cartridge.Mirroring directly

/// PPU type (from Ppu module)
pub const PpuType = Ppu.State.PpuState;

// ============================================================================
// Test reference (for zig build test)
// ============================================================================

comptime {
    // Import and run tests from core modules
    // NOTE: We manually reference modules instead of using refAllDecls(@This())
    // to avoid compiling backends (which have C deps) during test compilation
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
    // iNES test reference removed (export removed)
}
