# APU Implementation Gap Analysis
**Date:** 2025-10-06
**Status:** Critical gaps identified
**Purpose:** Comprehensive analysis of what's implemented vs what AccuracyCoin requires

---

## Executive Summary

**Current Status:** Phase 1 APU provides register state tracking and frame counter timing, but **DOES NOT** implement the hardware behavior required for AccuracyCoin's ~30-40 APU tests to pass.

**Critical Finding:** Our implementation has the timing framework but lacks the actual hardware emulation that the timing drives.

---

## What We Have (Phase 1 - Completed)

### ✅ Implemented Features
1. **Frame Counter State Machine**
   - Cycle counter increments correctly
   - 4-step vs 5-step mode selection
   - Frame IRQ flag set at correct cycle (29829-29830)
   - IRQ inhibit flag
   - Reading $4015 clears frame IRQ flag

2. **DMC DMA State Machine**
   - RDY line stall (4 cycles: 3 idle + 1 fetch)
   - Variant-aware NTSC corruption (repeat reads)
   - Sample address tracking
   - Sample fetch triggering

3. **APU Register Routing**
   - All $4000-$4017 registers routed
   - Register writes stored in state
   - $4015 status read returns IRQ flags

4. **Bus Integration**
   - APU accessible via bus
   - DMC DMA priority (DMC > OAM > CPU)
   - IRQ line signaling to CPU

### ⚠️ Partially Implemented
- **DMC Channel State:** Structure exists but timer doesn't tick
- **Channel Enable Flags:** Stored but not processed
- **Register Storage:** Values stored but not used

---

## What AccuracyCoin Tests Require

### Test Categories (From GitHub Analysis)

#### 1. **Length Counter Tests** (~10 tests)
**What's Tested:**
- Writing to $4003/$4007/$400B/$400F sets length counter
- Reading $4015 before/after length counter writes
- Clocking length counter with $4017 (frame counter)
- Disabling channels clears length counter
- Infinite play settings (halt flag)

**What We Need:**
- [ ] Length counter table (32 values)
- [ ] Length counter decrement on half-frame clock
- [ ] Halt flag prevents decrement
- [ ] Writing to $400X loads counter from table
- [ ] $4015 bits 0-4 return non-zero when counter > 0
- [ ] Writing 0 to $4015 bits 0-4 clears counter

**Current Status:** ❌ NOT IMPLEMENTED (all stubbed)

---

#### 2. **Frame Counter IRQ Tests** (~8 tests)
**What's Tested:**
- IRQ flag behavior in 4-step mode
- IRQ flag NOT set in 5-step mode
- IRQ flag cleared on mode transitions
- Odd/even CPU cycle timing differences
- Reading $4015 clears IRQ flag

**What We Need:**
- [x] IRQ flag set at cycles 29829-29830 in 4-step mode
- [x] No IRQ in 5-step mode
- [x] IRQ inhibit flag
- [ ] Writing to $4017 on odd CPU cycle affects timing
- [ ] Mode transitions clear IRQ flag correctly

**Current Status:** ⚠️ PARTIAL (timing correct, edge cases untested)

---

#### 3. **Frame Counter Clocking Tests** (~6 tests)
**What's Tested:**
- Length counters clocked at correct half-frame steps
- Envelopes clocked at quarter-frame steps
- Triangle linear counter clocked at quarter-frames
- Sweep units clocked at half-frames

**What We Need:**
- [ ] Quarter-frame handler (clock envelopes + linear counter)
- [ ] Half-frame handler (clock length + sweep)
- [ ] Actual envelope implementation
- [ ] Actual linear counter implementation
- [ ] Actual sweep unit implementation

**Current Status:** ❌ NOT IMPLEMENTED (TODO comments only)

---

#### 4. **DMC Tests** (~8 tests)
**What's Tested:**
- DMC sample playback timing
- DMC IRQ on sample end
- DMC looping behavior
- DMC DMA bus conflicts
- DMA timing (odd/even cycles)
- Reading $4015 DMC IRQ flag

**What We Need:**
- [ ] DMC timer ticking (countdown from rate table)
- [ ] DMC sample buffer shifting
- [ ] DMC output level updates
- [ ] Sample end detection triggers IRQ
- [ ] Loop flag restarts sample
- [ ] DMA halt/alignment cycle bus access tracking

**Current Status:** ⚠️ PARTIAL (DMA stall works, playback missing)

---

#### 5. **APU Register Access Tests** (~5 tests)
**What's Tested:**
- OAM DMA reading from APU registers
- Bus conflicts with APU write-only registers
- Controllers clocked despite APU register visibility

**What We Need:**
- [ ] Bus conflict emulation (write-only register behavior)
- [ ] Proper open bus values for write-only registers
- [ ] OAM DMA can read from APU space

**Current Status:** ❌ NOT IMPLEMENTED

---

## Critical Timing Questions

### Frame Counter Timing Uncertainty

**Issue:** Conflicting information about exact cycle counts.

**From NESDev Wiki:**
- APU runs at half CPU speed (1 APU cycle = 2 CPU cycles)
- 4-step mode: 3728, 7456, 11185, 14914 **APU cycles**
- Converted to CPU: 7456, 14912, 22370, 29828 CPU cycles?

**Our Implementation:**
```zig
const FRAME_4STEP_QUARTER1: u32 = 7457;  // vs 7456 or 3728?
const FRAME_4STEP_HALF: u32 = 14913;     // vs 14912 or 7456?
const FRAME_4STEP_QUARTER3: u32 = 22371; // vs 22370 or 11185?
const FRAME_4STEP_IRQ: u32 = 29829;      // vs 29828 or 14914?
const FRAME_4STEP_TOTAL: u32 = 29830;    // vs 29828 or 14915?
```

**From Web Search:**
- "Delays between steps: 7459 delay to Step 1, then 7456, then 7458, then 7458"
- Cumulative: 7459, 14915, 22373, 29831
- OR: "3728.5 APU cycles = 7457 CPU cycles"

**Resolution Needed:**
- [ ] Run hardware test ROM on accurate emulator
- [ ] Compare exact cycle counts with known-good implementation
- [ ] Verify our off-by-1-or-2 values
- [ ] Determine if half-cycle offset is correct

---

## Missing Core Components

### 1. Length Counter (HIGH PRIORITY)

**Required for:** ~10 AccuracyCoin tests

**Implementation Needed:**
```zig
// In ApuState
pulse1_length: u8 = 0,
pulse2_length: u8 = 0,
triangle_length: u8 = 0,
noise_length: u8 = 0,

// Length counter table (indexed by $4003/$4007/$400B/$400F bits 3-7)
const LENGTH_TABLE: [32]u8 = .{
    10, 254, 20,  2, 40,  4, 80,  6,
    160,  8, 60, 10, 14, 12, 26, 14,
    12, 16, 24, 18, 48, 20, 96, 22,
    192, 24, 72, 26, 16, 28, 32, 30,
};

// On half-frame clock:
fn clockLengthCounters(state: *ApuState) void {
    if (!halt_flag_pulse1 and pulse1_length > 0) pulse1_length -= 1;
    // ... for each channel
}

// On $4003 write:
if (pulse1_enabled) {
    pulse1_length = LENGTH_TABLE[(value >> 3) & 0x1F];
}

// On $4015 read:
result |= if (pulse1_length > 0) 0x01 else 0;
```

**Files to Modify:**
- `src/apu/State.zig` - Add length counter fields
- `src/apu/Logic.zig` - Add LENGTH_TABLE and clockLengthCounters()
- `src/apu/Logic.zig` - Update writeControl() to load length on enable
- `src/apu/Logic.zig` - Update writeControl() to clear length on disable
- `src/apu/Logic.zig` - Update readStatus() to return length counter status
- `src/apu/Logic.zig` - Update tickFrameCounter() to call clockLengthCounters()

**Estimated Time:** 3-4 hours (including tests)

---

### 2. Envelope & Linear Counter (MEDIUM PRIORITY)

**Required for:** ~6 AccuracyCoin tests

**Implementation Needed:**
```zig
// Envelope (for pulse and noise)
envelope_divider: u4 = 0,
envelope_counter: u4 = 0,
envelope_start_flag: bool = false,

// Triangle linear counter
triangle_linear_counter: u7 = 0,
triangle_linear_reload: u7 = 0,
triangle_linear_reload_flag: bool = false,
```

**Estimated Time:** 4-5 hours

---

### 3. DMC Timer & Playback (MEDIUM PRIORITY)

**Required for:** ~8 AccuracyCoin tests

**Implementation Needed:**
```zig
// In tickApu():
if (dmc_active) {
    if (dmc_timer > 0) {
        dmc_timer -= 1;
    } else {
        dmc_timer = dmc_timer_period;
        // Clock DMC sample buffer, trigger DMA if needed
    }
}
```

**Estimated Time:** 3-4 hours

---

### 4. Sweep Units (LOW PRIORITY for AccuracyCoin)

**Required for:** ~3 AccuracyCoin tests

**Estimated Time:** 3-4 hours

---

## Recommended Action Plan

### Phase 1.5: Core APU Features (10-12 hours)

**Goal:** Pass majority of AccuracyCoin APU tests

**Priority Order:**
1. **Length Counters** (3-4h) - Required for most tests
2. **Frame Counter Clocking** (2h) - Wire up quarter/half frame handlers
3. **DMC Timer** (3-4h) - Sample playback and IRQ
4. **Status Register** (1h) - Correct $4015 read behavior
5. **Testing & Validation** (2-3h) - Run AccuracyCoin APU tests

**Deferred to Phase 2:**
- Envelopes (needed for volume, not critical)
- Sweep units (pitch bending, low test coverage)
- Actual audio output (completely deferred)

---

## Testing Strategy

### 1. Unit Tests
- Length counter load from table
- Length counter decrement on half-frame
- Halt flag prevents decrement
- $4015 status bits

### 2. Integration Tests
- Frame counter clocks length counters
- DMC timer triggers DMA fetch
- Channel disable clears length counter

### 3. ROM Tests
- Run AccuracyCoin APU subset
- Count passing tests before/after
- Target: 80%+ APU tests passing

---

## Open Questions

1. **Timing Precision:** Are our frame counter cycle counts off by 1-2? Need hardware verification.
2. **Bus Conflicts:** Do we need to emulate write-only register bus behavior for AccuracyCoin?
3. **DMC DMA Alignment:** Does AccuracyCoin test the specific cycle alignment behavior?
4. **Odd/Even Cycle Writes:** Does writing to $4017 on odd vs even CPU cycle matter?

---

## Success Criteria

**Minimum Viable (Phase 1.5):**
- [ ] Length counters implemented and tested
- [ ] Frame counter clocks length counters
- [ ] DMC timer and IRQ functional
- [ ] $4015 status register accurate
- [ ] 60%+ of AccuracyCoin APU tests pass

**Stretch Goal:**
- [ ] All length counter tests pass
- [ ] All DMC tests pass
- [ ] All frame IRQ tests pass
- [ ] 80%+ of AccuracyCoin APU tests pass

---

## Next Steps

1. **IMMEDIATE:** Verify frame counter timing with known-good emulator
2. **IMMEDIATE:** Create detailed Phase 1.5 implementation plan
3. **BEFORE CODING:** Answer all timing questions
4. **BEFORE CODING:** Validate length counter table values
5. **START:** Implement length counters (highest ROI)

