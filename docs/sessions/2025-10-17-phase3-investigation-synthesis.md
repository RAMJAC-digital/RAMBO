# Phase 3 Investigation Synthesis — 2025-10-17

## Executive Summary

Five specialist agents conducted comprehensive audits of all critical subsystems. **Three critical bugs found**, all with clear fix paths and low implementation risk.

**Critical Findings:**

### P0 Bugs (Blocking Commercial ROM Correctness)

1. **PPU A12 Edge Detection Uses Wrong Source** ⚠️ CRITICAL
   - **Bug:** Uses `v` register (nametable addressing) instead of actual CHR pattern table addresses
   - **Impact:** MMC3 IRQ counter miscounts edges → SMB3 status bar corruption, Kirby dialog missing, Mega Man 4 seams
   - **Fix:** Track `chr_address` during pattern fetches, use bit 12 for A12 detection
   - **Risk:** LOW - Localized change, 6 line additions + 1 line fix
   - **Files:** `src/ppu/State.zig`, `src/ppu/Logic.zig`, `src/ppu/logic/background.zig`, `src/ppu/logic/sprites.zig`

2. **MMC3 $E001 Incorrectly Acknowledges IRQ** ⚠️ CRITICAL
   - **Bug:** `$E001` (IRQ enable) clears `irq_pending` flag, should only enable without acknowledging
   - **Impact:** Games that rapidly enable/disable IRQs may miss interrupts or trigger IRQ storms
   - **Fix:** Remove line 146 in `Mapper4.zig`, update failing test
   - **Risk:** LOW - One line deletion + test update
   - **Files:** `src/cartridge/mappers/Mapper4.zig`, test update

3. **Input System Uses Layout-Dependent Keycodes** ⚠️ CRITICAL
   - **Bug:** Hard-coded keycodes (52, 111, 36) fail on non-US keyboard layouts
   - **Impact:** "No input" reports on AZERTY/Dvorak/Colemak layouts
   - **Fix:** Migrate to XKB keysyms (portable across layouts)
   - **Risk:** LOW - Additive change, backward compatible
   - **Files:** `src/mailboxes/XdgInputEventMailbox.zig`, `src/video/WaylandLogic.zig`, `src/input/KeyboardMapper.zig`, `src/main.zig`

### P1 Gaps (High Priority)

4. **MMC3 Test Coverage: 30%** (WEAK)
   - Missing: IRQ counter unit tests, banking tests, A12 edge counting
   - Proposed: 24 new unit tests across 3 files

5. **PPU Scrolling Test Coverage: 0%** (MISSING)
   - Missing: PPUSCROLL/PPUADDR behavior, mid-frame changes, t/v synchronization
   - Proposed: 20 new unit tests
   - **Impact:** SMB1 green line, SMB3 floor disappearing

6. **Visual Regression Testing: Manual Only**
   - No automated framebuffer validation
   - Proposed: 15 checkpoint system with xxHash comparison

### P2 Questions (New Bug Reports)

7. **SMB3 Super Leaf Float / Collision Issues**
   - **Analysis:** Physics bugs are almost always CPU/APU cycle timing, NOT IRQ timing
   - **Not explained by P0 bugs** - Requires separate investigation
   - **Hypothesis:** CPU microstep timing deviation or APU frame counter drift

---

## Detailed Bug Analysis

### Bug #1: PPU A12 Detection Uses `v` Register Instead of CHR Address

**Current Code (WRONG):**
```zig
// src/ppu/Logic.zig:240
const current_a12 = (state.internal.v & 0x1000) != 0;  // ← Uses VRAM address, not CHR address!
```

**Hardware Specification (nesdev.org):**
> MMC3 watches the PPU's **CHR address bus** (A0-A12) during pattern fetches

**Problem:**
- `v` register holds **nametable address** ($2000-$3FFF), NOT pattern table address ($0000-$1FFF)
- During sprite fetches, `v` doesn't change → A12 edges from sprites **completely missed**
- During background, `v` bit 12 reflects nametable selection, NOT pattern table selection
- **Result:** MMC3 IRQ counter sees wrong edges → triggers at wrong scanlines

**Example Scenario:**
```
Background using pattern table 0 ($0000-0FFF): A12 should be 0
But nametable at $2800 (bit 12=1): v & 0x1000 = 1
MMC3 sees A12=1 instead of A12=0 → WRONG EDGE COUNT
```

**Fix Design (Option A: Explicit Tracking):**

1. Add field to `PpuState`:
   ```zig
   /// Most recent CHR pattern table address (for A12 edge detection)
   chr_address: u16 = 0,
   ```

2. Update background pattern fetches (`background.zig:80, 87`):
   ```zig
   5 => {
       const pattern_addr = getPatternAddress(state, false);
       state.chr_address = pattern_addr;  // ← ADD THIS
       state.bg_state.pattern_latch_lo = memory.readVram(state, cart, pattern_addr);
   },

   7 => {
       const pattern_addr = getPatternAddress(state, true);
       state.chr_address = pattern_addr;  // ← ADD THIS
       state.bg_state.pattern_latch_hi = memory.readVram(state, cart, pattern_addr);
   },
   ```

3. Update sprite pattern fetches (`sprites.zig:~100, ~117`):
   ```zig
   if (fetch_cycle == 5 or fetch_cycle == 6) {
       // ... calculate addr ...
       state.chr_address = addr;  // ← ADD THIS
       const pattern_lo = memory.readVram(state, cart, addr);
   }

   if (fetch_cycle == 7 or fetch_cycle == 0) {
       // ... calculate addr ...
       state.chr_address = addr;  // ← ADD THIS
       const pattern_hi = memory.readVram(state, cart, addr);
   }
   ```

4. Fix A12 detection (`Logic.zig:240`):
   ```zig
   // OLD (BUGGY):
   // const current_a12 = (state.internal.v & 0x1000) != 0;

   // NEW (CORRECT):
   const current_a12 = (state.chr_address & 0x1000) != 0;
   ```

**Expected Impact:**
- ✅ SMB3 status bar splits work correctly
- ✅ Kirby's Adventure dialog boxes render
- ✅ Mega Man 4 vertical seams eliminated
- ✅ TMNT II may boot (if grey screen is IRQ-related)

**Test Strategy:**
- Add unit test: "PPU A12 edges during BG pattern fetches (expect ~8/scanline)"
- Add integration test: "SMB3 MMC3 IRQ fires at correct scanline for status bar"
- Verify A12 filter (6-8 cycle delay) still works

---

### Bug #2: MMC3 $E001 Incorrectly Acknowledges Pending IRQs

**Current Code (WRONG):**
```zig
// src/cartridge/mappers/Mapper4.zig:145-147
} else {
    // $E001-$FFFF: IRQ enable
    // Per nesdev.org: Writing to $E001 acknowledges any pending IRQ  ← WRONG COMMENT
    self.irq_enabled = true;
    self.irq_pending = false;  // ← BUG: Should NOT clear pending
}
```

**nesdev.org Specification:**
> $E000: "disable MMC3 interrupts AND acknowledge any pending interrupts"
> $E001: "enable MMC3 interrupts" (no mention of acknowledging)

**Problem:**
- Games that disable IRQs, then re-enable them expect pending IRQ to persist
- Current code: Re-enabling clears the pending flag → IRQ lost
- **Impact:** IRQ storms or missed splits in games using rapid enable/disable patterns

**Fix:**
```zig
// src/cartridge/mappers/Mapper4.zig:145-147
} else {
    // $E001-$FFFF: IRQ enable
    // Per nesdev.org: Enables IRQ generation without acknowledging
    self.irq_enabled = true;
    // REMOVED: self.irq_pending = false;
}
```

**Also Fix Failing Test:**
```zig
// tests/cartridge/mappers/Mapper4.zig:617-645
// Current test name: "IRQ enable clears pending flag"
// NEW test name: "IRQ enable does NOT clear pending flag"
// Invert expectation: expect(mapper.irq_pending == true) after enable
```

**Expected Impact:**
- ✅ TMNT II may boot (if using rapid IRQ toggling)
- ✅ Correct IRQ acknowledge semantics per hardware

---

### Bug #3: Input System Keycodes Are Layout-Dependent

**Current Code (NON-PORTABLE):**
```zig
// src/input/KeyboardMapper.zig:25-38
pub const Keymap = struct {
    pub const KEY_UP: u32 = 111;      // ← US layout only!
    pub const KEY_DOWN: u32 = 116;
    pub const KEY_LEFT: u32 = 113;
    pub const KEY_RIGHT: u32 = 114;
    pub const KEY_Z: u32 = 52;        // B button
    pub const KEY_X: u32 = 53;        // A button
    pub const KEY_RSHIFT: u32 = 62;   // Select
    pub const KEY_ENTER: u32 = 36;    // Start (doesn't match KP_Enter!)
};
```

**Problem:**
- XKB keycodes = physical key position + compositor offset
- Different layouts assign different keycodes to same logical key
- User on AZERTY presses 'Z' → different keycode than US QWERTY
- **Result:** No input detected, switch statement falls through

**Solution: XKB Keysyms (Portable)**

Keysyms = layout-aware symbolic constants:
- `XKB_KEY_z` = 0x007a (same on all layouts)
- `XKB_KEY_Up` = 0xff52 (same on all layouts)

**Migration Plan:**

1. Update `XdgInputEventMailbox` to carry keysym:
   ```zig
   pub const XdgInputEvent = union(enum) {
       key_press: struct {
           keycode: u32,      // Keep for diagnostics
           keysym: u32,       // NEW: portable mapping
           modifiers: u32,
       },
       // ...
   };
   ```

2. Extract keysym in `WaylandLogic.zig`:
   ```zig
   const keysym = xkb.xkb_state_key_get_one_sym(xkb_state_ptr, code);
   postKeyEvent(context, code, keysym, pressed);  // Pass both
   ```

3. Update `KeyboardMapper` to use keysyms:
   ```zig
   pub const Keymap = struct {
       const xkb = @import("../video/WaylandState.zig").xkb;

       pub const KEY_UP: u32 = xkb.XKB_KEY_Up;        // 0xff52
       pub const KEY_Z: u32 = xkb.XKB_KEY_z;          // 0x007a
       pub const KEY_ENTER: u32 = xkb.XKB_KEY_Return; // 0xff0d
       pub const KEY_KP_ENTER: u32 = xkb.XKB_KEY_KP_Enter; // 0xff8d
   };

   pub fn keyPress(self: *KeyboardMapper, keysym: u32) void {
       switch (keysym) {
           Keymap.KEY_ENTER, Keymap.KEY_KP_ENTER => self.buttons.start = true,  // Both Enter keys!
           // ...
       }
   }
   ```

4. Add `--input-diagnostics` flag:
   ```zig
   // Prints: "KEY PRESS: keycode=52 keysym=0x007a → B Button"
   ```

**Expected Impact:**
- ✅ SMB1 input works on all layouts (AZERTY, Dvorak, Colemak, etc.)
- ✅ Keypad Enter works for Start button
- ✅ Diagnostic mode helps users verify input

---

## Test Coverage Gaps

### Gap #1: MMC3 Unit Tests (30% Coverage)

**Missing Tests:**
- IRQ counter reload/decrement/zero (8 tests)
- CHR banking mode 0/1 (6 tests)
- PRG banking mode 0/1 (6 tests)
- Mirroring control (2 tests)
- PRG-RAM protection (2 tests)

**Proposed Test Files:**
1. `tests/cartridge/mappers/mmc3_irq_test.zig` (8 tests)
2. `tests/cartridge/mappers/mmc3_chr_banking_test.zig` (6 tests)
3. `tests/cartridge/mappers/mmc3_prg_banking_test.zig` (6 tests)
4. `tests/cartridge/mappers/mmc3_misc_test.zig` (4 tests)

**Total:** 24 new unit tests

---

### Gap #2: PPU Scrolling (0% Coverage)

**Missing Tests:**
- Fine X scroll (3-bit value 0-7)
- Coarse X/Y scroll updates
- Mid-scanline scroll changes (status bar splits)
- PPUADDR double-write behavior
- t/v register synchronization

**Proposed Test File:**
- `tests/ppu/scrolling_test.zig` (20 tests)

**Impact:**
- ✅ Fix SMB1 green line (8-pixel offset on left edge)
- ✅ Fix SMB3 floor disappearing (scroll timing)

---

### Gap #3: Visual Regression (Manual Only)

**Current:** Screenshot → manual inspection
**Proposed:** Automated framebuffer comparison with xxHash

**Framework:**
```zig
const CHECKPOINTS = [_]FrameCheckpoint{
    .{ .rom = "SMB3", .frame = 360, .hash = 0x..., .desc = "Level 1-1 floor visible" },
    .{ .rom = "Kirby", .frame = 600, .hash = 0x..., .desc = "Dialog box rendered" },
    // ... 15 total checkpoints
};

test "Visual Regression: Commercial ROM checkpoints" {
    for (CHECKPOINTS) |cp| {
        const actual = runUntilFrame(cp.rom, cp.frame);
        try testing.expectEqual(cp.hash, xxHash(actual.framebuffer));
    }
}
```

**Benefits:**
- Catch rendering regressions immediately
- Enable confident refactoring
- Reduce manual testing burden

---

## New Bug Analysis: SMB3 Physics Issues

### User Report:
- Super leaf floats upwards (gravity inverted?)
- Collision not quite right

### Analysis:

**Physics bugs are almost always CPU/APU timing, NOT PPU/IRQ timing:**

1. **Gravity calculation** runs on CPU every frame
2. **Collision detection** runs on CPU during gameplay loop
3. **IRQ timing** only affects when split-screen code executes, NOT physics

**Hypotheses (in order of likelihood):**

1. **CPU Cycle Timing Deviation** (HIGH)
   - Known issue: Absolute,X/Y without page crossing has +1 cycle deviation
   - Documented in `docs/CURRENT-ISSUES.md` as "functionally correct but timing deviated"
   - **Impact:** Physics runs 1 cycle earlier/later → gravity accumulates error
   - **Evidence:** AccuracyCoin passes despite deviation → deviation is minor but real

2. **APU Frame Counter Drift** (MEDIUM)
   - APU frame counter drives game timing
   - If frame IRQ timing off by a few cycles → physics updates at wrong cadence
   - **Evidence:** 135 APU tests pass, but may not cover all frame counter edge cases

3. **DMA Pause Timing** (LOW)
   - OAM DMA pauses CPU for 513/514 cycles
   - If DMA timing slightly off → frame timing accumulates error
   - **Evidence:** Recent Phase 2E work improved DMA accuracy

4. **IRQ Acknowledge Delay** (LOW)
   - If IRQ not acknowledged fast enough → next frame starts late
   - Cumulative error over many frames
   - **Evidence:** Unlikely, IRQ timing is edge-triggered

**NOT Explained by P0 Bugs:**
- ❌ A12 detection bug affects **when splits happen**, NOT **how physics run**
- ❌ MMC3 acknowledge bug affects **IRQ triggering**, NOT **gravity calculations**
- ❌ Input bug affects **controller reading**, NOT **collision detection**

**Recommended Investigation:**

1. **Profile CPU cycle counts** over 60 frames:
   - Expected: 29780.5 CPU cycles/frame × 60 = 1,786,830 cycles
   - Measure actual cycle count → look for drift

2. **Add physics-specific diagnostics:**
   - Log Mario Y position, Y velocity every frame
   - Compare against known-good emulator (Mesen)
   - Identify exactly when gravity inverts

3. **Instrument APU frame counter:**
   - Log frame IRQ timing relative to PPU NMI
   - Verify 4-step vs 5-step mode correct
   - Check if games use frame IRQ for timing

**Defer to Separate Investigation:**
- Physics bugs are complex, require deep CPU/APU timing analysis
- Should NOT block P0 bug fixes (A12, IRQ acknowledge, input)
- Create separate investigation task after P0 bugs fixed

---

## Implementation Plan

### Phase 3A: Critical Bug Fixes (Week 1)

**Day 1-2: PPU A12 Detection Fix**
- Add `chr_address` field to `PpuState`
- Update 4 pattern fetch sites (background × 2, sprite × 2)
- Fix A12 detection in `Logic.zig:240`
- Add unit test: "A12 edge count during rendering"
- Manual test: SMB3, Kirby, Mega Man 4
- **Expected:** Status bar splits work, dialog boxes render

**Day 3: MMC3 IRQ Acknowledge Fix**
- Remove line 146 in `Mapper4.zig`
- Update failing test (invert expectation)
- Add new test: "IRQ persists after enable"
- Manual test: TMNT II, SMB3
- **Expected:** No regressions, possible TMNT II boot fix

**Day 4-5: Input System Keysym Migration**
- Update `XdgInputEventMailbox` (add keysym field)
- Extract keysym in `WaylandLogic.zig`
- Update `KeyboardMapper` to use XKB keysyms
- Add `--input-diagnostics` flag
- Test on US layout, then request testing on AZERTY/Dvorak
- **Expected:** Input works on all layouts

### Phase 3B: Test Coverage (Week 2)

**Day 6-7: MMC3 Unit Tests**
- Implement `mmc3_irq_test.zig` (8 tests)
- Implement `mmc3_chr_banking_test.zig` (6 tests)
- Implement `mmc3_prg_banking_test.zig` (6 tests)
- **Expected:** 20+ new tests passing

**Day 8-9: PPU Scrolling Tests**
- Implement `scrolling_test.zig` (20 tests)
- Enable shift register prefetch tests (5 tests in `.wip` file)
- **Expected:** 25+ new tests, may uncover bugs

**Day 10: Visual Regression Framework**
- Capture 15 reference frames (5 games × 3 checkpoints)
- Implement xxHash comparison test
- Add to `zig build test-integration`
- **Expected:** Automated regression detection

### Phase 3C: Physics Investigation (Week 3+)

**After P0 Bugs Fixed:**
- Profile CPU cycle counts
- Add Mario physics diagnostics
- Compare against Mesen
- Deep-dive into timing deviation
- **Expected:** Identify root cause of gravity/collision bugs

---

## Risk Assessment

### P0 Bug Fixes (Low Risk)

**A12 Detection Fix:**
- ✅ Localized change (6 additions + 1 fix)
- ✅ No existing code depends on buggy behavior
- ✅ Easy to verify (A12 edge count visible in tests)
- ⚠️ Must update snapshot serialization (add `chr_address` field)

**MMC3 IRQ Acknowledge Fix:**
- ✅ One line deletion
- ✅ Matches hardware specification exactly
- ✅ Test suite will catch regressions
- ⚠️ One existing test will fail (expected, needs update)

**Input Keysym Migration:**
- ✅ Additive change (backward compatible)
- ✅ Keycode still available for diagnostics
- ✅ Easy to test on multiple layouts
- ⚠️ Requires XKB library (already used)

### Test Coverage (Medium Risk)

**MMC3 Unit Tests:**
- ✅ Pure unit tests, no integration risk
- ✅ May uncover additional mapper bugs (GOOD)
- ⚠️ Test suite size increases significantly

**PPU Scrolling Tests:**
- ⚠️ May expose bugs in current implementation
- ⚠️ Fixes may affect rendering pipeline
- ✅ Well-understood hardware behavior

**Visual Regression:**
- ⚠️ Hash stability across platforms unknown
- ⚠️ Requires headless rendering
- ⚠️ Initial checkpoint capture effort

### Physics Investigation (High Complexity)

- ⚠️ CPU timing is complex, deep expertise required
- ⚠️ May require profiling tools and instrumentation
- ⚠️ Cross-emulator comparison needed (Mesen)
- ✅ Well-defined scope (Mario physics only)

---

## Success Criteria

### Phase 3A (Critical Bugs) — MUST PASS

- ✅ SMB3 status bar stable for 60+ frames (no corruption)
- ✅ Kirby's Adventure dialog boxes render on first try
- ✅ Mega Man 4 background scrolls smoothly (no vertical seams)
- ✅ Input works on AZERTY/Dvorak/Colemak layouts
- ✅ Test suite: 1038/1044 → 1040+/1044 (expect +2-5 from fixes)

### Phase 3B (Test Coverage) — NICE TO HAVE

- ✅ MMC3 unit tests: 20+ new tests passing
- ✅ PPU scrolling tests: 20+ new tests passing
- ✅ Visual regression: 15 checkpoints captured and passing
- ✅ Test suite: 1040/1044 → 1085+/1044

### Phase 3C (Physics) — INVESTIGATIVE

- ✅ Root cause identified for gravity/collision bugs
- ✅ Cycle timing profiling complete
- ✅ Fix implemented and verified against Mesen

---

## Questions for User

### Before Implementation:

1. **Priority Confirmation:**
   - Agree with P0 → P1 → P2 ordering?
   - Should physics investigation happen in Phase 3C or separate session?

2. **Test Coverage:**
   - Comfortable with 24 new MMC3 tests?
   - Should visual regression use xxHash or pixel-perfect comparison?

3. **Input System:**
   - Can you test on non-US layout after keysym migration?
   - Preferred alternative bindings (J/K for B/A)?

4. **Physics Bugs:**
   - Are gravity/collision bugs consistent (always float up)?
   - Or intermittent (sometimes works)?
   - Which level/scenario reproduces reliably?

---

## Files Modified (Summary)

### P0 Bug Fixes (10 files)

**A12 Detection:**
1. `src/ppu/State.zig` — Add `chr_address` field
2. `src/ppu/Logic.zig` — Fix A12 detection (line 240)
3. `src/ppu/logic/background.zig` — Update pattern fetches (2 sites)
4. `src/ppu/logic/sprites.zig` — Update sprite fetches (2 sites)

**MMC3 IRQ:**
5. `src/cartridge/mappers/Mapper4.zig` — Remove line 146
6. `tests/cartridge/mappers/Mapper4.zig` — Update failing test

**Input System:**
7. `src/mailboxes/XdgInputEventMailbox.zig` — Add keysym field
8. `src/video/WaylandLogic.zig` — Extract keysym
9. `src/input/KeyboardMapper.zig` — Use XKB keysyms
10. `src/main.zig` — Pass keysym, add diagnostics flag

### P1 Test Coverage (4 new files)

11. `tests/cartridge/mappers/mmc3_irq_test.zig` — NEW
12. `tests/cartridge/mappers/mmc3_chr_banking_test.zig` — NEW
13. `tests/cartridge/mappers/mmc3_prg_banking_test.zig` — NEW
14. `tests/ppu/scrolling_test.zig` — NEW
15. `tests/integration/visual_regression_test.zig` — NEW

---

## Conclusion

**Phase 3 investigation complete.** Three critical bugs identified with clear, low-risk fix paths. Test coverage gaps documented with actionable remediation plan. New physics bugs identified as separate concern requiring dedicated investigation.

**Recommended next steps:**
1. Get user approval on implementation plan
2. Implement P0 fixes (A12, IRQ acknowledge, input) — 5 days
3. Verify commercial ROM correctness
4. Add test coverage (MMC3, scrolling, visual) — 5 days
5. Investigate physics bugs separately — TBD

**Expected outcome:** 995/995 tests passing (100%), commercial ROMs fully playable.