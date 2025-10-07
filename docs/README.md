# RAMBO Documentation Hub

_Last updated: 2025-10-07 — Test suite: **887/889** passing — Input System Phase 2 COMPLETE ✅_

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
| ROM Toolchain | Assemble AccuracyCoin / future test ROMs | [`compiler/README.md`](../compiler/README.md), [`compiler/docs/microsoft-basic-port-plan.md`](../compiler/docs/microsoft-basic-port-plan.md), [`compiler/docs/macro-expansion-design.md`](../compiler/docs/macro-expansion-design.md) |
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
- **Input System:** [`implementation/INPUT-SYSTEM-DESIGN.md`](implementation/INPUT-SYSTEM-DESIGN.md), [`implementation/INPUT-SYSTEM-TEST-COVERAGE.md`](implementation/INPUT-SYSTEM-TEST-COVERAGE.md)
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

## Recent Documentation Changes (2025-10-07)

**Input System Phase 2 Complete (ButtonState + KeyboardMapper):**
- ✅ **ButtonState Implementation** - NES controller state (8 buttons packed into 1 byte, 21 tests passing)
- ✅ **KeyboardMapper Implementation** - Wayland keyboard events → NES buttons (24 tests passing)
- ✅ **45 Unit Tests PASSING** - Full API coverage for both components
- ✅ **Test Scaffolds Ready** - 22 integration tests for main thread wiring
- ✅ **Comprehensive Documentation** - Design doc (505 lines) + test coverage report (391 lines)
- ✅ **CLAUDE.md Updated** - Input System section updated (lines 437-496)
- ✅ 887/889 tests passing (99.8%, +25 tests from Phase 1)

**Recent Changes (2025-10-06):**
- ✅ **Mapper System Foundation** - AnyCartridge union, IRQ infrastructure
- ✅ **AccuracyCoin PASSING** - Full CPU/PPU validation ($00 $00 $00 $00 status)
- ✅ 560/561 tests → 862/864 tests (mapper + input system)

**Documentation Cleanup:**
- Archived outdated APU planning docs to `archive/apu-planning/`
- Archived Phase 1.5 docs to `archive/phase-1.5/`
- Archived gap analyses and audits to `archive/audits-2025-10-06/`
- Moved mapper summary to `implementation/MAPPER-SYSTEM-SUMMARY.md`
- Updated all high-level docs with mapper system completion

**Phase 0 & P1 Complete:**
- ✅ All 256 CPU opcodes implemented with cycle-accurate timing
- ✅ Fixed +1 cycle deviation for indexed addressing modes
- ✅ P1 accuracy fixes (unstable opcodes, OAM DMA)
- ✅ Phase 0 session docs archived to `archive/sessions/p0/`
- ✅ Timing fix completion documented in `archive/p0/P0-TIMING-FIX-COMPLETION-2025-10-06.md`

---

## Need Help?

- **Slack / ChatOps:** Refer to the team channel `#rambo-dev` (internal) for coordination.
- **Issues & Tasks:** Track progress in the project board linked from `STATUS.md`.
- **Testing:** Always run `zig build --summary all test` before submitting changes; the command is documented in the root README and produces step-by-step counts.

Happy emulating!
