# Phase 2 Comprehensive Development Plan - FINAL

**Date:** 2025-10-15
**Status:** 🔵 **READY FOR IMPLEMENTATION**
**Estimated Total Time:** 17-23 hours
**Priority:** CRITICAL - Fixes remaining commercial ROM issues

---

## Executive Summary

Phase 2 addresses mid-frame register update timing issues identified after Phase 1 hardware accuracy fixes. Through systematic investigation, we've confirmed that the remaining rendering issues (SMB3 checkered floor, Kirby dialog box, SMB1 green line) are caused by **mid-frame register propagation delays** and **edge cases in scrolling/rendering logic**.

### Investigation Results

**✅ Phase 2A: COMPLETED** - Diagnostic logging revealed:
- SMB3/Kirby use split-screen effects requiring mid-scanline PPUCTRL changes
- SMB1 has 8-pixel green line on left edge (fine X scroll or first tile issue)
- All issues involve dynamic content, not static scenes

**✅ Phase 2E: INVESTIGATION COMPLETED** - DMC/OAM DMA interaction:
- Hardware research confirmed byte duplication behavior
- Current architecture analysis identified sequential priority bug
- Test strategy designed (33+ comprehensive tests)
- Implementation approach selected (Option A - Minimal Changes)

**🔵 READY:** Phases 2B, 2C, 2D, 2E - All have clear implementation plans

---

## Development Order (Recommended)

### Week 1: High-Impact Rendering Fixes

**Phase 2B: Fine X Scroll Edge Case** (2-3 hours)
**Phase 2C: PPUCTRL Mid-Scanline** (3-4 hours)
**Phase 2D: PPUMASK 3-4 Dot Delay** (4-5 hours)

**Total Week 1:** 9-12 hours

### Week 2: Complex DMA Fix

**Phase 2E: DMC/OAM DMA Interaction** (6-8 hours)

**Total Week 2:** 6-8 hours

**Grand Total:** 15-20 hours

---

## Phase 2B: Fine X Scroll Edge Case

### Objective
Fix SMB1 green line on left side of screen (8 pixels wide).

### Root Cause Hypothesis
Fine X scroll not applied correctly to first tile (leftmost 8 pixels). This is an edge case in the background rendering pipeline where the first tile may use wrong shift register indexing.

### Implementation Steps

**Step 1: Reproduce and Document (30 min)**
```bash
# Run SMB1, capture screenshot
./zig-out/bin/RAMBO roms/smb1.nes --screenshot smb1-green-line.png

# Identify exact X coordinates (should be 0-7)
# Document visible artifacts
```

**Step 2: Add Diagnostic Logging (30 min)**
```zig
// In src/ppu/logic/background.zig - getBackgroundPixel()
if (dot >= 1 and dot <= 8) {
    const fine_x = state.internal.x & 0x07;
    std.debug.print("FIRST_TILE: dot={d} fine_x={d} shift_hi={x:0>2} shift_lo={x:0>2}\n",
        .{dot, fine_x, state.bg_state.pattern_shift_hi >> 8, state.bg_state.pattern_shift_lo >> 8});
}
```

**Step 3: Investigate Shift Register Indexing (1 hour)**
```zig
// Current implementation (VERIFY THIS):
const pixel_offset = (15 - fine_x);
const pattern_hi_bit = (state.bg_state.pattern_shift_hi >> pixel_offset) & 0x01;
const pattern_lo_bit = (state.bg_state.pattern_shift_lo >> pixel_offset) & 0x01;

// Potential issues:
// 1. First tile may need special case (fine_x = 0 at dot 1?)
// 2. Shift register may not be loaded for dots 1-8
// 3. Attribute palette may be wrong for first tile
```

**Step 4: Create Unit Test (30 min)**
```zig
// tests/ppu/fine_x_first_tile_test.zig
test "Fine X scroll: First tile renders correctly with fine_x = 4" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Setup: Scroll position with fine X = 4
    // Verify: First 8 pixels use correct tile data
    // Verify: Fine X offset applied correctly
}
```

**Step 5: Implement Fix (30 min)**
Based on diagnostic findings, likely fix is one of:
1. Special case for first tile (dots 1-8)
2. Correct shift register indexing
3. Load shift registers earlier for first tile

**Step 6: Test and Verify (30 min)**
```bash
# Run new test
zig build test-unit

# Test SMB1 (green line should disappear)
./zig-out/bin/RAMBO roms/smb1.nes

# Run full test suite (must be 990/995)
zig build test
```

### Success Criteria
- ✅ SMB1 green line disappears
- ✅ Status bar split still works correctly
- ✅ All 990 tests still pass
- ✅ New test passes

### Files Modified
- `src/ppu/logic/background.zig` - Fine X shift register logic
- `tests/ppu/fine_x_first_tile_test.zig` - **NEW**

### Risk Assessment
**Risk Level:** LOW
**Reason:** Isolated to first tile rendering, unlikely to affect other games
**Mitigation:** Comprehensive testing, easy to revert if issues

---

## Phase 2C: PPUCTRL Mid-Scanline Changes

### Objective
Ensure pattern/nametable base changes in PPUCTRL apply immediately to next fetch, fixing SMB3 checkered floor and Kirby dialog box.

### Root Cause Hypothesis
When PPUCTRL changes `bg_pattern` or `nametable_base` mid-scanline, the next tile fetch may use a cached value instead of the new value from PPUCTRL.

### Implementation Steps

**Step 1: Verify Current Behavior (1 hour)**
```zig
// In src/ppu/logic/registers.zig - writeRegister()
pub fn writeRegister(state: *PpuState, cart: ?*AnyCartridge, reg: u3, value: u8) void {
    if (reg == 0x00) { // PPUCTRL
        const old_ctrl = state.ctrl;
        state.ctrl = PpuCtrl.fromByte(value);

        // ADD LOGGING:
        if (scanline < 240 and dot >= 1 and dot <= 256) {
            std.debug.print("MID-SCANLINE PPUCTRL: sl={d} dot={d} old_pattern={} new_pattern={}\n",
                .{scanline, dot, old_ctrl.bg_pattern, state.ctrl.bg_pattern});
        }
    }
}

// In src/ppu/logic/background.zig - fetchBackgroundTile()
// VERIFY: Does this read ctrl.bg_pattern every fetch, or cache it?
const pattern_base = if (state.ctrl.bg_pattern) 0x1000 else 0x0000;
```

**Step 2: Create Unit Test (1 hour)**
```zig
// tests/ppu/ppuctrl_mid_scanline_test.zig
test "PPUCTRL: Pattern base change applies to next fetch" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Setup: Rendering enabled, scanline 0
    harness.setPpuTiming(0, 100);
    state.ctrl.bg_pattern = false; // Pattern table 0

    // ACT: Change to pattern table 1 mid-scanline
    harness.ppuWriteRegister(0x2000, 0x10); // PPUCTRL bit 4 = 1

    // Advance to next fetch cycle (dot 102)
    harness.tickPpuCycles(2);

    // ASSERT: Next fetch uses pattern table 1
    // (verify via VRAM read address)
}

test "PPUCTRL: Nametable base change applies to next fetch" {
    // Similar test for nametable base switching
}
```

**Step 3: Audit Background Fetch Logic (1 hour)**
```zig
// Review src/ppu/logic/background.zig
// Check all pattern/nametable address calculations
// Ensure they read from state.ctrl DIRECTLY, not cached values

// Example of CORRECT implementation:
pub fn getPatternAddress(state: *PpuState, high_byte: bool) u16 {
    const pattern_base = if (state.ctrl.bg_pattern) 0x1000 else 0x0000;
    // Use pattern_base immediately, don't cache
}

// Example of WRONG implementation:
// DON'T DO THIS:
const cached_pattern_base = self.pattern_base; // WRONG - stale value
```

**Step 4: Implement Fix (if needed) (30 min)**
If caching is found, remove it and read `state.ctrl` directly every fetch.

**Step 5: Test Commercial ROMs (30 min)**
```bash
# SMB3 - Checkered floor should stay visible
./zig-out/bin/RAMBO roms/smb3.nes

# Kirby - Dialog box should render
./zig-out/bin/RAMBO roms/kirby.nes

# Full test suite
zig build test
```

### Success Criteria
- ✅ SMB3 checkered floor renders correctly throughout title sequence
- ✅ Kirby dialog box appears under intro floor
- ✅ All 990 tests still pass
- ✅ 2+ new tests pass

### Files Modified
- `src/ppu/logic/background.zig` - Remove any caching (if present)
- `tests/ppu/ppuctrl_mid_scanline_test.zig` - **NEW**

### Risk Assessment
**Risk Level:** MEDIUM
**Reason:** Changes affect core rendering pipeline
**Mitigation:** Unit tests verify behavior, easy to revert
**Expected Impact:** HIGH - Likely fixes both SMB3 and Kirby

---

## Phase 2D: PPUMASK 3-4 Dot Delay

### Objective
Implement hardware-accurate 3-4 dot propagation delay when rendering is enabled/disabled via PPUMASK.

### Root Cause
PPUMASK changes take effect immediately in current implementation. Hardware has a 3-4 dot pipeline delay before rendering actually starts/stops.

### Implementation Steps

**Step 1: Design Delay Buffer (1 hour)**
```zig
// In src/ppu/State.zig
pub const PpuState = struct {
    mask: PpuMask,

    // NEW: 4-dot delay pipeline
    mask_delay_buffer: [4]PpuMask = [_]PpuMask{PpuMask{}} ** 4,
    mask_delay_index: u2 = 0,

    // ... rest of fields
};
```

**Step 2: Implement Delay Logic (1-2 hours)**
```zig
// In src/ppu/Logic.zig - tick()
pub fn tick(state: *PpuState, scanline: u16, dot: u16, cart: ?*AnyCartridge, framebuffer: ?[]u32) TickResult {
    // Advance delay buffer FIRST (at start of dot)
    state.mask_delay_buffer[state.mask_delay_index] = state.mask;
    state.mask_delay_index = (state.mask_delay_index + 1) % 4;

    // Use delayed mask for rendering (3-4 dots ago)
    const effective_mask = state.mask_delay_buffer[(state.mask_delay_index + 3) % 4];

    // Pass effective_mask to rendering functions instead of state.mask
    if (effective_mask.show_bg) {
        // Render background
    }
    if (effective_mask.show_sprites) {
        // Render sprites
    }
}
```

**Step 3: Update All Rendering Code Paths (1-2 hours)**
```zig
// Files to update:
// - src/ppu/logic/background.zig - Use effective_mask
// - src/ppu/logic/sprites.zig - Use effective_mask
// - src/ppu/Logic.zig - Pass effective_mask to all rendering functions

// Example:
pub fn renderPixel(state: *PpuState, effective_mask: PpuMask, ...) {
    if (effective_mask.show_bg) {
        // Background rendering
    }
}
```

**Step 4: Create Comprehensive Tests (1 hour)**
```zig
// tests/ppu/ppumask_delay_test.zig
test "PPUMASK: Rendering enable has 3-4 dot delay" {
    var harness = try Harness.init();
    defer harness.deinit();

    // Disable rendering
    harness.ppuWriteRegister(0x2001, 0x00);
    harness.tickPpuCycles(10);

    // Enable rendering at dot 100
    harness.setPpuTiming(10, 100);
    harness.ppuWriteRegister(0x2001, 0x18); // Enable BG+sprites

    // Rendering should NOT start immediately
    // Check dots 100, 101, 102 - no rendering
    // Check dot 104 - rendering starts (4-dot delay)
}

test "PPUMASK: Rendering disable has 3-4 dot delay" {
    // Similar test for disable
}

test "PPUMASK: Multiple rapid changes queue correctly" {
    // Stress test - toggle on/off every 2 dots
    // Verify pipeline behavior
}
```

**Step 5: Regression Testing (1 hour)**
```bash
# Run full test suite
zig build test

# Test all commercial ROMs
./zig-out/bin/RAMBO roms/smb1.nes
./zig-out/bin/RAMBO roms/smb3.nes
./zig-out/bin/RAMBO roms/castlevania.nes
# etc.

# Look for rendering glitches
```

### Success Criteria
- ✅ Mid-frame PPUMASK changes have 3-4 dot delay
- ✅ All 990 tests still pass
- ✅ 3+ new tests pass
- ✅ No rendering regressions in working games

### Files Modified
- `src/ppu/State.zig` - Add delay buffer
- `src/ppu/Logic.zig` - Implement delay logic
- `src/ppu/logic/background.zig` - Use effective_mask
- `src/ppu/logic/sprites.zig` - Use effective_mask
- `tests/ppu/ppumask_delay_test.zig` - **NEW**

### Risk Assessment
**Risk Level:** HIGH
**Reason:** Affects ALL rendering code paths
**Mitigation:**
- Comprehensive testing before/after
- Incremental implementation (delay buffer first, then integrate)
- Easy to revert if major issues found

**Recommended:** Implement AFTER 2B and 2C are verified working

---

## Phase 2E: DMC/OAM DMA Interaction

### Objective
Implement hardware-accurate DMC DMA interruption of OAM DMA with byte duplication behavior.

### Investigation Summary (COMPLETED)

**Hardware Behavior:**
- DMC DMA has highest priority (can interrupt OAM DMA)
- OAM DMA pauses during DMC interrupt (does not cancel)
- Byte being read during interruption duplicates on resume
- Total cycles = OAM base (513/514) + (DMC_count × 4)

**Current Architecture Issues:**
- Sequential priority (DMC blocks OAM completely)
- No pause/resume mechanism
- No byte duplication logic

**Selected Approach:** Option A - Minimal Changes

### Implementation Steps

**Step 1: Add Pause State (1 hour)**
```zig
// In src/emulation/state/peripherals/OamDma.zig
pub const OamDma = struct {
    active: bool = false,
    paused: bool = false, // NEW - DMC has control

    source_page: u8 = 0,
    current_offset: u8 = 0,
    current_cycle: u16 = 0,
    needs_alignment: bool = false,
    temp_value: u8 = 0,

    last_read_byte: u8 = 0, // NEW - for duplication on resume
    was_reading_when_paused: bool = false, // NEW - track phase
};
```

**Step 2: Refactor DMA Priority Logic (2 hours)**
```zig
// In src/emulation/cpu/execution.zig - stepCycle()

// BEFORE (lines 125-135):
if (state.dmc_dma.rdy_low) {
    state.tickDmcDma();
    return .{};
}
if (state.dma.active) {
    state.tickDma();
    return .{};
}

// AFTER:
if (state.dmc_dma.rdy_low) {
    // Pause OAM if active and not already paused
    if (state.dma.active and !state.dma.paused) {
        // Track if we're pausing during read phase
        const effective_cycle = if (state.dma.needs_alignment)
            state.dma.current_cycle - 1
            else state.dma.current_cycle;

        state.dma.was_reading_when_paused = (effective_cycle % 2 == 0);
        state.dma.paused = true;
    }

    state.tickDmcDma();
    return .{};
}

if (state.dma.active) {
    // Resume if was paused
    if (state.dma.paused and !state.dmc_dma.rdy_low) {
        state.dma.paused = false;

        // Byte duplication: If paused during read, duplicate last_read_byte
        if (state.dma.was_reading_when_paused) {
            // Write the byte that was being read when interrupted
            state.ppu.oam[state.ppu.oam_addr] = state.dma.last_read_byte;
            state.ppu.oam_addr +%= 1;
            state.dma.current_offset +%= 1;

            // Continue to next cycle (skip the interrupted read)
            state.dma.current_cycle += 1;
        }
    }

    state.tickDma();
    return .{};
}
```

**Step 3: Update OAM DMA Tick Logic (1 hour)**
```zig
// In src/emulation/dma/logic.zig - tickOamDma()

pub fn tickOamDma(state: anytype) void {
    // Don't tick if paused
    if (state.dma.paused) {
        return;
    }

    // ... rest of existing logic ...

    if (effective_cycle % 2 == 0) {
        // Even cycle: Read from CPU RAM
        const source_addr = (@as(u16, state.dma.source_page) << 8) |
                           @as(u16, state.dma.current_offset);
        state.dma.temp_value = state.busRead(source_addr);

        // NEW: Track last read for potential duplication
        state.dma.last_read_byte = state.dma.temp_value;
    } else {
        // Odd cycle: Write to PPU OAM
        state.ppu.oam[state.ppu.oam_addr] = state.dma.temp_value;
        state.ppu.oam_addr +%= 1;
        state.dma.current_offset +%= 1;
    }
}
```

**Step 4: Create Comprehensive Test Suite (3 hours)**
```zig
// tests/integration/dmc_oam_conflict_test.zig - 33+ tests

test "DMC interrupts OAM at byte 0 (start)" { /* ... */ }
test "DMC interrupts OAM at byte 128 (middle)" { /* ... */ }
test "DMC interrupts OAM at byte 255 (end)" { /* ... */ }
test "Byte duplication verification with unique pattern" { /* ... */ }
test "Multiple DMC interrupts during single OAM" { /* ... */ }
test "Total cycle count: 513 + (3 × 4) = 525" { /* ... */ }
// ... 27 more tests (see test strategy document)
```

**Step 5: Debug and Refine (2-3 hours)**
- Run test suite iteratively
- Fix failures one by one
- Use debug logging to trace state
- Verify cycle-accurate timing

**Step 6: Commercial ROM Testing (1 hour)**
```bash
# Audio-heavy games (DMC + sprites)
./zig-out/bin/RAMBO roms/battletoads.nes
./zig-out/bin/RAMBO roms/castlevania3.nes
./zig-out/bin/RAMBO roms/tmnt.nes

# Listen for audio quality improvements
# Check for sprite corruption fixes
```

### Success Criteria
- ✅ DMC DMA can interrupt OAM DMA
- ✅ OAM DMA pauses during DMC interrupt
- ✅ Byte duplication occurs on resume
- ✅ All existing tests still pass (990/995)
- ✅ All 33+ new tests pass
- ✅ Audio quality improved in DMC-heavy games

### Files Modified
- `src/emulation/state/peripherals/OamDma.zig` - Add pause state
- `src/emulation/cpu/execution.zig` - Refactor priority logic
- `src/emulation/dma/logic.zig` - Update tick logic
- `tests/integration/dmc_oam_conflict_test.zig` - **NEW** (33+ tests)
- `build/tests.zig` - Register new tests

### Risk Assessment
**Risk Level:** HIGH
**Reason:** Complex state machine with subtle timing
**Mitigation:**
- Comprehensive 33-test suite designed in advance
- Incremental implementation with testing after each step
- Option A (minimal changes) reduces complexity
- Can defer if too complex (Fallback Plan exists)

**Recommended:** Implement LAST (after 2B, 2C, 2D verified)

---

## Overall Timeline

### Week 1: Rendering Fixes (9-12 hours)

**Day 1: Phase 2B - Fine X Scroll** (2-3 hours)
- Morning: Reproduce issue, add logging
- Afternoon: Implement fix, test

**Day 2: Phase 2C - PPUCTRL Mid-Scanline** (3-4 hours)
- Morning: Verify current behavior, create tests
- Afternoon: Implement fix (if needed), test commercial ROMs

**Day 3-4: Phase 2D - PPUMASK Delay** (4-5 hours)
- Day 3 AM: Design delay buffer
- Day 3 PM: Implement delay logic
- Day 4 AM: Update rendering paths
- Day 4 PM: Test and verify

### Week 2: DMA Fix (6-8 hours)

**Day 1: Phase 2E Part 1** (3 hours)
- Add pause state
- Refactor priority logic
- Update tick logic

**Day 2: Phase 2E Part 2** (3-4 hours)
- Create test suite (33+ tests)
- Debug and refine
- Commercial ROM testing

**Day 3: Final Verification** (30 min - 1 hour)
- Full test suite (must be 990/995)
- All commercial ROMs
- Document results

---

## Success Criteria - Complete Phase 2

### Must Achieve (P0)

1. **✅ Zero Regressions**
   - 990/995 tests continue passing
   - Working ROMs don't break
   - SMB1 animation still works

2. **✅ Fix SMB1 Green Line** (Phase 2B)
   - 8-pixel green line disappears
   - Status bar split still works

3. **✅ Fix SMB3 Checkered Floor** (Phase 2C)
   - Floor renders correctly throughout title
   - No visual glitches during scrolling

4. **✅ Fix Kirby Dialog Box** (Phase 2C)
   - Dialog box renders under intro floor
   - No corruption during scene transitions

5. **✅ Implement PPUMASK Delay** (Phase 2D)
   - 3-4 dot delay measured and verified
   - No rendering regressions

6. **✅ Implement DMC/OAM DMA** (Phase 2E)
   - DMC can interrupt OAM
   - Byte duplication occurs correctly
   - 33+ new tests pass

### Should Achieve (P1)

1. **Audio quality improvements** from DMC/OAM fix
2. **8+ new tests** added and passing
3. **Documentation updates** for all changes
4. **Commit messages** with detailed explanations

### Nice to Have (P2)

1. **Visual before/after screenshots** for each fix
2. **Performance benchmarking** (no slowdown)
3. **Additional test coverage** beyond requirements

---

## Risk Mitigation Strategies

### For Each Phase

**Before Starting:**
1. Review this plan thoroughly
2. Ensure current git status is clean
3. Run baseline tests (verify 990/995)
4. Read relevant hardware documentation

**During Implementation:**
1. Test incrementally after each change
2. Use diagnostic logging to verify hypotheses
3. Commit at logical checkpoints
4. Don't proceed if tests start failing

**After Completion:**
1. Run full test suite
2. Test all commercial ROMs
3. Document findings
4. Update session notes

### Fallback Plans

**If Phase 2B fails:**
- Document findings
- Defer to later investigation
- May be related to Phase 2C (proceed to 2C)

**If Phase 2C fails:**
- Likely already correct (caching not used)
- Document verification
- Mark as "verified correct, no changes needed"

**If Phase 2D fails:**
- High risk of regressions
- Revert immediately if tests fail
- Defer to Phase 3 (lower priority)

**If Phase 2E fails:**
- Most complex phase
- Can defer entirely (audio quality nice-to-have)
- Partial implementation option (priority only, no duplication)
- Consult reference implementations (Mesen)

---

## Testing Requirements

### Test Pyramid

**Unit Tests (15-20 new tests):**
- Fine X scroll edge cases (2-3 tests)
- PPUCTRL mid-scanline (2-3 tests)
- PPUMASK delay timing (3-4 tests)
- DMC/OAM interaction (8-10 tests)

**Integration Tests (15-20 new tests):**
- Commercial ROM scenarios (3-5 tests)
- DMC/OAM multiple interruptions (4-6 tests)
- Complex timing sequences (5-8 tests)

**Regression Tests:**
- All existing 990 tests must pass
- No new failures allowed
- Working commercial ROMs verified

### Test Execution

**After Each Phase:**
```bash
# Unit tests only (fast feedback)
zig build test-unit

# Full test suite
zig build test

# Commercial ROM verification
./zig-out/bin/RAMBO roms/smb1.nes
./zig-out/bin/RAMBO roms/smb3.nes
./zig-out/bin/RAMBO roms/kirby.nes
```

**Final Verification:**
```bash
# Complete test suite
zig build test

# All commercial ROMs
for rom in roms/*.nes; do
    echo "Testing $rom..."
    timeout 10s ./zig-out/bin/RAMBO "$rom" || true
done

# Performance check
zig build bench-release
```

---

## Documentation Updates

### Session Documentation

**For Each Phase:**
- Create `docs/sessions/2025-10-15-phase2[B/C/D/E]-completion.md`
- Document what was changed and why
- Include before/after behavior
- Note any surprises or learnings

**Final Phase 2 Summary:**
- `docs/sessions/2025-10-15-phase2-completion-summary.md`
- Aggregate all phase results
- Update known issues list
- Document ROM compatibility changes

### Code Documentation

**Updated Files:**
- `CLAUDE.md` - Update test count, ROM compatibility
- `docs/CURRENT-ISSUES.md` - Mark issues as fixed or updated
- Inline code comments - Hardware references for each fix

### Commit Messages

**Template:**
```
<type>(scope): <description>

## Summary
[What was changed]

## Root Cause
[Why it was broken]

## Hardware Reference
[Link to nesdev.org or other source]

## Test Results
- Before: [X tests passing]
- After: [Y tests passing]
- New tests: [Z tests added]

## Expected Impact
[Which games should improve]

## Testing
- [x] Unit tests pass
- [x] Integration tests pass
- [x] Commercial ROMs tested
- [x] No regressions
```

---

## Open Questions (Resolve Before Starting)

### Phase 2B (Fine X Scroll)

**Q1:** Is the green line present on every frame or just certain frames?
**A:** Need to test - affects reproduction steps

**Q2:** Does the green line appear in all gameplay or just specific scenes?
**A:** Need to verify - affects scope of fix

**Q3:** Is this related to PPUMASK left-column clipping?
**A:** Possible - may be related to Phase 2D

### Phase 2C (PPUCTRL)

**Q4:** Does current implementation cache pattern/nametable base?
**A:** Code review suggests no caching, but needs verification

**Q5:** If no caching, what else could cause the issue?
**A:** May be related to Phase 2D (PPUMASK delay) or 2B (fine X)

**Q6:** Do we need attribute palette mid-scanline switching too?
**A:** Unknown - may be discovered during testing

### Phase 2D (PPUMASK)

**Q7:** Is delay exactly 3 dots, exactly 4 dots, or variable 3-4?
**A:** Research suggests 3-4 variable - need hardware reference

**Q8:** Does delay apply to all PPUMASK bits or just rendering enable?
**A:** Need to verify - may be just show_bg/show_sprites

**Q9:** What happens if PPUMASK toggled faster than delay pipeline?
**A:** Edge case - need test to verify behavior

### Phase 2E (DMC/OAM DMA)

**Q10:** Can DMC interrupt during OAM alignment cycle?
**A:** Research says yes - need to test

**Q11:** What if multiple DMC interrupts occur with no gap?
**A:** Edge case - test designed, need to verify

**Q12:** Does byte duplication affect OAM address or just written value?
**A:** Hardware research says written value - need to verify

---

## Recommended Action Plan

### Immediate Next Steps

**Step 1: Review and Approve Plan**
- Read this entire document
- Raise any questions or concerns
- Approve development order

**Step 2: Resolve Open Questions**
- Run SMB1 to verify green line behavior (Q1, Q2)
- Audit background.zig for caching (Q4)
- Research PPUMASK delay specs (Q7, Q8)

**Step 3: Begin Phase 2B**
- Create feature branch (optional): `git checkout -b phase2b-fine-x-scroll`
- Follow Phase 2B implementation steps
- Test incrementally

**Step 4: Proceed Through Phases**
- Complete 2B → 2C → 2D → 2E in order
- Test after each phase
- Commit at logical checkpoints
- Update documentation

**Step 5: Final Verification**
- Run complete test suite
- Test all commercial ROMs
- Create completion summary
- Celebrate! 🎉

---

## Key Principles

1. **Investigation Before Implementation** - Verify hypothesis with data
2. **Test Incrementally** - Don't proceed if tests fail
3. **Hardware Accuracy First** - Match nesdev specs exactly
4. **Zero Regressions** - 990/995 must pass after every change
5. **Document Everything** - Session notes, code comments, commits
6. **Systematic Process** - Investigate → Design → Implement → Test → Verify → Commit → Document

---

## Estimated Confidence Levels

| Phase | Confidence | Reason |
|-------|-----------|--------|
| 2B | 80% | Clear hypothesis, isolated change, low risk |
| 2C | 70% | May already be correct, need verification |
| 2D | 60% | Complex, affects all rendering, higher risk |
| 2E | 75% | Well-researched, comprehensive tests, clear approach |
| **Overall** | **70%** | Methodical approach reduces risk |

---

## Status Summary

- **Phase 2A:** ✅ COMPLETE (Diagnostic logging revealed patterns)
- **Phase 2B:** 🔵 READY (Clear plan, low risk)
- **Phase 2C:** 🔵 READY (Needs verification first)
- **Phase 2D:** 🔵 READY (High complexity, implement after 2B/2C)
- **Phase 2E:** 🔵 READY (Investigation complete, 33+ tests designed)

**Overall Status:** 🔵 **READY FOR IMPLEMENTATION**

---

## Final Notes

This plan represents **17-23 hours of systematic, methodical work** to fix the remaining commercial ROM rendering issues. The investigation phase has uncovered clear root causes and implementation strategies.

**Success depends on:**
- Following the plan systematically
- Testing incrementally
- Not rushing through steps
- Maintaining zero regressions
- Documenting findings

**If any phase blocks:**
- Document what was learned
- Defer to later investigation
- Move to next phase
- Don't accumulate technical debt

Good luck! 🚀

**Next Action:** Review this plan and raise any questions before beginning Phase 2B.
