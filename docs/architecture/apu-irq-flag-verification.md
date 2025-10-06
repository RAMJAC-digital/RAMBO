# APU Frame Counter IRQ Flag - Behavior Verification

**Date:** 2025-10-06
**Status:** Research and verification document
**Purpose:** Document exact IRQ flag behavior before implementation

---

## Problem Statement

The APU frame counter IRQ flag behavior has complex edge cases when reading $4015 during the cycles where the flag is being set. We need to verify the exact hardware behavior before implementing.

---

## Evidence Collected

### From AccuracyCoin Test Descriptions

**Tests J-L (Flag Setting Timing):**
- **Error J:** "IRQ flag SHOULD be set at cycle 29828, even if suppressing interrupts"
- **Error K:** "IRQ flag SHOULD be set at cycle 29829, even if suppressing interrupts"
- **Error L:** "IRQ flag should NOT be set at cycle 29830 if suppressing interrupts"

**Interpretation:** Flag is actively SET by hardware at cycles 29828-29829.

**Tests E-H (Reading $4015 During Flag Setting):**
- **Error E:** "Reading $4015 at cycle 29829 should NOT clear IRQ (it gets set again on following 2 cycles)"
   - Reading at 29829 → flag re-set at 29830, 29831
- **Error F:** "Reading $4015 1 cycle later should NOT clear IRQ (it gets set again on following 1 cycle)"
   - Reading at 29830 → flag re-set at 29831
- **Error G:** "Reading $4015 1 cycle later should NOT clear IRQ (it gets set again on this cycle)"
   - Reading at 29831 → flag re-set at 29831
- **Error H:** "Reading $4015 1 cycle later SHOULD clear IRQ"
   - Reading at 29832 → flag cleared successfully

**Interpretation:** Flag is actively re-set at cycles 29829-29831 (3 cycles).

### From NESDev Forum Research

**Quote from forum:**
> "The frame interrupt flag is set three times in a row 29831 clocks after writing $4017 with $00"

**Quote about timing:**
> "The frame IRQ should take effect at 29829... The IRQ handler is invoked at minimum 29833 clocks after writing $00 to $4017"

**Interpretation:** There's a discrepancy between when flag is set (29829) and when IRQ handler runs (29833).

---

## Current Understanding (Best Interpretation)

### Hypothesis: Two-Stage Flag Behavior

**Stage 1: Active Setting (Cycles 29828-29829)**
- Frame counter hardware actively SETS flag when `counter == 29828 || counter == 29829`
- This is combinational logic - flag is driven high by hardware

**Stage 2: Latched (Cycles 29830-29831)**
- Counter resets at 29830, but flag remains LATCHED (stays high)
- Flag is no longer being actively set, but previous state persists
- Some additional cycle(s) where flag stays latched

**Stage 3: Clearable (Cycle 29832+)**
- Flag can be cleared by reading $4015
- No active setting or latching

### Behavior When Reading $4015

**At Cycles 29828-29829 (Active Setting):**
```
CPU reads $4015 → Clears flag latch
Frame counter checks condition → Sees counter == 29828/29829 → Sets flag again
Result: Flag remains set
```

**At Cycles 29830-29831 (Latched):**
```
CPU reads $4015 → Clears flag latch
But... why doesn't it stay cleared?
```

**Problem:** If flag is just latched (not actively set) at 29830-29831, why does reading not clear it?

---

## Alternative Hypothesis: Extended Active Window

Maybe the flag is actively SET for more cycles than we think:

**Hypothesis 2: Flag actively set at cycles 29829, 29830, 29831**
- Counter reaches 29829 → Flag SET
- Counter resets to 0 at 29830, but IRQ flag logic has 2-cycle delay
- Flag continues to be SET at 29830, 29831 due to delay

This would explain why reading at 29829-29831 doesn't clear it - hardware keeps re-setting it.

---

## Contradictions to Resolve

### Contradiction 1: Counter Reset Timing

**From our constants:**
```zig
const FRAME_4STEP_IRQ: u32 = 29829;      // IRQ flag set
const FRAME_4STEP_TOTAL: u32 = 29830;    // Reset counter to 0
```

**If counter resets at 29830:**
- How can flag still be actively set at 29830-29831?
- Counter would be 0 or 1, not 29830/29831

**Possible Resolution:**
- IRQ flag logic uses delayed/pipelined counter value
- Flag check happens before counter increment
- Counter reset has 1-2 cycle delay

### Contradiction 2: 3 Cycles vs 2 Cycles

**Tests J-K:** Flag set at cycles 29828-29829 (2 cycles)
**Tests E-G:** Flag re-set at cycles 29829-29831 when read (3 cycles)

**Possible Resolution:**
- Base behavior: Set at 29828-29829
- Extended behavior when read: Stays set through 29831
- OR: Always set at 29829-29831, tests J-K checking different thing

---

## Proposed Test-Driven Approach

Since we cannot definitively determine behavior from documentation alone, I propose:

### Step 1: Implement Simplest Interpretation

```zig
pub fn tickFrameCounter(state: *ApuState) bool {
    state.frame_counter_cycles += 1;
    const cycles = state.frame_counter_cycles;

    // Set flag at 29828-29829 (confirmed by tests J-K)
    if ((cycles == 29828 || cycles == 29829) && !state.irq_inhibit) {
        state.frame_irq_flag = true;
    }

    // Counter reset
    if (cycles >= 29830) {
        state.frame_counter_cycles = 0;
    }

    return state.frame_irq_flag && !state.irq_inhibit;
}

pub fn readStatus(state: *ApuState) u8 {
    var result: u8 = 0;

    // Read current flag state
    if (state.frame_irq_flag) result |= 0x40;

    // Clear flag
    state.frame_irq_flag = false;

    return result;
}
```

### Step 2: Run AccuracyCoin Tests E-H

- Test will likely FAIL with this implementation
- Error messages will tell us exact behavior expected

### Step 3: Adjust Based on Failures

**If test E fails (reading at 29829):**
- Add logic to re-set flag if `cycles == 29829 || cycles == 29830 || cycles == 29831`

**If test timing is off:**
- Adjust cycle constants (maybe 29829-29831 instead of 29828-29829)

### Step 4: Iterate Until Tests Pass

This empirical approach will reveal exact hardware behavior through test failures.

---

## Proposed Implementation (V1)

Based on best current understanding:

```zig
pub fn tickFrameCounter(state: *ApuState) bool {
    state.frame_counter_cycles += 1;
    const cycles = state.frame_counter_cycles;
    const is_5_step = state.frame_counter_mode;
    var should_irq = false;

    if (!is_5_step) {
        // 4-step mode
        if (cycles == FRAME_4STEP_QUARTER1) {
            clockQuarterFrame(state);
        } else if (cycles == FRAME_4STEP_HALF) {
            clockQuarterFrame(state);
            clockHalfFrame(state);
        } else if (cycles == FRAME_4STEP_QUARTER3) {
            clockQuarterFrame(state);
        } else if (cycles == FRAME_4STEP_IRQ) {
            clockHalfFrame(state);

            // Set IRQ flag (if not inhibited)
            if (!state.irq_inhibit) {
                state.frame_irq_flag = true;
                should_irq = true;
            }
        }

        // ALSO set flag at cycle 29828 (based on test J)
        if (cycles == 29828 && !state.irq_inhibit) {
            state.frame_irq_flag = true;
            should_irq = true;
        }

        // Counter reset
        if (cycles >= FRAME_4STEP_TOTAL) {
            state.frame_counter_cycles = 0;
        }
    }

    return should_irq;
}

pub fn readStatus(state: *ApuState) u8 {
    var result: u8 = 0;

    // Length counter status (bits 0-3)
    if (state.pulse1_length > 0) result |= 0x01;
    if (state.pulse2_length > 0) result |= 0x02;
    if (state.triangle_length > 0) result |= 0x04;
    if (state.noise_length > 0) result |= 0x08;

    // DMC status (bit 4)
    if (state.dmc_bytes_remaining > 0) result |= 0x10;

    // IRQ flags (bits 6-7)
    if (state.frame_irq_flag) result |= 0x40;
    if (state.dmc_irq_flag) result |= 0x80;

    // Clear frame IRQ flag
    state.frame_irq_flag = false;

    return result;
}
```

**Note:** This is Version 1 - simple implementation. Will be adjusted based on test results.

---

## Open Questions

1. **Exact cycles where flag is actively set:** 29828-29829? Or 29829-29831?
2. **Re-set mechanism:** Is it automatic re-set, or latching, or delayed counter?
3. **Counter reset timing:** Does reset happen immediately at 29830, or delayed?
4. **$4017 write delay interaction:** Does the 3-4 cycle delay affect IRQ flag behavior?

---

## Decision: Test-Driven Implementation

**Conclusion:** We cannot determine exact behavior from documentation alone.

**Recommended Approach:**
1. Implement simplest reasonable interpretation (V1 above)
2. Run AccuracyCoin Frame Counter IRQ tests
3. Use test failures to guide corrections
4. Document final working behavior
5. Update architecture docs with verified implementation

**Rationale:**
- Hardware behavior is complex with multiple edge cases
- Test ROMs are the ground truth
- Iterative refinement is faster than perfect upfront analysis
- We can document verified behavior after tests pass

---

## Next Actions

1. ⬜ Implement V1 (simplest interpretation)
2. ⬜ Create unit test for basic IRQ flag behavior
3. ⬜ Run AccuracyCoin Frame Counter IRQ test
4. ⬜ Analyze failures (error codes E-H specifically)
5. ⬜ Implement V2 based on failure analysis
6. ⬜ Iterate until all tests pass
7. ⬜ Document final verified behavior
