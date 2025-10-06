# APU Timing Analysis - Edge Cases & Precision

**Date:** 2025-10-06
**Status:** Deep-dive analysis of timing edge cases and potential deviations
**Purpose:** Identify all timing-related issues that could cause AccuracyCoin failures

---

## Executive Summary

This document analyzes potential timing issues in our APU implementation that could cause test failures:
1. **Rising vs Falling Edge:** Which cycle do events actually occur?
2. **Sub-Stepping:** Do we need finer-grained than CPU cycle resolution?
3. **Write Delays:** 3-4 cycle delays when writing to $4017
4. **Clock Phase Alignment:** CPU/APU phase relationship
5. **Cycle Boundary Events:** What happens on the exact cycle boundary?

---

## Problem 1: Rising vs Falling Edge Timing

### The Issue

**Question:** When we say "event occurs at cycle N", does it happen:
- At the START of cycle N (rising edge)?
- At the END of cycle N (falling edge)?
- DURING cycle N (somewhere in the middle)?

### Hardware Behavior (From NESDev Research)

**CPU Read/Write Cycles:**
```
Cycle N:
  φ1 (first half):  Address lines stable, read occurs
  φ2 (second half): Write occurs, data bus updated
```

**APU Clocking:**
```
APU increments on EVEN CPU cycles (0, 2, 4, 6, ...)
APU cycle M corresponds to CPU cycles 2M and 2M+1

Example:
  APU cycle 0 = CPU cycles 0-1
  APU cycle 1 = CPU cycles 2-3
  APU cycle 2 = CPU cycles 4-5
```

### Our Implementation

**Current Behavior:**
```zig
pub fn tickFrameCounter(state: *ApuState) bool {
    state.frame_counter_cycles += 1;  // Increment FIRST
    const cycles = state.frame_counter_cycles;

    if (cycles == FRAME_4STEP_QUARTER1) {
        clockQuarterFrame(state);  // Occurs AFTER increment
    }
    // ...
}
```

**Analysis:**
- We increment counter THEN check for events
- Event occurs at START of cycle N+1, or END of cycle N
- This matches hardware: counter increments, THEN value is checked

**Verdict:** ✅ Correct - events occur after counter increment

---

## Problem 2: Sub-Cycle Timing (The .5 Cycle Issue)

### The Issue

NESDev discussions mention "7457.5 CPU cycles" for quarter-frame timing. Do we need sub-cycle precision?

### Hardware Reality

**From NESDev Wiki:**
```
APU cycles are EXACTLY 2 CPU cycles (no fractional cycles)
The .5 refers to which HALF of the APU cycle the event occurs on

Example:
  3728.5 APU cycles means:
    - APU cycle 3728 completes
    - Event occurs on SECOND half of APU cycle 3728
    - This is CPU cycle 7457 (second half of APU cycle = odd CPU cycle)
```

**Truth Table:**
```
APU Cycle  | CPU Cycle Range | Event at ".5"
-----------|-----------------|---------------
0          | 0-1             | CPU cycle 1
1          | 2-3             | CPU cycle 3
3728       | 7456-7457       | CPU cycle 7457
7456       | 14912-14913     | CPU cycle 14913
```

### Our Implementation

**Current Constants:**
```zig
const FRAME_4STEP_QUARTER1: u32 = 7457;   // .5 → odd cycle
const FRAME_4STEP_HALF:     u32 = 14913;  // .5 → odd cycle
const FRAME_4STEP_QUARTER3: u32 = 22371;  // .5 → odd cycle
const FRAME_4STEP_IRQ:      u32 = 29829;  // IRQ set at 29828-29829
```

**Analysis:**
- We use ODD CPU cycles (7457, 14913, 22371)
- This matches ".5 APU cycle" interpretation
- No sub-cycle tracking needed

**Verdict:** ✅ Correct - ".5" means odd CPU cycle, not fractional cycle

---

## Problem 3: $4017 Write Delay (3-4 Cycle Latency)

### The Issue

**From NESDev:** Writing to $4017 doesn't take effect immediately - there's a 3-4 cycle delay.

**AccuracyCoin Tests (Frame Counter IRQ, error codes A-D):**
- Error code A: "IRQ enabled too early (odd CPU cycle write)"
- Error code B: "IRQ enabled too late (odd CPU cycle write)"
- Error code C: "IRQ enabled too early (even CPU cycle write)"
- Error code D: "IRQ enabled too late (even CPU cycle write)"

### Hardware Behavior

**Write Cycle Breakdown:**
```
Cycle 0: CPU writes to $4017 (value on bus)
Cycle 1: APU latches value (internal delay)
Cycle 2: APU processes command (internal delay)
Cycle 3: New mode active, counter reset (odd write)
Cycle 4: New mode active, counter reset (even write)
```

**Odd vs Even Write:**
- Odd CPU cycle write: 3 cycle delay
- Even CPU cycle write: 4 cycle delay
- Reason: APU only updates on even cycles

### Our Implementation

**Current Behavior:**
```zig
pub fn writeFrameCounter(state: *ApuState, value: u8) void {
    const new_mode = (value & 0x80) != 0;
    state.frame_counter_mode = new_mode;

    // IMMEDIATE effect (no delay)
    if (new_mode) {
        clockQuarterFrame(state);
        clockHalfFrame(state);
    }

    // IMMEDIATE counter reset
    state.frame_counter_cycles = 0;

    // IMMEDIATE IRQ inhibit
    const irq_inhibit = (value & 0x40) != 0;
    state.irq_inhibit = irq_inhibit;
    if (irq_inhibit) {
        state.frame_irq_flag = false;
    }
}
```

**Problem:** ❌ No delay - effects happen immediately

### Required Fix

**Add pending write state:**
```zig
pub const ApuState = struct {
    // NEW: Pending $4017 write
    frame_counter_write_pending: bool = false,
    frame_counter_write_value: u8 = 0,
    frame_counter_write_delay: u8 = 0,  // Cycles until effect
};
```

**Updated write handler:**
```zig
pub fn writeFrameCounter(state: *ApuState, value: u8, cpu_cycle_odd: bool) void {
    state.frame_counter_write_pending = true;
    state.frame_counter_write_value = value;

    // Delay: 3 cycles if odd write, 4 if even
    state.frame_counter_write_delay = if (cpu_cycle_odd) 3 else 4;
}
```

**Updated tick function:**
```zig
pub fn tickFrameCounter(state: *ApuState) bool {
    // Process pending $4017 write
    if (state.frame_counter_write_pending) {
        if (state.frame_counter_write_delay > 0) {
            state.frame_counter_write_delay -= 1;
        } else {
            // Apply write NOW
            applyFrameCounterWrite(state);
            state.frame_counter_write_pending = false;
        }
    }

    // Normal counter increment
    state.frame_counter_cycles += 1;
    // ... rest of logic
}
```

**Priority:** ⚠️ MEDIUM - Required for Frame Counter IRQ tests A-D (4 tests)

---

## Problem 4: Clock Phase Alignment (Random Startup)

### The Issue

**From Web Research:**
> "CPU/APU alignment at startup is effectively random - the CPU can begin on either half of an APU cycle."

**Implication:**
- Frame counter timing can vary ±1 cycle across resets
- Tests may expect specific alignment
- Our constants may need adjustment based on which alignment tests assume

### Hardware Behavior

**Two Possible Alignments:**
```
Alignment A (CPU starts on even cycle):
  Quarter 1 at: 7456
  Half 1 at:    14912
  Quarter 3 at: 22370
  IRQ at:       29828

Alignment B (CPU starts on odd cycle):
  Quarter 1 at: 7457
  Half 1 at:    14913
  Quarter 3 at: 22371
  IRQ at:       29829
```

### Our Implementation

**Current Constants:** Uses Alignment B (odd values)

**Analysis:**
- AccuracyCoin likely tests specific alignment
- We won't know which until we run the tests
- If tests fail by ±1 cycle, this is the culprit

**Action Plan:**
1. Run AccuracyCoin Frame Counter 4-step test
2. If fails with "IRQ early/late by 1 cycle", try other alignment
3. Document which alignment AccuracyCoin expects

**Priority:** 🔍 DIAGNOSTIC - Will know from test failures

---

## Problem 5: IRQ Flag Multi-Cycle Behavior

### The Issue

**From AccuracyCoin (Frame Counter IRQ, error codes E-H):**
```
Error E: Reading $4015 at cycle 29829 should NOT clear IRQ
         (flag gets set again immediately)
Error F: Reading $4015 at cycle 29830 should NOT clear IRQ
         (flag gets set again on this cycle)
Error G: Reading $4015 at cycle 29831 should NOT clear IRQ
         (flag gets set again on this cycle)
Error H: Reading $4015 at cycle 29832 should clear IRQ
         (flag no longer being set)
```

**Insight:** IRQ flag is SET for multiple cycles (29829-29831)

### Hardware Behavior

**IRQ Flag Timeline:**
```
Cycle 29828: Frame counter = 29828, IRQ flag SET (first time)
Cycle 29829: Frame counter = 29829, IRQ flag SET (second time)
Cycle 29830: Frame counter resets to 0, IRQ flag cleared

BUT: If you READ $4015 at 29828/29829, it clears the flag,
     then the SAME CYCLE sets it again!
```

**Why:** IRQ flag is set by combinational logic, not edge-triggered
- Every cycle, hardware checks: `if (counter == 29828 || counter == 29829) set_flag()`
- Reading $4015 clears flag
- Hardware immediately re-evaluates and sets it again

### Our Implementation

**Current Behavior:**
```zig
if (cycles == FRAME_4STEP_IRQ or cycles == FRAME_4STEP_IRQ + 1) {
    if (!state.irq_inhibit) {
        state.frame_irq_flag = true;  // Set flag
        should_irq = true;
    }
}
```

**Problem:** ❌ Only sets flag once per tick, doesn't handle re-set after $4015 read

### Required Fix

**IRQ flag must be RE-SET every cycle it's active:**

```zig
// In readStatus():
pub fn readStatus(state: *ApuState) u8 {
    var result: u8 = 0;

    // ... other bits

    if (state.frame_irq_flag) result |= 0x40;

    // Clear frame IRQ flag when read
    state.frame_irq_flag = false;

    return result;
}

// In tickFrameCounter():
pub fn tickFrameCounter(state: *ApuState) bool {
    state.frame_counter_cycles += 1;
    const cycles = state.frame_counter_cycles;

    // ... quarter/half frame clocking

    if (!is_5_step) {
        // Check IRQ flag condition EVERY cycle
        if ((cycles == FRAME_4STEP_IRQ or cycles == FRAME_4STEP_IRQ + 1)
            and !state.irq_inhibit) {
            state.frame_irq_flag = true;  // Re-set even if just cleared
            should_irq = true;
        }
    }

    // ... counter reset
}
```

**Key Change:** IRQ flag is SET every tick when condition is true, not just once

**Priority:** ⚠️ HIGH - Required for Frame Counter IRQ tests E-H (4 tests)

---

## Problem 6: Event Ordering Within a Cycle

### The Issue

**Question:** When multiple things happen in one cycle, what order do they occur?

**Example:** Cycle 14913 in 4-step mode
1. Quarter frame clock
2. Half frame clock
3. Counter increment
4. IRQ check

**Which order?**

### Hardware Behavior

**From NESDev Cycle-by-Cycle Breakdown:**
```
Each CPU cycle (in frame counter context):
  1. Counter increments
  2. Counter value compared to thresholds
  3. Events triggered based on comparison
  4. IRQ line updated
```

### Our Implementation

**Current Order:**
```zig
pub fn tickFrameCounter(state: *ApuState) bool {
    state.frame_counter_cycles += 1;  // 1. Increment
    const cycles = state.frame_counter_cycles;

    if (cycles == FRAME_4STEP_HALF) {
        clockQuarterFrame(state);      // 2. Quarter event
        clockHalfFrame(state);         // 3. Half event
    }

    if (cycles == FRAME_4STEP_IRQ) {
        // 4. IRQ flag set
        state.frame_irq_flag = true;
    }

    // 5. Counter reset check
}
```

**Verdict:** ✅ Correct - increment, compare, trigger events, update IRQ

---

## Problem 7: Length Counter Immediate Effects

### The Issue

**From AccuracyCoin (APU Length Counter, error code 5):**
> "Disabling the audio channel should immediately clear the length counter to zero."

**Question:** Does "immediately" mean:
- Same cycle as $4015 write?
- Next cycle after write?
- After write delay?

### Hardware Behavior

**From NESDev:**
```
Writing to $4015:
  Cycle N (write cycle): CPU writes value to $4015
  Cycle N (same cycle):  APU latches value, clears disabled channel length counters
  Cycle N+1:             Length counters = 0, channels silent
```

**Immediate = same cycle as write**

### Our Implementation

**Current Behavior:**
```zig
pub fn writeControl(state: *ApuState, value: u8) void {
    state.pulse1_enabled = (value & 0x01) != 0;

    if (!state.pulse1_enabled) {
        state.pulse1_length = 0;  // Immediate clear
    }
}
```

**Verdict:** ✅ Correct - immediate clear within write handler

---

## Problem 8: APU vs CPU Cycle Tracking

### The Issue

Our frame counter counts CPU cycles, but APU internally uses APU cycles. Could this cause off-by-one errors?

### Analysis

**Our Approach:** Count CPU cycles, use CPU cycle thresholds
```zig
const FRAME_4STEP_QUARTER1: u32 = 7457;  // CPU cycles
```

**Alternative Approach:** Count APU cycles, double for CPU
```zig
const FRAME_4STEP_QUARTER1_APU: u16 = 3728;  // APU cycles
const cpu_cycles = apu_cycles * 2;
```

**Comparison:**
```
Our approach:        frame_counter_cycles = 7457 → trigger
Alternative:         apu_cycles = 3728 → cpu_cycles = 7456 → trigger
Difference:          1 cycle off!
```

### Root Cause

**The ".5" in "3728.5 APU cycles":**
- If we use 3728 APU cycles × 2 = 7456 CPU cycles ❌
- If we use 3728.5 → trigger on ODD cycle = 7457 CPU cycles ✅

**Our implementation uses CPU cycle counts directly, accounting for .5 offset**

**Verdict:** ✅ Correct - we handle ".5" by using odd CPU cycles

---

## Problem 9: State/Logic Separation for Timing

### Design Pattern Adherence

**Our State/Logic Pattern:**
- `ApuState`: Pure data, no hidden state
- `ApuLogic`: Pure functions, deterministic

**Timing State Requirements:**
```zig
pub const ApuState = struct {
    // Counter state (u32, not hidden)
    frame_counter_cycles: u32 = 0,

    // Mode state (bool, not derived)
    frame_counter_mode: bool = false,

    // IRQ state (bool, explicit)
    frame_irq_flag: bool = false,
    irq_inhibit: bool = false,
};
```

**No Hidden State:**
- ✅ All timing state is in `ApuState`
- ✅ No static variables in Logic functions
- ✅ Deterministic - same inputs = same outputs
- ✅ Fully serializable for save states

**Verdict:** ✅ Correct - design pattern followed

---

## Summary of Issues Found

### ❌ Critical Issues (Must Fix for AccuracyCoin)

1. **IRQ Flag Re-Set:** Flag must be set every cycle it's active, not just once
   - **Impact:** Frame Counter IRQ tests E-H (4 tests)
   - **Fix:** Check IRQ condition every tick, set flag even if just cleared

2. **$4017 Write Delay:** No 3-4 cycle delay implemented
   - **Impact:** Frame Counter IRQ tests A-D (4 tests)
   - **Fix:** Add pending write state, apply after delay

### ⚠️ Potential Issues (Diagnostic Needed)

3. **Clock Phase Alignment:** Using odd cycles (7457, 14913, 22371)
   - **Impact:** All frame counter tests (if wrong alignment)
   - **Diagnostic:** Run tests, adjust ±1 if failures

### ✅ Verified Correct

4. **Event Timing:** Increment-then-check order ✅
5. **Sub-Cycle Resolution:** Using odd CPU cycles for ".5" ✅
6. **Immediate Effects:** Length counter clear is immediate ✅
7. **Cycle Counting:** Direct CPU cycles, not APU×2 ✅
8. **Design Pattern:** State/Logic separation maintained ✅

---

## Action Plan

### Phase 1.5.1: Fix Critical Issues (2-3 hours)

1. **Implement IRQ flag re-set behavior**
   - Modify `tickFrameCounter()` to set flag every cycle condition is true
   - Test with manual cycle counting

2. **Implement $4017 write delay**
   - Add pending write state to `ApuState`
   - Track CPU cycle parity (odd/even) in `EmulationState`
   - Apply write after 3-4 cycle delay

3. **Run AccuracyCoin Frame Counter IRQ tests**
   - Validate error codes A-H (8 tests)
   - Confirm all pass

### Phase 1.5.2: Implement Length Counters (3-4 hours)

4. **Add length counter state and logic**
   - Implement as documented in `apu-length-counter.md`
   - Wire up to frame counter half-frame clocks

5. **Run AccuracyCoin APU Length Counter tests**
   - Validate all 8 tests pass
   - Run APU Length Table tests (24 tests)

6. **Run Frame Counter 4-step and 5-step tests**
   - Validate half-frame clock timing (12 tests)
   - Adjust cycle constants ±1 if needed

### Phase 1.5.3: Validation (1-2 hours)

7. **Run full test suite**
   - Ensure no regressions (585/585 tests still passing)
   - Confirm AccuracyCoin APU tests passing

8. **Update documentation**
   - Document final cycle values used
   - Note any AccuracyCoin-specific quirks found

---

## References

- **NESDev Wiki - APU Frame Counter:** https://www.nesdev.org/wiki/APU_Frame_Counter
- **NESDev Forum - APU Timing:** https://forums.nesdev.org/viewtopic.php?t=454
- **AccuracyCoin README:** `/home/colin/Development/RAMBO/AccuracyCoin/README.md`
- **Our Gap Analysis:** `/home/colin/Development/RAMBO/docs/APU-GAP-ANALYSIS-2025-10-06.md`
