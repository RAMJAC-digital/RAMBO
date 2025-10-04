# Gemini Development Guide for RAMBO

**Date:** 2025-10-04
**Status:** PPU Complete (100%). Video subsystem implementation next.

This document provides a high-level overview and development guidelines for the RAMBO NES emulator project, specifically for the Gemini agent.

## 1. Project Overview

- **Project:** RAMBO (Cycle-Accurate NES Emulator)
- **Language:** Zig 0.15.1
- **Primary Goal:** Achieve 100% pass rate on the AccuracyCoin test suite.

## 2. Core Architecture: Hybrid Model

The project follows a **hybrid architecture**:

1.  **Synchronous Emulation Core:**
    *   The core components (CPU, PPU, Bus) run in a **single, deterministic, single-threaded loop** to ensure cycle-accuracy.
    *   This core is a pure state machine: `next_state = f(current_state)`.
    *   **CRITICAL:** The core emulation loop must remain **Real-Time (RT) safe**. This means no memory allocations, no blocking I/O, and no locks on the hot path.

2.  **Asynchronous I/O Layer:**
    *   All I/O operations (video rendering, audio output, controller input, file access) are handled separately.
    *   The planned architecture uses a **Mailbox (Double-Buffer Swap)** pattern for video frames and `libxev` for other async events.

## 3. Key Design Patterns & Conventions

-   **State/Logic Separation:** All core components (`Cpu`, `Ppu`, `Bus`) are strictly separated into `State` (pure data structs) and `Logic` (pure functions that operate on the state). Adhere to this pattern.

-   **Comptime Generics for Polymorphism:** The project uses Zig's compile-time duck typing instead of runtime V-tables (e.g., `Cartridge(MapperType)`). This is the preferred method for polymorphism.

-   **Testing:** The project has a comprehensive test suite. New features must be accompanied by tests. For hardware features, follow the TDD approach established in Phase 4 & 7A (write failing tests first, then implement).

## 4. Current Status & Development Priorities

-   **CPU:** ✅ 100% complete (105/105 tests).
-   **PPU:** ✅ 100% complete (79/79 tests). Background and sprite rendering pipelines fully implemented and tested.
-   **Debugger/Snapshot:** ✅ Complete and production-ready (62/62 debugger tests, 8/9 snapshot tests).
-   **Architecture:** ✅ Major refactoring complete. Thread architecture and mailbox pattern implemented.

**Primary Roadmap:** The authoritative plan is `docs/DEVELOPMENT-ROADMAP.md`.

**Next Critical Path:**
1.  **Video Subsystem:** Implement the video backend to display the PPU's output on screen.
2.  **Controller I/O:** Implement controller registers ($4016/$4017) to allow user input.
3.  **Mappers:** Implement additional mappers (MMC1, MMC3) to expand game compatibility.

## 5. Key Documents for Reference

Before starting any task, consult these primary documents:

-   **Roadmap:** `docs/DEVELOPMENT-ROADMAP.md` - Complete project roadmap
-   **Cleanup Plan:** `docs/code-review/CLEANUP-PLAN-2025-10-04.md` - Code cleanup status
-   **High-Level Status:** `docs/implementation/STATUS.md` - Current implementation status
-   **Video Plan:** `docs/architecture/video-system.md` - Phase 8 Wayland+Vulkan implementation
-   **Sprite Specification:** `docs/architecture/ppu-sprites.md` - Complete sprite rendering spec
-   **Thread Architecture:** `docs/architecture/threading.md` - Mailbox pattern and timer-driven emulation

## 6. Agent Contribution Guidelines

1.  **Analyze First:** Always review relevant specs and status docs before coding.
2.  **Follow Patterns:** Adhere strictly to the established State/Logic and comptime generics patterns.
3.  **Prioritize RT-Safety:** Do not introduce allocations, blocking calls, or locks into the core emulation loop.
4.  **Test Thoroughly:** Add unit and integration tests for all new functionality.
5.  **Update Documentation:** All code changes must be reflected in relevant status documents.