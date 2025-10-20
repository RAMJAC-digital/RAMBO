# VBlank/NMI Bug Remediation Plan
**Date:** 2025-10-19
**Status:** Investigation Complete - Ready for Implementation
**Goal:** Fix VBlank/NMI behavior to pass all 10 AccuracyCoin accuracy tests

---

## Executive Summary

After comprehensive analysis using specialized agents and reviewing all session documents, we have identified the root causes of the VBlank/NMI test failures. The current code shows evidence of **partial fixes** that were implemented but incomplete or reverted.

**Current Test Status:**
- 9 tests FAILING with documented error codes
- 1 test (unofficial instructions) passes with unexpected code 0x00
- All tests expect FAIL codes (documenting broken behavior per ROM screenshot)

**Key Finding:** The code has been partially fixed since VBLANK-BUGS-QUICK-REFERENCE.txt was written. Many bugs listed in that document no longer exist in the current codebase, suggesting fixes were attempted but either incomplete or caused regressions that led to partial reversion.

---

## Current Code State Analysis

### What's Already Fixed ✅

**1. VBlankLedger.isFlagVisible() - CORRECTED**
- Current implementation (VBlankLedger.zig:35-45):
  ```zig
  pub inline fn isFlagVisible(self: VBlankLedger) bool {
      if (!self.isActive()) return false;
      if (self.last_read_cycle >= last_set_cycle) return false;
      return true;
  }
  ```
- **Correct behavior:** Flag becomes invisible once read (read_cycle >= set_cycle)
- **No longer uses hasRace()** - race handling is separate

**2. NMI Line Assertion - CORRECTED**
- Current implementation (execution.zig:107):
  ```zig
  const nmi_line_should_assert = vblank_flag_visible and state.ppu.ctrl.nmi_enable;
  ```
- **Correct behavior:** No inverted race logic
- **Does not check hasRaceSuppression()** - may need to add this back

**3. Race State Preservation - CORRECTED**
- Current implementation (State.zig:658-660):
  ```zig
  if (result.nmi_signal) {
      self.vblank_ledger.last_set_cycle = self.clock.ppu_cycles;
      // DO NOT clear last_race_cycle here - preserve race state across VBlank period
  }
  ```
- **Correct behavior:** Race state NOT cleared on VBlank SET
- **Comment shows intentional fix**

**4. Race State Clearing - CORRECT**
- Current implementation (State.zig:662-666):
  ```zig
  if (result.vblank_clear) {
      self.vblank_ledger.last_clear_cycle = self.clock.ppu_cycles;
      self.vblank_ledger.last_race_cycle = 0;  // Clear race state at VBlank end
  }
  ```
- **Correct behavior:** Race state cleared at VBlank end only

### What Needs Investigation 🔍

**1. Race Condition Semantics - UNCLEAR**

The current implementation has `hasRaceSuppression()` that returns true when a race occurs, but:
- It's **not used** in NMI line assertion (execution.zig:107)
- It's **not used** in isFlagVisible() (VBlankLedger.zig:35-45)

**Question:** Should race conditions suppress NMI generation?

**Hardware Behavior (from NESDev):**
- Reading $2002 on the EXACT cycle VBlank is set (scanline 241, dot 1):
  - The read returns 0 (flag not yet visible)
  - The flag is still SET (not cleared by the read)
  - **NMI is SUPPRESSED** (this is the critical race behavior)

**Current Code Analysis:**
- Race detection: State.zig:294 checks `if (now == last_set)`
- Sets `last_race_cycle = last_set` when race detected
- But `hasRaceSuppression()` is never checked in NMI logic!

**This is the bug!** NMI should be suppressed when `hasRaceSuppression()` returns true.

**2. $2002 Read Path - NEEDS AUDIT**

Current path (State.zig:350-355):
```zig
if (ppu_read_result) |result| {
    if (result.read_2002) {
        const now = self.clock.ppu_cycles;
        self.vblank_ledger.last_read_cycle = now;
    }
}
```

**Potential Issues:**
- Are ALL $2002 reads setting `result.read_2002 = true`?
- Do RMW dummy writes bypass this path?
- Do all addressing modes properly signal $2002 reads?

**Need to verify:** Every code path that reads $2002 updates the ledger

**3. Test Setup Method - HYBRID APPROACH NEEDED**

Current test setup (from accuracy tests):
```zig
h.seekToScanlineDot(241, 1);  // Position at VBlank start
h.state.cpu.pc = 0xB4D5;      // Jump to test entry point
h.state.bus.ram[0x0452] = 0x80; // RUNNING marker
```

**Agent Analysis Shows:**
- ✅ Positioning is correct (VBlank set at 241, 1)
- ✅ VBlankLedger properly initialized
- ❌ May skip NMI handler initialization
- ❌ CPU starts 3 cycles after seek (not a bug, but noted)

**ACCURACYCOIN-ANALYSIS.md suggests:**
- Boot from reset to initialize NMI handlers
- Then jump to test entry point
- This hybrid approach may be needed

But VBLANK-BUGS-QUICK-REFERENCE.txt says the bugs are in the EMULATOR, not the test setup!

**4. Race Detection Window - EXACT CYCLE ONLY**

Current implementation (State.zig:294):
```zig
if (last_set > last_clear and now == last_set) {
    self.vblank_ledger.last_race_cycle = last_set;
}
```

**Hardware behavior:** Race only occurs on EXACT same cycle (now == last_set)

**VBLANK-BUGS-QUICK-REFERENCE claimed:** Window should be `delta <= 2 cycles`

**Current implementation:** Checks exact cycle only (now == last_set)

**Which is correct?** Need to verify against hardware documentation.

---

## Root Cause Hypothesis

Based on all evidence, the most likely root cause is:

### **BUG: Race Suppression Not Applied to NMI Generation**

**The Problem:**
1. Race conditions are detected correctly (State.zig:294)
2. Race state is preserved correctly (State.zig:658-660)
3. `hasRaceSuppression()` method exists (VBlankLedger.zig:51-53)
4. **But NMI generation doesn't check for race suppression!** (execution.zig:107)

**Expected behavior:**
```zig
const vblank_flag_visible = state.vblank_ledger.isFlagVisible();
const race_suppression = state.vblank_ledger.hasRaceSuppression();
const nmi_line_should_assert = vblank_flag_visible and
                                 state.ppu.ctrl.nmi_enable and
                                 !race_suppression;  // ← MISSING!
```

**Current behavior:**
```zig
const vblank_flag_visible = state.vblank_ledger.isFlagVisible();
const nmi_line_should_assert = vblank_flag_visible and state.ppu.ctrl.nmi_enable;
```

**Why this causes test failures:**

Example test scenario (VBlank Beginning Test):
1. Test seeks to scanline 241, dot 1 (VBlank SET moment)
2. Test CPU reads $2002 on same cycle as VBlank SET (race condition)
3. Race detected, `last_race_cycle = last_set_cycle`
4. **Expected:** NMI suppressed, test passes
5. **Actual:** NMI fires anyway (race suppression not checked), test fails

---

## Detailed Test Failure Analysis

### Test 1: VBlank Beginning (FAIL 1)
- **Expected:** 0x00 (PASS)
- **Actual:** 0x01 (FAIL 1)
- **Likely Cause:** Race condition at scanline 241, dot 1 not suppressing NMI
- **Fix:** Add race suppression check to NMI line assertion

### Test 2: VBlank End (FAIL 1)
- **Expected:** 0x00 (PASS)
- **Actual:** 0x01 (FAIL 1)
- **Likely Cause:** VBlank clear timing or flag visibility issue
- **Fix:** Verify VBlank clear happens at scanline 261, dot 1

### Test 3: NMI Control (FAIL 7)
- **Expected:** 0x00 (PASS) - 8 subtests all pass
- **Actual:** 0x07 (FAIL 7) - 7 out of 8 subtests fail
- **Likely Cause:** Multiple issues with NMI enable/disable edge cases
- **Critical Subtests:**
  - Subtest 5: NMI shouldn't trigger twice when writing $80 to $2000 when already enabled
  - Subtest 6: Similar to 5 but NMI enabled going into VBlank
- **Fix:** Review NMI edge trigger logic and double-trigger suppression

### Test 4: NMI Timing (FAIL 1)
- **Expected:** 0x00 (PASS)
- **Actual:** 0x01 (FAIL 1)
- **Likely Cause:** NMI delay incorrect (should occur 2 instructions after PPUCTRL write)
- **Fix:** Verify NMI edge detection timing

### Test 5: NMI Suppression (FAIL 1)
- **Expected:** 0x00 (PASS)
- **Actual:** 0x01 (FAIL 1)
- **Likely Cause:** Race suppression not working
- **Fix:** Add race suppression to NMI logic

### Test 6: NMI at VBlank End (FAIL 1)
- **Expected:** 0x00 (PASS)
- **Actual:** 0x01 (FAIL 1)
- **Likely Cause:** VBlank clear timing or NMI behavior at boundary
- **Fix:** Verify timing of VBlank clear and NMI generation

### Test 7: NMI Disabled at VBlank (FAIL 1)
- **Expected:** 0x00 (PASS)
- **Actual:** 0x01 (FAIL 1)
- **Likely Cause:** NMI shouldn't fire when disabled, but does
- **Fix:** Verify NMI enable check in line assertion

### Test 8: All NOP Instructions (FAIL 1)
- **Expected:** 0x00 (PASS)
- **Actual:** 0x00 (PASS) ✅
- **Status:** Already passing
- **Note:** This test doesn't use VBlank/NMI, so it passes

### Test 9: Unofficial Instructions (FAIL A)
- **Expected:** 0x00 (PASS)
- **Actual:** 0x00 (PASS) ✅
- **Status:** Already passing
- **Note:** This test doesn't use VBlank/NMI, so it passes

---

## Remediation Plan

### Phase 1: Add Race Suppression to NMI Logic (CRITICAL)

**File:** `src/emulation/cpu/execution.zig`
**Line:** 106-109
**Change:**
```zig
// Current:
const vblank_flag_visible = state.vblank_ledger.isFlagVisible();
const nmi_line_should_assert = vblank_flag_visible and state.ppu.ctrl.nmi_enable;

// Fixed:
const vblank_flag_visible = state.vblank_ledger.isFlagVisible();
const race_suppression = state.vblank_ledger.hasRaceSuppression();
const nmi_line_should_assert = vblank_flag_visible and
                                 state.ppu.ctrl.nmi_enable and
                                 !race_suppression;
```

**Rationale:** Hardware suppresses NMI when $2002 is read on the exact cycle VBlank is set. Our ledger already tracks this via `hasRaceSuppression()`, but NMI generation doesn't check it.

**Expected Impact:**
- VBlank Beginning test: FAIL 1 → PASS
- NMI Suppression test: FAIL 1 → PASS
- Possibly others that involve race conditions

### Phase 2: Verify $2002 Read Path (HIGH PRIORITY)

**Action Items:**
1. Add debug logging to State.zig:353 to log every `last_read_cycle` update
2. Run failing tests and verify last_read_cycle updates on EVERY $2002 read
3. If reads are missed, audit busRead() path for edge cases

**Files to Review:**
- `src/emulation/State.zig` (busRead function)
- `src/ppu/logic/registers.zig` (readRegister function)
- `src/cpu/opcodes/*.zig` (RMW instructions, addressing modes)

**Test Approach:**
```zig
// Add to State.zig:353
if (result.read_2002) {
    const now = self.clock.ppu_cycles;
    std.debug.print("[VBlank] $2002 read at cycle {}, updating last_read_cycle\n", .{now});
    self.vblank_ledger.last_read_cycle = now;
}
```

### Phase 3: Verify Double-Trigger Suppression (HIGH PRIORITY)

**Current Code:** execution.zig:111-117
```zig
const vblank_active = state.vblank_ledger.isActive();
const current_vblank_set_cycle = if (vblank_active)
    state.vblank_ledger.last_set_cycle
else
    0;

// Later passed to checkInterrupts()
```

**Need to verify:**
- Does `checkInterrupts()` use `current_vblank_set_cycle` correctly?
- Does it prevent multiple NMIs during the same VBlank span?
- Is this working for NMI re-enable scenarios (NMI Control Test subtests 5 & 6)?

**Action:** Review CPU interrupt logic implementation

### Phase 4: Review Race Detection Window (MEDIUM PRIORITY)

**Current:** Checks exact cycle match (`now == last_set`)
**VBLANK-BUGS-QUICK-REFERENCE claimed:** Should check `delta <= 2 cycles`

**Action:**
1. Research hardware documentation (NESDev wiki)
2. Determine correct race window
3. Update if needed

**Current code (State.zig:294):**
```zig
if (last_set > last_clear and now == last_set) {
    self.vblank_ledger.last_race_cycle = last_set;
}
```

**If window should be 2 cycles:**
```zig
if (last_set > last_clear) {
    const delta = if (now >= last_set) now - last_set else 0;
    if (delta <= 2) {
        self.vblank_ledger.last_race_cycle = last_set;
    }
}
```

### Phase 5: Run Full Test Suite (REQUIRED)

**After each fix:**
1. Run accuracy tests: `zig build test -- accuracy`
2. Run full suite: `zig build test --summary all`
3. Check for regressions in:
   - cpu_ppu_integration_test
   - commercial_rom_test
   - mmc3_visual_regression_test
4. Document any regressions and analyze root cause

**Regression Protocol:**
- If regression occurs, analyze WHY
- Determine if regression reveals another bug or if fix was incorrect
- Do NOT blindly revert - understand the interaction

### Phase 6: Update Test Expectations (FINAL STEP)

**Only after all tests pass:**

Update all accuracy test files to expect 0x00 (PASS):
- vblank_beginning_test.zig: 0x01 → 0x00
- vblank_end_test.zig: 0x01 → 0x00
- nmi_control_test.zig: 0x07 → 0x00
- nmi_timing_test.zig: 0x01 → 0x00
- nmi_suppression_test.zig: 0x01 → 0x00
- nmi_vblank_end_test.zig: 0x01 → 0x00
- nmi_disabled_vblank_test.zig: 0x01 → 0x00

---

## Success Criteria

### Primary Goals
- [ ] All 10 AccuracyCoin accuracy tests return 0x00 (PASS)
- [ ] No regressions in existing test suite (990+ tests still passing)
- [ ] Commercial ROMs still work (Castlevania, Mega Man, Kid Icarus, etc.)

### Verification Steps
1. Run `zig build test -- accuracy` - all pass
2. Run `zig build test-integration` - no new failures
3. Run `zig build test` - maintain 990+/995 passing
4. Manual test: Load AccuracyCoin.nes in GUI, verify all tests show PASS on screen
5. Manual test: Load and play commercial ROMs, verify no regressions

---

## Risk Assessment

### Low Risk Changes
- Adding race suppression check to NMI logic (straightforward boolean)
- Updating test expectations (documentation only)

### Medium Risk Changes
- Modifying race detection window (affects timing-sensitive behavior)
- Changes to double-trigger suppression (affects NMI re-enable)

### High Risk Changes
- Modifying isFlagVisible() logic (affects all $2002 reads)
- Changing VBlank SET/CLEAR timing (affects PPU timing)

### Mitigation Strategy
- Make changes incrementally (one fix at a time)
- Run full test suite after each change
- Keep detailed notes on what changed and why
- Use git commits at each milestone for easy reversion

---

## Open Questions

### Question 1: Hardware Race Window
**Q:** Is the race window exactly 1 cycle or up to 2-3 cycles?
**Research:** Check NESDev wiki VBlank timing article
**Impact:** Affects race detection logic

### Question 2: Double-Trigger Suppression
**Q:** How does NMI Control Test subtest 5 & 6 expect NMI to behave when:
- NMI already enabled
- VBlank flag already read (invisible)
- PPUCTRL written with $80 (NMI enable, but already enabled)
**Expected:** No NMI should fire (flag already cleared)
**Impact:** May need additional tracking

### Question 3: Test Setup Method
**Q:** Should tests boot from reset then jump to entry points (hybrid)?
**Current:** Jump directly to entry points at scanline 241, dot 1
**Alternative:** Boot from reset, wait for init, then jump
**Impact:** Test reliability and coverage

---

## Documentation Requirements

### Session Notes
Create final session document: `2025-10-19-VBLANK-FIX-SESSION.md`
- All fixes applied
- Test results before/after
- Any regressions and their resolution
- Final verification steps

### Code Comments
Update comments in:
- `VBlankLedger.zig` - Clarify race suppression semantics
- `execution.zig` - Document NMI line assertion logic
- `State.zig` - Document race detection and VBlank event handling

### CLAUDE.md Updates
- Update "Current Status" section with new test counts
- Document any architectural changes
- Update "Known Issues" section

---

## Timeline

**Phase 1 (Immediate):** Add race suppression to NMI logic - 30 min
**Phase 2 (High Priority):** Audit $2002 read path - 1 hour
**Phase 3 (High Priority):** Verify double-trigger suppression - 1 hour
**Phase 4 (Medium Priority):** Research and fix race window if needed - 1 hour
**Phase 5 (Required):** Full test suite validation - 30 min
**Phase 6 (Final):** Update expectations and documentation - 30 min

**Total Estimated Time:** 4.5 hours

---

## Next Immediate Steps

1. ✅ Investigation complete - all findings documented
2. **NEXT:** Implement Phase 1 (race suppression fix)
3. Run accuracy tests to verify improvement
4. Proceed to Phase 2 if needed
5. Continue until all tests pass

---

**Status:** Ready for implementation
**Confidence Level:** HIGH - Root cause identified with strong evidence
**Risk Level:** LOW-MEDIUM - Changes are targeted and testable
