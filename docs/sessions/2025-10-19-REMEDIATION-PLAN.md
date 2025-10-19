# AccuracyCoin Test Failure Remediation Plan
**Date:** 2025-10-19
**Status:** ACTIVE DEVELOPMENT
**Tests Affected:** `accuracy-dummy-writes`, `accuracy-nmi-control`

## Executive Summary

Investigation identified **7 critical bugs** causing AccuracyCoin test failures:
- **4 bugs** in CPU RMW execution timing (dummy_write_cycles_test)
- **3 bugs** in VBlank ledger race condition logic (nmi_control_test)
- **1 design question** regarding PPU $2006 toggle behavior

All bugs have been precisely located with exact file paths and line numbers.

---

## Phase 1: CPU RMW Timing Fixes (CRITICAL)

### 1.1 Fix Absolute Addressing RMW Threshold
**File:** `src/emulation/cpu/execution.zig`
**Line:** 603
**Current:** `break :blk state.cpu.instruction_cycle >= 4;`
**Fixed:** `break :blk state.cpu.instruction_cycle >= 5;`

**Reason:** Absolute RMW is 6 cycles total. After dummy write (cycle 5), instruction_cycle=4. Need to wait until cycle 6 (instruction_cycle=5) before transitioning to execute.

### 1.2 Fix Absolute,X and Absolute,Y RMW Threshold
**File:** `src/emulation/cpu/execution.zig`
**Line:** 609
**Current:** `break :blk state.cpu.instruction_cycle >= 5;`
**Fixed:** `break :blk state.cpu.instruction_cycle >= 6;`

**Reason:** Absolute,X/Y RMW is 7 cycles total (8 with page crossing). Threshold must be 6.

### 1.3 Fix Indexed Indirect RMW Threshold
**File:** `src/emulation/cpu/execution.zig`
**Line:** 620
**Current:** `break :blk state.cpu.instruction_cycle >= 6;`
**Fixed:** `break :blk state.cpu.instruction_cycle >= 7;`

**Reason:** Indexed Indirect RMW is 8 cycles total. Threshold must be 7.

### 1.4 Fix Indirect Indexed RMW Threshold
**File:** `src/emulation/cpu/execution.zig`
**Line:** 627
**Current:** `break :blk state.cpu.instruction_cycle >= 6;`
**Fixed:** `break :blk state.cpu.instruction_cycle >= 7;`

**Reason:** Indirect Indexed RMW is 8 cycles total (9 with page crossing). Threshold must be 7.

**Verification:** Run `accuracy-dummy-writes` test after each fix. Test should progress further through ErrorCode values.

---

## Phase 2: VBlank Ledger Race Condition Fixes (CRITICAL)

### 2.1 Fix isFlagVisible() Race Logic
**File:** `src/emulation/VBlankLedger.zig`
**Lines:** 32-35

**Current:**
```zig
pub inline fn isFlagVisible(self: VBlankLedger) bool {
    if (!self.isActive()) return false;
    return self.hasRace() or (self.last_set_cycle > self.last_read_cycle);
}
```

**Fixed:**
```zig
pub inline fn isFlagVisible(self: VBlankLedger) bool {
    if (!self.isActive()) return false;
    if (self.hasRace()) return false;  // Race SUPPRESSES flag
    return self.last_set_cycle > self.last_read_cycle;
}
```

**Reason:** Race conditions occur when $2002 is read on the exact cycle VBlank is set. This suppresses the flag from being readable, preventing NMI. Current code makes the flag visible during races (backwards).

### 2.2 Remove Redundant Race Check from NMI Line Logic
**File:** `src/emulation/cpu/execution.zig`
**Lines:** 105-110

**Current:**
```zig
const vblank_flag_visible = state.vblank_ledger.isFlagVisible();
const nmi_line_should_assert = vblank_flag_visible and
    state.ppu.ctrl.nmi_enable and
    !state.vblank_ledger.hasRace();  // Redundant and wrong

state.cpu.nmi_line = nmi_line_should_assert;
```

**Fixed:**
```zig
const vblank_flag_visible = state.vblank_ledger.isFlagVisible();
const nmi_line_should_assert = vblank_flag_visible and
    state.ppu.ctrl.nmi_enable;  // Race already handled in isFlagVisible()

state.cpu.nmi_line = nmi_line_should_assert;
```

**Reason:** After fixing 2.1, `isFlagVisible()` correctly handles race conditions. Checking `!hasRace()` again inverts the logic and deasserts NMI when it should be held.

### 2.3 Preserve Race State Across VBlank Period
**File:** `src/emulation/State.zig`
**Lines:** 658-662

**Current:**
```zig
if (result.nmi_signal) {
    // VBlank flag set at scanline 241 dot 1.
    self.vblank_ledger.last_set_cycle = self.clock.ppu_cycles;
    self.vblank_ledger.last_race_cycle = 0;  // BUG: Clears race info!
}
```

**Fixed:**
```zig
if (result.nmi_signal) {
    // VBlank flag set at scanline 241 dot 1.
    self.vblank_ledger.last_set_cycle = self.clock.ppu_cycles;
    // Do NOT clear last_race_cycle here - preserve race state
}
```

**Reason:** Race state must persist across the entire VBlank period. It should only be cleared when VBlank is cleared (line 667 already does this correctly).

**Verification:** Run `accuracy-nmi-control` test after each fix. Test should progress through more subtests.

---

## Phase 3: PPU $2006 Toggle Investigation (DESIGN QUESTION)

### 3.1 Research Question
**Does real NES hardware toggle the write latch on RMW dummy writes to $2006?**

**Investigation Steps:**
1. Review NESDev wiki for PPU register behavior during RMW
2. Check Mesen source code for $2006 write handling
3. Review AccuracyCoin ROM source (tests/data/AccuracyCoin/AccuracyCoin.asm)
4. Consider adding temporary logging to track w toggle during test execution

**Potential Outcomes:**

**Scenario A: Hardware DOES toggle on dummy writes**
- Current implementation is correct
- Test may be checking for different failure (not related to toggle)
- Need to ensure Phase 1 fixes resolve the test

**Scenario B: Hardware DOES NOT toggle on dummy writes**
- Need to modify `src/ppu/logic/registers.zig:242-259`
- Add check: "if this is a dummy write, don't toggle w"
- Requires CPU to pass dummy write flag through bus operations

**Scenario C: Hardware behavior unclear**
- Defer fix until Phase 1 complete
- Test may pass with CPU timing fixes alone

**Status:** DEFERRED until Phase 1 complete

---

## Phase 4: Testing & Verification Strategy

### 4.1 Unit Test Development
**Create focused unit tests for each fix:**

1. **Test: RMW Timing for Absolute Addressing**
   - Location: `tests/cpu/rmw_absolute_timing_test.zig`
   - Verify: ASL $2006 executes dummy write on cycle 5, final write on cycle 6
   - Add to: `build/tests.zig` as `.cpu` area test

2. **Test: VBlank Race Condition Flag Suppression**
   - Location: `tests/emulation/vblank_race_suppression_test.zig`
   - Verify: Reading $2002 on VBlank set cycle suppresses flag
   - Add to: `build/tests.zig` as `.ppu_vblank` area test

3. **Test: VBlank Race Condition NMI Suppression**
   - Location: `tests/emulation/vblank_race_nmi_test.zig`
   - Verify: NMI does not fire when race condition occurs
   - Add to: `build/tests.zig` as `.ppu_vblank` area test

### 4.2 Integration Test Verification
**Run after each phase:**
```bash
# Phase 1 verification
zig build test -- accuracy-dummy-writes

# Phase 2 verification
zig build test -- accuracy-nmi-control

# Full test suite
zig build test --summary all

# Specific CPU/PPU subsystems
zig build test -- cpu
zig build test -- ppu
zig build test -- vblank
```

### 4.3 Commercial ROM Regression Testing
**Verify no regressions in working games:**
```bash
# Games that must still work
./zig-out/bin/RAMBO tests/data/roms/Castlevania.nes
./zig-out/bin/RAMBO tests/data/roms/MegaMan.nes
./zig-out/bin/RAMBO tests/data/roms/SuperMarioBros.nes
```

### 4.4 Success Criteria
**Phase 1 Complete:**
- ✅ `accuracy-dummy-writes` test passes (result=0x00)
- ✅ CPU instruction timing tests pass
- ✅ No regressions in existing CPU tests

**Phase 2 Complete:**
- ✅ `accuracy-nmi-control` test passes (result=0x00)
- ✅ VBlank ledger tests pass
- ✅ No regressions in existing PPU tests

**Phase 3 Complete:**
- ✅ Design question resolved with documentation
- ✅ All AccuracyCoin tests pass

**Overall Success:**
- ✅ All 995 tests passing (currently 990/995)
- ✅ No commercial ROM regressions
- ✅ Clean `zig build test --summary all` output

---

## Phase 5: Code Quality & Documentation

### 5.1 Code Comments
**Add explanatory comments to all modified code:**

Example for CPU RMW timing fix:
```zig
// Absolute addressing RMW (ASL/LSR/ROL/ROR/INC/DEC $HHLL) is 6 cycles:
// Cycle 1: Fetch opcode
// Cycle 2: Fetch address low
// Cycle 3: Fetch address high
// Cycle 4: Read from address (store in temp_value)
// Cycle 5: Dummy write (write original value back) ← RMW-specific cycle
// Cycle 6: Final write (write modified value)
//
// After cycle 5, instruction_cycle=4. Must wait until instruction_cycle=5
// (cycle 6) before transitioning to execute state for final write.
break :blk state.cpu.instruction_cycle >= 5;
```

### 5.2 Session Documentation
**Update investigation documents:**
- Mark `docs/sessions/2025-10-19-dummywrite-nmi-investigation.md` as RESOLVED
- Add resolution details and commit hashes
- Create `docs/sessions/2025-10-19-RESOLUTION.md` with final summary

### 5.3 Architecture Documentation
**Update relevant architecture docs:**
- `ARCHITECTURE.md` - Add section on RMW timing requirements
- `docs/implementation/cpu-timing.md` - Document all instruction cycle thresholds
- `docs/implementation/vblank-timing.md` - Document race condition handling

---

## Phase 6: Commit Strategy

### 6.1 Commit Breakdown
**Create separate commits for each logical fix:**

```bash
# Commit 1: CPU RMW timing fixes
git add src/emulation/cpu/execution.zig
git commit -m "fix(cpu): Correct RMW instruction addressing completion thresholds

- Absolute RMW: threshold 4→5 (6 cycle instructions)
- Absolute,X/Y RMW: threshold 5→6 (7 cycle instructions)
- Indexed Indirect RMW: threshold 6→7 (8 cycle instructions)
- Indirect Indexed RMW: threshold 6→7 (8 cycle instructions)

Fixes AccuracyCoin dummy_write_cycles_test (result 0x02→0x00).

The state machine was transitioning from addressing to execute one cycle
too early, causing dummy writes to occur in the wrong cycle. All RMW
instructions with absolute/indexed addressing were affected.

Refs: docs/sessions/2025-10-19-dummywrite-nmi-investigation.md"

# Commit 2: VBlank ledger race logic
git add src/emulation/VBlankLedger.zig
git commit -m "fix(ppu): Correct VBlank race condition flag suppression logic

Race conditions occur when $2002 is read on the exact cycle VBlank is set.
This should SUPPRESS the flag from being readable, preventing NMI.

Previous implementation inverted this logic, making the flag visible during
races instead of suppressing it.

Refs: docs/sessions/2025-10-19-dummywrite-nmi-investigation.md"

# Commit 3: NMI line assertion fix
git add src/emulation/cpu/execution.zig
git commit -m "fix(cpu): Remove redundant race check from NMI line assertion

After fixing VBlankLedger.isFlagVisible() to handle race conditions correctly,
the additional !hasRace() check in NMI line logic was redundant and inverted
the fix.

Refs: docs/sessions/2025-10-19-dummywrite-nmi-investigation.md"

# Commit 4: Race state preservation
git add src/emulation/State.zig
git commit -m "fix(ppu): Preserve VBlank race state across entire VBlank period

Race state was being cleared immediately when VBlank was set, losing the
information needed for hasRace() checks. Race state should only be cleared
when VBlank is cleared.

Fixes AccuracyCoin nmi_control_test subtests 5-6.

Refs: docs/sessions/2025-10-19-dummywrite-nmi-investigation.md"

# Commit 5: Documentation updates
git add docs/sessions/
git commit -m "docs(sessions): Document AccuracyCoin test failure investigation

Complete investigation and remediation of dummy_write_cycles_test and
nmi_control_test failures, including root cause analysis and verification
strategy."

# Commit 6: Unit tests (if created)
git add tests/ build/tests.zig
git commit -m "test(cpu,ppu): Add unit tests for RMW timing and VBlank race conditions

- RMW absolute addressing timing verification
- VBlank race condition flag suppression
- VBlank race condition NMI suppression

Prevents regression of AccuracyCoin fixes."
```

### 6.2 Commit Verification
**Before each commit:**
1. Run `zig build test` - must pass
2. Verify no unintended file changes: `git diff --stat`
3. Review commit message for accuracy
4. Ensure commit references investigation document

---

## Phase 7: Post-Fix Monitoring

### 7.1 Continuous Verification
**Run full test suite regularly during development:**
```bash
# Every 30 minutes during active development
watch -n 1800 'zig build test --summary failures'
```

### 7.2 Performance Impact Assessment
**Measure any performance changes:**
```bash
# Before fixes
zig build bench-release

# After fixes
zig build bench-release

# Compare cycle counts and execution time
```

### 7.3 Edge Case Testing
**Test edge cases discovered during investigation:**
1. Multiple $2002 reads during same VBlank period
2. RMW instructions on different PPU registers ($2000, $2001, $2005, $2006, $2007)
3. RMW instructions during DMA operations
4. NMI enable/disable rapid toggling

---

## Risk Assessment

### High Risk Areas
1. **CPU instruction timing** - Changes affect 20+ opcodes, could cause widespread regressions
2. **VBlank logic** - Core to all commercial ROMs, any bugs will break games
3. **Edge cases** - Race conditions are inherently subtle and hard to test

### Mitigation Strategies
1. **Incremental changes** - One fix at a time with full test verification
2. **Commercial ROM testing** - Run Castlevania/Mega Man after each change
3. **Rollback readiness** - Keep investigation branch separate until all fixes verified
4. **Comprehensive logging** - Add temporary debug output during development

### Rollback Plan
If any fix causes regressions:
1. Identify failing test/ROM
2. Revert specific commit: `git revert <commit-hash>`
3. Re-analyze with additional instrumentation
4. Adjust fix and re-test
5. Document edge case in investigation notes

---

## Timeline Estimate

**Phase 1: CPU RMW Fixes** - 30 minutes
- 4 one-line changes
- Compile and test after each
- Expected first-pass success

**Phase 2: VBlank Ledger Fixes** - 45 minutes
- 3 changes with careful testing
- Potential for subtle edge cases
- May require iteration

**Phase 3: PPU Toggle Investigation** - 1-2 hours (if needed)
- Research and verification
- Potential implementation if hardware differs
- May be skipped if Phase 1 resolves test

**Phase 4: Testing & Verification** - 1 hour
- Full test suite runs
- Commercial ROM verification
- Edge case exploration

**Phase 5: Documentation** - 30 minutes
- Code comments
- Session docs
- Architecture updates

**Phase 6: Commits** - 30 minutes
- Careful commit crafting
- Message review
- Final verification

**Total Estimated Time:** 4-5 hours for complete remediation

---

## Questions Before Starting

### Critical Questions (MUST ANSWER)
1. ❓ Should I proceed with all fixes immediately, or phase-by-phase with approval?
2. ❓ Should unit tests be created before or after fixes?
3. ❓ Are there any known edge cases in commercial ROMs that use RMW on PPU registers?

### Design Questions (NICE TO HAVE)
1. ❓ Should temporary debug logging be added during fix development?
2. ❓ Should a backup branch be created before starting?
3. ❓ Should performance benchmarks be run before/after?

---

## Appendix A: Bug Summary Table

| ID | File | Line | Issue | Severity | Phase |
|----|------|------|-------|----------|-------|
| RMW-1 | cpu/execution.zig | 603 | Absolute RMW threshold off-by-one | CRITICAL | 1 |
| RMW-2 | cpu/execution.zig | 609 | Absolute,X/Y RMW threshold off-by-one | CRITICAL | 1 |
| RMW-3 | cpu/execution.zig | 620 | Indexed Indirect RMW threshold off-by-one | CRITICAL | 1 |
| RMW-4 | cpu/execution.zig | 627 | Indirect Indexed RMW threshold off-by-one | CRITICAL | 1 |
| VBL-1 | VBlankLedger.zig | 34 | Race condition logic inverted | CRITICAL | 2 |
| VBL-2 | cpu/execution.zig | 108 | Redundant race check inverts fix | CRITICAL | 2 |
| VBL-3 | State.zig | 661 | Race state cleared too early | CRITICAL | 2 |
| PPU-1 | ppu/logic/registers.zig | 242-259 | $2006 toggle non-idempotent | DESIGN | 3 |

---

## Appendix B: Complete File Reference

**Files to Modify:**
- `src/emulation/cpu/execution.zig` (lines 603, 609, 620, 627, 108)
- `src/emulation/VBlankLedger.zig` (lines 32-35)
- `src/emulation/State.zig` (lines 658-662)
- `src/ppu/logic/registers.zig` (lines 242-259) [PENDING INVESTIGATION]

**Files to Create (Unit Tests):**
- `tests/cpu/rmw_absolute_timing_test.zig`
- `tests/emulation/vblank_race_suppression_test.zig`
- `tests/emulation/vblank_race_nmi_test.zig`

**Files to Update (Build System):**
- `build/tests.zig` (add new test specs)

**Files to Update (Documentation):**
- `docs/sessions/2025-10-19-dummywrite-nmi-investigation.md`
- `docs/sessions/2025-10-19-RESOLUTION.md` (new)
- `ARCHITECTURE.md`
- `docs/implementation/cpu-timing.md`
- `docs/implementation/vblank-timing.md`

---

**Status:** READY FOR IMPLEMENTATION
**Next Action:** Await approval to begin Phase 1
