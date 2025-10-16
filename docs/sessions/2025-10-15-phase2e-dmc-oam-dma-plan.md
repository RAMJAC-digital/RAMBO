# Phase 2E: DMC/OAM DMA Interaction - Investigation & Implementation Plan

**Date Created:** 2025-10-15
**Status:** 🔵 **PLANNING** - Ready for next session
**Estimated Time:** 6-8 hours
**Complexity:** HIGH
**Priority:** MEDIUM

---

## Executive Summary

Phase 2E addresses the complex interaction between DMC (Delta Modulation Channel) DMA and OAM (Object Attribute Memory) DMA. When both are active simultaneously, hardware priority rules and byte duplication behavior must be emulated for accurate sprite rendering and audio playback.

**Key Challenge:** DMC DMA can interrupt OAM DMA mid-transfer, causing the OAM byte being read to duplicate. This affects sprite positioning in games that use heavy DMC audio.

---

## Hardware Behavior (nesdev.org)

### DMA Priority Rules

**Priority Order (Highest to Lowest):**
1. **DMC DMA** - Highest priority
2. **OAM DMA** - Medium priority
3. **CPU execution** - Lowest priority

**Reference:** nesdev.org/wiki/APU_DMC

### DMC DMA Characteristics

**Trigger:** DMC channel needs to fetch next audio sample
**Bus Access:** Steals CPU cycles to read sample from memory
**Timing:** Can occur at any time during DMC playback
**Duration:** 4 CPU cycles per sample fetch
**Frequency:** Depends on DMC sample rate (33-428 cycles between fetches)

### OAM DMA Characteristics

**Trigger:** Write to $4014 register
**Bus Access:** Transfers 256 bytes from CPU memory to OAM
**Timing:** Takes 513 or 514 CPU cycles (alignment dependent)
**Pattern:** Read cycle, write cycle, repeat 256 times
**Blocking:** Halts CPU execution during transfer

### Conflict Behavior

**When DMC Interrupts OAM:**
1. OAM DMA **pauses** mid-transfer (does not cancel)
2. DMC DMA executes (4 cycles)
3. OAM DMA **resumes** from where it left off
4. **Critical:** OAM read during DMC interruption duplicates previous byte

**Example Timeline:**
```
Cycle 0: OAM reads byte 0 from $0200
Cycle 1: OAM writes byte 0 to OAM[0]
Cycle 2: OAM reads byte 1 from $0201
Cycle 3: DMC INTERRUPT! OAM pauses
Cycle 4-7: DMC reads sample from $C000
Cycle 8: OAM resumes - reads byte 1 AGAIN (should read byte 2!)
Cycle 9: OAM writes duplicated byte 1 to OAM[1]
Cycle 10: OAM reads byte 2 from $0202 (skipped byte 2!)
Cycle 11: OAM writes byte 2 to OAM[2]
```

**Result:** Sprite data corruption - OAM[1] has duplicate of byte 1, byte 2 lost

---

## Current Implementation Analysis

### OAM DMA State Machine

**Location:** `src/emulation/State.zig`

**Current Structure (Needs Investigation):**
```zig
pub const OamDma = struct {
    active: bool,
    page: u8,
    offset: u8,
    cycles_remaining: u16,
    alignment_cycle: bool,
};
```

**Current Logic (Needs Investigation):**
- Check if OAM DMA can be interrupted
- Check if DMC DMA can interrupt it
- Verify byte duplication is NOT currently implemented

### DMC DMA State Machine

**Location:** `src/apu/Dmc.zig` (likely)

**Current Structure (Needs Investigation):**
```zig
// DMC channel should have:
// - sample_address: Current read address
// - bytes_remaining: Sample length counter
// - rdy_low: DMA request flag
```

**Current Priority Logic (Needs Investigation):**
- Where is DMA priority checked?
- Does DMC correctly preempt OAM?
- Is there already a pause mechanism?

---

## Investigation Steps

### Step 1: Map Current DMA Implementation (30 minutes)

**Files to Examine:**
1. `src/emulation/State.zig` - OAM DMA state
2. `src/cpu/Logic.zig` or `src/emulation/State.zig` - DMA tick logic
3. `src/apu/Dmc.zig` - DMC sample fetch logic
4. `src/apu/State.zig` - DMC state structure

**Questions to Answer:**
- Where does OAM DMA execute? (Which function?)
- Where does DMC DMA execute? (Which function?)
- What is the call order? (DMC before OAM? Or vice versa?)
- Is there existing pause/resume logic?
- How are CPU cycles deducted during DMA?

**Investigation Commands:**
```bash
# Find OAM DMA tick logic
grep -n "tickDma\|oam_dma\|OamDma" src/emulation/*.zig src/cpu/*.zig

# Find DMC DMA logic
grep -n "dmc_dma\|DmcDma\|rdy_low" src/apu/*.zig src/emulation/*.zig

# Find DMA priority checks
grep -n "dmc.*oam\|oam.*dmc" src/**/*.zig
```

### Step 2: Hardware Research (1 hour)

**Primary Sources:**
- nesdev.org/wiki/APU_DMC (DMC behavior)
- nesdev.org/wiki/PPU_OAM (OAM DMA behavior)
- nesdev.org/wiki/DMA (General DMA timing)
- nesdev forums: Search "DMC OAM conflict" or "DMA priority"

**Research Questions:**
1. Exact cycle count for DMC DMA (4 cycles confirmed?)
2. Exact OAM DMA cycle pattern (read-write-read-write?)
3. At which point in OAM cycle can DMC interrupt? (Read? Write? Either?)
4. How many bytes can be duplicated? (Just 1? Multiple?)
5. Real hardware test results (any homebrew tests available?)

**Document Findings:**
- Create `docs/hardware/dmc-oam-dma-conflict.md`
- Include cycle-by-cycle timing diagrams
- Note any ambiguities or edge cases

### Step 3: Test Strategy (1 hour)

**Test Categories:**

**A. Unit Tests (Simple Cases)**
1. DMC DMA alone (no conflict)
2. OAM DMA alone (no conflict)
3. DMC interrupts OAM at start of transfer
4. DMC interrupts OAM mid-transfer (byte 128)
5. DMC interrupts OAM at end of transfer (byte 255)

**B. Integration Tests (Complex Cases)**
1. Multiple DMC interruptions during single OAM transfer
2. DMC interrupts during alignment cycle
3. Back-to-back OAM DMAs with DMC active
4. Verify correct byte duplication pattern

**C. Timing Tests**
1. Verify total cycle count (513/514 + DMC interrupts)
2. Verify CPU halts during both DMAs
3. Verify DMC priority over OAM

**Test Infrastructure Needed:**
- Test harness for precise cycle control
- OAM inspection helpers
- DMC state inspection helpers
- Cycle counting verification

---

## Implementation Approach

### Option A: Minimal State Machine (Recommended)

**Add to OamDma:**
```zig
pub const OamDma = struct {
    active: bool,
    paused: bool,          // NEW - DMC has control
    page: u8,
    offset: u8,
    cycles_remaining: u16,
    alignment_cycle: bool,
    last_read_byte: u8,    // NEW - for duplication on resume
};
```

**Logic:**
```zig
// In CPU tick or emulation tick:
if (dmc_dma.rdy_low) {
    // DMC has priority - pause OAM if active
    if (oam_dma.active and !oam_dma.paused) {
        oam_dma.paused = true;
        // last_read_byte already set from previous OAM read
    }
    tickDmcDma();
    return;
}

if (oam_dma.active) {
    if (oam_dma.paused) {
        // Resume OAM - duplicate last byte
        writeOam(oam_dma.offset, oam_dma.last_read_byte);
        oam_dma.offset += 1;
        oam_dma.paused = false;
    }
    tickOamDma();
    return;
}
```

### Option B: Explicit Interrupt State Machine

**More Complex - Only if Option A insufficient:**
```zig
pub const DmaState = enum {
    idle,
    oam_reading,
    oam_writing,
    oam_paused_by_dmc,
    dmc_reading,
};

pub const DmaController = struct {
    state: DmaState,
    oam: OamDma,
    dmc: DmcDma,
};
```

**Recommendation:** Start with Option A. Add Option B only if edge cases require it.

---

## Implementation Steps

### Phase 1: Investigation & Documentation (2-3 hours)

1. **Map Current Implementation** (30 min)
   - Document current OAM DMA logic
   - Document current DMC DMA logic
   - Create call graph diagram

2. **Hardware Research** (1 hour)
   - Read all nesdev.org DMA documentation
   - Search forums for test results
   - Document findings in `docs/hardware/`

3. **Design Review** (30-60 min)
   - Choose implementation approach (Option A vs B)
   - Identify state changes needed
   - Plan backward compatibility

### Phase 2: Core Implementation (2-3 hours)

1. **Add Pause State** (30 min)
   - Add `paused` flag to OamDma
   - Add `last_read_byte` tracking
   - Update state initialization

2. **Implement Priority Logic** (1 hour)
   - Refactor DMA tick order
   - Add pause on DMC interrupt
   - Add resume with duplication

3. **Verify Compilation** (15 min)
   - Build and fix type errors
   - Run existing tests (should still pass)

### Phase 3: Testing & Validation (2-3 hours)

1. **Create Test Suite** (1-1.5 hours)
   - Unit tests for simple cases
   - Integration tests for conflicts
   - Timing verification tests

2. **Debug & Refine** (1-1.5 hours)
   - Fix test failures
   - Verify cycle counts
   - Check for edge cases

3. **Commercial ROM Testing** (30 min)
   - Test audio-heavy games (Battletoads, Mega Man, Castlevania)
   - Listen for audio quality improvements
   - Check for sprite corruption fixes

---

## Files Expected to Modify

**Core Implementation:**
1. `src/emulation/State.zig` - OamDma structure + pause logic
2. `src/cpu/Logic.zig` OR `src/emulation/State.zig` - DMA priority
3. `src/apu/Dmc.zig` - DMC DMA request handling

**Testing:**
4. `tests/integration/dmc_oam_conflict_test.zig` - **NEW**
5. `build/tests.zig` - Register new tests

**Documentation:**
6. `docs/hardware/dmc-oam-dma-conflict.md` - **NEW**
7. `docs/sessions/2025-10-15-phase2e-completion.md` - **NEW** (after impl)

---

## Risk Assessment

### High Risk Areas

**1. Cycle Timing Precision**
- **Risk:** Off-by-one errors in cycle counting
- **Mitigation:** Comprehensive timing tests, cycle-by-cycle verification
- **Impact:** Audio glitches, sprite positioning errors

**2. State Machine Complexity**
- **Risk:** Pause/resume logic has subtle bugs
- **Mitigation:** Start simple (Option A), add complexity only if needed
- **Impact:** OAM corruption, crashes

**3. Regression in Existing Games**
- **Risk:** Changes break currently working games
- **Mitigation:** Run full test suite before/after, commercial ROM testing
- **Impact:** Loss of compatibility

### Medium Risk Areas

**4. DMC Sample Rate Edge Cases**
- **Risk:** Very fast/slow DMC rates have unexpected behavior
- **Mitigation:** Test multiple sample rates (33-428 cycle range)
- **Impact:** Rare audio glitches

**5. Multiple Interruptions**
- **Risk:** Multiple DMC interrupts during one OAM transfer
- **Mitigation:** Integration test with continuous DMC playback
- **Impact:** Cumulative sprite corruption

---

## Success Criteria

### Must Have (P0)
- ✅ DMC DMA can interrupt OAM DMA
- ✅ OAM DMA pauses during DMC interrupt
- ✅ OAM DMA resumes after DMC completes
- ✅ Byte duplication occurs on resume
- ✅ All existing tests still pass
- ✅ New test suite passes (6+ tests)

### Should Have (P1)
- ✅ Accurate cycle timing (513/514 + DMC cycles)
- ✅ Multiple DMC interruptions handled correctly
- ✅ No audio quality regression in existing games
- ✅ Sprite positioning improved in audio-heavy games

### Nice to Have (P2)
- ✅ Detailed timing documentation
- ✅ Visual test ROM (if available)
- ✅ Performance benchmarking (should be negligible impact)

---

## Open Questions (To Resolve During Investigation)

1. **Q:** Can DMC interrupt during OAM alignment cycle?
   **A:** TBD - Research needed

2. **Q:** What happens if second DMC interrupt occurs while still paused?
   **A:** TBD - Likely extends pause, test needed

3. **Q:** Does byte duplication affect OAM address or just written value?
   **A:** TBD - Need cycle-by-cycle analysis

4. **Q:** Are there any games that visibly rely on this behavior?
   **A:** TBD - Commercial ROM testing will reveal

5. **Q:** Does RAMBO's APU already implement DMC DMA?
   **A:** TBD - Investigation Step 1 will answer

---

## Reference Materials

### Essential Reading
1. nesdev.org/wiki/APU_DMC
2. nesdev.org/wiki/PPU_OAM#DMA
3. nesdev.org/wiki/DMA

### Community Resources
4. nesdev forums: "DMC DMA timing"
5. nesdev forums: "OAM corruption"
6. blargg's NES tests (if available)

### Code References
7. FCEUX source code (DMA implementation)
8. Mesen source code (known accurate emulator)

---

## Estimated Timeline

**Session 1: Investigation (2-3 hours)**
- Current implementation mapping: 30 min
- Hardware research: 1 hour
- Design decisions: 30-60 min

**Session 2: Core Implementation (2-3 hours)**
- State structure changes: 30 min
- Priority logic refactor: 1 hour
- Compilation + smoke testing: 30-60 min

**Session 3: Testing & Polish (2-3 hours)**
- Test suite creation: 1-1.5 hours
- Debug & refinement: 1-1.5 hours
- Commercial ROM verification: 30 min

**Total: 6-9 hours** (within 6-8 hour estimate, accounting for unknowns)

---

## Next Session Checklist

**Before Starting:**
- [ ] Read this entire plan
- [ ] Have nesdev.org/wiki open
- [ ] Fresh terminal session
- [ ] Git status clean (current work committed)

**Investigation Phase:**
- [ ] Run grep commands to find DMA logic
- [ ] Read and document current OAM DMA implementation
- [ ] Read and document current DMC DMA implementation
- [ ] Create call graph or state diagram
- [ ] Research hardware behavior on nesdev.org
- [ ] Make design decision (Option A vs B)

**Implementation Phase:**
- [ ] Create feature branch (optional)
- [ ] Add pause/resume state to OamDma
- [ ] Refactor DMA priority logic
- [ ] Add byte duplication on resume
- [ ] Compile and fix errors
- [ ] Run existing test suite (verify no regressions)

**Testing Phase:**
- [ ] Create `tests/integration/dmc_oam_conflict_test.zig`
- [ ] Write 6+ test cases
- [ ] Verify all tests pass
- [ ] Test with commercial ROMs
- [ ] Document findings

**Completion:**
- [ ] Write completion report
- [ ] Update CLAUDE.md if needed
- [ ] Commit with detailed message
- [ ] Mark Phase 2 as COMPLETE 🎉

---

## Fallback Plan

**If Implementation Proves Too Complex:**

1. **Defer to Phase 3:**
   - Document what was learned
   - Mark as "requires more research"
   - Move to lower priority

2. **Partial Implementation:**
   - Implement DMC priority only (no byte duplication)
   - Document known limitation
   - Revisit when edge cases found in games

3. **Consult Reference Implementations:**
   - Study Mesen source code
   - Reach out to nesdev community
   - Consider pair programming session

---

## Conclusion

Phase 2E is the most complex phase of Phase 2, involving precise timing interaction between three subsystems (CPU, PPU, APU). This plan provides a structured approach to investigation, implementation, and testing.

**Key Success Factors:**
- Start with investigation, not implementation
- Choose simplest design that works (Option A)
- Test extensively before declaring complete
- Don't be afraid to defer if too complex

**Status:** 🔵 **READY FOR NEXT SESSION**

Good luck! 🚀
