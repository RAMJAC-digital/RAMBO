# Phase 2E: DMA Research Findings - Hardware Behavior Analysis

**Date:** 2025-10-16
**Status:** 🔍 Research Complete, Critical Questions Identified
**Sources:** nesdev.org Wiki, test expectations, agent analysis

## Research Summary

After comprehensive multi-agent analysis and nesdev research, I've identified the exact expected behavior and the root causes of the 3 test failures.

## Test Expectations (From Code Comments)

### Expected Behavior (Line 226-227, dmc_oam_conflict_test.zig)

```zig
// Byte 0 should be in OAM[0] (duplication causes it to also appear in OAM[1])
try testing.expect(state.ppu.oam[0] == 0x00);
```

**Interpretation:**
- OAM[0] = byte 0 (duplicate write)
- OAM[1] = byte 0 (re-write after re-read)
- OAM[2] = byte 1
- ...
- OAM[255] = byte 254
- **Byte 255 is never transferred** (only 255 unique bytes)

### Expected Cycle Count (Line 10, 481-482)

```zig
//! - Total cycles = OAM base (513/514) + (DMC_count × 4)
...
// Should be 513 (OAM base) + 4 (DMC) = 517 CPU cycles
try testing.expectEqual(@as(u64, 517), elapsed_cpu);
```

**Interpretation:**
- OAM DMA normally: 513 cycles (even start) or 514 cycles (odd start)
- DMC DMA: 4 cycles
- **Total with one DMC interrupt: 513 + 4 = 517 cycles**

## NESdev Wiki Findings

### From DMA Wiki Page

**Priority:**
> "DMC DMA has higher priority than OAM DMA"

**Interruption Behavior:**
> "DMC DMA is allowed to run and OAM DMA is paused, trying again on the next cycle"

**Cycle Cost:**
> "Typical interruption costs 2 cycles: 1 cycle for DMC DMA get, 1 cycle for OAM DMA to realign"

**Note:** The wiki says 2 cycles total, but DMC actually takes 4 cycles. This suggests the "2 cycles" refers to overhead BEYOND the DMC duration, OR the wiki is discussing a specific scenario.

### Ambiguity in Documentation

The nesdev wiki does NOT explicitly state:
1. Whether the interrupted byte duplicates
2. How many total bytes transfer when duplication occurs
3. Whether OAM DMA completes early to maintain 256 total writes

## Current Implementation Behavior

### What Happens Now (Traced Through Code)

**Resume Logic (logic.zig:35-49):**

```zig
if (just_resumed) {
    ledger.oam_resume_cycle = now;

    if (ledger.paused_during_read) {
        state.ppu.oam[state.ppu.oam_addr] = ledger.paused_byte_value;  // Duplicate
        state.ppu.oam_addr +%= 1;  // Advance to OAM[1]
        ledger.paused_during_read = false;
    }
    // Fall through to continue normal operation
}

// ... continue with current_cycle (still at interrupted value)

const is_read_cycle = @rem(effective_cycle, 2) == 0;

if (is_read_cycle) {
    dma.temp_value = state.busRead(addr);  // Re-read same offset
} else {
    state.ppu.oam[state.ppu.oam_addr] = dma.temp_value;
    state.ppu.oam_addr +%= 1;  // Advance again
    dma.current_offset +%= 1;
}

dma.current_cycle += 1;
```

**Cycle-by-Cycle Trace (Interrupt at Byte 0):**

```
OAM Setup:
├─ Trigger $4014 write
├─ active = true, current_cycle = 0, current_offset = 0
└─ needs_alignment = false (even start)

DMC Triggers:
├─ triggerFetch($C000)
└─ rdy_low = true, stall_cycles_remaining = 4

Tick 1: (CPU cycle 0, PPU cycles 0-2)
├─ execution.zig: DMC active, OAM active
├─ Pause detection: effective_cycle = 0, is_reading = true
├─ Capture: paused_byte_value = 0x00, paused_during_read = true
├─ tickDmcDma(): stall -= 1 (now 3)
└─ OAM doesn't tick (paused)

Ticks 2-4: (DMC completes)
├─ DMC continues, OAM paused
└─ At end: rdy_low = false, last_dmc_inactive_cycle updated

Tick 5: (Resume)
├─ tickOamDma() called
├─ just_resumed = true (DMC inactive, was paused)
├─ Write duplicate: OAM[0] = 0x00, oam_addr = 1
├─ Fall through: effective_cycle = 0 (still)
├─ is_read_cycle = true
├─ Re-read byte 0: temp_value = 0x00
└─ current_cycle = 1

Tick 6:
├─ effective_cycle = 1
├─ is_read_cycle = false (write cycle)
├─ Write: OAM[1] = 0x00, oam_addr = 2
├─ Offset: current_offset = 1
└─ current_cycle = 2

Ticks 7-516:
├─ Continue normally
├─ Transfer bytes 1-254 to OAM[2]-OAM[255]
└─ current_cycle reaches 510

Tick 517:
├─ effective_cycle = 510
├─ Read byte 255: temp_value = 0xFF
└─ current_cycle = 511

Tick 518:
├─ effective_cycle = 511
├─ Write: OAM[oam_addr] = 0xFF
├─ BUT oam_addr wraps! 256 % 256 = 0
├─ OAM[0] = 0xFF (OVERWRITES the duplicate!)
└─ current_cycle = 512

Tick 519:
├─ effective_cycle = 512
├─ Completion check: >= 512, DMA completes
└─ Total cycles: 517 + pause overhead
```

**Result:**
- ✅ Cycle count: 517 total (correct!)
- ❌ OAM[0] = 0xFF (WRONG - test expects 0x00)
- ❌ 257 writes performed (256 normal + 1 duplicate)

## Root Cause Identified

### The Problem

**We perform 257 total writes when we should perform 256.**

1. Duplicate write: OAM[0] = byte 0
2. Re-write: OAM[1] = byte 0
3. Normal writes: OAM[2]-OAM[255] = bytes 1-254 (253 writes)
4. **Extra write: OAM[0] = byte 255 (wraps, overwrites duplicate!)**

### Why This Happens

The current code:
- Writes the duplicate "for free" during resume
- Then continues with the FULL 512 cycles of operations
- This gives 513 operations total (1 duplicate + 512 normal)
- But 512 cycles = 256 read/write pairs = 256 more writes
- **Total: 257 writes**

### What Should Happen

Based on test expectations:
- 256 total OAM slots filled
- Byte 0 occupies slots 0 and 1
- Bytes 1-254 occupy slots 2-255
- Byte 255 never transfers
- **Total: 256 writes, 255 unique bytes**

## Critical Analysis: Three Possible Interpretations

### Interpretation A: Duplicate Doesn't Count (Hardware Quirk)

**Theory:** The duplicate write happens "outside" normal cycle counting.

**Sequence:**
```
Pause at cycle 0 (read):
└─ Byte 0 read into temp buffer

Resume (special cycle):
├─ Write temp buffer → OAM[0] (duplicate, doesn't increment cycle)
└─ Continue at cycle 0

Cycle 0: Re-read byte 0
Cycle 1: Write byte 0 → OAM[1]
Cycles 2-509: Transfer bytes 1-254
Cycle 510: Read byte 255
Cycle 511: Would write byte 255, but DMA TERMINATES EARLY
```

**Result:** 256 writes (1 duplicate + 255 normal), cycle 512 never happens

**Issue:** This contradicts the wiki saying OAM DMA completes its full 513 cycles.

### Interpretation B: Duplicate Replaces Write Cycle

**Theory:** The duplicate write happens IN PLACE of cycle 1's write.

**Sequence:**
```
Pause at cycle 0 (read):
└─ Byte 0 read into temp buffer

Resume at cycle 0:
├─ Write duplicate → OAM[0] (counts as cycle 1's write!)
└─ Skip to cycle 2

Cycle 2: Read byte 1 (skip re-reading byte 0)
Cycle 3: Write byte 1 → OAM[1]
Cycles 4-511: Transfer bytes 2-255 normally
```

**Result:** 256 writes (1 duplicate + 255 normal for bytes 1-255)

**Issue:** This contradicts test expectations (byte 0 should appear in OAM[1]).

### Interpretation C: OAM Address Doesn't Advance on Duplicate

**Theory:** Duplicate write goes to SAME address as re-write.

**Sequence:**
```
Resume at cycle 0:
├─ Write duplicate → OAM[0] (DON'T increment oam_addr!)
└─ Continue at cycle 0

Cycle 0: Re-read byte 0
Cycle 1: Write byte 0 → OAM[0] AGAIN (overwrites duplicate)
├─ NOW increment oam_addr → 1
└─ Increment offset → 1

Cycles 2-511: Transfer bytes 1-255 normally
```

**Result:** 256 writes, all 256 bytes transfer, no wrap

**Issue:** This contradicts test expectations (byte 0 should appear in BOTH OAM[0] and OAM[1]).

## The Correct Interpretation (Based on All Evidence)

After analyzing all evidence, **Interpretation A** is most consistent with test expectations, but needs refinement:

### Refined Theory: Early Termination After Duplication

**Key Insight:** When duplication occurs, OAM DMA terminates one cycle early to prevent wrap.

**Sequence:**
```
Normal OAM DMA: 513 cycles (even start)
├─ Cycle -1: Alignment (needs_alignment check)
├─ Cycles 0-511: 256 read/write pairs (512 operations)
└─ Cycle 512: Check completion, DMA ends

With Duplication at Byte 0:
├─ Cycle 0: Read byte 0 (INTERRUPTED before write)
├─ [DMC runs 4 cycles]
├─ Resume: Write duplicate → OAM[0], oam_addr = 1
├─ Cycle 0: Re-read byte 0 → temp_value
├─ Cycle 1: Write byte 0 → OAM[1], oam_addr = 2, offset = 1
├─ Cycles 2-509: Transfer bytes 1-254 → OAM[2]-OAM[255]
└─ Cycle 510: Check completion EARLY (duplication flag set), DMA ends
```

**Mechanism:** After duplication, the completion check should be `>= 510` instead of `>= 512`.

**Result:**
- 256 total writes ✅
- Byte 0 in OAM[0] and OAM[1] ✅
- Bytes 1-254 in OAM[2]-OAM[255] ✅
- Byte 255 never transfers ✅
- Total cycles: 517 (513 base - 2 skipped + 4 DMC + 2 overhead) ✅

## CRITICAL QUESTIONS FOR USER

Before implementing, I need clarification on:

### Question 1: Completion Cycle Adjustment

Should the completion check be adjusted when duplication occurs?

**Current Code:**
```zig
if (effective_cycle >= 512) {
    dma.reset();  // Complete
}
```

**Proposed Fix:**
```zig
// Track if duplication occurred
const duplication_occurred = ledger.oam_resume_cycle > 0 and ledger.paused_during_read_initial;

// Terminate 2 cycles early if duplication happened
const completion_cycle: i32 = if (duplication_occurred) 510 else 512;

if (effective_cycle >= completion_cycle) {
    dma.reset();  // Complete
}
```

**Is this the correct approach?**

### Question 2: Total Cycle Count Verification

The test expects exactly 517 cycles with one DMC interrupt. Let me verify:

```
Normal OAM: 513 cycles
DMC interrupt: 4 cycles
Total: 517 cycles ✅
```

This matches! But should the OAM portion still be 513, or does it become 511 due to early termination?

**Calculation:**
```
Normal: 1 alignment + 512 operations = 513
With dup: 1 alignment + 510 operations + 2 for dup/re-read = 513
Total: 513 (OAM) + 4 (DMC) = 517 ✅
```

**Is this interpretation correct?**

### Question 3: Architectural Pattern for DMC Completion

Three agents identified a timestamp race condition. Should we fix this first (architectural) or fix byte duplication first (functional)?

**Architect recommendation:** Fix timestamp race first (use external state management)
**My recommendation:** Fix duplication first (it's the immediate blocker), then refactor architecture

**Which approach do you prefer?**

## Proposed Implementation Plan

### Phase 1: Fix Byte Duplication (Immediate)

**Step 1:** Track duplication occurrence
```zig
// In DmaInteractionLedger
paused_during_read_initial: bool = false,  // Capture at pause, don't clear
```

**Step 2:** Adjust completion check
```zig
const duplication_occurred = (ledger.oam_resume_cycle > 0 and
                              ledger.paused_during_read_initial);
const completion_cycle: i32 = if (duplication_occurred) 510 else 512;

if (effective_cycle >= completion_cycle) {
    dma.reset();
    ledger.reset();
    return;
}
```

**Step 3:** Test verification
- Run "DMC interrupts OAM at byte 0" - should pass
- Run "Cycle count: OAM 513 + DMC 4 = 517" - verify still correct
- Run all 12 DMC/OAM tests

**Estimated time:** 30 minutes

### Phase 2: Fix DMC Critical Bugs (Code Quality)

**Bug #1:** Add return after DMC fetch (5 min)
**Bug #2:** Capture last_read_address in busRead (10 min)
**Bug #3:** Simplify DMC corruption logic (5 min)

**Estimated time:** 20 minutes

### Phase 3: Fix Timestamp Race (Architectural - Optional)

Only if Phase 1 doesn't fully resolve the issue.

**Estimated time:** 1 hour

## Files Requiring Changes

### Phase 1 (Duplication Fix)
1. `src/emulation/DmaInteractionLedger.zig` - Add paused_during_read_initial field
2. `src/emulation/cpu/execution.zig` - Set flag at pause
3. `src/emulation/dma/logic.zig` - Adjust completion check

### Phase 2 (Critical Bugs)
4. `src/emulation/dma/logic.zig` - Add return, fix corruption
5. `src/emulation/State.zig` - Capture last_read_address

### Phase 3 (Architecture - If Needed)
6. `src/emulation/state/peripherals/DmcDma.zig` - Add transfer_complete flag
7. `src/emulation/cpu/execution.zig` - External DMC completion handling

## Summary and Next Steps

### Key Findings

1. ✅ **Root cause identified:** 257 writes instead of 256 due to no early termination
2. ✅ **Fix proposed:** Terminate 2 cycles early when duplication occurs
3. ✅ **Critical bugs found:** 3 unrelated DMC bugs that need fixing
4. ⚠️ **Architecture issue:** Timestamp race exists but may not be causing current failures

### Confidence Levels

- **Duplication fix:** 85% confident this resolves the 3 test failures
- **Cycle count:** 95% confident 517 is correct total
- **Pattern compliance:** 90% confident architecture refactor is optional

### Recommended Action

1. **User reviews this document** and answers the 3 critical questions
2. **Implement Phase 1** (duplication fix) - 30 minutes
3. **Run tests** - verify 3 failures become passes
4. **Implement Phase 2** (critical bugs) - 20 minutes
5. **Run full suite** - achieve 1030/1030 passing (100%)
6. **Phase 3 optional** - only if issues remain

## Open Questions Requiring User Input

❓ **Question 1:** Is early termination (effective_cycle >= 510) the correct fix?
❓ **Question 2:** Should total cycle count remain 517 with early termination?
❓ **Question 3:** Fix duplication first (functional) or architecture first (pattern)?

**Status:** Awaiting user review and approval to proceed with implementation.
