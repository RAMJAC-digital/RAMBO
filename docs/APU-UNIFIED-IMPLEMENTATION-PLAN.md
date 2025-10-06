# APU Unified Implementation Plan (Phase 2/3 Combined)

**Date:** 2025-10-06
**Goal:** Implement ALL missing APU components to achieve 80-90/95 AccuracyCoin tests passing
**Time Estimate:** 20-25 hours (more efficient than sequential phases)
**Architecture:** Independent channels, future-ready for audio mailbox output

---

## Executive Summary

**Current State:** 32/95 APU tests passing (length counters complete)
**Target State:** 80-90/95 APU tests passing (full APU emulation)
**Strategy:** Implement components in dependency order, extensive testing at each step

**Key Architectural Decisions:**
1. **Independent Channel Processing:** Each channel (Pulse1, Pulse2, Triangle, Noise, DMC) has isolated state
2. **Reusable Components:** Envelope and Sweep as generic components
3. **Future Audio Ready:** Design supports AudioOutputMailbox (beyond spec, deferred)
4. **Zero Regressions:** Continuous testing, existing 627 tests always passing

---

## Architecture Design

### Channel Independence

```zig
// Each channel is fully independent with its own state
pub const ApuState = struct {
    // Pulse 1 Channel (complete isolation)
    pulse1: PulseChannel = .{},

    // Pulse 2 Channel
    pulse2: PulseChannel = .{},

    // Triangle Channel
    triangle: TriangleChannel = .{},

    // Noise Channel
    noise: NoiseChannel = .{},

    // DMC Channel
    dmc: DmcChannel = .{},

    // Frame counter (clocks all channels)
    frame_counter: FrameCounter = .{},
};

// Reusable component: Envelope (used by Pulse1, Pulse2, Noise)
pub const Envelope = struct {
    start_flag: bool = false,
    divider: u4 = 0,
    decay_level: u4 = 0,
    loop_flag: bool = false,
    constant_volume: bool = false,
    volume_envelope: u4 = 0,

    pub fn clock(self: *Envelope) void { ... }
    pub fn getVolume(self: *const Envelope) u4 { ... }
};

// Reusable component: Sweep (used by Pulse1, Pulse2)
pub const Sweep = struct {
    enabled: bool = false,
    divider: u3 = 0,
    period: u3 = 0,
    negate: bool = false,
    shift: u3 = 0,
    reload_flag: bool = false,

    pub fn clock(self: *Sweep, timer_period: *u11, channel: u1) void { ... }
    pub fn isMuted(self: *const Sweep, timer_period: u11, channel: u1) bool { ... }
};

// Independent channel structures
pub const PulseChannel = struct {
    enabled: bool = false,
    length_counter: u8 = 0,
    halt_flag: bool = false,
    envelope: Envelope = .{},
    sweep: Sweep = .{},
    timer_period: u11 = 0,
    regs: [4]u8 = [_]u8{0} ** 4,
};

pub const TriangleChannel = struct {
    enabled: bool = false,
    length_counter: u8 = 0,
    halt_flag: bool = false,  // Also control flag for linear counter
    linear_counter: u7 = 0,
    linear_reload: u7 = 0,
    linear_reload_flag: bool = false,
    timer_period: u11 = 0,
    regs: [4]u8 = [_]u8{0} ** 4,
};

pub const NoiseChannel = struct {
    enabled: bool = false,
    length_counter: u8 = 0,
    halt_flag: bool = false,
    envelope: Envelope = .{},
    timer_period: u4 = 0,
    mode_flag: bool = false,  // Periodic vs random
    regs: [4]u8 = [_]u8{0} ** 4,
};

pub const DmcChannel = struct {
    enabled: bool = false,
    irq_enabled: bool = false,
    loop_flag: bool = false,
    timer: u16 = 0,
    timer_period: u16 = 0,
    output_level: u7 = 0,
    sample_address: u8 = 0,
    sample_length: u8 = 0,
    current_address: u16 = 0,
    bytes_remaining: u16 = 0,
    sample_buffer: u8 = 0,
    sample_buffer_empty: bool = true,
    bits_remaining: u3 = 0,
    shift_register: u8 = 0,
    silence_flag: bool = true,
    irq_flag: bool = false,
    regs: [4]u8 = [_]u8{0} ** 4,
};
```

### Future Audio Mailbox Architecture (Beyond Spec, Design Only)

```zig
// FUTURE: Audio output mailbox (not implemented in this phase)
// Design consideration: Each channel can independently write samples

pub const AudioSample = struct {
    pulse1: u4,      // 4-bit volume
    pulse2: u4,
    triangle: u4,    // 4-bit step
    noise: u4,
    dmc: u7,         // 7-bit level
};

// FUTURE: Beyond spec - deferred until video display working
// pub const AudioOutputMailbox = Mailbox(AudioSample);
```

**Note:** We design channels for independence NOW, but actual audio output (waveform generation, mixing, mailbox) is DEFERRED until video subsystem is working.

---

## Implementation Order (Dependency-Driven)

### Phase 2A: Core DMC (Day 1: 6-8 hours)
**Why First:** Most complex, highest test count, validates overall timing

**Implements:**
1. DMC timer countdown
2. DMC output unit (shift register, silence flag)
3. DMC sample buffer management
4. DMC IRQ and looping logic
5. Integration with existing DMA mechanics

**Tests Added:** 15-20 unit tests
**AccuracyCoin Impact:** +15 tests (47/95 = 49%)

---

### Phase 2B: Envelopes (Day 2: 4-5 hours)
**Why Second:** Required for volume behavior, reusable component

**Implements:**
1. Generic Envelope struct
2. Envelope clocking (quarter-frame)
3. Integration with Pulse1, Pulse2, Noise
4. Start flag, decay, loop, constant volume

**Tests Added:** 10-12 unit tests
**AccuracyCoin Impact:** +6 tests (53/95 = 56%)

---

### Phase 2C: Linear Counter (Day 2: 3-4 hours)
**Why Third:** Triangle channel timing, also quarter-frame

**Implements:**
1. Linear counter state
2. Linear counter clocking (quarter-frame)
3. Reload flag and control flag interaction
4. Triangle channel silencing

**Tests Added:** 8-10 unit tests
**AccuracyCoin Impact:** +3 tests (56/95 = 59%)

---

### Phase 2D: Sweep Units (Day 3: 4-5 hours)
**Why Fourth:** Pulse channel frequency modulation, half-frame

**Implements:**
1. Generic Sweep struct
2. Sweep clocking (half-frame)
3. Target period calculation
4. Muting conditions (period < 8 or target > $7FF)
5. Pulse 1 vs Pulse 2 negate difference

**Tests Added:** 10-12 unit tests
**AccuracyCoin Impact:** +3 tests (59/95 = 62%)

---

### Phase 2E: Frame IRQ Edge Cases (Day 3: 3-4 hours)
**Why Fifth:** Completes frame counter accuracy

**Implements:**
1. IRQ flag re-set at cycles 29829-29831
2. Test-driven refinement based on AccuracyCoin results

**Tests Added:** 5-6 unit tests
**AccuracyCoin Impact:** +4 tests (63/95 = 66%)

---

### Phase 2F: APU Register Open Bus (Day 4: 2-3 hours)
**Why Last:** Simple fix, high test impact

**Implements:**
1. Write-only register behavior
2. Correct open bus values for $4000-$4013, $4017
3. $4015 read doesn't update open bus

**Tests Added:** 3-4 unit tests
**AccuracyCoin Impact:** +5 tests (68/95 = 72%)

---

### Phase 2G: Integration & Refinement (Day 4: 2-3 hours)
**Why Final:** Verify all components work together

**Activities:**
1. Run full AccuracyCoin test suite
2. Analyze failures
3. Refine edge cases
4. Document findings

**Expected Final Result:** 80-90/95 tests passing (84-95%)

---

## Detailed Component Specifications

### 1. DMC Timer & Output Unit

**State Fields:**
```zig
pub const DmcChannel = struct {
    // Timer
    timer: u16 = 0,              // Current timer value
    timer_period: u16 = 0,       // Reload value from rate table

    // Output Unit
    output_level: u7 = 0,        // Current output (0-127)
    shift_register: u8 = 0,      // 8-bit sample shift register
    bits_remaining: u3 = 0,      // Bits left in shift register
    silence_flag: bool = true,   // Output unit silenced

    // Sample Buffer
    sample_buffer: u8 = 0,       // Next sample byte
    sample_buffer_empty: bool = true,

    // Memory Reader
    current_address: u16 = 0,    // Current sample address
    bytes_remaining: u16 = 0,    // Bytes left in sample

    // Control
    enabled: bool = false,
    irq_enabled: bool = false,
    loop_flag: bool = false,
    irq_flag: bool = false,
};
```

**Logic:**
```zig
pub fn tickDmc(state: *DmcChannel) bool {
    var trigger_dma = false;

    // Timer countdown
    if (state.timer > 0) {
        state.timer -= 1;
    } else {
        state.timer = state.timer_period;

        // Clock output unit
        if (!state.silence_flag) {
            // Shift out one bit
            const bit = state.shift_register & 0x01;
            state.shift_register >>= 1;
            state.bits_remaining -= 1;

            // Update output level
            if (bit == 1) {
                if (state.output_level <= 125) {
                    state.output_level += 2;
                }
            } else {
                if (state.output_level >= 2) {
                    state.output_level -= 2;
                }
            }

            // Check if shift register empty
            if (state.bits_remaining == 0) {
                state.bits_remaining = 8;

                if (state.sample_buffer_empty) {
                    state.silence_flag = true;
                } else {
                    // Load sample buffer into shift register
                    state.shift_register = state.sample_buffer;
                    state.sample_buffer_empty = true;

                    // Trigger DMA if bytes remaining
                    if (state.bytes_remaining > 0) {
                        trigger_dma = true;
                    }
                }
            }
        }
    }

    return trigger_dma;
}

pub fn loadSampleByte(state: *DmcChannel, value: u8) void {
    state.sample_buffer = value;
    state.sample_buffer_empty = false;

    // Update address (wraps $FFFF -> $8000)
    if (state.current_address == 0xFFFF) {
        state.current_address = 0x8000;
    } else {
        state.current_address += 1;
    }

    state.bytes_remaining -= 1;

    // Check for sample end
    if (state.bytes_remaining == 0) {
        if (state.loop_flag) {
            // Restart sample
            state.current_address = 0xC000 + (@as(u16, state.sample_address) << 6);
            state.bytes_remaining = (@as(u16, state.sample_length) << 4) + 1;
        } else {
            // Sample complete
            if (state.irq_enabled) {
                state.irq_flag = true;
            }
        }
    }
}
```

**Tests:**
1. Timer countdown and reload
2. Output level increment (+2)
3. Output level decrement (-2)
4. Output level clamping (0-127)
5. Shift register behavior
6. Sample buffer loading
7. Silence flag management
8. DMA triggering
9. Sample looping
10. IRQ on sample end
11. Address wrapping ($FFFF → $8000)
12. Bits remaining counter
13. Integration with existing DMA
14. $4015 bit 4 (DMC active status)
15. $4010-$4013 register writes

---

### 2. Envelope (Reusable Component)

**State:**
```zig
pub const Envelope = struct {
    start_flag: bool = false,
    divider: u4 = 0,
    decay_level: u4 = 0,
    loop_flag: bool = false,
    constant_volume: bool = false,
    volume_envelope: u4 = 0,
};
```

**Logic:**
```zig
pub fn clock(self: *Envelope) void {
    if (self.start_flag) {
        self.start_flag = false;
        self.decay_level = 15;
        self.divider = self.volume_envelope;
    } else {
        if (self.divider > 0) {
            self.divider -= 1;
        } else {
            self.divider = self.volume_envelope;

            if (self.decay_level > 0) {
                self.decay_level -= 1;
            } else if (self.loop_flag) {
                self.decay_level = 15;
            }
        }
    }
}

pub fn getVolume(self: *const Envelope) u4 {
    if (self.constant_volume) {
        return self.volume_envelope;
    } else {
        return self.decay_level;
    }
}

pub fn restart(self: *Envelope) void {
    self.start_flag = true;
}
```

**Tests:**
1. Start flag clears and reloads
2. Decay level countdown
3. Divider countdown and reload
4. Loop flag behavior
5. Constant volume mode
6. Volume output (constant vs decay)
7. Integration with pulse1/pulse2/noise
8. Register writes ($4000, $4004, $400C)
9. Quarter-frame clocking
10. Multiple envelope instances independent

---

### 3. Linear Counter (Triangle Only)

**State:**
```zig
// Inside TriangleChannel
linear_counter: u7 = 0,
linear_reload: u7 = 0,
linear_reload_flag: bool = false,
halt_flag: bool = false,  // Also control flag
```

**Logic:**
```zig
pub fn clockLinearCounter(triangle: *TriangleChannel) void {
    if (triangle.linear_reload_flag) {
        triangle.linear_counter = triangle.linear_reload;
    } else if (triangle.linear_counter > 0) {
        triangle.linear_counter -= 1;
    }

    if (!triangle.halt_flag) {
        triangle.linear_reload_flag = false;
    }
}

// On $400B write (timer high)
triangle.linear_reload_flag = true;

// Triangle is silenced when:
// linear_counter == 0 OR length_counter == 0
```

**Tests:**
1. Linear counter reload
2. Linear counter decrement
3. Reload flag behavior
4. Control flag interaction
5. Triangle silencing conditions
6. Register writes ($4008, $400B)
7. Quarter-frame clocking
8. Interaction with length counter

---

### 4. Sweep Unit (Reusable Component)

**State:**
```zig
pub const Sweep = struct {
    enabled: bool = false,
    divider: u3 = 0,
    period: u3 = 0,
    negate: bool = false,
    shift: u3 = 0,
    reload_flag: bool = false,
};
```

**Logic:**
```zig
pub fn clock(self: *Sweep, timer_period: *u11, channel: u1) void {
    // Update divider
    if (self.divider == 0 and self.enabled and self.shift > 0 and !self.isMuted(timer_period.*, channel)) {
        timer_period.* = self.calculateTarget(timer_period.*, channel);
    }

    if (self.divider == 0 or self.reload_flag) {
        self.divider = self.period;
        self.reload_flag = false;
    } else {
        self.divider -= 1;
    }
}

pub fn calculateTarget(self: *const Sweep, current: u11, channel: u1) u11 {
    const change_amount = current >> self.shift;

    if (self.negate) {
        // Pulse 1: ones' complement (subtract change + 1)
        // Pulse 2: twos' complement (subtract change)
        if (channel == 0) {
            return current -% change_amount -% 1;
        } else {
            return current -% change_amount;
        }
    } else {
        return current +% change_amount;
    }
}

pub fn isMuted(self: *const Sweep, current: u11, channel: u1) bool {
    const target = self.calculateTarget(current, channel);
    return current < 8 or target > 0x7FF;
}

// On $4001/$4005 write
sweep.reload_flag = true;
```

**Tests:**
1. Divider countdown and reload
2. Target period calculation (add mode)
3. Target period calculation (negate mode)
4. Pulse 1 vs Pulse 2 negate difference
5. Muting condition (period < 8)
6. Muting condition (target > $7FF)
7. Sweep enable flag
8. Reload flag behavior
9. Register writes ($4001, $4005)
10. Half-frame clocking
11. Two sweep instances independent
12. Period update conditions

---

### 5. Frame IRQ Edge Cases

**Current Logic:**
```zig
if (cycles == FRAME_4STEP_IRQ) {
    clockHalfFrame(state);
    if (!state.irq_inhibit) {
        state.frame_irq_flag = true;
        should_irq = true;
    }
}
```

**Updated Logic (Test-Driven Refinement):**
```zig
// IRQ flag is actively RE-SET during cycles 29829-29831
// This is the V1 implementation - will refine based on AccuracyCoin failures

if (cycles >= 29829 and cycles <= 29831) {
    if (!state.irq_inhibit) {
        state.frame_irq_flag = true;
        should_irq = true;
    }
}

// Half-frame clocking still at 29829
if (cycles == 29829) {
    clockHalfFrame(state);
}
```

**Tests:**
1. IRQ flag set at cycle 29829
2. IRQ flag stays set at cycle 29830
3. IRQ flag stays set at cycle 29831
4. Reading $4015 at 29829 doesn't clear (re-set on 29830, 29831)
5. Reading $4015 at 29832 clears successfully
6. IRQ inhibit prevents flag setting
7. Cycle 29828 doesn't set flag
8. Test-driven refinement based on AccuracyCoin E-H

---

### 6. APU Register Open Bus

**Current Issue:**
```zig
// Write-only registers may return $00 or wrong values
```

**Fix:**
```zig
// In busRead():
if (address >= 0x4000 and address <= 0x4013) {
    // Write-only APU registers - return open bus
    return self.open_bus;
}

if (address == 0x4017) {
    // Also write-only
    return self.open_bus;
}

// $4015 read does NOT update open bus (special case)
if (address == 0x4015) {
    // Don't update open_bus on read
    return ApuLogic.readStatus(&self.apu);
}
```

**Tests:**
1. $4000-$4013 return open bus
2. $4017 returns open bus
3. $4015 read doesn't update open bus
4. Write to $4015 updates open bus
5. OAM DMA can read from APU space
6. Bus conflicts with APU registers

---

## Testing Strategy

### Test Organization

```
tests/apu/
├── dmc_test.zig              # 15-20 DMC tests
├── envelope_test.zig         # 10-12 envelope tests
├── linear_counter_test.zig   # 8-10 linear counter tests
├── sweep_test.zig            # 10-12 sweep tests
├── frame_irq_edge_test.zig   # 5-6 IRQ edge case tests
├── open_bus_test.zig         # 3-4 open bus tests
└── integration_test.zig      # 10-15 full integration tests

Total New Tests: ~65-80 unit + integration tests
```

### Test-First Development

**For Each Component:**
1. Write unit tests FIRST (based on nesdev.org specs)
2. Implement component to pass tests
3. Run existing 627 tests - verify zero regressions
4. Run AccuracyCoin - check test count improvement
5. Document findings

### Continuous Validation

**After Each Component:**
```bash
# Run all tests
zig build test --summary all

# Verify zero regressions
# Expected: 627 + N new tests passing

# Run AccuracyCoin
zig build test 2>&1 | grep -A 20 "AccuracyCoin"

# Verify test count improvement
```

---

## Development Milestones

### Milestone 1: DMC Complete (Day 1, 6-8h)
- ✅ DMC timer ticking
- ✅ Output unit state machine
- ✅ Sample buffer management
- ✅ IRQ and looping
- ✅ 15-20 unit tests passing
- ✅ Zero regressions
- **Checkpoint:** Run AccuracyCoin, expect 47/95 tests

---

### Milestone 2: Envelopes Complete (Day 2, 4-5h)
- ✅ Generic Envelope component
- ✅ Integration with Pulse1, Pulse2, Noise
- ✅ 10-12 unit tests passing
- ✅ Zero regressions
- **Checkpoint:** Run AccuracyCoin, expect 53/95 tests

---

### Milestone 3: Linear Counter Complete (Day 2, 3-4h) - ✅ COMPLETE
- ✅ Linear counter implementation
- ✅ Triangle channel timing
- ✅ 15 unit tests passing
- ✅ Zero regressions (672 → 687 total tests)
- **Checkpoint:** Run AccuracyCoin, expect 56/95 tests (blocked by PRG RAM)

---

### Milestone 4: Sweep Units Complete (Day 3, 4-5h) - ✅ COMPLETE
- ✅ Generic Sweep component
- ✅ Integration with Pulse1, Pulse2
- ✅ Muting logic
- ✅ 25 unit tests passing
- ✅ Zero regressions (687 → 712 total tests)
- **Checkpoint:** Run AccuracyCoin, expect 59/95 tests (blocked by PRG RAM)

---

### Milestone 5: Frame IRQ Edge Cases (Day 3, 3-4h)
- ✅ IRQ re-set logic
- ✅ 5-6 unit tests passing
- ✅ Zero regressions
- **Checkpoint:** Run AccuracyCoin, expect 63/95 tests

---

### Milestone 6: Open Bus Fix (Day 4, 2-3h)
- ✅ Write-only register behavior
- ✅ 3-4 unit tests passing
- ✅ Zero regressions
- **Checkpoint:** Run AccuracyCoin, expect 68/95 tests

---

### Milestone 7: Integration & Refinement (Day 4, 2-3h)
- ✅ Full AccuracyCoin run
- ✅ Analyze failures
- ✅ Refine edge cases
- **Final Target:** 80-90/95 tests passing

---

## Architecture Verification Checklist

### Independent Channel Design ✓
- [ ] Each channel has isolated state
- [ ] No cross-channel dependencies in state
- [ ] Frame counter clocks all channels independently
- [ ] Channels can be tested in isolation

### Reusable Components ✓
- [ ] Envelope generic for Pulse1/Pulse2/Noise
- [ ] Sweep generic for Pulse1/Pulse2
- [ ] Components tested independently
- [ ] Components compose correctly

### Future Audio Mailbox Ready ✓
- [ ] Channels process independently
- [ ] Output values accessible per channel
- [ ] Design supports future AudioSample struct
- [ ] No blocking or synchronization issues

### State/Logic Separation ✓
- [ ] All state in ApuState struct
- [ ] All logic in ApuLogic pure functions
- [ ] No hidden state
- [ ] Fully serializable for save states

### No Future Conflicts ✓
- [ ] No hardcoded channel counts
- [ ] No shared mutable state between channels
- [ ] Clean register routing
- [ ] Extensible for future features

---

## Risk Mitigation

### Risk 1: DMC Complexity
**Mitigation:**
- Implement timer, output unit, sample buffer separately
- Unit test each state machine independently
- Extensive logging during development
- Cross-reference with nesdev.org at each step

### Risk 2: IRQ Edge Cases Unknown
**Mitigation:**
- Test-driven refinement approach
- Implement V1, run AccuracyCoin
- Analyze exact error messages
- Iterate based on failures (expect 2-3 iterations)

### Risk 3: Component Interaction Bugs
**Mitigation:**
- Integration tests after each component
- Continuous AccuracyCoin runs
- Test channel combinations
- Document all interactions

### Risk 4: Time Estimation
**Mitigation:**
- Build in 20% buffer (20-25h estimate)
- Checkpoint after each milestone
- Can pause/resume between components
- Parallel testing development

---

## Success Criteria

### Must Have:
- ✅ All DMC tests passing (15/15)
- ✅ All length counter tests passing (32/32)
- ✅ All frame counter tests passing (12/12)
- ✅ Zero regressions (627+ tests passing)
- ✅ 80+ AccuracyCoin tests passing (84%+)

### Should Have:
- ✅ All envelope tests passing
- ✅ All linear counter tests passing
- ✅ All sweep tests passing
- ✅ Clean independent channel architecture
- ✅ 85+ AccuracyCoin tests passing (89%+)

### Nice to Have:
- ✅ 90/95 AccuracyCoin tests passing (95%)
- ✅ Comprehensive integration test coverage
- ✅ Performance benchmarks updated
- ✅ Documentation of all edge cases

---

## Post-Implementation

### Beyond AccuracyCoin (Future Work):
1. **Audio Output Mailbox** - For actual sound generation
2. **Waveform Generation** - Pulse duty cycles, triangle steps, noise LFSR
3. **DAC Mixing** - Combine channel outputs with nonlinear mixing
4. **Audio Thread** - Separate thread consuming AudioOutputMailbox

**Note:** Audio output is DEFERRED until video display is working. This implementation focuses on timing and logic accuracy only.

---

## Ready to Begin

**Development Plan:** ✅ Complete
**Architecture Design:** ✅ Complete
**Testing Strategy:** ✅ Complete
**Risk Mitigation:** ✅ Complete

**Time Estimate:** 20-25 hours (4-5 days)
**Expected Result:** 80-90/95 AccuracyCoin tests passing

**Next Step:** Proceed with Milestone 1 (DMC Implementation)

---

**Any questions, concerns, or requested changes before beginning development?**

---

## MILESTONE 1 STATUS UPDATE (2025-10-06)

### ✅ DMC Timer & Playback - COMPLETE

**Implementation:** 100% Complete (6 hours)
- ✅ DMC state fields added to ApuState (11 fields)
- ✅ Pure functional Dmc.zig module (187 lines)
- ✅ Integration with emulation loop (tickDmc called every CPU cycle)
- ✅ Side effects properly isolated to EmulationState.tickApu()
- ✅ 25 comprehensive unit tests (all passing)
- ✅ Zero regressions (627 → 652 total tests)

**Test Results:**
- Timer countdown: ✅ Verified
- Output unit (shift register): ✅ Verified
- Level modification (+2/-2): ✅ Verified
- Clamping (0-127): ✅ Verified
- Sample buffer management: ✅ Verified
- DMA triggering: ✅ Verified
- IRQ generation: ✅ Verified
- Looping behavior: ✅ Verified

**Architecture Validation:**
```zig
// ✅ Pure state (no logic)
dmc_timer: u16
dmc_output: u7
dmc_shift_register: u8

// ✅ Pure logic (no side effects)
pub fn tick(apu: *ApuState) bool {
    // Returns: should trigger DMA
}

// ✅ Side effects isolated to EmulationState
const needs_dma = ApuLogic.tickDmc(&self.apu);
if (needs_dma) self.dmc_dma.triggerFetch(address);
```

### ⚠️ AccuracyCoin Validation BLOCKED

**Issue:** PRG RAM ($6000-$7FFF) not implemented in Mapper0
- AccuracyCoin writes test results to PRG RAM
- Current Mapper0 returns open bus (0xFF) for $6000-$7FFF
- Test extraction reads all 0xFF → Cannot determine pass/fail
- **NOT an APU bug** - Cartridge feature gap

**Documentation:** See `docs/PRG-RAM-GAP.md` for complete analysis

**Decision:** Defer PRG RAM implementation (2-3 hours) until Milestones 2-7 complete
- Unit tests provide sufficient validation (25 DMC tests passing)
- Maintain momentum on APU feature development
- Implement PRG RAM as final step before comprehensive AccuracyCoin testing

### Next: Milestone 2 - Envelopes (4-5 hours)

**Status:** Ready to begin

### ✅ Milestone 2: Envelopes - COMPLETE (2025-10-06)

**Implementation:** 100% Complete (4 hours)
- ✅ Envelope module created (src/apu/Envelope.zig, 106 lines)
- ✅ Reusable Envelope structure (used by pulse1, pulse2, noise)
- ✅ Integration with ApuState (3 envelope instances)
- ✅ Register write handlers updated (writePulse1, writePulse2, writeNoise)
- ✅ Quarter-frame clocking integrated (clockQuarterFrame)
- ✅ 20 comprehensive unit tests (all passing)
- ✅ Zero regressions (652 → 672 total tests)

**Test Results:**
- Start flag reload: ✅ Verified
- Divider countdown: ✅ Verified
- Decay level decrement: ✅ Verified  
- Loop flag behavior: ✅ Verified
- Constant volume mode: ✅ Verified
- Volume output (constant vs decay): ✅ Verified
- Register writes ($4000/$4004/$400C): ✅ Verified
- Quarter-frame clocking: ✅ Verified
- Independent envelope instances: ✅ Verified
- Complete decay cycles (loop/no-loop): ✅ Verified

**Architecture Validation:**
```zig
// ✅ Reusable component - pure state
pub const Envelope = struct {
    start_flag: bool,
    divider: u4,
    decay_level: u4,
    loop_flag: bool,
    constant_volume: bool,
    volume_envelope: u4,
};

// ✅ Pure functional logic
pub fn clock(envelope: *Envelope) void { ... }
pub fn getVolume(envelope: *const Envelope) u4 { ... }

// ✅ Integration with ApuState
pulse1_envelope: Envelope = .{},
pulse2_envelope: Envelope = .{},
noise_envelope: Envelope = .{},

// ✅ Quarter-frame clocking (called at 240 Hz)
Envelope.clock(&state.pulse1_envelope);
Envelope.clock(&state.pulse2_envelope);
Envelope.clock(&state.noise_envelope);
```

**Files:**
- `src/apu/Envelope.zig` (NEW) - Reusable envelope component
- `src/apu/State.zig` - Added 3 envelope instances
- `src/apu/Logic.zig` - Wired envelope control and clocking
- `src/apu/Apu.zig` - Exported Envelope module
- `tests/apu/envelope_test.zig` (NEW) - 20 comprehensive tests
- `build.zig` - Added envelope test suite

**Next:** Milestone 3 - Linear Counter (3-4 hours)

---

## Milestone 3 Completion: Linear Counter (2025-10-06)

**Status:** ✅ **COMPLETE** - Triangle channel linear counter implemented and validated

**Completed Tasks:**
- ✅ Linear counter state fields added to ApuState
- ✅ clockLinearCounter() function implemented (public for testing)
- ✅ Register write handlers updated (writeTriangle $4008/$400B)
- ✅ Quarter-frame clocking integrated (clockQuarterFrame)
- ✅ 15 comprehensive unit tests (all passing)
- ✅ Zero regressions (672 → 687 total tests)

**Test Results:**
- Reload flag triggers reload: ✅ Verified
- Countdown when reload flag clear: ✅ Verified
- Stops at zero: ✅ Verified
- Reload flag cleared when halt clear: ✅ Verified
- Reload flag persists when halt set: ✅ Verified
- Register writes ($4008/$400B): ✅ Verified
- Complete reload/countdown cycles: ✅ Verified
- Halt flag behavior: ✅ Verified
- Independence from envelopes: ✅ Verified
- Quarter-frame integration: ✅ Verified

**Architecture Validation:**
```zig
// ✅ Linear counter state in ApuState
triangle_linear_counter: u7 = 0,
triangle_linear_reload: u7 = 0,
triangle_linear_reload_flag: bool = false,

// ✅ Pure functional logic (public for testing)
pub fn clockLinearCounter(state: *ApuState) void {
    if (state.triangle_linear_reload_flag) {
        state.triangle_linear_counter = state.triangle_linear_reload;
    } else if (state.triangle_linear_counter > 0) {
        state.triangle_linear_counter -= 1;
    }

    if (!state.triangle_halt) {
        state.triangle_linear_reload_flag = false;
    }
}

// ✅ Register write integration
pub fn writeTriangle(state: *ApuState, offset: u2, value: u8) void {
    switch (offset) {
        0 => { // $4008: CRRR RRRR
            state.triangle_halt = (value & 0x80) != 0;
            state.triangle_linear_reload = @intCast(value & 0x7F);
        },
        3 => { // $400B: LLLL Lttt
            state.triangle_linear_reload_flag = true;
        },
        ...
    }
}

// ✅ Quarter-frame clocking (240 Hz)
fn clockQuarterFrame(state: *ApuState) void {
    Envelope.clock(&state.pulse1_envelope);
    Envelope.clock(&state.pulse2_envelope);
    Envelope.clock(&state.noise_envelope);
    clockLinearCounter(state);  // ← NEW
}
```

**Files:**
- `src/apu/State.zig` - Added linear counter state fields (3 fields)
- `src/apu/Logic.zig` - Implemented clockLinearCounter() and register writes
- `tests/apu/linear_counter_test.zig` (NEW) - 15 comprehensive tests
- `build.zig` - Added linear counter test suite

**Key Insights:**
- Direct testing pattern (like Envelope): Tests call `clockLinearCounter()` directly instead of using `tickFrameCounter()` for better reliability
- Quarter-frame intervals are non-uniform (7457, 7456, 7458, 7458 cycles), making direct frame counter testing unreliable
- Made `clockLinearCounter()` public to enable isolated unit testing
- Linear counter is triangle-specific (unlike envelopes which are reusable)

**Next:** Milestone 4 - Sweep Units (4-5 hours)

---

## Milestone 4 Completion: Sweep Units (2025-10-06)

**Status:** ✅ **COMPLETE** - Pulse channel sweep units implemented and validated

**Completed Tasks:**
- ✅ Sweep.zig module created (140 lines) with generic Sweep component
- ✅ Sweep instances added to ApuState (pulse1_sweep, pulse2_sweep)
- ✅ Pulse channel periods added to ApuState (pulse1_period, pulse2_period)
- ✅ Register write handlers updated (writePulse1 $4001-$4003, writePulse2 $4005-$4007)
- ✅ Half-frame clocking integrated (clockHalfFrame)
- ✅ 25 comprehensive unit tests (all passing)
- ✅ Zero regressions (687 → 712 total tests)

**Test Results:**
- Divider countdown and reload: ✅ Verified
- Period modification (increase/decrease): ✅ Verified
- One's complement vs two's complement: ✅ Verified
- Muting conditions (period < 8, target > $7FF): ✅ Verified
- Sweep update conditions: ✅ Verified
- Register writes ($4001/$4005): ✅ Verified
- Period registers ($4002-$4003, $4006-$4007): ✅ Verified
- Complete sweep cycles: ✅ Verified
- Pulse1 vs Pulse2 differences: ✅ Verified

**Architecture Validation:**
```zig
// ✅ Generic Sweep component - reusable for both pulse channels
pub const Sweep = struct {
    enabled: bool = false,
    divider: u3 = 0,
    period: u3 = 0,
    negate: bool = false,
    shift: u3 = 0,
    reload_flag: bool = false,
};

// ✅ Pure functional logic
pub fn clock(sweep: *Sweep, current_period: *u11, ones_complement: bool) void {
    // Calculate target period using u12 to prevent wrapping
    const change_amount: u12 = current_period.* >> sweep.shift;
    const target_period: u12 = if (sweep.negate) ...;

    // Reload divider when divider==0 OR reload_flag
    if (sweep.divider == 0 or sweep.reload_flag) {
        sweep.divider = sweep.period;
        sweep.reload_flag = false;

        // Update period when divider reloads (hardware behavior)
        if (sweep.enabled and sweep.shift != 0 and target_period <= 0x7FF) {
            current_period.* = @intCast(target_period);
        }
    } else {
        sweep.divider -= 1;
    }
}

// ✅ Muting detection
pub fn isMuting(sweep: *const Sweep, current_period: u11, ones_complement: bool) bool {
    if (current_period < 8) return true;
    if (!sweep.negate and target_period > 0x7FF) return true;
    return false;
}

// ✅ Integration with ApuState
pulse1_sweep: Sweep = .{},
pulse2_sweep: Sweep = .{},
pulse1_period: u11 = 0,  // 11-bit timer period
pulse2_period: u11 = 0,

// ✅ Half-frame clocking (120 Hz)
fn clockHalfFrame(state: *ApuState) void {
    clockLengthCounters(state);
    Sweep.clock(&state.pulse1_sweep, &state.pulse1_period, true);   // One's complement
    Sweep.clock(&state.pulse2_sweep, &state.pulse2_period, false);  // Two's complement
}
```

**Files:**
- `src/apu/Sweep.zig` (NEW) - Generic sweep component (140 lines)
- `src/apu/State.zig` - Added sweep instances and pulse periods (4 fields)
- `src/apu/Logic.zig` - Integrated sweep clocking and register writes
- `src/apu/Apu.zig` - Exported Sweep module
- `tests/apu/sweep_test.zig` (NEW) - 25 comprehensive tests (415 lines)
- `build.zig` - Added sweep test suite

**Key Insights:**
- **u12 arithmetic for overflow detection**: Used u12 instead of u11 for target period calculation to properly detect > $7FF without wrapping
- **Hardware timing accuracy**: Period updates only occur when divider reloads (either divider==0 OR reload_flag), matching NES hardware behavior
- **Complement mode differences**: Pulse 1 uses one's complement (-c - 1), Pulse 2 uses two's complement (-c) for period decreases
- **Reusable component pattern**: Sweep follows same pattern as Envelope - generic component with pure functional interface

**Next:** Milestone 5 - Frame IRQ Edge Cases (3-4 hours) OR continue with remaining milestones
