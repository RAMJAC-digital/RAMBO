# RAMBO Documentation Hub

**Last Updated:** 2025-10-13 (Phase 6 Documentation Remediation Complete)
**Test Status:** 930/966 passing (96.3%)
**Documentation Audit:** ✅ Completed 2025-10-11, remediated 2025-10-13 (see archive/2025-10/audits/)

---

## Quick Navigation

### For Users

| Document | Purpose |
|----------|---------|
| [**QUICK-START.md**](../QUICK-START.md) | Build, install, and run RAMBO |
| [**README.md**](../README.md) | Project overview and features |
| [**CURRENT-STATUS.md**](CURRENT-STATUS.md) | Detailed implementation status |
| [**KNOWN-ISSUES.md**](KNOWN-ISSUES.md) | Current bugs and investigations |

### For Developers

| Document | Purpose |
|----------|---------|
| [**CLAUDE.md**](../CLAUDE.md) | **Primary development reference** (architecture, patterns, roadmap) |
| [**CURRENT-STATUS.md**](CURRENT-STATUS.md) | Current implementation status and known issues |
| [**sessions/**](sessions/) | Development session notes and investigations |

---

## Documentation Structure

### Active Documentation

```
docs/
├── README.md                          # This file - navigation hub
├── KNOWN-ISSUES.md                    # Current bugs and investigations
├── CODE-REVIEW-REMEDIATION-PLAN.md    # Phase 1-7 remediation tracking
│
├── sessions/                          # Active session documentation
│   ├── debugger-quick-start.md        # Debugger usage guide (active)
│   ├── smb-investigation-plan.md      # Super Mario Bros debugging (active)
│   └── smb-nmi-handler-investigation.md  # SMB NMI analysis (active)
│
├── architecture/                      # System architecture
│   ├── apu.md                        # APU implementation (85% Phase 5 complete)
│   ├── ppu-sprites.md                # PPU sprite system (complete)
│   ├── codebase-inventory.md         # Complete file structure inventory
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
    ├── sessions-2025-10-09-10/       # Oct 9-10 VBlank investigation (27 files)
    ├── graphviz-audits/              # GraphViz audit artifacts (8 files)
    ├── completed-phases/             # Archived phase documentation
    └── [Other historical archives]
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

## Recent Changes (2025-10-09)

### Hardware Accuracy Fixes

**Latest Session (2025-10-09):**
- ✅ Fixed BRK flag masking bug (hardware interrupts now clear bit 4 correctly)
- ✅ Fixed frame pacing precision (16ms → 17ms rounding for NTSC timing)
- ✅ Fixed background fine_x panic (masked to 3 bits)
- ✅ Fixed debugger output (handleCpuSnapshot now functional)
- 🔄 Investigating Super Mario Bros blank screen (root cause identified)

See **[Session Summary](sessions/session-summary-2025-10-09.md)** for complete details.

### Documentation Updates (2025-10-11)

**Latest:**
- ✅ Comprehensive documentation audit completed (100% accuracy achieved)
- ✅ Updated all test counts to 949/986 (was 955/967 in 9 locations)
- ✅ Fixed architecture.dot mailbox count (9→7, identified 4 orphaned files)
- ✅ Added 19 missing debugger API methods to debugger-api.md
- ✅ Verified all GraphViz diagrams (95-98% accuracy)
- ✅ Updated VBlank migration documentation in ppu-module-structure.dot
- ✅ See: archive/2025-10/audits/DOCUMENTATION-AUDIT-FINAL-REPORT-2025-10-11.md for complete details

**Previous (2025-10-09):**
- ✅ Updated CLAUDE.md with test counts
- ✅ Updated README.md with recent fixes and current focus
- ✅ Updated KNOWN-ISSUES.md with SMB investigation
- ✅ Updated docs/README.md navigation
- ✅ Created comprehensive session documentation in docs/sessions/

**Previous Cleanup (2025-10-08):**
- ✅ Archived dated audit files from docs/implementation/ (13 files)
- ✅ Archived Phase 8 planning docs
- ✅ Top-level docs clean (only README.md and CURRENT-STATUS.md)

### Test Status

**Latest:** 949/986 passing (96.2%)
**Previous:** 920/926 passing (99.4%)

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
→ [docs/sessions/debugger-quick-start.md](sessions/debugger-quick-start.md) (Quick start)
→ [docs/api-reference/debugger-api.md](api-reference/debugger-api.md) (Full API)

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

**Documentation Last Audited:** 2025-10-11
**Audit Status:** ✅ Comprehensive audit completed
**See:** archive/2025-10/audits/DOCUMENTATION-AUDIT-2025-10-11.md for complete findings

Happy emulating!
