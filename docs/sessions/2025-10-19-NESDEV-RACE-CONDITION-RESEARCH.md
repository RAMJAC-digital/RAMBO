# NESDev Research: VBlank Race Condition Behavior
**Date:** 2025-10-19
**Source:** NESDev Wiki and Forums (researched 2024-2025)

## Authoritative Behavior from Hardware

### VBlank Flag Timing
- **VBlank flag SET:** Scanline 241, dot 1 (PPU cycle 82,181 in a frame)
- **VBlank flag CLEAR:** Scanline 261, dot 1 (start of pre-render scanline)

### Race Condition Windows

Reading $2002 (PPUSTATUS) at different timings relative to VBlank set:

| Timing | Flag Read Value | Flag After Read | NMI Behavior |
|--------|----------------|-----------------|--------------|
| Dot 0 (1 before set) | 0 (clear) | Stays clear | NOT generated |
| **Dot 1 (SAME cycle)** | **1 (set)** | **Cleared** | **SUPPRESSED** |
| Dot 2 (1 after set) | 1 (set) | Cleared | **MAY be suppressed** |
| Dot 3+ (2+ after) | 1 (set) | Cleared | Normal (fires) |

### Key Insights

**Quote from NESDev:**
> "Reading $2002 one PPU clock before VBlank is set reads it as clear and never sets the flag or generates NMI for that frame. Reading on the same PPU clock or one later reads it as set, clears it, and suppresses the NMI for that frame."

**Technical Explanation:**
> "This suppression behavior is due to the $2002 read pulling the NMI line back up too quickly after it drops (NMI is active low) for the CPU to see it."

**Race Window:**
> "NMI is also suppressed when this occurs, and may even be suppressed by reads landing on the following dot or two."

## Implementation Requirements

### Current Code Analysis

**Race Detection (State.zig:294):**
```zig
if (last_set > last_clear and now == last_set) {
    self.vblank_ledger.last_race_cycle = last_set;
}
```

**Problem:** Only detects reads on EXACT same cycle (dot 1)
**Should:** Detect reads within 0-2 cycle window (dots 1-3)

### Correct Implementation

```zig
// Detect race condition: $2002 reads within 0-2 cycles after VBlank set
if (last_set > last_clear) {
    const delta = if (now >= last_set) now - last_set else 0;
    if (delta <= 2) {  // Race window: same cycle + 2 cycles after
        self.vblank_ledger.last_race_cycle = last_set;
    }
}
```

**Rationale:**
- delta = 0: Exact same cycle (dot 1) - **Always suppresses**
- delta = 1: One cycle after (dot 2) - **May suppress**
- delta = 2: Two cycles after (dot 3) - **May suppress** (conservative)
- delta >= 3: Normal behavior

### NMI Suppression Logic

**Current (execution.zig:107):**
```zig
const nmi_line_should_assert = vblank_flag_visible and state.ppu.ctrl.nmi_enable;
```

**Missing:** Race suppression check!

**Should be:**
```zig
const vblank_flag_visible = state.vblank_ledger.isFlagVisible();
const race_suppression = state.vblank_ledger.hasRaceSuppression();
const nmi_line_should_assert = vblank_flag_visible and
                                 state.ppu.ctrl.nmi_enable and
                                 !race_suppression;
```

### Flag Visibility Logic

**Current (VBlankLedger.zig:35-45):**
```zig
pub inline fn isFlagVisible(self: VBlankLedger) bool {
    if (!self.isActive()) return false;
    if (self.last_read_cycle >= self.last_set_cycle) return false;
    return true;
}
```

**Status:** ✅ CORRECT - Flag becomes invisible once read, regardless of race

**Important:** Race affects NMI generation, NOT flag visibility!
- Race read DOES see flag as 1
- Race read DOES clear flag (makes it invisible for next read)
- Race read SUPPRESSES NMI (prevents interrupt from firing)

## Test Implications

### Tests Currently Passing (6 tests)
These tests don't depend on precise race condition behavior:
- VBlank Beginning (basic flag visibility)
- VBlank End (flag clear timing)
- NMI Control subtests (basic enable/disable)
- NMI at VBlank End
- NMI Disabled at VBlank
- All NOP Instructions

### Tests Currently Timing Out (2 tests)
These tests SPECIFICALLY test race condition behavior:

**NMI SUPPRESSION Test:**
- **Purpose:** Verify NMI suppressed when $2002 read on exact VBlank set cycle
- **Why it timeouts:** We don't suppress NMI, so test logic fails
- **Fix:** Add race suppression to NMI logic

**NMI TIMING Test:**
- **Purpose:** Verify exact cycle timing of NMI execution
- **Why it timeouts:** NMI timing may be incorrect due to missing suppression
- **Fix:** Add race suppression + verify NMI edge detection timing

## Action Items

### 1. Widen Race Detection Window (HIGH PRIORITY)
**File:** `src/emulation/State.zig:294`
**Change:** Check delta <= 2 instead of exact match

### 2. Add Race Suppression to NMI Logic (CRITICAL)
**File:** `src/emulation/cpu/execution.zig:107`
**Change:** Check !race_suppression before asserting NMI line

### 3. Verify Tests Pass
- NMI SUPPRESSION should return 0x00 (PASS)
- NMI TIMING should return 0x00 (PASS)
- All 6 currently passing tests should remain passing

### 4. Update Test Expectations
- Change all expectations from FAIL codes to 0x00 (PASS)
- Remove "regression detection" comments

## References

- [NESDev Wiki: PPU Registers](https://www.nesdev.org/wiki/PPU_registers)
- [NESDev Wiki: NMI](https://www.nesdev.org/wiki/NMI)
- [NESDev Wiki: PPU Frame Timing](https://www.nesdev.org/wiki/PPU_frame_timing)
- [NESDev Forums: NMI Timing](https://forums.nesdev.org/viewtopic.php?f=3&t=17663)

---

**Confidence Level:** HIGH - Hardware behavior documented by NESDev community
**Risk Level:** LOW - Changes are targeted and well-understood
**Expected Outcome:** All 10 AccuracyCoin accuracy tests should pass
