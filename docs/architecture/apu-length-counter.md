# APU Length Counter - Hardware Architecture

**Date:** 2025-10-06
**Status:** Architecture documentation for Phase 1.5 implementation
**References:** NESDev Wiki, AccuracyCoin test suite

---

## Overview

Length counters control the duration of notes on all APU channels (pulse 1, pulse 2, triangle, noise). Each channel has an independent length counter that:
1. Loads a value from a 32-entry lookup table when triggered
2. Decrements on half-frame clock events (approximately 120 Hz)
3. Silences the channel when it reaches zero

**Critical Insight:** Length counters are DIRECTLY TESTED by AccuracyCoin (32 tests total). This is the highest-priority missing feature.

---

## Hardware Specifications (NESDev Wiki)

### Length Counter Table (32 Values)

**Table Index:** Bits 3-7 of $4003/$4007/$400B/$400F

```zig
const LENGTH_TABLE: [32]u8 = .{
    10, 254, 20,  2, 40,  4, 80,  6,  // 0x00-0x07
   160,   8, 60, 10, 14, 12, 26, 14,  // 0x08-0x0F
    12,  16, 24, 18, 48, 20, 96, 22,  // 0x10-0x17
   192,  24, 72, 26, 16, 28, 32, 30,  // 0x18-0x1F
};
```

**AccuracyCoin Test:** APU Length Table (24 error codes, tests A-X) validates every single table entry

---

## Per-Channel State

Each of the 4 channels (pulse 1, pulse 2, triangle, noise) requires:

```zig
pub const ApuState = struct {
    // Length counters (decrement on half-frame clock)
    pulse1_length: u8 = 0,
    pulse2_length: u8 = 0,
    triangle_length: u8 = 0,
    noise_length: u8 = 0,

    // Halt flags (prevent length counter decrement)
    // Extracted from $4000 bit 5, $4004 bit 5, $4008 bit 7, $400C bit 5
    pulse1_halt: bool = false,
    pulse2_halt: bool = false,
    triangle_halt: bool = false,  // Note: Also called "linear counter control"
    noise_halt: bool = false,

    // Channel enable flags (from $4015 bits 0-3)
    pulse1_enabled: bool = false,
    pulse2_enabled: bool = false,
    triangle_enabled: bool = false,
    noise_enabled: bool = false,
};
```

---

## Length Counter Lifecycle

### 1. Loading (Triggered by Register Write)

**Pulse 1:** Write to $4003
```
$4003 = LLLL Lttt
        |||| |+++--- Fine tune (timer low 3 bits)
        ++++-+------ Length counter table index (0-31)
```

**Behavior:**
```zig
// When $4003 written:
if (pulse1_enabled) {
    const table_index = (value >> 3) & 0x1F;
    pulse1_length = LENGTH_TABLE[table_index];
}
// If channel disabled, length counter NOT loaded
```

**Same pattern for:**
- Pulse 2: $4007 writes load `pulse2_length`
- Triangle: $400B writes load `triangle_length`
- Noise: $400F writes load `noise_length`

### 2. Halt Flag Configuration

**Pulse 1:** Bit 5 of $4000
```
$4000 = DDLC VVVV
        || | ||||
        || | ++++--- Volume / Envelope period
        || +-------- Constant volume flag
        |+---------- Length counter halt / Envelope loop
        +----------- Duty cycle
```

**Behavior:**
```zig
// When $4000 written:
pulse1_halt = (value & 0x20) != 0;  // Bit 5
```

**Same pattern for:**
- Pulse 2: $4004 bit 5 → `pulse2_halt`
- Triangle: $4008 bit 7 → `triangle_halt`
- Noise: $400C bit 5 → `noise_halt`

### 3. Decrement (Half-Frame Clock)

**Triggered by:** Frame counter half-frame events (120 Hz)

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

**AccuracyCoin Test:** Frame Counter 4-step and 5-step tests (12 total) validate half-frame clock timing

### 4. Channel Disable (Immediate Clear)

**Triggered by:** Write to $4015 with channel enable bit = 0

```zig
// When $4015 written:
fn writeControl(state: *ApuState, value: u8) void {
    state.pulse1_enabled = (value & 0x01) != 0;
    state.pulse2_enabled = (value & 0x02) != 0;
    state.triangle_enabled = (value & 0x04) != 0;
    state.noise_enabled = (value & 0x08) != 0;

    // Disabled channels: Clear length counter IMMEDIATELY
    if (!state.pulse1_enabled) state.pulse1_length = 0;
    if (!state.pulse2_enabled) state.pulse2_length = 0;
    if (!state.triangle_enabled) state.triangle_length = 0;
    if (!state.noise_enabled) state.noise_length = 0;
}
```

**AccuracyCoin Test:** APU Length Counter error code 5 validates immediate clear on disable

---

## Status Register Interface: $4015

### Read (Report Length Counter Status)

```
$4015 = IF-D NT21
        || | ||||
        || | |||+-- Pulse 1: 1 if length counter > 0, else 0
        || | ||+--- Pulse 2: 1 if length counter > 0, else 0
        || | |+---- Triangle: 1 if length counter > 0, else 0
        || | +----- Noise: 1 if length counter > 0, else 0
        || +------- DMC: 1 if bytes remaining > 0, else 0
        |+--------- Frame IRQ flag
        +---------- DMC IRQ flag
```

**Implementation:**
```zig
fn readStatus(state: *ApuState) u8 {
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

    return result;
}
```

**AccuracyCoin Tests:**
- APU Length Counter error codes 1-2: $4015 bits 0-3 reflect length counter state

### Write (Enable/Disable Channels)

```
$4015 = ---D NT21
           | ||||
           | |||+-- Pulse 1 enable (0 = disable, clear length counter)
           | ||+--- Pulse 2 enable
           | |+---- Triangle enable
           | +----- Noise enable
           +------- DMC enable (separate behavior)
```

**Side Effects:**
- Bit 0 = 0: Clear `pulse1_length` to 0
- Bit 1 = 0: Clear `pulse2_length` to 0
- Bit 2 = 0: Clear `triangle_length` to 0
- Bit 3 = 0: Clear `noise_length` to 0

**AccuracyCoin Test:** APU Length Counter error code 5 validates immediate length counter clear

---

## Edge Cases & Special Behaviors

### Halt Flag ("Infinite Play")

**When halt flag is set:**
- Length counter does NOT decrement on half-frame clocks
- Length counter value remains unchanged
- Channel continues playing indefinitely (or until manually disabled)

**AccuracyCoin Tests:**
- Error code 7: Halt flag prevents decrement
- Error code 8: Halt flag leaves counter unchanged

**Use Case:** Sustained notes (e.g., continuous background drone)

### Length Counter Load When Disabled

**Hardware Behavior:**
```zig
// Writing to $4003 when pulse1_enabled = false:
if (pulse1_enabled) {
    // Load from table - NORMAL BEHAVIOR
    pulse1_length = LENGTH_TABLE[index];
} else {
    // Channel disabled - length counter NOT loaded
    // pulse1_length remains 0
}
```

**AccuracyCoin Test:** APU Length Counter error code 6 validates this

**Rationale:** Prevents accidental channel activation before explicitly enabling via $4015

### Frame Counter Immediate Clock

**Hardware Behavior:**
- Writing $80 to $4017 (5-step mode): Immediately clocks quarter + half frame
- This includes immediate length counter decrement (if not halted)

**AccuracyCoin Test:** APU Length Counter error code 3

**Implementation:**
```zig
fn writeFrameCounter(state: *ApuState, value: u8) void {
    const new_mode = (value & 0x80) != 0;  // Bit 7: 5-step mode

    // Mode transitions
    state.frame_counter_mode = new_mode;

    // 5-step mode: Immediately clock quarter + half frame
    if (new_mode) {
        clockQuarterFrame(state);  // Envelopes + linear counter
        clockHalfFrame(state);      // Length counters + sweep units
    }

    // Reset counter (after 3-4 cycle delay in real hardware)
    state.frame_counter_cycles = 0;

    // IRQ inhibit handling
    const irq_inhibit = (value & 0x40) != 0;
    state.irq_inhibit = irq_inhibit;
    if (irq_inhibit) {
        state.frame_irq_flag = false;  // Clear IRQ flag
    }
}
```

---

## Integration with Frame Counter

### Half-Frame Clock Timing

**4-Step Mode:**
```
Cycle 14913 (step 2): clockHalfFrame()  → decrement length counters
Cycle 29829 (step 4): clockHalfFrame()  → decrement length counters
```

**5-Step Mode:**
```
Cycle 14913 (step 2): clockHalfFrame()  → decrement length counters
Cycle 37281 (step 5): clockHalfFrame()  → decrement length counters
```

**Implementation in `tickFrameCounter()`:**
```zig
pub fn tickFrameCounter(state: *ApuState) bool {
    state.frame_counter_cycles += 1;
    const cycles = state.frame_counter_cycles;
    const is_5_step = state.frame_counter_mode;

    if (!is_5_step) {
        // 4-step mode
        if (cycles == FRAME_4STEP_QUARTER1) {
            clockQuarterFrame(state);
        } else if (cycles == FRAME_4STEP_HALF) {
            clockQuarterFrame(state);
            clockHalfFrame(state);  // ← Length counters decremented here
        } else if (cycles == FRAME_4STEP_QUARTER3) {
            clockQuarterFrame(state);
        } else if (cycles == FRAME_4STEP_IRQ) {
            clockHalfFrame(state);  // ← Length counters decremented here
            // IRQ flag handling...
        }
    } else {
        // 5-step mode
        if (cycles == FRAME_5STEP_QUARTER1) {
            clockQuarterFrame(state);
        } else if (cycles == FRAME_5STEP_HALF) {
            clockQuarterFrame(state);
            clockHalfFrame(state);  // ← Length counters decremented here
        } else if (cycles == FRAME_5STEP_QUARTER3) {
            clockQuarterFrame(state);
        } else if (cycles == FRAME_5STEP_FINAL) {
            clockQuarterFrame(state);
            clockHalfFrame(state);  // ← Length counters decremented here
        }
    }

    // Counter reset and IRQ logic...
}
```

---

## Implementation Checklist (Phase 1.5)

### State.zig Changes

```zig
pub const ApuState = struct {
    // Existing fields...
    frame_counter_mode: bool = false,
    frame_counter_cycles: u32 = 0,
    // ... etc

    // NEW: Length counters
    pulse1_length: u8 = 0,
    pulse2_length: u8 = 0,
    triangle_length: u8 = 0,
    noise_length: u8 = 0,

    // NEW: Halt flags (extracted from $4000/$4004/$4008/$400C)
    pulse1_halt: bool = false,
    pulse2_halt: bool = false,
    triangle_halt: bool = false,
    noise_halt: bool = false,
};
```

### Logic.zig Changes

**Add constants:**
```zig
const LENGTH_TABLE: [32]u8 = .{
    10, 254, 20,  2, 40,  4, 80,  6,
   160,   8, 60, 10, 14, 12, 26, 14,
    12,  16, 24, 18, 48, 20, 96, 22,
   192,  24, 72, 26, 16, 28, 32, 30,
};
```

**Add helper:**
```zig
fn clockLengthCounters(state: *ApuState) void {
    if (state.pulse1_length > 0 and !state.pulse1_halt) {
        state.pulse1_length -= 1;
    }
    if (state.pulse2_length > 0 and !state.pulse2_halt) {
        state.pulse2_length -= 1;
    }
    if (state.triangle_length > 0 and !state.triangle_halt) {
        state.triangle_length -= 1;
    }
    if (state.noise_length > 0 and !state.noise_halt) {
        state.noise_length -= 1;
    }
}
```

**Update `clockHalfFrame()` stub:**
```zig
fn clockHalfFrame(state: *ApuState) void {
    clockLengthCounters(state);
    // TODO Phase 2: Clock sweep units
}
```

**Update register writes:**
```zig
pub fn writePulse1(state: *ApuState, offset: u2, value: u8) void {
    state.regs_pulse1[offset] = value;

    switch (offset) {
        0 => {
            // $4000: Duty, loop/halt, constant volume, volume/envelope
            state.pulse1_halt = (value & 0x20) != 0;
        },
        3 => {
            // $4003: Length counter load, timer high
            if (state.pulse1_enabled) {
                const table_index = (value >> 3) & 0x1F;
                state.pulse1_length = LENGTH_TABLE[table_index];
            }
        },
        else => {},
    }
}
```

**Update `writeControl()`:**
```zig
pub fn writeControl(state: *ApuState, value: u8) void {
    state.pulse1_enabled = (value & 0x01) != 0;
    state.pulse2_enabled = (value & 0x02) != 0;
    state.triangle_enabled = (value & 0x04) != 0;
    state.noise_enabled = (value & 0x08) != 0;

    // Clear length counters when disabled
    if (!state.pulse1_enabled) state.pulse1_length = 0;
    if (!state.pulse2_enabled) state.pulse2_length = 0;
    if (!state.triangle_enabled) state.triangle_length = 0;
    if (!state.noise_enabled) state.noise_length = 0;

    // DMC control (bit 4)
    // ...existing DMC code
}
```

**Update `readStatus()`:**
```zig
pub fn readStatus(state: *ApuState) u8 {
    var result: u8 = 0;

    // Length counter status
    if (state.pulse1_length > 0) result |= 0x01;
    if (state.pulse2_length > 0) result |= 0x02;
    if (state.triangle_length > 0) result |= 0x04;
    if (state.noise_length > 0) result |= 0x08;

    // DMC status
    if (state.dmc_bytes_remaining > 0) result |= 0x10;

    // IRQ flags
    if (state.frame_irq_flag) result |= 0x40;
    if (state.dmc_irq_flag) result |= 0x80;

    return result;
}
```

---

## Test Coverage Mapping

### AccuracyCoin: APU Length Counter (8 tests)

1. **Error code 1:** Reading $4015 before $4003 write → bit 0 should be 0
2. **Error code 2:** Reading $4015 after $4003 write → bit 0 should be 1
3. **Error code 3:** Writing $80 to $4017 immediately clocks length counter
4. **Error code 4:** Writing $00 to $4017 does NOT clock length counter
5. **Error code 5:** Disabling channel ($4015 bit 0 = 0) clears length counter
6. **Error code 6:** Length counter not loaded when channel disabled
7. **Error code 7:** Halt flag prevents length counter decrement
8. **Error code 8:** Halt flag leaves length counter value unchanged

### AccuracyCoin: APU Length Table (24 tests)

**Error codes 2-X:** Validates all 32 table entries
- Test index 0x00 → value 10
- Test index 0x01 → value 254
- Test index 0x02 → value 20
- ... all 32 entries ...
- Test index 0x1F → value 30

### AccuracyCoin: Frame Counter 4-step (6 tests)

1-2. **Error codes 1-2:** First half-frame clock at cycle 14913 (early/late)
3-4. **Error codes 3-4:** Second half-frame clock at cycle 29829 (early/late)

### AccuracyCoin: Frame Counter 5-step (6 tests)

1-2. **Error codes 1-2:** First half-frame clock at cycle 14913 (early/late)
3-4. **Error codes 3-4:** Second half-frame clock at cycle 37281 (early/late)

**Total:** 38 AccuracyCoin tests dependent on length counter implementation

---

## Performance Considerations

**Computational Cost:** Negligible
- 4 u8 comparisons + decrements per half-frame clock
- Half-frame clock occurs ~120 times per second
- Total: ~480 operations/second

**Memory Cost:**
- 4 bytes (length counters)
- 4 bytes (halt flags, bit-packed)
- Total: 8 bytes additional state

**Design Pattern Adherence:**
- ✅ State stored in `ApuState` (pure data)
- ✅ Logic in `Logic.zig` (pure functions)
- ✅ No heap allocations
- ✅ Deterministic behavior

---

## References

- **NESDev Wiki:** https://www.nesdev.org/wiki/APU_Length_Counter
- **NESDev Wiki:** https://www.nesdev.org/wiki/APU_Pulse
- **AccuracyCoin Tests:** APU Length Counter, APU Length Table, Frame Counter 4-step, Frame Counter 5-step
- **Implementation:** `src/apu/State.zig`, `src/apu/Logic.zig`

---

## Next Steps

1. ✅ Document length counter architecture (this file)
2. ⬜ Document DMC/DPCM architecture
3. ⬜ Implement length counter state in `State.zig`
4. ⬜ Implement length counter logic in `Logic.zig`
5. ⬜ Update register write handlers to extract halt flags and load counters
6. ⬜ Update `clockHalfFrame()` to call `clockLengthCounters()`
7. ⬜ Run AccuracyCoin APU Length Counter tests
8. ⬜ Validate all 38 tests pass
