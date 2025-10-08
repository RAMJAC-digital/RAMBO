# NMI Interrupt Investigation Archive

**Date:** 2025-10-08
**Duration:** ~4 hours
**Status:** Investigation Complete - Implementation In Progress

---

## What Was Investigated

Commercial ROMs (Super Mario Bros, Donkey Kong, BurgerTime) displayed blank screens while test ROMs (AccuracyCoin) worked perfectly. This archive contains the investigation that led to discovering the root cause.

---

## Key Findings

### Root Cause: NMI Interrupts Not Implemented

**Problem:** Interrupt states (`.interrupt_sequence`, etc.) were defined in the `ExecutionState` enum but had **zero implementation** in `executeCpuCycle()`.

**Impact:**
- ALL commercial games hung in infinite loops
- Games waited for NMI that never executed
- Title screens never appeared

### Investigation Process

1. **Hypothesis 1: PPU Not Rendering** ❌
   - PPU rendering pipeline worked correctly
   - Backdrop color rendered (61,440 pixels filled)

2. **Hypothesis 2: PPUMASK Not Enabled** ⚠️
   - Games set PPUMASK to initialization values only
   - Never progressed to full rendering

3. **Hypothesis 3: PPU Warm-Up Period** ✅
   - Fixed: Tests incorrectly called `reset()`
   - Power-on initialization now preserves warm-up requirement

4. **Hypothesis 4: VBlank Not Setting** ❌
   - VBlank sets correctly at scanline 241, dot 1
   - Clears at scanline 261, dot 1 (hardware behavior)

5. **Hypothesis 5: NMI Not Firing** ✅ **ROOT CAUSE**
   - PPU VBlank sets correctly ✅
   - NMI signal propagates correctly ✅
   - Edge detection works ✅
   - `startInterruptSequence()` called ✅
   - **BUT NO CODE TO EXECUTE THE INTERRUPT** ❌

---

## Documents in This Archive

### CRITICAL-FINDING-NMI-NOT-IMPLEMENTED.md
- Comprehensive root cause analysis
- Investigation timeline (6 hypotheses)
- Required implementation details
- Testing strategy

### SESSION-SUMMARY.md
- Session timeline and objectives
- Work completed (infrastructure, tests)
- Technical analysis
- Lessons learned

---

## Work Completed During Investigation

### Infrastructure Created

1. **FramebufferValidator** (`tests/helpers/FramebufferValidator.zig`)
   - Pixel counting utilities
   - Framebuffer hashing (CRC32)
   - PPM export for visual debugging
   - 10 unit tests passing

2. **Commercial ROM Tests** (`tests/integration/commercial_rom_test.zig`)
   - End-to-end ROM loading
   - Framebuffer validation
   - PPU register tracking
   - NMI execution detection
   - 6 test cases (currently failing - blocked on NMI implementation)

### Diagnostic Output Added (Later Removed)

- `src/ppu/Logic.zig` - PPUCTRL/PPUMASK write tracking
- `src/emulation/State.zig` - NMI assertion tracking
- `src/emulation/Ppu.zig` - VBlank tracking
- `src/cpu/Logic.zig` - Edge detection tracking

All debug output was cleanly removed after root cause identification.

---

## Outcome

**Discovery:** The interrupt sequence states were vestigial from an earlier design. The current architecture uses:
- **Single state** (`.interrupt_sequence`) with cycle counter
- **Inline microsteps** in `executeCpuCycle()` (matches BRK pattern)
- **No separate method** (inline pattern, not separate state machine)

**Solution:** Implement inline interrupt handling following the exact BRK pattern (lines 1229-1238 in `src/emulation/State.zig`).

---

## Implementation Status

**Current:** See `docs/sessions/2025-10-08-nmi-interrupt-investigation/IMPLEMENTATION-PLAN.md`

**Estimated Time:** 6-8 hours

**Phases:**
1. ✅ Investigation Complete
2. ✅ Architecture Analysis Complete
3. ⏳ Implementation In Progress
4. ⏳ Testing In Progress

---

## References

- **Hardware Spec:** nesdev.org - Interrupt Handling
- **BRK Reference:** `src/emulation/State.zig:1229-1238`
- **Current Plan:** `../2025-10-08-nmi-interrupt-investigation/IMPLEMENTATION-PLAN.md`
