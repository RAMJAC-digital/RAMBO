# Documentation Navigation

**Last Updated:** 2025-10-20

This is your guide to RAMBO's documentation. All files listed here are current and accurate.

---

## Quick Links

- 🎯 **[STATUS.md](STATUS.md)** - **Single source of truth** for test counts and component status
- 📘 **[../CLAUDE.md](../CLAUDE.md)** - Primary development reference
- 📖 **[../README.md](../README.md)** - Project overview
- 🚀 **[../QUICK-START.md](../QUICK-START.md)** - Getting started guide
- ⚠️ **[CURRENT-ISSUES.md](CURRENT-ISSUES.md)** - Known bugs and game compatibility

---

## Documentation by Category

### Getting Started
- [README.md](../README.md) - Project overview and features
- [QUICK-START.md](../QUICK-START.md) - Setup and first steps
- [CLAUDE.md](../CLAUDE.md) - Developer reference (build commands, patterns, structure)

### Project Status
- **[STATUS.md](STATUS.md)** ⭐ - **Current test results and component status**
- [CURRENT-ISSUES.md](CURRENT-ISSUES.md) - Known issues and game compatibility
- [FAILING_GAMES_INVESTIGATION.md](FAILING_GAMES_INVESTIGATION.md) - Game-specific debugging

### Architecture
- [ARCHITECTURE.md](../ARCHITECTURE.md) - Core patterns reference (State/Logic, VBlank, DMA)
- [architecture/](architecture/) - Component-specific architecture docs
  - [apu.md](architecture/apu.md) - APU implementation
  - [threading.md](architecture/threading.md) - 3-thread mailbox architecture
  - [codebase-inventory.md](architecture/codebase-inventory.md) - Complete code mapping

### API Reference
- [api-reference/debugger-api.md](api-reference/debugger-api.md) - Debugger API
- [api-reference/snapshot-api.md](api-reference/snapshot-api.md) - Save state API

### Testing
- **[STATUS.md](STATUS.md)** ⭐ - **Current test results**
- [testing/TESTING-README.md](testing/TESTING-README.md) - Test infrastructure
- [testing/accuracycoin-*.md](testing/) - AccuracyCoin test documentation
- [testing/harness.md](testing/harness.md) - Test harness usage

### Implementation Guides
- [implementation/](implementation/) - Feature implementation docs
  - [phase2-dma-refactor.md](implementation/phase2-dma-refactor.md) - DMA implementation
  - [phase2-ppu-fixes.md](implementation/phase2-ppu-fixes.md) - PPU fixes
  - [phase2-summary.md](implementation/phase2-summary.md) - Phase 2 summary

### Visual Documentation
- [dot/](dot/) - GraphViz architecture diagrams
  - [architecture.dot](dot/architecture.dot) - Complete system overview
  - [cpu-module-structure.dot](dot/cpu-module-structure.dot) - CPU subsystem
  - [ppu-module-structure.dot](dot/ppu-module-structure.dot) - PPU subsystem
  - [emulation-coordination.dot](dot/emulation-coordination.dot) - Timing coordination
  - See [dot/README.md](dot/README.md) for complete diagram index

### NES Hardware Reference
- [nesdev/](nesdev/) - NES hardware specifications
  - [nmi.md](nesdev/nmi.md) - NMI interrupt behavior
  - [ppu-frame-timing.md](nesdev/ppu-frame-timing.md) - PPU timing
  - [the-frame-and-nmis.md](nesdev/the-frame-and-nmis.md) - Frame/NMI interaction

### Analysis & Research
- [analysis/](analysis/) - Technical analysis documents
- [reviews/](reviews/) - Code reviews and audits
- [investigations/](investigations/) - Bug investigations

### Development Sessions
- [sessions/](sessions/) - Development session notes
  - Recent: [2025-10-20-accuracy-test-fix.md](sessions/2025-10-20-accuracy-test-fix.md)
  - See directory for complete session history

---

## Archive

- [archive/](archive/) - Outdated documentation preserved for historical reference
  - [archive/outdated-docs/](archive/outdated-docs/) - 2025-10-20 consolidation archive

**⚠️ Archive contents are outdated - do not use for current development**

---

## Documentation Standards

### Single Source of Truth

**Do NOT duplicate these in other files - always link here:**

| Information | Authoritative Source |
|-------------|---------------------|
| Test counts | [STATUS.md](STATUS.md) |
| Component completion status | [STATUS.md](STATUS.md) |
| Current bugs | [STATUS.md](STATUS.md) + [CURRENT-ISSUES.md](CURRENT-ISSUES.md) |
| Build commands | [CLAUDE.md](../CLAUDE.md) |
| Architecture patterns | [ARCHITECTURE.md](../ARCHITECTURE.md) |

### When to Update

- **STATUS.md** - After every test run that changes results
- **CURRENT-ISSUES.md** - When bugs are found or fixed
- **Session docs** - During active development sessions
- **Architecture docs** - When patterns or structure changes

### How to Update STATUS.md

```bash
zig build test
# Update STATUS.md with new test counts
# Update "Last Updated" date
# Commit changes
```

---

## Questions?

- Can't find something? Check [STATUS.md](STATUS.md) first
- Need historical context? See [archive/](archive/)
- Found outdated info? Update it or file an issue

**Last Documentation Audit:** 2025-10-20
