
@sessions/CLAUDE.sessions.md

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**RAMBO** is a cycle-accurate NES emulator written in Zig 0.15.1, targeting hardware-accurate 6502/2C02 emulation with cycle-level precision.

**Current Status:** 1004/1026 tests passing (97.9%) - See [docs/STATUS.md](docs/STATUS.md) for details

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

### Terminal Backend Usage

**Build with movy support:**
```bash
zig build -Dwith_movy=true
```

**Run in terminal mode:**
```bash
./zig-out/bin/RAMBO path/to/rom.nes --backend=terminal
```

**Features:**
- SSH-friendly development (no GUI required)
- Half-block ANSI rendering (2 pixels per terminal cell)
- TV-accurate overscan cropping (8px all edges, 240×224 visible area)
- Automatic terminal centering and size detection
- Overlay menu system (ESC for menu, ENTER to select, Y/N confirmation)

**Input handling:**
- Direct ButtonState updates (bypasses XDG layer)
- Auto-release mechanism: Buttons auto-release after 3 frames (compensates for terminal press-only limitation)
- Standard keyboard mapping (Arrow keys=D-pad, Z=B, X=A, RShift=Select, Enter=Start)

**Known limitations:**
- Requires TTY (not suitable for CI/automated testing)
- Frame rate may vary based on terminal performance
- Uses terminal raw mode + alternate screen buffer
- Can interfere with stdout/stderr logging during operation

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
3. **Render Thread:** Backend-agnostic rendering (60 FPS, comptime backend selection)

**Rendering Backends** (comptime polymorphism, zero VTable overhead):
- **VulkanBackend:** Wayland + Vulkan rendering (default, production use)
- **MovyBackend:** Terminal rendering via movy (requires `-Dwith_movy=true`, for development/debugging)

**Communication via lock-free mailboxes:**
- `FrameMailbox` - Emulation → Render (double-buffered RGBA frame data)
- `ControllerInputMailbox` - Main → Emulation (NES button state)
- `DebugCommandMailbox` / `DebugEventMailbox` - Bidirectional debugging
- `XdgInputEventMailbox` / `XdgWindowEventMailbox` - Input events → Main

## Critical Hardware Behaviors

### 1. CPU/PPU Sub-Cycle Execution Order 🔒

**LOCKED BEHAVIOR** - Verified correct per nesdev.org hardware specification.

Within a single PPU cycle, the NES hardware executes operations in this order:
1. **CPU Read Operations** (if CPU is active this cycle)
2. **CPU Write Operations** (if CPU is active this cycle)
3. **PPU Events** (VBlank flag set, sprite evaluation, etc.)
4. **End of cycle**

**Critical Race Condition:** When CPU reads $2002 (PPUSTATUS) at exactly the same PPU cycle that VBlank is set (scanline 241, dot 1), the CPU read executes **BEFORE** the PPU sets the VBlank flag:
- CPU reads $2002 → sees VBlank bit = 0 (flag not set yet)
- PPU sets VBlank flag → flag becomes 1
- Result: CPU missed seeing the VBlank flag (same-cycle race)

**Implementation:** `src/emulation/State.zig:tick()` lines 617-699
- CPU executes via `stepCpuCycle()` BEFORE `applyPpuCycleResult()`
- PPU flag updates happen AFTER CPU memory operations
- VBlankLedger timestamps set after CPU has executed

**Hardware Citation:** https://www.nesdev.org/wiki/PPU_frame_timing

**Do not modify this execution order without strong hardware justification.**

### 2. Read-Modify-Write (RMW) Dummy Write

ALL RMW instructions (ASL, LSR, ROL, ROR, INC, DEC) write the original value back before writing the modified value:

```zig
// INC $10: 5 cycles
// Cycle 3: Read value from $10
// Cycle 4: Write ORIGINAL value back to $10  <-- CRITICAL!
// Cycle 5: Write INCREMENTED value to $10
```

This is visible to memory-mapped I/O and tested by AccuracyCoin.

### 3. Dummy Reads on Page Crossing

Indexed addressing crossing page boundaries performs a dummy read at the wrong address:

```zig
// LDA $10FF,X with X=$02
// Cycle 4: Dummy read at $1001 (wrong - high byte not incremented yet)
// Cycle 5: Read from $1101 (correct)
```

### 4. Open Bus Behavior

Every bus read/write updates the data bus. Reading unmapped memory returns the last bus value (tracked in `BusState.open_bus` with decay timer).

### 5. Zero Page Wrapping

Zero page indexed addressing wraps within page 0:

```zig
// LDA $FF,X with X=$02 -> reads from $01, NOT $101
address = @as(u16, (base +% index))  // Wraps at byte boundary
```

### 6. NMI Edge Detection

NMI triggers on **falling edge** (high → low transition). IRQ is **level-triggered**.

### 7. PPU Warm-Up Period

PPU ignores writes to $2000/$2001/$2005/$2006 for first 29,658 CPU cycles after power-on (implemented in `PpuState.warmup_complete` flag).

### 8. PPU Sprite Vertical Flip Wrapping 🔒

**LOCKED BEHAVIOR** - Verified correct per nesdev.org pre-render scanline specification.

Sprite pattern address calculations use wrapping subtraction for vertical flip to match hardware behavior:

```zig
// 8x8 sprites: Vertical flip calculation wraps naturally
const flipped_row = if (vertical_flip) 7 -% row else row;

// 8x16 sprites: Vertical flip across all 16 rows
const flipped_row = if (vertical_flip) 15 -% row else row;
```

**Critical Edge Case:** On pre-render scanline (-1), sprite fetches use stale secondary OAM from scanline 239. When `next_scanline = 0` and `sprite_y = 200`, the row calculation wraps:
- `row = 0 -% 200 = 56` (out of bounds for 8x8 sprite)
- Hardware doesn't crash - it uses the wrapped value to fetch arbitrary pattern data
- Without wrapping subtraction (`--%`), vertical flip would cause undefined behavior

**Implementation:** `src/ppu/logic/sprites.zig` - `getSpritePatternAddress()` and `getSprite16PatternAddress()`

**Hardware Citation:** https://www.nesdev.org/wiki/PPU_rendering (pre-render scanline sprite fetching)

**Do not change this wrapping behavior - it matches hardware edge case handling.**

### 9. DMC/OAM DMA Time-Sharing 🔒

**LOCKED BEHAVIOR** - Verified correct per nesdev.org and Mesen2 reference implementation.

When DMC DMA interrupts OAM DMA, hardware implements time-sharing where OAM continues executing during DMC idle cycles:

**DMC DMA cycle breakdown** (4 cycles total, countdown from stall_cycles_remaining):
- **Cycle 4 (halt):** OAM continues executing ✓ (counts as DMC halt cycle)
- **Cycle 3 (dummy):** OAM continues executing ✓ (counts as DMC dummy cycle)
- **Cycle 2 (alignment):** OAM continues executing ✓ (counts as DMC alignment cycle)
- **Cycle 1 (read):** OAM PAUSES ✗ (DMC reads memory, OAM must wait)

**Net overhead:** 4 DMC cycles - 3 OAM advancement cycles + 1 post-DMC alignment = ~2 cycles total (can vary 1-3 cycles based on timing alignment)

**Implementation:** `src/emulation/dma/logic.zig:41-42`
- OAM stall detection: `dmc_is_stalling_oam = rdy_low and stall_cycles_remaining == 1`
- OAM only pauses during DMC read cycle (stall == 1), not during halt/dummy/alignment
- After DMC completes, OAM consumes one alignment cycle before resuming normal operation

**Hardware Citations:**
- Primary: https://www.nesdev.org/wiki/DMA#DMC_DMA_during_OAM_DMA
- Reference Implementation: Mesen2 NesCpu.cpp:385 "Sprite DMA cycles count as halt/dummy cycles for the DMC"

**Test Coverage:** `tests/integration/dmc_oam_conflict_test.zig` - All 14 DMC/OAM conflict tests passing

**Do not modify this time-sharing behavior - it matches hardware specification exactly.**

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
│   ├── logic/            # PPU logic modules
│   │   ├── background.zig # Background tile fetching
│   │   ├── sprites.zig    # Sprite evaluation and rendering
│   │   ├── memory.zig     # VRAM access
│   │   ├── scrolling.zig  # Scroll register manipulation
│   │   └── registers.zig  # CPU register I/O
│   ├── palette.zig       # NES color palette (64 colors)
│   └── timing.zig        # PPU timing constants (341 dots × 262 scanlines)
├── apu/              # Audio Processing Unit (emulation logic 100%, audio output TODO)
│   ├── State.zig         # APU channels, frame counter
│   ├── Logic.zig         # APU operations
│   ├── Dmc.zig           # DMC channel
│   ├── Envelope.zig      # Generic envelope component
│   └── Sweep.zig         # Generic envelope component
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
├── video/            # Rendering system (100% complete)
│   ├── Backend.zig       # Backend interface definition
│   ├── backends/         # Backend implementations
│   │   ├── VulkanBackend.zig  # Wayland + Vulkan rendering (default)
│   │   └── MovyBackend.zig    # Terminal rendering (movy, optional)
│   ├── WaylandState.zig  # Wayland window state
│   ├── WaylandLogic.zig  # XDG shell protocol logic
│   ├── VulkanState.zig   # Vulkan rendering state
│   ├── VulkanLogic.zig   # Vulkan rendering pipeline
│   ├── VulkanBindings.zig# Vulkan C bindings
│   └── shaders/          # GLSL shaders (texture.vert, texture.frag)
├── input/            # Input system (100% complete)
│   ├── ButtonState.zig   # NES controller state (8 buttons)
│   └── KeyboardMapper.zig# Keyboard → NES buttons
├── debug/            # Debug utilities
│   └── frame_dump.zig    # PPM frame dumping (--dump-frame)
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
│   └── RenderThread.zig  # Backend-agnostic rendering (comptime dispatch)
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

**Current Status:** 1023/1041 tests passing (98.3%), 6 skipped, 12 failing
**Last Verified:** 2025-10-20
**Full Details:** See [docs/STATUS.md](docs/STATUS.md) and `docs/CURRENT-ISSUES.md` for complete issue tracking

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

**Reference:** See `docs/sessions/2025-10-15-phase2-development-plan.md` for detailed investigation plan

**Note:** DMC/OAM DMA time-sharing is now hardware-accurate (verified 2025-11-02)

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

**Total:** 1004/1026 tests passing (97.9%), 6 skipped, 16 failing
**Current Focus:** VBlank/PPU/NMI timing bugs (TDD - failing tests identify bugs)

**See [docs/STATUS.md](docs/STATUS.md) for complete test breakdown** and `docs/CURRENT-ISSUES.md` for game compatibility tracking.

**Recent Fix (2025-11-02):** DMC/OAM DMA time-sharing now hardware-accurate (+2 tests passing)

### By Component

| Component | Tests | Status |
|-----------|-------|--------|
| CPU | ~280 | ✅ All passing |
| PPU | ~93 | ✅ All passing |
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

**Version:** 0.2.0-alpha
**Last Updated:** 2025-11-02
**Status:** 1004/1026 tests passing (97.9%) - See [docs/STATUS.md](docs/STATUS.md)
**Documentation:** Up to date - Current issues documented in `docs/STATUS.md` and `docs/CURRENT-ISSUES.md`
**Current Focus:** VBlank/PPU/NMI timing bugs (TDD approach - failing tests identify bugs to fix)
**Recent Fix:** DMC/OAM DMA time-sharing now hardware-accurate (2025-11-02)
