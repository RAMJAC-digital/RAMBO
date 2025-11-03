# VBlank Prevention Bug Analysis - 2025-11-02

**Task:** h-fix-oam-nmi-accuracy
**Investigation:** NMI test regressions (separate from AccuracyCoin issues)
**Status:** Root cause identified, fix ready for implementation

---

## Executive Summary

**Bug:** VBlank prevention logic checks `if (dot == 0)` but CPU can never execute at dot 0 due to CPU/PPU phase alignment. The check is NEVER true, causing VBlank to set when it should be prevented.

**Fix:** Change check to `if (dot == 1)` and set `prevent_vbl_set_cycle = self.clock.ppu_cycles` (current master clock, not +1).

**Impact:** Should fix NMI test regressions introduced by recent VBlank timing changes.

---

## Root Cause Analysis

### CPU/PPU Phase Alignment

In RAMBO, CPU and PPU are phase-locked with a 1:3 ratio:
- CPU ticks when `ppu_cycles % 3 == 0`
- PPU advances before CPU executes

**Scanline 241 timing:**
```
Dot 0: ppu_cycles = 82,181, 82,181 % 3 = 2 → NOT a CPU tick
Dot 1: ppu_cycles = 82,182, 82,182 % 3 = 0 → IS a CPU tick (VBlank sets here)
Dot 2: ppu_cycles = 82,183, 82,183 % 3 = 1 → NOT a CPU tick
Dot 4: ppu_cycles = 82,185, 82,185 % 3 = 0 → IS a CPU tick
```

**Critical insight:** CPU physically cannot execute at dot 0. It can only execute at dots 1, 4, 7, 10, etc.

### RAMBO tick() Execution Order

```
1. nextTimingStep() - Captures pre-advance position, advances clock
   Before: ppu_cycles = 82,181 (scanline 241, dot 0)
   After:  ppu_cycles = 82,182 (scanline 241, dot 1)

2. stepPpuCycle() - Processes PPU at post-advance position (241, 1)

3. stepCpuCycle() - IF cpu_tick (true at ppu_cycles 82,182)
   - Executes CPU instruction
   - busRead($2002) calls clock.scanline() and clock.dot()
   - Returns: scanline = 241, dot = 1 (post-advance values)
   - Checks: if (dot == 0) → FALSE (BUG!)

4. applyPpuCycleResult() - Updates VBlank ledger timestamps
   - Checks prevention: ppu_cycles == prevent_vbl_set_cycle
   - Since prevention wasn't set, VBlank sets normally
```

### The Bug

**Current code** (`src/emulation/State.zig:318`):
```zig
if (dot == 0) {
    self.vblank_ledger.prevent_vbl_set_cycle = self.clock.ppu_cycles + 1;
}
```

**Problems:**
1. `dot == 0` is NEVER true when CPU executes (CPU can't execute at dot 0)
2. `ppu_cycles + 1` would be 82,183, but VBlank sets at 82,182

### Mesen2 vs RAMBO Comparison

**Mesen2:**
- CPU's memory operation spans multiple PPU cycles
- StartCpuCycle() runs PPU for ~6 cycles
- CPU reads $2002 while PPU is at cycle 0
- UpdateStatusFlag() sees `_cycle == 0`, sets `_preventVblFlag = true`
- PPU continues to cycle 1
- Checks `if (!_preventVblFlag)`, skips VBlank set

**RAMBO:**
- Clock advances BEFORE CPU executes
- CPU only executes at post-advance cycle values
- When CPU reads $2002, it's already at the VBlank set cycle
- Need to prevent at CURRENT cycle, not next cycle

### "MC + 1 holds the race" Interpretation

The user's guidance "MC + 1 holds the race" refers to **Mesen2's perspective**:
- Read at cycle N (e.g., 0)
- Prevent at cycle N+1 (e.g., 1)

In RAMBO's post-advance execution model:
- Read happens at post-advance MC (82,182)
- Prevent at CURRENT MC (82,182), not MC+1 (82,183)
- The "+1" is implicit in Mesen2's "check at 0, prevent at 1" pattern
- In RAMBO, we check at the already-advanced cycle, so no +1 needed

---

## The Fix

### Change 1: Check dot == 1 instead of dot == 0

**File:** `src/emulation/State.zig`
**Line:** 318

**Current:**
```zig
if (dot == 0) {
    // Set prevention for NEXT cycle (dot 1)
    // User guidance: "MC + 1 holds the race"
    self.vblank_ledger.prevent_vbl_set_cycle = self.clock.ppu_cycles + 1;
}
```

**Fixed:**
```zig
if (dot == 1) {
    // Set prevention for CURRENT cycle (already at dot 1 post-advance)
    // In RAMBO's post-advance model, we prevent the current MC value
    self.vblank_ledger.prevent_vbl_set_cycle = self.clock.ppu_cycles;
}
```

### Change 2: Use current MC, not MC+1

**Rationale:**
- `applyPpuCycleResult()` runs at the same `ppu_cycles` value
- Check: `if (self.clock.ppu_cycles == self.vblank_ledger.prevent_vbl_set_cycle)`
- Need them to match for prevention to work
- If we set prevent_vbl_set_cycle to MC+1, they won't match and prevention fails

### Change 3: Adjust race window comment

The race window check at line 313:
```zig
if (scanline == 241 and dot <= 2) {
```

Should be adjusted to only check dot 1 for prevention (dot 4+ is too late for prevention, only suppression):
```zig
if (scanline == 241 and dot == 1) {
    // Prevention: Stop VBlank from setting
    self.vblank_ledger.prevent_vbl_set_cycle = self.clock.ppu_cycles;
    // Suppression: Also mark as race for NMI suppression
    self.vblank_ledger.last_race_cycle = self.clock.ppu_cycles;
}
```

---

## Testing Plan

### Unit Tests
- Verify `prevent_vbl_set_cycle` is set at dot 1
- Verify VBlank does NOT set when prevention is active
- Verify NMI does NOT fire when prevention is active

### Integration Tests
- Run NMI timing tests that recently regressed
- Expected: Tests should pass with correct prevention timing

### Regression Check
- Run full test suite (currently 999/1026 passing)
- Expected: Restore to 1004+ passing tests
- Monitor for any new regressions

---

## Implementation Notes

### Why dot == 1, not dot <= 2?

The CPU can execute at dots 1, 4, 7, etc. Only dot 1 is the "prevent" scenario. Dot 4 and beyond are too late for prevention (VBlank already set at dot 1), those need suppression only.

The current code checks `dot <= 2` which would catch dot 1 but also attempts to prevent at dot 2, which is:
1. Impossible (CPU can't execute at dot 2)
2. Unnecessary (dot 4 is the next CPU tick, VBlank already set)

### Master Clock is the Source of Truth

Per user guidance: Use master clock (MC) because PPU may skip dots (odd frame behavior). Scanline/dot derivation is for human readability, but MC is the authoritative value for prevention timestamps.

### applyPpuCycleResult() Ordering

Critical: Prevention check happens at the SAME ppu_cycles value where the read occurred:
1. CPU reads at ppu_cycles = X
2. Sets prevent_vbl_set_cycle = X
3. applyPpuCycleResult() checks at ppu_cycles = X
4. Prevention matches, VBlank set is skipped

---

## AccuracyCoin Note

Per user: AccuracyCoin is a **separate issue** from these NMI test regressions. AccuracyCoin has always failed and represents broader compatibility issues. This fix targets the recent regressions in existing NMI tests.

---

## References

- Mesen2 source: `Core/NES/NesPpu.cpp` lines 585-594 (UpdateStatusFlag), 1339-1344 (VBlank set with prevention)
- RAMBO implementation: `src/emulation/State.zig` lines 285-354 (bus read with race detection)
- Hardware spec: https://www.nesdev.org/wiki/PPU_frame_timing (VBlank race condition)
- Previous investigation: `docs/investigation/mesen2-validated-vblank-nmi-specification.md`

---

**Status:** Ready for implementation
**Confidence:** High (root cause identified with concrete evidence)
**Risk:** Low (changes isolated to prevention check and timestamp assignment)
