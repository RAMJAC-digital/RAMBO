# A12 Edge Detection Bug - Executive Summary

**Date:** 2025-10-18
**Status:** CRITICAL BUG IDENTIFIED
**Confidence:** VERY HIGH (test-proven, execution flow verified)

---

## The Bug in One Sentence

A12 edge detection reads `state.chr_address` **BEFORE** background tile fetches write it, causing a one-cycle delay that makes all background pattern fetches invisible to MMC3 IRQ timing.

---

## Evidence

**Test Output:**
```
Expected: 34 A12 edges per scanline (32 background + 2 prefetch)
Actual:   1 A12 edge per scanline (dot 258 only - sprite fetch)
Missing:  ALL background fetch edges (dots 6, 14, 22, 30...)
```

**Source:** `/home/colin/Development/RAMBO/tests/ppu/a12_edge_detection_test.zig`

---

## Root Cause

### Execution Order in `/src/ppu/Logic.zig` tick()

```
Current (BROKEN):
1. Lines 236-268: A12 detection READS chr_address (sees OLD value)
2. Lines 270-301: Background fetch WRITES chr_address (too late!)
3. Lines 305+:    Sprite evaluation WRITES chr_address

Hardware (CORRECT):
1. Address setup:  CHR address bus driven to pattern table address
2. A12 detection:  Monitors CHR address bus (sees CURRENT value)
3. Memory read:    Pattern data latched
```

**Gap:** A12 detection runs **BEFORE** background fetch updates chr_address.

---

## Why Sprites Work (Accidental)

Sprite evaluation is the **LAST** operation in tick():
- Dot N: Sprite writes chr_address
- Dot N+1: A12 detection reads chr_address from dot N ✓

**Background fails because:**
- Dot N: A12 reads chr_address (from dot N-1)
- Dot N: Background writes chr_address (missed by A12!)

---

## Impact

**Commercial ROM Failures:**
- **Super Mario Bros. 3:** Status bar disappears (IRQ counter not decrementing)
- **Super Mario Bros. 3:** Checkered floor rendering broken
- **Kirby's Adventure:** Dialog box missing
- **All MMC3 games:** Scanline IRQ effects fail

**Why:** MMC3 IRQ counter requires ~32 A12 edges per scanline (one per tile). Current implementation detects only 1 edge (sprite fetch), so counter decrements 32× too slowly.

---

## Solution

**Move A12 detection AFTER background/sprite pipelines** (reorder lines 236-268 to after line 332).

### Before (BROKEN):
```zig
pub fn tick(...) {
    // A12 detection (reads chr_address) - WRONG ORDER
    if (is_rendering_line and rendering_enabled) {
        const current_a12 = (state.chr_address & 0x1000) != 0;
        // ... filter logic ...
    }

    // Background pipeline (writes chr_address) - TOO LATE
    if (is_rendering_line and rendering_enabled) {
        fetchBackgroundTile(state, cart, dot);
    }

    // Sprite evaluation (writes chr_address)
    fetchSprites(state, cart, scanline, dot);
}
```

### After (CORRECT):
```zig
pub fn tick(...) {
    // Background pipeline (writes chr_address) - FIRST
    if (is_rendering_line and rendering_enabled) {
        fetchBackgroundTile(state, cart, dot);
    }

    // Sprite evaluation (writes chr_address)
    fetchSprites(state, cart, scanline, dot);

    // A12 detection (reads chr_address) - LAST (sees current dot!)
    if (is_rendering_line and rendering_enabled) {
        const current_a12 = (state.chr_address & 0x1000) != 0;
        // ... filter logic ...
    }
}
```

---

## Verification Steps

1. **Move A12 detection block** to after sprite evaluation
2. **Run test:** `zig build test` → a12_edge_detection_test should pass
3. **Check output:** Should show 34 A12 edges per scanline
4. **Test SMB3:** Status bar should persist throughout gameplay

---

## Risk Assessment

**Risk Level:** LOW
**Reasoning:**
- A12 detection is pure read logic (no side effects)
- Moving reads AFTER writes is always safe
- Sprite fetches already prove this pattern works
- No dependencies on execution order within tick()

---

## Files

**Bug Location:**
- `/home/colin/Development/RAMBO/src/ppu/Logic.zig` (lines 236-268, 270-301)

**Related Code:**
- `/home/colin/Development/RAMBO/src/ppu/logic/background.zig` (lines 45-110)
- `/home/colin/Development/RAMBO/src/ppu/logic/sprites.zig` (lines 95-129)

**Test:**
- `/home/colin/Development/RAMBO/tests/ppu/a12_edge_detection_test.zig`

**Full Analysis:**
- `/home/colin/Development/RAMBO/docs/reviews/a12-edge-detection-execution-order-bug.md`
- `/home/colin/Development/RAMBO/docs/dot/a12-execution-order-bug.dot` (GraphViz diagram)
- `/home/colin/Development/RAMBO/docs/dot/a12-execution-order-bug.png` (visual diagram)

---

## Key Insight

**Hardware has no "execution order" - CHR address bus is driven continuously.**
**Software must model this by ensuring A12 detection reads chr_address AFTER fetch logic writes it.**

The bug is a **read-before-write race condition** caused by incorrect statement ordering in a sequential function.
