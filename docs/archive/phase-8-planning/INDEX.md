# RAMBO Documentation Index

**Last Updated:** 2025-10-06
**Status:** 571/571 tests passing (100%)

---

## 🎯 START HERE - Primary References

### For Wayland/Vulkan Development

**📘 [`COMPLETE-ARCHITECTURE-AND-PLAN.md`](COMPLETE-ARCHITECTURE-AND-PLAN.md)** ← **AUTHORITATIVE**
- Complete architecture with zero outstanding questions
- Library usage (libxev, std.Thread, zig-wayland, Vulkan)
- 8 mailboxes with synchronization primitives specified
- 3-thread architecture (Main, Emulation, Render)
- 5-phase development plan (40-54 hours)
- **Read this first for Wayland development**

**📘 [`MAILBOX-ARCHITECTURE.md`](MAILBOX-ARCHITECTURE.md)** ← **REFERENCE**
- Detailed mailbox specifications
- Communication flows
- XDG protocol isolation
- Example code patterns
- **Companion to COMPLETE-ARCHITECTURE-AND-PLAN.md**

### For Current Codebase Understanding

**📘 [`CLAUDE.md`](../CLAUDE.md)** ← **DEVELOPMENT GUIDE**
- Current status (571/571 tests, AccuracyCoin passing)
- Component breakdown (CPU, PPU, Bus, Debugger, Controller I/O)
- State/Logic architecture pattern
- Test organization
- Next actions and priorities
- **Primary guide for contributors**

**📘 [`README.md`](../README.md)** ← **PROJECT OVERVIEW**
- Quick start (build, test, run)
- Feature status
- Architecture highlights
- Performance metrics
- Critical path to playability

---

## 📂 Active Documentation (By Category)

### Code Review & Status
- **[`code-review/STATUS.md`](code-review/STATUS.md)** - Current implementation status
- **[`code-review/CPU.md`](code-review/CPU.md)** - CPU implementation review
- **[`code-review/PPU.md`](code-review/PPU.md)** - PPU implementation review
- **[`code-review/MEMORY_AND_BUS.md`](code-review/MEMORY_AND_BUS.md)** - Memory/Bus review
- **[`code-review/ASYNC_AND_IO.md`](code-review/ASYNC_AND_IO.md)** - libxev integration review
- **[`code-review/TESTING.md`](code-review/TESTING.md)** - Test strategy
- **[`code-review/CODE_SAFETY.md`](code-review/CODE_SAFETY.md)** - Safety practices
- **[`code-review/CONFIGURATION.md`](code-review/CONFIGURATION.md)** - Config system

### Architecture Deep Dives
- **[`architecture/ppu-sprites.md`](architecture/ppu-sprites.md)** - Complete sprite rendering spec
- **[`architecture/threading.md`](architecture/threading.md)** - Mailbox pattern architecture
- **[`architecture/apu-*.md`](architecture/)** - APU planning (future phase)

### API Reference
- **[`api-reference/debugger-api.md`](api-reference/debugger-api.md)** - Debugger API guide
- **[`api-reference/snapshot-api.md`](api-reference/snapshot-api.md)** - Snapshot API guide

### Implementation Guides
- **[`implementation/STATUS.md`](implementation/STATUS.md)** - Implementation tracking
- **[`implementation/design-decisions/`](implementation/design-decisions/)** - Design rationale
  - `final-hybrid-architecture.md` - State/Logic pattern
  - `cpu-execution-architecture.md` - CPU microsteps
  - `ppu-rendering-architecture.md` - PPU rendering
  - `async-io-architecture.md` - libxev integration
  - `6502-hardware-timing-quirks.md` - Hardware accuracy

### Testing
- **[`testing/accuracycoin-cpu-requirements.md`](testing/accuracycoin-cpu-requirements.md)** - Test ROM requirements
- **[`testing/FUZZING-STATIC-ANALYSIS.md`](testing/FUZZING-STATIC-ANALYSIS.md)** - Advanced testing

### Completed Work
- **[`implementation/completed/`](implementation/completed/)** - Completion summaries
  - `MAPPER-FOUNDATION-ACCURACYCOIN-2025-10-06.md` - Mapper system
  - `P1-TASKS-1.1-1.2-COMPLETION-2025-10-06.md` - P1 accuracy fixes
  - `P1-TASK-1.2-OAM-DMA-COMPLETION.md` - OAM DMA implementation

---

## 🗂️ Archived Documentation

All historical, superseded, or completed phase documentation is in [`archive/`](archive/):

- **`archive/wayland-planning-2025-10-06/`** - Superseded Wayland plans (3 iterations)
- **`archive/audits-general/`** - General audit documents from 2025-10-06
- **`archive/audits-2025-10-06/`** - Specific audits (PRG-RAM, runtime)
- **`archive/audits/`** - Documentation audit history
- **`archive/p0/`** - Phase 0 completion docs
- **`archive/p1/`** - Phase 1 (P1) completion docs
- **`archive/phase-1.5/`** - Phase 1.5 intermediate work
- **`archive/sessions/`** - Development session notes
  - `sessions/p0/` - Phase 0 session history
  - `sessions/controller-io/` - Controller I/O implementation
- **`archive/apu-planning/`** - APU implementation planning (future phase)
- **`archive/code-review-2025-10-04/`** - Historical code review
- **`archive/code-review/archive/2025-10-05/`** - Code review snapshots
- **`archive/phases/`** - Phase documentation
- **`archive/video-*.md`** - Video subsystem planning history

---

## 📋 Documentation Hierarchy

```
Priority 1 (Read First):
├── COMPLETE-ARCHITECTURE-AND-PLAN.md  ← Wayland/Vulkan development
├── MAILBOX-ARCHITECTURE.md            ← Mailbox specifications
├── ../CLAUDE.md                       ← Development guide
└── ../README.md                       ← Project overview

Priority 2 (Reference):
├── code-review/                       ← Implementation reviews
├── architecture/                      ← Deep dives
├── api-reference/                     ← API docs
└── implementation/                    ← Design decisions

Priority 3 (Historical):
└── archive/                           ← Completed/superseded docs
```

---

## 🚀 Quick Links by Task

### I want to implement Wayland/Vulkan
1. Read [`COMPLETE-ARCHITECTURE-AND-PLAN.md`](COMPLETE-ARCHITECTURE-AND-PLAN.md)
2. Read [`MAILBOX-ARCHITECTURE.md`](MAILBOX-ARCHITECTURE.md)
3. Start Phase 0: Mailbox implementation

### I want to understand the emulator
1. Read [`../CLAUDE.md`](../CLAUDE.md) - Development guide
2. Read [`../README.md`](../README.md) - Project overview
3. Browse [`code-review/`](code-review/) - Component reviews

### I want to understand State/Logic pattern
1. Read [`implementation/design-decisions/final-hybrid-architecture.md`](implementation/design-decisions/final-hybrid-architecture.md)
2. Read [`code-review/CPU.md`](code-review/CPU.md) - Example implementation
3. Review actual code: `src/cpu/State.zig`, `src/cpu/Logic.zig`

### I want to add a new feature
1. Read [`../CLAUDE.md`](../CLAUDE.md) - Current status and priorities
2. Check [`implementation/STATUS.md`](implementation/STATUS.md) - Implementation tracking
3. Follow State/Logic pattern from existing components

### I want to understand threading/mailboxes
1. **Phase 8 (Planned):** Read [`COMPLETE-ARCHITECTURE-AND-PLAN.md`](COMPLETE-ARCHITECTURE-AND-PLAN.md) - Authoritative 3-thread architecture
2. **Phase 8 (Planned):** Read [`MAILBOX-ARCHITECTURE.md`](MAILBOX-ARCHITECTURE.md) - All 8 mailboxes with specs
3. **Phase 6 (Current):** Read [`architecture/threading.md`](architecture/threading.md) - Current 2-thread implementation
4. Read [`code-review/ASYNC_AND_IO.md`](code-review/ASYNC_AND_IO.md) - libxev integration

### I want to run tests
1. Read [`../README.md`](../README.md) - Quick start
2. Read [`code-review/TESTING.md`](code-review/TESTING.md) - Test organization
3. Run `zig build test` - Should see 571/571 passing

---

## 📝 Documentation Guidelines

### When to Archive
- Document is superseded by newer version
- Phase is completed
- Information is historical but useful for reference
- Multiple iterations of same topic exist

### When to Keep Active
- Document is current authoritative source
- Document is actively referenced by code
- Document describes current system state
- Document guides ongoing development

### Single Source of Truth
- Wayland/Vulkan: `COMPLETE-ARCHITECTURE-AND-PLAN.md`
- Current Status: `../CLAUDE.md`
- Project Overview: `../README.md`
- Mailboxes: `MAILBOX-ARCHITECTURE.md`
- Each component: Respective `code-review/*.md`

### No Redundancy
- Information appears in ONE place
- Other documents reference the authoritative source
- Updates happen in single location

---

## 🔍 Finding Information

**Use this decision tree:**

```
Question: "How do I implement X?"
├─ X = Wayland/Vulkan?
│  └─ Read COMPLETE-ARCHITECTURE-AND-PLAN.md
├─ X = Mailbox communication?
│  └─ Read MAILBOX-ARCHITECTURE.md
├─ X = New feature in existing component?
│  └─ Read ../CLAUDE.md, then code-review/{component}.md
├─ X = Understand existing code?
│  └─ Read code-review/{component}.md
└─ X = Historical context?
   └─ Check archive/{topic}/
```

---

## ✅ Documentation Coverage Checklist

- ✅ **Architecture** - Comprehensive (COMPLETE-ARCHITECTURE-AND-PLAN.md)
- ✅ **Mailboxes** - Detailed (MAILBOX-ARCHITECTURE.md)
- ✅ **Threading** - Documented (architecture/threading.md)
- ✅ **libxev Usage** - Specified (COMPLETE-ARCHITECTURE-AND-PLAN.md)
- ✅ **State/Logic Pattern** - Documented (implementation/design-decisions/)
- ✅ **CPU** - Reviewed (code-review/CPU.md)
- ✅ **PPU** - Reviewed (code-review/PPU.md)
- ✅ **Bus** - Reviewed (code-review/MEMORY_AND_BUS.md)
- ✅ **Debugger** - API documented (api-reference/debugger-api.md)
- ✅ **Testing** - Strategy documented (code-review/TESTING.md)
- ✅ **Development Plan** - 5 phases detailed (COMPLETE-ARCHITECTURE-AND-PLAN.md)
- ✅ **No Gaps** - All active components documented
- ✅ **No Conflicts** - Superseded docs archived
- ✅ **No Redundancy** - Single source of truth for each topic

---

**Last Review:** 2025-10-06
**Next Review:** After Phase 0 completion
**Status:** Ready for Phase 0 implementation
