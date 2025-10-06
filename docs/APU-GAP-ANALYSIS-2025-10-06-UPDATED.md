# APU Implementation Gap Analysis (Updated)
**Date:** 2025-10-06 (Post-Phase 1.5)
**Status:** Length Counters COMPLETE, Major Gaps Remain
**Purpose:** Comprehensive audit of APU implementation vs AccuracyCoin requirements

---

## Executive Summary

**Current Status:**
- ✅ **Phase 1.5 COMPLETE:** Length counters fully implemented and tested (32/95 APU tests expected to pass)
- ⚠️ **Frame Counter:** Basic timing working, IRQ edge cases untested
- ⚠️ **DMC:** DMA stall mechanics complete, playback/timer NOT implemented
- ❌ **Envelopes:** NOT implemented (needed for volume)
- ❌ **Linear Counter:** NOT implemented (triangle channel timing)
- ❌ **Sweep Units:** NOT implemented (pitch bending)

**Estimated Tests Passing:** 32/95 (34%) → **Target: 80+/95 (84%)**

---

## What We Have (Phase 1.5 Complete)

### ✅ Fully Implemented

**1. Frame Counter State Machine**
```zig
// State
frame_counter_mode: bool = false,      // 4-step vs 5-step
frame_counter_cycles: u32 = 0,         // Current cycle in sequence
irq_inhibit: bool = false,             // IRQ enable/disable
frame_irq_flag: bool = false,          // IRQ flag (readable $4015 bit 6)

// Logic
tickFrameCounter() - Increments cycle counter
- 4-step mode: Calls quarter/half frame at 7457, 14913, 22371, 29829
- 5-step mode: Calls quarter/half frame at 7457, 14913, 22371, 37281
- IRQ flag set at 29829 in 4-step mode (if not inhibited)
- Resets counter at 29830 (4-step) or 37281 (5-step)
```

**2. Length Counters (All 4 Channels)**
```zig
// State
pulse1_length: u8 = 0,
pulse2_length: u8 = 0,
triangle_length: u8 = 0,
noise_length: u8 = 0,

pulse1_halt: bool = false,
pulse2_halt: bool = false,
triangle_halt: bool = false,
noise_halt: bool = false,

// Logic
const LENGTH_TABLE: [32]u8 = { ... };  // All 32 values correct
clockLengthCounters() - Decrements all 4 counters
- Respects halt flags
- Guards against underflow
- Called on half-frame events

writePulse1/2/Triangle/Noise() - Extract halt flag, load from table
writeControl() - Clear counters when channel disabled
readStatus() - Return counter > 0 status (bits 0-3)
writeFrameCounter() - Immediate clock in 5-step mode
```

**3. DMC DMA Mechanics**
```zig
// Implemented in emulation/Dma.zig
- 4-cycle stall (1 get + 3 idle, or 2 get + 2 idle)
- Bus priority (DMC > OAM > CPU)
- Address tracking and sample fetch triggering
- Variant-aware NTSC corruption

// State tracking
dmc_sample_address: u8 = 0,
dmc_sample_length: u8 = 0,
dmc_bytes_remaining: u16 = 0,
dmc_current_address: u16 = 0,
dmc_sample_buffer: u8 = 0,
```

**4. Register Routing**
```zig
// All $4000-$4017 registers routed
// Write values stored in pulse1_regs, pulse2_regs, etc.
// $4015 read returns IRQ flags + length counter status
```

### Test Coverage
- **Length counter tests:** 25 unit tests covering all behavior
- **Frame counter tests:** 8 integration tests (timing, IRQ, mode switching)
- **Benchmark tests:** 3 performance measurement tests

---

## What AccuracyCoin Tests Require

### APU Test Breakdown (95 tests total)

**Group 1: Length Counter & Table (32 tests) - ✅ SHOULD PASS**
- APU Length Counter: 8 tests
  1. $4015 read before/after $4003 write
  2. $4017 write with $80 clocks immediately
  3. $4017 write with $00 doesn't clock
  4. Disabling channel clears length
  5. Length not loaded when disabled
  6. Halt flag prevents decrement
  7-8. Halt flag verification

- APU Length Table: 24 tests
  - All 32 LENGTH_TABLE entries (indices 0-31)

**Group 2: Frame Counter IRQ (15 tests) - ⚠️ PARTIAL**
- IRQ flag set/cleared correctly
- **Missing:** Re-set behavior (cycles 29829-29831) - Tests E-H
- **Missing:** Odd/even CPU cycle write timing - Tests A-D, J-L

**Group 3: Frame Counter 4-step/5-step (12 tests) - ✅ SHOULD PASS**
- Length counter clock timing at correct cycles
- 4-step: 14913, 29829
- 5-step: 14913, 37281

**Group 4: Delta Modulation Channel (15 tests) - ❌ FAIL**
- **Missing:** DMC timer ticking
- **Missing:** Sample playback (output level updates)
- **Missing:** DMC IRQ on sample end
- **Missing:** Looping behavior
- **Have:** DMA stall mechanics

**Group 5: DMA + Register Interactions (16 tests) - ⚠️ PARTIAL**
- **Have:** DMC DMA timing and bus conflicts
- **Missing:** APU register bus conflicts (write-only behavior)
- **Missing:** Proper open bus values for APU registers

---

## Missing Components (Priority Order)

### PHASE 2: Core Missing Features (HIGH PRIORITY)

#### P2.1: Frame Counter IRQ Edge Cases (3-4 hours)
**What's Missing:**
```zig
// IRQ flag re-set behavior at cycles 29829-29831
// AccuracyCoin tests E-H require this

// Current (simplified):
if (cycles == FRAME_4STEP_IRQ) {
    state.frame_irq_flag = true;
}

// Needed (re-set logic):
// Flag is actively RE-SET at cycles 29829, 29830, 29831
// Reading $4015 clears it, but hardware immediately re-sets if still in window
if (cycles >= 29829 and cycles <= 29831) {
    if (!state.irq_inhibit) {
        state.frame_irq_flag = true;
    }
}
```

**Tests Affected:** 4 tests (E-H)
**Complexity:** Medium (test-driven refinement)

---

#### P2.2: DMC Timer & Playback (6-8 hours)
**What's Missing:**
```zig
// State needed:
dmc_bits_remaining: u3 = 0,           // Shift register bit counter
dmc_silence_flag: bool = false,       // Output unit silence state
dmc_sample_buffer_empty: bool = true, // Sample buffer status

// Logic needed:
pub fn tickDmc(state: *ApuState) void {
    // Timer countdown
    if (state.dmc_timer > 0) {
        state.dmc_timer -= 1;
    } else {
        state.dmc_timer = state.dmc_timer_period;
        clockDmcOutput(state);
    }
}

fn clockDmcOutput(state: *ApuState) void {
    // Clock output unit (shifts bit, updates level)
    if (!state.dmc_silence_flag) {
        if (state.dmc_bits_remaining == 0) {
            state.dmc_bits_remaining = 8;
            if (state.dmc_sample_buffer_empty) {
                state.dmc_silence_flag = true;
            } else {
                // Load sample buffer into shift register
                state.dmc_silence_flag = false;
                state.dmc_sample_buffer_empty = true;
                // Trigger DMA fetch if bytes remaining > 0
            }
        }

        // Update output level based on shift register bit
        const bit = state.dmc_sample_buffer & 0x01;
        state.dmc_sample_buffer >>= 1;
        state.dmc_bits_remaining -= 1;

        if (bit == 1) {
            if (state.dmc_output <= 125) state.dmc_output += 2;
        } else {
            if (state.dmc_output >= 2) state.dmc_output -= 2;
        }
    }
}

// IRQ and looping logic in loadSampleByte()
if (state.dmc_bytes_remaining == 0) {
    const loop_flag = (state.dmc_regs[0] & 0x40) != 0;
    const irq_enabled = (state.dmc_regs[0] & 0x80) != 0;

    if (loop_flag) {
        // Restart sample
        state.dmc_current_address = 0xC000 + (@as(u16, state.dmc_sample_address) << 6);
        state.dmc_bytes_remaining = (@as(u16, state.dmc_sample_length) << 4) + 1;
    } else {
        state.dmc_active = false;
        if (irq_enabled) {
            state.dmc_irq_flag = true;
        }
    }
}
```

**Tests Affected:** 15 tests (DMC channel)
**Complexity:** High (multiple interacting state machines)

---

### PHASE 3: Audio Features (MEDIUM PRIORITY)

#### P3.1: Envelopes (4-5 hours)
**What's Missing:**
```zig
// State needed (per channel):
pulse1_envelope_start: bool = false,
pulse1_envelope_divider: u4 = 0,
pulse1_envelope_decay: u4 = 0,
pulse1_envelope_loop: bool = false,
pulse1_constant_volume: bool = false,
pulse1_volume_envelope: u4 = 0,

// Logic needed:
fn clockEnvelope(envelope: *EnvelopeState) void {
    if (envelope.start_flag) {
        envelope.start_flag = false;
        envelope.decay_level = 15;
        envelope.divider = envelope.divider_period;
    } else {
        if (envelope.divider > 0) {
            envelope.divider -= 1;
        } else {
            envelope.divider = envelope.divider_period;
            if (envelope.decay_level > 0) {
                envelope.decay_level -= 1;
            } else if (envelope.loop_flag) {
                envelope.decay_level = 15;
            }
        }
    }
}

fn clockQuarterFrame(state: *ApuState) void {
    clockEnvelope(&state.pulse1_envelope);
    clockEnvelope(&state.pulse2_envelope);
    clockEnvelope(&state.noise_envelope);
    clockLinearCounter(state);  // Also on quarter frame
}

// Get volume output:
fn getVolume(envelope: *EnvelopeState) u4 {
    if (envelope.constant_volume) {
        return envelope.volume_envelope;
    } else {
        return envelope.decay_level;
    }
}
```

**Tests Affected:** ~6 tests (indirect - affects volume behavior)
**Complexity:** Medium (well-documented algorithm)

---

#### P3.2: Triangle Linear Counter (3-4 hours)
**What's Missing:**
```zig
// State needed:
triangle_linear_counter: u7 = 0,
triangle_linear_reload: u7 = 0,
triangle_linear_reload_flag: bool = false,
triangle_control_flag: bool = false,  // Same as halt flag

// Logic needed:
fn clockLinearCounter(state: *ApuState) void {
    if (state.triangle_linear_reload_flag) {
        state.triangle_linear_counter = state.triangle_linear_reload;
    } else if (state.triangle_linear_counter > 0) {
        state.triangle_linear_counter -= 1;
    }

    if (!state.triangle_control_flag) {
        state.triangle_linear_reload_flag = false;
    }
}

// On $400B write:
state.triangle_linear_reload_flag = true;

// Triangle channel is silenced when linear counter == 0
```

**Tests Affected:** ~3 tests (triangle behavior)
**Complexity:** Medium (simpler than envelope)

---

#### P3.3: Sweep Units (4-5 hours)
**What's Missing:**
```zig
// State needed (per pulse channel):
pulse1_sweep_enabled: bool = false,
pulse1_sweep_divider: u3 = 0,
pulse1_sweep_period: u3 = 0,
pulse1_sweep_negate: bool = false,
pulse1_sweep_shift: u3 = 0,
pulse1_sweep_reload: bool = false,
pulse1_timer_period: u11 = 0,

// Logic needed:
fn clockSweep(sweep: *SweepState, pulse_num: u2) void {
    if (sweep.divider > 0) {
        sweep.divider -= 1;
    } else {
        sweep.divider = sweep.period;
        if (sweep.enabled and sweep.shift > 0 and !isMuted(sweep)) {
            sweep.timer_period = calculateTargetPeriod(sweep, pulse_num);
        }
    }

    if (sweep.reload) {
        sweep.reload = false;
        sweep.divider = sweep.period;
    }
}

fn calculateTargetPeriod(sweep: *SweepState, pulse_num: u2) u11 {
    const change = sweep.timer_period >> sweep.shift;
    if (sweep.negate) {
        // Pulse 1: ones' complement
        // Pulse 2: twos' complement
        if (pulse_num == 0) {
            return sweep.timer_period - change - 1;
        } else {
            return sweep.timer_period - change;
        }
    } else {
        return sweep.timer_period + change;
    }
}

fn isMuted(sweep: *SweepState) bool {
    const target = calculateTargetPeriod(sweep);
    return sweep.timer_period < 8 or target > 0x7FF;
}
```

**Tests Affected:** ~3 tests (sweep behavior, muting)
**Complexity:** Medium-High (complex muting rules)

---

### PHASE 4: Register Bus Conflicts (LOW PRIORITY)

#### P4.1: APU Register Open Bus (2-3 hours)
**What's Missing:**
```zig
// Write-only registers ($4000-$4013, $4017) should return open bus
// Currently might return $00 or wrong values

// In busRead():
if (address >= 0x4000 and address <= 0x4013) {
    // These are write-only - return open bus
    return self.open_bus;
}
if (address == 0x4017) {
    // Also write-only
    return self.open_bus;
}
```

**Tests Affected:** ~5 tests (APU Register Activation, bus conflicts)
**Complexity:** Low (simple fix)

---

## Implementation Order & Time Estimates

### Phase 2: Core Features (10-12 hours)
**Goal:** Pass 60-70 APU tests

1. **DMC Timer & Playback** (6-8h) - HIGHEST PRIORITY
   - Enables 15 DMC tests
   - Complex but well-documented

2. **Frame IRQ Edge Cases** (3-4h)
   - Enables 4 IRQ timing tests
   - Test-driven refinement approach

### Phase 3: Audio Features (11-14 hours)
**Goal:** Pass 75-85 APU tests

3. **Envelopes** (4-5h)
   - Enables ~6 volume-related tests
   - Quarter-frame clocking

4. **Linear Counter** (3-4h)
   - Enables ~3 triangle tests
   - Also quarter-frame

5. **Sweep Units** (4-5h)
   - Enables ~3 sweep tests
   - Half-frame clocking
   - Complex muting logic

### Phase 4: Polish (2-3 hours)
**Goal:** Pass 80-90 APU tests

6. **APU Register Open Bus** (2-3h)
   - Enables ~5 bus conflict tests
   - Simple fix, high test impact

### Total Estimated Time: 23-29 hours (3-4 days)

---

## Critical Questions & Risks

### 1. Frame Counter Timing Precision
**Question:** Are our cycle counts (7457, 14913, 22371, 29829) exact?

**Evidence:**
- NESDev wiki: "3728.5 APU cycles = 7457 CPU cycles" ✅
- Our implementation matches this

**Risk:** LOW - Timing appears correct, backed by multiple sources

---

### 2. IRQ Flag Re-Set Behavior
**Question:** How exactly does the IRQ flag re-set at cycles 29829-29831?

**Evidence from AccuracyCoin:**
- Test E: "Reading $4015 at cycle 29829 should NOT clear IRQ (it gets set again on following 2 cycles)"
- Test F: "1 cycle later should NOT clear IRQ (it gets set again on following 1 cycle)"
- Test G: "1 cycle later should NOT clear IRQ (it gets set again on this cycle)"
- Test H: "1 cycle later SHOULD clear IRQ"

**Interpretation:** Flag is actively RE-SET during cycles 29829-29831

**Risk:** MEDIUM - Will require test-driven refinement

**Approach:**
1. Implement V1 (flag set once, stays set)
2. Run tests E-H
3. Adjust based on exact failure messages
4. Iterate until all pass

---

### 3. DMC Timer Clocking
**Question:** When exactly does DMC timer tick relative to CPU cycles?

**Evidence:**
- DMC runs at CPU speed (not APU half-speed)
- Timer decrements every CPU cycle
- Output unit clocks when timer == 0

**Risk:** LOW - Well-documented behavior

---

### 4. Envelope/Sweep Implementation Priority
**Question:** Are these needed for AccuracyCoin to pass?

**Analysis:**
- Envelopes: Affect volume output (audio waveform)
- Sweeps: Affect pitch (audio frequency)
- AccuracyCoin tests focus on **timing and logic**, not audio output

**Verdict:** Can defer to Phase 3 if time-limited

**Priority:** DMC Timer > IRQ Edge Cases > Envelopes > Linear Counter > Sweeps

---

## Recommended Development Plan

### Option A: Aggressive (DMC Focus)
**Goal:** Maximum test passage quickly
**Time:** 10-12 hours

1. DMC Timer & Playback (6-8h)
2. Frame IRQ Edge Cases (3-4h)
3. **Run AccuracyCoin** - Expect ~60-70 tests passing

**Pros:** Highest test ROI, validates core timing
**Cons:** Skips audio features (envelopes, sweeps)

---

### Option B: Comprehensive (Full Audio)
**Goal:** Complete APU implementation
**Time:** 23-29 hours

1. DMC Timer & Playback (6-8h)
2. Frame IRQ Edge Cases (3-4h)
3. Envelopes (4-5h)
4. Linear Counter (3-4h)
5. Sweep Units (4-5h)
6. APU Register Open Bus (2-3h)
7. **Run AccuracyCoin** - Expect 80-90 tests passing

**Pros:** Complete implementation, future-proof
**Cons:** Takes 3-4 days, some features not tested by AccuracyCoin

---

### Option C: Balanced (Core + Critical Audio)
**Goal:** Best coverage/time ratio
**Time:** 14-17 hours

1. DMC Timer & Playback (6-8h)
2. Frame IRQ Edge Cases (3-4h)
3. Envelopes (4-5h)
4. **Run AccuracyCoin** - Expect ~70-80 tests passing

**Pros:** Good balance, covers most-tested features
**Cons:** Linear counter and sweeps deferred

---

## Recommended: Option A (Aggressive DMC Focus)

**Rationale:**
1. DMC has most tests (15)
2. DMC playback is complex - validates implementation quality
3. Frame IRQ edge cases complete timing accuracy
4. Can add audio features incrementally after baseline established
5. Faster feedback loop (10-12h vs 23-29h)

**Success Criteria:**
- ✅ 32/95 tests passing (length counters) → **Current**
- ✅ 60-70/95 tests passing → **After Phase 2**
- ✅ 80+/95 tests passing → **After Phase 3**

---

## Next Steps

### Before Implementation:
1. ✅ Read AccuracyCoin test documentation
2. ✅ Study nesdev.org APU specs
3. ✅ Audit current implementation
4. ⬜ **USER APPROVAL:** Review this plan, raise concerns
5. ⬜ **USER DECISION:** Choose Option A, B, or C

### During Implementation:
1. Create detailed task breakdown for chosen option
2. Implement features in priority order
3. Write unit tests for each component
4. Run AccuracyCoin after each phase
5. Document findings and adjustments

### Quality Gates:
- ✅ All existing 627 tests continue passing (zero regressions)
- ✅ New unit tests for each component
- ✅ Code documented with inline comments
- ✅ State/Logic separation maintained
- ✅ Cycle-accurate timing verified

---

## Open Issues & Questions for User

### Questions:
1. **Which implementation option?** A (aggressive), B (comprehensive), or C (balanced)?
2. **Audio output priority?** Do we need actual waveform generation, or just timing/logic?
3. **Time constraints?** Is 3-4 days acceptable for full implementation?
4. **Risk tolerance?** Should we validate DMC timing with nestest.nes first?

### Concerns:
1. **DMC Complexity:** Multi-state-machine with sample buffer, output unit, timer, and DMA coordination
2. **IRQ Edge Cases:** May require multiple test iterations to get exact behavior
3. **Test Coverage:** Some features (sweeps) have low AccuracyCoin coverage - worth implementing?

### Proposed Approach:
**Start with Option A (10-12 hours):**
1. Implement DMC timer & playback
2. Add IRQ edge cases
3. Run AccuracyCoin and analyze results
4. **DECISION POINT:** If 60-70 tests pass, continue to Phase 3 (audio features)
5. **DECISION POINT:** If failures occur, investigate and refine

---

**Awaiting user approval to proceed with implementation.**
