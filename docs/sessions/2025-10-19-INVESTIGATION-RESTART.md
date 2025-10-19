# AccuracyCoin Test Failure Investigation - Systematic Analysis
**Date:** 2025-10-19
**Status:** ACTIVE - Evidence-Based Investigation

## Current Test Status (VERIFIED)

### Test Suite Results
- **Total Tests:** 1062
- **Passing:** 1040 (97.9%)
- **Failing:** 17
- **Skipped:** 5

### AccuracyCoin Accuracy Tests (from screenshots)

#### CPU Behavior Tests (Page 1/20)
1. ✅ **PASS:** ROM is not writable
2. ✅ **PASS:** RAM mirroring
3. ✅ **PASS:** PC wraparound
4. ✅ **PASS:** The decimal flag
5. ✅ **PASS:** The B flag
6. ✅ **PASS:** Dummy read cycles
7. ❌ **FAIL 2:** DUMMY WRITE CYCLES
8. ✅ **PASS:** Open bus
9. ❌ **FAIL A:** UNOFFICIAL INSTRUCTIONS
10. ❌ **FAIL 1:** ALL NOP INSTRUCTIONS
11. (Status unknown): NOP modified flags

#### PPU VBlank Timing Tests (Page 17/20)
1. ❌ **FAIL 1:** VBLANK BEGINNING
2. ❌ **FAIL 1:** VBLANK END
3. ❌ **FAIL 4:** NMI CONTROL
4. ❌ **FAIL 1:** NMI TIMING
5. ❌ **FAIL 1:** NMI SUPPRESSION
6. ❌ **FAIL 1:** NMI AT VBLANK END
7. ❌ **FAIL 1:** NMI DISABLED AT VBLANK

### Summary
- **10 accuracy tests failing**
- **3 CPU-related** (dummy writes, unofficial opcodes, NOPs)
- **7 VBlank/NMI-related** (all VBlank timing tests)

---

## Previous Investigation Documents Review

### Documents Available
1. `2025-10-19-dummywrite-nmi-investigation.md` - Initial investigation
2. `2025-10-19-REMEDIATION-PLAN.md` - Proposed fixes (UNVERIFIED)
3. `2025-10-19-BUG-FOUND.md` - Indirect indexed bug
4. `2025-10-19-VBLANK-LEDGER-DEEP-ANALYSIS.md` - VBlank ledger analysis
5. `2025-10-19-ppu-register-investigation-report.md` - PPU register behavior
6. Multiple other session documents

### Remediation Plan Analysis

The remediation plan proposed 4 RMW timing fixes:
- Absolute RMW: threshold 4→5
- Absolute,X/Y RMW: threshold 5→6
- Indexed Indirect RMW: threshold 6→7
- Indirect Indexed RMW: threshold 6→7

**ATTEMPTED AND FAILED:**
- Applied all 4 fixes
- Code compiled successfully
- RMW tests CRASHED with "unreachable" error at line 467
- **ROOT CAUSE:** Thresholds were increased, but microstep switch statements don't have cases for the higher instruction_cycle values
- **CONCLUSION:** Remediation plan diagnosis is INCORRECT

---

## Evidence-Based Analysis

### Why Did My Fixes Fail?

The microstep execution flow is:
1. Execute microstep using current `instruction_cycle` as switch index
2. Increment `instruction_cycle` by 1
3. Check if `instruction_cycle >= threshold`
4. If true, transition to execute state

For absolute_x RMW microsteps:
```zig
switch (state.cpu.instruction_cycle) {
    0 => fetchAbsLow,
    1 => fetchAbsHigh,
    2 => calcAbsoluteX,
    3 => rmwRead,
    4 => rmwDummyWrite,  // LAST CASE
    else => unreachable,
}
```

Current threshold: >= 5
- After instruction_cycle=4 (rmwDummyWrite), increment to 5
- Check >= 5: TRUE
- Transition to execute ✅ CORRECT

My "fix" threshold: >= 6
- After instruction_cycle=4 (rmwDummyWrite), increment to 5
- Check >= 6: FALSE
- Continue addressing, try to execute case 5
- No case for 5, hit unreachable ❌ CRASH

**CONCLUSION:** The current thresholds are CORRECT for the microstep structure.

---

## Hypothesis: The Bug Is NOT in the Thresholds

If the thresholds are correct, what else could cause dummy write failures?

### Possibility 1: Dummy Write Not Happening
Looking at `rmwDummyWrite()` implementation:
```zig
pub fn rmwDummyWrite(state: anytype) bool {
    state.busWrite(state.cpu.effective_address, state.cpu.temp_value);
    return false;
}
```

This DOES perform the write. So dummy writes ARE happening.

### Possibility 2: Writes Happening at Wrong Address
If `effective_address` is wrong, dummy writes go to the wrong place.

### Possibility 3: PPU Register Side Effects
From ppu-register-investigation-report.md:
- Writing to $2006 toggles the `w` register
- Dummy write and final write both toggle it
- This causes non-idempotent behavior

### Possibility 4: Test Expectations Don't Match Reality
Maybe the test expects different behavior than we're implementing?

---

## Action Plan: Evidence-Based Investigation

### Phase 1: Verify Dummy Writes Are Occurring
1. Add logging to `rmwDummyWrite()` to confirm it's called
2. Log the address and value being written
3. Run `dummy_write_cycles_test` with instrumentation
4. Verify writes to $2006 are happening

### Phase 2: Analyze PPU Register Behavior
1. Check if PPU $2006 writes have correct side effects
2. Verify address latch toggle behavior
3. Compare with hardware documentation

### Phase 3: Review AccuracyCoin ROM Source
1. Read the actual test ROM assembly
2. Understand what the test expects
3. Compare with our implementation

### Phase 4: Fix Based on Evidence
1. Apply fixes only after confirming root cause
2. Test after each fix
3. Document results

---

## Next Steps

**IMMEDIATE:**
1. Do NOT apply remediation plan fixes (they're wrong)
2. Run dummy_write_cycles_test with detailed logging
3. Analyze actual failure mode
4. Research hardware behavior
5. Apply evidence-based fix

**STOP GUESSING. START INVESTIGATING.**
