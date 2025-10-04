# RAMBO Development Plan

**Date:** 2025-10-04
**Version:** 0.2.0-alpha
**Status:** Thread Architecture Complete. Ready for Video Subsystem Implementation.

## 1. Overview

This document provides the consolidated, authoritative development plan for the RAMBO NES emulator. It supersedes all previous planning documents and reflects the latest architectural decisions and implementation progress.

**Current State:**
- **CPU:** 100% complete and tested (256/256 opcodes).
- **PPU Background:** 100% complete (registers, VRAM, rendering pipeline).
- **PPU Sprites:** 0% implemented (38 tests written, deferred to Phase 3).
- **Thread Architecture:** ✅ COMPLETE - Mailbox pattern, timer-driven emulation.
- **Debugger/Snapshot:** Fully implemented and tested (62/62 tests).
- **Testing:** 486/496 tests passing (97.9%) - 10 expected failures.

**Goal:** Achieve a playable emulator by implementing the critical path components: video output, sprite rendering, and controller input.

## 2. Critical Path to Playability

The following phases are the top priority and must be completed in order.

### Phase 1: Thread Architecture & Timer-Driven Emulation ✅ COMPLETE

**Objective:** Establish multi-threaded architecture with mailbox communication pattern and accurate NTSC frame timing.
**Status:** ✅ COMPLETE as of 2025-10-04.

**Completed Components:**
1.  **Mailboxes Container:** Central dependency injection pattern (`src/mailboxes/Mailboxes.zig`)
2.  **Frame Mailbox:** Double-buffered frame passing (`src/mailboxes/FrameMailbox.zig`)
3.  **Wayland Event Mailbox:** Double-buffered event queue (`src/mailboxes/WaylandEventMailbox.zig`)
4.  **Config Mailbox:** Single-value config updates (`src/mailboxes/ConfigMailbox.zig`)
5.  **Timer-Driven Emulation:** libxev timer-based frame pacing (16.639ms @ 60.0988 Hz NTSC)
6.  **Emulation Thread:** Dedicated RT thread with own event loop
7.  **Main Thread Coordination:** Clean shutdown and statistics tracking

**Performance Results:**
- Average FPS: 61.46 (within 2.2% of target 60.10 FPS)
- Clean shutdown with no spam
- Frame count accurately tracked

**Acceptance:** ✅ Timer-driven emulation running at accurate NTSC frame rate with proper thread separation.

### Phase 2: Video Subsystem Implementation (Est. 15-20 hours)

**Objective:** Render the PPU's output to the screen.
**Reference:** `docs/VIDEO-SUBSYSTEM-DEVELOPMENT-PLAN.md` (the revised plan)

**Tasks:**
1.  **Frame Mailbox (4-5 hours):** Implement the double-buffer mailbox pattern.
2.  **Window & OpenGL Backend (6-8 hours):** Create a window using GLFW and set up an OpenGL context.
3.  **Integration (3-4 hours):** Integrate the video subsystem with the main emulation loop.
4.  **Polish (2-3 hours):** Add FPS counter, handle window resizing, and ensure clean shutdown.

**Acceptance Criteria:** The emulator displays a stable 60 FPS video output. Window management is functional.

### Phase 3: PPU Sprite Rendering (Est. 29-42 hours)

**Objective:** Implement complete sprite rendering pipeline for foreground graphics.
**Reference:** `docs/SPRITE-RENDERING-SPECIFICATION.md`

**Tasks:**
1.  **Sprite Evaluation (8-12 hours):** Implement cycles 1-256 sprite evaluation logic.
2.  **Sprite Fetching (6-8 hours):** Implement cycles 257-320 sprite data fetching.
3.  **Sprite Rendering (8-12 hours):** Implement sprite pixel output with background priority.
4.  **Sprite 0 Hit Detection (3-4 hours):** Implement accurate sprite 0 collision detection.
5.  **OAM DMA (3-4 hours):** Implement $4014 DMA transfer.

**Acceptance Criteria:**
- All 38 existing sprite tests pass
- Sprite graphics visible in visual output
- Sprite 0 hit works correctly
- OAM DMA transfers sprite data correctly

### Phase 4: Controller I/O (Est. 3-4 hours)

**Objective:** Implement controller input to allow for gameplay.

**Tasks:**
1.  **Register Implementation (2 hours):** Implement the controller registers at $4016 and $4017.
2.  **Input Mapping (1-2 hours):** Map keyboard/gamepad inputs to NES controller buttons.

**Acceptance Criteria:** User can control games using keyboard or gamepad. Controller test ROMs pass.

## 3. Secondary Priorities (Post-Playability)

- **APU (Audio):** Implement the audio processing unit for sound output.
- **Mappers:** Implement additional mappers (MMC1, MMC3, etc.) to expand game compatibility.
- **OAM DMA:** Complete the full implementation and testing of OAM DMA.
- **Advanced Debugger Features:** Add disassembler, symbol support, and a TUI.

## 4. Documentation

- This `DEVELOPMENT-PLAN.md` is the single source of truth for the project roadmap.
- The `docs/code-review/CLEANUP-PLAN-2025-10-04.md` tracks outstanding cleanup tasks.