# RAMBO NES Emulator

Cycle-accurate NES emulator written in Zig 0.15.1.

**Current Status:** ~99% complete (955/967 tests passing, AccuracyCoin PASSING ✅)

---

## Recent Fixes (2025-10-09)

- ✅ **BRK Flag Masking:** Hardware interrupts (NMI/IRQ) now correctly clear B flag (bit 4)
- ✅ **Frame Pacing Precision:** Fixed nanosecond rounding (16ms → 17ms) for accurate NTSC timing
- ✅ **Fine X Scroll Guard:** Masked to 3 bits to prevent panic on invalid values
- ✅ **Debugger Restoration:** Implemented `handleCpuSnapshot()` for full CPU state display

See **[Session Summary](docs/sessions/session-summary-2025-10-09.md)** for details.

---

## Quick Start

### Build

```bash
# Clone repository
git clone <repository-url>
cd RAMBO

# Build executable
zig build

# Run tests (955/967 passing)
zig build test

# Run emulator
zig build run

# Run with debugger (see docs/sessions/debugger-quick-start.md)
./zig-out/bin/RAMBO "path/to/rom.nes" --break-at 0x8000 --inspect
./zig-out/bin/RAMBO "path/to/rom.nes" --watch 0x2001 --inspect
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

- **PPU (2C02):** 100% complete (~90 tests)
  - Background rendering (tile fetching, scroll, palette)
  - Sprite rendering (evaluation, fetching, priority)
  - Sprite 0 hit detection
  - Hardware warm-up period (29,658 cycles)

- **Video Display:** 100% complete - Wayland + Vulkan
  - XDG shell window management
  - 60 FPS rendering at 256×240
  - Nearest-neighbor filtering
  - Lock-free frame delivery

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
3. **Render Thread:** Wayland window + Vulkan rendering

---

## Testing

### Test Status

**955/967 tests passing (98.8%)**

```bash
# All tests
zig build test

# Specific categories
zig build test-unit           # Fast unit tests
zig build test-integration    # Integration tests
zig build bench-release       # Release benchmarks
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
- **[Architecture Overview](docs/code-review/01-architecture.md)** - Hybrid State/Logic pattern
- **[Thread Architecture](docs/architecture/threading.md)** - Mailbox pattern details
- **[Video System](docs/implementation/video-subsystem.md)** - Wayland + Vulkan implementation

### For Code Review

- **[Code Review Index](docs/code-review/README.md)** - Review findings
- **[CPU Review](docs/code-review/02-cpu.md)** - CPU implementation
- **[PPU Review](docs/code-review/03-ppu.md)** - PPU implementation
- **[Bus Review](docs/code-review/04-memory-and-bus.md)** - Bus architecture

---

## Project Structure

```
RAMBO/
├── src/
│   ├── cpu/              # 6502 CPU emulation
│   ├── ppu/              # 2C02 PPU emulation
│   ├── apu/              # Audio Processing Unit
│   ├── video/            # Wayland + Vulkan rendering
│   ├── input/            # Input system (keyboard mapping)
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
├── tests/                # Test suite (939/947 passing)
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
zig build test  # Must report 955/967 (7 skipped, 5 flaky integration tests)

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

**Last Updated:** 2025-10-09
**Version:** 0.2.0-alpha
**Status:** ~99% complete, 955/967 tests passing, AccuracyCoin PASSING ✅
**Current Focus:** Super Mario Bros blank screen investigation (see docs/sessions/session-summary-2025-10-09.md)
