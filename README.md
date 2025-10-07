# RAMBO NES Emulator

Cycle-accurate NES emulator written in Zig 0.15.1.

**Current Status:** 88% complete (560/561 tests passing, AccuracyCoin PASSING ✅)

---

## Quick Start

### Build

```bash
# Clone repository
git clone <repository-url>
cd RAMBO

# Build executable
zig build

# Run tests (560/561 passing)
zig build test

# Run emulator (video output in Phase 8)
zig build run
```

### Requirements

- **Zig:** 0.15.1 (check with `zig version`)
- **System:** Linux with Wayland compositor (for Phase 8 video)
- **GPU:** Vulkan 1.0+ compatible (for Phase 8 video)

---

## Features

### Completed ✅

- **CPU (6502):** 100% complete (105/105 tests)
  - All 256 opcodes (151 official + 105 unofficial)
  - Cycle-accurate microstep execution
  - NMI edge detection, IRQ level triggering

- **PPU (2C02):** 100% complete (79/79 tests)
  - Background rendering (tile fetching, scroll, palette)
  - Sprite rendering (evaluation, fetching, priority)
  - Sprite 0 hit detection

- **Thread Architecture:** Mailbox pattern with timer-driven emulation
  - RT-safe emulation (zero heap allocations in hot path)
  - 62.97 FPS average (4.8% over 60.10 NTSC target)
  - Double-buffered frame passing

- **Debugger:** Full debugging system (62/62 tests)
  - Breakpoints, watchpoints, callbacks
  - Step execution (instruction, scanline, frame)
  - Snapshot-based time-travel debugging

- **Bus & Memory:** 85% complete (17/17 tests)
  - RAM mirroring, open bus simulation
  - ROM write protection, PPU register routing

- **Cartridge:** Mapper system foundation complete (47/47 tests)
  - AnyCartridge tagged union with inline dispatch
  - Duck-typed mapper interface (zero VTable overhead)
  - Full IRQ infrastructure (A12 tracking, IRQ polling)
  - Mapper 0 (NROM) fully implemented

### In Progress 🟡

- **Video Display:** Phase 8 - Wayland + Vulkan (20-28 hours)
  - Window management (XDG shell)
  - Vulkan rendering backend
  - Vsync integration

### Planned ⬜

- **Controller I/O:** Phase 9 (3-4 hours)
  - $4016/$4017 registers
  - Keyboard to NES controller mapping

- **APU (Audio):** Future (40-60 hours)
  - All 5 channels (Pulse, Triangle, Noise, DMC)
  - Sample-accurate audio

---

## Architecture Highlights

### State/Logic Separation

All components use **hybrid State/Logic pattern** for modularity and RT-safety:

- **State modules:** Pure data structures, fully serializable
- **Logic modules:** Pure functions, deterministic execution
- **Zero hidden state:** All side effects explicit

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

2-thread mailbox pattern (3 threads in Phase 8):

1. **Main Thread:** Coordinator only (minimal work)
2. **Emulation Thread:** RT-safe cycle-accurate emulation
3. **Video Thread:** Wayland window + Vulkan rendering (Phase 8)

---

## Testing

### Test Status

**560/561 tests passing (99.8%)**

```bash
# All tests
zig build test

# Specific categories
zig build test-unit           # Fast unit tests
zig build test-integration    # Integration tests
zig build test-trace          # Cycle-by-cycle traces
```

### Test Breakdown

- CPU: 105/105 (100%)
- PPU: 79/79 (100%)
- Debugger: 62/62 (100%)
- Bus: 17/17 (100%)
- Integration: 35/35 (100%)
- Cartridge: 2/2 (100%)
- Mapper Registry: 45/45 (100%)
- Snapshot: 8/9 (1 non-blocking failure)
- Comptime: 8/8 (100%)

### AccuracyCoin Target

**Goal:** Pass all 128 AccuracyCoin tests (CPU, PPU, APU, timing)

**Current:** ✅ **PASSING** - Full CPU/PPU validation complete
- Test status bytes: `$00 $00 $00 $00` (all tests passed)
- 600 frames executed, 53.6M instructions
- Zero failures detected

---

## Companion ROM Tooling

- `compiler/` is a uv-managed Python workspace that builds and caches the patched `nesasm` assembler alongside helper CLIs.
- Run `uv run compiler toolchain` once per machine to fetch and patch `nesasm`, then `uv run compiler build-accuracycoin` to regenerate the AccuracyCoin ROM used by integration tests.
- Builds are byte-for-byte verified against `AccuracyCoin/AccuracyCoin.nes` by default so the emulator always exercises the canonical test image.
- The Microsoft BASIC port effort is tracked in `compiler/docs/microsoft-basic-port-plan.md`; once the macro translation layer lands the `build-basic` command will emit a NES-compatible ROM.
- Additional mapper/memory reference notes for future ROM work live in `compiler/README.md`.

---

## Documentation

### For Users

- **[Documentation Hub](docs/README.md)** - Start here for navigation
- **[Development Roadmap](docs/DEVELOPMENT-ROADMAP.md)** - Project status and timeline
- **[Build & Test Guide](docs/README.md#quick-start)** - Getting started

### For Developers

- **[CLAUDE.md](CLAUDE.md)** - Development guide for contributors
- **[Architecture Overview](docs/code-review/01-architecture.md)** - Hybrid State/Logic pattern
- **[Thread Architecture](docs/architecture/threading.md)** - Mailbox pattern details
- **[Video System Plan](docs/architecture/video-system.md)** - Phase 8 implementation

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
│   ├── bus/              # Memory bus and routing
│   ├── cartridge/        # Cartridge and mapper system
│   │   └── mappers/      # Mapper implementations + registry
│   ├── debugger/         # Debugging system
│   ├── mailboxes/        # Thread communication
│   ├── config/           # Configuration management
│   └── main.zig          # Entry point
├── compiler/             # Python toolchain for assembling reference ROMs
├── tests/                # Test suite (560/561 passing)
├── docs/                 # Comprehensive documentation
└── build.zig             # Build configuration
```

---

## Performance

### Emulation Performance

- **FPS:** 62.97 average (target: 60.10 NTSC)
- **Frame Timing:** 16ms intervals (timer-driven)
- **Accuracy:** Cycle-accurate 6502, PPU rendering
- **Memory:** <1 MB working set

### CPU Usage

- Emulation thread: 100% of one core
- Main thread: <1%
- Future video thread: 10-20% of one core

---

## Critical Path to Playability

**Current Progress: 88% Complete**

1. ✅ CPU Emulation (100%)
2. ✅ Architecture Refactoring (100%)
3. ✅ PPU Background (100%)
4. ✅ PPU Sprites (100%)
5. ✅ Debugger (100%)
6. ✅ Thread Architecture (100%)
7. ✅ Controller I/O (100%) - $4016/$4017 registers
8. ✅ Mapper System Foundation (100%) - AnyCartridge, IRQ infrastructure
9. 🟡 Video Display (0%) - Wayland + Vulkan - **NEXT** (20-28 hours)

**Estimated Time to Playable:** 20-28 hours (2.5-3.5 days)

---

## Hardware Accuracy

### Implemented Behaviors

- ✅ Read-Modify-Write dummy writes (RMW instructions)
- ✅ Page crossing dummy reads (indexed addressing)
- ✅ Open bus simulation (decay timer)
- ✅ Zero page wrapping
- ✅ NMI edge detection (falling edge trigger)
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

- **libxev:** Event loop library (integrated, used for timer-driven emulation)
- **zig-wayland:** Wayland protocol bindings (configured, awaiting Phase 8)

### System Requirements

**Development:**
- Zig 0.15.1
- Linux (Wayland compositor for Phase 8)

**Runtime:**
- Vulkan 1.0+ GPU (for Phase 8 video)
- Wayland compositor: GNOME, KDE Plasma, Sway, etc.

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
2. Check [Development Roadmap](docs/DEVELOPMENT-ROADMAP.md) for current priorities
3. Review [Architecture Overview](docs/code-review/01-architecture.md) for patterns
4. Pick a task from current phase

### Testing Requirements

```bash
# Before committing
zig build test  # Must report 560/561 (1 known non-blocking failure)

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

**Last Updated:** 2025-10-06
**Version:** 0.2.0-alpha
**Status:** 88% complete, 560/561 tests passing, AccuracyCoin PASSING ✅
**Next Milestone:** Video Display (Phase 8) - 20-28 hours to first visual output
