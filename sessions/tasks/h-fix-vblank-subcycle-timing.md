---
name: h-fix-vblank-subcycle-timing
branch: fix/h-fix-vblank-subcycle-timing
status: pending
created: 2025-11-01
---

# VBlank Sub-Cycle Timing Fix

## Problem/Goal

Fix CPU/PPU sub-cycle execution order to match hardware behavior. When CPU reads $2002 (PPUSTATUS) at the exact same PPU cycle that VBlank is set (scanline 241, dot 1), the hardware executes CPU memory operations BEFORE PPU flag updates within that cycle.

**Current Bug:** Emulator executes PPU flag updates before CPU operations, causing CPU to read VBlank flag as 1 when it should read 0.

**Hardware Behavior (per nesdev.org):**
```
PPU Cycle N (scanline 241, dot 1):
├─ Phase 0: CPU Read Operations (if CPU is active this cycle)
├─ Phase 1: CPU Write Operations (if CPU is active this cycle)
├─ Phase 2: PPU Event (VBlank flag SET)
└─ Phase 3: End of cycle
```

**Ground Truth:** AccuracyCoin test ROM (runs on real NES hardware and passes on Mesen).

## Success Criteria
- [ ] AccuracyCoin VBlank Beginning test passes (ground truth - runs on real hardware)
- [ ] CPU/PPU sub-cycle execution order matches hardware behavior as verified by AccuracyCoin (CPU memory operations before PPU flag updates)
- [ ] VBlank flag visibility logic correctly handles same-cycle reads (read_cycle == set_cycle → flag not visible)
- [ ] All VBlank race condition edge cases pass AccuracyCoin tests (dots 0, 1, 2-3, multiple reads, read-set-read pattern)
- [ ] Any existing tests that fail after the fix are audited and corrected if they had incorrect hardware assumptions
- [ ] Final test count at least maintains baseline or improves (regressions in incorrectly-written tests are acceptable and should be fixed)

## Context Manifest
<!-- REQUIRED: Must run context-gathering agent at task startup before beginning work -->
<!-- Added by context-gathering agent -->

## User Notes
<!-- Any specific notes or requirements from the developer -->

## Work Log
<!-- Updated as work progresses -->
- [2025-11-01] Task created

