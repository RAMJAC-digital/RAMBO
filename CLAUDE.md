# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**RAMBO** is a cycle-accurate NES emulator written in Zig 0.15.1, targeting hardware-accurate 6502/2C02 emulation with cycle-level precision validated against the AccuracyCoin test suite.

**Current Status:** ~99% complete, 939/947 tests passing, AccuracyCoin PASSING ✅

## Build Commands

```bash
# Build executable
zig build

# Run tests
zig build test              # All tests (939/947 passing)
zig build test-unit         # Unit tests only (fast)
zig build test-integration  # Integration tests only
zig build bench-release     # Release-optimized benchmarks

# Run emulator
zig build run

# Run with debugging
zig build run -- --inspect path/to/rom.nes
```

## Architecture

### State/Logic Separation Pattern

All core components use **hybrid State/Logic separation** for modularity, testability, and RT-safety:

**State modules** (`State.zig`):
- Pure data structures with optional non-owning pointers
- Zero hidden state - fully serializable for save states
- Convenience methods that delegate to Logic functions

**Logic modules** (`Logic.zig`):
- Pure functions operating on State pointers
- No global state - deterministic execution
- All side effects explicit through parameters

```zig
// Example: src/cpu/State.zig
pub const CpuState = struct {
    a: u8, x: u8, y: u8, sp: u8, pc: u16,
    p: StatusRegister,

    // Convenience delegation
    pub inline fn tick(self: *CpuState, bus: *BusState) void {
        Logic.tick(self, bus);
    }
};

// Example: src/cpu/Logic.zig
pub fn tick(cpu: *CpuState, bus: *BusState) void {
    // Pure function - all state passed explicitly
}
```

### Comptime Generics (Zero-Cost Polymorphism)

All polymorphism uses comptime duck typing - zero runtime overhead:

```zig
pub fn Cartridge(comptime MapperType: type) type {
    return struct {
        mapper: MapperType,

        // Direct delegation - no VTable, fully inlined
        pub fn cpuRead(self: *const Self, address: u16) u8 {
            return self.mapper.cpuRead(self, address);
        }
    };
}

// Usage - compile-time type instantiation
const NromCart = Cartridge(Mapper0);  // Zero runtime overhead
```

### Thread Architecture

3-thread mailbox pattern with RT-safe emulation:

1. **Main Thread:** Coordinator (minimal work)
2. **Emulation Thread:** Cycle-accurate CPU/PPU emulation (RT-safe, zero heap allocations)
3. **Render Thread:** Wayland window + Vulkan rendering (60 FPS)

**Communication via lock-free mailboxes:**
- `FrameMailbox` - Emulation → Render (double-buffered RGBA frame data)
- `ControllerInputMailbox` - Main → Emulation (NES button state)
- `DebugCommandMailbox` / `DebugEventMailbox` - Bidirectional debugging
- `XdgInputEventMailbox` / `XdgWindowEventMailbox` - Wayland events → Main

## Critical Hardware Behaviors

### 1. Read-Modify-Write (RMW) Dummy Write

ALL RMW instructions (ASL, LSR, ROL, ROR, INC, DEC) write the original value back before writing the modified value:

```zig
// INC $10: 5 cycles
// Cycle 3: Read value from $10
// Cycle 4: Write ORIGINAL value back to $10  <-- CRITICAL!
// Cycle 5: Write INCREMENTED value to $10
```

This is visible to memory-mapped I/O and tested by AccuracyCoin.

### 2. Dummy Reads on Page Crossing

Indexed addressing crossing page boundaries performs a dummy read at the wrong address:

```zig
// LDA $10FF,X with X=$02
// Cycle 4: Dummy read at $1001 (wrong - high byte not incremented yet)
// Cycle 5: Read from $1101 (correct)
```

### 3. Open Bus Behavior

Every bus read/write updates the data bus. Reading unmapped memory returns the last bus value (tracked in `BusState.open_bus` with decay timer).

### 4. Zero Page Wrapping

Zero page indexed addressing wraps within page 0:

```zig
// LDA $FF,X with X=$02 -> reads from $01, NOT $101
address = @as(u16, (base +% index))  // Wraps at byte boundary
```

### 5. NMI Edge Detection

NMI triggers on **falling edge** (high → low transition). IRQ is **level-triggered**.

### 6. PPU Warm-Up Period

PPU ignores writes to $2000/$2001/$2005/$2006 for first 29,658 CPU cycles after power-on (implemented in `PpuState.warmup_complete` flag).

## Component Structure

```
src/
├── cpu/              # 6502 CPU emulation
│   ├── State.zig         # CPU registers and microstep state
│   ├── Logic.zig         # Pure CPU functions
│   ├── opcodes/          # All 256 opcodes (14 modules)
│   ├── decode.zig        # Opcode decoding tables
│   └── dispatch.zig      # Opcode → executor mapping
├── ppu/              # 2C02 PPU emulation
│   ├── State.zig         # PPU registers, VRAM, OAM, rendering state
│   ├── Logic.zig         # PPU operations (background + sprite rendering)
│   ├── palette.zig       # NES color palette (64 colors)
│   └── timing.zig        # PPU timing constants (341 dots × 262 scanlines)
├── apu/              # Audio Processing Unit (86% complete)
│   ├── State.zig         # APU channels, frame counter
│   ├── Logic.zig         # APU operations
│   ├── Dmc.zig           # DMC channel
│   ├── Envelope.zig      # Generic envelope component
│   └── Sweep.zig         # Generic sweep component
├── cartridge/        # Cartridge system
│   ├── Cartridge.zig     # Generic Cartridge(MapperType) factory
│   ├── ines/             # iNES ROM parser (5 modules)
│   └── mappers/          # Mapper implementations
│       ├── Mapper0.zig   # NROM (complete)
│       └── registry.zig  # AnyCartridge tagged union
├── emulation/        # Emulation coordination
│   ├── State.zig         # EmulationState (CPU/PPU/APU/Bus integration)
│   ├── Ppu.zig           # PPU orchestration helpers
│   └── MasterClock.zig   # Cycle counting and synchronization
├── video/            # Wayland + Vulkan rendering (100% complete)
│   ├── WaylandState.zig  # Wayland window state
│   ├── WaylandLogic.zig  # XDG shell protocol logic
│   ├── VulkanState.zig   # Vulkan rendering state
│   ├── VulkanLogic.zig   # Vulkan rendering pipeline
│   ├── VulkanBindings.zig# Vulkan C bindings
│   └── shaders/          # GLSL shaders (texture.vert, texture.frag)
├── input/            # Input system (100% complete)
│   ├── ButtonState.zig   # NES controller state (8 buttons)
│   └── KeyboardMapper.zig# Wayland keyboard → NES buttons
├── debugger/         # Debugging system (100% complete)
│   └── Debugger.zig      # Breakpoints, watchpoints, stepping
├── mailboxes/        # Thread communication (lock-free)
│   ├── Mailboxes.zig     # Mailbox collection
│   ├── FrameMailbox.zig  # Double-buffered frame data
│   ├── ControllerInputMailbox.zig
│   ├── DebugCommandMailbox.zig
│   ├── DebugEventMailbox.zig
│   └── SpscRingBuffer.zig# Generic ring buffer
├── snapshot/         # Save state system
├── threads/          # Threading system
│   ├── EmulationThread.zig# RT-safe emulation loop
│   └── RenderThread.zig  # Wayland + Vulkan rendering
├── config/           # Configuration management
├── timing/           # Frame timing utilities
├── benchmark/        # Performance benchmarking
├── memory/           # Memory adapters
├── test/             # Shared test utilities
├── root.zig          # Library root (public API)
└── main.zig          # Entry point
```

## Development Workflow

### Before Implementing Features

1. Read relevant tests in `tests/` to understand requirements
2. Review component State/Logic modules
3. Check `docs/` for architecture documentation

### Testing Requirements

```bash
# Before committing
zig build test  # Must pass (939/947 expected, 7 skipped, 1 timing-sensitive failure)

# Verify no regressions
git diff --stat
```

### Commit Guidelines

```bash
# Commit at milestones (every 2-4 hours of work)
git add <files>
git commit -m "type(scope): description"

# Example commit types:
# feat(cpu): Add NMI interrupt handling
# fix(ppu): Correct sprite 0 hit timing
# refactor(bus): Extract open bus logic
# test(integration): Add commercial ROM tests
# docs(architecture): Update State/Logic pattern
```

## Known Issues

### CPU Timing Deviation (Medium Priority)

**Issue:** Absolute,X/Y reads without page crossing have +1 cycle deviation
- **Hardware:** 4 cycles (dummy read IS the actual read)
- **Implementation:** 5 cycles (separate addressing + execute states)
- **Impact:** Functionally correct, timing slightly off
- **Priority:** MEDIUM (defer to post-playability)

### Threading Tests (Low Priority)

1 threading test fails in some environments (timing-sensitive), 7 tests skipped. This is a test infrastructure issue, not a functional problem.

## Test Coverage

**Total:** 939/947 tests passing (99.2%)

### By Component

| Component | Tests | Status |
|-----------|-------|--------|
| CPU | ~280 | ✅ All passing |
| PPU | ~90 | ✅ All passing |
| APU | 135 | ✅ All passing |
| Debugger | ~66 | ✅ All passing |
| Integration | 94 | ✅ All passing |
| Mailboxes | 57 | ✅ All passing |
| Input System | 40 | ✅ All passing |
| Cartridge | ~48 | ✅ All passing |
| Threading | 14 | ⚠️ 13/14 passing |
| Config | ~30 | ✅ All passing |
| iNES | 26 | ✅ All passing |
| Snapshot | ~23 | ✅ All passing |
| Bus & Memory | ~20 | ✅ All passing |
| Comptime | 8 | ✅ All passing |

## Companion ROM Tooling

The `compiler/` directory contains a Python workspace for building reference ROMs:

```bash
# Setup (once per machine)
uv run compiler toolchain

# Build AccuracyCoin test ROM
uv run compiler build-accuracycoin

# Microsoft BASIC port (in progress)
uv run compiler analyze-basic
uv run compiler preprocess-basic
```

See `compiler/README.md` for details.

## Dependencies

### External Libraries (build.zig.zon)

- **libxev:** Event loop library (timer-driven emulation)
- **zig-wayland:** Wayland protocol bindings (window management)
- **zli:** CLI argument parsing

### System Requirements

**Development:**
- Zig 0.15.1
- Linux with Wayland compositor
- Vulkan SDK (for shader compilation: `glslc`)

**Runtime:**
- Vulkan 1.0+ compatible GPU
- Wayland compositor (GNOME, KDE Plasma, Sway, etc.)
- System libraries: `wayland-client`, `vulkan`

## Resources

### Documentation

- **[Documentation Hub](docs/README.md)** - Start here
- **[Current Status](docs/CURRENT-STATUS.md)** - Implementation status
- **[Architecture Details](docs/code-review/01-architecture.md)** - Deep dive into patterns

### NES Hardware

- [NESDev Wiki](https://www.nesdev.org/wiki/) - Comprehensive NES documentation
- [6502 Reference](http://www.6502.org/) - CPU architecture
- [PPU Rendering](https://www.nesdev.org/wiki/PPU_rendering) - PPU details

### Zig Resources

- [Zig Language Reference](https://ziglang.org/documentation/master/)
- [Zig Standard Library](https://ziglang.org/documentation/master/std/)

---

**Key Principle:** Hardware accuracy first. Cycle-accurate execution over performance optimization.

**Version:** 0.2.0-alpha
**Last Updated:** 2025-10-08
**Status:** 939/947 tests passing, AccuracyCoin PASSING ✅
