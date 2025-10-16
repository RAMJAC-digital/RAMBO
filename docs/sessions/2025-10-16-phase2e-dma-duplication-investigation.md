# Phase 2E: DMC/OAM DMA Duplication Investigation

**Date:** 2025-10-16
**Status:** BLOCKED - Need hardware specification clarity
**Context:** Implementing clean architecture for DMA, hit byte duplication edge case

## Problem Statement

Tests expect byte duplication when DMC interrupts OAM during read cycle, but implementation causes either:
1. 257-byte overflow (corrupts OAM[0]) OR
2. No duplication (test fails)

## Hardware Specification (From nesdev.org)

### OAM DMA Base Behavior
- **Cycles:** 513 (even start) or 514 (odd start)
- **Structure:** 1 halt + [optional alignment] + 256 GET/PUT pairs
- **Transfer:** 256 bytes from $XX00-$XXFF → OAM

### DMC/OAM Interaction (From web search)
- DMC has absolute priority
- OAM pauses when DMC active
- **Key quote:** "DMC read occurs where sprite read would otherwise occur"
- Takes 2 cycles in most cases (1 DMC get + 1 OAM realignment)

### User-Stated Behavior (NEED TO VERIFY SOURCE)
```
- DMC DMA has absolute priority over OAM DMA
- When DMC interrupts OAM, OAM pauses mid-transfer
- If interrupted during READ cycle, byte is read TWICE on resume
- OAM cycle counter FREEZES during pause
```

**CRITICAL QUESTION:** What does "byte is read TWICE" mean exactly?
- Does it mean the same memory address is read again?
- Does it mean the byte appears in two OAM slots?
- How do we maintain exactly 256 bytes transferred?

## Current Implementation Status

### What Works
- ✅ Ledger captures interrupted state
- ✅ Edge-triggered pause logic
- ✅ Resume phase transitions

### What's Broken
- ❌ Byte duplication mechanism unclear
- ❌ Counter advancement logic inconsistent
- ❌ 257-byte overflow OR no duplication

### Current Bookkeeping
```zig
.duplication_write => {
    ppu_oam_addr.* +%= 1;      // OAM slot advances
    dma.current_offset +%= 1;  // Source offset advances (skips byte)
    // cycle does NOT advance (free operation)
    dma.phase = .resuming_normal;
}
```

**Problem:** This skips the source byte, preventing actual duplication.

## Test Expectations

### Test 1: "Byte duplication: Interrupted during read cycle"
- Fills RAM with unique pattern `(i * 3) % 256`
- Expects to find SAME value in consecutive OAM slots
- **Verifies:** `state.ppu.oam[i] == state.ppu.oam[i + 1]` for some i

### Test 2: "DMC interrupts OAM at byte 0"
- Expects OAM[0] == 0x00 (not corrupted)
- **Verifies:** No overflow from 257 bytes

**These requirements seem contradictory!**

## Action Items

1. **DELEGATE TO AGENTS:**
   - architect-reviewer: Review clean architecture implementation
   - debugger: Analyze exact test failure modes
   - search-specialist: Find authoritative hardware spec for byte duplication

2. **REQUIRED INFORMATION:**
   - Exact hardware cycle-by-cycle behavior when DMC interrupts during OAM read
   - How byte duplication occurs while maintaining 256 total transfers
   - Official nesdev or hardware test ROM documentation

3. **BLOCKED UNTIL:**
   - Clear understanding of hardware behavior
   - Development plan approved
   - Test output saved and analyzed

## Notes

**DO NOT PROCEED** with implementation until hardware behavior is fully understood and documented.

**User Context:** Under extreme time pressure (eviction court 2 weeks). Cannot afford wasted time on unfocused work.
