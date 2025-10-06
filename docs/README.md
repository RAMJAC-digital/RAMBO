# RAMBO Documentation Hub

_Last updated: 2025-10-06 — Test suite: **551/551** passing — P1 Accuracy Fixes COMPLETE ✅_

---

## Documentation Hierarchy

**🎯 Primary Reference:** [`CLAUDE.md`](../CLAUDE.md) is the **single source of truth** for:
- Test counts and detailed breakdown (lines 50-60)
- Component status and completion (lines 155-313)
- Architecture patterns and design (lines 64-152)
- Current development phase and roadmap (lines 405-471)
- Next actions and priorities (lines 657-692)

**This file (docs/README.md) provides navigation only.** For canonical project information, always refer to CLAUDE.md.

---

## Quick Navigation

| Topic | Purpose | Key Files |
|-------|---------|-----------|
| Getting Started | Build, test, and contributor onboarding | [`README.md`](../README.md), [`AGENTS.md`](../AGENTS.md) |
| Architecture | Deep dives into core subsystems | [`architecture/`](architecture/) — sprites, threading model, video plan |
| API Guides | Public-facing modules | [`api-reference/debugger-api.md`](api-reference/debugger-api.md), [`api-reference/snapshot-api.md`](api-reference/snapshot-api.md) |
| Implementation Status | Task tracking and completion | [`code-review/STATUS.md`](code-review/STATUS.md), [`implementation/completed/`](implementation/completed/) |
| Testing | AccuracyCoin requirements and strategy | [`testing/accuracycoin-cpu-requirements.md`](testing/accuracycoin-cpu-requirements.md) |
| Archived Planning | Historical roadmaps and plans | [`archive/phases/roadmaps/`](archive/phases/roadmaps/), [`archive/p1/planning/`](archive/p1/planning/) |
| Historical Archive | P0 sessions, archived reviews | [`archive/sessions/p0/`](archive/sessions/p0/), [`archive/p0/`](archive/p0/), [`archive/code-review-2025-10-04/`](archive/code-review-2025-10-04/) |

---

## Component Summary

**For detailed test breakdown and component status, see [CLAUDE.md](../CLAUDE.md) lines 50-313.**

Quick links to component documentation:
- **Architecture:** [`architecture/ppu-sprites.md`](architecture/ppu-sprites.md), [`architecture/threading.md`](architecture/threading.md), [`architecture/video-system.md`](architecture/video-system.md)
- **API Guides:** [`api-reference/debugger-api.md`](api-reference/debugger-api.md), [`api-reference/snapshot-api.md`](api-reference/snapshot-api.md)
- **Code Reviews:** [`code-review/CPU.md`](code-review/CPU.md), [`code-review/PPU.md`](code-review/PPU.md), [`code-review/TESTING.md`](code-review/TESTING.md)

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
