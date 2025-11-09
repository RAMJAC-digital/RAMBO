
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

### WebAssembly Build Target

RAMBO includes a WebAssembly build target for browser execution via Phoenix LiveView front-end.

**Build:**
```bash
zig build wasm  # Outputs zig-out/bin/rambo.wasm
```

**Implementation Details:**
- **Target:** `wasm32-freestanding` (no OS, pure WebAssembly)
- **Entry Point:** `src/wasm.zig` - C-compatible API for browser integration
- **Export Symbols:** 21 functions defined in `build/wasm.zig` EXPORT_SYMBOLS array
  - Lifecycle: `rambo_init`, `rambo_shutdown`, `rambo_reset`
  - Emulation: `rambo_step_frame`, `rambo_set_controller_state`
  - Framebuffer: `rambo_framebuffer_ptr`, `rambo_framebuffer_size`, `rambo_frame_dimensions`
  - Memory: `rambo_alloc`, `rambo_free`, `rambo_heap_size_bytes`
- **Memory Model:** Imports memory from JavaScript (256MB max)
  - JavaScript provides `WebAssembly.Memory` with proper configuration
  - Avoids Zig linker `__heap_base` placement issues
- **Build Configuration:**
  - `entry = .disabled` - No `_start` function (library mode)
  - `export_table = true` - Export function table for JavaScript access
  - `import_memory = true` - Use JavaScript-provided memory

**Phoenix LiveView Front-End (`rambo_web/`):**
- **Framework:** Elixir/Phoenix 1.7.10 + LiveView 0.20.1
- **Setup:** `cd rambo_web && mix setup` (installs Hex deps + JS toolchain)
- **Run:** `mix phx.server` (http://localhost:5000)
- **Features:** ROM upload, real-time frame streaming, browser-based emulation
- **Integration:** JavaScript layer calls exported WASM functions, streams RGBA frames to HTML5 canvas
- **Asset Pipeline:** Tailwind CSS + esbuild for static assets

**Deployment:**
```bash
zig build wasm -Doptimize=ReleaseSmall  # Optimized WASM
cd rambo_web
mix assets.deploy                       # Compile + minify assets
# Deploy Phoenix app (see rambo_web/README.md)
```

### Black Box Module Pattern (Subsystem Self-Containment)

The emulator follows a "black box" module pattern where subsystems own their state and output signals, eliminating backwards coupling where EmulationState orchestrates internals.

**Pattern Established:** PPU Self-Containment (COMPLETED 2025-11-07), DMA Consolidation (COMPLETED 2025-11-08), Controller Module (COMPLETED 2025-11-09), Bus Module Extraction (COMPLETED 2025-11-09), PpuHandler Refactoring (COMPLETED 2025-11-09)

#### PPU Black Box (COMPLETED 2025-11-07)

**Ownership Boundaries:**
- **PPU owns:** Timing (scanline/cycle), rendering state, VBlank state, NMI line, framebuffer, OAM, VRAM, registers
- **PPU outputs:** nmi_line signal (to CPU), framebuffer data (to render system)
- **EmulationState reads:** ppu.nmi_line, ppu.framebuffer, ppu.frame_complete

**Implementation:**
- [x] VBlank state moved to ppu/VBlank.zig (type renamed from VBlankLedger)
- [x] nmi_line field added to PpuState (PPU computes internally)
- [x] framebuffer field added to PpuState (PPU owns output buffer)
- [x] PPU Logic.tick() manages VBlank internally (scanline 241 dot 1 set, scanline -1 dot 1 clear)
- [x] NMI line computation moved to PPU (vblank_flag AND ctrl.nmi_enable)
- [x] EmulationState orchestration functions deleted (stepPpuCycle, applyVBlankTimestamps)

**Interface:**
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

#### DMA Black Box (COMPLETED 2025-11-08)

**Ownership Boundaries:**
- **DMA owns:** OAM DMA state, DMC DMA state, interaction tracking, RDY line output signal
- **DMA outputs:** rdy_line signal (to CPU, halts execution during DMA)
- **EmulationState reads:** dma.rdy_line, dma.active

**Implementation:**
- [x] Consolidated DMA state in src/dma/State.zig (OamDma, DmcDma, interaction ledger)
- [x] Created src/dma/Logic.zig for DMA execution logic
- [x] Created src/dma/Dma.zig for DMA coordination
- [x] DMA module follows PPU black box pattern (owns state, outputs signals)

#### Controller Black Box (COMPLETED 2025-11-09)

**Ownership Boundaries:**
- **Controller owns:** Shift register state, strobe mode, button data
- **Controller outputs:** Serial data bits (read via bus handlers)
- **EmulationState reads:** None (bus handlers access controller state directly)

**Implementation:**
- [x] Consolidated controller logic in src/controller/ (State/Logic separation)
- [x] Created src/controller/State.zig - 4021 shift register state
- [x] Created src/controller/Logic.zig - Shift register operations (latch, read, write)
- [x] Created src/controller/ButtonState.zig - Button data representation (moved from src/input/)
- [x] Added lifecycle functions: power_on(), reset()
- [x] EmulationState delegates initialization via ControllerLogic functions

#### Bus Black Box (COMPLETED 2025-11-09)

**Ownership Boundaries:**
- **Bus owns:** RAM, open bus tracking, handler instances (7 zero-size stateless handlers)
- **Bus operations:** read(), write(), read16(), dummyRead() routing via BusLogic
- **EmulationState delegates:** All memory access via inline BusLogic functions

**Implementation:**
- [x] Extracted bus module in src/bus/ (State/Logic/Inspection separation)
- [x] Created src/bus/State.zig - RAM, open bus, handler instances (all data)
- [x] Created src/bus/Logic.zig - Routing operations (read, write, read16, dummyRead)
- [x] Created src/bus/Inspection.zig - Debugger-safe peek operations
- [x] Moved handlers from src/emulation/bus/handlers/ to src/bus/handlers/
- [x] Handlers struct owned by bus/State.zig (not EmulationState)
- [x] EmulationState delegates via inline functions (busRead, busWrite, etc.)

**Interface:**
```zig
// Bus Logic - routing operations
pub fn read(bus: *BusState, state: anytype, address: u16) u8 {
    // Dispatch to handlers, update open bus
}

// EmulationState - simple delegation
pub inline fn busRead(self: *EmulationState, address: u16) u8 {
    return BusLogic.read(&self.bus, self, address);
}
```

#### PpuHandler Black Box (COMPLETED 2025-11-09)

**Ownership Boundaries:**
- **PpuHandler owns:** Nothing - zero-size stateless routing struct
- **PpuHandler delegates to:** PpuLogic.readRegister(), PpuLogic.writeRegister()
- **PpuLogic owns:** All $2002/$2000 side effects (VBlank clear, NMI computation, address latch reset)

**Implementation:**
- [x] Moved all $2002 read side effects from PpuHandler to PpuLogic.readRegister()
- [x] Moved all $2000 write NMI computation from PpuHandler to PpuLogic.writeRegister()
- [x] Changed PpuLogic.readRegister() signature: removed vblank_ledger, scanline, dot parameters
- [x] Added master_cycles parameter to PpuLogic.readRegister() (PPU owns timing internally)
- [x] PpuHandler reduced from 314 lines to ~100 lines (68% reduction)
- [x] Handler now pure routing - no cross-module state extraction

**Interface:**
```zig
// PpuLogic - self-contained register operations
pub fn readRegister(
    state: *PpuState,
    cart: ?*AnyCartridge,
    address: u16,
    master_cycles: u64,
) PpuReadResult {
    // All side effects managed internally
    // - VBlank flag clear on $2002 read
    // - Sprite overflow clear on $2002 read
    // - Address latch reset on $2002 read
    // - Open bus update
    return .{ .value = result, .read_2002 = is_2002 };
}

// PpuHandler - pure routing
pub fn read(_: *const PpuHandler, state: anytype, address: u16) u8 {
    const result = PpuLogic.readRegister(&state.ppu, state.cart, address, state.clock.master_cycles);
    if (result.read_2002) {
        state.cpu.nmi_line = false;  // Signal wiring only
    }
    return result.value;
}
```

**Benefits Achieved (All Subsystems):**
- Eliminated backwards coupling (EmulationState no longer extracts subsystem internals)
- State management co-located with signal generation (vblank+nmi_enable, dma_state+rdy_line)
- Reduced EmulationState tick() complexity (deleted orchestration functions)
- Bus routing logic consolidated in dedicated module (not embedded in EmulationState)
- Handlers ownership transferred to bus module (clearer separation of concerns)
- PpuHandler refactored to pure routing - all side effects moved to PpuLogic
- Zero legacy code - complete extraction from emulation/
- Enables independent subsystem testing
- Matches hardware architecture (autonomous chips communicating via signals)

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

## Module Reorganization (2025-11-07 to 2025-11-08)

### Files Moved (Architectural Cleanup)

**CPU Module Restructuring:**
- `src/emulation/cpu/execution.zig` → `src/cpu/Execution.zig` (moved from emulation to cpu module)
- `src/emulation/cpu/microsteps.zig` → `src/cpu/Microsteps.zig` (moved from emulation to cpu module)
- Created `src/cpu/MicrostepTable.zig` - Table-driven dispatch system (522 lines)

**PPU VBlank Ownership Transfer:**
- `src/emulation/VBlankLedger.zig` → `src/ppu/VBlank.zig` (moved from emulation to ppu module)
- Type renamed: `VBlankLedger` → `VBlank` (reflects new ownership)
- Module documentation updated: "The PPU owns and manages this state internally"

**DMA Subsystem Consolidation (2025-11-08):**
- Created `src/dma/State.zig` - Consolidated DMA state (OAM DMA, DMC DMA, interaction tracking)
- Created `src/dma/Logic.zig` - DMA execution logic
- Created `src/dma/Dma.zig` - DMA coordination module
- Follows PPU black box pattern: DMA owns state, outputs RDY line signal to CPU

**Controller Module Consolidation (2025-11-09):**
- Created `src/controller/State.zig` - NES 4021 shift register state
- Created `src/controller/Logic.zig` - Controller operations (latch, shift, read/write)
- Created `src/controller/Controller.zig` - Controller module facade
- `src/input/ButtonState.zig` → `src/controller/ButtonState.zig` (moved to controller module)
- Follows State/Logic separation pattern used by CPU/PPU/APU/DMA

**Bus Module Extraction (2025-11-09):**
- Created `src/bus/State.zig` - Bus state (RAM, open bus tracking, handler instances)
- Created `src/bus/Logic.zig` - Bus routing operations (read, write, read16, dummyRead)
- Created `src/bus/Inspection.zig` - Debugger-safe bus inspection (peek without side effects)
- Created `src/bus/Bus.zig` - Bus module facade
- Moved handlers: `src/emulation/bus/handlers/` → `src/bus/handlers/`
- Follows State/Logic separation pattern used by CPU/PPU/APU/DMA/Controller

**Rationale:**
- CPU execution logic belongs in cpu module, not emulation/cpu subdirectory
- VBlank state is PPU hardware behavior, should live in ppu module
- DMA logic deserves dedicated module (not scattered across EmulationState)
- Controller logic belongs with controller state (ButtonState moved from input/)
- Bus routing logic deserves dedicated module (not embedded in EmulationState)
- Handlers ownership moved to bus module (not EmulationState)
- Table-driven dispatch eliminates opcode duplication and nested switches
- Improves module cohesion and separation of concerns

### Interface Changes (Subsystem Cleanup Sessions 5-7)

**VBlank Ownership (Session 5):**

Deleted from EmulationState:
- `vblank_ledger` field (moved to PpuState.vblank)
- `stepPpuCycle()` function (PPU now self-contained)
- `applyVBlankTimestamps()` function (PPU manages VBlank internally)

Added to PpuState:
- `vblank: VBlank` field (PPU owns VBlank state)
- `nmi_line: bool` field (PPU output signal computed from vblank_flag AND ctrl.nmi_enable)
- `framebuffer: ?[]u32` field (PPU owns rendering output)

Signal wiring:
- EmulationState.tick() wires `ppu.nmi_line → cpu.nmi_line` (simple signal passing)

**CPU Lifecycle Functions (Session 7):**

Added to CpuLogic:
- `power_on(state: *CpuState, reset_vector: u16)` - Hardware-accurate power-on sequence
- `reset(state: *CpuState, reset_vector: u16)` - Hardware-accurate reset sequence
- EmulationState now delegates instead of directly manipulating CPU registers

**PPU Lifecycle Functions (Session 7):**

Added to PpuLogic:
- `power_on(state: *PpuState)` - Hardware-accurate PPU power-on state
- `reset(state: *PpuState)` - Hardware-accurate PPU reset sequence
- EmulationState delegates instead of directly setting PPU fields

**APU Signal Interface (Session 7):**

Changed in ApuLogic:
- `tickFrameCounter(state: *ApuState) void` - Changed from `bool` return to `void`
- Communicates frame IRQ via `state.frame_irq_flag` field only (matches PPU nmi_line pattern)
- Eliminates dual return/mutation interface

**Controller Lifecycle Functions (Session 9):**

Added to ControllerLogic:
- `power_on(state: *ControllerState)` - Hardware-accurate power-on state
- `reset(state: *ControllerState)` - Hardware-accurate reset sequence
- EmulationState delegates instead of directly manipulating controller fields

**PPU Register Interface Simplification (Session 10):**

Changed in PpuLogic:
- `readRegister(state, cart, address, master_cycles)` - Signature simplified from 6 parameters to 4
- Removed: `vblank_ledger`, `scanline`, `dot` parameters (PPU owns this internally)
- All $2002 read side effects moved from PpuHandler to PpuLogic.readRegister()
  - VBlank flag clear, sprite overflow clear, open bus update, address latch reset
- All $2000 write NMI computation moved from PpuHandler to PpuLogic.writeRegister()
  - NMI line = vblank_flag AND nmi_enable (level-based signal computation)
- Result: PpuHandler reduced from 314 lines to ~100 lines (68% reduction), now pure routing
- Pattern: Handlers delegate to Logic modules, no cross-module state extraction

### Import Path Changes (Completed)
- All files importing from `emulation/VBlankLedger` updated to `ppu/VBlank`
- Files affected: emulation/State.zig, ppu/Logic.zig, bus/handlers/PpuHandler.zig, snapshot/state.zig, ppu/logic/registers.zig
- All references to `vblank_ledger` updated to `ppu.vblank`
- All files importing ButtonState from `input/ButtonState` updated to `controller/ButtonState`
- Files affected: input/KeyboardMapper.zig, mailboxes/ControllerInputMailbox.zig, various test files

### CPU Table-Driven Execution (Refactor Completed 2025-11-07)

The CPU execution system was refactored from nested switch statements to a table-driven dispatch pattern, reducing Execution.zig from 533 lines to 279 lines (48% reduction).

**Architecture:**

1. **MicrostepTable.zig** - Comptime-built dispatch table (522 lines)
   - MICROSTEP_TABLE[256] - Maps every opcode to its microstep sequence
   - MicrostepSequence struct: steps array, max_cycles, operand_source
   - 39 predefined sequences (13 addressing modes × 3 variants: read/write/rmw)
   - 8 special sequences (JSR, RTS, RTI, BRK, PHA, PHP, PLA, PLP)
   - callMicrostep() - Runtime dispatcher for 39 microstep function indices

2. **Execution.zig** - State machine executor (279 lines, down from 533, 48% reduction)
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
