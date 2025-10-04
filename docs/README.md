# RAMBO Documentation

Cycle-accurate NES emulator written in Zig 0.15.1.

## Quick Links

### Getting Started
- [Build & Run Instructions](../README.md) (see root README)
- [Architecture Overview](ARCHITECTURE.md) *(coming soon)*
- [Development Roadmap](DEVELOPMENT-ROADMAP.md) *(coming soon)*

### Architecture Documentation
- **Core Components:**
  - CPU (6502) - Complete *(docs in code-review/02-cpu.md)*
  - PPU (2C02) - Complete *(docs in code-review/03-ppu.md)*
  - Bus & Memory - Complete *(docs in code-review/04-memory-and-bus.md)*
  - Cartridge System - Mapper 0 complete *(docs in code-review/)*

- **Advanced Topics:**
  - [Sprite Rendering](architecture/ppu-sprites.md) - Complete specification
  - [Thread Architecture](architecture/threading.md) *(coming soon)*
  - [Video System Plan](architecture/video-system.md) *(coming soon)*
  - [Hybrid State/Logic Pattern](implementation/design-decisions/final-hybrid-architecture.md)
  - [Comptime Generics](code-review/PHASE-3-COMPTIME-GENERICS-PLAN.md)

### API Reference
- [Debugger API](api-reference/debugger-api.md) - Complete debugging system
- [Snapshot API](api-reference/snapshot-api.md) - State save/restore

### Development
- **Current Status:** [Implementation Status](implementation/STATUS.md)
- **Code Reviews:** [Review Findings](code-review/README.md)
- **Testing:** [Test Strategy](05-testing/)
- **Session Notes:** [Implementation Sessions](implementation/sessions/)
- **Design Decisions:** [Architecture Decisions](implementation/design-decisions/)

### Archive
- **Historical Documents:** [Archived Documentation](archive/) - Superseded plans and completed phases

---

## Current Status

**Last Updated:** 2025-10-04
**Version:** 0.2.0-alpha

### Component Status

| Component | Status | Tests | Notes |
|-----------|--------|-------|-------|
| CPU (6502) | ✅ 100% | 105/105 | All 256 opcodes implemented |
| PPU Background | ✅ 100% | 6/6 | Full tile rendering pipeline |
| PPU Sprites | ✅ 100% | 73/73 | Evaluation, fetching, rendering complete |
| Debugger | ✅ 100% | 62/62 | Breakpoints, watchpoints, callbacks |
| Bus & Memory | ✅ 85% | 17/17 | Missing controller I/O ($4016/$4017) |
| Cartridge | ✅ Mapper 0 | 2/2 | NROM complete, ~5% game coverage |
| Thread Architecture | ✅ 100% | N/A | Mailbox pattern, timer-driven |
| Snapshot System | ✅ 99% | 8/9 | 1 cosmetic metadata test |
| Video Display | ⬜ 0% | N/A | Wayland+Vulkan planned |
| Controller I/O | ⬜ 0% | N/A | Phase 9 |
| APU (Audio) | ⬜ 0% | N/A | Future |

**Overall: 575/576 tests passing (99.8%)**

### Architecture Highlights

- **State/Logic Separation:** All components use hybrid pattern for modularity and RT-safety
- **Comptime Generics:** Zero-cost polymorphism via duck typing (no VTables)
- **Thread Architecture:** 2-thread mailbox pattern with libxev event loops
- **Mailbox Communication:**
  - FrameMailbox: Double-buffered (480 KB total)
  - ConfigMailbox: Single-value atomic updates
  - WaylandEventMailbox: Double-buffered event queue (awaiting Phase 8)

### Performance Metrics

- **Emulation Speed:** 62.97 FPS average (target: 60.10 NTSC)
- **Frame Timing:** 16ms intervals (libxev timer-driven)
- **Accuracy:** Cycle-accurate 6502, PPU rendering
- **Memory Usage:** ~500 KB frame buffers, minimal heap allocations

---

## Critical Path to Playability

**Current Progress: 83% Complete**

1. ✅ **CPU Emulation** - Production ready (256/256 opcodes)
2. ✅ **Architecture Refactoring** - State/Logic pattern, comptime generics
3. ✅ **PPU Background** - Tile fetching and rendering
4. ✅ **PPU Sprites** - Evaluation, fetching, rendering
5. ✅ **Debugger** - Full debugging system
6. ✅ **Thread Architecture** - Mailbox pattern complete
7. 🟡 **Video Display (Next)** - Wayland + Vulkan backend (20-30 hours)
8. ⬜ **Controller I/O** - $4016/$4017 registers (3-4 hours)

**Estimated Time to Playable:** 23-34 hours (3-5 days)

---

## Quick Start

### Running Tests

```bash
# All tests (575/576 passing)
zig build test

# Specific categories
zig build test-unit               # Fast unit tests
zig build test-integration        # Integration tests
zig build test-trace              # Cycle-by-cycle traces
```

### Running Emulator

```bash
# Demo (no video output yet)
zig build run

# Outputs FPS statistics and emulation metrics
# Phase 1: Thread Architecture Demo
```

### Test Breakdown

- **CPU Tests:** 105 (instructions, unofficial opcodes, RMW)
- **PPU Tests:** 79 (6 background/CHR + 73 sprite)
- **Debugger Tests:** 62 (breakpoints, watchpoints, callbacks)
- **Bus Tests:** 17 (RAM mirroring, PPU routing, open bus)
- **Cartridge Tests:** 2 (ROM loading and validation)
- **Snapshot Tests:** 9 (8 passing, 1 cosmetic failure)
- **Integration Tests:** 21 (CPU-PPU cross-component)
- **Comptime Tests:** 8 (mapper generic validation)
- **Inline Tests:** ~297 (within implementation files)

**Known Failure:** 1 snapshot metadata test (4-byte size discrepancy, cosmetic only)

---

## Documentation Structure

```
docs/
├── README.md                     # This file - navigation hub
├── ARCHITECTURE.md               # High-level architecture (coming soon)
├── DEVELOPMENT-ROADMAP.md        # Development plan (coming soon)
│
├── architecture/                 # Architecture documentation
│   ├── ppu-sprites.md            # Sprite rendering specification
│   ├── threading.md              # Thread architecture (coming soon)
│   └── video-system.md           # Wayland+Vulkan plan (coming soon)
│
├── api-reference/                # API documentation
│   ├── debugger-api.md           # Debugger API guide
│   └── snapshot-api.md           # Snapshot API guide
│
├── implementation/               # Implementation notes
│   ├── STATUS.md                 # Current implementation status
│   ├── sessions/                 # Development session notes
│   ├── design-decisions/         # Architecture decision records
│   └── completed/                # Completed work summaries
│
├── code-review/                  # Code review findings
│   ├── README.md                 # Review overview
│   ├── 01-architecture.md        # Hybrid State/Logic pattern
│   ├── 02-cpu.md                 # CPU implementation review
│   ├── 03-ppu.md                 # PPU implementation review
│   ├── 04-memory-and-bus.md      # Bus architecture review
│   └── ... (additional reviews)
│
├── 05-testing/                   # Testing documentation
│   └── accuracycoin-cpu-requirements.md
│
└── archive/                      # Historical/superseded docs
    └── (Phase plans, old designs, audit reports)
```

---

## Key Principles

1. **Hardware Accuracy:** Cycle-accurate 6502 emulation, accurate PPU timing
2. **RT-Safety:** Zero heap allocations in hot path, deterministic execution
3. **State/Logic Separation:** Testable, serializable state; pure functional logic
4. **Comptime Over Runtime:** Zero-cost abstractions via duck typing
5. **Documentation First:** Code changes require corresponding doc updates

---

## Next Actions

### For New Contributors
1. Read [Architecture Overview](ARCHITECTURE.md) *(coming soon)*
2. Check [Development Roadmap](DEVELOPMENT-ROADMAP.md) *(coming soon)*
3. Review [Code Review Findings](code-review/README.md)
4. Pick a task from current phase

### For Current Development
**Current Phase:** Video Display (Wayland + Vulkan)
- See [Video System Plan](architecture/video-system.md) *(coming soon)*
- Estimated: 20-30 hours implementation
- Dependencies: zig-wayland (already in build.zig.zon)
- Scaffolding: WaylandEventMailbox implemented

---

**Project:** RAMBO NES Emulator
**Language:** Zig 0.15.1
**Target:** AccuracyCoin Test Suite (cycle-accurate validation)
**License:** MIT
