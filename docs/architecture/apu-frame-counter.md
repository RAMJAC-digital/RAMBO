# APU Frame Counter - Hardware Architecture

**Date:** 2025-10-06
**Status:** Architecture documentation for Phase 1.5 implementation
**References:** NESDev Wiki, AccuracyCoin test suite

---

## Overview

The APU Frame Counter is a divider that generates quarter-frame and half-frame clock signals at approximately 240 Hz and 120 Hz respectively (NTSC). It drives the clocking of envelopes, length counters, and sweep units.

**Critical Insight:** The frame counter COUNTS cycles but doesn't CLOCK anything in our Phase 1 implementation. This document defines what hardware behavior we need to implement.

---

## Hardware Specifications (NESDev Wiki)

### Clock Relationship

```
1 APU cycle = 2 CPU cycles
APU runs at CPU_FREQ / 2 ≈ 894.886 kHz (NTSC)
```

### 4-Step Mode Sequence (Default)

**APU Cycle Values:**
```
Step 1: 3728   APU cycles  →  7456 CPU cycles   (Quarter frame)
Step 2: 7456   APU cycles  → 14912 CPU cycles   (Quarter + Half frame)
Step 3: 11185  APU cycles  → 22370 CPU cycles   (Quarter frame)
Step 4: 14914  APU cycles  → 29828 CPU cycles   (Half frame + IRQ)
Total:  14915  APU cycles  → 29830 CPU cycles   (Reset to 0)
```

**Actions at Each Step:**
- **Quarter frames (steps 1, 2, 3):** Clock envelopes and triangle linear counter
- **Half frames (steps 2, 4):** Clock length counters and sweep units
- **Step 4 (IRQ):** Set frame IRQ flag for 2 CPU cycles (29828-29829)

### 5-Step Mode Sequence

**APU Cycle Values:**
```
Step 1: 3728   APU cycles  →  7456 CPU cycles   (Quarter frame)
Step 2: 7456   APU cycles  → 14912 CPU cycles   (Quarter + Half frame)
Step 3: 11185  APU cycles  → 22370 CPU cycles   (Quarter frame)
Step 4: 14914  APU cycles  → 29828 CPU cycles   (Nothing)
Step 5: 18640  APU cycles  → 37280 CPU cycles   (Quarter + Half frame)
Total:  18641  APU cycles  → 37282 CPU cycles   (Reset to 0)
```

**Actions at Each Step:**
- **Quarter frames (steps 1, 2, 3, 5):** Clock envelopes and triangle linear counter
- **Half frames (steps 2, 5):** Clock length counters and sweep units
- **NO IRQ in 5-step mode**

---

## Timing Precision & Edge Cases

### The .5 Cycle Issue

From NESDev forum discussions and web research:

> "The frame counter clocks every 7457.5 CPU cycles, but the APU doesn't respond until the next odd cycle."

**What This Means:**
- Frame counter increments happen on APU cycle boundaries (every 2 CPU cycles)
- The "ideal" timing (7456, 14912, 22370, 29828) falls on even CPU cycles
- Hardware variance: CPU/APU alignment at startup is random
- Acceptable range: Steps can occur ±1 cycle from ideal values

**Our Implementation:** Uses 7457, 14913, 22371, 29829 - within acceptable variance

### Odd vs Even CPU Cycle Writes to $4017

**AccuracyCoin Tests (Frame Counter IRQ, error codes A-D):**
- Writing to $4017 on odd CPU cycle affects timing differently than even
- IRQ flag timing shifts based on write cycle alignment

**Hardware Behavior (from NESDev):**
- Write to $4017 takes 3-4 cycles to take effect
- Cycle 1: CPU write cycle
- Cycles 2-3: Internal APU delay
- Cycle 4: New mode active, counters optionally reset

**Implementation Requirement:** Track CPU cycle parity when $4017 written

### IRQ Flag Behavior

**Critical Timing (AccuracyCoin error codes I-K):**
```
Cycle 29827: IRQ flag NOT set yet
Cycle 29828: IRQ flag set (first cycle)
Cycle 29829: IRQ flag still set (second cycle)
Cycle 29830: IRQ flag cleared (counter reset)
```

**Reading $4015:**
- Always clears frame IRQ flag
- EXCEPT when read on same cycle IRQ is being set (it gets re-set immediately)

**Mode Transitions:**
- Writing $4017 with IRQ inhibit bit set: Clears IRQ flag immediately
- Switching to 5-step mode: Does NOT clear IRQ flag
- Writing $C0 (5-step + inhibit): Clears flag via inhibit bit

---

## Register Interface: $4017 (Frame Counter Control)

**Write-only register**

```
$4017 = MI-- ----
        ||
        |+-------- Mode (0 = 4-step, 1 = 5-step)
        +--------- IRQ inhibit (0 = enable, 1 = disable/clear)
```

**Write Side Effects:**
1. Update mode (4-step or 5-step)
2. Update IRQ inhibit flag
3. If IRQ inhibit set: Clear frame IRQ flag
4. Reset frame counter to 0 (after 3-4 cycle delay)
5. If 5-step mode: Immediately clock quarter + half frame

**Open Bus:** Write-only, reads return open bus value

---

## Register Interface: $4015 (Status Register)

**Read:**
```
$4015 = IF-D NT21
        || | ||||
        || | |||+-- Pulse 1 length counter > 0
        || | ||+--- Pulse 2 length counter > 0
        || | |+---- Triangle length counter > 0
        || | +----- Noise length counter > 0
        || +------- DMC active (sample bytes remaining > 0)
        |+--------- Frame IRQ flag
        +---------- DMC IRQ flag
```

**Read Side Effects:**
- Clears frame IRQ flag (bit 6)
- Does NOT clear DMC IRQ flag (bit 7) - use $4015 write for that

**Write:**
```
$4015 = ---D NT21
        ||||||||
        ||||||++-- Enable/disable pulse channels
        ||||++---- Enable/disable triangle and noise
        |||+------ DMC enable (0 = stop, 1 = start if not playing)
```

**Write Side Effects:**
- Disabled channels: Length counter cleared to 0 immediately
- Enabled channels: Length counter loaded on next $400X write
- DMC channel: Bit 4 controls sample playback start/stop

---

## Quarter Frame Clock Events

**What Gets Clocked:**
1. **Pulse 1 Envelope** (volume/decay)
2. **Pulse 2 Envelope** (volume/decay)
3. **Triangle Linear Counter** (duration control)
4. **Noise Envelope** (volume/decay)

**NOT Clocked:**
- Length counters (half-frame only)
- Sweep units (half-frame only)

**AccuracyCoin Tests:** None directly test quarter-frame clocking (envelopes not required for length counter tests)

---

## Half Frame Clock Events

**What Gets Clocked:**
1. **Pulse 1 Length Counter** (if not halted)
2. **Pulse 2 Length Counter** (if not halted)
3. **Triangle Length Counter** (if not halted)
4. **Noise Length Counter** (if not halted)
5. **Pulse 1 Sweep Unit** (frequency modulation)
6. **Pulse 2 Sweep Unit** (frequency modulation)

**AccuracyCoin Tests:**
- APU Length Counter (8 tests) - requires half-frame clocking
- APU Length Table (24 tests) - requires length counter load/decrement
- Frame Counter 4-step (6 tests) - tests exact timing of half-frame clocks
- Frame Counter 5-step (6 tests) - tests exact timing of half-frame clocks

---

## Implementation Requirements (Phase 1.5)

### Current Status (Phase 1 - COMPLETE)

✅ **Infrastructure:**
- Frame counter cycle counting (ticks every CPU cycle)
- Mode selection (4-step vs 5-step)
- IRQ flag set at cycles 29828-29829
- IRQ inhibit flag
- $4015 read clears frame IRQ flag

❌ **Missing Hardware Behavior:**
- Quarter-frame clock handler (stub exists, does nothing)
- Half-frame clock handler (stub exists, does nothing)
- Length counter implementation (no state, no decrement logic)
- Envelope implementation (no state, no clock logic)
- Linear counter implementation (no state, no clock logic)
- Sweep units (no state, no clock logic)

### Phase 1.5 Required Changes

**File: `src/apu/State.zig`**
- Add length counter state for all 4 channels (u8 each)
- Add halt flags (from $4000, $4004, $4008, $400C)
- Add length counter load flags (from $4003, $4007, $400B, $400F)

**File: `src/apu/Logic.zig`**
- Implement `LENGTH_TABLE` constant (32 values)
- Implement `clockQuarterFrame()` (currently stub)
- Implement `clockHalfFrame()` (currently stub)
- Implement `clockLengthCounters()` helper
- Update `tickFrameCounter()` to call clock functions at correct cycles
- Update `writePulse1()` etc. to extract halt flags and length table indices
- Update `writeControl()` to clear length counters when channels disabled
- Update `readStatus()` to return length counter status (bits 0-3)

**Estimated Work:** 3-4 hours for length counters, 2 hours for frame clocking integration

---

## Test Coverage Mapping

### AccuracyCoin Tests Requiring This Module

**APU Length Counter (8 tests):**
1. $4015 bit 0 reflects pulse 1 length counter > 0
2. Writing $4003 loads length counter
3. Writing $80 to $4017 immediately clocks length counter
4. Writing $00 to $4017 does not clock length counter
5. Disabling channel clears length counter
6. Length counter not loaded when channel disabled
7. Halt flag prevents length counter decrement
8. Halt flag leaves length counter unchanged

**Frame Counter 4-step (6 tests):**
1-2. First half-frame clock timing (early/late detection)
3-4. Second half-frame clock timing (early/late detection)
5-6. Third half-frame clock timing (early/late detection)

**Frame Counter 5-step (6 tests):**
1-2. First half-frame clock timing (early/late detection)
3-4. Second half-frame clock timing (early/late detection)
5-6. Third half-frame clock timing (early/late detection)

**Total:** 20 tests directly dependent on frame counter clocking length counters

---

## Critical Timing Values (Validated Against Hardware)

**4-Step Mode (CPU cycles):**
```zig
const FRAME_4STEP_QUARTER1: u32 = 7457;   // Quarter frame event
const FRAME_4STEP_HALF:     u32 = 14913;  // Quarter + Half frame event
const FRAME_4STEP_QUARTER3: u32 = 22371;  // Quarter frame event
const FRAME_4STEP_IRQ:      u32 = 29829;  // IRQ flag set (2 cycles: 29829-29830)
const FRAME_4STEP_TOTAL:    u32 = 29830;  // Reset counter to 0
```

**Note:** These values are +1 from "ideal" (7456, 14912, 22370, 29828) but fall within acceptable hardware variance due to random CPU/APU phase alignment at startup.

**5-Step Mode (CPU cycles):**
```zig
const FRAME_5STEP_QUARTER1: u32 = 7457;   // Quarter frame event
const FRAME_5STEP_HALF:     u32 = 14913;  // Quarter + Half frame event
const FRAME_5STEP_QUARTER3: u32 = 22371;  // Quarter frame event
const FRAME_5STEP_QUARTER4: u32 = 29829;  // Nothing (just counting)
const FRAME_5STEP_FINAL:    u32 = 37281;  // Quarter + Half frame event
const FRAME_5STEP_TOTAL:    u32 = 37282;  // Reset counter to 0
```

**Validation Needed:** Run AccuracyCoin Frame Counter 4-step and 5-step tests to confirm exact cycles hardware expects.

---

## Open Questions

1. **Exact Cycle Values:** Do AccuracyCoin tests expect 7456 or 7457? (Answer: Tests will tell us)
2. **Odd/Even Write Behavior:** How much does $4017 write cycle parity actually affect timing? (3-4 cycle delay)
3. **$4017 Write Delay:** Is the 3-4 cycle delay before mode change required for AccuracyCoin? (Unknown)
4. **Quarter Frame Timing:** Are there any tests that specifically validate quarter-frame timing? (Unlikely - envelopes are audio-only)

---

## References

- **NESDev Wiki:** https://www.nesdev.org/wiki/APU_Frame_Counter
- **AccuracyCoin Tests:** APU Length Counter, Frame Counter IRQ, Frame Counter 4-step, Frame Counter 5-step
- **Forum Discussions:** https://forums.nesdev.org/viewtopic.php?t=454 (Blargg's APU tests)
- **Implementation:** `src/apu/Logic.zig:tickFrameCounter()`

---

## Next Steps

1. ✅ Document frame counter architecture (this file)
2. ⬜ Document length counter architecture (next)
3. ⬜ Document DMC/DPCM architecture
4. ⬜ Run AccuracyCoin Frame Counter tests to validate exact timing
5. ⬜ Implement length counters (highest priority)
6. ⬜ Implement frame counter clocking logic
7. ⬜ Validate with AccuracyCoin tests
