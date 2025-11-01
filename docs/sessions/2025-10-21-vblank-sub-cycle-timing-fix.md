# VBlank Sub-Cycle Timing Fix - Implementation Session

**Date:** 2025-10-21
**Issue:** AccuracyCoin VBlank Beginning test fails due to incorrect CPU/PPU sub-cycle execution order
**Baseline:** 1024/1041 tests passing (98.3%)
**Target:** 1025/1041 tests passing (+1, no regressions)

## Problem Statement

When CPU reads $2002 (PPUSTATUS) at the EXACT same PPU cycle that VBlank is set (scanline 241, dot 1):
- **Hardware Behavior:** CPU reads 0 (CPU executes BEFORE PPU flag set within the cycle)
- **Current Emulator:** CPU reads 1 (PPU executes BEFORE CPU - WRONG ORDER)

### Hardware Timing (per nesdev.org)

```
PPU Cycle N (scanline 241, dot 1):
├─ Phase 0: CPU Read Operations (if CPU is active this cycle)
├─ Phase 1: CPU Write Operations (if CPU is active this cycle)
├─ Phase 2: PPU Event (VBlank flag SET)
└─ Phase 3: End of cycle
```

### Current Emulator Order

```zig
tick() {
    1. nextTimingStep() - advance clock
    2. stepPpuCycle() - PPU executes
    3. applyPpuCycleResult() - VBlank flag updated
    4. stepApuCycle() - APU executes (if cpu_tick)
    5. stepCpuCycle() - CPU executes (if cpu_tick)
}
```

**Problem:** By step 5, VBlank flag already updated at step 3.

## Implementation Plan

### Phase 1: Swap CPU/PPU Execution Order

**Goal:** Execute CPU memory operations BEFORE PPU flag updates are applied

**Changes:**
1. Move CPU/APU execution before applyPpuCycleResult()
2. Keep PPU tick first (for rendering), but delay flag updates
3. Update VBlankLedger.isFlagVisible() to handle same-cycle reads

**Critical Constraints:**
- PPU must still tick every cycle for rendering
- APU must tick before CPU (for IRQ state)
- CPU:PPU ratio remains 1:3 (unchanged)
- No changes to instruction timing or microsteps

### Phase 2: Fix Flag Visibility Logic

**Goal:** Correct `isFlagVisible()` for same-cycle reads

**Changes:**
- Use `>` instead of `>=` for read_cycle comparison
- If read_cycle == set_cycle, CPU read before set, flag still visible

### Phase 3: Edge Case Testing

**Goal:** Verify all race condition scenarios

**Test Cases:**
- Read at dot 0 (1 before set)
- Read at dot 1 (same cycle as set)
- Read at dot 2-3 (1-2 after set)
- Multiple reads same cycle
- Read-set-read pattern

## Implementation Log

### Change 1: Reorder tick() Execution

**File:** `src/emulation/State.zig`
**Function:** `tick()` (lines 593-652)

**What Changed:**

1. **Split PPU event application into two phases:**
   - `applyPpuEventsPreCpu()` - Executes BEFORE CPU (A12 rising, frame state)
   - `applyPpuEventsPostCpu()` - Executes AFTER CPU (VBlank flag updates)

2. **New execution order:**
   ```
   tick() {
       1. stepPpuCycle() - PPU rendering
       2. applyPpuEventsPreCpu() - A12 rising for mapper IRQ
       3. APU tick - APU IRQ state
       4. CPU tick - Memory operations including $2002 reads
       5. applyPpuEventsPostCpu() - VBlank flag updates AFTER CPU
   }
   ```

**Why This Fixes The Bug:**

When CPU reads $2002 at scanline 241 dot 1 (same cycle VBlank sets):
- **Before:** VBlank set at step 3 → CPU reads at step 5 → sees flag=1 ✗
- **After:** CPU reads at step 4 → VBlank set at step 5 → sees flag=0 ✓

**Hardware Reference:** nesdev.org "PPU frame timing" - CPU operations execute before PPU flag updates within a cycle.

**Lines Changed:**
- 618-620: Call `applyPpuEventsPreCpu()` instead of `applyPpuCycleResult()`
- 647-651: Call `applyPpuEventsPostCpu()` after CPU execution
- 654-695: Split `applyPpuCycleResult()` into two functions with detailed documentation

