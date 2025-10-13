# VBlank/NMI Fix Development Plan

**Created:** 2025-10-12
**Priority:** P0 (Critical)
**Target Milestone:** Super Mario Bros Playability
**Status:** In Progress - Phase 2

---

## Executive Summary

This document provides a systematic development plan for fixing the Super Mario Bros blank screen bug. The issue has evolved through multiple investigation phases, and this plan provides structure to avoid circular investigation and ensure forward progress.

**Current Understanding:**
- VBlank flag timing is correct
- NMI mechanism fires correctly
- SMB NMI handler executes but gets stuck in countdown loop
- Root cause: Unknown (handler loop never terminates)

**Next Steps:**
- Use debugger to break at handler loop
- Identify why countdown loop doesn't exit
- Implement fix based on root cause

---

## Problem Statement

### Core Issue

Super Mario Bros displays a **blank screen** because the game never writes `PPUMASK=0x1E` to enable rendering. The game is stuck in its initialization sequence, specifically in a countdown loop within the NMI handler at address `0x8E6C-0x8E79`.

### What Works ✅

- VBlank flag sets at scanline 241.1 and clears at 261.1
- Reading $2002 returns correct VBlank status and clears the flag
- NMI edge detection fires correctly when VBlank sets
- NMI handler executes and jumps to `0x8082` correctly
- VBlankLedger architecture handles race conditions properly
- AccuracyCoin test ROM passes (939/939 opcode tests)
- Mario Bros (different game) works correctly

### What's Broken ❌

- SMB NMI handler gets stuck in countdown loop at `0x8E6C-0x8E79`
- Loop structure: `DEY + BNE` (decrement Y, branch if not zero)
- Loop never terminates (Y never reaches zero)
- Handler never completes initialization
- Game never writes PPUMASK=0x1E to enable rendering

### Impact

- **User Experience:** Super Mario Bros unplayable
- **Project Milestone:** Blocks commercial ROM compatibility milestone
- **Test Coverage:** Exposes gap in real-world timing tests
- **Confidence:** Undermines confidence in cycle accuracy despite passing AccuracyCoin

---

## Success Criteria

### Primary Goal

**Super Mario Bros displays title screen and responds to input**

Acceptance criteria:
- ✅ SMB displays title screen (rendering enabled)
- ✅ SMB responds to controller input
- ✅ SMB gameplay starts when START button pressed
- ✅ No visual glitches or timing issues
- ✅ Game progresses through levels correctly

### Secondary Goals

**No regressions in existing functionality**

Regression criteria:
- ✅ All existing tests still pass (949/986 or better)
- ✅ AccuracyCoin still passes (939/939 opcode tests)
- ✅ Mario Bros still works (no regression in working ROM)
- ✅ VBlank timing tests still pass (44 tests)
- ✅ No new timing bugs introduced

### Documentation Goals

**Complete investigation trail for future reference**

Documentation criteria:
- ✅ Root cause identified and documented
- ✅ Fix implementation explained with rationale
- ✅ Test coverage added for discovered issue
- ✅ Session notes provide clear investigation history
- ✅ KNOWN-ISSUES.md updated with resolution

---

## Phases

### Phase 1: Code Review ✅ COMPLETE

**Status:** ✅ Complete (2025-10-12)
**Duration:** 1 day
**Effort:** 4 hours

**Objective:** Verify VBlankLedger and NMI edge detection implementation correctness

**Tasks Completed:**
- [x] Reviewed VBlankLedger timestamp tracking logic
- [x] Reviewed $2002 read handler side effects
- [x] Reviewed NMI edge detection in CPU stepping
- [x] Verified race condition handling
- [x] Confirmed single source of truth architecture

**Deliverables:**
- ✅ VBlankLedger architecture verified sound
- ✅ No architectural duplication found
- ✅ Race condition handling confirmed correct
- ✅ Side effect isolation verified proper

**Outcome:** Architecture is correct, bug must be in handler execution or timing

---

### Phase 2: Timing Analysis (CURRENT)

**Status:** 🔄 In Progress
**Duration:** 1-2 days
**Effort:** 6-8 hours

**Objective:** Trace SMB NMI handler execution to identify why countdown loop doesn't terminate

**Tasks:**

**2.1: Break at Handler Entry** (HIGH PRIORITY)
- [ ] Build RAMBO with debugger: `zig build`
- [ ] Launch SMB with breakpoint at NMI handler: `--break-at 0x8082 --inspect`
- [ ] Capture CPU state at handler entry (A, X, Y, SP, P, PC)
- [ ] Document initial register values in session notes

**2.2: Trace to Stuck Loop** (HIGH PRIORITY)
- [ ] Continue execution until PC reaches `0x8E6C` (loop entry)
- [ ] Capture CPU state at loop entry (especially Y register)
- [ ] Set breakpoint at `0x8E6C`: `--break-at 0x8E6C --inspect`
- [ ] Count how many iterations loop executes before timeout

**2.3: Analyze Loop Behavior** (MEDIUM PRIORITY)
- [ ] Disassemble complete loop (`0x8E6C-0x8E79`)
- [ ] Identify memory addresses accessed: `LDA abs,X` operand
- [ ] Identify zero page addresses written: `STA zp` operand
- [ ] Check if Y register actually decrements each iteration
- [ ] Verify BNE branch target and condition

**2.4: Compare with Expected** (MEDIUM PRIORITY)
- [ ] Research SMB disassembly online (if available)
- [ ] Compare loop behavior with known-good execution
- [ ] Identify expected Y register initial value
- [ ] Identify expected loop iteration count
- [ ] Check if memory contents match expected values

**2.5: Check PPU State** (LOW PRIORITY)
- [ ] Capture PPU scanline/dot during handler execution
- [ ] Check if handler timing affects memory-mapped I/O
- [ ] Verify VBlank span still active during handler
- [ ] Check if OAM DMA conflicts with handler

**Deliverables:**
- [ ] Complete disassembly of handler loop
- [ ] CPU register values at loop entry
- [ ] Memory addresses accessed by loop
- [ ] Loop iteration count before timeout
- [ ] Hypothesis for why loop doesn't terminate

**Success Metric:** Root cause identified with evidence

---

### Phase 3: Test Enhancement

**Status:** ⏸️ Pending Phase 2 Complete
**Duration:** 1-2 days
**Effort:** 6-8 hours

**Objective:** Add test coverage for discovered issue to prevent regression

**Tasks:**

**3.1: Create SMB-Specific Tests**
- [ ] Create `tests/integration/smb_nmi_handler_test.zig`
- [ ] Simulate countdown loop structure (DEY + BNE)
- [ ] Test Y register decrements correctly
- [ ] Test loop terminates at Y=0
- [ ] Test memory access pattern matches expected

**3.2: Add Multi-Frame Tests**
- [ ] Test NMI handler executes multiple frames
- [ ] Test handler can re-enable NMI for next frame
- [ ] Test initialization across 3-5 VBlank cycles
- [ ] Test PPUMASK writes in sequence

**3.3: Add OAM DMA Tests**
- [ ] Test OAM DMA during NMI handler
- [ ] Test DMA timing doesn't corrupt handler
- [ ] Test DMA completes before handler returns

**3.4: Add $2002 During Handler Tests**
- [ ] Test reading $2002 during handler execution
- [ ] Test flag clears but NMI edge persists
- [ ] Test handler can query VBlank status mid-execution

**Deliverables:**
- [ ] 10+ new tests covering SMB scenario
- [ ] All new tests passing
- [ ] Test coverage report showing improvement
- [ ] Integration with existing test suite

**Success Metric:** Test coverage prevents future regression of discovered issue

---

### Phase 4: Root Cause Identification

**Status:** ⏸️ Pending Phase 2 Complete
**Duration:** 1 day
**Effort:** 4-6 hours

**Objective:** Definitively identify why SMB handler loop doesn't terminate

**Possible Root Causes:**

**A. CPU Bug - Instruction Implementation**

**Symptoms:**
- DEY instruction not decrementing Y register
- BNE instruction not branching correctly
- Status flags (Z flag) not setting correctly

**Investigation:**
- [ ] Test DEY instruction in isolation (unit test)
- [ ] Test BNE instruction with various Z flag states
- [ ] Verify status register flag updates
- [ ] Check if other ROMs use DEY+BNE successfully

**Fix Approach:**
- Fix DEY implementation in `src/cpu/opcodes/`
- Fix BNE branch condition evaluation
- Add comprehensive unit tests for DEY+BNE

---

**B. Memory Bug - Bus/Mapper Routing**

**Symptoms:**
- Loop reads wrong memory addresses
- Memory-mapped I/O returns wrong values
- Cartridge mapper routing addresses incorrectly

**Investigation:**
- [ ] Verify `LDA abs,X` operand address
- [ ] Check memory read returns expected value
- [ ] Verify zero page writes go to correct addresses
- [ ] Test mapper (NROM) address decoding

**Fix Approach:**
- Fix bus address routing in `src/emulation/bus/`
- Fix NROM mapper implementation
- Add memory access tracing for debugging

---

**C. Timing Bug - PPU/VBlank Interaction**

**Symptoms:**
- Handler expects specific PPU scanline/dot
- VBlank period ends prematurely
- OAM DMA timing conflicts with handler

**Investigation:**
- [ ] Trace PPU scanline/dot during handler
- [ ] Check if VBlank span ends before handler completes
- [ ] Verify OAM DMA cycle counting
- [ ] Check if handler timing affects memory-mapped I/O

**Fix Approach:**
- Adjust VBlank timing (unlikely, tests pass)
- Fix OAM DMA cycle counting
- Add PPU state tracking during interrupts

---

**D. Initialization Bug - Game State**

**Symptoms:**
- Game expects specific power-on state
- Zero page memory not initialized correctly
- Stack or stack pointer in wrong state

**Investigation:**
- [ ] Compare zero page contents with known-good
- [ ] Check stack pointer and stack contents
- [ ] Verify power-on state matches hardware
- [ ] Test if controller input is required

**Fix Approach:**
- Fix power-on initialization
- Document required user input (if applicable)
- Add initialization state tests

---

**Deliverables:**
- [ ] Root cause identified with high confidence
- [ ] Evidence collected (traces, tests, comparisons)
- [ ] Fix approach selected with rationale
- [ ] Implementation plan documented

**Success Metric:** Root cause identified and fix approach agreed upon

---

### Phase 5: Fix Implementation

**Status:** ⏸️ Pending Phase 4 Complete
**Duration:** 1-2 days
**Effort:** 4-8 hours (depends on root cause)

**Objective:** Implement fix that resolves SMB issue without breaking existing functionality

**Tasks:**

**5.1: Implement Fix**
- [ ] Implement fix based on root cause (Phase 4)
- [ ] Add code comments explaining fix
- [ ] Update relevant documentation
- [ ] Run affected unit tests

**5.2: Add Test Coverage**
- [ ] Add unit tests for fixed code
- [ ] Add integration test for SMB scenario
- [ ] Verify new tests pass
- [ ] Verify new tests fail without fix (validate test)

**5.3: Test SMB**
- [ ] Build RAMBO: `zig build`
- [ ] Run SMB: `./zig-out/bin/RAMBO "Super Mario Bros. (World).nes"`
- [ ] Verify title screen appears
- [ ] Test controller input (D-pad, A, B, START, SELECT)
- [ ] Test gameplay (level 1-1)

**5.4: Code Review**
- [ ] Review fix for correctness
- [ ] Review fix for performance
- [ ] Review fix for maintainability
- [ ] Check for edge cases

**Deliverables:**
- [ ] Fix implemented and tested
- [ ] SMB displays title screen
- [ ] New test coverage added
- [ ] Code reviewed and approved

**Success Metric:** SMB playable, fix is clean and well-tested

---

### Phase 6: Regression Testing

**Status:** ⏸️ Pending Phase 5 Complete
**Duration:** 1 day
**Effort:** 2-4 hours

**Objective:** Verify fix doesn't break existing functionality

**Tasks:**

**6.1: Run Full Test Suite**
```bash
zig build test
```
- [ ] Verify 949+ tests passing (no decrease)
- [ ] Check for new failures
- [ ] Investigate any regressions
- [ ] Fix any introduced bugs

**6.2: Run AccuracyCoin**
```bash
./zig-out/bin/RAMBO tests/data/AccuracyCoin.nes
```
- [ ] Verify 939/939 opcode tests pass
- [ ] Check for timing regressions
- [ ] Verify ROM completes successfully

**6.3: Run Mario Bros (Working ROM)**
```bash
./zig-out/bin/RAMBO "tests/data/Mario Bros (USA).nes"
```
- [ ] Verify title screen displays
- [ ] Verify gameplay works
- [ ] Check for visual glitches
- [ ] Test controller input

**6.4: Run VBlank Test Suite**
```bash
zig build test --filter vblank
```
- [ ] Verify 44 VBlank/NMI tests pass
- [ ] Check timing tests pass
- [ ] Verify race condition tests pass

**6.5: Run SMB Again**
```bash
./zig-out/bin/RAMBO "Super Mario Bros. (World).nes"
```
- [ ] Verify fix still works
- [ ] Test multiple play sessions
- [ ] Test save states (if implemented)
- [ ] Test reset functionality

**Deliverables:**
- [ ] Full test suite passing (949+ tests)
- [ ] AccuracyCoin passing (939/939)
- [ ] Mario Bros working (no regression)
- [ ] SMB working (primary goal)
- [ ] Regression report (if any issues found)

**Success Metric:** Zero regressions, SMB works reliably

---

### Phase 7: Documentation & Cleanup

**Status:** ⏸️ Pending Phase 6 Complete
**Duration:** 0.5 days
**Effort:** 2-3 hours

**Objective:** Document fix and update project status

**Tasks:**

**7.1: Update KNOWN-ISSUES.md**
- [ ] Mark SMB blank screen as ✅ FIXED
- [ ] Document root cause
- [ ] Document fix implementation
- [ ] Add references to commits and docs

**7.2: Update Investigation Doc**
- [ ] Add final session notes
- [ ] Document complete investigation trail
- [ ] Add lessons learned section
- [ ] Archive or update status

**7.3: Update CLAUDE.md**
- [ ] Update test count (949+ passing)
- [ ] Update current status
- [ ] Remove SMB from known issues
- [ ] Update last updated date

**7.4: Create Commit**
```bash
git add <files>
git commit -m "fix(nmi): Fix SMB NMI handler loop termination

Root cause: [DESCRIPTION]
Fix: [DESCRIPTION]

- Fixes Super Mario Bros blank screen issue
- Handler countdown loop now terminates correctly
- Added test coverage for NMI handler timing
- No regressions in existing tests (949+ passing)
- AccuracyCoin still passes (939/939)

Closes #XXX (if issue exists)

🤖 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>"
```

**7.5: Clean Up Debug Code**
- [ ] Remove temporary debug logging
- [ ] Clean up test harness changes (if temporary)
- [ ] Update comments to reflect fix
- [ ] Run linter/formatter

**Deliverables:**
- [ ] KNOWN-ISSUES.md updated
- [ ] Investigation doc completed
- [ ] CLAUDE.md updated
- [ ] Clean commit created
- [ ] No debug code left in codebase

**Success Metric:** Documentation complete, codebase clean

---

## Risk Mitigation

### Risk: Fix breaks AccuracyCoin

**Likelihood:** Low
**Impact:** High (breaks confidence in cycle accuracy)

**Mitigation:**
- Run AccuracyCoin after every code change
- If regression occurs, bisect commits to find cause
- Have rollback plan (git branch before fix)
- Add AccuracyCoin to CI pipeline

**Contingency:**
- If AccuracyCoin breaks, revert fix
- Investigate why fix broke AccuracyCoin
- Find alternative fix that satisfies both
- Consider SMB-specific workaround if necessary

---

### Risk: Fix is SMB-specific hack

**Likelihood:** Medium
**Impact:** Medium (technical debt, future bugs)

**Mitigation:**
- Verify fix is based on hardware behavior
- Reference nesdev.org specifications
- Test fix with multiple commercial ROMs
- Add comments explaining hardware correspondence

**Contingency:**
- If fix is hack, document as such in code
- Add TODO for proper fix in future
- Create issue for tracking proper implementation
- Test with other games to ensure no negative impact

---

### Risk: Root cause is multiple bugs

**Likelihood:** Medium
**Impact:** High (extended timeline, complex fix)

**Mitigation:**
- Use systematic debugging approach
- Fix one issue at a time
- Re-test after each fix
- Document each issue separately

**Contingency:**
- Break into multiple smaller fixes
- Prioritize critical bugs first
- Track bugs in separate issues
- Coordinate fixes to avoid conflicts

---

### Risk: Cannot reproduce in debugger

**Likelihood:** Low
**Impact:** High (blocks investigation)

**Mitigation:**
- Use built-in debugger (already working)
- Add trace logging if debugger insufficient
- Use test harness to simulate scenario
- Compare with known-good emulator

**Contingency:**
- If debugger fails, add temporary logging
- Compare memory dumps at key points
- Use differential testing with known-good emulator
- Create minimal reproduction test case

---

## Estimated Timeline

### Optimistic Case: 3-4 days

**Assumptions:**
- Root cause is simple (single instruction bug)
- Fix is straightforward (no architectural changes)
- No regressions occur
- SMB works after first fix attempt

**Timeline:**
- Day 1: Phase 2 (Timing Analysis) - 6 hours
- Day 2: Phase 3-4 (Tests + Root Cause) - 8 hours
- Day 3: Phase 5 (Fix Implementation) - 4 hours
- Day 4: Phase 6-7 (Regression + Docs) - 4 hours

**Total:** ~22 hours over 4 days

---

### Realistic Case: 5-7 days

**Assumptions:**
- Root cause is moderately complex (timing interaction)
- Fix requires careful implementation
- Minor regressions need fixing
- SMB works after 2-3 fix iterations

**Timeline:**
- Day 1-2: Phase 2 (Timing Analysis) - 12 hours
- Day 3: Phase 3 (Test Enhancement) - 6 hours
- Day 4: Phase 4 (Root Cause ID) - 6 hours
- Day 5-6: Phase 5 (Fix Implementation) - 12 hours
- Day 7: Phase 6-7 (Regression + Docs) - 6 hours

**Total:** ~42 hours over 7 days

---

### Pessimistic Case: 10-14 days

**Assumptions:**
- Root cause is complex (multiple interacting bugs)
- Fix requires architectural changes
- Significant regressions occur
- SMB requires multiple fix iterations and workarounds

**Timeline:**
- Day 1-3: Phase 2 (Timing Analysis) - 18 hours
- Day 4-5: Phase 3 (Test Enhancement) - 12 hours
- Day 6-7: Phase 4 (Root Cause ID) - 12 hours
- Day 8-11: Phase 5 (Fix Implementation) - 24 hours
- Day 12-13: Phase 6 (Regression Testing) - 12 hours
- Day 14: Phase 7 (Documentation) - 4 hours

**Total:** ~82 hours over 14 days

---

## Dependencies

### External Dependencies

**None** - All work can be completed with existing tools:
- Zig 0.15.1 compiler
- Built-in debugger
- Existing test infrastructure
- nesdev.org documentation

### Internal Dependencies

**Phase Dependencies:**
- Phase 3 blocked on Phase 2 (need root cause hypothesis)
- Phase 4 blocked on Phase 2 (need timing analysis data)
- Phase 5 blocked on Phase 4 (need root cause identification)
- Phase 6 blocked on Phase 5 (need fix implementation)
- Phase 7 blocked on Phase 6 (need regression testing complete)

**Resource Dependencies:**
- Single developer (no parallelization possible)
- Debugger working (already verified)
- Test suite reliable (already verified)
- SMB ROM available (already in repo)

---

## Success Metrics

### Quantitative Metrics

| Metric | Current | Target | Success Threshold |
|--------|---------|--------|------------------|
| Test Pass Rate | 949/986 (96.2%) | 955/986+ (96.8%+) | No decrease |
| AccuracyCoin | 939/939 (100%) | 939/939 (100%) | Must maintain |
| SMB Playable | No | Yes | Yes |
| VBlank Tests | 44 passing | 44 passing | No decrease |
| Code Coverage | Unknown | +5% | Increase |

### Qualitative Metrics

**Code Quality:**
- [ ] Fix is based on hardware specification
- [ ] Fix is well-commented and documented
- [ ] Fix doesn't introduce technical debt
- [ ] Fix is maintainable and understandable

**Testing:**
- [ ] New tests cover discovered issue
- [ ] Tests are deterministic and reliable
- [ ] Tests run quickly (no slow integration tests)
- [ ] Tests are well-documented

**Documentation:**
- [ ] Investigation trail is complete
- [ ] Root cause is clearly explained
- [ ] Fix rationale is documented
- [ ] Future developers can understand the issue

---

## Monitoring & Validation

### During Development

**Daily Checks:**
```bash
# Run full test suite
zig build test

# Quick SMB test
./zig-out/bin/RAMBO "Super Mario Bros. (World).nes"

# Quick AccuracyCoin check
./zig-out/bin/RAMBO tests/data/AccuracyCoin.nes
```

**After Each Code Change:**
```bash
# Run affected tests only
zig build test --filter <test-name>

# Run VBlank tests
zig build test --filter vblank

# Run CPU tests (if CPU fix)
zig build test --filter cpu
```

### Post-Deployment

**Validation Steps:**
1. Run full test suite (must pass 949+ tests)
2. Run AccuracyCoin (must pass 939/939)
3. Run Mario Bros (must work, no regression)
4. Run Super Mario Bros (must display title screen)
5. Play SMB level 1-1 (must complete without issues)
6. Test multiple play sessions (verify stability)

**Success Criteria:**
- ✅ All validation steps pass
- ✅ No visual glitches or timing issues
- ✅ Game is stable across multiple sessions
- ✅ No performance regressions

---

## Communication Plan

### Status Updates

**Daily Updates:**
- Update investigation doc session notes
- Document findings in real-time
- Track phase completion in checklist

**Milestone Updates:**
- Update this plan when phase completes
- Update KNOWN-ISSUES.md when fixed
- Update CLAUDE.md when project status changes

### Stakeholder Communication

**User Communication:**
- Update GitHub issues (if applicable)
- Post progress in community channels (if applicable)
- Document in changelog for release

**Developer Communication:**
- Keep investigation doc updated for context
- Document lessons learned for future reference
- Share findings in code comments

---

## Lessons Learned (Post-Mortem)

**To be filled after Phase 7 complete:**

### What Went Well

(Document successful aspects of investigation and fix)

### What Could Be Improved

(Document areas for improvement in process)

### Technical Insights

(Document technical learnings about NES hardware or emulation)

### Process Improvements

(Document process improvements for future investigations)

---

## Appendix

### Quick Reference Commands

**Build:**
```bash
zig build
```

**Run Full Tests:**
```bash
zig build test
```

**Run Specific Tests:**
```bash
zig build test --filter vblank
zig build test --filter cpu
zig build test --filter integration
```

**Debug SMB:**
```bash
# Break at NMI handler
./zig-out/bin/RAMBO "Super Mario Bros. (World).nes" \
  --break-at 0x8082 --inspect

# Break at stuck loop
./zig-out/bin/RAMBO "Super Mario Bros. (World).nes" \
  --break-at 0x8E6C --inspect

# Watch PPU registers
./zig-out/bin/RAMBO "Super Mario Bros. (World).nes" \
  --watch 0x2000,0x2001,0x2002 --inspect
```

**Run Known-Good ROM:**
```bash
./zig-out/bin/RAMBO "tests/data/Mario Bros (USA).nes"
```

**Run AccuracyCoin:**
```bash
./zig-out/bin/RAMBO tests/data/AccuracyCoin.nes
```

### File Locations

**Implementation Files:**
- `src/emulation/state/VBlankLedger.zig` - VBlank timing tracking
- `src/ppu/logic/registers.zig` - PPU register handlers
- `src/emulation/cpu/execution.zig` - CPU stepping and NMI detection
- `src/cpu/opcodes/` - CPU instruction implementations

**Test Files:**
- `tests/ppu/vblank_behavior_test.zig` - VBlank flag tests
- `tests/ppu/vblank_nmi_timing_test.zig` - NMI edge detection tests
- `tests/integration/smb_vblank_reproduction_test.zig` - SMB-specific tests
- `tests/integration/vblank_wait_test.zig` - Integration tests

**Documentation Files:**
- `docs/sessions/2025-10-12-vblank-nmi-investigation.md` - Investigation doc
- `docs/planning/vblank-nmi-fix-plan.md` - This document
- `docs/KNOWN-ISSUES.md` - Known issues tracking
- `CLAUDE.md` - Project overview

---

**Document Status:** Living document, update as plan progresses
**Owner:** Claude Code
**Last Updated:** 2025-10-12
**Next Review:** After Phase 2 complete
