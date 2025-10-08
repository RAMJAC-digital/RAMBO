# APU Implementation - Decision Required

**Date:** 2025-10-06
**Status:** Comprehensive plan ready, awaiting user approval

---

## Current State

**Implemented (Phase 1.5):**
- ✅ Length counters (all 4 channels, 32-value table)
- ✅ Frame counter timing (4-step/5-step modes)
- ✅ DMC DMA mechanics (bus stalls, priority)
- ✅ Register routing ($4000-$4017)

**Test Results:** 32/95 APU tests expected to pass (34%)

---

## Missing for Full AccuracyCoin Passage

### Phase 2: Core Features (10-12 hours)
1. **DMC Timer & Playback** (6-8h) - 15 tests
2. **Frame IRQ Edge Cases** (3-4h) - 4 tests

**Expected Result:** 60-70/95 tests passing (63-74%)

### Phase 3: Audio Features (11-14 hours)
3. **Envelopes** (4-5h) - 6 tests
4. **Linear Counter** (3-4h) - 3 tests
5. **Sweep Units** (4-5h) - 3 tests

**Expected Result:** 75-85/95 tests passing (79-89%)

### Phase 4: Polish (2-3 hours)
6. **APU Register Open Bus** (2-3h) - 5 tests

**Expected Result:** 80-90/95 tests passing (84-95%)

**Total Time:** 23-29 hours (3-4 days)

---

## Three Implementation Options

### Option A: Aggressive DMC Focus ⭐ RECOMMENDED
**Time:** 10-12 hours (1.5 days)
**Goal:** Maximum test passage quickly

**Implements:**
1. DMC Timer & Playback
2. Frame IRQ Edge Cases

**Result:** 60-70 tests passing

**Pros:**
- Fastest path to significant improvement
- Validates complex timing logic
- Highest test ROI
- Quick feedback loop

**Cons:**
- Audio features (envelopes, sweeps) deferred
- May need Phase 3 later for 80%+ passage

---

### Option B: Comprehensive Full Audio
**Time:** 23-29 hours (3-4 days)
**Goal:** Complete APU implementation

**Implements:** Everything (DMC, IRQ, Envelopes, Linear, Sweeps, Open Bus)

**Result:** 80-90 tests passing

**Pros:**
- Complete implementation
- Future-proof
- All audio features working

**Cons:**
- Takes 3-4 full days
- Some features have low test coverage

---

### Option C: Balanced Core + Critical Audio
**Time:** 14-17 hours (2 days)
**Goal:** Best coverage/time ratio

**Implements:**
1. DMC Timer & Playback
2. Frame IRQ Edge Cases
3. Envelopes

**Result:** 70-80 tests passing

**Pros:**
- Good balance
- Covers most-tested features
- Reasonable time investment

**Cons:**
- Linear counter and sweeps still missing
- May need additional work later

---

## Recommended Approach: Option A

**Why:**
1. Fastest validation of complex DMC logic
2. Establishes baseline for incremental improvement
3. Can add audio features afterward based on results
4. 10-12 hour investment is reasonable
5. Provides clear go/no-go decision point

**Process:**
1. Implement DMC timer & playback (6-8h)
2. Add IRQ edge case handling (3-4h)
3. **Run AccuracyCoin** - analyze results
4. **Decision Point:** Continue to Phase 3 based on results

---

## Critical Questions

### Implementation Complexity

**Q: Is DMC playback well-documented enough?**
**A:** Yes - nesdev.org has complete specifications including:
- Timer countdown logic
- Output unit state machine
- Sample buffer management
- Shift register behavior
- IRQ and looping mechanics

**Risk:** MEDIUM - Complex multi-state-machine, but well-specified

---

### Timing Accuracy

**Q: Are our frame counter cycle counts correct?**
**A:** Yes - Cross-referenced with:
- NESDev wiki: "3728.5 APU cycles = 7457 CPU cycles"
- Multiple emulator sources
- AccuracyCoin test expectations

**Our values:** 7457, 14913, 22371, 29829 ✅

**Risk:** LOW - Highly confident in timing values

---

### IRQ Edge Cases

**Q: Can we determine IRQ re-set behavior without hardware?**
**A:** Yes - Using AccuracyCoin test-driven approach:
1. Implement V1 (simple flag set)
2. Run tests E-H
3. Analyze exact error messages
4. Adjust logic based on failures
5. Iterate until tests pass

**Risk:** MEDIUM - May require 2-3 iterations

---

### Audio Output Priority

**Q: Do we need actual waveform generation?**
**A:** NO - AccuracyCoin tests timing and logic, not audio output
- Envelopes: Need decay counter logic, not actual volume mixing
- Sweeps: Need target period calculation, not frequency generation
- Triangle: Need linear counter logic, not waveform

**We can defer actual audio DAC output until video display is working**

---

## Decision Required

### 1. Choose Implementation Option
- [ ] **Option A:** Aggressive DMC Focus (10-12h) ⭐ RECOMMENDED
- [ ] **Option B:** Comprehensive Full Audio (23-29h)
- [ ] **Option C:** Balanced Core + Critical Audio (14-17h)

### 2. Audio Output Scope
- [ ] **Timing/Logic Only** - Defer waveform generation ⭐ RECOMMENDED
- [ ] **Full Audio** - Implement waveform mixing and DAC output

### 3. Testing Strategy
- [ ] **Test-Driven** - Implement → Test → Refine ⭐ RECOMMENDED
- [ ] **Spec-Driven** - Perfect implementation before testing

### 4. Risk Tolerance
- [ ] **Aggressive** - Accept 2-3 iterations for edge cases ⭐ RECOMMENDED
- [ ] **Conservative** - Research all edge cases upfront

---

## Proposed Next Steps (Option A)

### Day 1 (6-8 hours): DMC Implementation
1. Add DMC state fields (bits_remaining, silence_flag, etc.)
2. Implement `tickDmc()` - timer countdown
3. Implement `clockDmcOutput()` - output unit state machine
4. Update `loadSampleByte()` - IRQ and looping logic
5. Write 15-20 unit tests for DMC behavior
6. Verify zero regressions (all 627 tests still pass)

### Day 2 (3-4 hours): IRQ Edge Cases + Testing
1. Implement IRQ re-set at cycles 29829-29831
2. Write unit tests for edge cases
3. **Run AccuracyCoin** - extract results
4. Analyze test passages (expect 60-70/95)
5. Document findings

### Day 3 (Optional): Refinement
1. Address any DMC timing issues found
2. Refine IRQ edge cases based on test results
3. **Re-run AccuracyCoin** - verify improvements
4. **Decision Point:** Continue to Phase 3 or declare victory

---

## Success Criteria

### Minimum (Phase 2 Complete):
- ✅ DMC timer ticking correctly
- ✅ DMC output unit state machine working
- ✅ DMC IRQ and looping functional
- ✅ IRQ flag re-set behavior correct
- ✅ 60+ APU tests passing (63%+)
- ✅ Zero regressions on existing 627 tests

### Stretch (Phase 3 Complete):
- ✅ Envelopes implemented
- ✅ Linear counter implemented
- ✅ Sweep units implemented
- ✅ 80+ APU tests passing (84%+)

---

## Open Questions for User

1. **Which option?** A (aggressive), B (comprehensive), or C (balanced)?

2. **Audio output?** Defer waveform generation or implement now?

3. **Time budget?** Is 10-12 hours (Option A) acceptable? Or prefer full 23-29 hours (Option B)?

4. **Additional validation?** Should we run nestest.nes or other test ROMs alongside AccuracyCoin?

5. **Any concerns?** With the implementation approach, complexity, or timeline?

---

**Ready to begin implementation upon approval.**

**Recommendation:** Option A (Aggressive DMC Focus) with test-driven refinement approach.
