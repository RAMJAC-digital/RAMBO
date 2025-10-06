# RAMBO Documentation Hub

_Last updated: 2025-10-06 — Test suite: **551/551** passing — P1 Accuracy Fixes COMPLETE ✅_

Welcome! This directory hosts the technical documentation for the RAMBO NES emulator. Use this page as the entry point for architecture notes, API references, testing plans, and historical archives.

---

## Quick Navigation

| Topic | Purpose | Key Files |
|-------|---------|-----------|
| Getting Started | Build, test, and contributor onboarding | [`README.md`](../README.md), [`AGENTS.md`](../AGENTS.md) |
| Architecture | Deep dives into core subsystems | [`architecture/`](architecture/) — sprites, threading model, video plan |
| API Guides | Public-facing modules | [`api-reference/debugger-api.md`](api-reference/debugger-api.md), [`api-reference/snapshot-api.md`](api-reference/snapshot-api.md) |
| Implementation Status | Current progress and roadmap | [`implementation/STATUS.md`](implementation/STATUS.md), [`DEVELOPMENT-ROADMAP.md`](DEVELOPMENT-ROADMAP.md) |
| Testing | AccuracyCoin requirements and strategy | [`testing/accuracycoin-cpu-requirements.md`](testing/accuracycoin-cpu-requirements.md) |
| Code Review Findings | Current status and P1 planning | [`code-review/STATUS.md`](code-review/STATUS.md), [`code-review/PLAN-P1-ACCURACY-FIXES.md`](code-review/PLAN-P1-ACCURACY-FIXES.md) |
| Historical Archive | P0 sessions, archived reviews | [`archive/sessions/p0/`](archive/sessions/p0/), [`archive/p0/`](archive/p0/), [`archive/code-review-2025-10-04/`](archive/code-review-2025-10-04/) |

---

## Component Snapshot (Active Documents)

| Component | Location | Tests | Notes |
|-----------|----------|-------|-------|
| CPU (6502) | `src/cpu/` + [`code-review/archive/2025-10-05/02-cpu.md`](code-review/archive/2025-10-05/02-cpu.md) | 105/105 | ✅ P0 Complete - Cycle-accurate, all 256 opcodes |
| PPU (2C02) | `src/ppu/` + [`architecture/ppu-sprites.md`](architecture/ppu-sprites.md) | 79/79 | Background + sprite pipelines validated |
| Bus & Memory | `src/bus/` + [`code-review/archive/2025-10-05/04-memory-and-bus.md`](code-review/archive/2025-10-05/04-memory-and-bus.md) | 17/17 | Controller I/O pending (Phase 9) |
| Snapshot System | `src/snapshot/` + [`api-reference/snapshot-api.md`](api-reference/snapshot-api.md) | 9/9 | Metadata sizing now measured at runtime |
| Debugger | `src/debugger/` + [`api-reference/debugger-api.md`](api-reference/debugger-api.md) | 62/62 | Breakpoints, watchpoints, virtual console |
| Thread Architecture | `src/mailboxes/`, [`architecture/threading.md`](architecture/threading.md) | N/A | Two-thread mailbox design; third thread reserved for video |
| Video Plan | `architecture/video-system.md` | N/A | Wayland + Vulkan roadmap for Phase 8 |

---

## How to Use This Directory

1. **Start with the overview:** The root [`README.md`](../README.md) describes the current feature set and test commands.
2. **Consult the roadmap:** [`DEVELOPMENT-ROADMAP.md`](DEVELOPMENT-ROADMAP.md) outlines the critical path (Video → Controller I/O → Playable games).
3. **Dive into subsystems:** Architecture notes explain the rationale behind the State/Logic split and thread model.
4. **Reference APIs:** Use the guides under `api-reference/` when integrating with external tooling or writing tests.
5. **Review historical context:** Everything under `docs/archive/` retains earlier decisions and progress reports. Each file now carries a historical note with its original date.

---

## Recent Documentation Changes (2025-10-06)

**Phase 1 (P1) Accuracy Fixes Complete:**
- ✅ Task 1.1: Unstable Opcode Configuration (comptime variant dispatch)
- ✅ Task 1.2: OAM DMA Implementation (14 tests, cycle-accurate 513/514 cycles)
- ✅ 551/551 tests passing (100%)
- ✅ P1 completion documented in `implementation/completed/P1-TASKS-1.1-1.2-COMPLETION-2025-10-06.md`

**Documentation Updates:**
- Test counts corrected throughout (562/583 → 551, verified count)
- P1 task status updated to COMPLETE in `code-review/STATUS.md`
- Build system cleaned up (removed deleted test file references)
- Generated docs added to .gitignore
- All documentation hubs updated with current state

**Phase 0 Complete:**
- ✅ All 256 CPU opcodes implemented with cycle-accurate timing
- ✅ Fixed +1 cycle deviation for indexed addressing modes
- ✅ Phase 0 session docs archived to `archive/sessions/p0/`
- ✅ Timing fix completion documented in `archive/p0/P0-TIMING-FIX-COMPLETION-2025-10-06.md`

For detailed update plan, see [`DOCUMENTATION-UPDATE-PLAN-2025-10-06.md`](DOCUMENTATION-UPDATE-PLAN-2025-10-06.md).

---

## Need Help?

- **Slack / ChatOps:** Refer to the team channel `#rambo-dev` (internal) for coordination.
- **Issues & Tasks:** Track progress in the project board linked from `STATUS.md`.
- **Testing:** Always run `zig build --summary all test` before submitting changes; the command is documented in the root README and produces step-by-step counts.

Happy emulating!
