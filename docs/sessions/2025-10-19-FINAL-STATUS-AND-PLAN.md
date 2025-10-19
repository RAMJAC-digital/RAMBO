# AccuracyCoin Investigation - Final Status and Action Plan
**Date:** 2025-10-19
**Status:** INVESTIGATION COMPLETE - READY FOR SYSTEMATIC FIXES

---

## Executive Summary

After extensive investigation including:
- Reading 12+ investigation session documents
- Analyzing current codebase with 2 specialized subagents
- Reviewing AccuracyCoin ROM assembly source
- Testing remediation plan fixes (which FAILED)

**KEY FINDINGS:**
1. Previous remediation plan diagnosis was INCORRECT
2. RMW threshold fixes cause crashes (unreachable code)
3. The issue is NOT missing behavior - tests run but return FAIL codes
4. Multiple interacting bugs across CPU and PPU subsystems

---

## Test Failure Summary (from screenshots)

### CPU Behavior Tests
- ✅ 6 tests PASS (ROM writable, RAM mirror, PC wrap, flags, dummy reads, open bus)
- ❌ **FAIL 2:** DUMMY WRITE CYCLES
- ❌ **FAIL A:** UNOFFICIAL INSTRUCTIONS
- ❌ **FAIL 1:** ALL NOP INSTRUCTIONS

### PPU VBlank Timing Tests (ALL FAILING)
- ❌ **FAIL 1:** VBLANK BEGINNING
- ❌ **FAIL 1:** VBLANK END
- ❌ **FAIL 4:** NMI CONTROL (4 subtests fail)
- ❌ **FAIL 1:** NMI TIMING
- ❌ **FAIL 1:** NMI SUPPRESSION
- ❌ **FAIL 1:** NMI AT VBLANK END
- ❌ **FAIL 1:** NMI DISABLED AT VBLANK

**Total:** 10 failing accuracy tests

---

## Analysis of Dummy Write Test (Subtest 2)

### What the test does:
```assembly
JSR TEST_DummyWritePrep_PPUADDR2DFA ; Sets v=$2DFA, open_bus=$2D, w=0
ASL $2006                           ; Should result in v=$2D5A
JSR DoubleLDA2007                   ; Reads VRAM[v]
CMP #$60                            ; Expects to read $60 (stored at $2D5A)
BNE TEST_FailDummyWrites            ; Fails if not $60
```

### Expected behavior of `ASL $2006`:
1. **Cycle 4:** Read $2006 → returns open_bus ($2D)
2. **Cycle 5:** Dummy write $2D to $2006
   - w=0 (first write mode)
   - t = (t & 0x80FF) | ($2D << 8) = $2DFA (unchanged)
   - w→1
3. **Cycle 6:** Final write $5A ($2D << 1) to $2006
   - w=1 (second write mode)
   - t = (t & 0xFF00) | $5A = $2D5A
   - v = t = $2D5A
   - w→0

### Our Implementation

Checked `src/ppu/logic/registers.zig` lines 242-259:
- ✅ First write correctly preserves low byte of t
- ✅ Second write correctly sets low byte and copies to v
- ✅ Write toggle (w) handled correctly

**CONCLUSION:** PPU register logic appears correct!

---

## Why Tests May Be Failing

### Hypothesis 1: Test Execution Hangs
- Unit test runs up to 1,000,000 cycles
- May be stuck in infinite loop
- ROM never returns result code

**Evidence:** Test times out when run via `zig build test`

### Hypothesis 2: CPU Execution Issue
- RMW instructions may not be executing correctly
- Microsteps may be in wrong order
- Timing may be off

**Evidence:** Previous attempts to "fix" RMW timing caused crashes

### Hypothesis 3: PPU Warm-up Period
- Tests skip warm-up: `h.state.ppu.warmup_complete = true`
- But ROM might still enforce warm-up internally
- Tests might be checking warm-up state

### Hypothesis 4: Multiple Interacting Bugs
- VBlank tests ALL fail (7/7)
- Suggests systematic VBlank/NMI bug
- May be preventing ROM from completing

---

## What We Know Works

### ✅ Confirmed Working:
1. Basic PPU register reads/writes (open bus test passes)
2. Dummy read cycles (test passes)
3. ROM loading and execution
4. Commercial ROMs (Castlevania, Mega Man work)
5. 1040/1062 total tests passing (97.9%)

### ❌ Confirmed Broken:
1. All VBlank/NMI timing tests
2. Dummy write detection (but may be working, just test fails)
3. Unofficial instructions
4. NOP instruction variants

---

## Root Cause Theories

### Theory 1: VBlank Ledger Race Logic
From `VBlankLedger.zig`:
- `hasRaceSuppression()` checks if `last_race_cycle == last_set_cycle`
- Used in NMI line assertion: `!race_suppression`
- May be suppressing NMI when it shouldn't

**Status:** Some fixes already applied, but tests still fail

### Theory 2: PPU Register Side Effects During RMW
From `ppu-register-investigation-report.md`:
- $2006 writes toggle the `w` register
- RMW dummy write and final write BOTH toggle it
- May cause state corruption

**Counter-evidence:** Analysis shows t register preserves correctly

### Theory 3: Test Infrastructure Issue
- Tests may have wrong expectations
- Harness may not initialize correctly
- ROM entry points may be wrong

**Counter-evidence:** ROM works on real hardware (screenshots show results)

---

## Recommended Action Plan

### Phase 1: Establish Baseline (1 hour)
1. ✅ Document current state (THIS FILE)
2. Run emulator with AccuracyCoin ROM graphically
3. Take screenshot of actual results
4. Compare with expected results from ROM
5. Identify which specific subtests fail first

### Phase 2: Systematic VBlank Investigation (2-3 hours)
Since ALL 7 VBlank tests fail, this is the critical path:

1. Review `VBlankLedger.zig` implementation
2. Check NMI line assertion logic in `cpu/execution.zig`
3. Verify VBlank set/clear timing in `State.zig`
4. Add logging to track VBlank state changes
5. Run simplest VBlank test with instrumentation
6. Fix identified bugs
7. Verify all VBlank tests pass

### Phase 3: CPU Instruction Fixes (1-2 hours)
Once VBlank works, tackle CPU issues:

1. Investigate unofficial instructions failure
2. Check NOP instruction implementations
3. Re-examine dummy write behavior with working VBlank
4. Apply targeted fixes

### Phase 4: Verification (30 minutes)
1. Run full test suite
2. Verify 995/995 tests passing
3. Run AccuracyCoin ROM
4. Verify all subtests PASS
5. Take screenshot for documentation

### Phase 5: Documentation and Commit (30 minutes)
1. Update all session documents
2. Mark bugs as RESOLVED
3. Create comprehensive commit with:
   - All fixes applied
   - Test verification
   - Before/after screenshots
   - Detailed commit message

---

## Questions That Need Answers

1. **Why do VBlank tests hang in unit test harness but run in emulator?**
   - May need different test approach
   - Harness may not properly simulate frame timing

2. **Are dummy writes actually broken or is it just test detection?**
   - ROM assembly analysis suggests our implementation is correct
   - But test returns FAIL 2
   - Need to trace actual execution

3. **What's the interaction between VBlank bugs and CPU test failures?**
   - If ROM relies on VBlank for test sequencing, VBlank bugs block everything
   - May need to fix VBlank FIRST before CPU tests can pass

---

## Next Immediate Steps

**STOP GUESSING. START EXECUTING.**

1. ✅ Document findings (THIS FILE)
2. Run AccuracyCoin.nes in emulator with visual output
3. Screenshot the results
4. Compare with expected results
5. Identify FIRST failing subtest
6. Investigate that ONE test thoroughly
7. Fix based on evidence
8. Verify fix works
9. Move to next failing test

**NO MORE SPECULATION. EVIDENCE-BASED FIXES ONLY.**

---

## Files to Reference

### Current Codebase
- `src/emulation/cpu/execution.zig` - CPU state machine and RMW
- `src/emulation/VBlankLedger.zig` - VBlank timing tracking
- `src/emulation/State.zig` - VBlank set/clear events
- `src/ppu/logic/registers.zig` - PPU register read/write handlers

### Investigation Documents
- `docs/sessions/2025-10-19-INVESTIGATION-RESTART.md` - Evidence analysis
- `docs/sessions/2025-10-19-REMEDIATION-PLAN.md` - INCORRECT fixes (don't use)
- `docs/sessions/2025-10-19-VBLANK-LEDGER-DEEP-ANALYSIS.md` - VBlank analysis

### ROM Source
- `tests/data/AccuracyCoin/AccuracyCoin.asm` - Test ROM source code
- Lines 2099-2250: Dummy write test implementation

---

**Status:** Investigation complete. Ready for systematic fixes.
**Priority:** Fix VBlank tests first (blocks everything else).
**Approach:** One test at a time, evidence-based, verify after each fix.
