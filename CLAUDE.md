# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**RAMBO** is a cycle-accurate NES emulator written in Zig 0.15.1, targeting hardware-accurate 6502/2C02 emulation with cycle-level precision validated against the AccuracyCoin test suite.

**Current Status:** 990/995 tests passing (99.5%), AccuracyCoin PASSING ✅

**Commercial ROMs Status:**
- ✅ **Fully Working:** Castlevania, Mega Man, Kid Icarus, Battletoads, SMB2
- ⚠️ **Partial (Rendering Issues):**
  - SMB3: Checkered floor appears briefly then disappears (not Y position issue)
  - Kirby's Adventure: Dialog box doesn't render (not Y position issue)
- ❌ **Not Working:** TMNT series, Paperboy (grey screen - game-specific compatibility issue)

## Build Commands

```bash
# Build executable
zig build

# Run tests
zig build test              # All tests (expected 990/995 passing, 5 skipped)
zig build test-unit         # Unit tests only (fast subset)
zig build test-integration  # Integration tests only
zig build bench-release     # Release-optimized benchmarks

# Adapt this pattern to run singular tests, this is simply an example.
zig test --dep RAMBO  -Mroot=tests/integration/mmc3_visual_regression_test.zig -MRAMBO=src/root.zig -ODebug 

# Short form (via build system)
zig build test-integration

# Target specific tests by filter, in this ppu, and return a summary of the tests outcomes based on criteria.
zig build test --summary { all | failures | success } -- ppu

# Helper/tooling suites
zig build test-tooling      # Diagnostic executables

# Run emulator
zig build run

# Run with debugging
./zig-out/bin/RAMBO path/to/rom.nes --inspect
./zig-out/bin/RAMBO path/to/rom.nes --break-at 0x8000 --inspect
./zig-out/bin/RAMBO path/to/rom.nes --watch 0x2001 --inspect
```

### Build System Layout

- `build.zig` is the thin entry point that wires together sub-builders.
- `build/options.zig` defines feature flags exposed as build options.
- `build/dependencies.zig` resolves external packages (libxev, zli).
- `build/wayland.zig` runs the zig-wayland scanner and exposes generated bindings.
- `build/graphics.zig` compiles GLSL shaders and installs SPIR-V artifacts.
- `build/modules.zig` creates the primary RAMBO module and executable wiring.
- `build/tests.zig` owns the metadata table for every test (names, areas, memberships).
- `build/diagnostics.zig` registers developer tools such as the SMB diagnostic runner.

## Architecture

### Visual Architecture Documentation

**GraphViz diagrams** provide comprehensive visual maps of the entire codebase. Use these to understand system structure before diving into code:

**System Overview:**
- `docs/dot/architecture.dot` - Complete 3-thread architecture (60 nodes)
- `docs/dot/emulation-coordination.dot` - RT loop coordination (80 nodes)

**Core Modules:**
- `docs/dot/cpu-module-structure.dot` - 6502 complete subsystem (50 nodes)
- `docs/dot/ppu-module-structure.dot` - 2C02 rendering pipeline (60 nodes)
- `docs/dot/apu-module-structure.dot` - APU 5-channel audio (60 nodes)

**Systems:**
- `docs/dot/cartridge-mailbox-systems.dot` - Comptime generics + lock-free communication (70 nodes)

**Investigations:**
- `docs/dot/cpu-execution-flow.dot` - Cycle-accurate CPU state machine
- `docs/dot/ppu-timing.dot` - NTSC frame timing (262 scanlines × 341 dots)
- `docs/dot/investigation-workflow.dot` - Example investigation methodology

**How to use:**
1. Start with `architecture.dot` for high-level overview
2. Dive into specific module diagrams (`cpu-module-structure.dot`, etc.)
3. Reference during code navigation to understand data flow and ownership
4. Generate images: `cd docs/dot && dot -Tpng <file>.dot -o <file>.png`

All diagrams include:
- Complete type definitions and function signatures
- Data flow (color-coded: Blue=main, Red=writes, Green=reads)
- Side effects and ownership annotations
- Critical timing behaviors
- Hardware accuracy notes

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
│   ├── opcodes/          # All 256 opcodes (13 modules)
│   ├── decode.zig        # Opcode decoding tables
│   └── dispatch.zig      # Opcode → executor mapping
├── ppu/              # 2C02 PPU emulation
│   ├── State.zig         # PPU registers, VRAM, OAM, rendering state
│   ├── Logic.zig         # PPU operations (background + sprite rendering)
│   ├── palette.zig       # NES color palette (64 colors)
│   └── timing.zig        # PPU timing constants (341 dots × 262 scanlines)
├── apu/              # Audio Processing Unit (emulation logic 100%, audio output TODO)
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
zig build test  # Must pass (expected 990/995; see docs/CURRENT-ISSUES.md for known failures)

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

## Known Issues & Current Investigation

**Current Status:** 990/995 tests passing (99.5%), 5 skipped
**Last Verified:** 2025-10-15 (Post-Phase 1 hardware accuracy fixes)
**Full Details:** See `docs/CURRENT-ISSUES.md` for complete issue tracking

### Recent Major Fixes (2025-10-14 to 2025-10-15)

**✅ NMI Line Management** - Fixed critical bug preventing commercial ROMs from receiving interrupts
- Impact: Castlevania, Mega Man, Kid Icarus now fully working
- Commit: 1985d74 + double-trigger suppression

**✅ Progressive Sprite Evaluation** - Implemented hardware-accurate cycle-by-cycle sprite evaluation
- Impact: SMB1 title screen now animates correctly (+3 tests passing)
- Replaced instant evaluation with progressive evaluation across dots 65-256

**✅ RAM Initialization** - Fixed power-on RAM state (was all zeros, now pseudo-random)
- Impact: Commercial ROMs now take correct boot paths (~+54 tests)

**✅ Sprite Y Position Pipeline Delay** - Implemented 1-scanline pipeline delay
- Impact: Hardware-accurate per nesdev.org (+17 new tests), but didn't fix game rendering issues

**✅ Greyscale Mode** - Implemented PPUMASK bit 0 greyscale support
- Impact: Missing feature now implemented (+13 tests)

### Active Investigation: Phase 2 - Mid-Frame Register Changes

**Current Hypothesis:** Remaining rendering issues (SMB3 floor, Kirby dialog) are caused by **mid-frame register update propagation**, not sprite timing.

**Evidence:**
- Both games use split-screen effects requiring mid-scanline PPUCTRL/PPUMASK changes
- SMB1 green line suggests fine X scroll or first tile fetch issue
- All issues involve dynamic content (splits, scrolling), not static scenes

**Investigation Focus:**
1. **Fine X Scroll Edge Case** - SMB1 green line (8 pixels, left side)
2. **PPUCTRL Mid-Scanline Changes** - Pattern/nametable base switching during rendering
3. **PPUMASK 3-4 Dot Delay** - Rendering enable/disable propagation timing
4. **DMC/OAM DMA Interaction** - DMC interrupting OAM with byte duplication

**Reference:** See `docs/sessions/2025-10-15-phase2-development-plan.md` for detailed investigation plan

### Remaining Game-Specific Issues

**SMB1** - Sprite palette bug (left side of `?` boxes green instead of yellow)
**SMB3** - Checkered floor disappears after few frames
**Kirby's Adventure** - Dialog box doesn't render at all
**TMNT/Paperboy** - Grey screen (game-specific compatibility, likely mapper issue)

### Known Limitations (Low Priority)

**CPU Timing Deviation** - Absolute,X/Y without page crossing: +1 cycle deviation
- Functionally correct, AccuracyCoin passes despite deviation
- Priority: Deferred to post-playability

**Threading Tests** - 5 tests skipped (timing-sensitive)
- Not a functional problem - mailboxes work correctly in production
- Test infrastructure issue, not emulation issue

## Test Coverage

**Total:** 990/995 tests passing (99.5%), 5 skipped
**AccuracyCoin:** ✅ PASSING (baseline CPU validation)
**Current Focus:** Phase 2 investigation - Mid-frame register change timing

See `docs/CURRENT-ISSUES.md` for detailed test status and game compatibility tracking.

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
| Threading | 14 | ⚠️ 9/14 passing, 5 skipped |
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

- **[Documentation Hub](docs/README.md)** - Start here for all documentation
- **[Architecture Patterns](ARCHITECTURE.md)** - Core patterns reference (State/Logic, VBlank, DMA)
- **[Current Issues](docs/CURRENT-ISSUES.md)** - Known issues and game compatibility
- **[Implementation Guides](docs/implementation/)** - Detailed implementation documentation

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
**Last Updated:** 2025-10-15
**Status:** 990/995 tests passing (99.5%), AccuracyCoin PASSING ✅
**Documentation:** Up to date - Current issues documented in `docs/CURRENT-ISSUES.md`
**Current Focus:** Phase 2 investigation - Mid-frame register change timing (see `docs/sessions/2025-10-15-phase2-development-plan.md`)
