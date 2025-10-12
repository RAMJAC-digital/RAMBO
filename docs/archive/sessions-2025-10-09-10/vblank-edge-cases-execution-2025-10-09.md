# VBlank Edge Cases Fix - Execution Log
**Started:** 2025-10-09
**Status:** In Progress
**Related:** vblank-edge-cases-plan-2025-10-09.md, gemini-review-2025-10-09.md

## Plan Approval

**Date:** 2025-10-09
**Approved By:** User
**Scope:** Fix 3 failing VBlank/NMI edge case tests

### User Decisions

**Q1: Test Philosophy** → A) Fix implementation to match hardware ✓
**Q2: CPU State Machine** → B) Gather info, create separate issue (likely test harness)
**Q3: AccuracyCoin Test** → A) Fix if obvious (may continue failing for other reasons)
**Q4: Debug Logging** → Extend as needed, remove before commit
**Q5: Commit Strategy** → A) One atomic commit (unless phase needs breakout)

### Key Insights from User

1. **Test Harness Issue:** `seekToScanlineDot()` should **advance** emulator tick-by-tick, not teleport. Integration tests depend on proper state progression.
2. **AccuracyCoin Expectation:** NMI/PPU fixes may not fully resolve this test - ROMs should behave correctly even if test continues failing.
3. **Debugging Tools:** Can run ROMs with debugger (main.zig) to dump memory/registers without full recompile.
4. **Test Output:** Save to `/tmp` for time-saving during development.

---

## Execution Phases

### Phase 0: Fix VBlankLedger Test Compilation ✓ (Target: 30 min)
- [ ] Update test code to match new VBlankLedger API
- [ ] Fix parameter mismatches in recordVBlankSet(), recordCtrlToggle()
- [ ] Remove references to deleted ctrl_nmi_enabled field
- [ ] Verify compilation succeeds

### Phase 1: VBlank Detection Investigation & Fix (Target: 3h)
- [ ] Enable DEBUG_VBLANK and DEBUG_PPUSTATUS flags
- [ ] Run failing test with logging: `zig build test 2>&1 | tee /tmp/vblank-test-1.log`
- [ ] Analyze VBlank set/clear cycles
- [ ] Fix implementation based on findings
- [ ] Run test suite: `zig build test 2>&1 | tee /tmp/vblank-test-2.log`

### Phase 2: CPU State Machine Investigation (Target: 1h)
- [ ] Investigate test harness `seekToScanlineDot()` implementation
- [ ] Document issue: Should advance tick-by-tick, not teleport
- [ ] Gather diagnostic information for separate issue
- [ ] Create issue file in docs/issues/

### Phase 3: NMI Race Condition Fix (Target: 4h)
- [ ] Implement timestamp-based NMI latch
- [ ] Update applyPpuCycleResult() to use ledger
- [ ] Track $2002 reads in ledger
- [ ] Remove refreshPpuNmiLevel() dependency
- [ ] Test NMI edge detection with PPUCTRL.7 toggles

### Phase 4: AccuracyCoin Rendering Test (Target: 1.5h)
- [ ] Add PPUMASK write logging
- [ ] Run test: `zig build test-integration 2>&1 | tee /tmp/accuracycoin-test.log`
- [ ] Identify when ROM writes $2001
- [ ] Fix if obvious, otherwise document expected behavior

### Phase 5: Cleanup (Target: 1h)
- [ ] Remove all debug logging (DEBUG_VBLANK, DEBUG_PPUSTATUS)
- [ ] Verify no debug artifacts in code
- [ ] Run full test suite: `zig build test 2>&1 | tee /tmp/final-test.log`

### Phase 6: Documentation (Target: 2h)
- [ ] Update KNOWN-ISSUES.md with resolved items
- [ ] Update nmi-timing-implementation-log-2025-10-09.md
- [ ] Create docs/implementation/vblank-nmi-timing.md
- [ ] Document VBlankLedger architecture
- [ ] Add inline documentation

### Phase 7: Final Validation & Commit (Target: 30 min)
- [ ] Run full test suite
- [ ] Verify no regressions
- [ ] Commit with detailed message
- [ ] Update this execution log with results

---

## Findings & Notes

### Phase 0 Notes
*To be filled during execution*

### Phase 1 Notes
*To be filled during execution*

### Phase 2 Notes
*To be filled during execution*

### Phase 3 Notes
*To be filled during execution*

### Phase 4 Notes
*To be filled during execution*

---

## Success Criteria

**Primary:**
- ✅ 960+/966 tests passing (99.4%+)
- ✅ VBlank/NMI race conditions resolved
- ✅ No regressions

**Secondary:**
- ✅ Clean code (no debug artifacts)
- ✅ Comprehensive documentation
- ✅ Single atomic commit

---

## Time Tracking

| Phase | Planned | Actual | Notes |
|-------|---------|--------|-------|
| Phase 0 | 0.5h | TBD | |
| Phase 1 | 3h | TBD | |
| Phase 2 | 1h | TBD | |
| Phase 3 | 4h | TBD | |
| Phase 4 | 1.5h | TBD | |
| Phase 5 | 1h | TBD | |
| Phase 6 | 2h | TBD | |
| Phase 7 | 0.5h | TBD | |
| **Total** | **14h** | **TBD** | |

---

## Completion Status

**Status:** IN PROGRESS
**Started:** 2025-10-09
**Completed:** TBD
**Final Test Results:** TBD
**Commit SHA:** TBD
