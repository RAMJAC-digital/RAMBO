# Phase 2E: Clean Architecture Implementation Plan

**Date:** 2025-10-16
**Priority:** Option B - Architecture First (Clean, No Legacy)
**Pattern Reference:** PPU odd-frame skip (src/emulation/state/Timing.zig)

## Overview

This document provides a complete, researched implementation plan following established patterns. All decisions are based on existing idioms in the codebase to ensure consistency.

## Critical Pattern: PPU Skip vs Early Termination

### The Problem with Early Termination

**What I originally proposed** (WRONG):
```zig
// Terminate 2 cycles early
if (effective_cycle >= 510) {  // Instead of >= 512
    dma.reset();
    return;
}
```

**Why this is wrong:**
- Creates nondeterministic timing
- Cycle counter doesn't reach expected value
- Breaks timing assumptions in other code
- User feedback: "This has been an issue, and creates other nondeterministic failures"

### The Correct Pattern: Skip Work, Not Time

**PPU odd-frame skip** (CORRECT pattern from src/emulation/State.zig:594):
```zig
// Detection: Check BEFORE work
const skip_slot = TimingHelpers.shouldSkipOddFrame(
    odd_frame, rendering_enabled, scanline, dot
);

// Advancement: Clock ALWAYS advances
self.clock.advance(1);
if (skip_slot) {
    self.clock.advance(1);  // Skip through the position
}

// Work: Skip if flagged
if (step.skip_slot) {
    ppu_result.frame_complete = true;  // Manual fixup
    // NO other work happens
}
```

**Key principles:**
1. **Deterministic advancement** - Clock always moves forward predictably
2. **Skip work, not time** - Cycles still increment, but no operations execute
3. **Manual fixup** - Set any critical state that would have been set
4. **Pure detection** - Decision function has no side effects

## Phase 1: Architecture Refactor - DMC Completion Pattern

### Issue: Timestamp Race Condition

**Current problem** (architect agent finding):
```zig
// In tickDmcDma (logic.zig:119)
state.dmc_dma.rdy_low = false;  // DMC clears its own flag

// In execution.zig (happens NEXT cycle)
if (!dmc_is_active and dmc_was_active) {
    ledger.last_dmc_inactive_cycle = now;  // One cycle late!
}
```

**Result:** OAM checks timestamps but sees stale data (one cycle behind hardware state).

### Solution: External State Management

**Follow NMI/VBlank pattern** (src/emulation/cpu/execution.zig:105):
```zig
// NMI (CORRECT - external management):
const nmi_active = (ledger.last_set_cycle > ledger.last_clear_cycle);
// PPU sets vblank flag, execution.zig records timestamp
// State and timestamp updated in same place (synchronous)

// DMC (FIX - use same pattern):
// DMC signals completion, execution.zig clears flag AND records timestamp
```

### Implementation Steps

#### Step 1.1: Add Completion Signal to DmcDma

**File:** `src/emulation/state/peripherals/DmcDma.zig`

**Change:**
```zig
pub const DmcDma = struct {
    /// RDY line state (pulled low during DMA)
    rdy_low: bool = false,

    /// NEW: Completion signal (set when transfer finishes)
    /// execution.zig clears this AND rdy_low atomically
    transfer_complete: bool = false,

    // ... rest of fields
```

**Rationale:** Separates internal completion signal from external hardware state.

#### Step 1.2: Signal Completion Instead of Self-Modify

**File:** `src/emulation/dma/logic.zig`

**Current code (lines 100-106, 110-119):**
```zig
if (cycle == 0) {
    state.dmc_dma.rdy_low = false;  // ❌ Self-modification
    return;
}

// ...

if (cycle == 1) {
    // ... fetch sample ...
    state.dmc_dma.rdy_low = false;  // ❌ Self-modification
    return;  // ❌ Missing (bug #3)
}
```

**New code:**
```zig
if (cycle == 0) {
    // Signal completion, don't modify rdy_low
    state.dmc_dma.transfer_complete = true;
    return;
}

// ...

if (cycle == 1) {
    // Final cycle: Fetch sample byte
    const address = state.dmc_dma.sample_address;
    state.dmc_dma.sample_byte = state.busRead(address);
    ApuLogic.loadSampleByte(&state.apu, state.dmc_dma.sample_byte);

    // Signal completion, don't modify rdy_low
    state.dmc_dma.transfer_complete = true;
    return;  // ✅ Added return (fixes bug #3)
}

// Idle cycles: CPU repeats last read
if (has_dpcm_bug) {
    _ = state.busRead(state.dmc_dma.last_read_address);
}
```

**Changes:**
- ✅ Signal completion via new flag
- ✅ Don't self-modify rdy_low
- ✅ Add missing return after fetch (bug #3)

#### Step 1.3: Handle Completion Externally

**File:** `src/emulation/cpu/execution.zig`

**Current code (lines 126-136):**
```zig
// DMC edge detection (record active/inactive transitions in ledger)
const dmc_was_active = (state.dma_interaction_ledger.last_dmc_active_cycle >
    state.dma_interaction_ledger.last_dmc_inactive_cycle);
const dmc_is_active = state.dmc_dma.rdy_low;

// Record edges (direct field assignment)
if (dmc_is_active and !dmc_was_active) {
    state.dma_interaction_ledger.last_dmc_active_cycle = state.clock.ppu_cycles;
} else if (!dmc_is_active and dmc_was_active) {
    state.dma_interaction_ledger.last_dmc_inactive_cycle = state.clock.ppu_cycles;
}
```

**New code:**
```zig
// DMC completion handling (external state management)
// Check completion signal BEFORE reading rdy_low
if (state.dmc_dma.transfer_complete) {
    // Atomic update: clear flag, clear rdy_low, record timestamp
    state.dmc_dma.transfer_complete = false;
    state.dmc_dma.rdy_low = false;
    state.dma_interaction_ledger.last_dmc_inactive_cycle = state.clock.ppu_cycles;
}

// DMC edge detection for rising edge (active)
const dmc_was_active = (state.dma_interaction_ledger.last_dmc_active_cycle >
    state.dma_interaction_ledger.last_dmc_inactive_cycle);
const dmc_is_active = state.dmc_dma.rdy_low;

if (dmc_is_active and !dmc_was_active) {
    state.dma_interaction_ledger.last_dmc_active_cycle = state.clock.ppu_cycles;
}
```

**Changes:**
- ✅ Check completion signal first
- ✅ Atomically clear both flags and update timestamp
- ✅ Rising edge detection remains unchanged
- ✅ Falling edge handled by completion signal
- ✅ State and timestamp synchronized (no race)

### Milestone 1: Unit Test Verification

After completing Phase 1, run unit tests:

```bash
zig build test-unit
```

**Expected:** All passing (no regressions from architecture change)

**Validation:** DMC completion now follows NMI/VBlank pattern exactly.

---

## Phase 2: Apply PPU Skip Pattern to OAM Duplication

### Issue: 257 Writes Instead of 256

**Current behavior:**
1. Duplicate write at OAM[0]
2. Fall through to 512 full cycles (256 read/write pairs)
3. Total: 257 writes
4. OAM address wraps: 256 % 256 = 0
5. Byte 255 overwrites OAM[0]

**Root cause:** Not skipping the final pair after duplication.

### Solution: Skip Final Read/Write Pair

**Follow PPU skip pattern:**
- **Detection**: Check if duplication occurred and at final pair
- **Skip work**: Don't execute read/write for cycles 510-511
- **Advance cycle**: Counter still increments deterministically
- **Complete normally**: Check completion at cycle 512 (unchanged)

### Implementation Steps

#### Step 2.1: Add Duplication Tracking Flag

**File:** `src/emulation/DmaInteractionLedger.zig`

**Change:**
```zig
pub const DmaInteractionLedger = struct {
    // ... existing timestamp fields ...

    /// Captured state at moment of pause (flattened fields)
    paused_during_read: bool = false,
    paused_at_offset: u8 = 0,
    paused_byte_value: u8 = 0,
    paused_oam_addr: u8 = 0,

    /// NEW: Track if duplication occurred (set at pause, never cleared)
    /// Used to determine if final byte pair should be skipped
    duplication_occurred: bool = false,
```

**Rationale:** Need persistent flag that survives the resume (unlike paused_during_read which gets cleared).

#### Step 2.2: Set Flag at Pause

**File:** `src/emulation/cpu/execution.zig`

**Current code (lines 155-163):**
```zig
// Capture state (direct field assignment)
state.dma_interaction_ledger.oam_pause_cycle = state.clock.ppu_cycles;
state.dma_interaction_ledger.paused_at_offset = state.dma.current_offset;
state.dma_interaction_ledger.paused_during_read = is_reading;
state.dma_interaction_ledger.paused_oam_addr = state.ppu.oam_addr;

if (is_reading) {
    const addr = (@as(u16, state.dma.source_page) << 8) | state.dma.current_offset;
    state.dma_interaction_ledger.paused_byte_value = state.busRead(addr);
}
```

**New code:**
```zig
// Capture state (direct field assignment)
state.dma_interaction_ledger.oam_pause_cycle = state.clock.ppu_cycles;
state.dma_interaction_ledger.paused_at_offset = state.dma.current_offset;
state.dma_interaction_ledger.paused_during_read = is_reading;
state.dma_interaction_ledger.paused_oam_addr = state.ppu.oam_addr;

if (is_reading) {
    const addr = (@as(u16, state.dma.source_page) << 8) | state.dma.current_offset;
    state.dma_interaction_ledger.paused_byte_value = state.busRead(addr);

    // NEW: Set persistent flag for skip detection
    state.dma_interaction_ledger.duplication_occurred = true;
}
```

**Changes:**
- ✅ Set duplication_occurred when paused during read
- ✅ Flag persists through resume (unlike paused_during_read)

#### Step 2.3: Apply PPU Skip Pattern in tickOamDma

**File:** `src/emulation/dma/logic.zig`

**Current code (lines 35-82):**
```zig
// Check 2: Just resumed - handle duplication
const just_resumed = !dmc_is_active and was_paused;
if (just_resumed) {
    ledger.oam_resume_cycle = now;

    if (ledger.paused_during_read) {
        state.ppu.oam[state.ppu.oam_addr] = ledger.paused_byte_value;
        state.ppu.oam_addr +%= 1;
        ledger.paused_during_read = false;
    }
    // Fall through to continue normal operation
}

// Calculate effective cycle
const effective_cycle: i32 = if (dma.needs_alignment)
    @as(i32, @intCast(dma.current_cycle)) - 1
else
    @as(i32, @intCast(dma.current_cycle));

// Check 3: Alignment wait?
if (effective_cycle < 0) {
    dma.current_cycle += 1;
    return;
}

// Check 4: Completed?
if (effective_cycle >= 512) {
    dma.reset();
    ledger.reset();
    return;
}

// Check 5: Read or write?
const is_read_cycle = @rem(effective_cycle, 2) == 0;

if (is_read_cycle) {
    const addr = (@as(u16, dma.source_page) << 8) | dma.current_offset;
    dma.temp_value = state.busRead(addr);
} else {
    state.ppu.oam[state.ppu.oam_addr] = dma.temp_value;
    state.ppu.oam_addr +%= 1;
    dma.current_offset +%= 1;
}

dma.current_cycle += 1;
```

**New code (PPU skip pattern applied):**
```zig
// Check 2: Just resumed - handle duplication
const just_resumed = !dmc_is_active and was_paused;
if (just_resumed) {
    ledger.oam_resume_cycle = now;

    if (ledger.paused_during_read) {
        state.ppu.oam[state.ppu.oam_addr] = ledger.paused_byte_value;
        state.ppu.oam_addr +%= 1;
        ledger.paused_during_read = false;
    }
    // Fall through to continue normal operation
}

// Calculate effective cycle
const effective_cycle: i32 = if (dma.needs_alignment)
    @as(i32, @intCast(dma.current_cycle)) - 1
else
    @as(i32, @intCast(dma.current_cycle));

// Check 3: Alignment wait?
if (effective_cycle < 0) {
    dma.current_cycle += 1;
    return;
}

// Check 4: Completed?
if (effective_cycle >= 512) {
    dma.reset();
    ledger.reset();
    return;
}

// NEW: Check 5: Should skip final byte pair? (PPU skip pattern)
// Detection: After duplication, skip cycles 510-511 (read/write of byte 255)
const should_skip_final_pair = ledger.duplication_occurred and effective_cycle >= 510;

if (should_skip_final_pair) {
    // Skip work, but advance cycle (deterministic timing)
    dma.current_cycle += 1;
    return;
}

// Check 6: Read or write? (renamed from Check 5)
const is_read_cycle = @rem(effective_cycle, 2) == 0;

if (is_read_cycle) {
    const addr = (@as(u16, dma.source_page) << 8) | dma.current_offset;
    dma.temp_value = state.busRead(addr);
} else {
    state.ppu.oam[state.ppu.oam_addr] = dma.temp_value;
    state.ppu.oam_addr +%= 1;
    dma.current_offset +%= 1;
}

dma.current_cycle += 1;
```

**Changes:**
- ✅ Added skip detection before read/write logic
- ✅ Skip work (return early) but advance cycle first
- ✅ Deterministic timing (cycle always increments)
- ✅ Completion check unchanged (still at 512)
- ✅ Follows PPU skip pattern exactly

**Result:**
- Cycle 0-509: Normal operation (255 bytes transferred)
- Cycles 510-511: Skipped (no read/write for byte 255)
- Cycle 512: Completion check triggers
- Total: 256 writes (1 duplicate + 255 normal)
- OAM[0] preserved (no wrap)

### Milestone 2: DMC/OAM Test Verification

After completing Phase 2, run DMC/OAM tests:

```bash
zig build test 2>&1 | grep "dmc_oam_conflict_test"
```

**Expected:** 12/12 passing (3 failures should now pass)

**Specific tests that should pass:**
1. "DEBUG: Trace complete DMC/OAM interaction"
2. "DMC interrupts OAM at byte 0 (start of transfer)"
3. "Multiple DMC interrupts during single OAM transfer"

---

## Phase 3: Fix Critical Bugs (Code Quality)

These bugs are unrelated to test failures but affect commercial ROM accuracy.

### Bug #4: Capture last_read_address

**File:** `src/emulation/State.zig`

**Find busRead function** (around line 500-600):
```zig
pub fn busRead(self: *EmulationState, address: u16) u8 {
    // NEW: Capture last read address for DMC corruption (NTSC 2A03 bug)
    self.dmc_dma.last_read_address = address;

    // ... rest of busRead implementation
```

**Changes:**
- ✅ One line addition at start of function
- ✅ Fixes bug #9 (corruption feature was non-functional)

### Bug #5: Simplify DMC Corruption Logic

**File:** `src/emulation/dma/logic.zig`

**Current code (lines 123-143):**
```zig
if (has_dpcm_bug) {
    const last_addr = state.dmc_dma.last_read_address;

    if (last_addr == 0x4016 or last_addr == 0x4017) {
        _ = state.busRead(last_addr);  // Controller corruption
    }

    if (last_addr == 0x2002 or last_addr == 0x2007) {
        _ = state.busRead(last_addr);  // PPU corruption
    }
}
```

**New code:**
```zig
if (has_dpcm_bug) {
    // NTSC: Repeat last read (corruption occurs for any MMIO address)
    // This affects controllers, PPU, APU, and mapper IRQ counters
    _ = state.busRead(state.dmc_dma.last_read_address);
}
```

**Changes:**
- ✅ Simplified to single busRead (hardware-accurate)
- ✅ Handles ALL MMIO corruption (not just specific addresses)
- ✅ Fixes bug #8 (incomplete corruption logic)

### Milestone 3: Full Test Suite Verification

After completing Phase 3, run full test suite:

```bash
zig build test --summary all
```

**Expected:** 1030/1030 passing (100%)

---

## Phase 4: Code Cleanup (Remove Legacy)

User requirement: "Make sure that there is no legacy, shims or anything besides having a clean and consistent api."

### Cleanup Checklist

#### 4.1: Remove Unused Imports

After deleting `interaction.zig` and `actions.zig`, verify no orphaned imports:

```bash
grep -r "interaction.zig\|actions.zig" src/
```

**Expected:** No results (already removed in functional refactor)

#### 4.2: Verify No Dead Code in logic.zig

Check `src/emulation/dma/logic.zig` for:
- ❌ Commented-out code
- ❌ Unused functions
- ❌ Debug print statements

**Action:** Review entire file, remove any dead code.

#### 4.3: Verify DmaInteractionLedger is Clean

Check `src/emulation/DmaInteractionLedger.zig`:
- ✅ Only has `reset()` and `duplication_occurred` flag
- ✅ No mutation methods
- ✅ No query methods
- ✅ Matches VBlankLedger pattern

#### 4.4: Check for Unused Fields in OamDma

File: `src/emulation/state/peripherals/OamDma.zig`

Fields to verify are used:
- `active` ✅
- `source_page` ✅
- `current_offset` ✅
- `current_cycle` ✅
- `needs_alignment` ✅
- `temp_value` ✅

**Action:** Verify each field is referenced in logic.zig.

#### 4.5: Check for Unused Fields in DmcDma

File: `src/emulation/state/peripherals/DmcDma.zig`

New fields:
- `transfer_complete` ✅ (added in Phase 1)

Verify all existing fields are used.

### Milestone 4: Clean Architecture Verification

Run grep checks:
```bash
# Should find NO results:
grep -r "TODO\|FIXME\|HACK\|XXX" src/emulation/dma/
grep -r "//.*unused\|//.*deprecated" src/emulation/dma/
```

**Expected:** Clean output (no legacy markers)

---

## Phase 5: Documentation Update

### 5.1: Update Session Document

**File:** `docs/sessions/2025-10-16-phase2e-implementation-complete.md`

**Content:**
- Summary of all changes
- Pattern compliance verification
- Test results (1030/1030 passing)
- Lessons learned
- Before/after architecture diagrams

### 5.2: Update CLAUDE.md if Needed

Check if DMA patterns should be documented in project overview.

**Decision:** If this becomes a reference pattern, add example to CLAUDE.md.

---

## Testing Strategy

### After Each Phase

| Phase | Test Command | Expected Result |
|-------|--------------|-----------------|
| Phase 1 | `zig build test-unit` | All passing (no regressions) |
| Phase 2 | `grep "dmc_oam" test output` | 12/12 passing (3 new passes) |
| Phase 3 | `zig build test --summary all` | 1030/1030 passing (100%) |
| Phase 4 | Manual grep checks | No legacy code found |

### Regression Prevention

Before each phase:
1. Run tests to establish baseline
2. Make changes
3. Run tests again
4. Compare results (should improve, never regress)

### Commercial ROM Testing (Optional Phase 6)

After achieving 1030/1030:
```bash
./zig-out/bin/RAMBO roms/smb.nes
./zig-out/bin/RAMBO roms/smb3.nes
./zig-out/bin/RAMBO roms/kirby.nes
```

**Expected:** All games work correctly (no crashes, correct rendering)

---

## Pattern Compliance Verification

### After Implementation

Verify all patterns match established idioms:

| Pattern | Reference | DMA Implementation |
|---------|-----------|-------------------|
| External state management | NMI/VBlank (execution.zig:105) | DMC completion ✅ |
| Skip work, not time | PPU odd-frame (State.zig:594) | OAM duplication ✅ |
| Direct field assignment | VBlank ledger (State.zig:646) | All ledger updates ✅ |
| Pure detection functions | TimingHelpers.shouldSkipOddFrame | All checks ✅ |
| Atomic state updates | NMI edge detection | DMC completion ✅ |

---

## Estimated Timeline

| Phase | Description | Estimated Time |
|-------|-------------|----------------|
| Phase 1 | DMC completion architecture | 30 minutes |
| Phase 2 | PPU skip pattern for duplication | 30 minutes |
| Phase 3 | Critical bug fixes | 15 minutes |
| Phase 4 | Code cleanup | 15 minutes |
| Phase 5 | Documentation | 20 minutes |
| **Total** | | **1 hour 50 minutes** |

---

## Success Criteria

- ✅ 1030/1030 tests passing (100%)
- ✅ No legacy code or workarounds remaining
- ✅ All patterns match established idioms
- ✅ DMC completion follows NMI/VBlank pattern
- ✅ OAM duplication follows PPU skip pattern
- ✅ Critical bugs fixed (corruption, fetch return)
- ✅ Commercial ROMs work correctly

---

## Risk Mitigation

### If Tests Fail After Phase 1

**Likely cause:** DMC completion timing changed

**Debug:**
1. Check `transfer_complete` is set in both places (cycle 0 and 1)
2. Verify `rdy_low` is cleared when flag is set
3. Verify timestamp is updated atomically

### If Tests Fail After Phase 2

**Likely cause:** Skip logic incorrect

**Debug:**
1. Verify `duplication_occurred` is set at pause
2. Verify skip check is `>= 510` not `== 510`
3. Verify cycle still increments during skip
4. Add debug print to see which cycles are skipped

### If Cleanup Phase Finds Issues

**Action:** Create new tickets for any found issues, fix in separate commits

---

## Commit Strategy

### Commit 1: Phase 1 (Architecture)
```bash
git add src/emulation/state/peripherals/DmcDma.zig
git add src/emulation/dma/logic.zig
git add src/emulation/cpu/execution.zig
git commit -m "refactor(dma): External state management for DMC completion

Follow NMI/VBlank pattern for DMC completion to eliminate timestamp
race condition. DMC signals completion via flag, execution.zig handles
state and timestamp atomically.

- Add transfer_complete flag to DmcDma
- Remove self-modification of rdy_low in tickDmcDma
- Handle completion externally in execution.zig
- Add missing return after DMC fetch (bug fix)

Fixes architectural issue identified by agent analysis.
Tests: All unit tests passing (no regressions)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
Co-Authored-By: Claude <noreply@anthropic.com>"
```

### Commit 2: Phase 2 (Duplication Fix)
```bash
git add src/emulation/DmaInteractionLedger.zig
git add src/emulation/cpu/execution.zig
git add src/emulation/dma/logic.zig
git commit -m "fix(dma): Apply PPU skip pattern to OAM byte duplication

Follow established PPU odd-frame skip pattern: skip work, not time.
After duplication, skip final read/write pair (cycles 510-511) while
maintaining deterministic cycle counting.

- Add duplication_occurred flag to DmaInteractionLedger
- Set flag when paused during read
- Skip final byte pair operations (preserve cycle advancement)
- Complete at cycle 512 (unchanged)

Result: 256 total writes (1 duplicate + 255 normal), no wrap.

Fixes 3 DMC/OAM conflict test failures.
Tests: 12/12 DMC/OAM tests passing

🤖 Generated with [Claude Code](https://claude.com/claude-code)
Co-Authored-By: Claude <noreply@anthropic.com>"
```

### Commit 3: Phase 3 (Critical Bugs)
```bash
git add src/emulation/State.zig
git add src/emulation/dma/logic.zig
git commit -m "fix(dma): Complete NTSC DMC corruption implementation

Fix two critical bugs in DMC DMA corruption emulation:
1. Capture last_read_address in busRead (was never set)
2. Simplify corruption logic to repeat ANY read (not just specific addresses)

Hardware-accurate NTSC 2A03 DPCM bug now fully emulated.

Tests: Full suite 1030/1030 passing (100%)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
Co-Authored-By: Claude <noreply@anthropic.com>"
```

### Commit 4: Phase 4+5 (Cleanup & Docs)
```bash
git add docs/sessions/2025-10-16-phase2e-implementation-complete.md
git add src/emulation/dma/logic.zig  # If any cleanup needed
git commit -m "docs(dma): Document clean architecture implementation

Final cleanup and documentation of Phase 2E DMA refactor:
- Verified no legacy code remaining
- Confirmed pattern compliance with NMI/VBlank/PPU skip idioms
- Documented implementation decisions and lessons learned

Architecture: Clean, consistent, follows established patterns.
Tests: 1030/1030 passing (100%)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Ready to Implement

This plan is:
- ✅ Completely researched (PPU skip pattern analyzed)
- ✅ Architecturally sound (follows established idioms)
- ✅ Thoroughly documented (step-by-step with code snippets)
- ✅ Testable at each milestone (clear verification points)
- ✅ Risk-mitigated (debug strategies provided)

**Status:** Awaiting approval to proceed with implementation.
