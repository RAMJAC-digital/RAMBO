# Phase 2E: Multi-Agent Analysis Synthesis - DMA Resume Logic

**Date:** 2025-10-16
**Status:** 🔍 Analysis Complete, Awaiting Implementation Plan
**Agents:** architect-reviewer, debugger, code-reviewer

## Executive Summary

Three specialist agents conducted independent reviews of the functional DMA implementation. While the architectural refactor is **fundamentally sound**, all agents identified a **critical timing issue** that explains the 3 test failures. Additionally, 2 critical bugs unrelated to the test failures were discovered that would affect commercial ROM compatibility.

## Agent Findings Comparison

| Finding | Architect | Debugger | Code Reviewer | Severity |
|---------|-----------|----------|---------------|----------|
| Timestamp race condition | ✅ Primary focus | ✅ Identified | ⚠️ Implied | **CRITICAL** |
| Byte duplication 257 writes | ⚠️ Not mentioned | ✅ Root cause | ⚠️ Analyzed | **CRITICAL** |
| DMC fetch missing return | ⚠️ Not checked | ⚠️ Not checked | ✅ Found (Issue #2) | **CRITICAL** |
| last_read_address not set | ⚠️ Not checked | ⚠️ Not checked | ✅ Found (Issue #9) | **CRITICAL** |
| DMC corruption incomplete | ⚠️ Not checked | ⚠️ Not checked | ✅ Found (Issue #8) | HIGH |
| VBlank pattern deviation | ✅ Architectural focus | ⚠️ Not checked | ⚠️ Mentioned | MEDIUM |

## Critical Issue #1: Timestamp Race Condition (All Agents)

### Problem Statement

The **architect agent** identified the core architectural issue:

> "DMC DMA modifies its own completion state (`rdy_low = false`) but edge detection happens externally in `execution.zig`. This creates a race condition where timestamps lag behind state changes by one cycle."

**Timeline of the race:**

```
Cycle N: DMC completes
├─ tickDmcDma() sets rdy_low = false (line 119)
├─ OAM checks: dmc_is_active = (last_dmc_active > last_dmc_inactive)
├─ Result: TRUE (last_dmc_inactive not updated yet!)
└─ OAM stays paused incorrectly

Cycle N+1: Edge detection happens (too late)
├─ execution.zig updates last_dmc_inactive_cycle
└─ OAM can now resume (but lost a cycle)
```

### Why This Violates VBlank Pattern

The **architect agent** correctly identified this as a **pattern violation**:

**VBlank Pattern (CORRECT):**
```zig
// PPU sets vblank flag
ppu.status |= 0x80;  // Set vblank

// execution.zig detects edge and records timestamp
if (!prev_vblank and curr_vblank) {
    ledger.last_set_cycle = now;
}

// Edge detection and timestamp happen in ONE place
// State change and timestamp are synchronous
```

**Current DMA Pattern (INCORRECT):**
```zig
// DMC clears its own completion state
tickDmcDma() {
    state.dmc_dma.rdy_low = false;  // Self-modification
}

// execution.zig detects edge LATER (next cycle)
if (!dmc_is_active and dmc_was_active) {
    ledger.last_dmc_inactive_cycle = now;  // One cycle late
}

// State change and timestamp are ASYNCHRONOUS (race condition)
```

### Debugger's Evidence

The **debugger agent** found the fix empirically:

> "Moved edge detection to happen AFTER `tickDmcDma()`, checking both before and after states to properly detect the inactive edge."

This partially fixed the issue but didn't address the architectural problem.

### Code Reviewer's Perspective

The **code reviewer** noted the timing implications:

> "DMC fetch cycle executes idle logic too (missing return). This causes the idle cycle logic to run during the fetch, creating additional bus reads."

While focused on a different bug, this highlights timing sensitivity.

## Critical Issue #2: Byte Duplication 257 Writes (Debugger)

### Problem Statement

The **debugger agent** identified the exact failure mechanism:

> "After the duplicate write, OAM DMA performs 256 more read/write cycles, totaling 257 writes. This causes `oam_addr` to wrap from 255 to 0, overwriting OAM[0] with byte 255."

**Current behavior trace:**

```
Resume (cycle 0):
├─ Write duplicate byte 0 → OAM[0], oam_addr = 1
└─ Fall through to normal operation

Cycle 0 (read):
├─ Read byte 0 from offset 0 → temp_value

Cycle 1 (write):
├─ Write byte 0 → OAM[1], oam_addr = 2, offset = 1

Cycles 2-511 (normal):
├─ Transfer bytes 1-254 → OAM[2]-OAM[255]

Cycle 512 (completion):
├─ Read byte 255 from offset 255
└─ oam_addr wraps to 0

Cycle 513 (EXTRA WRITE):
├─ Write byte 255 → OAM[0] (OVERWRITES duplicate!)
└─ oam_addr = 1, offset wraps to 0
```

**Result:** OAM[0] contains byte 255, not byte 0. Test expects 0x00, gets 0xFF.

### Root Cause Analysis

The debugger identified the core question:

> "Does the duplicate write consume an OAM slot, or does it replace the normal write?"

**Hardware behavior (per nesdev.org):**

The DMC/OAM conflict page states:
> "The DMA will restart where it left off, but the byte read before it was interrupted will be written again."

This is **ambiguous**. It could mean:
1. Byte N writes twice (duplicate + re-write) = 257 total writes
2. Byte N writes twice BUT DMA terminates one cycle early = 256 total writes
3. Duplicate replaces the normal write (no re-read) = 256 total writes

### Test Expectations

Looking at the test comment:
```zig
// Byte 0 should be in OAM[0] (duplication causes it to also appear in OAM[1])
try testing.expect(state.ppu.oam[0] == 0x00);
```

This suggests:
- OAM[0] = byte 0 (duplicate)
- OAM[1] = byte 0 (re-write)
- OAM[2] = byte 1
- ...
- OAM[255] = byte 254
- **Byte 255 never transfers** (only 255 unique bytes)

### Question for User

**CRITICAL AMBIGUITY:** We need to determine the exact hardware behavior:

**Option A:** Duplication adds an extra write (257 total)
- Result: OAM wraps, last byte overwrites OAM[0]
- Test would need to be updated

**Option B:** Duplication happens but DMA still completes at cycle 512
- Result: Only 255 unique bytes transfer
- OAM[0] preserved
- This matches current test expectations

**Option C:** Duplication doesn't increment oam_addr
- Result: Duplicate and re-write go to same OAM[0]
- Only 256 unique bytes transfer
- Test would fail (OAM[1] != 0)

## Critical Issue #3: DMC Fetch Cycle Bug (Code Reviewer)

### Problem Statement

The **code reviewer** found a critical bug in DMC logic:

> "Lines 110-119 handle `cycle == 1` (final fetch cycle). After fetching the sample byte, the code clears `rdy_low = false` (line 119). However, **the function then continues to line 120** and enters the `else` block!"

**Code (src/emulation/dma/logic.zig:110-142):**

```zig
if (cycle == 1) {
    // Final cycle: Fetch sample byte
    const address = state.dmc_dma.sample_address;
    state.dmc_dma.sample_byte = state.busRead(address);
    ApuLogic.loadSampleByte(&state.apu, state.dmc_dma.sample_byte);
    state.dmc_dma.rdy_low = false;
    // MISSING RETURN - falls through to else block!
} else {
    // Idle cycles (2-4): CPU repeats last read
    if (has_dpcm_bug) {
        _ = state.busRead(state.dmc_dma.last_read_address);
    }
}
```

**Impact:** On the fetch cycle, the code:
1. Reads the sample byte from the correct address ✅
2. Loads it into APU ✅
3. **Then ALSO repeats the last read (idle cycle logic)** ❌

This causes two bus reads on the same cycle, potentially corrupting controller state or triggering mapper side effects twice.

**Fix:** Add `return;` after line 119.

## Critical Issue #4: DMC Corruption Non-Functional (Code Reviewer)

### Problem Statement

The **code reviewer** discovered the corruption feature is completely broken:

> "The `DmcDma` struct has a `last_read_address` field, but **this field is never set anywhere in the codebase!**"

**Evidence:**

```bash
$ grep -r "last_read_address.*=" src/
# No results!
```

**Impact:** The NTSC 2A03 DPCM bug (controller corruption) is not emulated. Games that work around this bug may behave incorrectly.

**Fix:** Capture the last CPU read address in `busRead()`:

```zig
pub fn busRead(self: *EmulationState, address: u16) u8 {
    self.dmc_dma.last_read_address = address;
    // ... rest of busRead
}
```

## Critical Issue #5: DMC Corruption Incomplete (Code Reviewer)

### Problem Statement

The corruption logic only handles specific addresses:

```zig
if (has_dpcm_bug) {
    if (last_addr == 0x4016 or last_addr == 0x4017) {
        _ = state.busRead(last_addr);  // Controllers only
    }
    if (last_addr == 0x2002 or last_addr == 0x2007) {
        _ = state.busRead(last_addr);  // PPU only
    }
}
```

**Missing:** APU registers, mapper IRQ counters, expansion audio, etc.

**Fix:** Simplify to repeat ANY read:

```zig
if (has_dpcm_bug) {
    _ = state.busRead(state.dmc_dma.last_read_address);
}
```

## Architectural Pattern Comparison: DMA vs NMI/IRQ

Let me compare the patterns to ensure consistency:

### NMI Edge Detection Pattern

**File:** `src/emulation/cpu/execution.zig` (around line 105)

```zig
// NMI edge detection (functional pattern)
const nmi_active = (ledger.last_set_cycle > ledger.last_clear_cycle);
const prev_nmi = state.cpu.nmi_line;
const curr_nmi = nmi_active;

// Record edge
if (curr_nmi and !prev_nmi) {
    // NMI triggered
    state.cpu.nmi_line = true;
}

// State mutation happens BEFORE logic uses it
// No race condition - all checks see consistent state
```

### IRQ Level Detection Pattern

```zig
// IRQ is level-triggered (not edge)
const irq_active = (state.apu.irq_flag or state.cart.irq_flag);

if (irq_active and !state.cpu.p.i) {
    // IRQ triggers
}

// Simple boolean check - no timestamps needed
```

### Current DMA Pattern (FLAWED)

```zig
// DMC completion (self-modification - WRONG)
tickDmcDma() {
    if (cycle == 1) {
        state.dmc_dma.rdy_low = false;  // Clears OWN state
    }
}

// Edge detection (external - happens LATER)
const dmc_was_active = (ledger.last_dmc_active > ledger.last_dmc_inactive);
const dmc_is_active = state.dmc_dma.rdy_low;

if (!dmc_is_active and dmc_was_active) {
    ledger.last_dmc_inactive_cycle = now;  // One cycle late!
}

// OAM resume (relies on timestamps)
const just_resumed = !dmc_is_active and was_paused;

// RACE: dmc_is_active uses hardware state (current)
//       but timestamp isn't updated until next cycle
```

### Correct DMA Pattern (Following NMI/IRQ)

**Option 1: External State Management (RECOMMENDED)**

```zig
// DMC signals completion via flag (doesn't self-modify rdy_low)
tickDmcDma() {
    if (cycle == 1) {
        state.dmc_dma.transfer_complete = true;  // Signal
        // Don't touch rdy_low
    }
}

// execution.zig handles ALL state transitions
if (state.dmc_dma.transfer_complete) {
    state.dmc_dma.rdy_low = false;  // External modification
    state.dmc_dma.transfer_complete = false;
    ledger.last_dmc_inactive_cycle = now;  // Synchronous
}

// Now OAM can check and see consistent state
```

**Option 2: Immediate Timestamp Update**

```zig
// If DMC must clear rdy_low, update timestamp immediately
tickDmcDma() {
    if (cycle == 1) {
        state.dmc_dma.rdy_low = false;
        // Update timestamp HERE (same cycle as state change)
        state.dma_interaction_ledger.last_dmc_inactive_cycle = state.clock.ppu_cycles;
    }
}

// No separate edge detection needed
```

## Summary of Findings

### Test Failures Root Cause

The 3 failing tests all stem from **Critical Issue #2 (257 writes)**:

1. **"DEBUG: Trace complete DMC/OAM interaction"** - Debug test that verifies the sequence
2. **"DMC interrupts OAM at byte 0"** - OAM[0] overwritten by wrap
3. **"Multiple DMC interrupts"** - Same wrap issue

### Bugs Unrelated to Tests

- **Issue #3:** DMC fetch missing return (would affect accuracy tests)
- **Issue #4:** last_read_address not captured (breaks corruption feature)
- **Issue #5:** Incomplete corruption logic (missing mapper/APU)

### Architectural Findings

- **Issue #1:** Timestamp race violates VBlank pattern (affects all DMA operations)

## Critical Questions Requiring User Input

Before proceeding with implementation, we need answers to:

### Question 1: Byte Duplication Hardware Behavior

When DMC interrupts OAM during a read cycle, what EXACTLY happens?

**A)** Duplicate write + re-read + normal continuation = 257 writes total?
**B)** Duplicate write + re-read + early termination = 256 writes (255 unique bytes)?
**C)** Duplicate write replaces normal write (no re-read) = 256 writes (256 unique bytes)?

**Test expectations suggest B**, but nesdev.org documentation is ambiguous.

**Required Research:**
- Check nesdev.org/wiki/APU_DMC#DMA_conflict for exact wording
- Look for hardware test results or emulator test ROMs
- Check blargg's test ROMs for DMA conflict tests
- Review other accurate emulators (Mesen, puNES)

### Question 2: Pattern Compliance Priority

Should we fix the timestamp race condition first (architectural), or the byte duplication (functional)?

**Option A:** Fix architecture first (timestamp race), then debug duplication
**Option B:** Fix duplication first (test failures), then refactor architecture

Recommendation: **Option A** - architectural correctness ensures the fix is built on solid foundation.

### Question 3: DMC Completion Pattern

Which pattern should we use for DMC completion?

**Option A:** External state management (like NMI/IRQ) - more consistent
**Option B:** Immediate timestamp update - simpler change

Recommendation: **Option A** - maintains consistency with established patterns.

## Recommended Implementation Sequence

Assuming answers to questions above:

### Phase 1: Fix Critical Bugs (Unrelated to Tests)

1. **Add return after DMC fetch** (Issue #3) - 5 min
2. **Capture last_read_address in busRead** (Issue #4) - 10 min
3. **Simplify DMC corruption logic** (Issue #5) - 5 min

**Validation:** Build should compile, existing tests should still pass

### Phase 2: Fix Timestamp Race (Architectural)

1. **Add transfer_complete flag to DmcDma** - 5 min
2. **Remove rdy_low = false from tickDmcDma** - 2 min
3. **Handle completion in execution.zig** - 15 min
4. **Update all timestamp assignments to be synchronous** - 10 min

**Validation:** DMC/OAM interaction should be more predictable, might fix some tests

### Phase 3: Fix Byte Duplication (Based on Research)

1. **Research exact hardware behavior** - 30-60 min
2. **Implement correct duplication sequence** - 20 min
3. **Adjust cycle counting if needed** - 10 min

**Validation:** All 3 failing tests should pass

### Phase 4: Verification

1. **Run full test suite** - 2 min
2. **Test commercial ROMs** - 10 min
3. **Document findings** - 15 min

**Total estimated time:** 2-3 hours

## Files Requiring Modification

### Core Implementation
1. `src/emulation/dma/logic.zig` - tickDmcDma, tickOamDma
2. `src/emulation/cpu/execution.zig` - DMC edge detection
3. `src/emulation/State.zig` - busRead to capture last_read_address
4. `src/emulation/state/peripherals/DmcDma.zig` - Add transfer_complete flag

### Testing
5. `tests/integration/dmc_oam_conflict_test.zig` - May need adjustment based on hardware research

## Next Steps

1. **User reviews this analysis** - Confirms approach, answers questions
2. **Research hardware behavior** - Get definitive answer on byte duplication
3. **Create detailed implementation plan** - Step-by-step with code snippets
4. **Implement Phase 1** - Fix unrelated bugs first
5. **Implement Phase 2** - Fix architectural issue
6. **Implement Phase 3** - Fix byte duplication based on research
7. **Verify and document** - Ensure all tests pass

## Conclusion

The functional DMA refactor is **architecturally sound** but has:
- 1 architectural issue (timestamp race)
- 1 functional issue (byte duplication)
- 3 unrelated bugs (DMC fetch, corruption)

All issues have been thoroughly analyzed and have clear fix paths. The main blocker is determining the exact hardware behavior for byte duplication, which requires additional research.

**Status:** Ready for user review and research phase.
