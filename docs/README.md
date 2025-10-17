# RAMBO Documentation Hub

**Welcome to the RAMBO NES Emulator documentation!**

This is your central navigation point for all project documentation.

**Last Updated:** 2025-10-17 (Documentation Reorganization Complete)
**Test Status:** 1027/1032 passing (99.5%), 5 skipped
**Project Status:** Phase 2 complete, MMC3 mapper investigation next

---

## Quick Start

### For Users

| Document | Purpose |
|----------|---------|
| [README.md](../README.md) | Project overview and features |
| [QUICK-START.md](../QUICK-START.md) | Build, install, and run RAMBO |
| [CURRENT-ISSUES.md](CURRENT-ISSUES.md) | Current bugs and known issues |

### For Developers

| Document | Purpose |
|----------|---------|
| [CLAUDE.md](../CLAUDE.md) | Primary development reference (build commands, workflow) |
| [ARCHITECTURE.md](../ARCHITECTURE.md) | Core patterns reference (State/Logic, VBlank, DMA) |
| [Implementation Guides](implementation/) | Detailed implementation documentation |
| [Architecture Diagrams](dot/) | Visual system architecture (GraphViz) |

---

## Documentation Structure

```
docs/
├── README.md                    # This file - central navigation
├── CURRENT-ISSUES.md            # Active bugs and known issues
│
├── implementation/              # Implementation guides
│   ├── phase2-summary.md        # Phase 2 high-level summary
│   ├── phase2-ppu-fixes.md      # PPU rendering fixes (2A-2D)
│   └── phase2-dma-refactor.md   # DMA architectural refactor (2E)
│
├── architecture/                # System architecture
│   ├── apu.md                   # APU implementation details
│   ├── ppu-sprites.md           # PPU sprite system
│   ├── threading.md             # Thread model and mailboxes
│   └── codebase-inventory.md   # Complete file structure
│
├── dot/                         # GraphViz architecture diagrams
│   ├── README.md                # Diagram generation guide
│   ├── architecture.dot         # Complete 3-thread architecture
│   ├── emulation-coordination.dot   # RT loop coordination
│   ├── cpu-module-structure.dot     # 6502 complete subsystem
│   ├── ppu-module-structure.dot     # 2C02 rendering pipeline
│   ├── apu-module-structure.dot     # APU 5-channel audio
│   └── dma-time-sharing-architecture.dot  # DMC/OAM DMA system
│
├── api-reference/               # API documentation
│   ├── debugger-api.md
│   └── snapshot-api.md
│
├── testing/                     # Test documentation
│   ├── accuracycoin-cpu-requirements.md
│   ├── dmc-oam-dma-test-strategy.md
│   └── harness.md
│
├── nesdev/                      # NES hardware references (offline)
│   ├── nmi.md
│   ├── ppu-frame-timing.md
│   └── the-frame-and-nmis.md
│
├── zig/                         # Zig language references (offline)
│   └── 0.15.1/                  # Zig 0.15.1 documentation
│
├── reviews/                     # Comprehensive reviews
│   └── phase2-comprehensive-review-2025-10-17.md
│
├── sessions/                    # Active session documentation
│   └── [Current development sessions]
│
└── archive/                     # Historical documentation
    └── sessions-phase2/         # Phase 2 session docs (24 files)
```

---

## Primary References

### 1. CLAUDE.md - Development Guide

**Location:** [CLAUDE.md](../CLAUDE.md)

**The single source of truth for development.**

**Contains:**
- Project overview and current status
- Build commands and workflow
- Component structure
- Critical hardware behaviors
- Test coverage summary
- Known issues and limitations

**Use CLAUDE.md for:**
- Building and running RAMBO
- Understanding project structure
- Finding component locations
- Checking current test status
- Learning development workflow

### 2. ARCHITECTURE.md - Pattern Reference

**Location:** [ARCHITECTURE.md](../ARCHITECTURE.md)

**Quick reference for core architectural patterns.**

**Contains:**
- State/Logic Separation Pattern
- Comptime Generics (Zero-Cost Polymorphism)
- Thread Architecture
- VBlank Pattern (Pure Data Ledgers)
- DMA Interaction Model
- RT-Safety Guidelines

**Use ARCHITECTURE.md for:**
- Understanding design patterns
- Following established conventions
- Implementing new features consistently
- Architectural decision reference

### 3. Implementation Guides

**Location:** [docs/implementation/](implementation/)

**Detailed guides for major implementations.**

**Available Guides:**
- [Phase 2 Summary](implementation/phase2-summary.md) - High-level overview
- [PPU Fixes](implementation/phase2-ppu-fixes.md) - Phases 2A-2D detailed
- [DMA Refactor](implementation/phase2-dma-refactor.md) - Phase 2E detailed

**Use Implementation Guides for:**
- Understanding implementation decisions
- Learning from past work
- Planning similar refactors
- Technical deep-dives

### 4. Architecture Diagrams

**Location:** [docs/dot/](dot/)

**Visual maps of entire codebase.**

**Key Diagrams:**
- `architecture.dot` - Complete 3-thread architecture (60 nodes)
- `emulation-coordination.dot` - RT loop coordination (80 nodes)
- `cpu-module-structure.dot` - 6502 complete subsystem (50 nodes)
- `ppu-module-structure.dot` - 2C02 rendering pipeline (60 nodes)
- `apu-module-structure.dot` - APU 5-channel audio (60 nodes)
- `dma-time-sharing-architecture.dot` - DMC/OAM DMA system (40 nodes)

**How to use:**
1. Start with `architecture.dot` for high-level overview
2. Dive into specific module diagrams as needed
3. Reference during code navigation
4. Generate images: `cd docs/dot && dot -Tpng <file>.dot -o <file>.png`

---

## Component Documentation

### Core Emulation

| Component | Documentation |
|-----------|---------------|
| CPU (6502) | [cpu-module-structure.dot](dot/cpu-module-structure.dot) |
| PPU (2C02) | [ppu-sprites.md](architecture/ppu-sprites.md), [ppu-module-structure.dot](dot/ppu-module-structure.dot) |
| APU | [apu.md](architecture/apu.md), [apu-module-structure.dot](dot/apu-module-structure.dot) |

### Systems

| System | Documentation |
|--------|---------------|
| Threading | [threading.md](architecture/threading.md) |
| DMA | [phase2-dma-refactor.md](implementation/phase2-dma-refactor.md), [dma-time-sharing-architecture.dot](dot/dma-time-sharing-architecture.dot) |
| Debugger | [debugger-api.md](api-reference/debugger-api.md), [debugger-quick-start.md](sessions/debugger-quick-start.md) |
| Cartridge | [cartridge-mailbox-systems.dot](dot/cartridge-mailbox-systems.dot) |

---

## Finding Information

### "I want to..."

**...build and run RAMBO**
→ [QUICK-START.md](../QUICK-START.md)

**...understand the architecture**
→ [ARCHITECTURE.md](../ARCHITECTURE.md) + [architecture.dot](dot/architecture.dot)

**...know what's implemented**
→ [CLAUDE.md](../CLAUDE.md) (Component Structure section)

**...add a new feature**
→ [ARCHITECTURE.md](../ARCHITECTURE.md) for patterns, then relevant component docs

**...fix a bug**
→ [CURRENT-ISSUES.md](CURRENT-ISSUES.md) for known issues, then component docs

**...write tests**
→ [CLAUDE.md](../CLAUDE.md) testing section, existing test files as examples

**...use the debugger**
→ [debugger-quick-start.md](sessions/debugger-quick-start.md) + [debugger-api.md](api-reference/debugger-api.md)

**...understand PPU rendering**
→ [ppu-sprites.md](architecture/ppu-sprites.md) + [ppu-module-structure.dot](dot/ppu-module-structure.dot)

**...understand threading**
→ [threading.md](architecture/threading.md) + [architecture.dot](dot/architecture.dot)

**...learn about Phase 2 work**
→ [phase2-summary.md](implementation/phase2-summary.md)

---

## Current Status

### Project Metrics

**Tests:** 1027/1032 passing (99.5%), 5 skipped
**AccuracyCoin:** ✅ PASSING (baseline CPU validation)
**Code Quality:** 94/100 (Excellent)
**Performance:** 10-50x real-time speed

### Recent Major Work

**Phase 2 Complete (2025-10-15 to 2025-10-17):**
- ✅ PPU rendering timing fixes (Phases 2A-2D)
- ✅ DMA system architectural refactor (Phase 2E)
- ✅ +37 tests passing
- ✅ -700 lines of code (58% reduction in DMA)
- ✅ +5-10% performance improvement

**See:** [phase2-summary.md](implementation/phase2-summary.md)

### Current Issues

**Fully Working:**
- ✅ Castlevania, Mega Man, Kid Icarus, Battletoads, SMB2, SMB1 (all NROM games)

**Partial Issues (MMC3 Mapper):**
- ⚠️ SMB3, Kirby's Adventure, TMNT (all MMC3 games)

**Next Focus:**
- MMC3 mapper investigation (separate from Phase 2)
- Test coverage improvements

**See:** [CURRENT-ISSUES.md](CURRENT-ISSUES.md) for complete details

---

## Contributing

### Before Making Changes

1. Read [CLAUDE.md](../CLAUDE.md) for workflow and structure
2. Read [ARCHITECTURE.md](../ARCHITECTURE.md) for patterns
3. Run `zig build test` to verify tests pass
4. Review relevant component documentation

### Making Changes

1. Follow State/Logic pattern (see [ARCHITECTURE.md](../ARCHITECTURE.md))
2. Write tests for new functionality
3. Update documentation with code changes
4. Ensure all tests pass
5. Create session notes if significant work

### Documentation Guidelines

1. **Update CLAUDE.md for major changes** - Primary reference
2. **Create/update component docs** - In appropriate directories
3. **Add session docs for investigations** - In `docs/sessions/`
4. **Archive completed work** - Move to `docs/archive/` when superseded
5. **Follow existing patterns** - Consistency is key

---

## External References

### NES Hardware

- [NESDev Wiki](https://www.nesdev.org/wiki/) - Comprehensive NES documentation
- [6502 Reference](http://www.6502.org/) - CPU architecture
- [PPU Rendering](https://www.nesdev.org/wiki/PPU_rendering) - PPU details

**Offline Snapshots:** [docs/nesdev/](nesdev/)

### Zig Resources

- [Zig Language Reference](https://ziglang.org/documentation/master/)
- [Zig Standard Library](https://ziglang.org/documentation/master/std/)

**Offline Snapshots:** [docs/zig/0.15.1/](zig/0.15.1/)

---

## Archives

Historical documentation preserved in [docs/archive/](archive/):

| Directory | Content |
|-----------|---------|
| `sessions-phase2/` | Phase 2 session docs (24 files, Oct 15-17 2025) |
| `2025-10/` | October 2025 historical docs (audits, investigations) |
| `sessions-2025-10-09-10/` | Early October session docs (36 files) |
| `sessions-2025-10-12/` | Mid-October session docs (11 files) |
| `graphviz-audits/` | GraphViz diagram audit sessions |

**Archives are for reference only** - all current information is in active docs.

---

## Documentation Conventions

### File Naming

- **Dates:** Use ISO 8601 format (YYYY-MM-DD)
- **Session docs:** `YYYY-MM-DD-topic-description.md`
- **Component docs:** `component-name.md` (lowercase, hyphenated)
- **Diagrams:** `component-name.dot` or `concept-name.dot`

### Document Structure

- **Title:** Single H1 at top
- **Metadata:** Date, status, author (if applicable)
- **Table of Contents:** For docs > 200 lines
- **Code Examples:** Use zig syntax highlighting
- **Links:** Relative paths preferred
- **Updates:** Note date and summary at document end

### Markdown Style

- **Headings:** Use ATX-style (#, ##, ###)
- **Lists:** Use - for unordered, 1. for ordered
- **Code:** Use triple backticks with language
- **Tables:** Use for structured data
- **Bold:** Use ** for emphasis
- **Italics:** Use * for definitions/terms

---

## Need Help?

### Resources

- **Quick Start:** [QUICK-START.md](../QUICK-START.md)
- **Development:** [CLAUDE.md](../CLAUDE.md)
- **Patterns:** [ARCHITECTURE.md](../ARCHITECTURE.md)
- **Issues:** [CURRENT-ISSUES.md](CURRENT-ISSUES.md)

### Getting Support

1. Check [QUICK-START.md](../QUICK-START.md) troubleshooting section
2. Review [CURRENT-ISSUES.md](CURRENT-ISSUES.md) for known issues
3. Search existing documentation
4. Create issue with full details (system info, ROM, error messages)

---

## Documentation History

**2025-10-17:** Major documentation reorganization
- Created [ARCHITECTURE.md](../ARCHITECTURE.md) with core patterns
- Consolidated Phase 2 docs into [implementation/](implementation/)
- Archived 24 Phase 2 session docs
- Reorganized GraphViz diagrams
- Created this comprehensive navigation hub

**2025-10-15:** Phase 2 documentation updates
- Added Phase 2A-2D session documentation
- Updated [CURRENT-ISSUES.md](CURRENT-ISSUES.md)

**2025-10-13:** Initial structure created
- Created documentation hub
- Organized component docs
- Established archive structure

---

**Key Principle:** Documentation should make development easier, not harder. Keep it organized, up-to-date, and easy to navigate.

**Version:** 2.0
**Last Updated:** 2025-10-17
**Next Review:** After MMC3 mapper work complete

Happy emulating!
