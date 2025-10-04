# RAMBO NES Emulator - Implementation Status

**Last Updated:** 2025-10-04
**Version:** 0.2.0-alpha
**Target:** Cycle-accurate NES emulation passing AccuracyCoin test suite
**Tests:** 575/576 passing (99.8%)

## Project Overview

RAMBO is a hardware-accurate NES emulator written in Zig. The project follows a **hybrid architecture**, combining a synchronous, single-threaded emulation core (CPU, PPU, Bus) with an asynchronous I/O layer for video, input, and file handling. This design ensures cycle-accuracy while maintaining a responsive user experience.

The project has completed major architectural refactoring and the full PPU rendering pipeline (background and sprites). The next focus is on implementing the video subsystem to display the rendered frames.

## Current Component Status

- ✅ **CPU:** 100% complete (105/105 tests). All 256 opcodes implemented and tested.
- ✅ **PPU:** 100% complete (79/79 tests). Background and sprite rendering pipelines fully implemented and tested.
- ✅ **Bus & Memory:** 85% complete (17/17 tests). Core functionality robust and tested. Controller I/O ($4016/$4017) pending.
- ✅ **Thread Architecture:** 100% complete. Mailbox pattern with timer-driven emulation (62.97 FPS measured).
- ✅ **Debugger & Snapshots:** Production-ready (62/62 debugger tests, 8/9 snapshot tests).
- ✅ **Testing:** 576 total tests (575 passing). Test infrastructure covers all major components.

## Development Plan

The authoritative development plan is now maintained in:

**[DEVELOPMENT-ROADMAP.md](../DEVELOPMENT-ROADMAP.md)**

This roadmap outlines the critical path to a playable emulator and long-term vision.

### Next Immediate Priorities:

1.  **Video Subsystem:** Implement the video backend to display the PPU's output on screen.
2.  **Controller I/O:** Implement controller registers to allow user input.
3.  **Mappers:** Implement additional mappers (MMC1, MMC3) to expand game compatibility.

## Build Commands

```bash
# Build executable
zig build

# Run all tests (unit + integration)
zig build test

# Run executable
zig build run -- <path/to/rom.nes>
```
