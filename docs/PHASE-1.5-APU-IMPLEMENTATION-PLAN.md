# Phase 1.5: APU Hardware Behavior Implementation

**Date:** 2025-10-06
**Status:** Research complete, ready for implementation
**Goal:** Implement length counters and frame counter clocking to pass ~38 AccuracyCoin APU tests

---

## Executive Summary

**Phase 1 Status:** ✅ COMPLETE - APU framework (registers, timing infrastructure) implemented, 585/585 tests passing

**Phase 1 Gap:** APU framework counts cycles but doesn't CLOCK anything. Length counters, envelopes, and sweep units are not implemented.

**Phase 1.5 Goal:** Implement minimal hardware behavior required for AccuracyCoin APU tests:
1. Length counters (all 4 channels)
2. Frame counter clocking (quarter/half frame events)
3. Critical timing fixes (IRQ flag re-set, $4017 write delay)

**Test Target:** ~38 AccuracyCoin tests (20 length counter, 12 frame counter, 6 timing)

**Estimated Time:** 10-12 hours total

**Deferred to Phase 2:** Envelopes, sweep units, DMC timer, actual audio output

---

## Research Documentation

### Architecture Documents Created

1. **`docs/architecture/apu-frame-counter.md`** (350+ lines)
   - Complete frame counter hardware specification
   - 4-step and 5-step mode timing
   - Register interfaces ($4017, $4015)
   - Quarter/half frame clock events
   - AccuracyCoin test mapping

2. **`docs/architecture/apu-length-counter.md`** (450+ lines)
   - Length counter table (32 values)
   - Per-channel state requirements
   - Load/decrement/halt behavior
   - Integration with frame counter
   - AccuracyCoin test mapping (38 tests)

3. **`docs/architecture/apu-timing-analysis.md`** (500+ lines)
   - Rising/falling edge analysis
   - Sub-cycle timing (".5 cycle" issue resolved)
   - $4017 write delay (3-4 cycles)
   - IRQ flag re-set behavior
   - Clock phase alignment
   - 2 critical issues identified, 6 verified correct

4. **`docs/APU-GAP-ANALYSIS-2025-10-06.md`** (350+ lines)
   - Comprehensive gap analysis
   - What we have vs what AccuracyCoin requires
   - Test categorization (~30-40 APU tests)
   - Implementation estimates

### Key Findings

**Critical Timing Issues Found:**
1. ❌ **IRQ Flag Re-Set:** Flag must be set EVERY cycle it's active (not just once)
2. ❌ **$4017 Write Delay:** 3-4 cycle delay not implemented

**Verified Correct:**
- ✅ Event timing (increment-then-check)
- ✅ Sub-cycle resolution (odd CPU cycles for ".5")
- ✅ Immediate length counter clear
- ✅ Direct CPU cycle counting
- ✅ State/Logic pattern adherence

---

## Implementation Roadmap

### Task 1: Fix Critical Timing Issues (2-3 hours)

**Priority:** HIGH - Required for 8 Frame Counter IRQ tests

#### 1.1: Implement IRQ Flag Re-Set Behavior

**Problem:** IRQ flag set once, not re-set if cleared by $4015 read on same cycle

**File:** `src/apu/Logic.zig`

**Changes:**
```zig
pub fn tickFrameCounter(state: *ApuState) bool {
    state.frame_counter_cycles += 1;
    const cycles = state.frame_counter_cycles;
    const is_5_step = state.frame_counter_mode;
    var should_irq = false;

    if (!is_5_step) {
        // ... quarter/half frame clocking ...

        // IRQ flag: Set EVERY cycle the condition is true
        // (Even if just cleared by $4015 read, re-set it)
        if ((cycles == FRAME_4STEP_IRQ or cycles == FRAME_4STEP_IRQ + 1)
            and !state.irq_inhibit) {
            state.frame_irq_flag = true;  // Re-set flag
            should_irq = true;
        }

        if (cycles >= FRAME_4STEP_TOTAL) {
            state.frame_counter_cycles = 0;
        }
    }

    return should_irq;
}
```

**Tests Affected:** Frame Counter IRQ error codes E-H (4 tests)

#### 1.2: Implement $4017 Write Delay (3-4 Cycles)

**Problem:** Write to $4017 takes effect immediately, should have 3-4 cycle delay

**File:** `src/apu/State.zig`

**Add State:**
```zig
pub const ApuState = struct {
    // ... existing fields ...

    // NEW: Pending $4017 write state
    frame_counter_write_pending: bool = false,
    frame_counter_write_value: u8 = 0,
    frame_counter_write_delay: u8 = 0,
};
```

**File:** `src/apu/Logic.zig`

**Split Write Handler:**
```zig
// Called when CPU writes to $4017
pub fn writeFrameCounter(state: *ApuState, value: u8, cpu_cycle_odd: bool) void {
    state.frame_counter_write_pending = true;
    state.frame_counter_write_value = value;

    // Delay: 3 cycles if odd CPU cycle write, 4 if even
    state.frame_counter_write_delay = if (cpu_cycle_odd) 3 else 4;
}

// Called after delay expires
fn applyFrameCounterWrite(state: *ApuState) void {
    const value = state.frame_counter_write_value;

    const new_mode = (value & 0x80) != 0;
    state.frame_counter_mode = new_mode;

    // 5-step mode: Immediately clock quarter + half frame
    if (new_mode) {
        clockQuarterFrame(state);
        clockHalfFrame(state);
    }

    // Reset counter
    state.frame_counter_cycles = 0;

    // IRQ inhibit
    const irq_inhibit = (value & 0x40) != 0;
    state.irq_inhibit = irq_inhibit;
    if (irq_inhibit) {
        state.frame_irq_flag = false;
    }
}
```

**Update Tick:**
```zig
pub fn tickFrameCounter(state: *ApuState) bool {
    // Process pending $4017 write
    if (state.frame_counter_write_pending) {
        if (state.frame_counter_write_delay > 0) {
            state.frame_counter_write_delay -= 1;
        } else {
            applyFrameCounterWrite(state);
            state.frame_counter_write_pending = false;
        }
    }

    // Normal counter increment and clocking
    state.frame_counter_cycles += 1;
    // ... rest of logic
}
```

**File:** `src/emulation/State.zig`

**Track CPU Cycle Parity:**
```zig
pub const EmulationState = struct {
    // ... existing fields ...

    cpu_cycle_odd: bool = false,  // NEW: Track CPU cycle parity
};

pub fn tick(self: *EmulationState) void {
    // ... existing tick logic ...

    self.cpu_cycle_odd = !self.cpu_cycle_odd;  // Toggle every cycle
}
```

**Update APU Write Routing:**
```zig
// In busWrite():
0x4017 => ApuLogic.writeFrameCounter(&self.apu, value, self.cpu_cycle_odd),
```

**Tests Affected:** Frame Counter IRQ error codes A-D (4 tests)

**Estimated Time:** 2-3 hours (includes testing)

---

### Task 2: Implement Length Counters (3-4 hours)

**Priority:** HIGHEST - Required for 38 AccuracyCoin tests

#### 2.1: Add Length Counter State

**File:** `src/apu/State.zig`

**Add Fields:**
```zig
pub const ApuState = struct {
    // ... existing fields ...

    // NEW: Length counters (u8, decrements on half-frame)
    pulse1_length: u8 = 0,
    pulse2_length: u8 = 0,
    triangle_length: u8 = 0,
    noise_length: u8 = 0,

    // NEW: Halt flags (prevent decrement)
    pulse1_halt: bool = false,
    pulse2_halt: bool = false,
    triangle_halt: bool = false,
    noise_halt: bool = false,

    // EXISTING: Channel enables (already in State from Phase 1)
    pulse1_enabled: bool = false,
    pulse2_enabled: bool = false,
    triangle_enabled: bool = false,
    noise_enabled: bool = false,
};
```

#### 2.2: Add Length Counter Logic

**File:** `src/apu/Logic.zig`

**Add Constant:**
```zig
const LENGTH_TABLE: [32]u8 = .{
    10, 254, 20,  2, 40,  4, 80,  6,
   160,   8, 60, 10, 14, 12, 26, 14,
    12,  16, 24, 18, 48, 20, 96, 22,
   192,  24, 72, 26, 16, 28, 32, 30,
};
```

**Add Helper:**
```zig
fn clockLengthCounters(state: *ApuState) void {
    // Pulse 1
    if (state.pulse1_length > 0 and !state.pulse1_halt) {
        state.pulse1_length -= 1;
    }

    // Pulse 2
    if (state.pulse2_length > 0 and !state.pulse2_halt) {
        state.pulse2_length -= 1;
    }

    // Triangle
    if (state.triangle_length > 0 and !state.triangle_halt) {
        state.triangle_length -= 1;
    }

    // Noise
    if (state.noise_length > 0 and !state.noise_halt) {
        state.noise_length -= 1;
    }
}
```

**Update Stubs:**
```zig
fn clockQuarterFrame(state: *ApuState) void {
    // TODO Phase 2: Clock envelopes and triangle linear counter
    _ = state;
}

fn clockHalfFrame(state: *ApuState) void {
    clockLengthCounters(state);  // ← NEW
    // TODO Phase 2: Clock sweep units
}
```

#### 2.3: Update Register Handlers

**Pulse 1 Registers:**
```zig
pub fn writePulse1(state: *ApuState, offset: u2, value: u8) void {
    state.regs_pulse1[offset] = value;

    switch (offset) {
        0 => {
            // $4000: DDLC VVVV
            // Bit 5: Length counter halt / Envelope loop
            state.pulse1_halt = (value & 0x20) != 0;
        },
        3 => {
            // $4003: LLLL Lttt
            // Bits 3-7: Length counter table index
            if (state.pulse1_enabled) {
                const table_index = (value >> 3) & 0x1F;
                state.pulse1_length = LENGTH_TABLE[table_index];
            }
        },
        else => {},
    }
}
```

**Same pattern for Pulse 2, Triangle, Noise:**
```zig
pub fn writePulse2(state: *ApuState, offset: u2, value: u8) void {
    state.regs_pulse2[offset] = value;
    switch (offset) {
        0 => state.pulse2_halt = (value & 0x20) != 0,
        3 => if (state.pulse2_enabled) {
            state.pulse2_length = LENGTH_TABLE[(value >> 3) & 0x1F];
        },
        else => {},
    }
}

pub fn writeTriangle(state: *ApuState, offset: u2, value: u8) void {
    state.regs_triangle[offset] = value;
    switch (offset) {
        0 => state.triangle_halt = (value & 0x80) != 0,  // Note: Bit 7
        3 => if (state.triangle_enabled) {
            state.triangle_length = LENGTH_TABLE[(value >> 3) & 0x1F];
        },
        else => {},
    }
}

pub fn writeNoise(state: *ApuState, offset: u2, value: u8) void {
    state.regs_noise[offset] = value;
    switch (offset) {
        0 => state.noise_halt = (value & 0x20) != 0,
        3 => if (state.noise_enabled) {
            state.noise_length = LENGTH_TABLE[(value >> 3) & 0x1F];
        },
        else => {},
    }
}
```

#### 2.4: Update Control Register ($4015)

**Update `writeControl()`:**
```zig
pub fn writeControl(state: *ApuState, value: u8) void {
    // Update channel enables
    state.pulse1_enabled = (value & 0x01) != 0;
    state.pulse2_enabled = (value & 0x02) != 0;
    state.triangle_enabled = (value & 0x04) != 0;
    state.noise_enabled = (value & 0x08) != 0;

    // Disabled channels: Clear length counter IMMEDIATELY
    if (!state.pulse1_enabled) state.pulse1_length = 0;
    if (!state.pulse2_enabled) state.pulse2_length = 0;
    if (!state.triangle_enabled) state.triangle_length = 0;
    if (!state.noise_enabled) state.noise_length = 0;

    // DMC enable (existing code)
    const dmc_enable = (value & 0x10) != 0;
    // ... existing DMC logic
}
```

**Update `readStatus()`:**
```zig
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

    // Clear frame IRQ flag when read
    state.frame_irq_flag = false;

    return result;
}
```

**Estimated Time:** 3-4 hours (includes testing)

---

### Task 3: Integration and Testing (2-3 hours)

#### 3.1: Wire Up Frame Counter Clocking

**Verify `tickFrameCounter()` calls clock functions:**
```zig
pub fn tickFrameCounter(state: *ApuState) bool {
    // ... pending write handling ...

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
            clockHalfFrame(state);  // ← Clocks length counters
        } else if (cycles == FRAME_4STEP_QUARTER3) {
            clockQuarterFrame(state);
        } else if (cycles == FRAME_4STEP_IRQ) {
            clockHalfFrame(state);  // ← Clocks length counters
            // IRQ flag logic...
        }
    } else {
        // 5-step mode (similar pattern)
        // ...
    }

    // Counter reset and IRQ logic...
    return should_irq;
}
```

#### 3.2: Unit Tests for Length Counters

**File:** `tests/apu/length_counter_test.zig` (new file)

```zig
const std = @import("std");
const testing = std.testing;
const ApuModule = @import("RAMBO").Apu;
const ApuState = ApuModule.State.ApuState;
const ApuLogic = ApuModule.Logic;

test "Length counter: Load from table" {
    var apu = ApuState.init();

    // Enable pulse 1
    ApuLogic.writeControl(&apu, 0x01);

    // Write to $4003 with table index 0x00 (bits 3-7)
    ApuLogic.writePulse1(&apu, 3, 0x00);  // Index 0 → value 10
    try testing.expectEqual(@as(u8, 10), apu.pulse1_length);

    // Write with table index 0x1F (all bits set)
    ApuLogic.writePulse1(&apu, 3, 0xF8);  // Index 31 → value 30
    try testing.expectEqual(@as(u8, 30), apu.pulse1_length);
}

test "Length counter: Decrement on half-frame" {
    var apu = ApuState.init();

    // Enable pulse 1, set halt = false
    ApuLogic.writeControl(&apu, 0x01);
    ApuLogic.writePulse1(&apu, 0, 0x00);  // Halt = 0

    // Load length counter
    ApuLogic.writePulse1(&apu, 3, 0x00);  // Value = 10
    try testing.expectEqual(@as(u8, 10), apu.pulse1_length);

    // Clock half-frame
    ApuLogic.clockHalfFrame(&apu);
    try testing.expectEqual(@as(u8, 9), apu.pulse1_length);

    ApuLogic.clockHalfFrame(&apu);
    try testing.expectEqual(@as(u8, 8), apu.pulse1_length);
}

test "Length counter: Halt flag prevents decrement" {
    var apu = ApuState.init();

    // Enable pulse 1, set halt = true
    ApuLogic.writeControl(&apu, 0x01);
    ApuLogic.writePulse1(&apu, 0, 0x20);  // Halt = 1 (bit 5)

    // Load length counter
    ApuLogic.writePulse1(&apu, 3, 0x00);  // Value = 10
    try testing.expectEqual(@as(u8, 10), apu.pulse1_length);

    // Clock half-frame (should NOT decrement)
    ApuLogic.clockHalfFrame(&apu);
    try testing.expectEqual(@as(u8, 10), apu.pulse1_length);
}

test "Length counter: Disable clears immediately" {
    var apu = ApuState.init();

    // Enable pulse 1, load counter
    ApuLogic.writeControl(&apu, 0x01);
    ApuLogic.writePulse1(&apu, 3, 0x00);  // Value = 10
    try testing.expectEqual(@as(u8, 10), apu.pulse1_length);

    // Disable pulse 1
    ApuLogic.writeControl(&apu, 0x00);
    try testing.expectEqual(@as(u8, 0), apu.pulse1_length);
}

test "Length counter: $4015 read returns status" {
    var apu = ApuState.init();

    // Initially, no channels have length > 0
    var status = ApuLogic.readStatus(&apu);
    try testing.expectEqual(@as(u8, 0), status & 0x0F);

    // Enable pulse 1, load counter
    ApuLogic.writeControl(&apu, 0x01);
    ApuLogic.writePulse1(&apu, 3, 0x00);  // Value = 10

    // Read status: bit 0 should be set
    status = ApuLogic.readStatus(&apu);
    try testing.expectEqual(@as(u8, 0x01), status & 0x01);
}
```

**Register in build.zig:**
```zig
const length_counter_tests = b.addTest(.{
    .root_module = b.createModule(.{
        .root_source_file = b.path("tests/apu/length_counter_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ .{ .name = "RAMBO", .module = mod } },
    }),
});

const run_length_counter_tests = b.addRunArtifact(length_counter_tests);
test_step.dependOn(&run_length_counter_tests.step);
```

#### 3.3: Run AccuracyCoin Tests

**Test Sequence:**
1. Run all existing tests → confirm no regressions (585/585)
2. Run new length counter unit tests → confirm logic correct
3. Run AccuracyCoin APU Length Counter test → target 8/8 passing
4. Run AccuracyCoin APU Length Table test → target 24/24 passing
5. Run AccuracyCoin Frame Counter 4-step → target 6/6 passing
6. Run AccuracyCoin Frame Counter 5-step → target 6/6 passing
7. Run AccuracyCoin Frame Counter IRQ → target 8-15 passing (depending on timing fixes)

**If Tests Fail:**
- Check cycle constants (may need ±1 adjustment)
- Validate frame counter step timing
- Confirm IRQ flag behavior
- Debug with cycle-by-cycle logging

**Estimated Time:** 2-3 hours (includes debugging)

---

## Test Coverage

### Phase 1.5 Test Targets

**AccuracyCoin Tests:**
- APU Length Counter: 8 tests
- APU Length Table: 24 tests
- Frame Counter 4-step: 6 tests
- Frame Counter 5-step: 6 tests
- Frame Counter IRQ: 8-15 tests (depending on timing fixes)

**Total:** ~38-45 AccuracyCoin tests

**Existing Tests:** 585 tests must continue passing (no regressions)

**New Unit Tests:** ~10 length counter unit tests

**Final Count:** ~633-640 total tests

---

## Design Pattern Adherence

### State/Logic Separation

**ApuState (pure data):**
- ✅ All state fields explicit (no hidden state)
- ✅ Simple data types (u8, bool, u32)
- ✅ No pointers to other components
- ✅ Fully serializable

**ApuLogic (pure functions):**
- ✅ All functions take `*ApuState` parameter
- ✅ No global variables
- ✅ No heap allocations
- ✅ Deterministic (same input = same output)

**No Side Effects:**
- ✅ Logic functions only modify ApuState
- ✅ IRQ signaling via return value (not direct CPU modification)
- ✅ Bus integration via explicit routing

---

## Success Criteria

### Minimum Viable (Phase 1.5 Complete)

- ✅ All 585 existing tests passing (no regressions)
- ✅ Length counters implemented (4 channels)
- ✅ Frame counter clocks length counters (half-frame events)
- ✅ $4015 status register returns length counter status
- ✅ $4015 write clears disabled channel length counters
- ✅ AccuracyCoin APU Length Counter: 8/8 passing
- ✅ AccuracyCoin APU Length Table: 24/24 passing
- ✅ AccuracyCoin Frame Counter 4-step: 6/6 passing
- ✅ AccuracyCoin Frame Counter 5-step: 6/6 passing

### Stretch Goal

- ✅ Frame Counter IRQ timing fixes (Task 1)
- ✅ AccuracyCoin Frame Counter IRQ: 15/15 passing
- ✅ ~45 AccuracyCoin APU tests passing total

---

## Timeline

**Total Estimated Time:** 10-12 hours

**Task Breakdown:**
- Task 1: Critical timing fixes (2-3 hours)
- Task 2: Length counter implementation (3-4 hours)
- Task 3: Integration and testing (2-3 hours)
- Task 4: Documentation and cleanup (1-2 hours)

**Suggested Schedule:**
- Day 1 (4 hours): Task 1 + Task 2.1-2.2
- Day 2 (4 hours): Task 2.3-2.4 + Task 3.1
- Day 3 (4 hours): Task 3.2-3.3 + Task 4

---

## Deferred to Phase 2 (Audio Synthesis)

**Not Required for AccuracyCoin:**
- Envelopes (volume control) - no audio output tests
- Triangle linear counter - length counter tests sufficient
- Sweep units (pitch bending) - low test coverage
- DMC timer and sample playback - separate DMC test category
- Actual audio waveform generation - no audio tests in AccuracyCoin

**When to Implement:**
- Phase 2: After video display working
- When adding actual audio output via SDL/PulseAudio
- When running games that require audio (e.g., Super Mario Bros)

---

## References

- **Architecture Docs:** `docs/architecture/apu-*.md`
- **Gap Analysis:** `docs/APU-GAP-ANALYSIS-2025-10-06.md`
- **AccuracyCoin README:** `AccuracyCoin/README.md`
- **NESDev Wiki:** https://www.nesdev.org/wiki/APU

---

## Next Actions

1. ✅ Research complete (this document)
2. ⬜ Begin Task 1: Critical timing fixes
3. ⬜ Begin Task 2: Length counter implementation
4. ⬜ Task 3: Integration and AccuracyCoin validation
5. ⬜ Update CLAUDE.md with Phase 1.5 completion status
