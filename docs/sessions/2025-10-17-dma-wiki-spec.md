# DMC DMA during OAM DMA - Complete Wiki Specification

**Source:** https://www.nesdev.org/wiki/DMA#DMC_DMA_during_OAM_DMA

## Core Principles

1. **Independent DMA units** - DMC and OAM have separate controllers
2. **Collision handling** - When both try to access memory the same cycle:
   - DMC DMA is allowed to run (higher priority)
   - OAM DMA is paused, tries again next cycle
3. **Alignment requirement** - OAM DMA may need additional alignment cycle after DMC completes
4. **No-op overlap** - No-operation cycles can overlap, saving cycles

## Timing Overhead

**Common case:** 2 cycles total
- 1 cycle for DMC DMA get
- 1 cycle for OAM DMA to realign back to a get

**Edge cases at end of OAM:**
- DMC on second-to-last put: 1 cycle total
- DMC on last put: 3 cycles total

## Cycle-by-Cycle Examples

### Example 1: DMC DMA at start of OAM DMA (write on get)

```
         (get) CPU writes to $4014
(halted) (put) CPU reads from address A      <- DMC and OAM DMA halt cycle
(halted) (get) OAM DMA reads from $xx00      <- DMC DMA dummy cycle
(halted) (put) OAM DMA writes to $2004       <- DMC DMA alignment cycle
(halted) (get) DMC DMA reads from address B
(halted) (put) CPU reads from address A      <- OAM DMA alignment cycle
(halted) (get) DMA reads from $xx01
(halted) (put) DMA writes to $2004
             ...
```

**Taking 2 cycles overhead**

### Example 2: DMC DMA at start of OAM DMA (write on put)

```
         (put) CPU writes to $4014           <- DMC DMA attempts to halt
(halted) (get) CPU reads from address A      <- DMC and OAM DMA halt cycle
(halted) (put) CPU reads from address A      <- DMC DMA dummy cycle, OAM DMA alignment cycle
(halted) (get) DMC DMA reads from address B
(halted) (put) CPU reads from address A      <- OAM DMA alignment cycle
(halted) (get) OAM DMA reads from $xx00
(halted) (put) OAM DMA writes to $2004
             ...
```

**Taking 2 cycles overhead**

### Example 3: DMC DMA in the middle of OAM DMA

```
             ...
(halted) (get) OAM DMA reads from address C
(halted) (put) OAM DMA writes to $2004         <- DMC DMA halt cycle
(halted) (get) OAM DMA reads from address C+1  <- DMC DMA dummy cycle
(halted) (put) OAM DMA writes to $2004         <- DMC DMA alignment cycle
(halted) (get) DMC DMA reads from address B
(halted) (put) CPU reads from address A        <- OAM DMA alignment cycle
(halted) (get) OAM DMA reads from address C+2
             ...
```

**Taking 2 cycles overhead**

### Example 4: DMC DMA on second-to-last OAM DMA put

```
             ...
(halted) (get) OAM DMA reads from $xxFE
(halted) (put) OAM DMA writes to $2004       <- DMC DMA halt cycle
(halted) (get) OAM DMA reads from $xxFF      <- DMC DMA dummy cycle
(halted) (put) OAM DMA writes to $2004       <- DMC DMA alignment cycle
(halted) (get) DMC DMA reads from address B
         (put) CPU reads from address A      <- CPU resumes execution
```

**Taking 1 cycle overhead** (DMC get happens after OAM completes)

### Example 5: DMC DMA on last OAM DMA put

```
             ...
(halted) (get) OAM DMA reads from $xxFF
(halted) (put) OAM DMA writes to $2004       <- DMC DMA halt cycle
(halted) (get) CPU reads from address A      <- DMC DMA dummy cycle
(halted) (put) CPU reads from address A      <- DMC DMA alignment cycle
(halted) (get) DMC DMA reads from address B
         (put) CPU reads from address A      <- CPU resumes execution
```

**Taking 3 cycles overhead** (OAM already done, just DMC overhead remains)

## Key Observations

### Get/Put Cycle Pattern

Every CPU cycle is labeled as either "(get)" or "(put)":
- **Get cycles:** Read from memory (fetch data)
- **Put cycles:** Write to memory or idle

OAM DMA alternates: get, put, get, put...
- Get: Read from $xxNN
- Put: Write to $2004

DMC DMA sequence when triggered:
1. Halt cycle (aligns to even cycle)
2. Dummy cycle (no-op)
3. Alignment cycle (no-op)
4. Get cycle (actual DMC read)

### Critical Insight: OAM Continues During DMC Dummy/Alignment

Looking at Example 3:

```
(halted) (put) OAM DMA writes to $2004         <- DMC DMA halt cycle
(halted) (get) OAM DMA reads from address C+1  <- DMC DMA dummy cycle
(halted) (put) OAM DMA writes to $2004         <- DMC DMA alignment cycle
(halted) (get) DMC DMA reads from address B    <- OAM MUST WAIT HERE
```

**OAM continues executing during DMC's dummy and alignment cycles!**

This is NOT a complete pause. OAM advances from C to C+1 during DMC preparation.

Only during the actual DMC read (cycle 4) must OAM wait.

### No Byte Duplication

OAM reads sequential addresses: C, C+1, C+2

There is NO byte duplication in hardware.

### Extra Alignment Cycle

After DMC completes its read, there's one extra alignment cycle:

```
(halted) (get) DMC DMA reads from address B
(halted) (put) CPU reads from address A        <- OAM DMA alignment cycle
(halted) (get) OAM DMA reads from address C+2  <- OAM resumes
```

This alignment cycle is required before OAM can resume normal get/put alternation.

## Implementation Requirements

### 1. Get/Put Cycle Tracking

OAM DMA needs to track whether current cycle is get or put:
- Even cycles (0, 2, 4...): get (read)
- Odd cycles (1, 3, 5...): put (write)

### 2. DMC Cycle Phase Tracking

DMC has 4 cycle phases:
- Cycle 4 (stall_cycles_remaining=4): Halt/align
- Cycle 3 (stall_cycles_remaining=3): Dummy
- Cycle 2 (stall_cycles_remaining=2): Alignment
- Cycle 1 (stall_cycles_remaining=1): Actual read

**OAM should only pause during cycle 1 (the actual DMC read)**

### 3. Post-DMC Alignment

After DMC completes (stall_cycles_remaining becomes 0), OAM needs:
1. One alignment cycle to get back to proper get/put rhythm
2. Then resume normal operation

### 4. Sequential Addressing

OAM must read sequential addresses:
- No capturing/duplicating bytes
- No skipping bytes
- Just continue from where it was

## Current Implementation Issues

**File:** `src/emulation/dma/logic.zig`

### Issue 1: Complete Pause (WRONG)

```zig
const dmc_is_active = ledger.last_dmc_active_cycle > ledger.last_dmc_inactive_cycle;
const was_paused = ledger.oam_pause_cycle > ledger.oam_resume_cycle;

if (dmc_is_active and was_paused) {
    return; // OAM stops completely
}
```

**Problem:** OAM stops for ALL 4 cycles of DMC, not just the read cycle.

**Should be:** OAM only pauses when `state.dmc_dma.stall_cycles_remaining == 1`

### Issue 2: No Alignment Cycle (MISSING)

After DMC completes, there's no extra alignment cycle for OAM.

**Should be:** Add one extra cycle after DMC completes before OAM resumes normal get/put.

### Issue 3: Duplication Logic (WRONG)

Code tries to handle byte duplication that doesn't exist in hardware.

**Should be:** Remove all duplication tracking and logic.

## Correct Implementation Strategy

### Phase 1: Identify DMC Read Cycle

```zig
pub fn tickOamDma(state: anytype) void {
    // Check if DMC is doing its actual read (cycle 1 only)
    const dmc_is_reading = state.dmc_dma.rdy_low and
                          state.dmc_dma.stall_cycles_remaining == 1;

    if (dmc_is_reading) {
        // OAM must wait this ONE cycle for DMC read
        return;
    }

    // Otherwise OAM continues (even if DMC is in dummy/alignment)
    // ... normal OAM logic ...
}
```

### Phase 2: Add Post-DMC Alignment

```zig
pub fn tickOamDma(state: anytype) void {
    const ledger = &state.dma_interaction_ledger;

    // Check if DMC just completed
    const dmc_just_completed = !state.dmc_dma.rdy_low and
                               ledger.needs_alignment_after_dmc;

    if (dmc_just_completed) {
        // Extra alignment cycle
        dma.current_cycle += 1;
        ledger.needs_alignment_after_dmc = false;
        return;
    }

    // ... rest of logic ...
}
```

### Phase 3: Mark Alignment Need

When DMC starts, mark that OAM will need alignment:

```zig
// In execution.zig when DMC becomes active
if (dmc_is_active and !dmc_was_active) {
    if (state.dma.active) {
        state.dma_interaction_ledger.needs_alignment_after_dmc = true;
    }
}
```

## Success Criteria

Tests should verify:

1. ✅ OAM offset advances during DMC execution (time-sharing)
2. ✅ OAM reads sequential addresses (C, C+1, C+2)
3. ✅ Cycle overhead is ~2 cycles (not ~4+)
4. ✅ No byte duplication occurs
5. ✅ Extra alignment cycle after DMC completes

---

**Status:** Specification documented, ready for implementation
