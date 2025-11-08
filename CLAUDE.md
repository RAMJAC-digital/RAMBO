
@sessions/CLAUDE.sessions.md

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**RAMBO** is a cycle-accurate NES emulator written in Zig 0.15.1, targeting hardware-accurate 6502/2C02 emulation with cycle-level precision.

**Current Status:** 1162/1184 tests passing (98.1%) - See [docs/STATUS.md](docs/STATUS.md) for details

## Build Commands

```bash
# Build executable
zig build
zig build -Dwith_movy=true  # Build with terminal backend support

# Run tests
zig build test              # All tests (see docs/STATUS.md for current results)
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

# Backend and frame dumping
./zig-out/bin/RAMBO path/to/rom.nes --backend=terminal  # Terminal rendering (requires -Dwith_movy=true)
./zig-out/bin/RAMBO path/to/rom.nes --backend=wayland  # Vulkan/Wayland rendering (default)
./zig-out/bin/RAMBO path/to/rom.nes --dump-frame 120   # Dump frame 120 to frame_0120.ppm
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
- `build/wasm.zig` WASM target for use in `rambo_web`.

### PPU Self-Containment (Module Boundary Principle - COMPLETED 2025-11-07)

The PPU has been refactored to be a self-contained module that owns all its internal state:

**Ownership Boundaries:**
- **PPU owns:** Timing (scanline/cycle), rendering state, VBlank state, NMI line, framebuffer, OAM, VRAM, registers
- **PPU outputs:** nmi_line signal (to CPU), framebuffer data (to render system)
- **EmulationState reads:** ppu.nmi_line, ppu.framebuffer, ppu.frame_complete

**Implementation Status (Completed):**
- [x] VBlank state moved to ppu/VBlank.zig (type renamed from VBlankLedger)
- [x] nmi_line field added to PpuState (PPU computes internally)
- [x] framebuffer field added to PpuState (PPU owns output buffer)
- [x] PPU Logic.tick() manages VBlank internally (scanline 241 dot 1 set, scanline -1 dot 1 clear)
- [x] VBlank set/clear logic moved to PPU Logic
- [x] NMI line computation moved to PPU (vblank_flag AND ctrl.nmi_enable)
- [x] EmulationState.stepPpuCycle() deleted (no longer extracting PPU internals)
- [x] EmulationState.applyVBlankTimestamps() deleted (PPU manages internally)
- [x] Signal wiring in EmulationState.tick(): ppu.nmi_line → cpu.nmi_line

**Current Interface:**
```zig
// PPU Logic.tick() - fully self-contained
pub fn tick(state: *PpuState, cart: ?*AnyCartridge) void {
    // PPU reads own timing internally (scanline/cycle fields)
    // PPU manages own VBlank state (state.vblank field)
    // PPU computes nmi_line = vblank_flag AND ctrl.nmi_enable
    // PPU renders into state.framebuffer
}

// EmulationState.tick() - simple signal wiring
PpuLogic.tick(&self.ppu, cart_ptr);
self.cpu.nmi_line = self.ppu.nmi_line;  // Wire PPU NMI signal to CPU
```

**Benefits Achieved:**
- Eliminated backwards coupling (EmulationState no longer extracts PPU internals)
- VBlank flag management co-located with NMI enable bit (ppu.ctrl.nmi_enable)
- Reduced EmulationState tick() complexity (deleted 2 orchestration functions)
- Enables independent PPU testing
- Matches hardware architecture (PPU is autonomous chip)

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
3. **Render Thread:** Backend-agnostic rendering (60 FPS, comptime backend selection)

**Rendering Backends** (comptime polymorphism, zero VTable overhead):
- **VulkanBackend:** Wayland + Vulkan rendering (default, production use)
- **MovyBackend:** Terminal rendering via movy (requires `-Dwith_movy=true`, for development/debugging)

**Communication via lock-free mailboxes:**
- `FrameMailbox` - Emulation → Render (double-buffered RGBA frame data)
- `ControllerInputMailbox` - Main → Emulation (NES button state)
- `DebugCommandMailbox` / `DebugEventMailbox` - Bidirectional debugging
- `XdgInputEventMailbox` / `XdgWindowEventMailbox` - Input events → Main

## Module Reorganization (2025-11-07)

### Files Moved (Architectural Cleanup)

**CPU Module Restructuring:**
- `src/emulation/cpu/execution.zig` → `src/cpu/Execution.zig` (moved from emulation to cpu module)
- `src/emulation/cpu/microsteps.zig` → `src/cpu/Microsteps.zig` (moved from emulation to cpu module)
- Created `src/cpu/MicrostepTable.zig` - Table-driven dispatch system (522 lines)

**PPU VBlank Ownership Transfer:**
- `src/emulation/VBlankLedger.zig` → `src/ppu/VBlank.zig` (moved from emulation to ppu module)
- Type renamed: `VBlankLedger` → `VBlank` (reflects new ownership)
- Module documentation updated: "The PPU owns and manages this state internally"

**Rationale:**
- CPU execution logic belongs in cpu module, not emulation/cpu subdirectory
- VBlank state is PPU hardware behavior, should live in ppu module
- Table-driven dispatch eliminates opcode duplication and nested switches
- Improves module cohesion and separation of concerns

### Interface Changes (VBlank Ownership)

**Deleted from EmulationState:**
- `vblank_ledger` field (moved to PpuState.vblank)
- `stepPpuCycle()` function (PPU now self-contained)
- `applyVBlankTimestamps()` function (PPU manages VBlank internally)

**Added to PpuState:**
- `vblank: VBlank` field (PPU owns VBlank state)
- `nmi_line: bool` field (PPU output signal computed from vblank_flag AND ctrl.nmi_enable)
- `framebuffer: ?[]u32` field (PPU owns rendering output)

**Signal Wiring:**
- EmulationState.tick() wires `ppu.nmi_line → cpu.nmi_line` (simple signal passing)

### Import Path Changes (Completed)
- All files importing from `emulation/VBlankLedger` updated to `ppu/VBlank`
- Files affected: emulation/State.zig, ppu/Logic.zig, bus/handlers/PpuHandler.zig, snapshot/state.zig, ppu/logic/registers.zig
- All references to `vblank_ledger` updated to `ppu.vblank`

### CPU Table-Driven Execution (Refactor Completed 2025-11-07)

The CPU execution system was refactored from nested switch statements to a table-driven dispatch pattern, reducing Execution.zig from 533 lines to 281 lines (47% reduction).

**Architecture:**

1. **MicrostepTable.zig** - Comptime-built dispatch table (522 lines)
   - MICROSTEP_TABLE[256] - Maps every opcode to its microstep sequence
   - MicrostepSequence struct: steps array, max_cycles, operand_source
   - 39 predefined sequences (13 addressing modes × 3 variants: read/write/rmw)
   - 8 special sequences (JSR, RTS, RTI, BRK, PHA, PHP, PLA, PLP)
   - callMicrostep() - Runtime dispatcher for 39 microstep function indices

2. **Execution.zig** - State machine executor (281 lines, down from 533)
   - 4-state machine: interrupt_sequence, fetch_opcode, fetch_operand_low, execute
   - Table lookup replaces 217 lines of nested switches
   - Early completion pattern for variable-cycle instructions (branches, indexed modes)
   - Single source of truth for addressing mode timing

3. **Microsteps.zig** - Atomic microstep functions (417 lines)
   - 39 pure functions implementing 6502 hardware microsteps
   - Each returns bool (true = early completion, false = continue)
   - Used as building blocks by table-driven dispatcher

**Key Pattern - Early Completion:**
```zig
// Microstep returns true to signal early completion
pub fn branchFetchOffset(state: anytype) bool {
    state.cpu.operand_low = state.busRead(state.cpu.pc);
    state.cpu.pc +%= 1;
    const should_branch = /* check condition */;
    if (!should_branch) return true;  // Branch not taken - complete (2 cycles)
    return false;  // Branch taken - continue (3-4 cycles)
}
```

**Benefits:**
- Single source of truth for opcode timing (eliminate 4+ duplicate opcode lists)
- Adding new opcode = 1 table entry (not 3+ switch case edits)
- Declarative specification (what microsteps to run, not how to dispatch)
- Hardware-accurate variable cycle counts (branches, indexed modes with page crossing)
- Maintainable (change timing = update one table entry)

**Implementation Notes:**
- Fixed INDEXED_INDIRECT vs INDIRECT_INDEXED microstep aliasing
  - (ind,X): fetchZpBase → addXToBase → fetchIndirectLow/High
  - (ind),Y: fetchZpPointer → fetchPointerLow/High → addYCheckPage
- Operand extraction uses OperandSource enum (immediate_pc, temp_value, operand_low, etc.)
- Table built at comptime (zero runtime overhead for dispatch structure)

## Development Workflow

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
- **movy:** Terminal rendering library (optional, requires `-Dwith_movy=true`)

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
