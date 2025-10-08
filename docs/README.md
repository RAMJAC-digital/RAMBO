# RAMBO Documentation Hub

**Last Updated:** 2025-10-07
**Test Status:** 897/900 passing (99.7%)
**Current Phase:** Hardware Accuracy Refinement & Game Testing

---

## Quick Navigation

### For Users

| Document | Purpose |
|----------|---------|
| [**QUICK-START.md**](../QUICK-START.md) | Build, install, and run RAMBO |
| [**README.md**](../README.md) | Project overview and features |
| [**CURRENT-STATUS.md**](CURRENT-STATUS.md) | Detailed implementation status |

### For Developers

| Document | Purpose |
|----------|---------|
| [**CLAUDE.md**](../CLAUDE.md) | **Primary development reference** (architecture, patterns, roadmap) |
| [**CURRENT-STATUS.md**](CURRENT-STATUS.md) | Current implementation status and known issues |
| [**DOCUMENTATION-AUDIT-SUMMARY-2025-10-07.md**](DOCUMENTATION-AUDIT-SUMMARY-2025-10-07.md) | Recent audit findings and cleanup summary |

---

## Documentation Structure

### Active Documentation

```
docs/
├── README.md                          # This file - navigation hub
├── CURRENT-STATUS.md                  # Single source of truth for current status
├── MAILBOX-ARCHITECTURE.md            # Mailbox system design
│
├── architecture/                      # System architecture
│   ├── apu.md                        # APU implementation (86% complete)
│   ├── ppu-sprites.md                # PPU sprite system (complete)
│   └── threading.md                  # Thread model and mailbox communication
│
├── implementation/                    # Current implementation docs
│   ├── video-subsystem.md            # Video system (Wayland + Vulkan, complete)
│   ├── CPU-COMPREHENSIVE-AUDIT-2025-10-07.md
│   ├── HARDWARE-ACCURACY-AUDIT-2025-10-07.md
│   ├── INPUT-SYSTEM-AUDIT-2025-10-07.md
│   ├── PPU-HARDWARE-ACCURACY-AUDIT.md
│   └── design-decisions/             # Architecture decision records
│
├── api-reference/                     # API documentation
│   ├── debugger-api.md
│   └── snapshot-api.md
│
├── testing/                           # Test documentation
│   └── accuracycoin-cpu-requirements.md
│
├── audits/                            # Current audits
│   └── CLAUDE-MD-ACCURACY-AUDIT-2025-10-07.md
│
└── archive/                           # Historical documentation
    ├── completed-phases/              # Archived phase documentation
    │   ├── phase-0/                  # CPU implementation
    │   ├── phase-8-planning/         # Video subsystem planning
    │   └── ...
    ├── audits-historical/            # Old audits
    ├── apu-planning-historical/      # Old APU planning
    └── ...
```

### Root Level Documentation

```
RAMBO/
├── README.md                         # Project overview
├── CLAUDE.md                         # **Primary development reference**
├── QUICK-START.md                    # User quick start guide
├── AGENTS.md                         # AI agent documentation
└── docs/                            # Detailed documentation (see above)
```

---

## Primary References

### 1. CLAUDE.md - Development Guide

**The single source of truth for development.**

**Contains:**
- Project overview and current status
- Architecture patterns (State/Logic separation)
- Component implementation details
- Test status by category
- Known issues and limitations
- Next actions and roadmap
- Development workflow

**Use CLAUDE.md for:**
- Understanding the architecture
- Finding component status
- Learning development patterns
- Planning next work

### 2. CURRENT-STATUS.md - Implementation Status

**Single source of truth for current implementation status.**

**Contains:**
- Completion status by component
- Test coverage breakdown
- Known issues (critical and minor)
- Hardware accuracy verification
- Performance metrics
- Next milestones

**Use CURRENT-STATUS.md for:**
- Quick status checks
- Understanding what's implemented
- Finding known issues
- Checking test coverage

### 3. QUICK-START.md - User Guide

**For end users getting started.**

**Contains:**
- Installation instructions
- Building from source
- Running the emulator
- Controls and keyboard mapping
- Troubleshooting
- Known limitations

**Use QUICK-START.md for:**
- First-time setup
- Running RAMBO
- Solving common problems

---

## Component Documentation

### Architecture

**Location:** `docs/architecture/`

| File | Component | Status |
|------|-----------|--------|
| `apu.md` | Audio Processing Unit | ✅ 86% Complete (logic done, waveform pending) |
| `ppu-sprites.md` | PPU Sprite System | ✅ Complete specification |
| `threading.md` | Thread Architecture | ✅ Complete (3-thread model) |

### Implementation Details

**Location:** `docs/implementation/`

| File | Component | Purpose |
|------|-----------|---------|
| `video-subsystem.md` | Video Display | Complete implementation docs (Wayland + Vulkan) |
| `CPU-COMPREHENSIVE-AUDIT-2025-10-07.md` | CPU | Recent CPU audit findings |
| `HARDWARE-ACCURACY-AUDIT-2025-10-07.md` | All Components | Hardware accuracy verification |
| `INPUT-SYSTEM-AUDIT-2025-10-07.md` | Input System | Input system audit and fixes |
| `PPU-HARDWARE-ACCURACY-AUDIT.md` | PPU | PPU hardware accuracy audit |

### Design Decisions

**Location:** `docs/implementation/design-decisions/`

Documents explaining architectural choices:
- `6502-hardware-timing-quirks.md` - CPU timing edge cases
- `async-io-architecture.md` - Async I/O design
- `cpu-execution-architecture.md` - CPU execution model
- `final-hybrid-architecture.md` - State/Logic pattern
- `memory-bus-implementation.md` - Bus architecture
- `ppu-rendering-architecture.md` - PPU rendering pipeline

### API Reference

**Location:** `docs/api-reference/`

| File | Component |
|------|-----------|
| `debugger-api.md` | Debugger API and usage |
| `snapshot-api.md` | Save state API |

---

## Component Status Quick Reference

For full details, see [CURRENT-STATUS.md](CURRENT-STATUS.md).

| Component | Completion | Tests | Notes |
|-----------|------------|-------|-------|
| CPU (6502) | 100% | ~280 | All 256 opcodes, cycle-accurate |
| PPU | 100% | ~90 | Background + sprites complete |
| APU | 86% | 135 | Logic done, waveform generation pending |
| Video Display | 100% | - | Wayland + Vulkan at 60 FPS |
| Controller I/O | 100% | 14 | Hardware-accurate 4021 shift register |
| Input System | 100% | 40 | Keyboard mapping complete |
| Threading | 100% | 14 | 3-thread model with mailboxes |
| Debugger | 100% | ~66 | Breakpoints, watchpoints, callbacks |
| Cartridge (Mapper 0) | 100% | ~48 | NROM complete, more mappers planned |

---

## Recent Changes (2025-10-07)

### Documentation Cleanup

**Major Reorganization:**
- ✅ Consolidated video subsystem docs (8 → 1)
- ✅ Consolidated audit docs (20+ → 1)
- ✅ Consolidated APU docs (6 → 1)
- ✅ Created CURRENT-STATUS.md (single source of truth)
- ✅ Created QUICK-START.md (user guide)
- ✅ Archived all completed phase documentation
- ✅ Archived historical audits and planning docs

**Documentation Now:**
- Cleaner structure (60 active docs vs 182 before)
- No duplicates
- Current state only (no outdated planning docs in active area)
- Easy navigation

### Code Updates

- ✅ Fixed threading test compilation error
- ✅ Updated CLAUDE.md with accurate test counts (897/900)
- ✅ Fixed 8 critical CLAUDE.md inaccuracies
- ✅ Removed all legacy references

### Test Status

**Before:** 885/886 passing
**Now:** 897/900 passing
**Change:** +12 tests (threading tests now compile and run)

---

## Finding Information

### "I want to..."

**...build and run RAMBO**
→ [QUICK-START.md](../QUICK-START.md)

**...understand the architecture**
→ [CLAUDE.md](../CLAUDE.md) sections on Architecture

**...know what's implemented**
→ [CURRENT-STATUS.md](CURRENT-STATUS.md)

**...add a new feature**
→ [CLAUDE.md](../CLAUDE.md) for patterns, then relevant component docs

**...fix a bug**
→ [CURRENT-STATUS.md](CURRENT-STATUS.md) for known issues, then component docs

**...write tests**
→ [CLAUDE.md](../CLAUDE.md) testing section, existing test files as examples

**...use the debugger**
→ [docs/api-reference/debugger-api.md](api-reference/debugger-api.md)

**...understand the PPU**
→ [docs/architecture/ppu-sprites.md](architecture/ppu-sprites.md)

**...understand threading**
→ [docs/architecture/threading.md](architecture/threading.md)

**...understand the video system**
→ [docs/implementation/video-subsystem.md](implementation/video-subsystem.md)

---

## Contributing

### Before Making Changes

1. Read [CLAUDE.md](../CLAUDE.md) for architecture patterns
2. Check [CURRENT-STATUS.md](CURRENT-STATUS.md) for current state
3. Run `zig build test` to verify tests pass
4. Review relevant component documentation

### Making Changes

1. Follow State/Logic pattern (see CLAUDE.md)
2. Write tests for new functionality
3. Update documentation with code changes
4. Ensure all tests pass
5. Update CURRENT-STATUS.md if needed

### Documentation Guidelines

1. **Keep CURRENT-STATUS.md up to date** - Single source of truth
2. **Update CLAUDE.md for major changes** - Primary reference
3. **Create/update component docs** - In appropriate directories
4. **Archive completed work** - Move to `docs/archive/completed-phases/`
5. **No duplicates** - One source of truth per topic

---

## Archives

Historical documentation is preserved in `docs/archive/`:

| Directory | Content |
|-----------|---------|
| `completed-phases/` | Completed phase documentation (Phase 0-8) |
| `audits-historical/` | Historical audits (pre-2025-10-07) |
| `apu-planning-historical/` | Old APU planning documents |
| `sessions/` | Development session notes |
| `p0/`, `p1/` | Phase 0 and Phase 1 completion docs |
| `code-review-2025-10-04/` | Old code review (archived) |

**Archives are for reference only** - all current information is in active docs.

---

## Need Help?

### Resources

- **Quick Start:** [QUICK-START.md](../QUICK-START.md)
- **Status:** [CURRENT-STATUS.md](CURRENT-STATUS.md)
- **Development:** [CLAUDE.md](../CLAUDE.md)
- **Issues:** Check known issues in CURRENT-STATUS.md

### Getting Support

1. Check QUICK-START.md troubleshooting section
2. Review CURRENT-STATUS.md known issues
3. Search existing documentation
4. Create issue with full details (system info, ROM, error messages)

---

**Documentation Last Audited:** 2025-10-07
**Next Audit:** After major feature completion

Happy emulating!
