# Phase 2E: DMC/OAM DMA Clean Architecture - MASTER DOCUMENT

**Date:** 2025-10-16
**Status:** BLOCKED - Architecture violations + bugs identified
**This is the ONLY authoritative document for this work.**

---

## Executive Summary

**Situation:** Implementing clean architecture for DMA, discovered fundamental architectural violations AND hardware bugs.

**Critical Findings:**
- 4 failing tests (byte duplication + timing)
- Major architectural violations (3-phase pattern broken)
- Need to decide: Fix architecture first OR patch bugs?

---

## Hardware Specification (Authoritative)

### OAM DMA Base Behavior (nesdev.org/wiki/DMA)

**Timing:**
- **Even CPU cycle start:** 513 cycles total
  - 1 dummy read cycle
  - 512 data cycles (256 read/write pairs)
- **Odd CPU cycle start:** 514 cycles total
  - 1 alignment cycle
  - 1 dummy read cycle
  - 512 data cycles

**Transfer:** 256 bytes from $XX00-$XXFF → OAM ($2004)

### DMC/OAM Interaction

**Priority:** DMC DMA has absolute priority, pauses OAM DMA

**Interrupt behavior:**
- DMC takes 2 cycles typically (1 DMC get + 1 OAM realignment)
- OAM state preserved during pause
- **Hardware complexity:** "Byte read twice" behavior is AMBIGUOUS
  - May involve address mangling/misalignment (per authoritative spec)
  - Test expects: Same byte appears in consecutive OAM slots
  - Implementation must allow re-reading same source offset
  - Current code SKIPS the byte instead of re-reading (BUG)

**Cycle behavior during pause:**
- OAM cycle counter FREEZES
- Counters resume from same state after DMC completes

---

## Current Test Failures (4 total)

### 1. Byte Duplication Test FAILS
**File:** `tests/integration/dmc_oam_conflict_test.zig:256`
**Expected:** Same byte appears in consecutive OAM slots
**Actual:** No duplication detected

**Root Cause:** `actions.zig:156` - `dma.current_offset +%= 1`
- This SKIPS the byte instead of allowing re-read
- Hardware requires: byte read, written, THEN READ AGAIN

**Fix:**
```zig
.duplication_write => {
    ppu_oam_addr.* +%= 1; // Advance OAM slot
    // REMOVE: dma.current_offset +%= 1;  <-- THIS LINE
    // Do NOT advance cycle - free operation
    dma.phase = .resuming_normal;
    ledger.clearDuplication();
}
```

### 2. Even Cycle Timing FAILS
**File:** `tests/integration/oam_dma_test.zig:153`
**Expected:** 513 CPU cycles
**Actual:** 512 CPU cycles

**Root Cause:** `actions.zig:166` and `179` - Completion threshold off by 1

**Fix:**
```zig
// Line 79: Change from
if (effective_cycle > 511) {
// To:
if (effective_cycle >= 512) {  // >= not > (completes after cycle 511)

// Line 166: Change from
if (effective_cycle >= 512) {
// To:
if (effective_cycle >= 513) {  // Completion threshold for 513 cycles
```

**Cycle counting logic:**
- Cycles 0-511 = 512 cycles
- Cycles 0-512 = 513 cycles
- Use `>= 512` to skip at cycle 512 (completes after 511)

### 3. Odd Cycle Timing FAILS
**File:** `tests/integration/oam_dma_test.zig:187`
**Expected:** 514 CPU cycles
**Actual:** 513 CPU cycles

**Root Cause:** Same as #2

**Fix:** Same as #2

### 4. Resume Edge Detection FAILS
**File:** `src/emulation/dma/interaction.zig:338`
**Expected:** `shouldOamResume` returns false on cycle 1005
**Actual:** Returns true (triggers every cycle after DMC completes)

**Root Cause:** Function ignores `cycle` parameter (line 155: `_ = cycle;`)

**Fix:**
```zig
pub fn shouldOamResume(
    ledger: *const DmaInteractionLedger,
    oam: *const OamDma,
    dmc_active: bool,
    cycle: u64,
) bool {
    return isPaused(oam.phase) and
        !dmc_active and
        ledger.oam_pause_cycle > 0 and
        ledger.oam_resume_cycle < ledger.oam_pause_cycle and
        ledger.last_dmc_inactive_cycle == cycle;  // ADD THIS LINE
}
```

---

## Critical Architectural Violations

### VIOLATION 1: "Pure" Functions Mutating State

**Location:** `interaction.zig:32-54`

```zig
/// CLAIMS: "Pure function - modifies ledger and returns pause action"
pub fn handleDmcPausesOam(
    ledger: *DmaInteractionLedger,  // MUTABLE!
    oam: *const OamDma,
    cycle: u64,
) PauseAction {
    // ...
    ledger.recordOamPause(cycle, interrupted);  // MUTATION!
```

**Problem:** Documentation says "pure" but function mutates ledger.

**Impact:** Breaks referential transparency, impossible to test in isolation.

### VIOLATION 2: Side Effects in Query Phase

**Location:** `execution.zig:146-157`

```zig
// This is supposed to be QUERY phase (pure, no mutations)
const action = DmaInteraction.handleDmcPausesOam(...); // MUTATES ledger

// BUS READ during query!
if (action.read_interrupted_byte) |read_info| {
    const addr = (@as(u16, read_info.source_page) << 8) | read_info.offset;
    state.dma_interaction_ledger.interrupted_state.byte_value = state.busRead(addr);
    state.dma_interaction_ledger.interrupted_state.oam_addr = state.ppu.oam_addr;
}
```

**Problem:** Query phase performing bus reads and state mutations.

**Impact:** Completely breaks 3-phase pattern (Query → Execute → Update).

### VIOLATION 3: Direct Field Mutations

**Location:** `execution.zig:155-156`

```zig
state.dma_interaction_ledger.interrupted_state.byte_value = state.busRead(addr);
state.dma_interaction_ledger.interrupted_state.oam_addr = state.ppu.oam_addr;
```

**Problem:** Bypassing ledger encapsulation, directly mutating internal fields.

**Impact:** Breaks abstraction, makes refactoring dangerous.

### VIOLATION 4: Business Logic in Ledger

**Location:** `DmaInteractionLedger.zig:92-94`

```zig
pub fn recordOamPause(...) void {
    self.oam_pause_cycle = cycle;
    self.interrupted_state = state;

    // Business logic decision in data structure!
    if (state.was_reading) {
        self.duplication_pending = true;
    }
}
```

**Problem:** Ledger mixing data recording with business logic.

**CRITICAL DIFFERENCE from VBlankLedger:**

VBlankLedger has **ONLY** a `reset()` method. ALL mutations happen in EmulationState.

DmaInteractionLedger VIOLATES this by having 6+ mutation methods:
- `recordDmcActive()` - Should be in EmulationState
- `recordDmcInactive()` - Should be in EmulationState
- `recordOamPause()` - Should be in EmulationState
- `recordOamResume()` - Should be in EmulationState
- `clearDuplication()` - Should be in EmulationState
- `clearPause()` - Should be in EmulationState

**Impact:** Violates single responsibility, spreads mutations across codebase, impossible to track state changes.

---

## Correct Architecture Pattern (VBlankLedger)

```zig
pub const VBlankLedger = struct {
    last_set_cycle: u64 = 0,      // Pure data
    last_clear_cycle: u64 = 0,    // Pure data
    last_read_cycle: u64 = 0,     // Pure data
    race_hold: bool = false,      // Pure data

    pub fn reset(self: *VBlankLedger) void {
        self.* = .{};  // Only mutation method
    }

    // NO business logic
    // NO decision-making
    // Just timestamps
};
```

**All mutations happen in EmulationState**, not in the ledger.

---

## Decision Point

**Option A: Fix Architecture First**
- Refactor to proper 3-phase pattern
- Move all mutations to single location
- Make functions truly pure
- Then fix bugs

**Pros:** Clean, maintainable, correct
**Cons:** More work, delays bug fixes

**Option B: Patch Bugs Now**
- Apply the 4 fixes identified
- Accept architectural debt
- Document violations

**Pros:** Fast, tests pass
**Cons:** Technical debt, harder to maintain

---

## Action Plan (PENDING USER DECISION)

### IF Option A (Fix Architecture):
1. Refactor `handleDmcPausesOam` to be truly pure (return data, no mutations)
2. Move all ledger mutations to `execution.zig` in centralized location
3. Separate query phase (pure) from mutation phase
4. Simplify ledger to pure data (remove business logic)
5. Then apply bug fixes
6. Run tests

### IF Option B (Patch Bugs):
1. Fix byte duplication (remove offset increment)
2. Fix cycle count threshold (512→513)
3. Fix resume edge detection (add cycle check)
4. Run tests
5. Document architectural debt in this file

---

## Files Modified (for either option)

**Bug fixes only:**
- `src/emulation/dma/actions.zig` (3 changes)
- `src/emulation/dma/interaction.zig` (1 change)

**Architecture refactor:**
- `src/emulation/dma/interaction.zig` (major refactor)
- `src/emulation/DmaInteractionLedger.zig` (simplify to pure data)
- `src/emulation/cpu/execution.zig` (centralize mutations)
- `src/emulation/dma/actions.zig` (same bug fixes)

---

## Test Output Location

**Full test output saved:** `/tmp/dma_test_full_output.txt`

**Summary:** 1041/1050 passing, 4 DMA failures

---

## Fix Verification Plan

### After Applying Fixes:

1. **Run integration tests:**
   ```bash
   zig build test 2>&1 | tee /tmp/phase2e_verification.txt
   ```

2. **Verify 4 DMA tests pass:**
   - "Byte duplication: Interrupted during read cycle"
   - "OAM DMA: even cycle start takes exactly 513 CPU cycles"
   - "OAM DMA: odd cycle start takes exactly 514 CPU cycles"
   - "interaction: shouldOamResume logic"

3. **Check for regressions:**
   - Full test suite should maintain or improve from 1041/1050
   - No new failures in other DMA tests

4. **Test with commercial ROMs:**
   - Castlevania (uses DMC)
   - Mega Man (uses DMC)
   - Verify no rendering regressions

---

## Notes

- User under extreme time pressure (eviction court 2 weeks)
- Cannot afford wasted time on unfocused work
- Need clear decision and execution plan
- This document is the ONLY source of truth - do not create additional docs

---

**AWAITING USER DECISION: Option A (fix architecture) or Option B (patch bugs)?**
