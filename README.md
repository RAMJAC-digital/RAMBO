# RAMBO NES Emulator

Cycle-accurate NES emulator written in Zig 0.15.1.

**Current Status:** 1162/1184 tests passing (98.1%) - See [docs/STATUS.md](docs/STATUS.md) for details

**Commercial ROMs:**
- ✅ Castlevania, Mega Man, Kid Icarus, Battletoads, SMB2
- ⚠️ SMB1: Title animates correctly, sprite palette bug (`?` boxes)
- ⚠️ SMB3: Missing checkered floor on title screen
- ⚠️ Bomberman: Menu visible, title screen black
- ❌ TMNT series: Grey screen (not rendering)

---

## Recent Fixes (2025-11-04)

### Bus Handler Architecture Migration

- ✅ **Stateless Handler Delegation:** CPU memory bus refactored from monolithic routing to 7 independent handlers
  - **Impact:** Zero compilation errors, +158 tests (1004/1026 → 1162/1184), improved code organization
  - **Implementation:** 7 zero-size handlers replacing 300+ line monolithic routing
    - RamHandler ($0000-$1FFF) - Internal RAM with 4x mirroring
    - PpuHandler ($2000-$3FFF) - PPU registers, VBlank/NMI coordination
    - ApuHandler ($4000-$4015) - APU channels
    - OamDmaHandler ($4014) - OAM DMA trigger
    - ControllerHandler ($4016-$4017) - Controller ports + APU frame counter
    - CartridgeHandler ($4020-$FFFF) - PRG ROM/RAM mapper delegation
    - OpenBusHandler (unmapped) - Hardware open bus behavior
  - **Handler Pattern:** Zero-size stateless handlers with read/write/peek interface
  - **Test Coverage:** All 44 handler unit tests passing (6-9 tests per handler)
  - **Debugger Support:** Side-effect-free `peek()` for debugger inspection
  - **Hardware Mirroring:** Handler boundaries match NES chip architecture (6502, 2C02, APU)
  - **Files:** `src/emulation/bus/handlers/*.zig`, `src/emulation/State.zig`
  - **Documentation:** `docs/implementation/bus-handler-architecture.md`
  - See `sessions/tasks/h-fix-oam-nmi-accuracy.md` for complete refactoring details

## Previous Fixes (2025-11-03)

### VBlank/NMI Timing Restructuring and IRQ Masking

- ✅ **VBlank Prevention Mechanism:** CPU execution moved BEFORE VBlank timestamp application
  - **Impact:** VBlank prevention now works correctly - CPU sets `prevent_vbl_set_cycle`, then VBlank checks flag before setting
  - **Implementation:** `src/emulation/State.zig:tick()` lines 651-774 - CPU executes, then VBlank timestamps applied
  - **Interrupt Sampling:** Moved to AFTER VBlank timestamps finalized (ensures correct NMI line state)
  - **Hardware Citation:** Matches Mesen2 NesPpu.cpp:1340-1344 (prevention flag check before VBlank set)
  - See `sessions/tasks/h-fix-oam-nmi-accuracy.md` for complete details

- ✅ **IRQ Masking During NMI:** Fixed infinite interrupt loop bug
  - **Issue:** IRQ restoration was overriding NMI during interrupt sequence cycles 0-6
  - **Fix:** `if (irq_pending_prev and pending_interrupt != .nmi)` preserves NMI priority
  - **Impact:** AccuracyCoin menu now accessible (first time) - indicates stable interrupt handling
  - **Hardware Citation:** Per nesdev.org/wiki/NMI, NMI has priority over IRQ

## Previous Fixes (2025-11-02)

### CPU/PPU Sub-Cycle Execution Order Fix

- ✅ **Hardware-Accurate Sub-Cycle Ordering:** CPU memory operations now execute BEFORE PPU flag updates (per nesdev.org)
  - **Impact:** Fixes VBlank race condition timing (CPU reads $2002 before PPU sets flag at scanline 241, dot 1)
  - **Commercial ROM Progress:** BurgerTime now working, TMNT series now displays (no longer grey screen)
  - **Implementation:** `src/emulation/State.zig:tick()` reordered to match NES hardware sub-cycle phasing
  - **Test Updates:** 8 tests corrected to match proper execution order semantics
  - **Behavioral Lockdown:** Execution order now locked per hardware specification
  - See `sessions/tasks/h-fix-vblank-subcycle-timing.md` for complete details

### PPU Sprite Wrapping Fix

- ✅ **Pre-Render Scanline Sprite Fetching:** Fixed unsigned underflow in vertical flip calculation
  - **Issue:** Pre-render scanline (261) uses stale secondary OAM from scanline 239, causing out-of-bounds row values
  - **Fix:** Changed vertical flip from regular subtraction to wrapping subtraction (`--%` operator)
  - **Impact:** Prevents undefined behavior when sprite Y positions cause row wrapping (e.g., `7 -% 56 = 207`)
  - **Hardware Accuracy:** Matches NES hardware behavior - uses wrapped value to fetch arbitrary pattern data
  - **Tests Added:** 3 comprehensive pre-render sprite fetch tests (all passing)
  - **Implementation:** `src/ppu/logic/sprites.zig` - `getSpritePatternAddress()` and `getSprite16PatternAddress()`
  - See `sessions/tasks/h-refactor-ppu-shift-register-rewrite.md` for complete details

## Previous Fixes (2025-10-15)

### Progressive Sprite Evaluation (Phase 2)

- ✅ **Cycle-Accurate Sprite Evaluation:** Replaced instant evaluation with hardware-accurate progressive evaluation
  - See [docs/STATUS.md](docs/STATUS.md) for current test status
  - SMB1 title screen now animates correctly (coin bounces) 🎉
  - Odd cycles: Read from OAM, check sprite in range
  - Even cycles: Write to secondary OAM if in range
  - Fixed sprite overflow flag (triggers on 9th sprite, not 8th)
  - Fixed general protection faults in threading tests

### Critical NMI Bug Fixes

- ✅ **NMI Line Management:** Fixed premature clearing that prevented CPU edge detection
  - Commercial ROMs now receive NMI interrupts correctly
  - Castlevania, Mega Man, Kid Icarus now working

- ✅ **Double-NMI Suppression:** Prevents multiple NMI triggers during same VBlank
  - Fixed game state corruption when PPUCTRL bit 7 toggles
  - Added `nmi_vblank_set_cycle` tracking

- ✅ **RAM Initialization:** Hardware-accurate pseudo-random RAM at power-on
  - Commercial ROMs now execute correct boot paths
  - Uses LCG with 87.5% bias toward low values (0x00-0x0F)

See **[CURRENT-ISSUES.md](docs/CURRENT-ISSUES.md)** for complete status and remaining issues.

---

## Quick Start

### Build

```bash
# Clone repository
git clone <repository-url>
cd RAMBO

# Build executable
zig build                   # Default build (Vulkan/Wayland backend)
zig build -Dwith_movy=true  # Build with terminal backend support (enables --backend=terminal)

# Run tests
zig build test

# Run emulator
zig build run

# Run with debugger (see docs/sessions/debugger-quick-start.md)
./zig-out/bin/RAMBO "path/to/rom.nes" --break-at 0x8000 --inspect
./zig-out/bin/RAMBO "path/to/rom.nes" --watch 0x2001 --inspect

# Backend selection and frame dumping
./zig-out/bin/RAMBO "path/to/rom.nes" --backend=terminal  # Terminal rendering (requires -Dwith_movy=true)
./zig-out/bin/RAMBO "path/to/rom.nes" --backend=wayland  # Vulkan/Wayland rendering (default)
./zig-out/bin/RAMBO "path/to/rom.nes" --dump-frame 120   # Dump frame 120 to frame_0120.ppm
```

**Terminal Mode:** For SSH/remote development or visual debugging without GUI:
```bash
# Build with movy support
zig build -Dwith_movy=true

# Run in terminal mode (displays NES frames in terminal using half-blocks)
./zig-out/bin/RAMBO "path/to/rom.nes" --backend=terminal

# Menu system: Press ESC for overlay menu, ENTER to select options, Y/N for confirmation
```

### Requirements

- **Zig:** 0.15.1 (check with `zig version`)
- **System:** Linux with Wayland compositor
- **GPU:** Vulkan 1.0+ compatible

---

## Features

### Completed ✅

- **CPU (6502):** 100% complete (~280 tests)
  - All 256 opcodes (151 official + 105 unofficial)
  - Cycle-accurate microstep execution
  - NMI edge detection, IRQ level triggering
  - Hardware-accurate timing quirks

- **PPU (2C02):** 100% complete (~93 tests)
  - Background rendering (tile fetching, scroll, palette)
  - Sprite rendering (evaluation, fetching, priority)
  - Sprite 0 hit detection
  - Hardware warm-up period (29,658 cycles)
  - Pre-render scanline sprite fetching (stale secondary OAM handling)

- **Video Display:** 100% complete - Backend-agnostic rendering
  - VulkanBackend: Wayland + Vulkan (default, production use)
  - MovyBackend: Terminal rendering via movy (optional, `-Dwith_movy=true`)
  - 60 FPS rendering at 256×240
  - Nearest-neighbor filtering
  - Lock-free frame delivery
  - Frame dumping to PPM files (`--dump-frame N`)

- **Input System:** 100% complete (40 tests)
  - NES controller emulation (ButtonState)
  - Keyboard mapping (Wayland events → NES buttons)
  - Thread-safe mailbox delivery

- **Controller I/O:** 100% complete (14 tests)
  - Hardware-accurate 4021 shift register
  - $4016/$4017 register emulation
  - NES strobe protocol

- **Thread Architecture:** Mailbox pattern with timer-driven emulation
  - RT-safe emulation (zero heap allocations in hot path)
  - 3-thread model (Main, Emulation, Render)
  - Lock-free communication

- **Debugger:** 100% complete (~66 tests)
  - Breakpoints, watchpoints, callbacks
  - Step execution (instruction, scanline, frame)
  - Bidirectional mailbox communication
  - Snapshot-based time-travel debugging

- **Bus & Memory:** 100% complete (~20 tests)
  - RAM mirroring, open bus simulation
  - ROM write protection, PPU register routing
  - Controller I/O integration

- **Cartridge:** Mapper system foundation complete (~48 tests)
  - AnyCartridge tagged union with inline dispatch
  - Duck-typed mapper interface (zero VTable overhead)
  - Full IRQ infrastructure (A12 tracking, IRQ polling)
  - Mapper 0 (NROM) fully implemented

- **APU (Audio):** 86% complete (135 tests)
  - Frame counter (4-step/5-step modes)
  - DMC channel with DMA
  - Envelope generators, sweep units
  - Linear counter, length counters
  - Frame IRQ edge cases

### Planned ⬜

- **APU Audio Output:** Waveform generation + audio backend
- **Additional Mappers:** MMC1, UxROM, CNROM, MMC3 (75% game coverage)

---

## Architecture Highlights

### State/Logic Separation

All components use **hybrid State/Logic pattern** for modularity and RT-safety:

- **State modules:** Pure data structures, fully serializable
- **Logic modules:** Pure functions, deterministic execution
- **Zero hidden state:** All side effects explicit

```zig
// Example: src/cpu/State.zig
pub const CpuState = struct {
    a: u8, x: u8, y: u8, sp: u8, pc: u16,
    p: StatusRegister,

    pub inline fn tick(self: *CpuState, bus: *BusState) void {
        Logic.tick(self, bus);
    }
};
```

### Comptime Generics

Zero-cost polymorphism via duck typing:

```zig
pub fn Cartridge(comptime MapperType: type) type {
    return struct {
        mapper: MapperType,
        // No VTables, all calls inlined
        pub fn cpuRead(self: *const Self, address: u16) u8 {
            return self.mapper.cpuRead(self, address);
        }
    };
}
```

### Thread Model

3-thread mailbox pattern:

1. **Main Thread:** Coordinator (minimal work)
2. **Emulation Thread:** RT-safe cycle-accurate emulation
3. **Render Thread:** Backend-agnostic rendering (comptime selection)
   - VulkanBackend (Wayland + Vulkan, default)
   - MovyBackend (Terminal rendering, optional)

---

## Testing

### Test Status

**See [docs/STATUS.md](docs/STATUS.md) for complete test breakdown and current status.**

```bash
# All tests
zig build test

# Specific categories
zig build test-unit           # Fast unit tests
zig build test-integration    # Integration tests
zig build bench-release       # Release benchmarks

# Adapt this pattern to run singular tests, this is simply an example.
zig test --dep RAMBO  -Mroot=tests/integration/mmc3_visual_regression_test.zig -MRAMBO=src/root.zig -ODebug 

# Short form (via build system)
zig build test-integration

# Target specific tests by filter, in this ppu, and return a summary of the tests outcomes based on criteria.
zig build test --summary { all | failures | success } -- ppu
```

### Test Breakdown

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

### AccuracyCoin Validation

**Goal:** Pass all 128 AccuracyCoin tests (CPU, PPU, APU, timing)

**Current:** ✅ **PASSING** - Full CPU/PPU validation complete
- Test status bytes: `$00 $00 $00 $00` (all tests passed)
- 600 frames executed, 53.6M instructions
- Zero failures detected

---

## Companion ROM Tooling

The `compiler/` directory is a Python workspace for building reference ROMs:

```bash
# Setup (once per machine)
uv run compiler toolchain

# Build AccuracyCoin test ROM
uv run compiler build-accuracycoin

# Microsoft BASIC port (in progress)
uv run compiler analyze-basic
uv run compiler preprocess-basic
```

Builds are byte-for-byte verified against canonical test ROMs. See `compiler/README.md` for details.

---

## Documentation

### For Users

- **[Documentation Hub](docs/README.md)** - Start here for navigation
- **[Current Status](docs/CURRENT-STATUS.md)** - Detailed implementation status
- **[Quick Start](QUICK-START.md)** - Getting started guide

### For Developers

- **[CLAUDE.md](CLAUDE.md)** - **Primary development reference**
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - **Core patterns reference** (State/Logic, VBlank, DMA)
- **[Implementation Guides](docs/implementation/)** - Detailed implementation documentation
- **[Thread Architecture](docs/architecture/threading.md)** - Mailbox pattern details

### Architecture Diagrams

- **[Visual Architecture](docs/dot/)** - GraphViz diagrams of entire system
- **[System Overview](docs/dot/architecture.dot)** - Complete 3-thread architecture
- **[Component Diagrams](docs/dot/)** - CPU, PPU, APU, DMA detailed diagrams

---

## Project Structure

```
RAMBO/
├── src/
│   ├── cpu/              # 6502 CPU emulation
│   ├── ppu/              # 2C02 PPU emulation
│   ├── apu/              # Audio Processing Unit
│   ├── video/            # Rendering system
│   │   ├── backends/     # VulkanBackend, MovyBackend
│   │   └── ...           # Wayland/Vulkan implementation
│   ├── input/            # Input system (keyboard mapping)
│   ├── debug/            # Debug utilities (frame dumping, etc.)
│   ├── cartridge/        # Cartridge and mapper system
│   │   ├── ines/         # iNES ROM parser
│   │   └── mappers/      # Mapper implementations + registry
│   ├── emulation/        # Emulation coordination (State, Bus)
│   ├── debugger/         # Debugging system
│   ├── mailboxes/        # Thread communication
│   ├── threads/          # EmulationThread, RenderThread
│   ├── snapshot/         # Save state system
│   ├── config/           # Configuration management
│   └── main.zig          # Entry point
├── compiler/             # Python toolchain for assembling reference ROMs
├── tests/                # Test suite (see CURRENT-ISSUES.md)
├── docs/                 # Comprehensive documentation
└── build.zig             # Build configuration
```

---

## Performance

### Emulation Performance

- **FPS:** ~60 FPS (NTSC timing)
- **Frame Timing:** 16.67ms intervals (timer-driven)
- **Accuracy:** Cycle-accurate 6502, PPU rendering
- **Memory:** <2 MB working set

### CPU Usage

- Emulation thread: ~100% of one core
- Render thread: ~10-20% of one core
- Main thread: <1%

---

## Hardware Accuracy

### Implemented Behaviors

- ✅ Read-Modify-Write dummy writes (RMW instructions)
- ✅ Page crossing dummy reads (indexed addressing)
- ✅ Open bus simulation (decay timer)
- ✅ Zero page wrapping
- ✅ NMI edge detection (falling edge trigger)
- ✅ PPU warm-up period (29,658 cycles)
- ✅ Sprite 0 hit detection
- ✅ Sprite evaluation algorithm (8 sprite limit)

### Known Deviations

**CPU Timing:** Absolute,X/Y without page crossing: +1 cycle deviation
- **Impact:** Functionally correct, timing slightly off
- **Priority:** Medium (defer to post-playability)

---

## Dependencies

### External Libraries

**Configured in build.zig.zon:**

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

---

## Contributing

### Development Principles

1. **Hardware Accuracy First** - Cycle-accurate over performance
2. **State/Logic Separation** - Hybrid pattern for all components
3. **RT-Safety** - Zero heap allocations in hot path
4. **Comptime Over Runtime** - Zero-cost abstractions
5. **Documentation First** - Code changes require doc updates

### Getting Started

1. Read [CLAUDE.md](CLAUDE.md) for development guide
2. Check [Current Status](docs/CURRENT-STATUS.md) for priorities
3. Review [Architecture Overview](docs/code-review/01-architecture.md) for patterns
4. Run tests: `zig build test`

### Testing Requirements

```bash
# Before committing
zig build test  # Verify no regressions (see CURRENT-ISSUES.md for current status)

# Verify no regressions
git diff --stat
```

---

## License

MIT License (see LICENSE file)

---

## Resources

### NES Hardware Documentation

- [NESDev Wiki](https://www.nesdev.org/wiki/) - Comprehensive NES documentation
- [6502 Reference](http://www.6502.org/) - CPU architecture
- [PPU Rendering](https://www.nesdev.org/wiki/PPU_rendering) - PPU details

### Zig Resources

- [Zig Language Reference](https://ziglang.org/documentation/master/)
- [Zig Standard Library](https://ziglang.org/documentation/master/std/)

---

**Last Updated:** 2025-11-04
**Version:** 0.2.0-alpha
**Status:** 1162/1184 tests passing (98.1%) - See [docs/STATUS.md](docs/STATUS.md)
**Current Focus:** Bus handler architecture refactoring complete, VBlank/PPU/NMI timing bugs remaining (see docs/STATUS.md and docs/CURRENT-ISSUES.md)
