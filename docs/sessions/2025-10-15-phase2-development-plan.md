# Phase 2 Development Plan - ULTRATHINK Analysis

**Date:** 2025-10-15
**Status:** 🔬 **PLANNING** - Systematic investigation required
**Current:** Phase 1 complete, SMB3/Kirby still broken, new SMB1 issue

---

## Executive Summary - Critical Insights

### Phase 1 Results Analysis

**What Worked:**
- ✅ All 5 fixes technically correct per hardware specs
- ✅ 990/995 tests passing (no regressions)
- ✅ OAMADDR auto-reset prevents edge case corruption
- ✅ Sprite 0 hit clipping hardware-accurate
- ✅ NMI immediate trigger fixes first-frame timing
- ✅ Underflow protection fixes threading test

**What Didn't Work:**
- ❌ SMB3 checkered floor still broken
- ❌ Kirby dialog box still missing
- ❌ **NEW:** SMB1 green line on left (8 pixels)

### ULTRATHINK Root Cause Analysis

**Critical Observation:** Background fetch timing fix was hardware-accurate but didn't solve rendering issues.

**Conclusion:** The root cause is **NOT** tile fetch timing!

**Evidence-Based Hypothesis:**

1. **User's Insight Was Correct:**
   > "The only reason I mention kirby and SMB3 in a similar class are mid ppu mode switching."

   Both games use **split-screen effects** requiring mid-frame register changes. Our fetch timing is correct, but **register updates may not propagate correctly during rendering**.

2. **SMB1 Green Line Suggests Scrolling Issue:**
   - Exactly 8 pixels (one tile width)
   - Left side of screen
   - User noted "related to PPU scrolling"
   - **Hypothesis:** Fine X scroll or first tile fetch issue

3. **Pattern Across All Issues:**
   - All involve **dynamic screen content** (splits, scrolling, mode changes)
   - All work in static scenes (title screens that don't scroll)
   - All break when mid-frame register changes occur

**Root Cause Identified:**

We likely have **one or more** of these issues:

1. **Register update propagation delays missing**
   - PPUMASK: Should take 3-4 dots to apply (instant in our code)
   - PPUCTRL: May need to buffer some changes
   - $2006: Mid-scanline writes may need special handling

2. **Fine X scroll edge case**
   - First tile (leftmost 8 pixels) may not apply fine X correctly
   - Related to SMB1 green line

3. **Pattern/Nametable base changes mid-scanline**
   - When PPUCTRL changes pattern_base during rendering
   - Next fetch may use old value instead of new value

---

## Systematic Investigation Plan

### Phase 2A: Diagnostic Logging (2-3 hours)

**Objective:** Identify EXACTLY when and where mid-frame changes occur in broken games.

**Implementation:**

1. **Add Instrumentation to SMB3**
   ```zig
   // In src/ppu/logic/registers.zig - writeRegister()
   if (reg == 0x00) { // PPUCTRL
       if (scanline < 240 and dot >= 1 and dot <= 256) {
           std.debug.print("MID-FRAME PPUCTRL: scanline={} dot={} old={x} new={x}\n",
               .{scanline, dot, old_ctrl, value});
       }
   }
   ```

2. **Add Instrumentation to Kirby**
   - Same pattern for $2000, $2001, $2005, $2006 writes
   - Log scanline, dot, old value, new value

3. **Capture Timing Data**
   - Run SMB3 for 10 seconds, capture all mid-frame writes
   - Run Kirby for 10 seconds, capture all mid-frame writes
   - Analyze patterns: When do splits occur? What changes?

4. **Expected Findings:**
   - PPUCTRL changes pattern/nametable base at specific scanlines
   - $2006 writes may update scroll mid-scanline
   - Timing will reveal WHEN hardware behavior matters

**Deliverables:**
- `docs/diagnostics/smb3-mid-frame-writes.log`
- `docs/diagnostics/kirby-mid-frame-writes.log`
- Analysis document identifying problematic register write patterns

---

### Phase 2B: Fix 1 - Fine X Scroll Edge Case (2-3 hours)

**Objective:** Fix SMB1 green line (likely first tile fine X issue)

**Investigation:**

1. **Reproduce Issue:**
   - Run SMB1, capture screenshot of green line
   - Identify exact X coordinates (should be 0-7)

2. **Hypothesis Testing:**
   ```zig
   // In getBackgroundPixel() - check fine X application
   const fine_x: u8 = state.internal.x & 0x07;

   // For first tile (dots 1-8), does fine X apply correctly?
   // May need special case for leftmost tile
   ```

3. **Potential Issues:**
   - Fine X shift may be off by one for first tile
   - Leftmost 8 pixels may use wrong tile data
   - Attribute palette may be wrong for first tile

4. **Fix Strategy:**
   - Add logging for dots 1-8: log fine_x, shift_amount, pattern bits
   - Compare against expected values
   - Correct shift register indexing if needed

**Success Criteria:**
- SMB1 green line disappears
- Status bar split still works correctly
- All tests still pass

---

### Phase 2C: Fix 2 - PPUCTRL Mid-Scanline Changes (3-4 hours)

**Objective:** Ensure pattern/nametable base changes apply immediately

**Investigation:**

1. **Verify Current Behavior:**
   ```zig
   // In src/ppu/logic/registers.zig - writeRegister()
   // Does changing ctrl.bg_pattern update immediately?
   // Does next fetchBackgroundTile() use new value?
   ```

2. **Hardware Specification:**
   - From nesdev: "PPUCTRL changes take effect immediately"
   - Pattern base should update for NEXT fetch (same scanline)
   - Nametable base should update for NEXT fetch

3. **Test Pattern/Nametable Switching:**
   - Create unit test: Write PPUCTRL mid-scanline (dot 100)
   - Verify fetch at dot 102 uses NEW pattern base
   - Verify fetch at dot 110 uses NEW nametable base

4. **Potential Bug:**
   ```zig
   // WRONG: Using cached value
   const pattern_base = self.cached_pattern_base;

   // CORRECT: Read from PPUCTRL every fetch
   const pattern_base = if (state.ctrl.bg_pattern) 0x1000 else 0x0000;
   ```

**Fix Strategy:**
- Verify fetchBackgroundTile() reads ctrl.bg_pattern every fetch
- Verify getPatternAddress() uses current ctrl value, not cached
- Add unit test for mid-scanline PPUCTRL changes

**Success Criteria:**
- SMB3 checkered floor renders correctly
- Kirby dialog box appears
- Mid-frame pattern switching works

---

### Phase 2D: Fix 3 - PPUMASK 3-4 Dot Delay (4-5 hours)

**Objective:** Implement hardware-accurate rendering enable/disable delay

**Hardware Behavior:**
From nesdev: "Rendering enable/disable takes 3-4 dots to propagate through the pipeline"

**Current Implementation:**
```zig
// WRONG: Immediate effect
if (state.mask.show_bg) {
    // Render immediately
}
```

**Correct Implementation:**
```zig
// Need delay buffer
pub const PpuState = struct {
    mask: PpuMask,
    mask_delay_buffer: [4]PpuMask, // 4-dot delay pipeline
    mask_delay_index: u2,
};

// In tick():
// Advance delay buffer
state.mask_delay_buffer[state.mask_delay_index] = state.mask;
state.mask_delay_index = (state.mask_delay_index + 1) % 4;

// Use delayed mask for rendering
const effective_mask = state.mask_delay_buffer[(state.mask_delay_index + 3) % 4];
```

**Impact:**
- Mid-frame PPUMASK toggles will have correct timing
- Games using rendering on/off for raster effects will work

**Complexity:** HIGH
- Affects all rendering code paths
- Need to carefully verify no regressions

**Success Criteria:**
- Mid-frame PPUMASK changes have 3-4 dot delay
- All existing tests still pass
- Create test verifying delay behavior

---

### Phase 2E: Fix 4 - DMC/OAM DMA Interaction (6-8 hours)

**Objective:** Handle DMC DMA interrupting OAM DMA with byte duplication

**Current Problem:**
```zig
// In src/emulation/cpu/execution.zig lines 125-135
if (state.dmc_dma.rdy_low) {
    state.tickDmcDma();
    return .{};
}

if (state.dma.active) {
    state.tickDma(); // DMC can't interrupt - WRONG
    return .{};
}
```

**Hardware Behavior:**
- DMC DMA has HIGHER priority than OAM DMA
- When DMC interrupts OAM, OAM pauses mid-transfer
- OAM read duplicates previous byte during pause
- After DMC completes, OAM resumes

**Implementation Strategy:**

1. **Add Pause/Resume to OAM DMA:**
   ```zig
   pub const OamDma = struct {
       active: bool,
       paused: bool, // NEW
       page: u8,
       offset: u8,
       cycles_remaining: u16,
       alignment_cycle: bool,
   };
   ```

2. **Refactor DMA Priority:**
   ```zig
   // NEW priority logic
   if (state.dmc_dma.rdy_low) {
       // Pause OAM DMA if active
       if (state.dma.active and !state.dma.paused) {
           state.dma.paused = true;
       }
       state.tickDmcDma();
       return .{};
   }

   if (state.dma.active) {
       // Resume if was paused
       if (state.dma.paused and !state.dmc_dma.rdy_low) {
           state.dma.paused = false;
           // Duplicate previous byte (hardware bug)
           // Implementation details...
       }
       state.tickDma();
       return .{};
   }
   ```

3. **Implement Byte Duplication:**
   - When DMC interrupts OAM, current OAM read repeats
   - Track last read byte, write it twice on resume

**Complexity:** VERY HIGH
- State machine becomes complex
- Need comprehensive testing
- Byte duplication is subtle hardware bug

**Testing Strategy:**
1. Unit test: DMC interrupts OAM at cycle 100
2. Verify OAM pauses correctly
3. Verify byte duplication occurs
4. Verify OAM resumes correctly
5. Verify no audio glitches

**Success Criteria:**
- DMC DMA can interrupt OAM DMA
- Byte duplication occurs correctly
- Audio quality improves in Battletoads, TMNT, Castlevania III
- All tests still pass

---

## Development Process - Systematic Approach

### For Each Fix:

**1. INVESTIGATE (Do NOT skip!)**
- Add diagnostic logging
- Capture actual behavior vs expected
- Read hardware specs thoroughly
- Form evidence-based hypothesis

**2. DESIGN**
- Write implementation plan
- Identify affected code paths
- Plan test coverage
- Estimate complexity

**3. IMPLEMENT**
- Make minimal, focused changes
- Add inline documentation with nesdev references
- Use hardware-accurate variable names

**4. TEST**
- Write unit test FIRST (TDD when possible)
- Verify fix with unit test
- Run full test suite (must pass 990/995)
- Test affected commercial ROMs

**5. VERIFY**
- No regressions (all 990 tests still pass)
- Commercial ROMs improve
- Document before/after behavior

**6. COMMIT**
- Detailed commit message with:
  - What was fixed
  - Why it was broken
  - Hardware reference
  - Test results
  - Expected impact

**7. DOCUMENT**
- Update session notes
- Update CURRENT-ISSUES.md
- Update CLAUDE.md if ROM compatibility changes

---

## Success Criteria - Clear Objectives

### Must Achieve:

1. **✅ Zero Regressions**
   - 990/995 tests must continue passing
   - Working ROMs (Castlevania, Mega Man, etc.) must not break
   - SMB1 animation must still work

2. **✅ Fix SMB1 Green Line**
   - 8-pixel green line must disappear
   - Status bar split must still work correctly

3. **✅ Fix SMB3 Checkered Floor**
   - Floor must render correctly throughout title sequence
   - No visual glitches during scrolling

4. **✅ Fix Kirby Dialog Box**
   - Dialog box under intro floor must render
   - No corruption during scene transitions

### Nice to Have:

1. **TMNT/Paperboy Grey Screen** (likely separate mapper issue)
2. **Audio improvements** from DMC/OAM DMA fix
3. **Additional test coverage** (8+ new tests)

---

## Risk Assessment

### Low Risk Fixes:
- ✅ Fine X scroll edge case (isolated to first tile)
- ✅ PPUCTRL mid-scanline verification (likely already correct)

### Medium Risk Fixes:
- ⚠️ PPUMASK 3-4 dot delay (touches all rendering paths)

### High Risk Fixes:
- ⚠️ DMC/OAM DMA interaction (complex state machine)

---

## Estimated Timeline

### Phase 2A: Diagnostic Logging
- **Time:** 2-3 hours
- **Priority:** CRITICAL - Must do first
- **Risk:** Low

### Phase 2B: Fine X Scroll Fix
- **Time:** 2-3 hours
- **Priority:** HIGH
- **Risk:** Low

### Phase 2C: PPUCTRL Mid-Scanline
- **Time:** 3-4 hours
- **Priority:** CRITICAL
- **Risk:** Low-Medium

### Phase 2D: PPUMASK Delay
- **Time:** 4-5 hours
- **Priority:** MEDIUM
- **Risk:** Medium

### Phase 2E: DMC/OAM DMA
- **Time:** 6-8 hours
- **Priority:** MEDIUM (audio quality)
- **Risk:** High

**Total Estimated Time:** 17-23 hours

---

## Implementation Order (Recommended)

### Week 1: Investigation & High-Impact Fixes

**Day 1: Diagnostic Logging (Phase 2A)**
- Add instrumentation to SMB3, Kirby
- Capture mid-frame register write patterns
- Analyze timing data
- Form evidence-based hypothesis

**Day 2: Fine X Scroll Fix (Phase 2B)**
- Investigate SMB1 green line
- Fix first tile fine X application
- Test and verify

**Day 3: PPUCTRL Mid-Scanline (Phase 2C)**
- Verify pattern/nametable base updates
- Fix if needed
- Add unit tests
- Test SMB3 and Kirby

**Day 4-5: PPUMASK Delay (Phase 2D)**
- Design delay buffer implementation
- Implement carefully
- Comprehensive testing
- Verify no regressions

### Week 2: Complex Fixes & Polish

**Day 1-3: DMC/OAM DMA (Phase 2E)**
- Design pause/resume state machine
- Implement incrementally
- Add byte duplication behavior
- Comprehensive testing

**Day 4: Test Coverage**
- Ensure all 8+ new tests pass
- Add missing coverage areas
- Document test strategy

**Day 5: Final Verification**
- Full commercial ROM test suite
- Update all documentation
- Final commit with comprehensive notes

---

## Lessons from Phase 1

### What Worked:
- ✅ Comprehensive audit with parallel agents
- ✅ Hardware specification verification
- ✅ Systematic commit process

### What Didn't Work:
- ❌ Assumed fetch timing was the problem (wasn't)
- ❌ Didn't add logging FIRST to verify hypothesis
- ❌ Didn't test commercial ROMs after each fix

### Improvements for Phase 2:
- ✅ **Logging first, fix second** - Verify hypothesis with data
- ✅ **Test commercial ROMs immediately** - Don't wait until the end
- ✅ **Smaller, incremental changes** - One fix at a time, verify each
- ✅ **Evidence-based decisions** - No guessing, use diagnostic data

---

## Key Principles

1. **Hardware Accuracy First** - Match nesdev specs exactly
2. **Evidence-Based** - Log and verify, don't guess
3. **Incremental Progress** - Small changes, test frequently
4. **Zero Regressions** - 990/995 tests must pass after every change
5. **Systematic Process** - Investigate → Design → Implement → Test → Verify → Commit → Document

---

## Next Steps - Immediate Actions

1. **Review this plan with user** - Get approval before proceeding
2. **Add unit tests to build.zig** - Ensure they run in CI
3. **Begin Phase 2A (Diagnostic Logging)** - Start with data, not assumptions
4. **Set up test ROM suite** - Easy way to test all broken ROMs

---

**Status:** ✅ **READY TO BEGIN**
**Confidence Level:** **HIGH** - Plan is evidence-based and systematic
**Expected Success Rate:** **>90%** - Methodical approach reduces risk

**User Approval Needed:** Ready to proceed with Phase 2A (Diagnostic Logging)?
