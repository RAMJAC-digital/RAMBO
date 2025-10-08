# Documentation Cleanup Action Plan
**Date:** 2025-10-07
**Status:** Ready for Execution
**Estimated Time:** 20-26 hours total

---

## ✅ Completed This Session (1.25 hours)

1. ✅ **Comprehensive Audit** - 4 parallel agents analyzed entire codebase
2. ✅ **Fixed Threading Tests** - Resolved compilation error, 896/900 tests passing
3. ✅ **Updated CLAUDE.md** - Fixed 8 critical inaccuracies
4. ✅ **Generated 4 Detailed Reports** - Full documentation of all issues

### Reports Generated:

- `docs/DOCUMENTATION-REORGANIZATION-ASSESSMENT-2025-10-07.md` (380 lines)
- `docs/audits/CLAUDE-MD-ACCURACY-AUDIT-2025-10-07.md` (515 lines)
- `TEST_VERIFICATION_REPORT.md` (656 lines)
- `docs/DOCUMENTATION-AUDIT-SUMMARY-2025-10-07.md` (900 lines)

---

## 📋 Remaining Tasks (Prioritized)

### Phase 1: Quick Wins (30 minutes)

**Delete Explicit Duplicates:**
```bash
# Files explicitly marked as duplicates
rm docs/archive/video-subsystem-architecture-duplicate.md
rm docs/archive/apu-planning/APU-GAP-ANALYSIS-2025-10-06.md
```

### Phase 2: Consolidate Duplicates (3-4 hours)

**Video Subsystem (8 files → 1):**
```bash
# Consolidate these into docs/implementation/phase-8-video/README.md:
- VIDEO-SUBSYSTEM-ARCHITECTURE.md
- video-architecture-review.md
- video-subsystem-executive-summary.md
- video-subsystem-code-review.md
- VIDEO-SUBSYSTEM-OPENGL-ALTERNATIVE.md
- video-subsystem-performance-analysis.md
- video-subsystem-testing-plan.md
```

**Audit Files (20+ files → 1):**
```bash
# Create docs/CURRENT-STATUS.md from:
- docs/archive/audits/* (all files)
- docs/archive/audits-2025-10-06/* (all files)
- docs/archive/audits-general/* (all files)
- DOCUMENTATION_AUDIT_2025-10-03.md
- DOCUMENTATION-AUDIT-REPORT-2025-10-03.md
```

**APU Documentation (6 files → 1):**
```bash
# Update docs/architecture/apu.md with content from:
- APU-UNIFIED-IMPLEMENTATION-PLAN.md
- APU-GAP-ANALYSIS-2025-10-06-UPDATED.md
- PHASE-1-APU-IMPLEMENTATION-PLAN.md
```

### Phase 3: Archive Completed Phases (1-2 hours)

```bash
# Create organized archive structure
mkdir -p docs/archive/completed-phases/{phase-0,phase-1,phase-1.5,phase-4,phase-7,phase-8}

# Move phase documentation
mv docs/archive/p0/* docs/archive/completed-phases/phase-0/
mv docs/archive/p1/* docs/archive/completed-phases/phase-1/
mv docs/archive/phase-1.5/* docs/archive/completed-phases/phase-1.5/
mv docs/archive/PHASE-4-* docs/archive/completed-phases/phase-4/
mv docs/archive/PHASE-7-* docs/archive/completed-phases/phase-7/
mv docs/implementation/phase-8-video/ docs/archive/completed-phases/phase-8/

# Archive old code reviews
mv docs/code-review/archive/2025-10-05/ docs/archive/code-reviews/2025-10-05/
mv docs/archive/code-review-2025-10-04/ docs/archive/code-reviews/2025-10-04/
```

### Phase 4: Create Missing Critical Docs (4-6 hours)

**1. QUICK-START.md** (2 hours)
```markdown
- Prerequisites (Zig 0.15.1, Wayland, Vulkan)
- Build instructions
- Running the emulator
- Loading ROMs
- Keyboard controls
- Common issues
```

**2. COMPATIBILITY.md** (1 hour)
```markdown
- Supported mappers (Mapper 0 currently)
- Known working games
- Known issues
- Testing results
```

**3. docs/architecture/overview.md** (2-3 hours)
```markdown
- System architecture
- Thread model
- Mailbox system
- State/Logic pattern
- Timing coordination
```

### Phase 5: Reorganize Structure (4-8 hours)

**Create new structure:**
```bash
docs/
├── README.md                 # Navigation hub (existing, update)
├── QUICK-START.md           # NEW
├── COMPATIBILITY.md         # NEW
├── CURRENT-STATUS.md        # NEW (single source of truth)
│
├── guides/                   # NEW: Developer guides
│   ├── getting-started.md
│   ├── architecture-overview.md
│   ├── contributing.md
│   ├── testing.md
│   └── debugging.md
│
├── api/                      # Expanded API reference
│   ├── cpu.md               # NEW
│   ├── ppu.md               # NEW
│   ├── apu.md               # NEW
│   ├── bus.md               # NEW
│   ├── cartridge.md         # NEW
│   ├── debugger.md          # existing
│   └── snapshot.md          # existing
│
├── architecture/             # Keep, consolidate
│   ├── overview.md          # NEW
│   ├── state-logic-pattern.md
│   ├── threading-model.md
│   ├── mailbox-system.md
│   └── timing-accuracy.md
│
├── implementation/           # Current work only
│   ├── current/             # NEW
│   └── notes/               # Design decisions, sessions
│
├── reference/                # NEW: Technical references
│   ├── 6502-timings.md
│   ├── ppu-registers.md
│   ├── mapper-list.md
│   └── test-roms.md
│
└── archive/                  # Organized archives
    ├── 2025-10/             # Date-based
    ├── completed-phases/     # Phase 0-8
    ├── code-reviews/        # Old reviews
    └── planning/            # Old plans
```

### Phase 6: Update Cross-References (2-3 hours)

```bash
# Update all markdown files to reference new locations
# Update CLAUDE.md with new document structure
# Update docs/README.md navigation
# Update docs/INDEX.md
```

---

## 🎯 Critical Metrics

### Current State:
- **Files:** 182 markdown documents
- **Duplicates:** 30+ files
- **Test Documentation Drift:** 342 undocumented tests
- **CLAUDE.md Accuracy:** 99% (was 92%)

### Target State:
- **Files:** ~60 active + ~120 archived (well-organized)
- **Duplicates:** 0
- **Test Documentation Drift:** 0
- **CLAUDE.md Accuracy:** 100%

---

## 🚀 Quick Start (Do This Now)

```bash
# 1. Delete explicit duplicates (2 minutes)
cd /home/colin/Development/RAMBO
rm docs/archive/video-subsystem-architecture-duplicate.md
rm docs/archive/apu-planning/APU-GAP-ANALYSIS-2025-10-06.md

# 2. Verify tests still passing (1 minute)
zig build test

# 3. Read the detailed audit reports
cat docs/DOCUMENTATION-AUDIT-SUMMARY-2025-10-07.md
cat docs/DOCUMENTATION-REORGANIZATION-ASSESSMENT-2025-10-07.md

# 4. Start Phase 2 consolidation when ready
```

---

## 📊 Success Criteria

✅ **Documentation Cleanup Complete When:**

1. All duplicate files consolidated (30+ → 0)
2. All completed phases archived properly
3. Missing critical docs created (QUICK-START, COMPATIBILITY, overview)
4. Test count documentation matches reality (850+ tests documented)
5. CLAUDE.md 100% accurate
6. Clean directory structure (60 active files, organized archive)
7. All cross-references updated
8. Single source of truth established (CURRENT-STATUS.md)

---

## ⏱️ Time Estimates

| Phase | Task | Time | Priority |
|-------|------|------|----------|
| 1 | Delete explicit duplicates | 30 min | HIGH |
| 2 | Consolidate duplicates | 3-4 hrs | HIGH |
| 3 | Archive completed phases | 1-2 hrs | MEDIUM |
| 4 | Create missing critical docs | 4-6 hrs | HIGH |
| 5 | Reorganize structure | 4-8 hrs | MEDIUM |
| 6 | Update cross-references | 2-3 hrs | MEDIUM |
| **TOTAL** | **Full Cleanup** | **15-23 hrs** | - |

---

## 🔍 Verification Checklist

After cleanup, verify:

- [ ] No files named "*duplicate*" exist
- [ ] No more than 1 file documenting the same topic
- [ ] All Phase 0-8 docs in `docs/archive/completed-phases/`
- [ ] QUICK-START.md exists and is accurate
- [ ] COMPATIBILITY.md lists all tested games
- [ ] Test counts in CLAUDE.md match `zig build test` output
- [ ] All links in docs/README.md work
- [ ] docs/CURRENT-STATUS.md is single source of truth
- [ ] `find docs -name "*.md" | wc -l` shows ~60 active files

---

**Ready to execute!** Start with Phase 1 (delete explicit duplicates) and proceed through phases systematically.
