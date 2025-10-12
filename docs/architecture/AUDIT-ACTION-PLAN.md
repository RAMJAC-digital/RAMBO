# Architecture Documentation Audit - Action Plan

**Generated:** 2025-10-11
**Based on:** ARCHITECTURE-AUDIT-2025-10-11.md
**Priority:** Immediate actions required

---

## Quick Summary

**Documentation Accuracy:** 75% overall
**Files Audited:** 8 architecture documents
**Critical Issues:** 2 (threading.md, apu.md)
**Status:** NEEDS IMMEDIATE UPDATES

---

## Priority 1: Critical Updates (Do First)

### 1. Fix threading.md - CRITICAL CONTRADICTION

**Issue:** Document claims 2-thread implementation but source code shows 3 threads exist

**Current Claim:**
```
Line 12: "This document describes the **Phase 6 (current) 2-thread implementation**"
```

**Reality:**
```
Source files exist:
- /src/threads/EmulationThread.zig (14.5 KB)
- /src/threads/RenderThread.zig (4.7 KB)
- /src/main.zig (15.4 KB) - Main thread

Conclusion: 3-thread architecture is implemented
```

**Action Required:**
- [ ] Rewrite threading.md to document actual 3-thread implementation
- [ ] Remove "Phase 6" and "Phase 8" references
- [ ] Update mailbox documentation (remove "future" language)
- [ ] Document RenderThread.zig implementation
- [ ] Fix contradiction with codebase-inventory.md

**Estimated Time:** 2-3 hours

---

### 2. Update apu.md - OUTDATED COMPLETION STATUS

**Issue:** Claims 86% complete but all 135 APU tests passing (100% functional)

**Current Claim:**
```
Line 3: "**Status:** ✅ **86% COMPLETE** - Logic implemented, waveform generation pending"
```

**Reality:**
```
CLAUDE.md line 275: "APU | 135 | ✅ All passing"
All APU logic implemented and tested
Missing: Audio output to speakers (not emulation logic)
```

**Action Required:**
- [ ] Update completion percentage (86% → 100% emulation logic)
- [ ] Clarify "Missing Features" section:
  - Rename to "Future Enhancements (Not Blocking)"
  - Explain audio output != emulation accuracy
- [ ] Update status line to reflect functional completeness
- [ ] Add note: "Emulation: 100% ✅ | Audio Output: 0% (future)"

**Estimated Time:** 30 minutes

---

### 3. Verify Test Counts Across All Documentation

**Issue:** CLAUDE.md claims 955/967 passing but actual test runs show failures

**Current Claim (CLAUDE.md):**
```
Line 270: "**Total:** 955/967 tests passing (98.8%)"
```

**Actual Test Run:**
```
3 VBlank integration tests failing
Error: 'CPU-PPU Integration: Reading PPUSTATUS clears VBlank...'
```

**Action Required:**
- [ ] Run full test suite: `zig build test 2>&1 | tee test-output.txt`
- [ ] Count actual passing/failing tests
- [ ] Update CLAUDE.md test counts
- [ ] Document known failures in KNOWN-ISSUES.md
- [ ] Update all architecture docs referencing test counts

**Estimated Time:** 1 hour

---

## Priority 2: Important Updates (Do Soon)

### 4. Remove Phase References Globally

**Issue:** Confusing historical phase numbers throughout documentation

**Files Affected:**
- apu-frame-counter.md: "Phase 1.5"
- apu-length-counter.md: "Phase 1.5"
- apu-timing-analysis.md: "Phase 1.5.1", "Phase 1.5.2"
- threading.md: "Phase 6", "Phase 8"
- ppu-sprites.md: "Phase 7"

**Action Required:**
- [ ] Global find/replace:
  - "Phase 1.5" → "Implementation" or remove
  - "Phase 6" → remove (document current state)
  - "Phase 7" → remove (sprites implemented)
  - "Phase 8" → remove (video implemented)
- [ ] Replace with status labels:
  - ✅ Complete
  - 🚧 In Progress
  - 📋 Planned
- [ ] Update CLAUDE.md roadmap if it exists

**Estimated Time:** 1-2 hours

---

### 5. Update Implementation Checklists

**Issue:** Multiple docs have unchecked implementation items that are complete

**Files with Outdated Checklists:**
- apu-frame-counter.md (lines 203-221)
- apu-length-counter.md (lines 360-485)
- ppu-sprites.md (lines 365-398)

**Action Required:**
- [ ] Mark all completed items with ✅
- [ ] Convert "Implementation Checklist" to "Verification Completed"
- [ ] Remove checklists for fully implemented features
- [ ] Add note: "All items implemented and tested"

**Estimated Time:** 30 minutes

---

## Priority 3: Long-Term Improvements (When Time Permits)

### 6. Create Missing Architecture Documents

**Gaps Identified:**

1. **ppu-vblank-timing.md** (CRITICAL BUG AREA)
   - VBlankLedger implementation details
   - NMI edge detection mechanism
   - $2002 read timing and flag clearing
   - Current bug: "VBlank flag race condition"
   - Test failures: 3 VBlank integration tests

2. **testing/accuracycoin.md**
   - What AccuracyCoin validates
   - RAMBO integration details
   - Passing/failing test categories

3. **rt-safety.md**
   - RT-safety definition for RAMBO
   - Which code paths must be RT-safe
   - Allocation tracking and validation
   - Performance guarantees

4. **debugger-architecture.md**
   - RT-safe debugging design
   - Breakpoint/watchpoint implementation
   - Performance impact on emulation

**Estimated Time:** 6-8 hours total

---

### 7. Document Design Patterns

**Needed Documentation:**

1. **design-patterns/state-logic-separation.md**
   - Rationale for pattern
   - Benefits: RT-safety, testability, determinism
   - Trade-offs and limitations
   - Before/after examples

2. **design-patterns/comptime-generics.md**
   - Performance comparison: comptime vs runtime
   - Cartridge(MapperType) pattern explained
   - Limitations and gotchas

3. **design-patterns/mailbox-communication.md**
   - Lock-free SPSC design
   - Producer/consumer patterns
   - Thread coordination strategies

**Estimated Time:** 4-6 hours total

---

### 8. Create Architecture Decision Records (ADRs)

**Document Key Decisions:**

- **ADR-001:** Why 3-thread architecture instead of 2 or 4?
- **ADR-002:** Why State/Logic separation pattern?
- **ADR-003:** Why libxev for event loops?
- **ADR-004:** Why comptime generics for mappers?
- **ADR-005:** Why lock-free mailboxes over channels?

**Estimated Time:** 2-3 hours total

---

## Quick Wins (< 15 minutes each)

These can be done immediately for quick improvements:

1. **Update apu.md Status Line**
   ```diff
   - **Status:** ✅ **86% COMPLETE** - Logic implemented, waveform generation pending
   + **Status:** ✅ **EMULATION COMPLETE** - All logic tested (135/135 passing) | Audio output pending
   ```

2. **Fix threading.md Opening Warning**
   ```diff
   - > This document describes the **Phase 6 (current) 2-thread implementation**.
   + > This document describes the **current 3-thread implementation** (Main + Emulation + Render).
   ```

3. **Add Clarification to apu.md**
   ```markdown
   ## Current Status

   **Emulation Logic:** 100% complete ✅ (135/135 tests passing)
   **Audio Output:** Not implemented (future enhancement)

   The APU is fully functional for cycle-accurate emulation. Missing audio output
   means the emulator runs silently but with perfect timing accuracy.
   ```

4. **Update codebase-inventory.md Thread Count**
   ```diff
   - **3-Thread Mailbox Pattern:**
   + **Current Architecture (3 Threads):**
   ```

5. **Archive Research Documents**
   - Move apu-irq-flag-verification.md to `docs/architecture/archive/`
   - Add note: "Historical research - Implementation verified and complete"

---

## Verification Checklist

After completing Priority 1 and 2 updates, verify:

- [ ] threading.md accurately describes 3-thread implementation
- [ ] No contradiction between threading.md and codebase-inventory.md
- [ ] apu.md completion status matches test reality (135/135 passing)
- [ ] All test counts in documentation match actual test runs
- [ ] No confusing "Phase X" references in user-facing docs
- [ ] Implementation checklists marked complete or removed
- [ ] CLAUDE.md reflects current project state

---

## Timeline Estimate

**Priority 1 (Critical):**
- threading.md rewrite: 2-3 hours
- apu.md updates: 30 minutes
- Test count verification: 1 hour
- **Total:** ~4 hours

**Priority 2 (Important):**
- Phase reference removal: 1-2 hours
- Checklist updates: 30 minutes
- **Total:** ~2 hours

**Priority 3 (Long-term):**
- New architecture docs: 6-8 hours
- Design pattern docs: 4-6 hours
- ADRs: 2-3 hours
- **Total:** ~15 hours

**Grand Total:** ~21 hours for complete documentation overhaul

---

## Success Metrics

Documentation will be considered "current and accurate" when:

1. ✅ No contradictions between architecture documents
2. ✅ Completion percentages match test reality
3. ✅ Thread architecture documented correctly (3-thread)
4. ✅ All test counts accurate and up-to-date
5. ✅ No confusing phase references
6. ✅ Implementation checklists reflect reality
7. ✅ Major architectural decisions documented
8. ✅ VBlank bug has architecture documentation

---

## Notes

- **Don't Delay Priority 1:** Critical contradictions confuse developers
- **Quick Wins First:** Build momentum with 15-minute fixes
- **Verify Before Committing:** Run tests after documentation updates
- **Keep CLAUDE.md Current:** It's the main reference for developers

---

**Action Plan Owner:** agent-docs-architect-pro
**Review Date:** After VBlank bug fix
**Next Audit:** After all Priority 1 and 2 items complete
