# Phase 1 Refactoring - Development Guide

**SINGLE SOURCE OF TRUTH for Phase 1 Development**

**Date Created:** 2025-10-09
**Status:** Active Development Guide
**Current Phase:** Planning Complete, Ready to Begin

---

## ⚠️ CRITICAL DEVELOPMENT RULES

### Absolute Requirements

1. **NO FUNCTIONALITY CHANGES** - Pure refactoring only
2. **NO SHIMS OR COMPATIBILITY LAYERS** - Update tests directly
3. **NO REGRESSIONS** - All passing tests must continue passing
4. **UPDATE ALL DOCUMENTATION** - Before code changes, not after
5. **COMMIT AT EVERY MILESTONE** - Working state only
6. **STATE ISOLATION** - Side effects only at top of `tick()`
7. **CLEAR OWNERSHIP** - No functions taking pointers and mutating EmulationState

### Test Policy

**Tests WILL break during refactoring - THIS IS EXPECTED**

- ✅ Update tests as you refactor modules
- ✅ Keep tests synchronized with code changes
- ❌ DO NOT add shims to preserve old test patterns
- ❌ DO NOT skip broken tests - fix them immediately

**Current Baseline:** 940/950 tests passing (3 known failures documented in KNOWN-ISSUES.md)

---

## Current Test Baseline (2025-10-09)

```bash
# Passing: 940 tests
# Failing: 3 tests (documented in docs/KNOWN-ISSUES.md)
#   1. src/emulation/State.zig:2138 - Odd frame skip
#   2. ppustatus_polling_test.zig:153 - VBlank clear bug
#   3. ppustatus_polling_test.zig:308 - BIT instruction VBlank timing
# Skipped: 7 tests (expected)
```

**Regression Check:** After each milestone, run `zig build test` - must have ≥940/950 passing

---

## Directory Structure Standards

### Naming Convention

**ALL new subdirectories follow this pattern:**

```
src/emulation/state/       # ← lowercase "state" subdirectory
├── BusState.zig          # ← PascalCase for struct files
├── CycleResults.zig
└── peripherals/          # ← lowercase subdirectory
    ├── OamDma.zig        # ← PascalCase for struct files
    ├── DmcDma.zig
    └── ControllerState.zig
```

**Rules:**
- Subdirectories: lowercase with underscores if needed (`emulation/state/`, not `emulation/State/`)
- Files exporting structs: PascalCase (`BusState.zig`)
- Files exporting functions: lowercase (`routing.zig`)
- Module facades: PascalCase matching primary type (`Cpu.zig`, `Ppu.zig`)

### Example File Structure

```
src/emulation/
├── State.zig              # Main facade (orchestrator)
├── Ppu.zig               # PPU runtime helpers
├── MasterClock.zig       # Clock management
├── state/                # ← NEW: Pure data structures
│   ├── BusState.zig
│   ├── CycleResults.zig
│   └── peripherals/
│       ├── OamDma.zig
│       ├── DmcDma.zig
│       └── ControllerState.zig
├── bus/                  # ← NEW: Bus routing logic
│   ├── routing.zig       # Bus read/write functions
│   └── README.md
└── cpu/                  # ← NEW: CPU execution helpers
    ├── microsteps.zig    # Addressing mode helpers
    ├── execution.zig     # executeCpuCycle refactored
    └── README.md
```

---

## Development Workflow

### For Each Milestone

**BEFORE writing any code:**

1. **Update this document** - Mark milestone as "In Progress"
2. **Update docs/CURRENT-STATUS.md** - Document planned changes
3. **Create git branch** - `git checkout -b phase-1.X-description`
4. **Review test dependencies** - Identify tests that will break

**During development:**

5. **Extract code** - Move functions/structs to new files
6. **Update imports** - In EmulationState and other modules
7. **Update tests immediately** - Fix any broken imports/calls
8. **Run `zig build test`** - Must have ≥940 passing
9. **Verify baseline** - Check no new failures introduced

**After milestone completion:**

10. **Update docs/refactoring/PHASE-1-PROGRESS.md** - Mark milestone complete
11. **Update docs/CURRENT-STATUS.md** - Reflect completed changes
12. **Commit with detailed message** - See commit template below
13. **Merge to main** - If all validations pass

### Commit Message Template

```
refactor(emulation): Phase 1.X - [Milestone Name]

[Detailed description of what was extracted/changed]

Files created:
- src/emulation/state/BusState.zig (15 lines)
- src/emulation/state/CycleResults.zig (16 lines)

Files modified:
- src/emulation/State.zig (-31 lines, added imports)
- tests/integration/cpu_ppu_integration_test.zig (updated imports)

Tests updated: 3 files
Tests passing: 940/950 (baseline maintained)

Phase 1 Progress: Milestone 1.1 Complete (2/10)
```

---

## Phase 1 Milestones

### Milestone 1.0: Dead Code Removal ✅ READY

**Duration:** 30 minutes
**Risk:** 🟢 Zero
**Files to Delete:**
- `src/ppu/VBlankState.zig` (120 lines)
- `src/ppu/VBlankFix.zig` (136 lines)

**Validation:**
```bash
# Verify zero usage
grep -r "VBlankState\|VBlankFix" src tests
# Should return no results

# Delete
rm src/ppu/VBlankState.zig src/ppu/VBlankFix.zig

# Test
zig build test
# Must have ≥940/950 passing
```

**Documentation to Update:**
- [ ] `docs/CURRENT-STATUS.md` - Update file counts
- [ ] `docs/refactoring/PHASE-1-PROGRESS.md` - Mark M1.0 complete
- [ ] This document - Check off milestone

**Commit:** `refactor(ppu): Phase 1.0 - Remove orphaned VBlank files`

---

### Milestone 1.1: Extract Pure Data Structures 🎯 NEXT

**Duration:** 2-3 days
**Risk:** 🟢 Minimal
**Goal:** Extract 286 lines of pure data structures from State.zig

#### Step 1.1.1: Create Directory Structure (30 min)

```bash
mkdir -p src/emulation/state/peripherals
```

**No code changes yet - just scaffolding**

#### Step 1.1.2: Extract CycleResults.zig (1 hour)

**File:** `src/emulation/state/CycleResults.zig`

```zig
//! PPU, CPU, and APU cycle result structures
//! Used by EmulationState.tick() to communicate component events

/// Result of a single PPU cycle
pub const PpuCycleResult = struct {
    frame_complete: bool = false,
    rendering_enabled: bool = false,
    nmi_signal: bool = false,
    vblank_clear: bool = false,
    a12_rising: bool = false,
};

/// Result of a single CPU cycle
pub const CpuCycleResult = struct {
    mapper_irq: bool = false,
};

/// Result of a single APU cycle
pub const ApuCycleResult = struct {
    frame_irq: bool = false,
    dmc_irq: bool = false,
};
```

**Changes to State.zig:**
```zig
// ADD at top:
const CycleResults = @import("state/CycleResults.zig");
const PpuCycleResult = CycleResults.PpuCycleResult;
const CpuCycleResult = CycleResults.CpuCycleResult;
const ApuCycleResult = CycleResults.ApuCycleResult;

// DELETE lines 30-46 (old definitions)
```

**Tests Affected:** 0 (internal types, not exported)

**Validation:**
```bash
zig build test  # Must pass ≥940/950
```

#### Step 1.1.3: Extract BusState.zig (1 hour)

**File:** `src/emulation/state/BusState.zig`

```zig
//! Memory bus state owned by emulation runtime
//! Stores all data required to service CPU/PPU bus accesses

const std = @import("std");

/// Memory bus state
pub const BusState = struct {
    /// Internal RAM: 2KB ($0000-$07FF), mirrored through $0000-$1FFF
    ram: [2048]u8 = std.mem.zeroes([2048]u8),

    /// Last value observed on CPU data bus (open bus behaviour)
    open_bus: u8 = 0,

    /// Optional external RAM used by tests in lieu of a cartridge
    test_ram: ?[]u8 = null,
};
```

**Changes to State.zig:**
```zig
// ADD at top:
const BusState = @import("state/BusState.zig").BusState;

// DELETE lines 49-58 (old definition)
```

**Tests Affected:** 0 (BusState not directly accessed by tests)

**Validation:**
```bash
zig build test  # Must pass ≥940/950
```

#### Step 1.1.4: Extract OamDma.zig (2 hours)

**File:** `src/emulation/state/peripherals/OamDma.zig`

```zig
//! OAM DMA State Machine
//! Cycle-accurate DMA transfer from CPU RAM to PPU OAM
//! Follows microstep pattern for hardware accuracy

/// OAM DMA state
pub const OamDma = struct {
    /// DMA active flag
    active: bool = false,

    /// Source page number (written to $4014)
    source_page: u8 = 0,

    /// Current byte offset within page (0-255)
    current_offset: u8 = 0,

    /// Cycle counter within DMA transfer
    current_cycle: u16 = 0,

    /// Alignment wait needed (odd CPU cycle start)
    needs_alignment: bool = false,

    /// Temporary value for read/write pair
    temp_value: u8 = 0,

    /// Trigger DMA transfer
    pub fn trigger(self: *OamDma, page: u8, on_odd_cycle: bool) void {
        self.active = true;
        self.source_page = page;
        self.current_offset = 0;
        self.current_cycle = 0;
        self.needs_alignment = on_odd_cycle;
        self.temp_value = 0;
    }

    /// Reset DMA state
    pub fn reset(self: *OamDma) void {
        self.* = .{};
    }
};
```

**Changes to State.zig:**
```zig
// ADD at top:
const OamDma = @import("state/peripherals/OamDma.zig").OamDma;

// REPLACE line 259: dma: DmaState = .{},
// WITH:
dma: OamDma = .{},

// DELETE lines 63-102 (old DmaState definition)
```

**Tests Affected:** 1 file
- `tests/integration/oam_dma_timing_test.zig` - Update `DmaState` → `OamDma`

**Validation:**
```bash
zig build test  # Must pass ≥940/950
```

#### Step 1.1.5: Extract DmcDma.zig (2 hours)

**File:** `src/emulation/state/peripherals/DmcDma.zig`

```zig
//! DMC DMA State Machine
//! Simulates RDY line (CPU stall) during DMC sample fetch
//! NTSC (2A03) only: Causes controller/PPU register corruption

/// DMC DMA state
pub const DmcDma = struct {
    /// RDY line active (CPU stalled)
    rdy_low: bool = false,

    /// Cycles remaining in RDY stall (0-4)
    stall_cycles_remaining: u8 = 0,

    /// Sample address to fetch
    sample_address: u16 = 0,

    /// Sample byte fetched (returned to APU)
    sample_byte: u8 = 0,

    /// Last CPU read address (for repeat reads during stall)
    last_read_address: u16 = 0,

    /// Trigger DMC sample fetch
    pub fn triggerFetch(self: *DmcDma, address: u16) void {
        self.rdy_low = true;
        self.stall_cycles_remaining = 4;
        self.sample_address = address;
    }

    /// Reset DMC DMA state
    pub fn reset(self: *DmcDma) void {
        self.* = .{};
    }
};
```

**Changes to State.zig:**
```zig
// ADD at top:
const DmcDma = @import("state/peripherals/DmcDma.zig").DmcDma;

// REPLACE line 262: dmc_dma: DmcDmaState = .{},
// WITH:
dmc_dma: DmcDma = .{},

// DELETE lines 194-224 (old DmcDmaState definition)
```

**Tests Affected:** 1 file
- `tests/integration/dmc_dma_conflict_test.zig` - Update `DmcDmaState` → `DmcDma`

**Validation:**
```bash
zig build test  # Must pass ≥940/950
```

#### Step 1.1.6: Extract ControllerState.zig (2 hours)

**File:** `src/emulation/state/peripherals/ControllerState.zig`

```zig
//! NES Controller State
//! Implements cycle-accurate 4021 8-bit shift register behavior
//! Button order: A, B, Select, Start, Up, Down, Left, Right

/// NES controller state
pub const ControllerState = struct {
    /// Controller 1 shift register
    shift1: u8 = 0,

    /// Controller 2 shift register
    shift2: u8 = 0,

    /// Strobe state (latched buttons or shifting mode)
    strobe: bool = false,

    /// Button data for controller 1
    buttons1: u8 = 0,

    /// Button data for controller 2
    buttons2: u8 = 0,

    /// Latch controller buttons into shift registers
    pub fn latch(self: *ControllerState) void {
        self.shift1 = self.buttons1;
        self.shift2 = self.buttons2;
    }

    /// Update button data from mailbox
    pub fn updateButtons(self: *ControllerState, buttons1: u8, buttons2: u8) void {
        self.buttons1 = buttons1;
        self.buttons2 = buttons2;
        if (self.strobe) {
            self.latch();
        }
    }

    /// Read controller 1 serial data (bit 0)
    pub fn read1(self: *ControllerState) u8 {
        if (self.strobe) {
            return self.buttons1 & 0x01;
        } else {
            const bit = self.shift1 & 0x01;
            self.shift1 = (self.shift1 >> 1) | 0x80;
            return bit;
        }
    }

    /// Read controller 2 serial data (bit 0)
    pub fn read2(self: *ControllerState) u8 {
        if (self.strobe) {
            return self.buttons2 & 0x01;
        } else {
            const bit = self.shift2 & 0x01;
            self.shift2 = (self.shift2 >> 1) | 0x80;
            return bit;
        }
    }

    /// Write strobe state ($4016 write, bit 0)
    pub fn writeStrobe(self: *ControllerState, value: u8) void {
        const new_strobe = (value & 0x01) != 0;
        const rising_edge = new_strobe and !self.strobe;
        self.strobe = new_strobe;
        if (rising_edge) {
            self.latch();
        }
    }

    /// Reset controller state
    pub fn reset(self: *ControllerState) void {
        self.* = .{};
    }
};
```

**Changes to State.zig:**
```zig
// ADD at top:
const ControllerState = @import("state/peripherals/ControllerState.zig").ControllerState;

// DELETE lines 107-189 (old ControllerState definition)
```

**Tests Affected:** 1 file
- `tests/integration/controller_integration_test.zig` - Update if directly referencing ControllerState

**Validation:**
```bash
zig build test  # Must pass ≥940/950
```

#### Milestone 1.1 Completion Checklist

- [ ] All 5 files extracted (CycleResults, BusState, OamDma, DmcDma, ControllerState)
- [ ] State.zig updated with imports
- [ ] All 3 affected test files updated
- [ ] `zig build test` passes ≥940/950 tests
- [ ] Documentation updated (see below)
- [ ] Git commit created

**Documentation to Update:**
- [ ] `docs/CURRENT-STATUS.md` - Update file counts, structure
- [ ] `docs/refactoring/PHASE-1-PROGRESS.md` - Mark M1.1 complete
- [ ] This document - Check off milestone

**Result:**
- State.zig: 2,225 → 1,939 lines (-286 lines, -12.9%)
- New files: 5 (total +286 lines organized into modules)
- Test changes: 3 files (simple import/type name updates)

**Commit:** `refactor(emulation): Phase 1.1 - Extract pure data structures`

---

### Milestone 1.2: Extract Bus Routing (Future)

**Status:** Not Yet Started
**See:** `docs/refactoring/state-zig-extraction-plan.md` for detailed steps

---

## Progress Tracking

### Overall Phase 1 Progress

| Milestone | Status | Lines Reduced | Tests Updated | Commit |
|-----------|--------|---------------|---------------|--------|
| 1.0 Dead Code | ✅ Ready | -256 | 0 | - |
| 1.1 Data Structures | 🎯 Next | -286 | 3 | - |
| 1.2 Bus Routing | ⏳ Planned | -280 | 0 | - |
| 1.3 CPU Microsteps | ⏳ Planned | -320 | 0 | - |
| 1.4 CPU Execution | ⏳ Planned | -600 | 0 | - |
| **Total** | **0%** | **-1,742** | **3** | - |

**Current:** Phase 1 Planning Complete, Ready to Begin Milestone 1.0

---

## Documentation Maintenance

### Documents to Update Before Each Milestone

**MANDATORY - Update before code changes:**

1. **This document** (`PHASE-1-DEVELOPMENT-GUIDE.md`)
   - Mark milestone "In Progress"
   - Update progress table

2. **docs/CURRENT-STATUS.md**
   - Update file counts
   - Document structural changes
   - Note new modules

3. **docs/refactoring/PHASE-1-PROGRESS.md**
   - Daily work log
   - Blockers encountered
   - Decisions made

### Documents to Update After Each Milestone

**MANDATORY - Update after validation:**

1. **This document** (`PHASE-1-DEVELOPMENT-GUIDE.md`)
   - Check off milestone completion
   - Update progress table

2. **docs/CURRENT-STATUS.md**
   - Confirm completed changes
   - Update statistics

3. **docs/refactoring/PHASE-1-PROGRESS.md**
   - Mark milestone complete
   - Record final stats

### Read-Only Reference Documents

**DO NOT MODIFY - These are historical:**

- `docs/refactoring/phase-0-completion-assessment.md`
- `docs/refactoring/state-zig-architecture-audit.md`
- `docs/refactoring/ppu-subsystem-audit-2025-10-09.md`
- `docs/KNOWN-ISSUES.md` (only update if discovering NEW issues)

---

## Validation Requirements

### After Every Code Change

```bash
# 1. Build must succeed
zig build

# 2. Full test suite
zig build test

# 3. Check for regressions
# Expected: 940/950 passing, 3 known failures, 7 skipped
# Failing tests must be same 3 documented in KNOWN-ISSUES.md
```

### After Every Milestone

```bash
# 1. All validation from above, plus:

# 2. AccuracyCoin validation (if available)
./zig-out/bin/RAMBO test/AccuracyCoin.nes

# 3. Verify no compilation warnings
zig build 2>&1 | grep -i "warning"
# Should return empty

# 4. Check test count hasn't decreased
zig build test 2>&1 | grep "passed"
# Should show ≥940 passing
```

### Before Each Commit

```bash
# 1. All milestone validation from above

# 2. Verify documentation updated
ls -la docs/refactoring/PHASE-1-PROGRESS.md
ls -la docs/CURRENT-STATUS.md

# 3. Review changes
git diff --stat

# 4. Ensure no debug code
grep -r "std.debug.print\|TODO\|FIXME" src/emulation/

# 5. Final test run
zig build test
```

---

## Troubleshooting

### Test Failures During Refactoring

**Expected:** Tests will break when moving code

**Procedure:**
1. Identify which tests failed
2. Update test imports to point to new locations
3. Update test code to use new types/function names
4. Re-run `zig build test`
5. Repeat until all tests pass

**Example:**
```zig
// OLD (before refactoring):
const DmaState = @import("../../src/emulation/State.zig").DmaState;

// NEW (after extracting to peripherals/):
const OamDma = @import("../../src/emulation/state/peripherals/OamDma.zig").OamDma;
```

### Build Failures

**Common Issues:**
1. **Missing imports** - Add import at top of file
2. **Type name mismatch** - Update to new type name (e.g., `DmaState` → `OamDma`)
3. **Circular dependencies** - Check import order, may need to reorganize

**Debug Process:**
```bash
# Get full error
zig build 2>&1 | less

# Find file with error
# Fix import/type/reference
# Retry
zig build
```

### Validation Failures

**If tests regress below 940/950:**

1. **STOP immediately** - Do not proceed
2. **Identify new failures** - Run `zig build test 2>&1 | grep "error:"`
3. **Determine cause** - Are they due to refactoring or introduced bugs?
4. **Fix or rollback** - Either fix the issue or `git reset --hard`
5. **Document decision** - Note in PHASE-1-PROGRESS.md

---

## Communication & Handoff

### For AI Agents

**When picking up work:**

1. Read this document **completely** - It's the single source of truth
2. Check **Milestone Progress** section for current status
3. Review **docs/refactoring/PHASE-1-PROGRESS.md** for latest updates
4. Verify baseline: `zig build test` should show 940/950 passing

**When handing off work:**

1. Update **this document** with progress
2. Update **docs/refactoring/PHASE-1-PROGRESS.md** with work log
3. Commit changes if milestone complete
4. Note any blockers or decisions needed

### For Humans

**Daily Standup Info:**
- Check "Overall Phase 1 Progress" table
- Review `docs/refactoring/PHASE-1-PROGRESS.md` for daily log
- See commit history for completed milestones

**Code Review Focus:**
- No functionality changes (pure refactoring)
- Tests updated to match code changes
- Documentation updated before commits
- No shims or compatibility layers introduced

---

## Emergency Procedures

### If Things Go Wrong

**Rollback Procedure:**
```bash
# If uncommitted changes:
git status
git diff  # Review what changed
git reset --hard  # Nuclear option: discard all changes

# If committed but broken:
git log --oneline -5  # Find last good commit
git reset --hard <commit-hash>  # Roll back to last good state

# Verify rollback:
zig build test  # Should show 940/950 passing again
```

**When to Rollback:**
- Test pass rate drops below 930/950 (>10 new failures)
- Build fails and fix isn't obvious within 30 minutes
- New functionality introduced accidentally
- Shims or compatibility layers added

### Getting Help

**Before asking for help:**
1. Document the issue in PHASE-1-PROGRESS.md
2. Capture full error output
3. Note what you've tried
4. Check if issue is in this guide's Troubleshooting section

**Information to provide:**
- Current milestone
- Error message (full text)
- Files modified
- Steps to reproduce
- Git status output

---

## Success Criteria

### Milestone Complete When:

- [ ] All code extracted and organized
- [ ] All imports updated
- [ ] All tests updated and passing
- [ ] `zig build test` shows ≥940/950 passing
- [ ] All documentation updated (see checklist)
- [ ] Git commit created with proper message
- [ ] No TODOs or FIXMEs introduced
- [ ] No debug print statements left in code

### Phase 1 Complete When:

- [ ] All 10 milestones complete
- [ ] State.zig under 800 lines
- [ ] All new modules created and documented
- [ ] All tests passing at baseline (≥940/950)
- [ ] AccuracyCoin still passing
- [ ] All documentation updated
- [ ] Code review approved
- [ ] CLAUDE.md updated with new structure

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-10-09 | Initial creation - Single source of truth established |

**Current Version:** 1.0
**Last Updated:** 2025-10-09 03:15 UTC
**Status:** Active Development Guide

---

**This is the ONLY development guide for Phase 1. All other documents are reference only.**
